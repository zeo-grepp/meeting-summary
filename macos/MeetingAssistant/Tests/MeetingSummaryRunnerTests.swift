import XCTest

@MainActor
final class MeetingSummaryRunnerTests: XCTestCase {
    /// 사유마다 사람이 할 일이 다르다. 그 갈림이 문구에 드러나야 한다.
    func testEachFailureSaysWhatToDoNext() throws {
        let cases: [(Error, String)] = [
            (URLError(.cannotFindHost), "VPN"),
            (URLError(.timedOut), "VPN"),
            (ClaudeSummarizer.SummarizerError.noAPIKey, "API 키를 넣어"),
            (ClaudeSummarizer.SummarizerError.badResponse("HTTP 401 — nope"), "키를 확인"),
            (ClaudeSummarizer.SummarizerError.badResponse("HTTP 404 — nope"), "주소를 확인"),
            (ClaudeSummarizer.SummarizerError.badResponse("HTTP 503 — nope"), "잠시 뒤"),
            (ClaudeSummarizer.SummarizerError.noNotes("…"), "녹음이 너무 짧"),
        ]

        for (error, expected) in cases {
            let reason = MeetingSummaryRunner.reason(for: error)
            XCTAssertTrue(reason.contains(expected), "\(error) → \(reason)")
        }
    }

    /// 모르는 상태 코드는 지어내지 말고 원문을 보여준다.
    func testUnknownStatusKeepsTheOriginalBody() throws {
        let reason = MeetingSummaryRunner.reason(for: ClaudeSummarizer.SummarizerError.badResponse("HTTP 418 — teapot"))

        XCTAssertTrue(reason.contains("teapot"), reason)
    }

    /// 자동 재시도는 잠깐 끊긴 경우에만 쓸모가 있다.
    /// 키가 틀렸는데 다시 보내면 5초만 더 기다리게 만든다.
    func testOnlyTransientNetworkErrorsAreRetried() throws {
        XCTAssertTrue(MeetingSummaryRunner.isNetworkFailure(URLError(.networkConnectionLost)))
        XCTAssertFalse(MeetingSummaryRunner.isNetworkFailure(URLError(.userAuthenticationRequired)))
        XCTAssertFalse(MeetingSummaryRunner.isNetworkFailure(ClaudeSummarizer.SummarizerError.noAPIKey))
    }
}
