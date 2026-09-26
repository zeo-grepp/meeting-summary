import AppKit
import SwiftUI

@MainActor @Observable
final class MeetingAssistantModel {
    let settings = SettingsStore()
    let notifications = NotificationManager()
    let detection: DetectionCoordinator

    init() {
        // 같은 번들이 둘 이상 떠 있으면 감지기도 둘이라 알림이 중복된다.
        // Xcode Run 중 이전 인스턴스가 남는 경우가 잦아 새로 뜬 쪽이 옛 인스턴스를 정리한다.
        for other in NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ) where other != .current {
            other.forceTerminate()
        }
        detection = DetectionCoordinator(settings: settings, notifications: notifications)
        detection.start()
    }
}

@main
struct MeetingAssistantApp: App {
    @State private var model = MeetingAssistantModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(settings: model.settings, detection: model.detection)
        } label: {
            Image(systemName: "person.2.wave.2.fill")
            if model.detection.recorder.isRecording {
                Text(model.detection.recorder.elapsedText)
            }
        }
        Settings {
            SettingsView(settings: model.settings, notifications: model.notifications)
        }
        .defaultSize(width: 560, height: 600)
    }
}
