// Tests for the platform-independent core (src/Core). Run with `make test`.
import Foundation

// MARK: - Minimal test harness

var checks = 0
var failures = 0

func expect(_ condition: Bool, _ message: @autoclosure () -> String = "", line: Int = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("    ✗ line \(line): \(message())")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("    ✗ line \(line): \(message)\n      expected: \(expected)\n      actual:   \(actual)")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    print("• \(name)")
    do {
        try body()
    } catch {
        failures += 1
        print("    ✗ unexpected error: \(error)")
    }
}

/// Issues of a configuration that must fail to parse.
func parseIssues(_ json: String, line: Int = #line) -> [ConfigIssue] {
    do {
        _ = try ConfigParser.parse(json)
        expect(false, "expected the configuration to be rejected", line: line)
        return []
    } catch let error as ConfigError {
        return error.issues
    } catch {
        expect(false, "unexpected error \(error)", line: line)
        return []
    }
}

// MARK: - Fixtures

let grave = KeyCodes.code(for: "grave_accent_and_tilde")!
let slash = KeyCodes.code(for: "slash")!
let isoSection = KeyCodes.code(for: "non_us_backslash")!
let leftArrow = KeyCodes.code(for: "left_arrow")!
let keyA = KeyCodes.code(for: "a")!
let keyC = KeyCodes.code(for: "c")!
let keyH = KeyCodes.code(for: "h")!
let keyK = KeyCodes.code(for: "k")!

/// Real key events always carry the "non-coalesced" bit; it must survive remapping.
let nonCoalesced = EventFlags(rawValue: 0x100)
let leftShift: EventFlags = [.shift, .leftShift]
let rightShift: EventFlags = [.shift, .rightShift]

func down(_ key: UInt16, _ flags: EventFlags = [], isRepeat: Bool = false, iso: Bool = false) -> KeyEvent {
    KeyEvent(keyCode: key, flags: flags.union(nonCoalesced), isKeyDown: true, isRepeat: isRepeat, isISO: iso)
}

func up(_ key: UInt16, _ flags: EventFlags = [], iso: Bool = false) -> KeyEvent {
    KeyEvent(keyCode: key, flags: flags.union(nonCoalesced), isKeyDown: false, isISO: iso)
}

func send(_ key: UInt16, _ flags: EventFlags = []) -> RemapAction {
    .replace(taps: [], key: KeyStroke(keyCode: key, flags: flags.union(nonCoalesced)))
}

func makeRemapper(_ json: String) throws -> Remapper {
    let remapper = Remapper()
    remapper.setRules(try ConfigParser.parse(json).rules)
    return remapper
}

func readExample(_ name: String) throws -> String {
    try String(contentsOfFile: "examples/\(name)", encoding: .utf8)
}

// MARK: - Key codes

test("key codes follow Karabiner names and macOS virtual key codes") {
    expectEqual(grave, 0x32)
    expectEqual(slash, 0x2C)
    expectEqual(isoSection, 0x0A)
    expectEqual(KeyCodes.code(for: "non_us_pound"), 0x2A, "alias")
    expectEqual(KeyCodes.name(for: 0x2A), "backslash", "canonical name wins over alias")
    expectEqual(KeyCodes.code(for: "nope"), nil)
    expectEqual(Set(KeyCodes.allNames).count, KeyCodes.allNames.count, "names are unique")
    for name in KeyCodes.allNames {
        expectEqual(KeyCodes.name(for: KeyCodes.code(for: name)!), name, "round trip of \(name)")
    }
}

test("ISO keyboards swap the section and grave key codes") {
    expectEqual(KeyCodes.normalize(isoSection, iso: true), grave)
    expectEqual(KeyCodes.normalize(grave, iso: true), isoSection)
    expectEqual(KeyCodes.normalize(slash, iso: true), slash)
    expectEqual(KeyCodes.normalize(isoSection, iso: false), isoSection)
}

test("arrow, function and keypad keys carry their own flags") {
    expectEqual(KeyCodes.inherentFlags(for: leftArrow), [.numericPad, .secondaryFn])
    expectEqual(KeyCodes.inherentFlags(for: KeyCodes.code(for: "f1")!), .secondaryFn)
    expectEqual(KeyCodes.inherentFlags(for: KeyCodes.code(for: "home")!), .secondaryFn)
    expectEqual(KeyCodes.inherentFlags(for: KeyCodes.code(for: "keypad_1")!), .numericPad)
    expectEqual(KeyCodes.inherentFlags(for: keyA), [])
}

test("unknown key names get suggestions") {
    expectEqual(KeyCodes.suggestion(for: "slsh"), "slash")
    expectEqual(KeyCodes.suggestion(for: "SLASH"), "slash")
    expectEqual(KeyCodes.suggestion(for: "space"), "spacebar")
    expectEqual(KeyCodes.suggestion(for: "grave_accent"), "grave_accent_and_tilde")
    expectEqual(KeyCodes.suggestion(for: "zzzzzzzzzz"), nil)
}

// MARK: - Modifiers

test("pressed modifiers come from the device bits of the flags") {
    expectEqual(Modifier.pressed(in: rightShift, keyCode: keyA), [.rightShift])
    expectEqual(Modifier.pressed(in: [.shift, .leftShift, .rightShift], keyCode: keyA), [.leftShift, .rightShift])
    expectEqual(Modifier.pressed(in: .shift, keyCode: keyA), [.leftShift], "generic bit only")
    expectEqual(Modifier.pressed(in: [.command, .rightCommand, .option, .leftOption], keyCode: keyA), [.rightCommand, .leftOption])
    expectEqual(Modifier.pressed(in: .secondaryFn, keyCode: keyA), [.fn])
    expectEqual(Modifier.pressed(in: [.secondaryFn, .numericPad], keyCode: leftArrow), [], "arrows always carry fn")
    expectEqual(Modifier.pressed(in: [.capsLock], keyCode: keyA), [.capsLock])
    expectEqual(Modifier.pressed(in: nonCoalesced, keyCode: keyA), [])
}

test("modifier names follow Karabiner") {
    expectEqual(ModifierPattern(name: "shift"), .family(.shift))
    expectEqual(ModifierPattern(name: "left_shift"), .key(.leftShift))
    expectEqual(ModifierPattern(name: "fn"), .key(.fn))
    expectEqual(ModifierPattern(name: "caps_lock"), .key(.capsLock))
    expectEqual(ModifierPattern(name: "left_alt"), .key(.leftOption))
    expectEqual(ModifierPattern(name: "right_gui"), .key(.rightCommand))
    expectEqual(ModifierPattern(name: "any"), .any)
    expectEqual(ModifierPattern(name: "shfit"), nil)
    expectEqual(Modifier(toName: "shift"), .leftShift)
    expectEqual(Modifier(toName: "right_command"), .rightCommand)
    expectEqual(Modifier(toName: "any"), nil)
    for name in ModifierPattern.validNames {
        expect(ModifierPattern(name: name) != nil, "\(name) is valid")
    }
}

// MARK: - Parsing

test("the requested JSON parses into two manipulators") {
    let config = try ConfigParser.parse(try readExample("pipe-to-underscore.json"))
    expectEqual(config.warnings, [])
    expectEqual(config.rules.count, 1)
    let rule = config.rules[0]
    expectEqual(rule.description, "| sin shift -> _ , - + shift -> |")
    expectEqual(rule.manipulators.count, 2)
    expectEqual(rule.manipulators[0].from, FromEvent(keyCode: grave, mandatory: [], optional: []))
    expectEqual(rule.manipulators[0].to, [ToEvent(keyCode: slash, modifiers: [.leftShift])])
    expectEqual(rule.manipulators[1].from, FromEvent(keyCode: slash, mandatory: [.family(.shift)], optional: []))
    expectEqual(rule.manipulators[1].to, [ToEvent(keyCode: grave)])
    expectEqual(rule.manipulators[1].ruleDescription, rule.description)
}

test("the default configuration is the requested JSON") {
    let fromExample = try ConfigParser.parse(try readExample("pipe-to-underscore.json"))
    expectEqual(try ConfigParser.parse(DefaultConfig.json), fromExample)
}

test("every example parses without warnings") {
    let files = try FileManager.default.contentsOfDirectory(atPath: "examples").filter { $0.hasSuffix(".json") }.sorted()
    expect(files.count >= 2, "examples found: \(files)")
    for file in files {
        let config = try ConfigParser.parse(try readExample(file))
        expect(!config.rules.isEmpty, "\(file) has rules")
        expectEqual(config.warnings, [], file)
    }
}

let bareManipulator = #"{"type": "basic", "from": {"key_code": "a"}, "to": [{"key_code": "b"}]}"#

test("accepts a rule list, a complex modifications file, a karabiner.json and a lone manipulator") {
    let list = try ConfigParser.parse("[{\"manipulators\": [\(bareManipulator)]}]")
    expectEqual(list.rules.map(\.description), ["Regla 1"])

    let file = try ConfigParser.parse("{\"title\": \"x\", \"rules\": [{\"description\": \"uno\", \"manipulators\": [\(bareManipulator)]}, {\"description\": \"dos\", \"manipulators\": []}]}")
    expectEqual(file.rules.map(\.description), ["uno", "dos"])

    let karabiner = try ConfigParser.parse("""
    {"profiles": [
        {"name": "A", "complex_modifications": {"rules": [{"description": "no", "manipulators": []}]}},
        {"name": "B", "selected": true,
         "simple_modifications": [{"from": {"key_code": "caps_lock"}, "to": [{"key_code": "escape"}]}],
         "complex_modifications": {"rules": [{"description": "sí", "manipulators": [\(bareManipulator)]}]}}
    ]}
    """)
    expectEqual(karabiner.rules.map(\.description), ["sí"], "uses the selected profile")
    expectEqual(karabiner.warnings.map(\.path), ["profiles[1].simple_modifications"])

    let lone = try ConfigParser.parse(bareManipulator)
    expectEqual(lone.manipulatorCount, 1)
}

test("accepts single strings and single objects where Karabiner does") {
    let config = try ConfigParser.parse("""
    {"manipulators": [{"type": "basic",
        "from": {"key_code": "a", "modifiers": {"mandatory": "shift", "optional": "caps_lock"}},
        "to": {"key_code": "b", "modifiers": "command", "repeat": false}}]}
    """)
    let manipulator = config.rules[0].manipulators[0]
    expectEqual(manipulator.from.mandatory, [.family(.shift)])
    expectEqual(manipulator.from.optional, [.key(.capsLock)])
    expectEqual(manipulator.to, [ToEvent(keyCode: KeyCodes.code(for: "b")!, modifiers: [.leftCommand], repeats: false)])
}

test("disabled rules are skipped without validation") {
    let config = try ConfigParser.parse(#"{"rules": [{"enabled": false, "manipulators": [{"from": {"key_code": "nope"}}]}]}"#)
    expectEqual(config.rules, [])
}

test("unknown keys are warnings, missing \"to\" disables the key") {
    let config = try ConfigParser.parse(#"{"manipulators": [{"type": "basic", "from": {"key_code": "f13"}, "extra": 1}]}"#)
    expectEqual(config.rules[0].manipulators[0].to, [])
    expectEqual(config.warnings.map(\.path), ["manipulators[0].extra", "manipulators[0].to"])
}

test("invalid JSON is reported") {
    let issues = parseIssues("{\"manipulators\": [")
    expectEqual(issues.count, 1)
    expect(issues.first?.message.hasPrefix("JSON inválido") == true, "\(issues)")
}

test("bad key and modifier names are reported with their path") {
    let issues = parseIssues("""
    {"manipulators": [
        {"type": "basic", "from": {"key_code": "slsh"}, "to": [{"key_code": "a"}]},
        {"type": "basic", "from": {"key_code": "a", "modifiers": {"mandatory": ["shfit"]}}, "to": [{"key_code": "b", "modifiers": ["any"]}]},
        {"type": "basic", "from": {"key_code": "a", "modifiers": {"mandatory": ["any"]}}, "to": [{"key_code": "left_shift"}]}
    ]}
    """)
    expectEqual(issues.map(\.path), [
        "manipulators[0].from.key_code",
        "manipulators[1].from.modifiers.mandatory[0]",
        "manipulators[1].to[0].modifiers[0]",
        "manipulators[2].from.modifiers.mandatory[0]",
        "manipulators[2].to[0].key_code",
    ])
    expect(issues[0].message.contains("\"slash\""), issues[0].message)
}

test("unsupported Karabiner features are errors, not silently ignored") {
    let issues = parseIssues("""
    {"manipulators": [
        {"type": "basic", "from": {"key_code": "a"}, "to": [{"shell_command": "open ."}],
         "conditions": [{"type": "frontmost_application_if"}]},
        {"type": "mouse_motion_to_scroll", "from": {"key_code": "a"}, "to": []}
    ]}
    """)
    expectEqual(issues.map(\.path), [
        "manipulators[0].conditions",
        "manipulators[0].to[0].shell_command",
        "manipulators[1].type",
    ])
}

#if canImport(Darwin)
test("comments and trailing commas are tolerated") {
    let config = try ConfigParser.parse("""
    {
        // Karabiner doesn't allow this, but it's handy.
        "manipulators": [\(bareManipulator),],
    }
    """)
    expectEqual(config.manipulatorCount, 1)
}
#endif

test("summaries describe manipulators") {
    let rule = try ConfigParser.parse(DefaultConfig.json).rules[0]
    expectEqual(rule.manipulators[0].from.summary, "grave_accent_and_tilde")
    expectEqual(rule.manipulators[0].toSummary, "shift + slash")
    expectEqual(rule.manipulators[1].from.summary, "shift + slash")
    expectEqual(rule.manipulators[1].toSummary, "grave_accent_and_tilde")
    expectEqual(rule.manipulators[0].from.conditionSummary, "Sin modificadores; con cualquier modificador la tecla no cambia")
    expectEqual(rule.manipulators[1].from.conditionSummary, "Con shift y ningún otro modificador")
}

// MARK: - Remapping

test("| alone types _ (shift + slash)") {
    let remapper = try makeRemapper(DefaultConfig.json)
    expectEqual(remapper.process(down(grave)), send(slash, leftShift))
    expectEqual(remapper.lastManipulator?.ruleDescription, "| sin shift -> _ , - + shift -> |")
    expectEqual(remapper.process(up(grave)), send(slash, leftShift))
}

test("| with shift or option is left alone, so ° and ¬ still work") {
    let remapper = try makeRemapper(DefaultConfig.json)
    expectEqual(remapper.process(down(grave, leftShift)), .passThrough)
    expectEqual(remapper.process(up(grave, leftShift)), .passThrough)
    expectEqual(remapper.process(down(grave, rightShift)), .passThrough)
    expectEqual(remapper.process(down(grave, [.option, .leftOption])), .passThrough)
    expectEqual(remapper.process(down(grave, [.command, .leftCommand])), .passThrough)
    expectEqual(remapper.lastManipulator, nil)
}

test("shift + - types | (shift is released for that key)") {
    let remapper = try makeRemapper(DefaultConfig.json)
    expectEqual(remapper.process(down(slash, leftShift)), send(grave))
    expectEqual(remapper.process(up(slash, leftShift)), send(grave))
    expectEqual(remapper.process(down(slash, rightShift)), send(grave), "either shift key")
    expectEqual(remapper.process(down(slash, .shift)), send(grave), "generic shift bit only")
    expectEqual(remapper.process(down(slash, [.shift, .leftShift, .rightShift])), send(grave), "both shift keys")
}

test("- alone and - with other modifiers are left alone") {
    let remapper = try makeRemapper(DefaultConfig.json)
    expectEqual(remapper.process(down(slash)), .passThrough)
    expectEqual(remapper.process(down(slash, leftShift.union([.command, .leftCommand]))), .passThrough)
    expectEqual(remapper.process(down(keyA, leftShift)), .passThrough)
}

test("caps lock blocks rules unless it is optional, as in Karabiner") {
    let strict = try makeRemapper(DefaultConfig.json)
    expectEqual(strict.process(down(grave, .capsLock)), .passThrough)

    let tolerant = try makeRemapper(try readExample("advanced.json"))
    expectEqual(tolerant.process(down(grave, .capsLock)), send(slash, leftShift.union(.capsLock)))
    expectEqual(tolerant.process(down(grave, leftShift.union(.capsLock))), .passThrough, "° still works")
    expectEqual(tolerant.process(down(slash, leftShift.union(.capsLock))), send(grave, .capsLock))
}

test("the release matches the press even if shift was released first") {
    let remapper = try makeRemapper(DefaultConfig.json)
    expectEqual(remapper.process(down(slash, leftShift)), send(grave))
    expectEqual(remapper.process(up(slash)), send(grave), "shift already up")
    expectEqual(remapper.process(up(slash)), .passThrough, "no longer held")
}

test("auto-repeat keeps the key chosen on press") {
    let remapper = try makeRemapper(DefaultConfig.json)
    expectEqual(remapper.process(down(grave)), send(slash, leftShift))
    expectEqual(remapper.process(down(grave, isRepeat: true)), send(slash, leftShift))
    expectEqual(remapper.process(down(grave, leftShift, isRepeat: true)), send(slash, leftShift), "shift pressed while repeating")
    expectEqual(remapper.process(down(keyA, isRepeat: true)), .passThrough, "repeat of a key that isn't held")
}

test("held keys are released correctly after reloading or disabling") {
    let remapper = try makeRemapper(DefaultConfig.json)
    expectEqual(remapper.process(down(slash, leftShift)), send(grave))
    remapper.setRules([])
    expectEqual(remapper.process(up(slash)), send(grave))
    expectEqual(remapper.process(down(slash, leftShift)), .passThrough, "rules are gone")

    let disabled = try makeRemapper(DefaultConfig.json)
    expectEqual(disabled.process(down(grave)), send(slash, leftShift))
    disabled.isEnabled = false
    expectEqual(disabled.process(up(grave)), send(slash, leftShift), "release of a key pressed while enabled")
    expectEqual(disabled.process(down(grave)), .passThrough)
    expectEqual(disabled.process(up(grave)), .passThrough)
}

test("ISO keyboards: the key left of 1 is grave_accent_and_tilde") {
    let remapper = try makeRemapper(DefaultConfig.json)
    expectEqual(remapper.process(down(isoSection, iso: true)), send(slash, leftShift))
    expectEqual(remapper.process(up(isoSection, iso: true)), send(slash, leftShift))
    expectEqual(remapper.process(down(grave, iso: true)), .passThrough, "the key right of left shift")
    expectEqual(remapper.process(down(slash, leftShift, iso: true)), send(isoSection), "outputs the key left of 1")
}

test("optional any keeps extra modifiers; arrows get their own flags") {
    let remapper = try makeRemapper(try readExample("advanced.json"))
    expectEqual(remapper.process(down(keyH, [.control, .leftControl])), send(leftArrow, [.numericPad, .secondaryFn]))
    expectEqual(
        remapper.process(down(keyH, [.control, .rightControl, .shift, .leftShift])),
        send(leftArrow, [.numericPad, .secondaryFn, .shift, .leftShift])
    )
    expectEqual(remapper.process(down(keyH)), .passThrough, "control is mandatory")
}

test("arrow keys as source ignore their built-in fn flag") {
    let remapper = try makeRemapper(#"{"manipulators": [{"type": "basic", "from": {"key_code": "left_arrow"}, "to": [{"key_code": "h"}]}]}"#)
    expectEqual(remapper.process(down(leftArrow, [.numericPad, .secondaryFn])), send(keyH))
}

test("fn as a mandatory modifier is consumed") {
    let remapper = try makeRemapper(#"{"manipulators": [{"type": "basic", "from": {"key_code": "h", "modifiers": {"mandatory": ["fn"]}}, "to": [{"key_code": "left_arrow"}]}]}"#)
    expectEqual(remapper.process(down(keyH, .secondaryFn)), send(leftArrow, [.numericPad, .secondaryFn]))
    expectEqual(remapper.process(down(keyH)), .passThrough)
}

test("several to events: all but the last are tapped first; repeat false stops repeats") {
    let remapper = try makeRemapper(try readExample("advanced.json"))
    let command: EventFlags = [.command, .leftCommand, nonCoalesced]
    expectEqual(
        remapper.process(down(keyK, [.command, .rightCommand])),
        .replace(taps: [KeyStroke(keyCode: keyA, flags: command)], key: KeyStroke(keyCode: keyC, flags: command))
    )
    expectEqual(remapper.process(down(keyK, [.command, .rightCommand], isRepeat: true)), .drop)
    expectEqual(remapper.process(up(keyK, [.command, .rightCommand])), .replace(taps: [], key: KeyStroke(keyCode: keyC, flags: command)))
    expectEqual(remapper.process(down(keyK, [.command, .leftCommand])), .passThrough, "right command only")
}

test("an empty to list disables the key") {
    let remapper = try makeRemapper(#"{"manipulators": [{"type": "basic", "from": {"key_code": "f13"}, "to": []}]}"#)
    let f13 = KeyCodes.code(for: "f13")!
    expectEqual(remapper.process(down(f13, .secondaryFn)), .drop)
    expectEqual(remapper.process(down(f13, .secondaryFn, isRepeat: true)), .drop)
    expectEqual(remapper.process(up(f13, .secondaryFn)), .drop)
}

test("the first matching manipulator wins") {
    let remapper = try makeRemapper("""
    {"manipulators": [
        {"type": "basic", "from": {"key_code": "a", "modifiers": {"mandatory": ["shift"]}}, "to": [{"key_code": "b"}]},
        {"type": "basic", "from": {"key_code": "a", "modifiers": {"optional": ["any"]}}, "to": [{"key_code": "c"}]}
    ]}
    """)
    expectEqual(remapper.process(down(keyA, leftShift)), send(KeyCodes.code(for: "b")!))
    expectEqual(remapper.process(down(keyA, leftShift.union([.option, .leftOption]))), send(keyC, leftShift.union([.option, .leftOption])))
    expectEqual(remapper.process(down(keyA)), send(keyC))
}

// MARK: - Summary

print("\n\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
