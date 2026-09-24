import Observation
import UserNotifications

@MainActor @Observable
final class NotificationManager {
    private let center = UNUserNotificationCenter.current()
    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var alertsEnabled = false
    private(set) var isRequesting = false
    private(set) var errorMessage: String?

    var statusText: String {
        switch authorizationStatus {
        case .notDetermined: "아직 요청하지 않음"
        case .denied: "거부됨 — 시스템 설정 > 알림에서 변경해주세요."
        case .authorized: alertsEnabled ? "허용됨" : "허용됨 — 배너/알림 표시는 꺼져 있습니다."
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
        if settings.authorizationStatus != .notDetermined { errorMessage = nil }
    }

    func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        errorMessage = nil
        do {
            _ = try await center.requestAuthorization(options: [.alert])
        } catch {
            errorMessage = "알림 권한 요청에 실패했습니다: \(error.localizedDescription)"
        }
        await refresh()
    }
}
