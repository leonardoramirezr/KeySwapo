// Checks KeySwapo's key code assumptions against Apple's real keyboard layouts: with the Latin
// American layout, the key names used by the default configuration must type the expected
// characters on both ANSI and ISO keyboards. Run with `make test` (macOS only).
import Foundation

struct Keyboard {
    let name: String
    let type: UInt32
    let iso: Bool
}

var failures = 0

func expectTyped(_ name: String, _ flags: EventFlags = [], on keyboard: Keyboard, _ expected: String) {
    let keyCode = KeyCodes.normalize(KeyCodes.code(for: name)!, iso: keyboard.iso)
    let actual = KeyboardLayout.character(keyCode: keyCode, flags: flags, keyboardType: keyboard.type)
    let label = (flags.contains(.shift) ? "shift + " : "") + name
    if actual == expected {
        print("  ✓ \(label) → \(expected)")
    } else {
        failures += 1
        print("  ✗ \(label): expected \(expected), got \(actual ?? "nothing")")
    }
}

let layoutID = "com.apple.keylayout.LatinAmerican"
if !KeyboardLayout.useLayout(id: layoutID) {
    print("✗ \(layoutID) is not installed. Installed layouts:")
    KeyboardLayout.installedLayoutIDs.forEach { print("  \($0)") }
    exit(1)
}

let keyboardTypes = (0...255).map { UInt32($0) }
let ansiType = keyboardTypes.first { KeyboardLayout.physicalLayoutName(keyboardType: $0) == "ANSI" }
let isoType = keyboardTypes.first { KeyboardLayout.isISO(keyboardType: $0) }
if ansiType == nil || isoType == nil {
    print("✗ Could not find ANSI and ISO keyboard types")
    exit(1)
}
let ansi = Keyboard(name: "ANSI", type: ansiType!, iso: false)
let iso = Keyboard(name: "ISO", type: isoType!, iso: true)

let shift: EventFlags = [.shift, .leftShift]
for keyboard in [ansi, iso] {
    print("• \(layoutID), \(keyboard.name) keyboard (type \(keyboard.type))")
    expectTyped("grave_accent_and_tilde", on: keyboard, "|")
    expectTyped("grave_accent_and_tilde", shift, on: keyboard, "°")
    expectTyped("slash", on: keyboard, "-")
    expectTyped("slash", shift, on: keyboard, "_")
    expectTyped("hyphen", on: keyboard, "'")
    expectTyped("hyphen", shift, on: keyboard, "?")
}
print("• \(layoutID), key next to the left shift (ISO only)")
expectTyped("non_us_backslash", on: iso, "<")
expectTyped("non_us_backslash", shift, on: iso, ">")

print(failures == 0 ? "\nLayout checks passed" : "\n\(failures) layout checks failed")
exit(failures == 0 ? 0 : 1)
