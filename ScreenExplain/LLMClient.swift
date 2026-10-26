import AppKit
import Foundation

enum LLMClientError: LocalizedError {
    case invalidURL
    case missingAPIKey
    case httpStatus(Int)
    /// Сервер прислал JSON с `error.message`; `status == 0` — ошибка пришла строкой посреди потока SSE.
    case server(status: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Некорректный URL сервера"
        case .missingAPIKey: "Введите OpenAI API key в настройках"
        case .httpStatus(let code):
            switch code {
            case 401, 403: "Ключ API не принят (HTTP \(code))"
            case 404: "Модель или адрес не найдены (HTTP 404)"
            case 429: "Превышен лимит запросов (HTTP 429)"
            default: "Сервер вернул HTTP \(code)"
            }
        case .server(let status, let message):
            status == 0 ? "Сервер вернул ошибку: \(message)" : "Сервер ответил (\(status)): \(message)"
        case .emptyResponse: "Модель вернула пустой ответ"
        }
    }
}

/// Клиент OpenAI-совместимого chat/completions API (OpenAI или LM Studio).
struct LLMClient {
    let settings: Settings

    private var baseURL: String {
        switch settings.backendMode {
        case .lmStudio: settings.lmStudioBaseURL
        case .openAI: "https://api.openai.com/v1"
        }
    }

    func listModels() async throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let (data, response) = try await URLSession.shared.data(for: makeRequest(path: "models", body: nil))
        try checkStatus(response, body: data)
        return try JSONDecoder().decode(Response.self, from: data).data.map(\.id).sorted()
    }

    /// Два шага: vision-модель описывает скриншот текстом, кодовая модель отвечает по описанию.
    /// Поток отдаёт дельты финального ответа кодовой модели.
    func explainStream(image: NSImage) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let summary = try await chat(model: settings.visionModel, content: [
                        ["type": "text", "text": Self.visionPrompt],
                        ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(pngBase64(image))"]],
                    ])
                    let answer = chatStream(model: settings.codeModel, content: [
                        ["type": "text", "text": codePrompt(screenSummary: summary)],
                    ])
                    for try await delta in answer {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - HTTP

    private func chat(model: String, content: [[String: Any]]) async throws -> String {
        let request = try chatRequest(model: model, content: content, stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, body: data)
        guard let text = SSE.fullContent(fromJSON: data) else { throw LLMClientError.emptyResponse }
        return text
    }

    /// Потоковый запрос (SSE). Если сервер ответил обычным JSON, поток отдаёт весь текст одной дельтой.
    private func chatStream(model: String, content: [[String: Any]]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatRequest(model: model, content: content, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try await checkStatus(response, bytes: bytes)
                    let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
                    if contentType?.contains("text/event-stream") == true {
                        for try await line in bytes.lines {
                            if let delta = SSE.contentDelta(fromLine: line) {
                                continuation.yield(delta)
                            } else if let message = SSE.errorMessage(fromLine: line) {
                                throw LLMClientError.server(status: 0, message: message)
                            }
                        }
                    } else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        guard let text = SSE.fullContent(fromJSON: data) else { throw LLMClientError.emptyResponse }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func chatRequest(model: String, content: [[String: Any]], stream: Bool) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": content]],
        ]
        if stream { body["stream"] = true }
        return try makeRequest(path: "chat/completions", body: body)
    }

    private func makeRequest(path: String, body: [String: Any]?) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/\(path)") else { throw LLMClientError.invalidURL }
        var request = URLRequest(url: url)
        if settings.backendMode == .openAI {
            guard !settings.openAIKey.isEmpty else { throw LLMClientError.missingAPIKey }
            request.setValue("Bearer \(settings.openAIKey)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// Не-2xx → `.server` с текстом из JSON-тела `error.message`, иначе `.httpStatus`.
    private func checkStatus(_ response: URLResponse, body: Data) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) else { return }
        if let message = SSE.errorMessage(fromJSON: body) {
            throw LLMClientError.server(status: status, message: message)
        }
        throw LLMClientError.httpStatus(status)
    }

    /// То же для потокового ответа: при ошибке дочитывает тело (не больше 64 КБ), успешный поток не трогает.
    private func checkStatus(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) else { return }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count >= 65_536 { break }
        }
        try checkStatus(response, body: body)
    }

    private func pngBase64(_ image: NSImage) -> String {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return "" }
        return png.base64EncodedString()
    }

    // MARK: - Prompts

    private static let visionPrompt = """
    Ты ассистент, который видит скриншот экрана разработчика.
    Кратко и структурированно опиши, что сейчас видно:
    - какая IDE/программа открыта;
    - какой файл или язык;
    - какие функции, классы или участки кода видны;
    - на что особенно стоит обратить внимание разработчику.
    Не давай советов, просто опиши картинку.
    """

    private func codePrompt(screenSummary: String) -> String {
        switch settings.assistantMode {
        case .explanation:
            """
            Ниже описание того, что видно на экране разработчика (получено от другой модели):

            \(screenSummary)

            Твоя задача — дать понятное Пояснение.
            Кратко и по-русски объясни:
            - что делает показанный код или интерфейс;
            - какие важные детали стоит заметить;
            - если видно потенциальные проблемы или улучшения — упомяни их.

            Не пиши, что описание пришло от другой модели или что ты не видишь картинку.
            Просто дай понятное объяснение для разработчика.
            """

        case .codeWriting:
            """
            Ниже текстовое описание экрана разработчика (получено от другой модели):

            \(screenSummary)

            Режим: Написание кода.

            Представь, что это задача уровня LeetCode/кодингового интервью.
            На основе описания:
            - определи, какую задачу по коду сейчас решает пользователь;
            - предложи законченное решение в подходящем языке программирования (если из описания понятно, какой язык — используй его);
            - оформи ответ в виде кода с минимальными, но понятными комментариями.

            Если задача формулируется в тексте (например, видно условие), используй её как основную,
            не трать много текста на объяснения — сосредоточься на самом коде.
            """

        case .problemSolving:
            """
            Ниже текстовое описание экрана разработчика (получено от другой модели):

            \(screenSummary)

            Режим: Решение задач / прохождение тестов.

            На основе описания:
            - определи, какую задачу или тесты пытается пройти пользователь;
            - предложи стратегию решения и полный код решения;
            - отдельно укажи, как ты бы проверял решение тестами (какие кейсы важны);
            - если видно ошибки тестов или падения, помоги их исправить.

            Пиши по-русски, но код и имена переменных оформи в нормальном стиле для выбранного языка.
            """

        case .refactoring:
            """
            Ниже текстовое описание экрана разработчика (получено от другой модели):

            \(screenSummary)

            Режим: Рефакторинг кода.

            Представь, что тебе нужно показать навыки рефакторинга.
            На основе описания:
            - опиши, какие части кода выглядят избыточно, плохо структурированы или сложны для понимания;
            - предложи улучшенный вариант структуры (функции, модули, классы);
            - приведи примеры фрагментов кода до/после (на основе описания того, что видно);
            - объясни, почему твой вариант лучше с точки зрения читаемости, поддержки и, при необходимости, производительности.

            Не меняй предполагаемое поведение кода, только его структуру и стиль.
            Пиши кратко, но по делу.
            """
        }
    }
}
