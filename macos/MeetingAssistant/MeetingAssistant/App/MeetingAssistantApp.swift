import SwiftUI

@MainActor @Observable
final class MeetingAssistantModel {
    let settings = SettingsStore()
    let notifications = NotificationManager()
    let detection: DetectionCoordinator

    init() {
        detection = DetectionCoordinator(settings: settings, notifications: notifications)
        detection.start()
    }
}

@main
struct MeetingAssistantApp: App {
    @State private var model = MeetingAssistantModel()

    var body: some Scene {
        MenuBarExtra("Meeting Assistant", systemImage: "mic") {
            MenuBarView(settings: model.settings, detection: model.detection)
        }
        Settings {
            SettingsView(settings: model.settings, notifications: model.notifications)
        }
        .defaultSize(width: 560, height: 600)
    }
}
