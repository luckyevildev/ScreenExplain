import SwiftUI

/// Строки секции «Все настройки». Список моделей берётся из `ReadinessChecker`.
struct AdvancedSettingsView: View {
    /// id строк для прокрутки из чеклиста («Настроить», «Сменить»).
    static let modelRowID = "advanced.model"
    static let hotkeyRowID = "advanced.hotkey"

    @ObservedObject var readiness: ReadinessChecker

    @AppStorage(SettingsKey.backendMode) private var backendMode: BackendMode = .lmStudio
    /// Ключ живёт в Keychain, не в UserDefaults: @State плюс запись в `KeychainStore` при каждом изменении.
    @State private var openAIKey = KeychainStore.read(account: KeychainStore.openAIKeyAccount) ?? ""
    @AppStorage(SettingsKey.lmStudioBaseURL) private var lmStudioBaseURL = Settings.defaultLMStudioBaseURL
    @AppStorage(SettingsKey.visionModel) private var visionModel = ""
    @AppStorage(SettingsKey.codeModel) private var codeModel = ""
    @AppStorage(SettingsKey.captureSource) private var captureSource: CaptureSource = .display
    @AppStorage(SettingsKey.selectedDisplayID) private var selectedDisplayID = ""
    @AppStorage(SettingsKey.selectedWindowKey) private var selectedWindowKey = ""
    @AppStorage(SettingsKey.explainShortcut) private var explainShortcut: ExplainShortcut = .cmdShiftSpace
    @AppStorage(SettingsKey.overlayOpacity) private var overlayOpacity: Double = Settings.defaultOverlayOpacity
    @AppStorage(SettingsKey.overlayFontSize) private var overlayFontSize: Double = Settings.defaultOverlayFontSize

    @ObservedObject private var runner = ExplainRunner.shared
    @State private var displays: [DisplayItem] = []
    @State private var windows: [WindowItem] = []
    @State private var isLoadingSources = false

    private var displaySelection: Binding<DisplayItem?> {
        Binding(
            get: { displays.first { String($0.displayID) == selectedDisplayID } ?? displays.first },
            set: { selectedDisplayID = $0.map { String($0.displayID) } ?? "" }
        )
    }

    private var windowSelection: Binding<WindowItem?> {
        Binding(
            get: { WindowKey(selectedWindowKey)?.match(in: windows) ?? windows.first },
            set: { selectedWindowKey = $0?.key ?? "" }
        )
    }

    var body: some View {
        Picker("Бэкенд", selection: $backendMode) {
            ForEach(BackendMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)

        if backendMode == .openAI {
            SecureField("OpenAI API Key", text: $openAIKey)
                .onChange(of: openAIKey) {
                    KeychainStore.write(openAIKey, account: KeychainStore.openAIKeyAccount)
                    Task { await readiness.checkAll() }
                }
        } else {
            TextField("LM Studio base URL", text: $lmStudioBaseURL)
        }

        if readiness.availableModels.isEmpty {
            Text("Модели не загружены")
                .foregroundStyle(.secondary)
                .id(Self.modelRowID)
        } else {
            modelPicker("Vision‑модель", selection: $visionModel)
                .id(Self.modelRowID)
            modelPicker("Кодовая модель", selection: $codeModel)
        }

        Picker("Источник захвата", selection: $captureSource) {
            ForEach(CaptureSource.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .onAppear { reloadCaptureSources() }
        .onChange(of: captureSource) { reloadCaptureSources() }

        captureSourcePicker

        Picker("Горячая клавиша", selection: $explainShortcut) {
            ForEach(ExplainShortcut.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.menu)
        .id(Self.hotkeyRowID)

        HStack {
            Slider(value: $overlayOpacity, in: 0.40...0.95) {
                Text("Непрозрачность полосы")
            }
            Text("\(Int(overlayOpacity * 100)) %")
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }

        HStack {
            Slider(value: $overlayFontSize, in: 13...24, step: 1) {
                Text("Размер шрифта полосы")
            }
            Text("\(Int(overlayFontSize)) pt")
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }

    private var captureSourcePicker: some View {
        HStack {
            if isLoadingSources {
                ProgressView().controlSize(.small)
            }
            switch captureSource {
            case .display:
                Picker("Дисплей", selection: displaySelection) {
                    Text("Авто (первый)").tag(DisplayItem?.none)
                    ForEach(displays) { Text($0.name).tag(Optional($0)) }
                }
                .disabled(displays.isEmpty)
            case .window:
                Picker("Окно", selection: windowSelection) {
                    Text("Не выбрано").tag(WindowItem?.none)
                    ForEach(windows) { Text($0.displayName).tag(Optional($0)) }
                }
                .disabled(windows.isEmpty)
            }
            Button("Обновить") { reloadCaptureSources() }
        }
    }

    private func modelPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(readiness.availableModels, id: \.self) { Text($0).tag($0) }
            // Сохранённая модель, которой нет на сервере, не подменяется (см. ReadinessChecker) — показываем её как есть.
            let stored = selection.wrappedValue
            if !stored.isEmpty && !readiness.availableModels.contains(stored) {
                Text("\(stored) (нет на сервере)").tag(stored)
            }
        }
    }

    private func reloadCaptureSources() {
        isLoadingSources = true
        Task {
            defer { isLoadingSources = false }
            do {
                async let d = ScreenCapture.availableDisplays()
                async let w = ScreenCapture.availableWindows()
                displays = try await d
                windows = try await w
                runner.lastMessage = ""
            } catch {
                runner.lastMessage = "Ошибка загрузки источников: \(error.localizedDescription)"
            }
        }
    }
}
