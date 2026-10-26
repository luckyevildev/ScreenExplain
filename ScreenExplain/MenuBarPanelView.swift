import AppKit
import SwiftUI

/// Панель, которая открывается по клику на иконку в строке меню.
struct MenuBarPanelView: View {
    @ObservedObject private var runner = ExplainRunner.shared
    @AppStorage(SettingsKey.assistantMode) private var assistantMode: AssistantMode = .explanation
    @AppStorage(SettingsKey.backendMode) private var mode: BackendMode = .lmStudio
    @AppStorage(SettingsKey.codeModel) private var codeModel = ""
    @AppStorage(SettingsKey.explainShortcut) private var explainShortcut: ExplainShortcut = .cmdShiftSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow

            Picker("Режим", selection: $assistantMode) {
                ForEach(AssistantMode.allCases) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                // Занятость читается из GlobalHotkeyManager при каждой перерисовке; группа (пере)регистрируется
                // синхронно в подписке на runner.isOverlayVisible, а runner перерисовывает панель.
                ForEach(Self.listedActions, id: \.self) { action in
                    Button { perform(action) } label: {
                        hotkeyRow(
                            action.title,
                            action.display(explainShortcut: explainShortcut),
                            isTaken: GlobalHotkeyManager.failedOverlayActions.contains(action)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                hotkeyRow("Режим", "⌃⌥1…4", isTaken: Self.modeActions.contains(where: GlobalHotkeyManager.failedOverlayActions.contains))
            }

            Divider()

            HStack {
                Button("Настройки…") { SettingsWindowController.shared.show() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Выход") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }

    /// Действия смены режима сведены в одну строку «Режим».
    private static let listedActions = HotkeyAction.all.filter { !modeActions.contains($0) }
    private static let modeActions = AssistantMode.allCases.map(HotkeyAction.setMode)

    /// Клик по строке действия делает то же, что его хоткей.
    private func perform(_ action: HotkeyAction) {
        switch action {
        case .explain: ExplainRunner.shared.trigger()
        case .hide: ExplainRunner.shared.hide()
        case .pageDown: OverlayManager.shared.pageDown()
        case .pageUp: OverlayManager.shared.pageUp()
        case .setMode: break // строка «Режим» — текст, режим выбирается сегментами выше
        }
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            stageTitle
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text("\(mode.rawValue) · \(codeModel.isEmpty ? "модель не выбрана" : codeModel)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var stageTitle: some View {
        if case .thinking = runner.phase {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(runner.stageTitle(now: context.date))
            }
        } else {
            Text(runner.stageTitle(now: .now))
        }
    }

    private var dotColor: Color {
        switch runner.phase {
        case .idle, .done: .green
        case .failed: .red
        case .capturing, .thinking, .streaming: .yellow
        }
    }

    // MARK: Hotkeys

    /// `isTaken`: сочетание не удалось зарегистрировать — вместо него серая пометка.
    private func hotkeyRow(_ title: String, _ display: String, isTaken: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isTaken {
                Text("занято другим приложением")
                    .foregroundStyle(.secondary)
            } else {
                Text(display)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
