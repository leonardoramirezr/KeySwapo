/// "1 regla", "2 reglas".
func pluralize(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}

/// A rule as shown in the settings window.
struct RuleRow: Identifiable {
    let id: Int
    let title: String
    let manipulators: [ManipulatorRow]
}

/// A manipulator in words, with the characters it involves in the current layout.
struct ManipulatorRow: Identifiable {
    let id: Int
    let fromKeys: String
    let fromCharacter: String?
    let toKeys: String
    let toCharacter: String?
    let condition: String

    init(id: Int, manipulator: Manipulator, layout: KeyboardLayout.Context) {
        self.id = id
        fromKeys = manipulator.from.summary
        toKeys = manipulator.toSummary
        condition = manipulator.from.conditionSummary

        var fromFlags = EventFlags()
        for pattern in manipulator.from.mandatory {
            switch pattern {
            case .key(let modifier): fromFlags.formUnion(modifier.flags)
            case .family(let family): fromFlags.formUnion(family.keys[0].flags)
            case .any: break
            }
        }
        fromCharacter = KeyboardLayout.character(
            keyCode: KeyCodes.normalize(manipulator.from.keyCode, iso: layout.isISO),
            flags: fromFlags,
            keyboardType: layout.keyboardType
        )

        let typed = manipulator.to.compactMap { target -> String? in
            let flags = target.modifiers.reduce(EventFlags()) { $0.union($1.flags) }
            return KeyboardLayout.character(
                keyCode: KeyCodes.normalize(target.keyCode, iso: layout.isISO),
                flags: flags,
                keyboardType: layout.keyboardType
            )
        }
        toCharacter = typed.count == manipulator.to.count && !typed.isEmpty ? typed.joined() : nil
    }
}

/// A key press seen by the key tester: the physical key and what KeySwapo sent instead.
struct KeyReportRow: Identifiable {
    let id: Int
    let physical: String
    let result: String
    let remapped: Bool

    init(id: Int, report: KeyEventReport) {
        self.id = id
        physical = Self.describe(keyCode: report.keyCode, flags: report.flags, report: report)
            + "   (código \(report.keyCode))"
        switch report.action {
        case .passThrough:
            result = "Sin cambios: ninguna regla aplica"
            remapped = false
        case .drop:
            result = "Descartada: la regla desactiva la tecla" + Self.ruleSuffix(report)
            remapped = true
        case let .replace(taps, key):
            let strokes = (taps + [key]).map { Self.describe(keyCode: $0.keyCode, flags: $0.flags, report: report) }
            result = "→ " + strokes.joined(separator: ", luego ") + Self.ruleSuffix(report)
            remapped = true
        }
    }

    /// For example `shift + slash «_»`, using Karabiner's names so they can go into the JSON.
    private static func describe(keyCode: UInt16, flags: EventFlags, report: KeyEventReport) -> String {
        let key = KeyCodes.normalize(keyCode, iso: report.isISO)
        let modifiers = Modifier.pressed(in: flags, keyCode: key).sorted().map(\.rawValue)
        var text = (modifiers + [KeyCodes.name(for: key) ?? "tecla \(key)"]).joined(separator: " + ")
        if let typed = KeyboardLayout.character(keyCode: keyCode, flags: flags, keyboardType: report.keyboardType) {
            text += " «\(typed)»"
        }
        return text
    }

    private static func ruleSuffix(_ report: KeyEventReport) -> String {
        report.ruleDescription.map { "   · regla: \($0)" } ?? ""
    }
}
