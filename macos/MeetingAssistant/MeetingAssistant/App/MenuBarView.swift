import AppKit
import SwiftUI

struct MenuBarView: View {
    let settings: SettingsStore
    @Environment(\.openSettings) private var openSettings
    @State private var errorMessage: String?

    var body: some View {
        Text("Meeting Assistant")
        Text("회의 감지: 준비 중 (Phase 2)")
        Text("녹음: 아직 지원하지 않음 (Phase 3)")
        Divider()
        Text("감시 대상으로 선택한 앱: \(settings.watchedApplications.filter(\.isEnabled).count)개")
        Button("녹음 시작 — 준비 중") {}.disabled(true)
        Button("녹음 폴더 열기") {
            guard let url = settings.recordingsURL else { return }
            if !NSWorkspace.shared.open(url) {
                errorMessage = "녹음 폴더를 열 수 없습니다. 설정의 프로젝트 경로와 recordings 폴더를 확인해주세요."
            }
        }
        .disabled(settings.recordingsURL == nil)
        if let errorMessage { Text(errorMessage) }
        Divider()
        Button("설정…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Button("종료") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
