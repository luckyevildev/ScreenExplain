import AppKit
import SwiftUI

/// Единственное окно настроек. Закрытие только прячет его, приложение продолжает жить в строке меню.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// Окно настроек сейчас на экране (проверка готовности при активации приложения только тогда).
    var isWindowVisible: Bool { window?.isVisible == true }

    private override init() {}

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // После закрытия окна приложение спрятано (NSApp.hide), его надо показать обратно.
        if NSApp.isHidden { NSApp.unhide(nil) }
        window.makeKeyAndOrderFront(nil)
        // Окно настроек — единственное место, где приложение активируется.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Закрытие окна прячет приложение, и фокус возвращается приложению, которое было активно до настроек.
    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenExplain"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        return window
    }
}
