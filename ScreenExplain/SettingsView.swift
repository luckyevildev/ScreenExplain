import AppKit
import SwiftUI

/// Окно настроек: чеклист готовности, шпаргалка хоткеев, кнопки и раскрываемые «Все настройки».
struct SettingsView: View {
    @StateObject private var readiness: ReadinessChecker
    @ObservedObject private var runner = ExplainRunner.shared
    @State private var showAdvanced = false

    init(readiness: ReadinessChecker? = nil) {
        _readiness = StateObject(wrappedValue: readiness ?? ReadinessChecker())
    }

    @AppStorage(SettingsKey.backendMode) private var backendMode: BackendMode = .lmStudio
    @AppStorage(SettingsKey.lmStudioBaseURL) private var lmStudioBaseURL = Settings.defaultLMStudioBaseURL
    @AppStorage(SettingsKey.visionModel) private var visionModel = ""
    @AppStorage(SettingsKey.codeModel) private var codeModel = ""
    @AppStorage(SettingsKey.explainShortcut) private var explainShortcut: ExplainShortcut = .cmdShiftSpace
    @AppStorage(SettingsKey.captureSource) private var captureSource: CaptureSource = .display
    @AppStorage(SettingsKey.selectedWindowKey) private var selectedWindowKey = ""

    /// Пробный прогон возможен, когда всё готово и (для окна) окно выбрано.
    private var canExplain: Bool {
        readiness.allOK && (captureSource == .display || !selectedWindowKey.isEmpty)
    }

    var body: some View {
        ScrollViewReader { proxy in
            form(proxy)
        }
    }

    private func form(_ proxy: ScrollViewProxy) -> some View {
        Form {
            Section("Готовность") {
                ReadinessRow(state: readiness.screenRecording, actionTitle: "Разрешить") {
                    readiness.requestScreenRecording()
                }
                ReadinessRow(state: readiness.model, actionTitle: "Настроить") {
                    openAdvanced(at: AdvancedSettingsView.modelRowID, proxy: proxy)
                }
                ReadinessRow(state: readiness.hotkey, actionTitle: "Сменить") {
                    openAdvanced(at: AdvancedSettingsView.hotkeyRowID, proxy: proxy)
                }
            }

            Section("Шпаргалка") {
                ForEach(HotkeyAction.all, id: \.self) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        // Читается при перерисовке: группа полосы (пере)регистрируется по runner.isOverlayVisible.
                        if GlobalHotkeyManager.failedOverlayActions.contains(action) {
                            Text("занято другим приложением")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(action.display(explainShortcut: explainShortcut))
                                .monospaced()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.quaternary))
                        }
                    }
                }
            }

            Section {
                HStack {
                    Button(runner.phase.isBusy ? "Остановить" : "Проверить на этом экране") {
                        ExplainRunner.shared.trigger()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!runner.phase.isBusy && !canExplain)
                    Spacer()
                    Button("Все настройки") { showAdvanced.toggle() }
                }
                if !runner.lastMessage.isEmpty {
                    Text(runner.lastMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showAdvanced {
                Section("Все настройки") {
                    AdvancedSettingsView(readiness: readiness)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .task { await readiness.checkAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Скрытое окно не перепроверяет (сетевой запрос моделей) при каждой активации приложения.
            guard SettingsWindowController.shared.isWindowVisible else { return }
            Task { await readiness.checkAll() }
        }
        .onChange(of: backendMode) { recheck() }
        .onChange(of: lmStudioBaseURL) { recheck() }
        .onChange(of: visionModel) { recheck() }
        .onChange(of: codeModel) { recheck() }
        .onChange(of: explainShortcut) {
            GlobalHotkeyManager.start()
            recheck()
        }
    }

    /// Раскрывает «Все настройки» и прокручивает к нужной строке, когда секция уже вставлена.
    private func openAdvanced(at rowID: String, proxy: ScrollViewProxy) {
        showAdvanced = true
        Task { @MainActor in
            withAnimation { proxy.scrollTo(rowID, anchor: .top) }
        }
    }

    private func recheck() {
        Task { await readiness.checkAll() }
    }
}

/// Строка чеклиста: индикатор, текст, кнопка действия (только при проблеме).
struct ReadinessRow: View {
    let state: ReadinessState
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            indicator
            Text(text)
            Spacer()
            if case .problem = state {
                Button(actionTitle, action: action)
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .checking:
            Circle().fill(.gray).frame(width: 10, height: 10)
            ProgressView().controlSize(.small)
        case .ok:
            mark("✓", color: .green)
        case .problem:
            mark("!", color: .orange)
        }
    }

    private func mark(_ symbol: String, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                Text(symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var text: String {
        switch state {
        case .checking: "Проверяю…"
        case .ok(let text), .problem(let text): text
        }
    }
}
