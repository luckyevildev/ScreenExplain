import AppKit
import Combine
import ScreenCaptureKit

/// Стадия рана «объяснить экран».
enum ExplainPhase: Equatable {
    case idle
    case capturing
    case thinking(since: Date)
    case streaming
    case done
    case failed(String)       // текст ошибки без префикса «Ошибка: »

    var isBusy: Bool {
        switch self {
        case .capturing, .thinking, .streaming: true
        case .idle, .done, .failed: false
        }
    }
}

/// Логика «объяснить экран». Вызывается из окна настроек и по глобальному хоткею (когда окно в трее),
/// поэтому читает настройки из `Settings.current`, а не из SwiftUI-состояния.
@MainActor
final class ExplainRunner: ObservableObject {
    static let shared = ExplainRunner()

    @Published private(set) var phase: ExplainPhase = .idle
    /// Накопленный ответ кодовой модели.
    @Published private(set) var text = ""
    @Published private(set) var isOverlayVisible = false
    /// Сообщения чеклиста/настроек (ошибка загрузки моделей), не трогает `phase`.
    @Published var lastMessage = ""

    private var current: Task<Void, Never>?
    /// Дельты, ещё не переданные в `text`: публикуем не чаще ~15 Гц, иначе полоса перерисовывается на каждый токен.
    private var pendingText = ""
    private var flushTask: Task<Void, Never>?
    private static let flushInterval: Duration = .milliseconds(66)

    private init() {}

    /// Заголовок стадии для полосы и панели.
    func stageTitle(now: Date) -> String {
        switch phase {
        case .idle: "Готов"
        case .capturing: "Снимаю экран…"
        case .thinking(let since): "Думаю… \(Int(now.timeIntervalSince(since))) с"
        case .streaming: "Отвечаю…"
        case .done: "Готово"
        case .failed(let message): "Ошибка: \(message)"
        }
    }

    /// Хоткей объяснения: во время рана — отмена, иначе проверка настроек и новый ран.
    func trigger() {
        if phase.isBusy {
            cancel()
            return
        }

        let settings = Settings.current
        if settings.visionModel.isEmpty || settings.codeModel.isEmpty {
            fail("Выберите модели в настройках")
            return
        }
        if settings.captureSource == .window && settings.selectedWindowKey.isEmpty {
            fail("Выберите окно в настройках")
            return
        }

        discardPending()
        text = ""
        phase = .capturing
        isOverlayVisible = true
        current = Task { await runExplain(settings) }
    }

    /// Отменяет текущий ран и скрывает полосу.
    func cancel() {
        current?.cancel()
        current = nil
        flushPending()
        phase = .idle
        isOverlayVisible = false
    }

    /// ⌘⇧Esc: скрыть полосу и сбросить ответ (идущий ран тоже отменяется).
    func hide() {
        cancel()
        text = ""
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        isOverlayVisible = true
    }

    /// Копит дельту и, если сброс ещё не запланирован, планирует его через `flushInterval`.
    private func appendDelta(_ delta: String) {
        pendingText += delta
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.flushInterval) } catch { return }
            self?.flushPending()
        }
    }

    /// Сразу переносит накопленное в `text` (по таймеру, в конце потока, при ошибке и отмене).
    private func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingText.isEmpty else { return }
        text += pendingText
        pendingText = ""
    }

    private func discardPending() {
        flushTask?.cancel()
        flushTask = nil
        pendingText = ""
    }

    private func runExplain(_ settings: Settings) async {
        do {
            let image = try await ScreenCapture.capture(
                source: settings.captureSource,
                displayID: settings.selectedDisplayID,
                windowKey: settings.selectedWindowKey,
                excludingWindowNumbers: OverlayManager.shared.panelWindowNumber.map { [$0] } ?? []
            )
            try Task.checkCancellation()
            phase = .thinking(since: .now)
            for try await delta in LLMClient(settings: settings).explainStream(image: image) {
                try Task.checkCancellation()
                // SSE может прислать пустую дельту (чанк только с role) — «Отвечаю…» только с первым текстом.
                if phase != .streaming && !delta.isEmpty { phase = .streaming }
                appendDelta(delta)
            }
            // При отмене поток просто завершается, без ошибки.
            try Task.checkCancellation()
            flushPending()
            if text.isEmpty { throw LLMClientError.emptyResponse }
            phase = .done
            // Первый удачный прогон: дальше окно настроек при запуске не открывается (если есть доступ к экрану).
            UserDefaults.standard.set(true, forKey: SettingsKey.hasCompletedFirstRun)
        } catch {
            // Отменивший (cancel/hide) уже выставил .idle; не трогаем состояние — там может идти новый ран.
            if Task.isCancelled { return }
            flushPending()
            if let streamError = error as? SCStreamError, streamError.code == .userDeclined {
                fail("Нет разрешения на запись экрана")
            } else {
                fail(error.localizedDescription)
            }
        }
    }
}

#if DEBUG
extension ExplainRunner {
    /// Экземпляр с заданным состоянием для офлайн-рендера картинок (см. PreviewRenderer).
    static func preview(phase: ExplainPhase, text: String) -> ExplainRunner {
        let runner = ExplainRunner()
        runner.phase = phase
        runner.text = text
        runner.isOverlayVisible = true
        return runner
    }
}
#endif
