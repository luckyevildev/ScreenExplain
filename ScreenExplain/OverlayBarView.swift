import Combine
import SwiftUI

// MARK: - Paging model

/// Состояние листания полосы. Менеджер дёргает pageDown/pageUp по хоткеям, вью прокручивает к `requestedOffset`.
@MainActor
final class OverlayPagingModel: ObservableObject {
    @Published var pageOffsets: [CGFloat] = [0]
    @Published var currentPage = 0
    /// Полоса прокручивает сюда и сбрасывает в nil.
    @Published var requestedOffset: CGFloat?
    /// Высота видимой области экрана полосы (для предела 45 % при блоке кода); выставляет менеджер в show().
    @Published var screenHeight: CGFloat = 800
    /// true до первого pageUp/ручной прокрутки вверх; снова true при новом ране и при доходе до низа.
    var followsEnd = true

    func pageDown() {
        guard !pageOffsets.isEmpty else { return }
        let last = pageOffsets.count - 1
        go(to: min(currentPage + 1, last))
        // Последняя страница кончается низом ответа: дошли до конца — снова следим за ним.
        if currentPage == last { followsEnd = true }
    }

    func pageUp() {
        guard !pageOffsets.isEmpty else { return }
        followsEnd = false
        go(to: max(currentPage - 1, 0))
    }

    private func go(to page: Int) {
        currentPage = page
        requestedOffset = pageOffsets[page]
    }
}

// MARK: - Theme

enum OverlayTheme {
    static let textPrimary = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let codeBlockBackground = Color.black.opacity(0.45)
    static let inlineCodeBackground = Color.white.opacity(0.12)
    static let keywordColor = Color(red: 0.68, green: 0.50, blue: 0.92)
    static let stringColor = Color(red: 0.73, green: 0.87, blue: 0.53)
    static let commentColor = Color(red: 0.47, green: 0.52, blue: 0.58)
    static let numberColor = Color(red: 0.98, green: 0.69, blue: 0.42)
}

// MARK: - Bar view

/// Полоса-оверлей: заголовок стадии, поток ответа, страницы.
struct OverlayBarView: View {
    @ObservedObject var runner: ExplainRunner
    @ObservedObject var paging: OverlayPagingModel
    /// Желаемая полная высота полосы (содержимое с пределом + заголовок + отступы).
    let onContentHeight: (CGFloat) -> Void

    @AppStorage(SettingsKey.overlayOpacity) private var storedOpacity = Settings.defaultOverlayOpacity
    @AppStorage(SettingsKey.overlayFontSize) private var storedFontSize = Settings.defaultOverlayFontSize
    @AppStorage(SettingsKey.assistantMode) private var assistantMode: AssistantMode = .explanation
    @AppStorage(SettingsKey.explainShortcut) private var explainShortcut: ExplainShortcut = .cmdShiftSpace

    @State private var headerHeight: CGFloat = 20
    @State private var contentHeight: CGFloat = 0
    @State private var segmentHeights: [Int: CGFloat] = [:]
    /// Текст, по которому построены кэши ниже; `parseContent` зовётся только когда `runner.text` от него отличается.
    @State private var cachedText = ""
    @State private var cachedSegments: [ContentSegment] = []
    /// Блоки для показа и страниц: склеенные абзацы с инлайн-кодом и блоки кода.
    @State private var cachedBlocks: [RenderBlock] = []
    /// Подсветка по тексту блока кода; хранятся только блоки текущего ответа, пусто при новом ране.
    @State private var highlightCache: [String: AttributedString] = [:]
    @State private var position = ScrollPosition(edge: .top)
    /// Идёт программная прокрутка: её смещения не считаются ручным скроллом.
    @State private var isAutoScrolling = false
    /// Пользователь крутит колесо/трекпад (фаза прокрутки ScrollView).
    @State private var isUserScrolling = false

    private static let padding: CGFloat = 14
    private static let spacing: CGFloat = 8
    private static let segmentSpacing: CGFloat = 12
    private static let progressHeight: CGFloat = 3

    private var opacity: Double { min(max(storedOpacity, 0.40), 0.95) }
    private var fontSize: CGFloat { CGFloat(min(max(storedFontSize, 13), 24)) }
    private var hasText: Bool { !runner.text.isEmpty }
    private var showsProgress: Bool {
        switch runner.phase {
        case .capturing, .thinking: !hasText
        default: false
        }
    }

    /// Заголовок + промежуток + вертикальные отступы.
    private var chrome: CGFloat { headerHeight + Self.spacing + Self.padding * 2 }
    private var maxContentHeight: CGFloat {
        let hasCodeBlock = cachedBlocks.contains { if case .code = $0 { true } else { false } }
        return hasCodeBlock ? max(paging.screenHeight * 0.45 - chrome, 0) : 5 * fontSize * 1.5
    }
    private var visibleContentHeight: CGFloat { min(contentHeight, maxContentHeight) }
    private var desiredHeight: CGFloat {
        if hasText { return chrome + visibleContentHeight }
        if showsProgress { return chrome + Self.progressHeight }
        return headerHeight + Self.padding * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            if hasText {
                content
            } else if showsProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(height: Self.progressHeight)
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(BarBackground(opacity: opacity))
        .environment(\.colorScheme, .dark)
        .onChange(of: desiredHeight, initial: true) { _, height in onContentHeight(height) }
        .onAppear { refreshContent() }
        .onChange(of: runner.text) {
            refreshContent()
            followEndIfNeeded()
        }
        .onChange(of: fontSize) { rebuildBlocks() }
        .onChange(of: segmentHeights) { recomputePages() }
        // Высота содержимого мерится после раскладки: низ для слежения за концом известен только здесь.
        .onChange(of: contentHeight) { followEndIfNeeded() }
        .onChange(of: visibleContentHeight) { recomputePages() }
        .onChange(of: paging.requestedOffset) { _, offset in
            guard let offset else { return }
            isAutoScrolling = true
            withAnimation(.easeOut(duration: 0.15)) {
                position.scrollTo(y: offset)
            } completion: {
                isAutoScrolling = false
            }
            paging.requestedOffset = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            stageTitle
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OverlayTheme.textPrimary)
                .lineLimit(1)
            Text(assistantMode.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(OverlayTheme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            Spacer(minLength: 8)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if paging.pageOffsets.count > 1 {
                Text("\(paging.currentPage + 1) / \(paging.pageOffsets.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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

    private var hint: String {
        if case .failed = runner.phase { return "\(explainShortcut.rawValue) повторить · ⌘⇧Esc скрыть" }
        return paging.pageOffsets.count > 1 ? "⌘⇧↓ дальше · ⌘⇧Esc скрыть" : "⌘⇧Esc скрыть"
    }

    // MARK: Content

    private var content: some View {
        ScrollView(.vertical) {
            // VStack, а не LazyVStack: страницам нужны высоты всех сегментов, ленивый стек не мерит невидимые.
            VStack(alignment: .leading, spacing: Self.segmentSpacing) {
                ForEach(Array(cachedBlocks.enumerated()), id: \.offset) { index, block in
                    SegmentView(segment: block, fontSize: fontSize, highlighted: highlighted(block))
                        .equatable()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { segmentHeights[index] = $0 }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.automatic)
        .scrollPosition($position)
        .frame(height: visibleContentHeight)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offset: geometry.contentOffset.y,
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height
            )
        } action: { old, new in
            let maxOffset = max(new.contentHeight - new.containerHeight, 0)
            // У низа считаем текущей последнюю страницу: её начало может быть дальше предела прокрутки.
            let page = new.offset >= maxOffset - 1
                ? max(paging.pageOffsets.count - 1, 0)
                : Pager.pageIndex(forOffset: new.offset, pageOffsets: paging.pageOffsets)
            if paging.currentPage != page { paging.currentPage = page }
            let sameLayout = old.contentHeight == new.contentHeight && old.containerHeight == new.containerHeight
            let manual = isUserScrolling || (!isAutoScrolling && sameLayout)
            if manual && new.offset < old.offset {
                paging.followsEnd = false
            } else if manual && new.offset >= maxOffset - 1 {
                paging.followsEnd = true
            }
        }
        .onScrollPhaseChange { _, phase in
            isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
        }
    }

    private func highlighted(_ block: RenderBlock) -> AttributedString? {
        if case .code(let code) = block { highlightCache[code] } else { nil }
    }

    // MARK: Content cache

    /// Пересчитывает сегменты, только если текст изменился.
    private func refreshContent() {
        guard runner.text != cachedText else { return }
        cachedText = runner.text
        if runner.text.isEmpty {
            segmentHeights = [:]
            contentHeight = 0
            highlightCache = [:]
        }
        cachedSegments = parseContent(runner.text)
        rebuildBlocks()
    }

    /// Блоки из `cachedSegments` для текущего размера шрифта; подсветка считается только для новых блоков кода.
    private func rebuildBlocks() {
        cachedBlocks = RenderBlock.blocks(from: cachedSegments, fontSize: fontSize)
        var cache: [String: AttributedString] = [:]
        for case .code(let code) in cachedBlocks {
            cache[code] = highlightCache[code] ?? SyntaxHighlighter.highlighted(code)
        }
        highlightCache = cache
    }

    // MARK: Paging

    private func recomputePages() {
        let ordered = cachedBlocks.indices.map { segmentHeights[$0] ?? 0 }
        paging.pageOffsets = Pager.pageOffsets(
            heights: ordered,
            spacing: Self.segmentSpacing,
            pageHeight: visibleContentHeight,
            lineHeight: fontSize * 1.5
        )
        if paging.currentPage >= paging.pageOffsets.count {
            paging.currentPage = paging.pageOffsets.count - 1
        }
        followEndIfNeeded()
    }

    private func followEndIfNeeded() {
        guard paging.followsEnd, hasText else { return }
        paging.requestedOffset = max(0, contentHeight - visibleContentHeight)
    }
}

private struct ScrollMetrics: Equatable {
    var offset: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat
}

/// Тёмное стекло на macOS 26, иначе материал с тёмной подложкой.
/// Под стеклом всегда непрозрачная на `opacity` подложка: на белом фоне одно стекло даже при 40 % не держит контраст текста.
private struct BarBackground: ViewModifier {
    let opacity: Double
    /// Офлайн-рендер картинок (PreviewRenderer): стекло и материалы вне экрана не рисуются, нужна плоская подложка.
    nonisolated(unsafe) static var flat = false

    func body(content: Content) -> some View {
        if Self.flat {
            content
                .background(Color.black.opacity(max(opacity, 0.78)))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if #available(macOS 26, *) {
            content.background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(opacity))
                    Color.clear.glassEffect(.regular.tint(.black.opacity(0.2)), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        } else {
            content
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(opacity))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

#if DEBUG
extension OverlayTheme {
    /// Включает плоскую подложку полосы для офлайн-рендера.
    static func useFlatBackground() { BarBackground.flat = true }
}
#endif

// MARK: - Render blocks

/// Блок полосы: абзац (обычный текст вперемешку с инлайн-кодом) или блок кода. Страницы и высоты считаются по блокам.
enum RenderBlock: Equatable {
    case paragraph(AttributedString)
    case code(String)

    /// Подряд идущие `.plain`/`.inlineCode` склеиваются в один абзац; у блоков кода убирается тег языка.
    static func blocks(from segments: [ContentSegment], fontSize: CGFloat) -> [RenderBlock] {
        var blocks: [RenderBlock] = []
        var paragraph: AttributedString?

        // Переводы строк вокруг блоков кода (```) не должны становиться пустыми строками абзаца.
        func flushParagraph() {
            defer { paragraph = nil }
            guard let paragraph else { return }
            let chars = paragraph.characters
            guard let first = chars.firstIndex(where: { !$0.isWhitespace }),
                  let last = chars.lastIndex(where: { !$0.isWhitespace }) else { return }
            blocks.append(.paragraph(AttributedString(paragraph[first...last])))
        }

        for segment in segments {
            switch segment {
            case .plain(let text):
                var part = AttributedString(text)
                part.font = .system(size: fontSize)
                part.foregroundColor = OverlayTheme.textPrimary
                paragraph = (paragraph ?? AttributedString()) + part
            case .inlineCode(let code):
                var part = AttributedString(code)
                part.font = .system(size: fontSize - 1, weight: .medium, design: .monospaced)
                part.foregroundColor = OverlayTheme.textPrimary
                part.backgroundColor = OverlayTheme.inlineCodeBackground
                paragraph = (paragraph ?? AttributedString()) + part
            case .codeBlock(let code):
                flushParagraph()
                blocks.append(.code(stripLanguageTag(code)))
            }
        }
        flushParagraph()
        return blocks
    }
}

/// Один блок полосы. Equatable: при новой дельте SwiftUI не перерисовывает неизменившиеся блоки.
struct SegmentView: View, Equatable {
    let segment: RenderBlock
    let fontSize: CGFloat
    /// Подсветка для `.code` (из кэша полосы); nil — до подсчёта, тогда показывается простой моноширинный текст.
    let highlighted: AttributedString?

    var body: some View {
        switch segment {
        case .paragraph(let text):
            Text(text)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

        case .code(let code):
            Text(highlighted ?? AttributedString(code))
                .font(.system(size: fontSize - 1, design: .monospaced))
                .foregroundStyle(OverlayTheme.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OverlayTheme.codeBlockBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - Syntax highlighting

enum SyntaxHighlighter {
    /// Порядок важен: более поздние правила перекрашивают более ранние (строки и комментарии поверх ключевых слов).
    /// Шаблоны — константы, поэтому `try!`: ошибка в литерале видна при первом же показе кода.
    private static let compiledRules: [(Regex<AnyRegexOutput>, Color)] = [
        (#"\b(func|var|let|if|else|for|while|return|class|struct|enum|extension|import|guard|switch|case|default|in|try|catch|throw|async|await|self|nil|true|false|def|lambda|with|yield|and|or|not|public|private|protected|static|final|override|init|deinit|throws|rethrows)\b"#, OverlayTheme.keywordColor),
        (#""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#, OverlayTheme.stringColor),
        (#"//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/"#, OverlayTheme.commentColor),
        (#"\b\d+\.?\d*\b"#, OverlayTheme.numberColor),
    ].map { pattern, color in (try! Regex(pattern), color) }

    static func highlighted(_ code: String) -> AttributedString {
        var result = AttributedString(code)
        result.foregroundColor = OverlayTheme.textPrimary

        for (regex, color) in compiledRules {
            for match in code.matches(of: regex) {
                if let start = AttributedString.Index(match.range.lowerBound, within: result),
                   let end = AttributedString.Index(match.range.upperBound, within: result) {
                    result[start..<end].foregroundColor = color
                }
            }
        }
        return result
    }
}
