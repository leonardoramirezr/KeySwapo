/// A key press or release, as the event tap sees it.
struct KeyEvent: Equatable {
    /// Virtual key code as macOS reports it.
    var keyCode: UInt16
    var flags: EventFlags
    var isKeyDown: Bool
    var isRepeat = false
    /// Whether the event comes from an ISO keyboard; see `KeyCodes.normalize(_:iso:)`.
    var isISO = false
}

/// A key event to send: a virtual key code (as macOS expects it) and its flags.
struct KeyStroke: Equatable {
    var keyCode: UInt16
    var flags: EventFlags
}

enum RemapAction: Equatable {
    /// Deliver the event unchanged.
    case passThrough
    /// Swallow the event.
    case drop
    /// Press and release each of `taps` first, then deliver `key` in place of the event.
    case replace(taps: [KeyStroke], key: KeyStroke)
}

/// Applies manipulators to key events.
///
/// It remembers which manipulator took each held key, so the auto-repeats and the release are
/// translated like the press even if the modifiers or the rules change in between. Otherwise
/// releasing shift before `-` would send the release of the wrong key.
final class Remapper {
    /// When false, new key presses pass through; keys already held are still released properly.
    var isEnabled = true
    private(set) var manipulators: [Manipulator] = []
    /// The manipulator that handled the last processed event, if any.
    private(set) var lastManipulator: Manipulator?

    private var manipulatorsByKey: [UInt16: [Manipulator]] = [:]
    private var heldKeys: [UInt16: HeldKey] = [:]

    private struct HeldKey {
        let manipulator: Manipulator
        /// Modifiers taken by `from.modifiers.mandatory`; they are released in the output.
        let consumed: Set<Modifier>
        /// Karabiner key code of the physical key.
        let fromKey: UInt16
    }

    private enum Phase {
        case press, autoRepeat, release
    }

    func setRules(_ rules: [Rule]) {
        manipulators = rules.flatMap(\.manipulators)
        manipulatorsByKey = Dictionary(grouping: manipulators, by: { $0.from.keyCode })
    }

    func process(_ event: KeyEvent) -> RemapAction {
        let fromKey = KeyCodes.normalize(event.keyCode, iso: event.isISO)
        if event.isKeyDown && !event.isRepeat {
            heldKeys[event.keyCode] = nil
            guard isEnabled, let held = match(fromKey: fromKey, flags: event.flags) else {
                lastManipulator = nil
                return .passThrough
            }
            heldKeys[event.keyCode] = held
            lastManipulator = held.manipulator
            return action(for: held, event: event, phase: .press)
        }
        guard let held = heldKeys[event.keyCode] else {
            lastManipulator = nil
            return .passThrough
        }
        if !event.isKeyDown {
            heldKeys[event.keyCode] = nil
        }
        lastManipulator = held.manipulator
        return action(for: held, event: event, phase: event.isKeyDown ? .autoRepeat : .release)
    }

    /// The first manipulator for this key whose modifier conditions hold, like Karabiner.
    private func match(fromKey: UInt16, flags: EventFlags) -> HeldKey? {
        guard let candidates = manipulatorsByKey[fromKey] else { return nil }
        let pressed = Modifier.pressed(in: flags, keyCode: fromKey)
        for manipulator in candidates {
            if let consumed = manipulator.from.match(pressed) {
                return HeldKey(manipulator: manipulator, consumed: consumed, fromKey: fromKey)
            }
        }
        return nil
    }

    private func action(for held: HeldKey, event: KeyEvent, phase: Phase) -> RemapAction {
        let targets = held.manipulator.to
        guard let last = targets.last else { return .drop }
        if phase == .autoRepeat && !last.repeats {
            return .drop
        }
        let kept = Modifier.pressed(in: event.flags, keyCode: held.fromKey).subtracting(held.consumed)
        func stroke(_ target: ToEvent) -> KeyStroke {
            KeyStroke(
                keyCode: KeyCodes.normalize(target.keyCode, iso: event.isISO),
                flags: event.flags.remapped(fromKey: held.fromKey, toKey: target.keyCode, modifiers: kept.union(target.modifiers))
            )
        }
        let taps = phase == .press ? targets.dropLast().map(stroke) : []
        return .replace(taps: taps, key: stroke(last))
    }
}
