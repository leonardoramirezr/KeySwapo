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

    /// Localized name of the current input source, such as "Latinoamericano".
    static var currentLayoutName: String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    /// For example "Distribución: Latinoamericano · teclado ISO".
    static var summary: String {
        let name = currentLayoutName ?? "desconocida"
        return "Distribución: \(name) · teclado \(physicalLayoutName(keyboardType: Context.current.keyboardType))"
    }

    /// The printable text typed by a virtual key code with some flags in the current layout.
    /// Nil for keys that don't type text (return, arrows…) and for command/control shortcuts.
    static func character(keyCode: UInt16, flags: EventFlags, keyboardType: UInt32) -> String? {
        guard flags.isDisjoint(with: [.command, .control]),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
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
            OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return displayable(String(utf16CodeUnits: characters, count: length))
    }

    /// Readable form of typed text: "␣" for a space, nil for control characters and the
    /// private-use characters macOS uses for function keys.
    static func displayable(_ text: String) -> String? {
        if text == " " {
            return "␣"
        }
        let printable = text.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
        }
        return printable ? text : nil
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
