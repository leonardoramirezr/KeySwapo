// End-to-end check meant for CI (`make e2e-test`). It selects the Latin American layout, starts
// KeySwapo's event tap, simulates key presses as if they came from ANSI and ISO keyboards, and
// checks what reaches a text field. It changes the keyboard layout and sends keystrokes to the
// session, so don't run it on your own Mac.
import AppKit
import ApplicationServices
import Carbon

setbuf(stdout, nil)

/// Key presses as seen after KeySwapo's tap, by a listen-only tap placed after it.
final class Recorder {
    private(set) var keyDowns: [CGEvent] = []
    private var port: CFMachPort?

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo, type == .keyDown, let copy = event.copy() {
                    Unmanaged<Recorder>.fromOpaque(userInfo).takeUnretainedValue().keyDowns.append(copy)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        return true
    }
}

struct Press {
    let label: String
    let keyCode: UInt16
    let flags: EventFlags
    let keyboardType: UInt32
    /// Text the event must carry after KeySwapo's tap.
    let expectedText: String
}

@MainActor
enum EndToEnd {
    static let layoutID = "com.apple.keylayout.LatinAmerican"
    static let tap = EventTap()
    static let recorder = Recorder()
    static var window: NSWindow?
    static var field: NSTextField?
    static var originalLayout: TISInputSource?

    static let arrowRule = """
    {"manipulators": [{"type": "basic",
        "from": {"key_code": "h", "modifiers": {"mandatory": ["control"], "optional": ["any"]}},
        "to": [{"key_code": "left_arrow"}]}]}
    """

    static func start() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        guard selectLayout(id: layoutID) else {
            finish("could not select \(layoutID)", success: false)
        }
        let keyboardTypes = (0...255).map { UInt32($0) }
        guard let ansi = keyboardTypes.first(where: { KeyboardLayout.physicalLayoutName(keyboardType: $0) == "ANSI" }),
              let iso = keyboardTypes.first(where: { KeyboardLayout.isISO(keyboardType: $0) }) else {
            finish("could not find ANSI and ISO keyboard types", success: false)
        }

        do {
            let rules = try ConfigParser.parse(DefaultConfig.json).rules + ConfigParser.parse(arrowRule).rules
            tap.remapper.setRules(rules)
        } catch {
            finish("configuration: \(error)", success: false)
        }
        guard tap.start() else {
            finish("could not create KeySwapo's event tap (is the Accessibility permission granted?)", success: false)
        }
        guard recorder.start() else {
            finish("could not create the recording tap", success: false)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 420, height: 90),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "KeySwapo end-to-end"
        let field = NSTextField(frame: NSRect(x: 20, y: 30, width: 380, height: 28))
        window.contentView?.addSubview(field)
        self.window = window
        self.field = field

        let grave = KeyCodes.code(for: "grave_accent_and_tilde")!
        let slash = KeyCodes.code(for: "slash")!
        let shift: EventFlags = [.shift, .leftShift]
        var presses: [Press] = []
        for (name, type, pipeKey) in [("ANSI", ansi, grave), ("ISO", iso, KeyCodes.isoSection)] {
            // On ISO keyboards macOS reports the key left of 1 as kVK_ISO_Section.
            presses += [
                Press(label: "\(name) |", keyCode: pipeKey, flags: [], keyboardType: type, expectedText: "_"),
                Press(label: "\(name) shift + |", keyCode: pipeKey, flags: shift, keyboardType: type, expectedText: "°"),
                Press(label: "\(name) -", keyCode: slash, flags: [], keyboardType: type, expectedText: "-"),
                Press(label: "\(name) shift + -", keyCode: slash, flags: shift, keyboardType: type, expectedText: "|"),
            ]
        }
        // A remapped key that doesn't type text: control + h must move left, not delete.
        presses += [
            Press(label: "a", keyCode: KeyCodes.code(for: "a")!, flags: [], keyboardType: ansi, expectedText: "a"),
            Press(label: "b", keyCode: KeyCodes.code(for: "b")!, flags: [], keyboardType: ansi, expectedText: "b"),
            Press(label: "control + h", keyCode: KeyCodes.code(for: "h")!, flags: [.control, .leftControl], keyboardType: ansi, expectedText: "\u{1C}"),
            Press(label: "c", keyCode: KeyCodes.code(for: "c")!, flags: [], keyboardType: ansi, expectedText: "c"),
        ]

        later(0.3) {
            activate(app)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            _ = window.makeFirstResponder(field)
        }
        for (index, press) in presses.enumerated() {
            later(1.5 + Double(index) * 0.25) {
                post(press)
            }
        }
        later(1.5 + Double(presses.count) * 0.25 + 1.5) {
            check(presses)
        }
        later(40) {
            finish("timed out", success: false)
        }
        app.run()
    }

    /// Brings this process to the front. `NSApp.activate()` alone is ignored for a background
    /// command line process, but setting the Accessibility "frontmost" attribute works.
    static func activate(_ app: NSApplication) {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let result = AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
        print("Activation through Accessibility: \(result == .success ? "ok" : "error \(result.rawValue)")")
    }

    /// Posts a press like the keyboard would: the event carries the text macOS would store for
    /// it, which KeySwapo has to replace when it rewrites the key.
    static func post(_ press: Press) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.keyboardType = press.keyboardType
        let flags = press.flags.union(EventFlags(rawValue: 0x100)) // non-coalesced, as on real key events
        let text = KeyboardLayout.eventText(keyCode: press.keyCode, flags: flags, keyboardType: press.keyboardType) ?? []
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: press.keyCode, keyDown: keyDown) else { continue }
            event.flags = CGEventFlags(rawValue: flags.rawValue)
            event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(press.keyboardType))
            event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
            event.post(tap: .cghidEventTap)
        }
    }

    static func check(_ presses: [Press]) {
        var problems: [String] = []

        print("Key presses after KeySwapo's tap:")
        let recorded = recorder.keyDowns
        for (index, event) in recorded.enumerated() {
            let label = index < presses.count ? presses[index].label : "?"
            let text = eventText(event)
            print("  \(label): key code \(event.getIntegerValueField(.keyboardEventKeycode)), flags 0x\(String(event.flags.rawValue, radix: 16)), text \(text.debugDescription)")
            if index < presses.count && text != presses[index].expectedText {
                problems.append("\(label) carries \(text.debugDescription) instead of \(presses[index].expectedText.debugDescription)")
            }
        }
        if recorded.count != presses.count {
            problems.append("recorded \(recorded.count) presses instead of \(presses.count)")
        }

        let expected = "_°-|_°-|acb"
        let isKey = window?.isKeyWindow ?? false
        print("Window is key: \(isKey), app is active: \(NSApp.isActive), frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")")
        var typed = fieldText()
        if !isKey {
            // The events went to another app; hand the rewritten events to the field directly,
            // which still exercises how AppKit reads them.
            print("Window never became key; replaying the rewritten events into the text field")
            if let editor = field?.currentEditor() as? NSTextView {
                for event in recorded {
                    if let nsEvent = NSEvent(cgEvent: event) {
                        editor.keyDown(with: nsEvent)
                    }
                }
            }
            typed = fieldText()
        }
        print("Text field: \(typed.debugDescription) (expected \(expected.debugDescription))")
        if typed != expected {
            problems.append("text field got \(typed.debugDescription)")
        }
        finish(problems.joined(separator: "; "), success: problems.isEmpty)
    }

    static func fieldText() -> String {
        field?.currentEditor()?.string ?? field?.stringValue ?? ""
    }

    static func eventText(_ event: CGEvent) -> String {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let maxLength = characters.count
        event.keyboardGetUnicodeString(maxStringLength: maxLength, actualStringLength: &length, unicodeString: &characters)
        return String(utf16CodeUnits: characters, count: length)
    }

    static func selectLayout(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue(),
              let sources = list as NSArray as? [TISInputSource],
              let source = sources.first else {
            return false
        }
        originalLayout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        _ = TISEnableInputSource(source)
        return TISSelectInputSource(source) == noErr
    }

    static func later(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated {
                action()
            }
        }
    }

    static func finish(_ message: String, success: Bool) -> Never {
        tap.stop()
        if let original = originalLayout {
            _ = TISSelectInputSource(original)
        }
        print(success ? "✓ End-to-end check passed" : "✗ End-to-end check failed: \(message)")
        exit(success ? 0 : 1)
    }
}

MainActor.assumeIsolated {
    EndToEnd.start()
}
