// End-to-end check meant for CI (`make e2e-test`). It selects the Latin American layout, starts
// KeySwapo's event tap with the default configuration, simulates key presses as if they came
// from ANSI and ISO keyboards, and checks what a text field receives. It changes the keyboard
// layout and sends keystrokes to the session, so don't run it on your own Mac.
import AppKit
import Carbon

setbuf(stdout, nil)

/// Key events as seen after KeySwapo's tap, by a listen-only tap placed after it.
final class Recorder {
    struct Entry {
        let keyCode: Int64
        let flags: UInt64
        let text: String
    }

    private(set) var keyDowns: [Entry] = []
    private var port: CFMachPort?

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo, type == .keyDown {
                    Unmanaged<Recorder>.fromOpaque(userInfo).takeUnretainedValue().record(event)
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

    private func record(_ event: CGEvent) {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let maxLength = characters.count
        event.keyboardGetUnicodeString(maxStringLength: maxLength, actualStringLength: &length, unicodeString: &characters)
        keyDowns.append(Entry(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags.rawValue,
            text: String(utf16CodeUnits: characters, count: length)
        ))
    }
}

struct Press {
    let keyCode: UInt16
    let shift: Bool
    let keyboardType: UInt32
    let label: String
}

@MainActor
enum EndToEnd {
    static let layoutID = "com.apple.keylayout.LatinAmerican"
    static let tap = EventTap()
    static let recorder = Recorder()
    static var window: NSWindow?
    static var field: NSTextField?
    static var originalLayout: TISInputSource?

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
            tap.remapper.setRules(try ConfigParser.parse(DefaultConfig.json).rules)
        } catch {
            finish("default configuration: \(error)", success: false)
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
        let presses = [
            Press(keyCode: grave, shift: false, keyboardType: ansi, label: "ANSI |"),
            Press(keyCode: grave, shift: true, keyboardType: ansi, label: "ANSI shift + |"),
            Press(keyCode: slash, shift: false, keyboardType: ansi, label: "ANSI -"),
            Press(keyCode: slash, shift: true, keyboardType: ansi, label: "ANSI shift + -"),
            // On ISO keyboards macOS reports the key left of 1 as kVK_ISO_Section.
            Press(keyCode: KeyCodes.isoSection, shift: false, keyboardType: iso, label: "ISO |"),
            Press(keyCode: KeyCodes.isoSection, shift: true, keyboardType: iso, label: "ISO shift + |"),
            Press(keyCode: slash, shift: false, keyboardType: iso, label: "ISO -"),
            Press(keyCode: slash, shift: true, keyboardType: iso, label: "ISO shift + -"),
        ]

        later(0.5) {
            app.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            _ = window.makeFirstResponder(field)
        }
        for (index, press) in presses.enumerated() {
            later(1.5 + Double(index) * 0.3) {
                post(press)
            }
        }
        later(1.5 + Double(presses.count) * 0.3 + 1.5) {
            check(presses)
        }
        later(30) {
            finish("timed out", success: false)
        }
        app.run()
    }

    static func post(_ press: Press) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.keyboardType = press.keyboardType
        var flags = EventFlags(rawValue: 0x100) // non-coalesced, as on real key events
        if press.shift {
            flags.formUnion([.shift, .leftShift])
        }
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: press.keyCode, keyDown: keyDown) else { continue }
            event.flags = CGEventFlags(rawValue: flags.rawValue)
            event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(press.keyboardType))
            event.post(tap: .cghidEventTap)
        }
    }

    static func check(_ presses: [Press]) {
        let expected = "_°-|_°-|"
        let typed = field?.currentEditor()?.string ?? field?.stringValue ?? ""
        print("Key downs after KeySwapo's tap:")
        for (index, entry) in recorder.keyDowns.enumerated() {
            let label = index < presses.count ? presses[index].label : "?"
            print("  \(label): key code \(entry.keyCode), flags 0x\(String(entry.flags, radix: 16)), text \"\(entry.text)\"")
        }
        print("Window is key: \(window?.isKeyWindow ?? false), app is active: \(NSApp.isActive)")
        print("Text field: \"\(typed)\" (expected \"\(expected)\")")

        let texts = recorder.keyDowns.map(\.text).joined()
        var problems: [String] = []
        if recorder.keyDowns.count != presses.count {
            problems.append("recorded \(recorder.keyDowns.count) key downs instead of \(presses.count)")
        } else if texts != expected {
            problems.append("event texts \"\(texts)\" instead of \"\(expected)\"")
        }
        if typed != expected {
            problems.append("text field got \"\(typed)\"")
        }
        finish(problems.joined(separator: "; "), success: problems.isEmpty)
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
