import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

enum SettingsTab: Hashable {
    case rules, json, tester
}

/// State shared by the menu bar item and the settings window.
@MainActor
final class AppModel: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            eventTap.remapper.isEnabled = isEnabled
            notifyStateChange()
        }
    }
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var ruleRows: [RuleRow] = []
    @Published private(set) var configErrors: [String] = []
    @Published private(set) var configWarnings: [String] = []
    @Published private(set) var hasAccessibility = false
    @Published private(set) var isTapRunning = false
    @Published private(set) var secureInputActive = false
    @Published private(set) var layoutDescription = ""
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginError: String?
    /// Text of the JSON editor; `savedText` is what the configuration file contains.
    @Published var editorText = "" {
        didSet {
            if editorText != oldValue {
                editorMessage = nil
            }
        }
    }
    @Published private(set) var savedText = ""
    @Published private(set) var editorErrors: [String] = []
    @Published private(set) var editorMessage: String?
    @Published private(set) var recentKeys: [KeyReportRow] = []
    @Published var selectedTab: SettingsTab = .rules {
        didSet { updateReporting() }
    }

    /// Called whenever the status shown in the menu bar may have changed.
    var onStateChange: (@MainActor () -> Void)?

    let store = ConfigStore()
    /// True if this launch created the configuration file.
    private(set) var createdDefaultConfig = false

    private let eventTap = EventTap()
    private var watcher: FileWatcher?
    private var statusTimer: Timer?
    private var promptedForAccessibility = false
    private var settingsVisible = false
    private var nextReportID = 0

    private static let enabledKey = "remappingEnabled"
    private static let maxRecentKeys = 12

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        eventTap.remapper.isEnabled = isEnabled
    }

    // MARK: - Status

    var isEditorDirty: Bool { editorText != savedText }

    var configPath: String { store.displayPath }

    var manipulatorCount: Int { rules.reduce(0) { $0 + $1.manipulators.count } }

    var needsAttention: Bool { !hasAccessibility || !isTapRunning || !configErrors.isEmpty }

    var statusText: String {
        if !hasAccessibility {
            return "Falta el permiso de Accesibilidad"
        }
        if !isTapRunning {
            return "No se pudo activar el interceptor de teclado"
        }
        if !configErrors.isEmpty {
            return rules.isEmpty ? "Error en \(store.fileName)" : "Error en \(store.fileName); siguen las reglas anteriores"
        }
        if !isEnabled {
            return "En pausa"
        }
        return "Activo · \(pluralize(rules.count, "regla", "reglas")) · \(pluralize(manipulatorCount, "cambio de tecla", "cambios de tecla"))"
    }

    // MARK: - Lifecycle

    func start() {
        do {
            createdDefaultConfig = try store.createDefaultIfNeeded()
        } catch {
            configErrors = ["No se pudo crear \(store.displayPath): \(error.localizedDescription)"]
        }
        reloadConfig()

        watcher = FileWatcher(fileURL: store.fileURL) { [weak self] in
            self?.reloadConfig()
        }
        watcher?.start()

        eventTap.onReport = { [weak self] report in
            guard let model = self else { return }
            // Leave the tap callback first; the tester can update afterwards.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    model.record(report)
                }
            }
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshStatus()
        // Picks up the permission as soon as it is granted (or revoked), and layout changes.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshStatus()
            }
        }
    }

    func stop() {
        statusTimer?.invalidate()
        statusTimer = nil
        watcher?.stop()
        eventTap.stop()
    }

    func refreshStatus() {
        let trusted = Accessibility.isTrusted
        if trusted {
            if !eventTap.isRunning {
                eventTap.start()
            }
        } else {
            eventTap.stop()
            if !promptedForAccessibility {
                promptedForAccessibility = true
                Accessibility.prompt()
            }
        }
        if hasAccessibility != trusted {
            hasAccessibility = trusted
        }
        let running = eventTap.isRunning
        if isTapRunning != running {
            isTapRunning = running
        }
        let secure = SecureInput.isEnabled
        if secureInputActive != secure {
            secureInputActive = secure
        }
        let layout = KeyboardLayout.summary
        if layoutDescription != layout {
            layoutDescription = layout
            rebuildRuleRows()
        }
        notifyStateChange()
    }

    // MARK: - Configuration

    func reloadConfig() {
        let text: String
        do {
            text = try store.readText()
        } catch {
            configErrors = ["No se pudo leer \(store.displayPath): \(error.localizedDescription)"]
            notifyStateChange()
            return
        }
        let editorWasClean = !isEditorDirty
        savedText = text
        if editorWasClean && editorText != text {
            editorText = text
        }
        do {
            apply(try ConfigParser.parse(text))
        } catch let error as ConfigError {
            configErrors = error.issues.map(\.description)
            notifyStateChange()
        } catch {
            configErrors = [error.localizedDescription]
            notifyStateChange()
        }
    }

    /// Validates the editor text and, if it is valid, saves and applies it.
    func applyEditorText() {
        let text = editorText
        do {
            let configuration = try ConfigParser.parse(text)
            try store.write(text)
            savedText = text
            editorErrors = []
            apply(configuration)
            let warnings = configuration.warnings.count
            editorMessage = warnings == 0
                ? "Guardado y aplicado."
                : "Guardado y aplicado, con \(pluralize(warnings, "advertencia", "advertencias")) (ver «Reglas»)."
        } catch let error as ConfigError {
            editorErrors = error.issues.map(\.description)
            editorMessage = nil
        } catch {
            editorErrors = ["No se pudo guardar \(store.displayPath): \(error.localizedDescription)"]
            editorMessage = nil
        }
    }

    func revertEditor() {
        editorText = savedText
        editorErrors = []
    }

    /// Loads a JSON file into the editor and applies it if it is valid.
    func importFile() {
        let panel = NSOpenPanel()
        panel.title = "Importar configuración JSON"
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            editorText = try String(contentsOf: url, encoding: .utf8)
        } catch {
            editorErrors = ["No se pudo leer \(url.path): \(error.localizedDescription)"]
            return
        }
        selectedTab = .json
        applyEditorText()
    }

    func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    private func apply(_ configuration: Configuration) {
        rules = configuration.rules
        configWarnings = configuration.warnings.map(\.description)
        configErrors = []
        eventTap.remapper.setRules(configuration.rules)
        rebuildRuleRows()
        notifyStateChange()
    }

    private func rebuildRuleRows() {
        let layout = KeyboardLayout.Context.current
        ruleRows = rules.enumerated().map { index, rule in
            RuleRow(
                id: index,
                title: rule.description,
                manipulators: rule.manipulators.enumerated().map { ManipulatorRow(id: $0.offset, manipulator: $0.element, layout: layout) }
            )
        }
    }

    // MARK: - Key tester

    func settingsWindowDidShow() {
        settingsVisible = true
        updateReporting()
    }

    func settingsWindowDidClose() {
        settingsVisible = false
        updateReporting()
    }

    func clearRecentKeys() {
        recentKeys = []
    }

    private func updateReporting() {
        eventTap.isReporting = settingsVisible && selectedTab == .tester
    }

    private func record(_ report: KeyEventReport) {
        // Only presses typed into KeySwapo's own window, never those meant for other apps.
        guard report.isKeyDown, !report.isRepeat, eventTap.isReporting, NSApp.isActive else { return }
        nextReportID += 1
        recentKeys.insert(KeyReportRow(id: nextReportID, report: report), at: 0)
        if recentKeys.count > Self.maxRecentKeys {
            recentKeys.removeLast(recentKeys.count - Self.maxRecentKeys)
        }
    }

    // MARK: - System

    func openAccessibilitySettings() {
        Accessibility.openSettings()
    }

    /// Bindable form of `launchAtLogin`.
    var launchAtLoginSetting: Bool {
        get { launchAtLogin }
        set { setLaunchAtLogin(newValue) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            launchAtLoginError = service.status == .requiresApproval
                ? "Apruébalo en Ajustes del Sistema › General › Ítems de inicio."
                : nil
        } catch {
            launchAtLoginError = "No se pudo cambiar el inicio automático: \(error.localizedDescription)"
        }
        launchAtLogin = service.status == .enabled
        notifyStateChange()
    }

    /// Starts a new copy of the app and quits this one.
    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func notifyStateChange() {
        onStateChange?()
    }
}

/// The Accessibility permission, required to create an event tap that modifies key events.
@MainActor
enum Accessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt, which also adds KeySwapo to the list in System Settings.
    static func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        _ = NSWorkspace.shared.open(url)
    }
}
