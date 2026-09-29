import XCTest

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testSettingsSurviveReloadAndRejectInvalidSelections() throws {
        let suite = "MeetingAssistantTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Test.app")
        let contents = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "example.test", "CFBundleName": "Test App", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let notADirectory = root.appendingPathComponent("file.txt")
        try Data().write(to: notADirectory)

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.watchedApplications.isEmpty)
        XCTAssertFalse(store.notificationsEnabled)
        XCTAssertNil(store.recordingsURL)
        try store.addApplication(at: appURL)
        store.watchedApplications[0].isEnabled = false
        try store.addApplication(at: appURL)
        XCTAssertEqual(store.watchedApplications.count, 1)
        XCTAssertEqual(store.watchedApplications[0].displayName, "Test App")
        XCTAssertFalse(store.watchedApplications[0].isEnabled)
        XCTAssertThrowsError(try store.addApplication(at: root))
        try store.selectProject(at: root)
        XCTAssertThrowsError(try store.selectProject(at: notADirectory))
        store.notificationsEnabled = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.watchedApplications, store.watchedApplications)
        XCTAssertTrue(reloaded.notificationsEnabled)
        XCTAssertEqual(reloaded.projectRootPath, root.standardizedFileURL.path)
        XCTAssertEqual(reloaded.recordingsURL?.lastPathComponent, "recordings")
        reloaded.watchedApplications.removeAll()
        XCTAssertTrue(SettingsStore(defaults: defaults).watchedApplications.isEmpty)
    }

    func testCorruptSettingsAreReportedWithoutOverwritingSavedData() throws {
        let suite = "MeetingAssistantTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("invalid json".utf8)
        defaults.set(data, forKey: "watchedApplications")
        let store = SettingsStore(defaults: defaults)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(defaults.data(forKey: "watchedApplications"), data)
    }
}
