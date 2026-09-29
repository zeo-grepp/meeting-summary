import AppKit
import SwiftUI

struct MenuBarView: View {
    let settings: SettingsStore
    let detection: DetectionCoordinator
    @Environment(\.openSettings) private var openSettings

    /// 동작 실패 메시지는 출처가 어디든(감지기/레코더/요약기) 한 줄로만 보여준다.
    private var alertMessage: String? {
        detection.actionMessage ?? detection.recorder.errorMessage ?? detection.summaryRunner.errorMessage
    }

    /// 메뉴 폭은 가장 긴 항목이 정한다. 오류 메시지나 긴 파일명 하나가 화면을 가로지르지 않게 자른다.
    private func short(_ text: String, _ limit: Int = 40) -> String {
        text.count <= limit ? text : text.prefix(limit) + "…"
    }

    /// "녹음 시작"이 비활성인 이유. macOS 메뉴 항목은 툴팁이 없어 직접 적어주지 않으면 알 길이 없다.
    private var startBlockReason: String? {
        guard !detection.recorder.isBusy else { return nil }
        if settings.recordingsURL == nil { return "설정에서 저장 폴더를 먼저 선택해주세요." }
        return nil
    }

    var body: some View {
        Text("회의 감지: \(detection.statusText)")
        if !detection.runningApps.isEmpty {
            Text(short("감시 앱 실행 중: \(detection.runningApps.map(\.displayName).joined(separator: ", "))"))
        }
        if detection.recorder.isRecording {
            // 경과 시간은 바로 위 메뉴바 라벨이 보여준다. 여기에 두면 초마다 메뉴가
            // 다시 그려져 마우스가 올라간 항목에서 포커스가 튄다.
            Text("🔴 \(detection.recordingAppName ?? "녹음") 녹음 중")
        } else if detection.recorder.isStarting {
            Text("녹음 권한 확인 및 준비 중…")
        } else if detection.recorder.isFinishing {
            Text("녹음 파일 저장 중…")
        } else {
            Text("녹음 중이 아님")
        }
        if let stageText = detection.summaryRunner.stageText {
            Text("회의록 만드는 중 · \(stageText)")
        }
        if let alertMessage { Text(short("⚠️ \(alertMessage)", 60)) }
        if let url = detection.recorder.lastSavedURL {
            Button(short("최근 녹음: \(url.lastPathComponent)")) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        if let url = detection.summaryRunner.lastSummaryURL {
            Button(short("최근 회의록: \(url.lastPathComponent)")) { NSWorkspace.shared.open(url) }
        }
        if let audio = detection.summaryRunner.lastAudioURL {
            Button("회의록 다시 만들기") {
                detection.summaryRunner.run(audio: audio, projectRoot: settings.projectRootURL)
            }
            .disabled(detection.summaryRunner.isRunning)
        }
        Divider()
        if let startBlockReason { Text(startBlockReason) }
        if detection.recorder.isRecording {
            Button("녹음 종료") { detection.stopRecording() }
        } else {
            Button("녹음 시작") { detection.startRecording() }
                .disabled(detection.recorder.isBusy || settings.recordingsURL == nil)
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
                // 녹음 파일은 이미 디스크에 있다. 회의록은 다음에 다시 만들면 된다.
                detection.summaryRunner.cancel()
                while detection.recorder.isStarting { try? await Task.sleep(for: .milliseconds(100)) }
                if detection.recorder.isRecording { detection.stopRecording() }
                while detection.recorder.isBusy { try? await Task.sleep(for: .milliseconds(100)) }
                NSApp.terminate(nil)
            }
        }
            .keyboardShortcut("q")
    }
}
