import AppKit
import SwiftUI

/// The "KeySwapo" window: status, rules, JSON editor and key tester.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KeySwapo"
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.setContentSize(NSSize(width: 720, height: 680))
        window.isReleasedWhenClosed = false
        window.center()
        _ = window.setFrameAutosaveName("KeySwapoSettings")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        model.settingsWindowDidShow()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        model.settingsWindowDidClose()
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            banners
            TabView(selection: $model.selectedTab) {
                RulesTab(model: model)
                    .tabItem { Text("Reglas") }
                    .tag(SettingsTab.rules)
                JSONTab(model: model)
                    .tabItem { Text("JSON") }
                    .tag(SettingsTab.json)
                TesterTab(model: model)
                    .tabItem { Text("Probador de teclas") }
                    .tag(SettingsTab.tester)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 580)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.needsAttention ? "exclamationmark.triangle.fill" : "keyboard")
                .font(.system(size: 28))
                .foregroundStyle(model.needsAttention ? Color.orange : Color.accentColor)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("KeySwapo").font(.title2.weight(.semibold))
                Text(model.statusText).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Remapeo activado", isOn: $model.isEnabled)
                .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private var banners: some View {
        if !model.hasAccessibility {
            Banner(
                systemImage: "lock.shield",
                tint: .orange,
                title: "Falta el permiso de Accesibilidad",
                message: "macOS exige este permiso para que KeySwapo pueda leer y cambiar las teclas. Actívalo para KeySwapo en Ajustes del Sistema › Privacidad y seguridad › Accesibilidad. El remapeo empieza solo en cuanto lo concedas. Si recompilaste la app y ya aparecía en la lista, quítala con «−» y vuelve a agregarla."
            ) {
                Button("Abrir Ajustes de Accesibilidad") { model.openAccessibilitySettings() }
            }
        } else if !model.isTapRunning {
            Banner(
                systemImage: "exclamationmark.triangle",
                tint: .orange,
                title: "No se pudo activar el interceptor de teclado",
                message: "El permiso está concedido, pero macOS no dejó instalar el interceptor. Normalmente se arregla reiniciando KeySwapo."
            ) {
                Button("Reiniciar KeySwapo") { model.relaunch() }
            }
        }
        if model.secureInputActive {
            Banner(
                systemImage: "lock.fill",
                tint: .blue,
                title: "Entrada segura activa",
                message: "Alguna app (un campo de contraseña, o la Terminal con «Entrada de teclado segura») está protegiendo el teclado. Mientras siga así, macOS no deja que KeySwapo vea ni cambie las teclas."
            ) {
                EmptyView()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Abrir KeySwapo al iniciar sesión", isOn: $model.launchAtLoginSetting)
            if let error = model.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button("Salir de KeySwapo") { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Tabs

struct RulesTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !model.configErrors.isEmpty {
                    IssueList(
                        title: model.rules.isEmpty
                            ? "La configuración tiene errores"
                            : "La configuración tiene errores; siguen activas las últimas reglas válidas",
                        issues: model.configErrors,
                        tint: .red
                    )
                }
                if model.ruleRows.isEmpty && model.configErrors.isEmpty {
                    Text("No hay reglas. Escribe o pega tu JSON en la pestaña «JSON».")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.ruleRows) { rule in
                    RuleCard(rule: rule)
                }
                if !model.configWarnings.isEmpty {
                    IssueList(title: "Advertencias", issues: model.configWarnings, tint: .orange)
                }
                Text(model.layoutDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }
}

struct RuleCard: View {
    let rule: RuleRow

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if rule.manipulators.isEmpty {
                    Text("Sin manipuladores").foregroundStyle(.secondary)
                }
                ForEach(rule.manipulators) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            KeyChip(keys: row.fromKeys, character: row.fromCharacter)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            KeyChip(keys: row.toKeys, character: row.toCharacter)
                            Spacer(minLength: 0)
                        }
                        Text(row.condition)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(rule.title).font(.headline)
        }
    }
}

struct KeyChip: View {
    let keys: String
    let character: String?

    var body: some View {
        HStack(spacing: 8) {
            if let character {
                Text(character)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 18)
            }
            Text(keys).font(.system(.callout, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct JSONTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.configPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                if model.isEditorDirty {
                    Text("Cambios sin aplicar").font(.caption).foregroundStyle(.orange)
                }
            }
            JSONTextView(text: $model.editorText)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))
            HStack {
                Button("Aplicar") { model.applyEditorText() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.isEditorDirty)
                Button("Descartar cambios") { model.revertEditor() }
                    .disabled(!model.isEditorDirty)
                Spacer()
                Button("Importar archivo…") { model.importFile() }
                Button("Mostrar en Finder") { model.revealConfigInFinder() }
            }
            if let message = model.editorMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if !model.editorErrors.isEmpty {
                IssueList(title: "No se aplicó: el JSON tiene errores", issues: model.editorErrors, tint: .red)
            }
            Text("Formato de Karabiner-Elements: una regla con \"manipulators\", o un objeto con \"rules\". También se aplica al guardar el archivo desde otro editor.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }
}

struct TesterTab: View {
    @ObservedObject var model: AppModel
    @State private var sample = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Escribe en el campo con esta ventana al frente. Verás el resultado real y, en la lista, la tecla física que detectó KeySwapo y lo que envió en su lugar. Los nombres son los que se usan en el JSON.")
                .fixedSize(horizontal: false, vertical: true)
            TextField("Escribe aquí para probar…", text: $sample)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 16, design: .monospaced))
            if !model.isTapRunning {
                Text("El interceptor de teclado no está activo, así que aquí no se verán cambios.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            List(model.recentKeys) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.physical).font(.system(.body, design: .monospaced))
                    Text(row.result)
                        .font(.caption)
                        .foregroundStyle(row.remapped ? Color.green : Color.secondary)
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 160)
            HStack {
                Text(model.layoutDescription).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Limpiar") {
                    sample = ""
                    model.clearRecentKeys()
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Building blocks

struct Banner<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message).fixedSize(horizontal: false, vertical: true)
                HStack {
                    actions()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct IssueList: View {
    let title: String
    let issues: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(tint)
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                Text("• " + issue)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
