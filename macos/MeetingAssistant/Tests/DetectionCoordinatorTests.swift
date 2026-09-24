import XCTest

@MainActor final class DetectionCoordinatorTests: XCTestCase {
    func testOnlyWatchedAppAndNewInputTransitionTriggersWithinCooldown() {
        let now = Date(timeIntervalSince1970: 1_000)
        func candidate(_ previous: MicrophoneState, _ current: MicrophoneState,
                       watched: Bool = true, enabled: Bool = true, last: Date? = nil) -> Bool {
            DetectionCoordinator.shouldNotify(previous: previous, current: current,
                                              hasWatchedApp: watched, enabled: enabled,
                                              lastNotificationAt: last, now: now)
        }

        XCTAssertTrue(candidate(.inactive, .active))
        XCTAssertFalse(candidate(.unknown, .active))
        XCTAssertFalse(candidate(.active, .active))
        XCTAssertFalse(candidate(.inactive, .inactive))
        XCTAssertFalse(candidate(.inactive, .active, watched: false))
        XCTAssertFalse(candidate(.inactive, .active, enabled: false))
        XCTAssertFalse(candidate(.inactive, .active, last: now.addingTimeInterval(-59)))
        XCTAssertTrue(candidate(.inactive, .active, last: now.addingTimeInterval(-60)))
    }
}
