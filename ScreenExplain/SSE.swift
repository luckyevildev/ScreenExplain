import Foundation

/// Разбор ответов chat/completions: строки потока Server-Sent Events и обычный JSON.
nonisolated enum SSE {
    /// "data: {json}" → текст дельты; nil для строк без текста ("data: [DONE]", пустые, чанк только с role, служебные).
    static func contentDelta(fromLine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(payload.utf8))
        else { return nil }
        return chunk.choices.first?.delta.content
    }

    /// "data: {"error":{"message":"…"}}" → message (ошибка посреди потока); nil для остальных строк.
    static func errorMessage(fromLine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        return errorMessage(fromJSON: Data(payload.utf8))
    }

    /// Тело ошибки OpenAI-совместимого API {"error":{"message":"…"}} → message; nil, если тело другое.
    static func errorMessage(fromJSON data: Data) -> String? {
        try? JSONDecoder().decode(ErrorResponse.self, from: data).error.message
    }

    /// Обычный (не потоковый) ответ chat/completions → текст первого choice; nil, если choices пуст или JSON не разобрался.
    static func fullContent(fromJSON data: Data) -> String? {
        try? JSONDecoder().decode(FullResponse.self, from: data).choices.first?.message.content
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }

    private struct ErrorResponse: Decodable {
        struct Body: Decodable { let message: String }
        let error: Body
    }

    private struct FullResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }
}
