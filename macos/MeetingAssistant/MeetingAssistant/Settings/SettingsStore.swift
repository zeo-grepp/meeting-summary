import Foundation
import Observation

@MainActor @Observable
final class SettingsStore {
    private let defaults: UserDefaults
    @ObservationIgnored var onDetectionSettingsChange: (() -> Void)?
    var errorMessage: String?

    var watchedApplications: [WatchedApplication] {
        didSet {
            do {
                defaults.set(try JSONEncoder().encode(watchedApplications), forKey: "watchedApplications")
            } catch {
                errorMessage = "감시 앱 설정을 저장하지 못했습니다: \(error.localizedDescription)"
            }
            onDetectionSettingsChange?()
        }
    }
    var projectRootPath: String {
        didSet { defaults.set(projectRootPath, forKey: "projectRootPath") }
    }
    var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
            onDetectionSettingsChange?()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        projectRootPath = defaults.string(forKey: "projectRootPath") ?? ""
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        watchedApplications = []
        if let data = defaults.data(forKey: "watchedApplications") {
            do {
                watchedApplications = try JSONDecoder().decode([WatchedApplication].self, from: data)
            } catch {
                errorMessage = "저장된 감시 앱 설정을 읽지 못했습니다. 앱을 다시 추가해주세요."
            }
        }
    }

    func addApplication(at url: URL) throws {
        let app = try WatchedApplication(url: url)
        // Re-adding an app preserves its existing enabled/disabled preference.
        guard !watchedApplications.contains(where: { $0.id == app.id }) else { return }
        watchedApplications.append(app)
    }

    /// 녹음·녹취록·회의록이 모일 폴더. 앱이 하위에 recordings/transcripts/summaries를 만든다.
    func selectProject(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard url.isFileURL,
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "폴더를 선택해주세요."
            ])
        }
        projectRootPath = url.standardizedFileURL.path
    }

    var isConfigured: Bool {
        !projectRootPath.isEmpty && watchedApplications.contains(where: \.isEnabled)
    }

    var projectRootURL: URL? {
        projectRootPath.isEmpty ? nil : URL(fileURLWithPath: projectRootPath, isDirectory: true)
    }

    var recordingsURL: URL? {
        projectRootURL?.appendingPathComponent("recordings", isDirectory: true)
    }
}
