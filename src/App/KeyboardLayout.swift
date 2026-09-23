import Carbon
import Foundation

/// Keyboard layout information from the Text Input Sources API, used to show which character
/// a key produces (so rules can be displayed as `|` → `_`).
enum KeyboardLayout {
    /// The keyboard type needed to translate key codes, and whether it is an ISO keyboard.
    struct Context {
        var keyboardType: UInt32
        var isISO: Bool

        /// The keyboard that was used last.
        static var current: Context {
            let type = UInt32(LMGetKbdType())
            return Context(keyboardType: type, isISO: KeyboardLayout.isISO(keyboardType: type))
        }
    }

    static func isISO(keyboardType: UInt32) -> Bool {
        KBGetLayoutType(Int16(truncatingIfNeeded: keyboardType)) == PhysicalKeyboardLayoutType(kKeyboardISO)
    }

    static func physicalLayoutName(keyboardType: UInt32) -> String {
        switch KBGetLayoutType(Int16(truncatingIfNeeded: keyboardType)) {
        case PhysicalKeyboardLayoutType(kKeyboardISO): return "ISO"
        case PhysicalKeyboardLayoutType(kKeyboardJIS): return "JIS"
        case PhysicalKeyboardLayoutType(kKeyboardANSI): return "ANSI"
        default: return "desconocido"
        }
    }

    /// Layout to use instead of the current one (`--check --layout`, tests). Only set at startup.
    nonisolated(unsafe) private static var layoutOverride: TISInputSource?

    /// Uses the keyboard layout with this input source ID (for example
    /// "com.apple.keylayout.LatinAmerican") instead of the current one. False if not found.
    static func useLayout(id: String) -> Bool {
        guard let source = inputSources([kTISPropertyInputSourceID as String: id]).first else { return false }
        layoutOverride = source
        return true
    }

    /// Input source IDs of every installed keyboard layout.
    static var installedLayoutIDs: [String] {
        inputSources([kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String])
            .compactMap { string(TISGetInputSourceProperty($0, kTISPropertyInputSourceID)) }
            .sorted()
    }

    private static func inputSources(_ filter: [String: String]) -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(filter as CFDictionary, true)?.takeRetainedValue() else {
            return []
        }
        return list as NSArray as? [TISInputSource] ?? []
    }

    private static func layoutSource() -> TISInputSource? {
        layoutOverride ?? TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
    }

    private static func string(_ pointer: UnsafeMutableRawPointer?) -> String? {
        guard let pointer else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    /// Localized name of the current input source, such as "Latinoamericano".
    static var currentLayoutName: String? {
        guard let source = layoutSource() else { return nil }
        return string(TISGetInputSourceProperty(source, kTISPropertyLocalizedName))
    }

    /// For example "Distribución: Latinoamericano · teclado ISO".
    static var summary: String {
        let name = currentLayoutName ?? "desconocida"
        return "Distribución: \(name) · teclado \(physicalLayoutName(keyboardType: Context.current.keyboardType))"
    }

    /// The character a virtual key code types with some flags in the current layout, for display:
    /// "␣" for a space, and a dead key shows its accent. Nil for keys that don't type text
    /// (return, arrows…) and for command/control shortcuts.
    static func character(keyCode: UInt16, flags: EventFlags, keyboardType: UInt32) -> String? {
        guard flags.isDisjoint(with: [.command, .control]),
              let characters = translate(keyCode: keyCode, flags: flags, keyboardType: keyboardType, deadKeysAsText: true),
              !characters.isEmpty else {
            return nil
        }
        let text = String(utf16CodeUnits: characters, count: characters.count)
        guard isPrintable(text) else { return nil }
        return text == " " ? "␣" : text
    }

    /// The text macOS stores in the event of a real press of this key with these flags: control
    /// characters included, and empty for a dead key. macOS fills it in when the event is created
    /// and doesn't update it if the key code or flags change later. Nil without layout data.
    static func eventText(keyCode: UInt16, flags: EventFlags, keyboardType: UInt32) -> [UniChar]? {
        translate(keyCode: keyCode, flags: flags, keyboardType: keyboardType, deadKeysAsText: false)
    }

    private static func translate(keyCode: UInt16, flags: EventFlags, keyboardType: UInt32, deadKeysAsText: Bool) -> [UniChar]? {
        guard let source = layoutSource(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let maxLength = characters.count
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            carbonModifierState(flags),
            keyboardType,
            deadKeysAsText ? OptionBits(1 << kUCKeyTranslateNoDeadKeysBit) : 0,
            &deadKeyState,
            maxLength,
            &length,
            &characters
        )
        guard status == noErr else { return nil }
        return Array(characters.prefix(length))
    }

    /// False for control characters and for the private-use characters of function keys.
    private static func isPrintable(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }

    /// Modifier state in the format `UCKeyTranslate` expects: Carbon's `EventModifiers >> 8`.
    private static func carbonModifierState(_ flags: EventFlags) -> UInt32 {
        var state: UInt32 = 0
        if flags.contains(.command) { state |= 0x01 } // cmdKey >> 8
        if flags.contains(.shift) { state |= 0x02 } // shiftKey >> 8
        if flags.contains(.capsLock) { state |= 0x04 } // alphaLock >> 8
        if flags.contains(.option) { state |= 0x08 } // optionKey >> 8
        if flags.contains(.control) { state |= 0x10 } // controlKey >> 8
        return state
    }
}

enum SecureInput {
    /// True while some app has secure keyboard entry on (password fields, Terminal's "Secure
    /// Keyboard Entry"…). Event taps don't see key presses then.
    static var isEnabled: Bool {
        IsSecureEventInputEnabled()
    }
}
