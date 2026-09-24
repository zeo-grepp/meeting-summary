import AppKit
import SwiftUI

struct MenuBarView: View {
    let settings: SettingsStore
    let detection: DetectionCoordinator
    @Environment(\.openSettings) private var openSettings
    @State private var errorMessage: String?

    var body: some View {
        Text("Meeting Assistant")
        Text("회의 감지: \(detection.statusText)")
        if let app = detection.runningApps.first { Text("감시 앱 실행 중: \(app.displayName)") }
        if let message = detection.actionMessage { Text(message) }
        if let startedAt = detection.recorder.startedAt {
            Text("🔴 녹음 중 · 시작: \(startedAt.formatted(date: .omitted, time: .shortened))")
        } else if detection.recorder.isStarting {
            Text("녹음 권한 확인 및 준비 중…")
        } else if detection.recorder.isFinishing {
            Text("녹음 파일 저장 중…")
        } else {
            Text("녹음 중이 아님")
        }
        if let error = detection.recorder.errorMessage { Text(error) }
        if let url = detection.recorder.lastSavedURL { Text("최근 녹음: \(url.lastPathComponent)") }
        Divider()
        Text("감시 대상으로 선택한 앱: \(settings.watchedApplications.filter(\.isEnabled).count)개")
        if detection.recorder.isRecording {
            Button("녹음 종료") { detection.stopRecording() }
        } else {
            Button("녹음 시작") { detection.startRecording() }
                .disabled(detection.recorder.isBusy || settings.recordingsURL == nil
                          || detection.runningApps.isEmpty)
        }
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
        Button("종료") {
            Task {
                while detection.recorder.isStarting { try? await Task.sleep(for: .milliseconds(100)) }
                if detection.recorder.isRecording { detection.stopRecording() }
                while detection.recorder.isBusy { try? await Task.sleep(for: .milliseconds(100)) }
                NSApp.terminate(nil)
            }
        }
            .keyboardShortcut("q")
    }
}
