import AppKit
import Combine

/// Состояние одной строки чеклиста «Готовность».
enum ReadinessState: Equatable {
    case checking
    case ok(String)
    case problem(String)

    var isOK: Bool {
        if case .ok = self { return true }
        return false
    }
}

/// Проверки готовности: запись экрана, модель, хоткей. Список моделей отдаёт и в «Все настройки».
@MainActor
final class ReadinessChecker: ObservableObject {
    @Published private(set) var screenRecording: ReadinessState = .checking
    @Published private(set) var model: ReadinessState = .checking
    @Published private(set) var hotkey: ReadinessState = .checking
    @Published private(set) var availableModels: [String] = []

    private var isChecking = false
    private var needsRecheck = false
    /// Системный запрос записи экрана уже показывали: повторное «Разрешить» открывает System Settings.
    private var requestedOnce = false

    var allOK: Bool {
        screenRecording.isOK && model.isOK && hotkey.isOK
    }

    func checkAll() async {
        // Вызов во время проверки не запускает вторую параллельно, а просит повторить после текущей.
        guard !isChecking else {
            needsRecheck = true
            return
        }
        isChecking = true
        defer { isChecking = false }

        repeat {
            needsRecheck = false
            checkScreenRecording()
            await checkModel()
            checkHotkey()
        } while needsRecheck
    }

    /// Первое нажатие — системный запрос; если разрешения всё ещё нет, следующее открывает System Settings.
    func requestScreenRecording() {
        if requestedOnce, case .problem = screenRecording {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        } else {
            requestedOnce = true
            _ = CGRequestScreenCaptureAccess()
        }
        Task { await checkAll() }
    }

    private func checkScreenRecording() {
        screenRecording = CGPreflightScreenCaptureAccess()
            ? .ok("Запись экрана разрешена")
            : .problem("Нет разрешения на запись экрана")
    }

    private func checkModel() async {
        model = .checking
        do {
            let ids = try await LLMClient(settings: .current).listModels()
            availableModels = ids
            guard let first = ids.first else {
                model = .problem("Модели не загружены")
                return
            }
            // Первая модель подставляется только в пустое поле (@AppStorage-пикеры подхватят);
            // выбранную пользователем модель, которой нет на сервере, не заменяем, а сообщаем о ней.
            let defaults = UserDefaults.standard
            var missing: [String] = []
            for key in [SettingsKey.visionModel, SettingsKey.codeModel] {
                let stored = defaults.string(forKey: key) ?? ""
                if stored.isEmpty {
                    defaults.set(first, forKey: key)
                } else if !ids.contains(stored) && !missing.contains(stored) {
                    missing.append(stored)
                }
            }
            if !missing.isEmpty {
                model = .problem("Модель \(missing.joined(separator: ", ")) не найдена на сервере")
                return
            }
            let settings = Settings.current
            model = .ok("Модель: \(settings.backendMode.rawValue) · \(settings.visionModel) / \(settings.codeModel)")
        } catch {
            availableModels = []
            model = .problem(error.localizedDescription)
        }
    }

    private func checkHotkey() {
        let shortcut = Settings.current.explainShortcut
        hotkey = GlobalHotkeyManager.explainHotkeyRegistered
            ? .ok("Хоткей \(shortcut.rawValue) свободен")
            : .problem("Хоткей \(shortcut.rawValue) занят другим приложением")
    }
}

#if DEBUG
extension ReadinessChecker {
    /// Все строки зелёные, проверки не запускаются: для офлайн-рендера окна настроек.
    static func preview() -> ReadinessChecker {
        let checker = ReadinessChecker()
        checker.screenRecording = .ok("Запись экрана разрешена")
        checker.model = .ok("Модель: LM Studio · qwen2.5-vl-7b-instruct / qwen2.5-coder-7b-instruct")
        checker.hotkey = .ok("Хоткей ⌘⇧Space свободен")
        checker.availableModels = ["qwen2.5-coder-7b-instruct", "qwen2.5-vl-7b-instruct"]
        checker.isChecking = true // checkAll() теперь только помечает needsRecheck и выходит
        return checker
    }
}
#endif
