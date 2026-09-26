import AppKit
import SwiftUI

struct MenuBarView: View {
    let settings: SettingsStore
    let detection: DetectionCoordinator
    @Environment(\.openSettings) private var openSettings

    /// 동작 실패 메시지는 출처가 어디든(감지기/레코더/폴더 열기) 한 줄로만 보여준다.
    private var alertMessage: String? {
        detection.actionMessage ?? detection.recorder.errorMessage
    }

    /// "녹음 시작"이 비활성인 이유. macOS 메뉴 항목은 툴팁이 없어 직접 적어주지 않으면 알 길이 없다.
    private var startBlockReason: String? {
        guard !detection.recorder.isBusy else { return nil }
        if settings.recordingsURL == nil { return "설정에서 meeting.py가 있는 프로젝트 폴더를 먼저 선택해주세요." }
        if !settings.watchedApplications.contains(where: \.isEnabled) {
            return "설정에서 감시할 앱을 먼저 추가해주세요."
        }
        if detection.runningApps.isEmpty { return "감시 앱이 실행 중이 아닙니다." }
        return nil
    }

    var body: some View {
        Text("Meeting Assistant")
        Text("회의 감지: \(detection.statusText)")
        if !detection.runningApps.isEmpty {
            Text("감시 앱 실행 중: \(detection.runningApps.map(\.displayName).joined(separator: ", "))")
        }
        if let startedAt = detection.recorder.startedAt {
            Text("🔴 \(detection.recordingAppName ?? "녹음") 녹음 중 · 시작: \(startedAt.formatted(date: .omitted, time: .shortened))")
        } else if detection.recorder.isStarting {
            Text("녹음 권한 확인 및 준비 중…")
        } else if detection.recorder.isFinishing {
            Text("녹음 파일 저장 중…")
        } else {
            Text("녹음 중이 아님")
        }
        if let alertMessage { Text("⚠️ \(alertMessage)") }
        if let url = detection.recorder.lastSavedURL { Text("최근 녹음: \(url.lastPathComponent)") }
        Divider()
        if let startBlockReason { Text(startBlockReason) }
        if detection.recorder.isRecording {
            Button("녹음 종료") { detection.stopRecording() }
        } else if detection.runningApps.count > 1 {
            // 어느 앱 소리를 녹음할지 조용히 고르지 않고 직접 고르게 한다.
            Menu("녹음 시작") {
                ForEach(detection.runningApps) { app in
                    Button(app.displayName) { detection.startRecording(app: app) }
                }
            }
            .disabled(detection.recorder.isBusy || settings.recordingsURL == nil)
        } else {
            Button("녹음 시작") { detection.startRecording() }
                .disabled(detection.recorder.isBusy || settings.recordingsURL == nil
                          || detection.runningApps.isEmpty)
        }
        Button("녹음 폴더 열기") {
            guard let url = settings.recordingsURL else { return }
            if !NSWorkspace.shared.open(url) {
                detection.report("녹음 폴더를 열 수 없습니다. 설정의 프로젝트 경로와 recordings 폴더를 확인해주세요.")
            }
        }
        .disabled(settings.recordingsURL == nil)
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
