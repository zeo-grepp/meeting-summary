import Foundation

/// 녹취록을 회의록으로 바꾼다. meeting.py가 Ollama에 하던 일을 Claude API로 한다.
///
/// 요청 하나뿐이라 SDK를 넣지 않고 URLSession으로 직접 친다.
struct ClaudeSummarizer {
    /// 사내 게이트웨이를 쓰면 주소와 모델 이름이 둘 다 달라진다.
    let baseURL: URL
    let apiKey: String
    let model: String

    @MainActor init(settings: SettingsStore) {
        baseURL = Self.normalize(settings.anthropicBaseURL)
        apiKey = settings.anthropicAPIKey
        model = settings.anthropicModel
    }

    /// 게이트웨이 문서가 알려주는 주소에는 `/v1`이 이미 붙어 있기도 하다.
    /// 그대로 두면 `/v1/v1/messages`로 가서 404가 난다. 끝의 `/v1`과 슬래시를 떼고 쓴다.
    static func normalize(_ baseURL: String) -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+(v1/*)?$", with: "", options: .regularExpression)
        return URL(string: trimmed) ?? URL(string: "https://api.anthropic.com")!
    }

    struct Summary {
        let title: String
        let content: String
    }

    func summarize(transcript: String) async throws -> Summary {
        // 도구를 강제할 수 없어서 가끔 글로만 답한다. 그때는 한 번 더 친다.
        let request = body(transcript: transcript)
        do {
            return try await parse(send(request))
        } catch SummarizerError.noNotes {
            return try await parse(send(request))
        }
    }

    /// 설정 화면의 "연결 테스트". 회의가 끝난 뒤 5분 기다려서 실패를 알게 되는 일을 막는다.
    func ping() async throws {
        _ = try await send(["model": model, "max_tokens": 1,
                            "messages": [["role": "user", "content": "."]]])
    }

    private func send(_ body: [String: Any]) async throws -> Data {
        guard !apiKey.isEmpty else { throw SummarizerError.noAPIKey }

        var request = URLRequest(url: baseURL.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // 1시간 회의는 출력이 길다. 기본 60초로는 모자란다.
        request.timeoutInterval = 300
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SummarizerError.badResponse("응답 없음") }
        guard http.statusCode == 200 else {
            throw SummarizerError.badResponse("HTTP \(http.statusCode) — \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        return data
    }

    /// Ollama의 format=RESPONSE_FORMAT에 해당하는 것이 Claude에는 없다.
    /// meeting.py의 RESPONSE_FORMAT을 그대로 tool의 input_schema로 쓴다.
    ///
    /// tool_choice로 강제하지 않는다 — 사내 게이트웨이가 type "tool"/"any"를 400으로 막는다.
    /// 그래서 도구를 쓰라고 본문에 적고, 그래도 글로 답하면 parse가 JSON을 건져낸다.
    private func body(transcript: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 8192,
            "system": Self.systemPrompt,
            "tools": [[
                "name": Self.toolName,
                "description": "작성한 회의 제목과 회의록을 넘긴다.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "회의 핵심 주제를 나타내는 짧고 구체적인 한국어 제목",
                        ],
                        "content": [
                            "type": "string",
                            "description": "Markdown 형식의 회의록 본문",
                        ],
                    ],
                    "required": ["title", "content"],
                ],
            ]],
            "messages": [[
                "role": "user",
                "content": "다음 녹취록을 바탕으로 회의 제목과 회의록을 작성해서 "
                    + "\(Self.toolName) 도구로 넘겨줘.\n\n\(transcript)",
            ]],
        ]
    }

    private func parse(_ data: Data) throws -> Summary {
        guard let input = Self.notes(in: data) else {
            throw SummarizerError.noNotes(String(decoding: data.prefix(300), as: UTF8.self))
        }
        let title = (input["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (input["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw SummarizerError.badResponse("회의 제목이 비었습니다.") }
        guard !content.isEmpty else { throw SummarizerError.badResponse("회의록 본문이 비었습니다.") }
        return Summary(title: title, content: content)
    }

    /// 응답에서 회의록을 꺼낸다. 도구를 쓴 응답이 정상이고, 글로만 답한 응답은
    /// 본문에 적어 보낸 JSON을 건져낸다. 둘 다 아니면 nil — 호출한 쪽이 한 번 재시도한다.
    static func notes(in data: Data) -> [String: Any]? {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let blocks = json?["content"] as? [[String: Any]] ?? []

        if let input = blocks.first(where: { $0["name"] as? String == toolName })?["input"] as? [String: Any] {
            return input
        }

        return blocks.compactMap { $0["text"] as? String }
            .compactMap(embeddedJSON)
            .first
    }

    /// 설명과 코드펜스에 둘러싸인 JSON에서 중괄호 사이만 떼어낸다.
    private static func embeddedJSON(_ text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        let object = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))
        return object as? [String: Any]
    }

    private static let toolName = "write_meeting_notes"

    enum SummarizerError: LocalizedError {
        case noAPIKey, badResponse(String), noNotes(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: "Claude API 키가 설정되지 않았습니다."
            case let .badResponse(detail): "Claude 응답을 읽지 못했습니다 — \(detail)"
            case let .noNotes(answer): "Claude가 회의록을 반환하지 않았습니다 — \(answer)"
            }
        }
    }

    /// meeting.py:39-98에서 그대로 옮겼다. 지금 결과물 품질이 이 프롬프트에서 나온다.
    private static let systemPrompt = """
        너는 개발팀 회의록을 작성하는 도우미다.

        음성 인식으로 생성된 녹취록을 바탕으로 회의 제목과 회의록을 작성한다.

        반드시 다음 규칙을 지킨다.

        - 회의 제목은 녹취록의 핵심 주제를 나타내는 짧고 구체적인 제목으로 작성한다.
        - "회의", "회의녹음", "미팅"처럼 내용이 드러나지 않는 제목은 사용하지 않는다.
        - 녹취록에 명시적으로 존재하는 내용만 사용한다.
        - 녹취록에 없는 내용을 추측해서 추가하지 않는다.
        - 정확한 화자 정보가 없으면 누가 발언했는지 추측하지 않는다.
        - 이름이 문장에 명시적으로 등장한 경우에만 이름을 사용한다.
        - 제안, 질문, 개인 의견을 결정 사항으로 작성하지 않는다.
        - 실제로 합의되거나 진행하기로 확정된 내용만 결정 사항으로 작성한다.
        - 확정 여부가 애매한 내용은 미결 사항으로 작성한다.
        - 담당자가 명확하게 지정된 경우에만 담당자를 액션 아이템에 기록한다.
        - 음성 인식 오류로 보이는 반복 문장이나 의미 없는 문장은 무시한다.
        - 같은 내용을 여러 섹션에 불필요하게 반복하지 않는다.
        - 반드시 한국어로 작성한다.
        - 개발 용어는 영어 그대로 사용한다.

        content는 다음 Markdown 형식으로 작성한다.

        ## 회의 요약

        - 핵심 내용

        ## 주요 논의 사항

        ### 주제

        - 논의 내용

        ## 결정 사항

        - 결정 내용

        없으면 "없음"

        ## 액션 아이템

        - [ ] 담당자: 할 일

        할 일은 명확하지만 담당자가 정해지지 않았다면:

        - [ ] 담당자 미정: 할 일

        없으면 "없음"

        ## 미결 사항

        - 미결 내용

        없으면 "없음"

        Markdown 문법 앞에 백슬래시를 붙이지 않는다.
        제목(`#`)과 날짜는 content에 포함하지 않는다.
        불필요한 서론, 후기, 자기평가를 출력하지 않는다.
        """
}
