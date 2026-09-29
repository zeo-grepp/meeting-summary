import Foundation

/// 회의록을 팀 노션 데이터베이스에 새 페이지로 올린다.
///
/// 설정이 비어 있으면 그냥 안 올린다 — 노션은 선택 기능이고, 로컬 .md는 어차피 남는다.
struct NotionUploader {
    var token = ProcessInfo.processInfo.environment["NOTION_TOKEN"] ?? ""
    var databaseID = ProcessInfo.processInfo.environment["NOTION_DATABASE_ID"] ?? ""
    /// DB마다 속성 이름이 다르다. Phase 3에서 설정값으로 뺀다.
    var titleProperty = ProcessInfo.processInfo.environment["NOTION_TITLE_PROPERTY"] ?? "이름"
    /// 날짜 속성이 없는 DB도 있다. 비워두면 안 쓴다.
    var dateProperty = ProcessInfo.processInfo.environment["NOTION_DATE_PROPERTY"] ?? ""

    var isEnabled: Bool { !token.isEmpty && !databaseID.isEmpty }

    /// 페이지를 만들고 그 URL을 돌려준다.
    func upload(title: String, markdown: String, date: Date) async throws -> URL {
        let blocks = Self.blocks(from: markdown)
        // children은 한 요청에 100개까지다. 긴 회의는 넘는다.
        // https://developers.notion.com/reference/patch-block-children
        let chunks = stride(from: 0, to: blocks.count, by: 100).map {
            Array(blocks[$0 ..< min($0 + 100, blocks.count)])
        }

        var properties: [String: Any] = [
            titleProperty: ["title": [["text": ["content": String(title.prefix(2000))]]]]
        ]
        if !dateProperty.isEmpty {
            properties[dateProperty] = ["date": ["start": Self.day.string(from: date)]]
        }
        let page = try await send(method: "POST", path: "v1/pages", body: [
            "parent": ["database_id": databaseID],
            "properties": properties,
            "children": chunks.first ?? [],
        ])

        guard let id = page["id"] as? String,
              let urlString = page["url"] as? String, let url = URL(string: urlString) else {
            throw NotionError.badResponse("페이지 응답에 id/url이 없습니다.")
        }
        for chunk in chunks.dropFirst() {
            _ = try await send(method: "PATCH", path: "v1/blocks/\(id)/children", body: ["children": chunk])
        }
        return url
    }

    private func send(method: String, path: String, body: [String: Any]) async throws -> [String: Any] {
        guard isEnabled else { throw NotionError.notConfigured }
        var request = URLRequest(url: URL(string: "https://api.notion.com/")!.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // 통합을 DB에 "연결"하지 않으면 토큰이 맞아도 404가 난다. 메시지에 그대로 실린다.
            throw NotionError.badResponse(json["message"] as? String
                ?? String(data: data, encoding: .utf8) ?? "알 수 없는 오류")
        }
        return json
    }

    /// 요약 프롬프트가 만드는 모양만 다룬다: ##, ###, - [ ], -, 그 외 문단.
    /// 임의의 Markdown이 아니므로 파서를 데려오지 않는다.
    static func blocks(from markdown: String) -> [[String: Any]] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            for (marker, type) in [("### ", "heading_3"), ("## ", "heading_2"),
                                   ("- [ ] ", "to_do"), ("- [x] ", "to_do"), ("- ", "bulleted_list_item")]
            where line.hasPrefix(marker) {
                var value: [String: Any] = ["rich_text": richText(String(line.dropFirst(marker.count)))]
                if type == "to_do" { value["checked"] = line.hasPrefix("- [x] ") }
                return ["object": "block", "type": type, type: value]
            }
            return ["object": "block", "type": "paragraph", "paragraph": ["rich_text": richText(line)]]
        }
    }

    /// rich_text 한 덩이는 2000자까지다. 긴 줄은 잘라서 여러 덩이로 넣는다.
    private static func richText(_ text: String) -> [[String: Any]] {
        stride(from: 0, to: max(text.count, 1), by: 2000).map { start in
            let from = text.index(text.startIndex, offsetBy: start)
            let to = text.index(from, offsetBy: 2000, limitedBy: text.endIndex) ?? text.endIndex
            return ["type": "text", "text": ["content": String(text[from ..< to])]]
        }
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    enum NotionError: LocalizedError {
        case notConfigured
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "노션 토큰과 데이터베이스 ID를 설정해주세요."
            case .badResponse(let message): "노션 업로드 실패: \(message)"
            }
        }
    }
}
