import XCTest

@MainActor final class DetectionCoordinatorTests: XCTestCase {
    func testOnlyNewMicrophoneUseByWatchedAppTriggersWithinCooldown() {
        let now = Date(timeIntervalSince1970: 1_000)
        func candidate(_ was: Bool, _ isOn: Bool, enabled: Bool = true, last: Date? = nil) -> Bool {
            DetectionCoordinator.shouldNotify(wasOnMicrophone: was, isOnMicrophone: isOn,
                                              enabled: enabled, lastNotificationAt: last, now: now)
        }

        XCTAssertTrue(candidate(false, true))
        // 브라우저처럼 늘 떠 있는 앱이라도 마이크를 잡은 순간에만 알린다.
        XCTAssertFalse(candidate(true, true))
        XCTAssertFalse(candidate(false, false))
        XCTAssertFalse(candidate(false, true, enabled: false))
        XCTAssertFalse(DetectionCoordinator.shouldNotify(wasOnMicrophone: false, isOnMicrophone: true,
            enabled: true, recordingBusy: true, lastNotificationAt: nil, now: now))
        XCTAssertFalse(candidate(false, true, last: now.addingTimeInterval(-59)))
        XCTAssertTrue(candidate(false, true, last: now.addingTimeInterval(-60)))
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
