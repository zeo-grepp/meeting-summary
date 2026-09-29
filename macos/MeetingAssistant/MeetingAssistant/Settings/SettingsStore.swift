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
    /// 사내 게이트웨이를 쓰면 주소와 모델 이름이 다르다.
    var anthropicBaseURL: String {
        didSet { defaults.set(anthropicBaseURL, forKey: "anthropicBaseURL") }
    }
    var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: "anthropicModel") }
    }
    var notionDatabaseID: String {
        didSet { defaults.set(notionDatabaseID, forKey: "notionDatabaseID") }
    }
    /// 전사 고유명사 보정. 팀마다 다르고, 배포본에는 붙어 있을 파일이 없다.
    var transcriptionPrompt: String {
        didSet { defaults.set(transcriptionPrompt, forKey: "transcriptionPrompt") }
    }
    /// 비밀값은 Keychain에만 둔다.
    var anthropicAPIKey: String {
        didSet { Keychain.set(anthropicAPIKey, for: "anthropicAPIKey") }
    }
    var notionToken: String {
        didSet { Keychain.set(notionToken, for: "notionToken") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        projectRootPath = defaults.string(forKey: "projectRootPath") ?? ""
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        // 저장값이 없으면 환경변수를 한 번 본다. Xcode scheme으로 돌려온 설정을 그대로 받는다.
        let environment = ProcessInfo.processInfo.environment
        func saved(_ key: String, _ variable: String, _ fallback: String = "") -> String {
            defaults.string(forKey: key) ?? environment[variable] ?? fallback
        }
        anthropicBaseURL = saved("anthropicBaseURL", "ANTHROPIC_BASE_URL", "https://api.anthropic.com")
        anthropicModel = saved("anthropicModel", "ANTHROPIC_MODEL", "claude-sonnet-5")
        notionDatabaseID = saved("notionDatabaseID", "NOTION_DATABASE_ID")
        transcriptionPrompt = defaults.string(forKey: "transcriptionPrompt") ?? ""
        anthropicAPIKey = Keychain.string(for: "anthropicAPIKey").isEmpty
            ? environment["ANTHROPIC_API_KEY"] ?? "" : Keychain.string(for: "anthropicAPIKey")
        notionToken = Keychain.string(for: "notionToken").isEmpty
            ? environment["NOTION_TOKEN"] ?? "" : Keychain.string(for: "notionToken")
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
