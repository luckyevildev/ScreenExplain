import AppKit
import SwiftUI

@main
struct ScreenExplainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("ScreenExplain", systemImage: "rectangle.bottomthird.inset.filled") {
            MenuBarPanelView()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate: режим строки меню, глобальные хоткеи, первое открытие настроек

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateOpenAIKeyToKeychain()
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["SCREENEXPLAIN_RENDER_DIR"] {
            Task { await PreviewRenderer.renderAll(to: URL(fileURLWithPath: dir)); NSApp.terminate(nil) }
            return
        }
        #endif
        GlobalHotkeyManager.onAction = { action in
            switch action {
            case .explain: ExplainRunner.shared.trigger()
            case .hide: ExplainRunner.shared.hide()
            case .pageDown: OverlayManager.shared.pageDown()
            case .pageUp: OverlayManager.shared.pageUp()
            case .setMode(let m): UserDefaults.standard.set(m.rawValue, forKey: SettingsKey.assistantMode)
            }
        }
        OverlayManager.shared.bind(to: ExplainRunner.shared)
        GlobalHotkeyManager.start()

        // Настройки открываются, пока не было ни одного удачного прогона или нет доступа к записи экрана.
        if !UserDefaults.standard.bool(forKey: SettingsKey.hasCompletedFirstRun) || !CGPreflightScreenCaptureAccess() {
            SettingsWindowController.shared.show()
        }
        UserDefaults.standard.set(true, forKey: SettingsKey.hasLaunchedBefore)
    }

    /// Ключ OpenAI раньше лежал в UserDefaults (plist читается любым процессом, попадает в бэкапы) — переносим в Keychain.
    private func migrateOpenAIKeyToKeychain() {
        let defaults = UserDefaults.standard
        if let key = defaults.string(forKey: SettingsKey.openAIKey), !key.isEmpty,
           !KeychainStore.write(key, account: KeychainStore.openAIKeyAccount) {
            return // не удалось записать — ключ остаётся в UserDefaults до следующего запуска
        }
        defaults.removeObject(forKey: SettingsKey.openAIKey)
    }

    /// Закрытие окна настроек не завершает приложение: оно живёт в строке меню.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
