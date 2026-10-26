import Foundation

enum BackendMode: String, CaseIterable, Identifiable {
    case lmStudio = "LM Studio"
    case openAI = "OpenAI"

    var id: String { rawValue }
}

enum AssistantMode: String, CaseIterable, Identifiable {
    case explanation = "Пояснение"
    case codeWriting = "Написание кода"
    case problemSolving = "Решение задач"
    case refactoring = "Рефакторинг"

    var id: String { rawValue }
}

extension AssistantMode {
    /// Короткая подпись для сегментного контрола.
    var shortTitle: String {
        switch self {
        case .explanation: "Пояснение"
        case .codeWriting: "Код"
        case .problemSolving: "Задача"
        case .refactoring: "Рефакторинг"
        }
    }

    /// 1…4 для хоткеев ⌃⌥1…4.
    var hotkeyNumber: Int {
        switch self {
        case .explanation: 1
        case .codeWriting: 2
        case .problemSolving: 3
        case .refactoring: 4
        }
    }
}

enum ExplainShortcut: String, CaseIterable, Identifiable {
    case cmdShiftSpace = "⌘⇧Space"
    case cmdShiftE = "⌘⇧E"
    case cmdOptionSpace = "⌘⌥Space"
    case cmdOptionE = "⌘⌥E"
    case cmdControlSpace = "⌘⌃Space"

    var id: String { rawValue }
}

/// Действие глобального хоткея.
enum HotkeyAction: Hashable {
    case explain, hide, pageDown, pageUp
    case setMode(AssistantMode)

    /// Все действия в порядке показа в шпаргалке и панели.
    static let all: [HotkeyAction] = [
        .explain, .hide, .pageDown, .pageUp,
        .setMode(.explanation), .setMode(.codeWriting),
        .setMode(.problemSolving), .setMode(.refactoring),
    ]

    var title: String {
        switch self {
        case .explain: "Объяснить экран / отменить"
        case .hide: "Скрыть оверлей"
        case .pageDown: "Листать вниз"
        case .pageUp: "Листать вверх"
        case .setMode(let mode): "Режим: \(mode.rawValue)"
        }
    }

    /// Для `.explain` сочетание берётся из настроек, остальные фиксированы.
    func display(explainShortcut: ExplainShortcut) -> String {
        switch self {
        case .explain: explainShortcut.rawValue
        case .hide: "⌘⇧Esc"
        case .pageDown: "⌘⇧↓"
        case .pageUp: "⌘⇧↑"
        case .setMode(let mode): "⌃⌥\(mode.hotkeyNumber)"
        }
    }
}

/// Ключи UserDefaults. Их же использует `@AppStorage` в `SettingsView` и `AdvancedSettingsView`.
enum SettingsKey {
    static let backendMode = "backendMode"
    static let assistantMode = "assistantMode"
    /// Только для миграции в Keychain при запуске (см. `AppDelegate`); сам ключ хранит `KeychainStore`.
    static let openAIKey = "openAIKey"
    static let lmStudioBaseURL = "lmStudioBaseURL"
    static let visionModel = "visionModel"
    static let codeModel = "codeModel"
    static let captureSource = "captureSource"
    static let selectedDisplayID = "selectedDisplayID"
    static let selectedWindowKey = "selectedWindowKey"
    static let explainShortcut = "explainShortcut"
    static let overlayOpacity = "overlayOpacity"
    static let overlayFontSize = "overlayFontSize"
    static let hasLaunchedBefore = "hasLaunchedBefore"
    /// true после первого прогона, дошедшего до `.done`.
    static let hasCompletedFirstRun = "hasCompletedFirstRun"
}

/// Снимок настроек для кода вне SwiftUI (глобальный хоткей, `ExplainRunner`).
struct Settings {
    static let defaultLMStudioBaseURL = "http://localhost:1234/v1"
    static let defaultOverlayOpacity = 0.70
    static let defaultOverlayFontSize = 16.0

    let backendMode: BackendMode
    let assistantMode: AssistantMode
    let openAIKey: String
    let lmStudioBaseURL: String
    let visionModel: String
    let codeModel: String
    let captureSource: CaptureSource
    let selectedDisplayID: UInt32?
    let selectedWindowKey: String
    let explainShortcut: ExplainShortcut

    static var current: Settings {
        let defaults = UserDefaults.standard
        func string(_ key: String, _ fallback: String = "") -> String {
            defaults.string(forKey: key) ?? fallback
        }
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        return Settings(
            backendMode: value(SettingsKey.backendMode, BackendMode.lmStudio),
            assistantMode: value(SettingsKey.assistantMode, AssistantMode.explanation),
            openAIKey: KeychainStore.read(account: KeychainStore.openAIKeyAccount) ?? "",
            lmStudioBaseURL: string(SettingsKey.lmStudioBaseURL, defaultLMStudioBaseURL),
            visionModel: string(SettingsKey.visionModel),
            codeModel: string(SettingsKey.codeModel),
            captureSource: value(SettingsKey.captureSource, CaptureSource.display),
            selectedDisplayID: defaults.string(forKey: SettingsKey.selectedDisplayID).flatMap(UInt32.init),
            selectedWindowKey: string(SettingsKey.selectedWindowKey),
            explainShortcut: value(SettingsKey.explainShortcut, ExplainShortcut.cmdShiftSpace)
        )
    }
}
