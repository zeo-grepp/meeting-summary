import XCTest

@MainActor final class DetectionCoordinatorTests: XCTestCase {
    func testOnlyNewMicrophoneUseByWatchedAppTriggersWithinCooldown() {
        let now = Date(timeIntervalSince1970: 1_000)
        func candidate(_ hasNew: Bool, enabled: Bool = true, last: Date? = nil) -> Bool {
            DetectionCoordinator.shouldNotify(hasNewAppOnMicrophone: hasNew,
                                              enabled: enabled, lastNotificationAt: last, now: now)
        }

        XCTAssertTrue(candidate(true))
        // 이미 마이크를 쓰고 있던 앱만 남아 있으면 새 회의가 아니다.
        XCTAssertFalse(candidate(false))
        XCTAssertFalse(candidate(true, enabled: false))
        XCTAssertFalse(DetectionCoordinator.shouldNotify(hasNewAppOnMicrophone: true,
            enabled: true, recordingBusy: true, lastNotificationAt: nil, now: now))
        XCTAssertFalse(candidate(true, last: now.addingTimeInterval(-59)))
        XCTAssertTrue(candidate(true, last: now.addingTimeInterval(-60)))
    }

    func testHelperProcessesCountAsTheirApp() {
        let chrome = WatchedApplication(bundleIdentifier: "com.google.Chrome", displayName: "Chrome")
        XCTAssertTrue(chrome.owns(audioProcess: "com.google.Chrome"))
        // Meet의 마이크를 실제로 여는 것은 헬퍼 프로세스다.
        XCTAssertTrue(chrome.owns(audioProcess: "com.google.Chrome.helper"))
        XCTAssertFalse(chrome.owns(audioProcess: "com.google.ChromeCanary"))
        XCTAssertFalse(chrome.owns(audioProcess: "com.hnc.Discord"))
    }
}
