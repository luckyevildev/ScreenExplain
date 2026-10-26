#if DEBUG
import AppKit
import SwiftUI

/// Офлайн-рендер картинок для README: реальные вью приложения в невидимом окне → PNG.
/// Запуск: `SCREENEXPLAIN_RENDER_DIR=/путь ScreenExplain.app/Contents/MacOS/ScreenExplain`,
/// обычно через `scripts/render-previews.sh`, который потом собирает GIF.
enum PreviewRenderer {
    static let sceneSize = CGSize(width: 1440, height: 900)

    static func renderAll(to dir: URL) async {
        OverlayTheme.useFlatBackground()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gifDir = dir.appendingPathComponent("gif")
        try? FileManager.default.createDirectory(at: gifDir, withIntermediateDirectories: true)

        // Скриншоты.
        await render(OverlayScene(runner: .preview(phase: .done, text: SampleText.codeAnswer)),
                     size: sceneSize, to: dir.appendingPathComponent("overlay-answer.png"))
        await render(OverlayScene(runner: .preview(phase: .thinking(since: .now.addingTimeInterval(-6)), text: "")),
                     size: sceneSize, to: dir.appendingPathComponent("overlay-thinking.png"))
        await render(PanelScene(), size: CGSize(width: 360, height: 420), to: dir.appendingPathComponent("menubar-panel.png"))
        await render(SettingsScene(), size: CGSize(width: 600, height: 700), to: dir.appendingPathComponent("settings.png"))

        // Кадры GIF: название, длительность в секундах, состояние.
        let frames: [(String, Double, ExplainRunner?)] = [
            ("01-page", 0.9, nil),
            ("02-capturing", 0.7, .preview(phase: .capturing, text: "")),
            ("03-thinking", 1.0, .preview(phase: .thinking(since: .now.addingTimeInterval(-2)), text: "")),
            ("04-stream", 0.45, .preview(phase: .streaming, text: SampleText.answerPrefix(60))),
            ("05-stream", 0.45, .preview(phase: .streaming, text: SampleText.answerPrefix(140))),
            ("06-stream", 0.6, .preview(phase: .streaming, text: SampleText.answerPrefix(260))),
            ("07-done", 3.0, .preview(phase: .done, text: SampleText.explanation)),
        ]
        var list = ""
        for (name, duration, runner) in frames {
            let file = gifDir.appendingPathComponent("\(name).png")
            await render(OverlayScene(runner: runner), size: sceneSize, to: file)
            list += "file '\(file.path)'\nduration \(duration)\n"
        }
        // ffmpeg concat: последний кадр повторяется, иначе его длительность теряется.
        if let last = frames.last { list += "file '\(gifDir.appendingPathComponent("\(last.0).png").path)'\n" }
        try? list.write(to: gifDir.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
    }

    /// Окно с alpha 0 на экране: раскладка и Retina-масштаб настоящие, пользователь ничего не видит.
    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) async {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(500))
        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
        window.orderOut(nil)
    }
}

// MARK: - Сцены

/// Страница онлайн-теста с полосой внизу (runner == nil: только страница).
private struct OverlayScene: View {
    let runner: ExplainRunner?
    @StateObject private var paging = OverlayPagingModel()
    @State private var barHeight: CGFloat = 56

    var body: some View {
        ZStack(alignment: .bottom) {
            MockTestPage()
            if let runner {
                OverlayBarView(runner: runner, paging: paging) { barHeight = $0 }
                    .frame(height: max(56, barHeight))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .onAppear { paging.screenHeight = PreviewRenderer.sceneSize.height }
    }
}

private struct PanelScene: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.86, green: 0.90, blue: 0.96), Color(red: 0.93, green: 0.94, blue: 0.97)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                    Text("12:41").monospacedDigit()
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(.white.opacity(0.6))
                MenuBarPanelView()
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                    .padding(.top, 6)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct SettingsScene: View {
    var body: some View {
        ZStack {
            Color(red: 0.80, green: 0.83, blue: 0.88)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) {
                        Circle().fill($0).frame(width: 12, height: 12)
                    }
                    Spacer()
                    Text("ScreenExplain").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Color.clear.frame(width: 52, height: 1)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color(nsColor: .windowBackgroundColor))
                SettingsView(readiness: .preview())
                    .frame(width: 560, height: 620)
            }
            .frame(width: 560)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }
}

/// Страница онлайн-теста: условие слева, редактор справа.
private struct MockTestPage: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<3) { _ in Circle().fill(Color(white: 0.82)).frame(width: 11, height: 11) }
                Text("Онлайн-тест · Задача 2 из 5 · 42:17")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.3))
                    .padding(.leading, 10)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.white)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("2. Two Sum").font(.system(size: 22, weight: .semibold))
                    Text("Дан массив целых чисел nums и число target. Верните индексы двух чисел, сумма которых равна target. Гарантируется ровно одно решение; один элемент дважды использовать нельзя.")
                    Text("Пример: nums = [2, 7, 11, 15], target = 9 → [0, 1]")
                        .font(.system(size: 14, design: .monospaced))
                    Text("Ограничения: 2 ≤ nums.length ≤ 10⁴, −10⁹ ≤ nums[i] ≤ 10⁹.")
                        .foregroundStyle(Color(white: 0.4))
                    Spacer()
                }
                .font(.system(size: 15))
                .foregroundStyle(Color(white: 0.15))
                .padding(28)
                .frame(width: 480, alignment: .topLeading)
                .background(.white)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(editorLines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 18) {
                            Text("\(index + 1)").foregroundStyle(Color(white: 0.45)).frame(width: 24, alignment: .trailing)
                            Text(line)
                        }
                        .frame(height: 24)
                    }
                    Spacer()
                }
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Color(red: 0.80, green: 0.82, blue: 0.86))
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            }
        }
        .background(Color(white: 0.96))
    }

    private var editorLines: [String] {
        ["def twoSum(nums, target):", "    # TODO", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
    }
}

// MARK: - Тексты

private enum SampleText {
    static let explanation = """
    На экране задача Two Sum: найти индексы двух чисел с суммой target. Решение за один проход: храним в словаре `seen` уже встреченные числа и их индексы, для каждого `x` проверяем, видели ли `target - x`.

    ```python
    def twoSum(nums, target):
        seen = {}
        for i, x in enumerate(nums):
            if target - x in seen:
                return [seen[target - x], i]
            seen[x] = i
    ```

    Сложность O(n) по времени и памяти. Крайние случаи: дубликаты (словарь хранит первый индекс, второй приходит как `i`) и отрицательные числа.
    """

    static let codeAnswer = """
    Задача Two Sum. Хеш-таблица, один проход, O(n).

    ```python
    def twoSum(nums, target):
        seen = {}  # число -> индекс
        for i, x in enumerate(nums):
            if target - x in seen:
                return [seen[target - x], i]
            seen[x] = i
        return []
    ```

    Проверка: nums = [2, 7, 11, 15], target = 9 → [0, 1].
    """

    static func answerPrefix(_ count: Int) -> String {
        String(explanation.prefix(count))
    }
}
#endif
