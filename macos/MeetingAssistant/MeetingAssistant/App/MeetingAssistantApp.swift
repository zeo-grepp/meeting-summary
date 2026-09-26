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

/// 메뉴바 아이콘. 설정이 비어 있으면 첫 실행에서 설정 창을 띄우는 역할도 겸한다.
/// (Dock 아이콘이 없는 앱이라 메뉴를 직접 열기 전까지는 아무 신호가 없다.)
/// 경과 시간 Text는 이 뷰 안에 넣지 않는다 — MenuBarExtra 라벨은 Image/Text가
/// 형제로 놓여야 둘 다 표시된다.
private struct MenuBarIcon: View {
    let settings: SettingsStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: "person.2.wave.2.fill")
            .task {
                guard !settings.isConfigured else { return }
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
    }
}

@main
struct MeetingAssistantApp: App {
    @State private var model = MeetingAssistantModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(settings: model.settings, detection: model.detection)
        } label: {
            MenuBarIcon(settings: model.settings)
            // 메뉴가 닫혀 있어도 보이는 유일한 자리다.
            // ⌘Q로 종료할 때 저장이 끝날 때까지 기다리는 동안의 유일한 피드백이기도 하다.
            if model.detection.recorder.isRecording {
                Text(model.detection.recorder.elapsedText)
            } else if model.detection.recorder.isFinishing {
                Text("저장 중…")
            } else if model.detection.recorder.isStarting {
                Text("준비 중…")
            } else if model.detection.summaryRunner.isRunning {
                Text("회의록 만드는 중…")
            }
        }
        Settings {
            SettingsView(settings: model.settings, notifications: model.notifications)
        }
        .defaultSize(width: 560, height: 600)
    }
}
