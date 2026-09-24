import SwiftUI

@main
struct MeetingAssistantApp: App {
    @State private var settings = SettingsStore()
    @State private var notifications = NotificationManager()

    var body: some Scene {
        MenuBarExtra("Meeting Assistant", systemImage: "mic") {
            MenuBarView(settings: settings)
        }
        Settings {
            SettingsView(settings: settings, notifications: notifications)
        }
        .defaultSize(width: 560, height: 600)
    }
}
