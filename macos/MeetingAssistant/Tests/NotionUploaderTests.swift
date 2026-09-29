import XCTest

final class NotionUploaderTests: XCTestCase {
    /// 요약 프롬프트가 만드는 다섯 가지 줄 모양이 각각 맞는 블록으로 간다.
    func testMarkdownLinesBecomeMatchingBlocks() throws {
        let blocks = NotionUploader.blocks(from: """
            ## 결정 사항

            - 첫 항목
            ### 액션 아이템
            - [ ] 할 일
            - [x] 끝난 일
            그냥 문단
            """)
        XCTAssertEqual(blocks.map { $0["type"] as? String },
                       ["heading_2", "bulleted_list_item", "heading_3", "to_do", "to_do", "paragraph"])
        XCTAssertEqual(text(blocks[0], "heading_2"), "결정 사항")
        XCTAssertEqual(text(blocks[1], "bulleted_list_item"), "첫 항목")
        XCTAssertEqual(text(blocks[3], "to_do"), "할 일")
        XCTAssertEqual((blocks[3]["to_do"] as? [String: Any])?["checked"] as? Bool, false)
        XCTAssertEqual((blocks[4]["to_do"] as? [String: Any])?["checked"] as? Bool, true)
        XCTAssertEqual(text(blocks[5], "paragraph"), "그냥 문단")
    }

    /// rich_text 한 덩이는 2000자까지라 긴 줄은 쪼개져야 한다. 잘려 사라지면 안 된다.
    func testLongLineIsSplitInsteadOfTruncated() throws {
        let line = String(repeating: "가", count: 4500)
        let rich = try XCTUnwrap((NotionUploader.blocks(from: line).first?["paragraph"]
            as? [String: Any])?["rich_text"] as? [[String: Any]])
        let pieces = rich.compactMap { ($0["text"] as? [String: String])?["content"] }
        XCTAssertEqual(pieces.map(\.count), [2000, 2000, 500])
        XCTAssertEqual(pieces.joined(), line)
    }

    private func text(_ block: [String: Any], _ type: String) -> String? {
        ((block[type] as? [String: Any])?["rich_text"] as? [[String: Any]])?
            .first.flatMap { ($0["text"] as? [String: String])?["content"] }
    }
}
