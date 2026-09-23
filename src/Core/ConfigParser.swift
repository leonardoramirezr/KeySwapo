import Foundation

/// A problem found in a configuration, with the JSON path where it was found.
struct ConfigIssue: Equatable, CustomStringConvertible {
    var path: String
    var message: String

    var description: String { path.isEmpty ? message : "\(path): \(message)" }
}

/// The configuration can't be used. KeySwapo applies a configuration completely or not at all:
/// applying only some manipulators could, for example, turn `|` into `_` while losing the
/// manipulator that gives `|` back.
struct ConfigError: Error, CustomStringConvertible {
    var issues: [ConfigIssue]
    var warnings: [ConfigIssue] = []

    var description: String { issues.map(\.description).joined(separator: "\n") }
}

struct Configuration: Equatable {
    var rules: [Rule]
    var warnings: [ConfigIssue] = []

    var manipulatorCount: Int { rules.reduce(0) { $0 + $1.manipulators.count } }
}

/// Reads Karabiner-Elements style JSON. Accepted shapes:
/// - a rule: `{"description": …, "manipulators": […]}`
/// - a list of rules: `[rule, …]`
/// - a complex modifications file: `{"title": …, "rules": [rule, …]}`
/// - a `karabiner.json`: the rules of the selected profile
/// - a single manipulator: `{"type": "basic", "from": …, "to": …}`
enum ConfigParser {
    static func parse(_ text: String) throws -> Configuration {
        try parse(data: Data(text.utf8))
    }

    static func parse(data: Data) throws -> Configuration {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: readingOptions)
        } catch {
            throw ConfigError(issues: [ConfigIssue(path: "", message: "JSON inválido: \(detail(of: error))")])
        }
        var parser = Parser()
        let rules = parser.parseRoot(root)
        if !parser.errors.isEmpty {
            throw ConfigError(issues: parser.errors, warnings: parser.warnings)
        }
        return Configuration(rules: rules, warnings: parser.warnings)
    }

    private static var readingOptions: JSONSerialization.ReadingOptions {
        #if canImport(Darwin)
        // Also accepts comments and trailing commas.
        return [.json5Allowed]
        #else
        return []
        #endif
    }

    private static func detail(of error: Error) -> String {
        let nsError = error as NSError
        return nsError.userInfo[NSDebugDescriptionErrorKey] as? String ?? nsError.localizedDescription
    }
}

private struct Parser {
    var errors: [ConfigIssue] = []
    var warnings: [ConfigIssue] = []

    private static let manipulatorKeys: Set<String> = ["type", "from", "to", "description"]
    private static let unsupportedManipulatorKeys: Set<String> = [
        "to_if_alone", "to_if_held_down", "to_after_key_up", "to_delayed_action",
        "to_if_other_key_pressed", "conditions",
    ]
    private static let unsupportedFromKeys: Set<String> = [
        "consumer_key_code", "pointing_button", "apple_vendor_keyboard_key_code",
        "apple_vendor_top_case_key_code", "generic_desktop", "any", "simultaneous",
        "simultaneous_options",
    ]
    private static let toKeys: Set<String> = ["key_code", "modifiers", "repeat"]
    private static let ignoredToKeys: Set<String> = ["lazy", "halt", "hold_down_milliseconds", "description"]
    private static let unsupportedToKeys: Set<String> = [
        "shell_command", "select_input_source", "set_variable", "set_notification_message",
        "mouse_key", "pointing_button", "consumer_key_code", "software_function", "sticky_modifier",
        "apple_vendor_keyboard_key_code", "apple_vendor_top_case_key_code", "generic_desktop",
    ]

    mutating func parseRoot(_ root: Any) -> [Rule] {
        if let list = root as? [Any] {
            return parseRules(list, path: "")
        }
        guard let object = root as? [String: Any] else {
            error("", "se esperaba un objeto o un arreglo JSON")
            return []
        }
        if object["manipulators"] != nil {
            return parseRule(object, path: "", index: 0).map { [$0] } ?? []
        }
        if let rules = object["rules"] {
            guard let list = rules as? [Any] else {
                error("rules", "debe ser un arreglo de reglas")
                return []
            }
            return parseRules(list, path: "rules")
        }
        if let profiles = object["profiles"] {
            return parseKarabinerProfiles(profiles)
        }
        if object["from"] != nil {
            let description = "Regla 1"
            let manipulator = parseManipulator(object, path: "", ruleDescription: description)
            return manipulator.map { [Rule(description: description, manipulators: [$0])] } ?? []
        }
        error("", "no se encontraron reglas: usa un objeto con \"manipulators\" (una regla), con \"rules\" (varias reglas) o un karabiner.json con \"profiles\"")
        return []
    }

    private mutating func parseKarabinerProfiles(_ value: Any) -> [Rule] {
        guard let profiles = value as? [Any] else {
            error("profiles", "debe ser un arreglo de perfiles")
            return []
        }
        let objects = profiles.map { $0 as? [String: Any] }
        guard let index = objects.firstIndex(where: { $0?["selected"] as? Bool == true }) ?? objects.firstIndex(where: { $0 != nil }),
              let profile = objects[index] else {
            error("profiles", "no hay ningún perfil")
            return []
        }
        let path = "profiles[\(index)]"
        if let simple = profile["simple_modifications"] as? [Any], !simple.isEmpty {
            warn(join(path, "simple_modifications"), "se ignoran; KeySwapo solo usa complex_modifications")
        }
        guard let complex = profile["complex_modifications"] as? [String: Any],
              let rules = complex["rules"] as? [Any] else {
            warn(path, "el perfil no tiene complex_modifications.rules")
            return []
        }
        return parseRules(rules, path: join(path, "complex_modifications.rules"))
    }

    private mutating func parseRules(_ list: [Any], path: String) -> [Rule] {
        var rules: [Rule] = []
        for (index, item) in list.enumerated() {
            let rulePath = "\(path)[\(index)]"
            guard let object = item as? [String: Any] else {
                error(rulePath, "cada regla debe ser un objeto")
                continue
            }
            if let rule = parseRule(object, path: rulePath, index: index) {
                rules.append(rule)
            }
        }
        return rules
    }

    private mutating func parseRule(_ object: [String: Any], path: String, index: Int) -> Rule? {
        if let enabled = object["enabled"] {
            guard let isEnabled = enabled as? Bool else {
                error(join(path, "enabled"), "debe ser true o false")
                return nil
            }
            if !isEnabled {
                return nil
            }
        }
        var description = "Regla \(index + 1)"
        if let value = object["description"] {
            if let text = value as? String {
                description = text
            } else {
                warn(join(path, "description"), "debe ser un texto; se ignora")
            }
        }
        let manipulatorsPath = join(path, "manipulators")
        guard let value = object["manipulators"] else {
            error(manipulatorsPath, "falta la lista de manipuladores")
            return nil
        }
        guard let list = value as? [Any] else {
            error(manipulatorsPath, "debe ser un arreglo")
            return nil
        }
        var manipulators: [Manipulator] = []
        for (index, item) in list.enumerated() {
            let itemPath = "\(manipulatorsPath)[\(index)]"
            guard let object = item as? [String: Any] else {
                error(itemPath, "cada manipulador debe ser un objeto")
                continue
            }
            if let manipulator = parseManipulator(object, path: itemPath, ruleDescription: description) {
                manipulators.append(manipulator)
            }
        }
        return Rule(description: description, manipulators: manipulators)
    }

    private mutating func parseManipulator(_ object: [String: Any], path: String, ruleDescription: String) -> Manipulator? {
        let errorCount = errors.count
        if let type = object["type"], type as? String != "basic" {
            error(join(path, "type"), "solo se admite \"basic\" (se encontró \(describe(type)))")
        }
        for key in object.keys.sorted() where !Self.manipulatorKeys.contains(key) {
            if Self.unsupportedManipulatorKeys.contains(key) {
                error(join(path, key), "KeySwapo no lo soporta")
            } else if key == "parameters" {
                warn(join(path, key), "se ignora")
            } else {
                warn(join(path, key), "clave desconocida; se ignora")
            }
        }

        var from: FromEvent?
        let fromPath = join(path, "from")
        if let value = object["from"] {
            if let fromObject = value as? [String: Any] {
                from = parseFrom(fromObject, path: fromPath)
            } else {
                error(fromPath, "debe ser un objeto")
            }
        } else {
            error(fromPath, "falta \"from\"")
        }

        var to: [ToEvent] = []
        let toPath = join(path, "to")
        if let value = object["to"] {
            var items: [(path: String, value: Any)] = []
            if let list = value as? [Any] {
                items = list.enumerated().map { ("\(toPath)[\($0.offset)]", $0.element) }
            } else if value is [String: Any] {
                items = [(toPath, value)]
            } else {
                error(toPath, "debe ser un arreglo de eventos")
            }
            for item in items {
                guard let toObject = item.value as? [String: Any] else {
                    error(item.path, "cada evento debe ser un objeto")
                    continue
                }
                if let event = parseTo(toObject, path: item.path) {
                    to.append(event)
                }
            }
        } else {
            warn(toPath, "no hay \"to\": la tecla quedará desactivada")
        }

        guard errors.count == errorCount, let from else { return nil }
        return Manipulator(from: from, to: to, ruleDescription: ruleDescription)
    }

    private mutating func parseFrom(_ object: [String: Any], path: String) -> FromEvent? {
        let errorCount = errors.count
        for key in object.keys.sorted() where key != "key_code" && key != "modifiers" {
            if Self.unsupportedFromKeys.contains(key) {
                error(join(path, key), "KeySwapo no lo soporta (solo \"key_code\")")
            } else {
                warn(join(path, key), "clave desconocida; se ignora")
            }
        }
        let keyCode = parseKeyCode(object["key_code"], path: join(path, "key_code"))

        var mandatory: [ModifierPattern] = []
        var optional: [ModifierPattern] = []
        let modifiersPath = join(path, "modifiers")
        if let value = object["modifiers"] {
            if let modifiers = value as? [String: Any] {
                mandatory = parsePatterns(modifiers["mandatory"], path: join(modifiersPath, "mandatory"), allowAny: false)
                optional = parsePatterns(modifiers["optional"], path: join(modifiersPath, "optional"), allowAny: true)
                for key in modifiers.keys.sorted() where key != "mandatory" && key != "optional" {
                    warn(join(modifiersPath, key), "clave desconocida; se ignora")
                }
            } else {
                error(modifiersPath, "debe ser un objeto con \"mandatory\" y/o \"optional\"")
            }
        }

        guard errors.count == errorCount, let keyCode else { return nil }
        return FromEvent(keyCode: keyCode, mandatory: mandatory, optional: optional)
    }

    private mutating func parseTo(_ object: [String: Any], path: String) -> ToEvent? {
        let errorCount = errors.count
        var hasUnsupportedEvent = false
        for key in object.keys.sorted() where !Self.toKeys.contains(key) {
            if Self.unsupportedToKeys.contains(key) {
                hasUnsupportedEvent = true
                error(join(path, key), "KeySwapo no lo soporta (solo \"key_code\" con \"modifiers\")")
            } else if Self.ignoredToKeys.contains(key) {
                warn(join(path, key), "se ignora")
            } else {
                warn(join(path, key), "clave desconocida; se ignora")
            }
        }
        var keyCode: UInt16?
        if !hasUnsupportedEvent || object["key_code"] != nil {
            keyCode = parseKeyCode(object["key_code"], path: join(path, "key_code"))
        }

        var modifiers: [Modifier] = []
        let modifiersPath = join(path, "modifiers")
        for (itemPath, item) in stringList(object["modifiers"], path: modifiersPath) {
            guard let name = item as? String, let modifier = Modifier(toName: name) else {
                error(itemPath, "modificador desconocido \(describe(item)); válidos: \(ModifierPattern.validNames.filter { $0 != "any" }.joined(separator: ", "))")
                continue
            }
            if !modifiers.contains(modifier) {
                modifiers.append(modifier)
            }
        }

        var repeats = true
        if let value = object["repeat"] {
            if let flag = value as? Bool {
                repeats = flag
            } else {
                error(join(path, "repeat"), "debe ser true o false")
            }
        }

        guard errors.count == errorCount, let keyCode else { return nil }
        return ToEvent(keyCode: keyCode, modifiers: modifiers, repeats: repeats)
    }

    private mutating func parseKeyCode(_ value: Any?, path: String) -> UInt16? {
        guard let value else {
            error(path, "falta \"key_code\"")
            return nil
        }
        guard let name = value as? String else {
            error(path, "debe ser el nombre de una tecla, por ejemplo \"slash\"")
            return nil
        }
        guard let code = KeyCodes.code(for: name) else {
            var message = "tecla desconocida \"\(name)\""
            if let suggestion = KeyCodes.suggestion(for: name) {
                message += "; ¿quisiste decir \"\(suggestion)\"?"
            }
            error(path, message)
            return nil
        }
        if KeyCodes.isModifierKey(code) {
            error(path, "\"\(name)\" es una tecla modificadora; KeySwapo solo cambia teclas normales (úsala en \"modifiers\")")
            return nil
        }
        return code
    }

    private mutating func parsePatterns(_ value: Any?, path: String, allowAny: Bool) -> [ModifierPattern] {
        var patterns: [ModifierPattern] = []
        for (itemPath, item) in stringList(value, path: path) {
            guard let name = item as? String, let pattern = ModifierPattern(name: name) else {
                error(itemPath, "modificador desconocido \(describe(item)); válidos: \(ModifierPattern.validNames.joined(separator: ", "))")
                continue
            }
            if pattern == .any && !allowAny {
                error(itemPath, "\"any\" solo se permite en \"optional\"")
                continue
            }
            if !patterns.contains(pattern) {
                patterns.append(pattern)
            }
        }
        return patterns
    }

    /// Items of a value that may be a single string or a list, with the path of each one.
    private mutating func stringList(_ value: Any?, path: String) -> [(path: String, value: Any)] {
        guard let value else { return [] }
        if value is String {
            return [(path, value)]
        }
        guard let list = value as? [Any] else {
            error(path, "debe ser una lista de modificadores")
            return []
        }
        return list.enumerated().map { ("\(path)[\($0.offset)]", $0.element) }
    }

    private mutating func error(_ path: String, _ message: String) {
        errors.append(ConfigIssue(path: path, message: message))
    }

    private mutating func warn(_ path: String, _ message: String) {
        warnings.append(ConfigIssue(path: path, message: message))
    }

    private func join(_ path: String, _ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }

    private func describe(_ value: Any) -> String {
        if let text = value as? String {
            return "\"\(text)\""
        }
        return "\(value)"
    }
}
