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
    static let retryAction = "RETRY_SUMMARY"
    private static let category = "MEETING_CANDIDATE"
    private static let summaryCategory = "SUMMARY_DONE"
    private static let failureCategory = "SUMMARY_FAILED"
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
            ], intentIdentifiers: [], options: [.customDismissAction]),
            // 본문을 누르면 회의록을 여는 것 말고 할 일이 없어 액션을 두지 않는다.
            UNNotificationCategory(identifier: Self.summaryCategory, actions: [],
                                   intentIdentifiers: [], options: []),
            // 실패는 대부분 고친 뒤 다시 돌리면 된다. 메뉴를 열러 가지 않아도 되게 버튼으로 둔다.
            UNNotificationCategory(identifier: Self.failureCategory, actions: [
                UNNotificationAction(identifier: Self.retryAction, title: "다시 만들기", options: [.foreground])
            ], intentIdentifiers: [], options: [])
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
        await post(title: "회의가 시작되었나요?",
                   body: "\(appName) 사용 중 마이크 입력이 감지됐어요.\n지금 녹음을 시작해보세요.",
                   category: Self.category, whatFailed: "회의 알림")
    }

    /// 작업 완료 알림. "회의 감지 알림" 설정과는 별개이므로 권한만 확인한다.
    func postSummary(title: String) async -> String? {
        await post(title: "회의록이 준비됐어요", body: "\(title)\n눌러서 열어보세요.",
                   category: Self.summaryCategory, whatFailed: "회의록 완료 알림")
    }

    /// 실패는 성공보다 더 알려야 한다. 메뉴를 열어보지 않으면 조용히 지나가기 때문이다.
    func postFailure(reason: String) async -> String? {
        await post(title: "회의록을 만들지 못했어요", body: reason,
                   category: Self.failureCategory, whatFailed: "회의록 실패 알림")
    }

    private func post(title: String, body: String, category: String, whatFailed: String) async -> String? {
        await refresh()
        guard authorizationStatus == .authorized, alertsEnabled else { return nil }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        let identifier = UUID().uuidString
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            return identifier
        } catch {
            errorMessage = "\(whatFailed)을 표시하지 못했습니다: \(error.localizedDescription)"
            return nil
        }
    }

    func removeCandidate(_ identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
