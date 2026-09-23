import AppKit

@main
@MainActor
struct KeySwapoApp {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--check") {
            let path = index + 1 < arguments.count ? arguments[index + 1] : nil
            exit(CheckCommand.run(path: path))
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly; keep it alive for the whole run.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusMenu: StatusMenuController?
    private var settingsWindow: SettingsWindowController?
    private var showSettingsObserver: NSObjectProtocol?

    /// Sent by a second copy of the app to the one already running.
    private static let showSettingsNotification = Notification.Name("com.leonardoramirezr.keyswapo.show-settings")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two copies would remap every key twice (and undo each other's swaps).
        if handOffToRunningInstance() {
            NSApp.terminate(nil)
            return
        }
        MainMenu.install()

        let model = AppModel()
        self.model = model
        statusMenu = StatusMenuController(model: model) { [weak self] in
            self?.showSettings()
        }
        model.onStateChange = { [weak self] in
            self?.statusMenu?.updateButton()
        }
        showSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.showSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.showSettings()
            }
        }

        model.start()
        if model.createdDefaultConfig || !model.hasAccessibility {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    /// Opening the app again (from Finder or Spotlight) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func showSettings() {
        guard let model else { return }
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(model: model)
        }
        settingsWindow?.show()
    }

    private func handOffToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let pid = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != pid }
        guard !others.isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            Self.showSettingsNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
}
