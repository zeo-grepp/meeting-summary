import AppKit
import Foundation
import Observation

@MainActor @Observable
final class DetectionCoordinator {
    private let settings: SettingsStore
    private let notifications: NotificationManager
    private let appDetector: AppDetector
    private let microphoneDetector = MicrophoneDetector()
    private var lastNotificationAt: Date?
    private var activeCandidateID: String?
    private var notificationInFlight = false
    private(set) var runningApps: [WatchedApplication] = []
    private(set) var microphoneState: MicrophoneState = .unknown
    private(set) var isRunning = false
    private(set) var actionMessage: String?

    init(settings: SettingsStore, notifications: NotificationManager) {
        self.settings = settings
        self.notifications = notifications
        appDetector = AppDetector(settings: settings)
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
                             hasWatchedApp: Bool, enabled: Bool,
                             lastNotificationAt: Date?, now: Date) -> Bool {
        previous == .inactive && current == .active && hasWatchedApp && enabled
            && (lastNotificationAt.map { now.timeIntervalSince($0) >= 60 } ?? true)
    }

    private func handleAction(_ action: String, identifier: String) {
        guard identifier == activeCandidateID,
              action == NotificationManager.startAction || action == NotificationManager.ignoreAction else { return }
        activeCandidateID = nil
        notifications.removeCandidate(identifier)
        if action == NotificationManager.startAction {
            actionMessage = "녹음 기능은 Phase 3에서 제공됩니다."
            let alert = NSAlert()
            alert.messageText = "아직 녹음을 시작할 수 없습니다"
            alert.informativeText = actionMessage ?? ""
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
