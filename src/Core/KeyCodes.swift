/// Karabiner-Elements `key_code` names and their macOS virtual key codes (`kVK_*` in Carbon's
/// Events.h).
///
/// Karabiner names physical keys by their USB HID usage. On ISO keyboards macOS gives two of
/// those keys swapped virtual key codes: the key left of `1` arrives as `kVK_ISO_Section` and
/// the key right of the left shift as `kVK_ANSI_Grave`. `normalize(_:iso:)` applies that swap,
/// so the same JSON names the same physical key on ANSI and ISO keyboards.
enum KeyCodes {
    static let isoSection: UInt16 = 0x0A
    static let ansiGrave: UInt16 = 0x32

    /// Canonical names. When several names share a code, the first one is used for display.
    private static let table: [(name: String, code: UInt16)] = [
        ("a", 0x00), ("s", 0x01), ("d", 0x02), ("f", 0x03), ("h", 0x04), ("g", 0x05), ("z", 0x06),
        ("x", 0x07), ("c", 0x08), ("v", 0x09), ("non_us_backslash", 0x0A), ("b", 0x0B), ("q", 0x0C),
        ("w", 0x0D), ("e", 0x0E), ("r", 0x0F), ("y", 0x10), ("t", 0x11), ("1", 0x12), ("2", 0x13),
        ("3", 0x14), ("4", 0x15), ("6", 0x16), ("5", 0x17), ("equal_sign", 0x18), ("9", 0x19),
        ("7", 0x1A), ("hyphen", 0x1B), ("8", 0x1C), ("0", 0x1D), ("close_bracket", 0x1E),
        ("o", 0x1F), ("u", 0x20), ("open_bracket", 0x21), ("i", 0x22), ("p", 0x23),
        ("return_or_enter", 0x24), ("l", 0x25), ("j", 0x26), ("quote", 0x27), ("k", 0x28),
        ("semicolon", 0x29), ("backslash", 0x2A), ("comma", 0x2B), ("slash", 0x2C), ("n", 0x2D),
        ("m", 0x2E), ("period", 0x2F), ("tab", 0x30), ("spacebar", 0x31),
        ("grave_accent_and_tilde", 0x32), ("delete_or_backspace", 0x33), ("escape", 0x35),
        ("right_command", 0x36), ("left_command", 0x37), ("left_shift", 0x38), ("caps_lock", 0x39),
        ("left_option", 0x3A), ("left_control", 0x3B), ("right_shift", 0x3C), ("right_option", 0x3D),
        ("right_control", 0x3E), ("fn", 0x3F), ("f17", 0x40), ("keypad_period", 0x41),
        ("keypad_asterisk", 0x43), ("keypad_plus", 0x45), ("keypad_num_lock", 0x47),
        ("volume_increment", 0x48), ("volume_decrement", 0x49), ("mute", 0x4A),
        ("keypad_slash", 0x4B), ("keypad_enter", 0x4C), ("keypad_hyphen", 0x4E), ("f18", 0x4F),
        ("f19", 0x50), ("keypad_equal_sign", 0x51), ("keypad_0", 0x52), ("keypad_1", 0x53),
        ("keypad_2", 0x54), ("keypad_3", 0x55), ("keypad_4", 0x56), ("keypad_5", 0x57),
        ("keypad_6", 0x58), ("keypad_7", 0x59), ("f20", 0x5A), ("keypad_8", 0x5B),
        ("keypad_9", 0x5C), ("international3", 0x5D), ("international1", 0x5E),
        ("keypad_comma", 0x5F), ("f5", 0x60), ("f6", 0x61), ("f7", 0x62), ("f3", 0x63),
        ("f8", 0x64), ("f9", 0x65), ("lang2", 0x66), ("f11", 0x67), ("lang1", 0x68), ("f13", 0x69),
        ("f16", 0x6A), ("f14", 0x6B), ("f10", 0x6D), ("application", 0x6E), ("f12", 0x6F),
        ("f15", 0x71), ("help", 0x72), ("home", 0x73), ("page_up", 0x74), ("delete_forward", 0x75),
        ("f4", 0x76), ("end", 0x77), ("f2", 0x78), ("page_down", 0x79), ("f1", 0x7A),
        ("left_arrow", 0x7B), ("right_arrow", 0x7C), ("down_arrow", 0x7D), ("up_arrow", 0x7E),
    ]

    /// Other names Karabiner-Elements accepts for the same keys.
    private static let aliases: [String: String] = [
        "non_us_pound": "backslash",
        "insert": "help",
        "print_screen": "f13",
        "scroll_lock": "f14",
        "pause": "f15",
        "japanese_kana": "lang1",
        "japanese_eisuu": "lang2",
        "left_alt": "left_option",
        "right_alt": "right_option",
        "left_gui": "left_command",
        "right_gui": "right_command",
    ]

    /// Names people often write instead of Karabiner's, for error suggestions.
    private static let hints: [String: String] = [
        "space": "spacebar",
        "enter": "return_or_enter",
        "return": "return_or_enter",
        "backspace": "delete_or_backspace",
        "delete": "delete_or_backspace",
        "esc": "escape",
        "minus": "hyphen",
        "dash": "hyphen",
        "equal": "equal_sign",
        "equals": "equal_sign",
        "grave": "grave_accent_and_tilde",
        "grave_accent": "grave_accent_and_tilde",
        "backtick": "grave_accent_and_tilde",
        "tilde": "grave_accent_and_tilde",
        "section": "non_us_backslash",
        "left": "left_arrow",
        "right": "right_arrow",
        "up": "up_arrow",
        "down": "down_arrow",
        "pageup": "page_up",
        "pagedown": "page_down",
        "forward_delete": "delete_forward",
    ]

    private static let byName: [String: UInt16] = {
        var map = [String: UInt16]()
        for entry in table {
            map[entry.name] = entry.code
        }
        for (alias, target) in aliases {
            map[alias] = map[target]
        }
        return map
    }()

    private static let byCode: [UInt16: String] = {
        var map = [UInt16: String]()
        for entry in table where map[entry.code] == nil {
            map[entry.code] = entry.name
        }
        return map
    }()

    /// Every canonical name, in key code order.
    static var allNames: [String] { table.map { $0.name } }

    static func code(for name: String) -> UInt16? {
        byName[name]
    }

    static func name(for code: UInt16) -> String? {
        byCode[code]
    }

    static let modifierKeyCodes: Set<UInt16> = [0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]

    /// Modifier keys reach the event tap as "flags changed" events, not key presses.
    static func isModifierKey(_ code: UInt16) -> Bool {
        modifierKeyCodes.contains(code)
    }

    /// Converts between the key code macOS reports and Karabiner's physical-key numbering.
    /// The ISO swap is its own inverse, so this works in both directions.
    static func normalize(_ code: UInt16, iso: Bool) -> UInt16 {
        guard iso else { return code }
        switch code {
        case isoSection: return ansiGrave
        case ansiGrave: return isoSection
        default: return code
        }
    }

    private static let functionKeyCodes: Set<UInt16> = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, // F1-F10
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A, // F11-F20
        0x72, 0x73, 0x74, 0x75, 0x77, 0x79, // help, home, page up, forward delete, end, page down
    ]

    private static let keypadKeyCodes: Set<UInt16> = [
        0x41, 0x43, 0x45, 0x47, 0x4B, 0x4C, 0x4E, 0x51, 0x52, 0x53,
        0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C, 0x5F,
    ]

    /// Flags macOS always sets on events of this key: fn for function and navigation keys,
    /// numeric pad for the keypad, and both for the arrows.
    static func inherentFlags(for code: UInt16) -> EventFlags {
        if (0x7B...0x7E).contains(code) {
            return [.numericPad, .secondaryFn]
        }
        if functionKeyCodes.contains(code) {
            return .secondaryFn
        }
        if keypadKeyCodes.contains(code) {
            return .numericPad
        }
        return []
    }

    /// The name the user probably meant when `name` is not a valid key_code.
    static func suggestion(for name: String) -> String? {
        let lowered = name.lowercased()
        if byName[lowered] != nil {
            return lowered
        }
        if let hint = hints[lowered] {
            return hint
        }
        var best: (name: String, distance: Int)?
        for candidate in byName.keys {
            let distance = editDistance(lowered, candidate)
            guard distance <= 2 else { continue }
            if let current = best, current.distance < distance || (current.distance == distance && current.name < candidate) {
                continue
            }
            best = (candidate, distance)
        }
        return best?.name
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        return previous[b.count]
    }
}
