import AppKit
import Carbon.HIToolbox

/// Глобальные хоткеи через Carbon API — срабатывают при любом активном приложении.
/// Хоткей объяснения зарегистрирован всегда; группа полосы — только пока полоса видна.
@MainActor
enum GlobalHotkeyManager {
    /// Что делать по нажатию. Задаётся один раз в `AppDelegate`.
    static var onAction: (HotkeyAction) -> Void = { _ in }

    /// true, если хоткей объяснения зарегистрирован успешно (для чеклиста «Хоткей свободен»).
    private(set) static var explainHotkeyRegistered = false

    private static let signature: OSType = "Scre".utf8.reduce(0) { $0 << 8 | OSType($1) }
    private static let explainID: UInt32 = 1
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var handlerInstalled = false
    private static var overlayEnabled = false

    /// Действия группы полосы, зарегистрированные сейчас. Пусто, когда группа снята.
    private(set) static var registeredOverlayActions: Set<HotkeyAction> = []
    /// Действия группы, чья последняя регистрация не удалась (сочетание занято). Сохраняется после снятия группы.
    static var failedOverlayActions: Set<HotkeyAction> = []

    /// Коды клавиш 1…4 для режимов (явно: kVK_ANSI_* идут не подряд по номерам).
    private static let modeKeyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4]

    /// Группа полосы: id → (код клавиши, модификаторы, действие). Esc и стрелки с ⌘⇧, режимы с ⌃⌥
    /// (⌘⇧3/4/5 заняты системными скриншотами macOS).
    private static let overlayGroup: [(id: UInt32, keyCode: Int, modifiers: Int, action: HotkeyAction)] =
        [
            (2, kVK_Escape, cmdKey | shiftKey, .hide),
            (3, kVK_DownArrow, cmdKey | shiftKey, .pageDown),
            (4, kVK_UpArrow, cmdKey | shiftKey, .pageUp),
        ] + AssistantMode.allCases.map { mode in
            (UInt32(10 + mode.hotkeyNumber), modeKeyCodes[mode.hotkeyNumber - 1], controlKey | optionKey, .setMode(mode))
        }

    /// (Пере)регистрирует хоткей объяснения из настроек. Устанавливает Carbon-обработчик при первом вызове.
    static func start() {
        if !handlerInstalled {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &eventType, nil, nil)
            handlerInstalled = true
        }
        unregister(explainID)
        let shortcut = Settings.current.explainShortcut
        explainHotkeyRegistered = register(explainID, keyCode: shortcut.carbonKeyCode, modifiers: shortcut.carbonModifiers)
    }

    /// Регистрирует (true) или снимает (false) группу: ⌘⇧Esc→.hide, ⌘⇧↓→.pageDown, ⌘⇧↑→.pageUp, ⌃⌥1…4→.setMode.
    static func setOverlayHotkeys(enabled: Bool) {
        guard enabled != overlayEnabled else { return }
        overlayEnabled = enabled
        for hotkey in overlayGroup {
            if enabled {
                if register(hotkey.id, keyCode: UInt32(hotkey.keyCode), modifiers: UInt32(hotkey.modifiers)) {
                    registeredOverlayActions.insert(hotkey.action)
                    failedOverlayActions.remove(hotkey.action)
                } else {
                    failedOverlayActions.insert(hotkey.action)
                }
            } else {
                unregister(hotkey.id)
            }
        }
        if !enabled { registeredOverlayActions = [] }
    }

    fileprivate static func dispatch(id: UInt32) {
        if id == explainID {
            onAction(.explain)
        } else if let hotkey = overlayGroup.first(where: { $0.id == id }) {
            onAction(hotkey.action)
        }
    }

    @discardableResult
    private static func register(_ id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        return true
    }

    private static func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
    }
}

nonisolated private func hotKeyCallback(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr else { return status }
    let hotKeyID = id.id
    Task { @MainActor in GlobalHotkeyManager.dispatch(id: hotKeyID) }
    return noErr
}

private extension ExplainShortcut {
    var carbonKeyCode: UInt32 {
        switch self {
        case .cmdShiftSpace, .cmdOptionSpace, .cmdControlSpace: UInt32(kVK_Space)
        case .cmdShiftE, .cmdOptionE: UInt32(kVK_ANSI_E)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .cmdShiftSpace, .cmdShiftE: UInt32(cmdKey | shiftKey)
        case .cmdOptionSpace, .cmdOptionE: UInt32(cmdKey | optionKey)
        case .cmdControlSpace: UInt32(cmdKey | controlKey)
        }
    }
}
