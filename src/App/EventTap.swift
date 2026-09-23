import CoreGraphics
import Foundation

/// What the event tap did with one key event, for the key tester.
struct KeyEventReport: Sendable {
    var keyCode: UInt16
    var flags: EventFlags
    var isKeyDown: Bool
    var isRepeat: Bool
    var isISO: Bool
    var keyboardType: UInt32
    var action: RemapAction
    var ruleDescription: String?
}

/// Intercepts key presses system-wide with a `CGEventTap` and rewrites them with a `Remapper`.
///
/// The tap runs on the main run loop, so every method must be called on the main thread.
/// Creating it requires the Accessibility permission.
final class EventTap {
    let remapper = Remapper()
    /// Receives every processed key event while `isReporting` is true.
    var onReport: (@Sendable (KeyEventReport) -> Void)?
    var isReporting = false

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isoByKeyboardType: [UInt32: Bool] = [:]

    /// Marks the events KeySwapo posts itself, so they are never remapped again.
    private static let syntheticEventMarker: Int64 = 0x4B53_5750 // "KSWP"

    deinit {
        stop()
    }

    var isRunning: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// Installs the tap. Returns false if macOS refused, usually for lack of permission.
    @discardableResult
    func start() -> Bool {
        if isRunning {
            return true
        }
        stop()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return tap.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        runLoopSource = source
        return true
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        port = nil
        runLoopSource = nil
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown, .keyUp:
            break
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches the tap off if a callback takes too long; switch it back on.
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyboardType = UInt32(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeyboardType))
        let input = KeyEvent(
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: EventFlags(rawValue: event.flags.rawValue),
            isKeyDown: type == .keyDown,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            isISO: isISO(keyboardType)
        )
        let action = remapper.process(input)

        if isReporting, let onReport {
            onReport(KeyEventReport(
                keyCode: input.keyCode,
                flags: input.flags,
                isKeyDown: input.isKeyDown,
                isRepeat: input.isRepeat,
                isISO: input.isISO,
                keyboardType: keyboardType,
                action: action,
                ruleDescription: remapper.lastManipulator?.ruleDescription
            ))
        }

        switch action {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .drop:
            return nil
        case let .replace(taps, key):
            for stroke in taps {
                post(stroke, keyDown: true, keyboardType: keyboardType, proxy: proxy)
                post(stroke, keyDown: false, keyboardType: keyboardType, proxy: proxy)
            }
            // Rewriting the event in place keeps its timestamp, keyboard type and source.
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(key.keyCode))
            event.flags = CGEventFlags(rawValue: key.flags.rawValue)
            setText(of: event, to: key, keyboardType: keyboardType)
            return Unmanaged.passUnretained(event)
        }
    }

    /// Sends an extra key event right before the one being processed.
    private func post(_ stroke: KeyStroke, keyDown: Bool, keyboardType: UInt32, proxy: CGEventTapProxy) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: keyDown) else { return }
        event.flags = CGEventFlags(rawValue: stroke.flags.rawValue)
        event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(keyboardType))
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        setText(of: event, to: stroke, keyboardType: keyboardType)
        event.tapPostEvent(proxy)
    }

    /// Cocoa text input translates the key code and flags with the current layout, but some apps
    /// read the text stored in the event instead, so store the new key's text there too. Keys
    /// that don't type plain text (shortcuts, dead keys, arrows…) keep the system's handling.
    private func setText(of event: CGEvent, to stroke: KeyStroke, keyboardType: UInt32) {
        guard let text = KeyboardLayout.typedText(keyCode: stroke.keyCode, flags: stroke.flags, keyboardType: keyboardType) else {
            return
        }
        let characters = Array(text.utf16)
        event.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
    }

    private func isISO(_ keyboardType: UInt32) -> Bool {
        if let cached = isoByKeyboardType[keyboardType] {
            return cached
        }
        let iso = KeyboardLayout.isISO(keyboardType: keyboardType)
        isoByKeyboardType[keyboardType] = iso
        return iso
    }
}
