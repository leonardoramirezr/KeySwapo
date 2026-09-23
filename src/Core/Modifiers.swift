/// Modifier bits of a macOS keyboard event. Bit-compatible with `CGEventFlags`, but defined
/// here so the remapping logic has no platform dependencies and can be tested anywhere.
struct EventFlags: OptionSet, Hashable, CustomStringConvertible {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    // Device-independent bits (CGEventFlags.mask*).
    static let capsLock = EventFlags(rawValue: 0x0001_0000)
    static let shift = EventFlags(rawValue: 0x0002_0000)
    static let control = EventFlags(rawValue: 0x0004_0000)
    static let option = EventFlags(rawValue: 0x0008_0000)
    static let command = EventFlags(rawValue: 0x0010_0000)
    static let numericPad = EventFlags(rawValue: 0x0020_0000)
    static let help = EventFlags(rawValue: 0x0040_0000)
    static let secondaryFn = EventFlags(rawValue: 0x0080_0000)

    // Device-dependent bits that tell left and right keys apart (NX_DEVICE*KEYMASK in IOLLEvent.h).
    static let leftControl = EventFlags(rawValue: 0x0000_0001)
    static let leftShift = EventFlags(rawValue: 0x0000_0002)
    static let rightShift = EventFlags(rawValue: 0x0000_0004)
    static let leftCommand = EventFlags(rawValue: 0x0000_0008)
    static let rightCommand = EventFlags(rawValue: 0x0000_0010)
    static let leftOption = EventFlags(rawValue: 0x0000_0020)
    static let rightOption = EventFlags(rawValue: 0x0000_0040)
    static let rightControl = EventFlags(rawValue: 0x0000_2000)

    /// Every bit that describes a modifier key or the caps lock state.
    static let modifierMask: EventFlags = [
        .capsLock, .shift, .control, .option, .command, .secondaryFn,
        .leftControl, .leftShift, .rightShift, .leftCommand, .rightCommand,
        .leftOption, .rightOption, .rightControl,
    ]

    var description: String { "0x" + String(rawValue, radix: 16) }

    /// These flags with every modifier bit replaced by `modifiers`, and the bits macOS always
    /// sets for `fromKey` (arrows, function and keypad keys) replaced by those of `toKey`.
    /// Other bits, such as "non-coalesced", are kept.
    func remapped(fromKey: UInt16, toKey: UInt16, modifiers: Set<Modifier>) -> EventFlags {
        var flags = subtracting(.modifierMask).subtracting(KeyCodes.inherentFlags(for: fromKey))
        for modifier in modifiers {
            flags.formUnion(modifier.flags)
        }
        return flags.union(KeyCodes.inherentFlags(for: toKey))
    }
}

/// Modifier keys grouped by what they do, regardless of side.
enum ModifierFamily: String, CaseIterable {
    case shift, control, option, command, fn
    case capsLock = "caps_lock"

    /// The keys of this family. The first one is used when a rule only says "shift".
    var keys: [Modifier] {
        switch self {
        case .shift: return [.leftShift, .rightShift]
        case .control: return [.leftControl, .rightControl]
        case .option: return [.leftOption, .rightOption]
        case .command: return [.leftCommand, .rightCommand]
        case .fn: return [.fn]
        case .capsLock: return [.capsLock]
        }
    }

    /// The device-independent bit set while any key of the family is held.
    var flag: EventFlags {
        switch self {
        case .shift: return .shift
        case .control: return .control
        case .option: return .option
        case .command: return .command
        case .fn: return .secondaryFn
        case .capsLock: return .capsLock
        }
    }
}

/// A modifier key (or the caps lock state), named as in Karabiner-Elements.
enum Modifier: String, CaseIterable, Comparable {
    case leftControl = "left_control"
    case rightControl = "right_control"
    case leftOption = "left_option"
    case rightOption = "right_option"
    case leftShift = "left_shift"
    case rightShift = "right_shift"
    case leftCommand = "left_command"
    case rightCommand = "right_command"
    case fn
    case capsLock = "caps_lock"

    var family: ModifierFamily {
        switch self {
        case .leftControl, .rightControl: return .control
        case .leftOption, .rightOption: return .option
        case .leftShift, .rightShift: return .shift
        case .leftCommand, .rightCommand: return .command
        case .fn: return .fn
        case .capsLock: return .capsLock
        }
    }

    /// The bit that identifies this exact key.
    var deviceFlag: EventFlags {
        switch self {
        case .leftControl: return .leftControl
        case .rightControl: return .rightControl
        case .leftOption: return .leftOption
        case .rightOption: return .rightOption
        case .leftShift: return .leftShift
        case .rightShift: return .rightShift
        case .leftCommand: return .leftCommand
        case .rightCommand: return .rightCommand
        case .fn: return .secondaryFn
        case .capsLock: return .capsLock
        }
    }

    /// Every bit an event carries while this modifier is held.
    var flags: EventFlags { family.flag.union(deviceFlag) }

    /// Name for summaries. Karabiner presses the left key for a plain "shift", so those print
    /// as the family name.
    var displayName: String {
        switch self {
        case .leftControl: return "control"
        case .leftOption: return "option"
        case .leftShift: return "shift"
        case .leftCommand: return "command"
        default: return rawValue
        }
    }

    /// Accepts Karabiner's modifier key names, including the `alt` and `gui` aliases.
    init?(karabinerName name: String) {
        switch name {
        case "left_alt": self = .leftOption
        case "right_alt": self = .rightOption
        case "left_gui": self = .leftCommand
        case "right_gui": self = .rightCommand
        default: self.init(rawValue: name)
        }
    }

    /// The key to press for a name in `to.modifiers`. As in Karabiner, "shift" means left shift.
    init?(toName name: String) {
        if let family = ModifierFamily(rawValue: name) {
            self = family.keys[0]
        } else {
            self.init(karabinerName: name)
        }
    }

    /// Modifiers held (or locked, for caps lock) according to an event's flags. Arrow and
    /// function keys always carry the fn bit, so for them fn can't be detected and is left out.
    static func pressed(in flags: EventFlags, keyCode: UInt16) -> Set<Modifier> {
        var pressed = Set<Modifier>()
        for family in [ModifierFamily.shift, .control, .option, .command] {
            let keys = family.keys.filter { flags.contains($0.deviceFlag) }
            if !keys.isEmpty {
                pressed.formUnion(keys)
            } else if flags.contains(family.flag) {
                // Synthetic events often carry only the device-independent bit.
                pressed.insert(family.keys[0])
            }
        }
        if flags.contains(.secondaryFn) && !KeyCodes.inherentFlags(for: keyCode).contains(.secondaryFn) {
            pressed.insert(.fn)
        }
        if flags.contains(.capsLock) {
            pressed.insert(.capsLock)
        }
        return pressed
    }

    static func < (lhs: Modifier, rhs: Modifier) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// A modifier as written in `from.modifiers`: one key ("left_shift"), either key of a family
/// ("shift"), or "any".
enum ModifierPattern: Hashable {
    case key(Modifier)
    case family(ModifierFamily)
    case any

    static let validNames = [
        "shift", "control", "option", "command", "fn", "caps_lock",
        "left_shift", "right_shift", "left_control", "right_control",
        "left_option", "right_option", "left_command", "right_command",
        "left_alt", "right_alt", "left_gui", "right_gui", "any",
    ]

    init?(name: String) {
        if name == "any" {
            self = .any
        } else if let family = ModifierFamily(rawValue: name) {
            self = family.keys.count == 1 ? .key(family.keys[0]) : .family(family)
        } else if let modifier = Modifier(karabinerName: name) {
            self = .key(modifier)
        } else {
            return nil
        }
    }

    var name: String {
        switch self {
        case .key(let modifier): return modifier.rawValue
        case .family(let family): return family.rawValue
        case .any: return "any"
        }
    }

    func matches(_ modifier: Modifier) -> Bool {
        switch self {
        case .key(let key): return key == modifier
        case .family(let family): return modifier.family == family
        case .any: return true
        }
    }
}
