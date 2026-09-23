import Foundation

/// `KeySwapo --check [archivo.json]`: validates a configuration and prints what it does,
/// without starting the app. Without a file it checks ~/.config/keyswapo/keyswapo.json.
enum CheckCommand {
    static func run(path: String?) -> Int32 {
        let store = ConfigStore()
        let url = path.map { URL(fileURLWithPath: $0) } ?? store.fileURL
        let displayPath = path ?? store.displayPath
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("✗ No se pudo leer \(displayPath): \(error.localizedDescription)")
            return 1
        }
        do {
            let configuration = try ConfigParser.parse(text)
            let layout = KeyboardLayout.Context.current
            print("✓ \(displayPath): \(pluralize(configuration.rules.count, "regla", "reglas")), \(pluralize(configuration.manipulatorCount, "cambio de tecla", "cambios de tecla"))")
            print("  \(KeyboardLayout.summary)")
            for rule in configuration.rules {
                print("\n• \(rule.description)")
                for (index, manipulator) in rule.manipulators.enumerated() {
                    let row = ManipulatorRow(id: index, manipulator: manipulator, layout: layout)
                    print("  \(index + 1). \(row.fromKeys)\(quoted(row.fromCharacter))  →  \(row.toKeys)\(quoted(row.toCharacter))")
                    print("     \(row.condition)")
                }
            }
            printWarnings(configuration.warnings)
            return 0
        } catch let error as ConfigError {
            print("✗ \(displayPath) tiene errores; KeySwapo no la aplicaría:")
            for issue in error.issues {
                print("  • \(issue)")
            }
            printWarnings(error.warnings)
            return 1
        } catch {
            print("✗ \(error)")
            return 1
        }
    }

    private static func quoted(_ character: String?) -> String {
        character.map { " «\($0)»" } ?? ""
    }

    private static func printWarnings(_ warnings: [ConfigIssue]) {
        guard !warnings.isEmpty else { return }
        print("\nAdvertencias:")
        for warning in warnings {
            print("  • \(warning)")
        }
    }
}
