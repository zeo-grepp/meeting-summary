import Observation
import UserNotifications

private final class NotificationActionDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onAction: (@Sendable (String, String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        onAction?(response.actionIdentifier, response.notification.request.identifier)
        completionHandler()
    }
}

@MainActor @Observable
final class NotificationManager {
    static let startAction = "START_RECORDING"
    private static let category = "MEETING_CANDIDATE"
    private let center = UNUserNotificationCenter.current()
    private let actionDelegate = NotificationActionDelegate()
    var onAction: ((String, String) -> Void)?
    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var alertsEnabled = false
    private(set) var soundsEnabled = false
    private(set) var isRequesting = false
    private(set) var errorMessage: String?

    init() {
        actionDelegate.onAction = { [weak self] action, identifier in
            Task { @MainActor [weak self] in self?.onAction?(action, identifier) }
        }
        center.delegate = actionDelegate
        center.setNotificationCategories([
            // 배너는 액션이 둘 이상이면 "옵션" 메뉴로 접는다.
            // 액션 하나만 두어 "녹음 시작"을 버튼으로 노출하고, 무시는 배너의 닫기(X)로 받는다.
            UNNotificationCategory(identifier: Self.category, actions: [
                UNNotificationAction(identifier: Self.startAction, title: "녹음 시작", options: [.foreground])
            ], intentIdentifiers: [], options: [.customDismissAction])
        ])
    }

    var statusText: String {
        switch authorizationStatus {
        case .notDetermined: "아직 요청하지 않음"
        // 시스템 설정으로 가라는 안내는 옆의 버튼이 대신한다.
        case .denied: "거부됨"
        case .authorized: alertsEnabled ? "허용됨" : "허용됨 — 배너 표시 꺼짐"
        case .provisional: "조용한 알림 허용됨"
        case .ephemeral: "일시적으로 허용됨"
        case nil: "확인 중…"
        @unknown default: "알 수 없는 권한 상태"
        }
    }

    func refresh() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        alertsEnabled = settings.alertSetting == .enabled
        soundsEnabled = settings.soundSetting == .enabled
        if settings.authorizationStatus != .notDetermined { errorMessage = nil }
    }

    func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        errorMessage = nil
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            errorMessage = "알림 권한 요청에 실패했습니다: \(error.localizedDescription)"
        }
        await refresh()
    }

    func postCandidate(appName: String) async -> String? {
        await refresh()
        guard authorizationStatus == .authorized, alertsEnabled else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "회의가 시작되었나요?"
        content.body = "\(appName) 사용 중 마이크 입력이 감지됐어요.\n지금 녹음을 시작해보세요."
        content.sound = .default
        content.categoryIdentifier = Self.category
        let identifier = UUID().uuidString
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            return identifier
        } catch {
            errorMessage = "회의 알림을 표시하지 못했습니다: \(error.localizedDescription)"
            return nil
        }
    }

    func removeCandidate(_ identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
