import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import UserNotifications

@MainActor @Observable
final class DetectionCoordinator {
    let recorder = Recorder()
    private let settings: SettingsStore
    private let notifications: NotificationManager
    private let appDetector: AppDetector
    private let microphoneDetector = MicrophoneDetector()
    private var lastNotificationAt: Date?
    private var activeCandidateID: String?
    private var notificationInFlight = false
    private var recordingStartInFlight = false
    private(set) var runningApps: [WatchedApplication] = []
    private(set) var microphoneState: MicrophoneState = .unknown
    private(set) var isRunning = false
    private var reportedText: String?
    private var reportedAt: Date?
    /// 녹음 대상으로 고른 앱. 감시 앱이 둘 이상 실행 중일 때 무엇이 녹음되는지 보여주려고 둔다.
    private(set) var recordingAppName: String?

    /// 마지막 동작 결과. 메뉴를 열 때마다 다시 평가되므로 오래된 메시지는 타이머 없이 저절로 사라진다.
    var actionMessage: String? {
        guard let reportedText, let reportedAt,
              Date().timeIntervalSince(reportedAt) < 120 else { return nil }
        return reportedText
    }

    /// 녹음 실패, 폴더 열기 실패처럼 메뉴에 한 번 보여주면 되는 메시지를 모아 받는다.
    func report(_ text: String?) {
        reportedText = text
        reportedAt = text == nil ? nil : Date()
    }

    init(settings: SettingsStore, notifications: NotificationManager) {
        self.settings = settings
        self.notifications = notifications
        appDetector = AppDetector(settings: settings)
        recorder.onSaved = { [weak self] url in self?.renameSavedRecording(url) }
    }

    /// 저장이 끝난 뒤 이름을 물어본다. 취소하거나 실패해도 파일은 자동 이름으로 이미 그 자리에 있다.
    private func renameSavedRecording(_ url: URL) -> URL? {
        let panel = NSSavePanel()
        panel.title = "녹음 저장"
        panel.nameFieldLabel = "파일 이름:"
        panel.nameFieldStringValue = url.lastPathComponent
        panel.directoryURL = url.deletingLastPathComponent()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.prompt = "저장"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let target = panel.url, target != url else { return nil }
        do {
            // 덮어쓸지는 패널이 이미 물어봤다.
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            report("이름을 바꾸지 못해 \(url.lastPathComponent)로 저장했습니다: \(error.localizedDescription)")
            return nil
        }
    }

    var statusText: String {
        if !microphoneDetector.isRunning { return "오디오 입력 감지 불가" }
        switch microphoneState {
        case .unknown: return "오디오 입력 상태 확인 중"
        case .inactive: return "회의 감지 중"
        case .active: return "오디오 입력 사용 중"
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        settings.onDetectionSettingsChange = { [weak self] in
            guard let self else { return }
            self.appDetector.refresh()
            self.clearInvalidCandidate()
        }
        appDetector.onChange = { [weak self] apps in
            self?.runningApps = apps
            self?.clearInvalidCandidate()
        }
        microphoneDetector.onChange = { [weak self] state in self?.updateMicrophone(state) }
        notifications.onAction = { [weak self] action, identifier in self?.handleAction(action, identifier: identifier) }
        appDetector.start()
        microphoneDetector.start()
        microphoneState = microphoneDetector.state
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        settings.onDetectionSettingsChange = nil
        notifications.onAction = nil
        appDetector.stop()
        microphoneDetector.stop()
        if let id = activeCandidateID { notifications.removeCandidate(id) }
        activeCandidateID = nil
        runningApps = []
        microphoneState = .unknown
    }

    private func updateMicrophone(_ next: MicrophoneState) {
        let previous = microphoneState
        microphoneState = next
        print("Meeting Assistant input: \(previous) → \(next), watched apps: \(runningApps.map(\.displayName))")
        if next != .active, let id = activeCandidateID {
            notifications.removeCandidate(id)
            activeCandidateID = nil
        }
        guard Self.shouldNotify(previous: previous, current: next,
                                hasWatchedApp: !runningApps.isEmpty,
                                enabled: settings.notificationsEnabled,
                                recordingBusy: recorder.isBusy || recordingStartInFlight,
                                lastNotificationAt: lastNotificationAt,
                                now: Date()), !notificationInFlight else { return }
        let app = runningApps[0]
        print("Meeting Assistant candidate: \(app.displayName)")
        notificationInFlight = true
        Task {
            defer { notificationInFlight = false }
            guard let id = await notifications.postCandidate(appName: app.displayName) else {
                print("Meeting Assistant notification unavailable: \(notifications.statusText), \(notifications.errorMessage ?? "no error")")
                return
            }
            print("Meeting Assistant notification delivered: \(id)")
            lastNotificationAt = Date()
            if microphoneState == .active && settings.notificationsEnabled && !runningApps.isEmpty {
                activeCandidateID = id
            } else {
                notifications.removeCandidate(id)
            }
        }
    }

    private func clearInvalidCandidate() {
        guard (!settings.notificationsEnabled || runningApps.isEmpty), let id = activeCandidateID else { return }
        notifications.removeCandidate(id)
        activeCandidateID = nil
    }

    static func shouldNotify(previous: MicrophoneState, current: MicrophoneState,
                             hasWatchedApp: Bool, enabled: Bool, recordingBusy: Bool = false,
                             lastNotificationAt: Date?, now: Date) -> Bool {
        previous == .inactive && current == .active && hasWatchedApp && enabled && !recordingBusy
            && (lastNotificationAt.map { now.timeIntervalSince($0) >= 60 } ?? true)
    }

    func startRecording(app: WatchedApplication? = nil) {
        guard !recorder.isBusy && !recordingStartInFlight else { return }
        if let id = activeCandidateID { notifications.removeCandidate(id) }
        activeCandidateID = nil
        report(nil)
        recordingStartInFlight = true
        let target = app ?? runningApps.first
        recordingAppName = target?.displayName
        Task {
            defer { recordingStartInFlight = false }
            do { try await recorder.start(in: settings.recordingsURL,
                                          appBundleIdentifier: target?.bundleIdentifier) }
            catch {
                recordingAppName = nil
                report(error.localizedDescription)
                let alert = NSAlert()
                alert.messageText = "녹음을 시작하지 못했습니다"
                alert.informativeText = error.localizedDescription
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    func stopRecording() {
        Task {
            do { try await recorder.stop() }
            catch { report(error.localizedDescription) }
        }
    }

    private func handleAction(_ action: String, identifier: String) {
        guard identifier == activeCandidateID,
              action == NotificationManager.startAction || action == UNNotificationDismissActionIdentifier
                || action == UNNotificationDefaultActionIdentifier else { return }
        activeCandidateID = nil
        notifications.removeCandidate(identifier)
        // 배너 본문 클릭(default action)은 macOS 관례상 "앱 열기"다.
        // 녹음은 "녹음 시작" 버튼을 눌렀을 때만 시작한다.
        if action == NotificationManager.startAction { startRecording() }
    }
}
