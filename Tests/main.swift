import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() { print("FAIL line \(line): \(message)"); exit(1) }
}

// parseContent
check(parseContent("a `b` c") == [.plain("a "), .inlineCode("b"), .plain(" c")], "inline code")
check(parseContent("x ```\nlet a = 1\n``` y") == [.plain("x "), .codeBlock("let a = 1"), .plain(" y")], "code block trimmed")
check(parseContent("start ```\nlet a") == [.plain("start "), .codeBlock("\nlet a")], "unterminated code block goes to end")
check(parseContent("a ` b") == [.plain("a "), .plain("` b")], "lone backtick kept")
check(parseContent("") == [], "empty")
check(stripLanguageTag("python\nprint(1)") == "print(1)", "language tag stripped")
check(stripLanguageTag("print(1)") == "print(1)", "single line kept")
check(stripLanguageTag("x = 1\ny = 2") == "x = 1\ny = 2", "code first line kept")

// SSE
check(SSE.contentDelta(fromLine: #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#) == "Hel", "delta text")
check(SSE.contentDelta(fromLine: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == nil, "role-only chunk ignored")
check(SSE.contentDelta(fromLine: "data: [DONE]") == nil, "DONE ignored")
check(SSE.contentDelta(fromLine: "") == nil, "empty line")
check(SSE.contentDelta(fromLine: ": keep-alive") == nil, "comment line")
check(SSE.fullContent(fromJSON: Data(#"{"choices":[{"message":{"content":"full"}}]}"#.utf8)) == "full", "non-stream body")
check(SSE.fullContent(fromJSON: Data(#"{"choices":[]}"#.utf8)) == nil, "no choices")
check(SSE.errorMessage(fromLine: #"data: {"error":{"message":"ctx"}}"#) == "ctx", "stream error message")
check(SSE.errorMessage(fromLine: #"data: {"choices":[]}"#) == nil, "no stream error")

// Pager
check(Pager.pageOffsets(heights: [], spacing: 12, pageHeight: 100, lineHeight: 0) == [0], "empty → one page")
check(Pager.pageOffsets(heights: [30, 30], spacing: 12, pageHeight: 100, lineHeight: 0) == [0], "fits one page")
check(Pager.pageOffsets(heights: [60, 60], spacing: 12, pageHeight: 100, lineHeight: 0) == [0, 32], "second page clamped to scroll end")
check(Pager.pageOffsets(heights: [50, 50, 50, 50, 50], spacing: 10, pageHeight: 100, lineHeight: 0) == [0, 60, 120, 190], "natural page starts kept, one close to end dropped")
check(Pager.pageOffsets(heights: [20, 250, 20], spacing: 10, pageHeight: 100, lineHeight: 0) == [0, 100, 155, 210], "tall segment split, no gaps, end clamped")
check(Pager.pageOffsets(heights: [350], spacing: 0, pageHeight: 100, lineHeight: 0) == [0, 100, 200, 250], "tall single segment: last page at scroll end")
check(Pager.pageOffsets(heights: [50], spacing: 12, pageHeight: 0, lineHeight: 0) == [0], "zero page height")
check(Pager.pageOffsets(heights: [350], spacing: 0, pageHeight: 100, lineHeight: 10) == [0, 90, 180, 250], "line overlap step")
check(Pager.pageOffsets(heights: [300], spacing: 0, pageHeight: 100, lineHeight: 0) == [0, 100, 200], "exact steps to end")
do {
    let heights: [CGFloat] = [40, 600, 60]
    let total = heights.reduce(0, +) + 12 * 2
    let pages = Pager.pageOffsets(heights: heights, spacing: 12, pageHeight: 300, lineHeight: 20)
    check(pages.allSatisfy { $0 <= total - 300 }, "no offset past scroll end: \(pages)")
    check(Set(pages).count == pages.count, "no duplicates: \(pages)")
    check(pages.last == total - 300, "last page at scroll end: \(pages)")
    check(zip(pages, pages.dropFirst()).allSatisfy { $1 - $0 >= 100 }, "neighbours ≥ pageHeight/3 apart: \(pages)")
    check(zip(pages, pages.dropFirst()).allSatisfy { $1 - $0 <= 300 }, "no skipped text between pages: \(pages)")
}
check(Pager.pageIndex(forOffset: 0, pageOffsets: [0, 72]) == 0, "page 1")
check(Pager.pageIndex(forOffset: 72, pageOffsets: [0, 72]) == 1, "page 2 exact")
check(Pager.pageIndex(forOffset: 71.5, pageOffsets: [0, 72]) == 1, "page 2 within tolerance")

print("OK: \(checks) checks")
