import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement
import Sparkle

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    let hotKey = HotKey()
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    var panel: FloatingPanel!
    var statusItem: NSStatusItem!
    var positioned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildStatusItem()
        hotKey.onPress = { [weak self] in MainActor.assumeIsolated { self?.toggle() } }
        store.hotkeyOK = hotKey.register(keyCode: kVK_ANSI_T, modifiers: optionKey)
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, e.window === self.panel else { return e }
                return self.store.handle(e) ? nil : e
            }
        }
        show()
    }

    private func buildPanel() {
        let p = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 700),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true

        let fx = NSVisualEffectView()
        fx.material = .popover
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 18
        fx.layer?.cornerCurve = .continuous
        fx.layer?.masksToBounds = true
        fx.layer?.borderWidth = 0.5
        fx.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let host = NSHostingView(rootView: RootView().environmentObject(store))
        host.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            host.topAnchor.constraint(equalTo: fx.topAnchor),
            host.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        p.contentView = fx
        panel = p
    }

    private var mouseScreen: NSScreen {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
    }

    private func position() {
        let screen = mouseScreen
        let v = screen.visibleFrame
        let h = min(780, v.height - 32)
        panel.setFrame(NSRect(x: v.maxX - 380 - 14, y: v.midY - h / 2, width: 380, height: h), display: true)
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        if !positioned || panel.screen != mouseScreen { position(); positioned = true }
        store.panelDidShow()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.panel.orderOut(nil) })
    }

    // MARK: - Barra de menús

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "TaskOut")
        let menu = NSMenu()
        menu.addItem(withTitle: store.hotkeyOK ? "Mostrar / ocultar  (⌥T)" : "Mostrar / ocultar  (⌥T está ocupado por otra app)",
                     action: #selector(menuToggle), keyEquivalent: "").target = self
        let login = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let upd = NSMenuItem(title: "Buscar actualizaciones…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        upd.target = updater
        menu.addItem(upd)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de TaskOut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func menuToggle() { toggle() }

    @objc private func toggleLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } catch { NSSound.beep() }
    }
}
