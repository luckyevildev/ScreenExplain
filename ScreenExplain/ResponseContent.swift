import Foundation

nonisolated enum ContentSegment: Equatable {
    case plain(String)
    case codeBlock(String)
    case inlineCode(String)
}

nonisolated func parseContent(_ text: String) -> [ContentSegment] {
    var segments: [ContentSegment] = []
    var remaining = text[...]

    while !remaining.isEmpty {
        // Ищем начало code block ```
        if let range = remaining.range(of: "```") {
            let before = String(remaining[..<range.lowerBound])
            if !before.isEmpty {
                segments.append(contentsOf: parsePlainTextWithInlineCode(before))
            }
            remaining = remaining[range.upperBound...]

            // Ищем конец code block
            if let endRange = remaining.range(of: "```") {
                let code = String(remaining[..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                segments.append(.codeBlock(code))
                remaining = remaining[endRange.upperBound...]
            } else {
                segments.append(.codeBlock(String(remaining)))
                break
            }
        } else {
            segments.append(contentsOf: parsePlainTextWithInlineCode(String(remaining)))
            break
        }
    }

    return segments
}

nonisolated func parsePlainTextWithInlineCode(_ text: String) -> [ContentSegment] {
    var segments: [ContentSegment] = []
    var remaining = text[...]

    while !remaining.isEmpty {
        if let range = remaining.range(of: "`") {
            let before = String(remaining[..<range.lowerBound])
            if !before.isEmpty {
                segments.append(.plain(before))
            }
            remaining = remaining[range.upperBound...]

            if let endRange = remaining.range(of: "`") {
                let code = String(remaining[..<endRange.lowerBound])
                segments.append(.inlineCode(code))
                remaining = remaining[endRange.upperBound...]
            } else {
                segments.append(.plain("`" + String(remaining)))
                break
            }
        } else {
            segments.append(.plain(String(remaining)))
            break
        }
    }

    return segments
}

/// Убирает тег языка из блока кода ("```python\n…"): первая строка — одно слово без пробелов, и строки дальше есть.
nonisolated func stripLanguageTag(_ code: String) -> String {
    guard let newline = code.firstIndex(of: "\n") else { return code }
    let firstLine = code[..<newline]
    // ^[A-Za-z0-9_+#.-]+$ (без regex-литерала: в режиме Swift 5 нужен флаг bare-slash-regex).
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+#.-")
    guard !firstLine.isEmpty, firstLine.allSatisfy(allowed.contains) else { return code }
    return String(code[code.index(after: newline)...])
}
