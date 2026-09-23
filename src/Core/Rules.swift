/// A described group of manipulators, like a Karabiner-Elements complex modification rule.
struct Rule: Equatable {
    var description: String
    var manipulators: [Manipulator]
}

/// One key remapping (a Karabiner "basic" manipulator).
struct Manipulator: Equatable {
    var from: FromEvent
    var to: [ToEvent]
    /// Description of the rule this manipulator belongs to.
    var ruleDescription = ""

    var toSummary: String {
        to.isEmpty ? "nada (tecla desactivada)" : to.map(\.summary).joined(separator: ", luego ")
    }
}

/// The key press a manipulator reacts to.
struct FromEvent: Equatable {
    /// Virtual key code in Karabiner's (ANSI) numbering; see `KeyCodes.normalize(_:iso:)`.
    var keyCode: UInt16
    /// Modifiers that must be held. They are released in the output unless `to` adds them back.
    var mandatory: [ModifierPattern] = []
    /// Modifiers that may also be held; they are kept in the output. Anything else held means
    /// the manipulator doesn't apply, so with both lists empty it only applies to the bare key.
    var optional: [ModifierPattern] = []

    /// The modifiers taken by `mandatory` if `pressed` satisfies this event, otherwise nil.
    func match(_ pressed: Set<Modifier>) -> Set<Modifier>? {
        var consumed = Set<Modifier>()
        for pattern in mandatory {
            let held = pressed.filter { pattern.matches($0) }
            if held.isEmpty {
                return nil
            }
            consumed.formUnion(held)
        }
        if optional.contains(.any) {
            return consumed
        }
        for modifier in pressed.subtracting(consumed) where !optional.contains(where: { $0.matches(modifier) }) {
            return nil
        }
        return consumed
    }

    var keyName: String { KeyCodes.name(for: keyCode) ?? "tecla \(keyCode)" }

    /// For example "shift + slash".
    var summary: String { (mandatory.map(\.name) + [keyName]).joined(separator: " + ") }

    /// When the manipulator applies, in words.
    var conditionSummary: String {
        var text = mandatory.isEmpty ? "Sin modificadores" : "Con " + mandatory.map(\.name).joined(separator: " + ")
        if optional.contains(.any) {
            text += "; se permite cualquier otro modificador"
        } else if optional.isEmpty {
            text += mandatory.isEmpty ? "; con cualquier modificador la tecla no cambia" : " y ningún otro modificador"
        } else {
            text += "; se permite además " + optional.map(\.name).joined(separator: ", ")
        }
        return text
    }
}

/// A key press a manipulator sends.
struct ToEvent: Equatable {
    /// Virtual key code in Karabiner's (ANSI) numbering; see `KeyCodes.normalize(_:iso:)`.
    var keyCode: UInt16
    var modifiers: [Modifier] = []
    /// Whether holding the original key auto-repeats this one.
    var repeats = true

    var keyName: String { KeyCodes.name(for: keyCode) ?? "tecla \(keyCode)" }

    /// For example "shift + slash".
    var summary: String { (modifiers.map(\.displayName) + [keyName]).joined(separator: " + ") }
}
