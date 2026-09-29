import XCTest

final class ClaudeSummarizerTests: XCTestCase {
    /// 게이트웨이 주소를 어떻게 적어 오든 `v1/messages`를 한 번만 붙인 주소가 나와야 한다.
    func testBaseURLEndsWithoutVersionSegment() throws {
        for written in ["https://gateway.example.com",
                        "https://gateway.example.com/",
                        "https://gateway.example.com/v1",
                        "https://gateway.example.com/v1/",
                        "  https://gateway.example.com/v1  "] {
            XCTAssertEqual(ClaudeSummarizer.normalize(written).appending(path: "v1/messages").absoluteString,
                           "https://gateway.example.com/v1/messages", "입력: \(written)")
        }
    }

    /// 주소를 지웠다고 요약이 죽으면 안 된다. 공개 API로 돌아간다.
    func testEmptyAddressFallsBackToPublicAPI() throws {
        XCTAssertEqual(ClaudeSummarizer.normalize("").absoluteString, "https://api.anthropic.com")
    }

    /// 정상 경로. 도구를 쓴 응답에서 회의록을 꺼낸다.
    func testToolUseBlockIsRead() throws {
        let data = Data("""
            {"content": [
                {"type": "thinking", "thinking": "생각"},
                {"type": "tool_use", "name": "write_meeting_notes",
                 "input": {"title": "제목", "content": "본문"}}
            ]}
            """.utf8)

        XCTAssertEqual(ClaudeSummarizer.notes(in: data)?["title"] as? String, "제목")
    }

    /// 게이트웨이가 tool_choice를 막아서 도구를 강제할 수 없다.
    /// 모델이 글로만 답하는 경우가 있고, 그 안에 적어 보낸 JSON을 건져내야 한다.
    func testJSONInPlainTextIsReadWhenTheToolIsSkipped() throws {
        let data = Data("""
            {"content": [{"type": "text", "text": "회의록입니다.\\n```json\\n{\\"title\\": \\"제목\\", \\"content\\": \\"본문\\"}\\n```"}]}
            """.utf8)

        XCTAssertEqual(ClaudeSummarizer.notes(in: data)?["content"] as? String, "본문")
    }

    /// 회의록이 없으면 nil이어야 한다 — 호출하는 쪽이 이걸 보고 한 번 재시도한다.
    func testProseWithoutJSONYieldsNothing() throws {
        let data = Data("""
            {"content": [{"type": "text", "text": "회의록으로 작성할 내용이 없습니다."}]}
            """.utf8)

        XCTAssertNil(ClaudeSummarizer.notes(in: data))
    }
}
