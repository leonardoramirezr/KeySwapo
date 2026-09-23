import AppKit

/// The menu bar item and its menu.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let model: AppModel
    private let showSettings: @MainActor () -> Void

    init(model: AppModel, showSettings: @escaping @MainActor () -> Void) {
        self.model = model
        self.showSettings = showSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        updateButton()
    }

    func updateButton() {
        guard let button = statusItem.button else { return }
        let symbol = model.needsAttention ? "exclamationmark.triangle" : "keyboard"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "KeySwapo") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "KS"
        }
        button.appearsDisabled = !model.isEnabled
        button.toolTip = "KeySwapo: \(model.statusText)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabledItem("KeySwapo: \(model.statusText)"))
        if !model.hasAccessibility {
            menu.addItem(actionItem("Conceder permiso de Accesibilidad…", #selector(openAccessibilitySettings)))
        } else if !model.isTapRunning {
            menu.addItem(actionItem("Reiniciar KeySwapo", #selector(relaunch)))
        }
        if !model.configErrors.isEmpty {
            menu.addItem(actionItem("Ver errores de la configuración…", #selector(openSettings)))
        }

        menu.addItem(.separator())
        let toggle = actionItem("Remapeo activado", #selector(toggleEnabled))
        toggle.state = model.isEnabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())
        if model.rules.isEmpty {
            menu.addItem(disabledItem("Sin reglas"))
        }
        for rule in model.rules {
            let item = disabledItem("\(rule.description)  (\(pluralize(rule.manipulators.count, "cambio", "cambios")))")
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Configuración…", #selector(openSettings), key: ","))
        menu.addItem(actionItem("Recargar \(model.store.fileName)", #selector(reloadConfig), key: "r"))
        menu.addItem(actionItem("Mostrar \(model.store.fileName) en Finder", #selector(revealConfig)))
        let login = actionItem("Abrir al iniciar sesión", #selector(toggleLaunchAtLogin))
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem("Salir de KeySwapo", #selector(quit), key: "q"))
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleEnabled() {
        model.isEnabled.toggle()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func reloadConfig() {
        model.reloadConfig()
    }

    @objc private func revealConfig() {
        model.revealConfigInFinder()
    }

    @objc private func openAccessibilitySettings() {
        model.openAccessibilitySettings()
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.launchAtLogin)
    }

    @objc private func relaunch() {
        model.relaunch()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
