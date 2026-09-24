import AVFAudio
import AppKit
import Foundation
import Observation

@MainActor @Observable
final class Recorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var statusTimer: Timer?
    private(set) var isStarting = false
    private(set) var startedAt: Date?
    private(set) var lastSavedURL: URL?
    private(set) var errorMessage: String?

    var isRecording: Bool { startedAt != nil }
    var isBusy: Bool { isStarting || isRecording }

    func start(in directory: URL?) async throws {
        guard !isBusy else { return }
        guard let directory else { throw RecordingError.projectNotSelected }
        guard FileManager.default.fileExists(atPath: directory.deletingLastPathComponent()
            .appendingPathComponent("meeting.py").path) else { throw RecordingError.projectNotSelected }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecordingError.microphoneDenied
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "\(Self.filenameDateFormatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).m4a"
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        guard recorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw RecordingError.couldNotStart
        }
        audioRecorder = recorder
        startedAt = Date()
        showRecordingStatus()
    }

    @discardableResult
    func stop() throws -> URL? {
        guard let audioRecorder else { return nil }
        let url = audioRecorder.url
        audioRecorder.stop()
        self.audioRecorder = nil
        startedAt = nil
        hideRecordingStatus()
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        guard size > 0 else { throw RecordingError.emptyFile }
        guard (try AVAudioPlayer(contentsOf: url)).duration > 0 else { throw RecordingError.emptyFile }
        lastSavedURL = url
        errorMessage = nil
        return url
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private func showRecordingStatus() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "녹음 중")
        let menu = NSMenu()
        let stopItem = NSMenuItem(title: "녹음 종료", action: #selector(stopFromStatusMenu), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)
        item.menu = menu
        statusItem = item
        updateStatusTitle()
        statusTimer = Timer.scheduledTimer(timeInterval: 1, target: self,
                                           selector: #selector(updateStatusTitle), userInfo: nil, repeats: true)
    }

    @objc private func updateStatusTitle() {
        guard let startedAt else { return }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        statusItem?.button?.title = String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    @objc private func stopFromStatusMenu() {
        do { try stop() }
        catch { errorMessage = error.localizedDescription }
    }

    private func hideRecordingStatus() {
        statusTimer?.invalidate()
        statusTimer = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private enum RecordingError: LocalizedError {
        case projectNotSelected, microphoneDenied, couldNotStart, emptyFile

        var errorDescription: String? {
            switch self {
            case .projectNotSelected: "설정에서 meeting.py가 있는 프로젝트 폴더를 먼저 선택해주세요."
            case .microphoneDenied: "마이크 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 Meeting Assistant를 허용해주세요."
            case .couldNotStart: "녹음을 시작하지 못했습니다. 입력 장치를 확인해주세요."
            case .emptyFile: "녹음 파일이 비어 있습니다. 입력 장치를 확인한 뒤 다시 시도해주세요."
            }
        }
    }
}

extension Recorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        let url = recorder.url
        Task { @MainActor [weak self] in self?.failIfCurrent(url, message: "녹음이 예상치 않게 종료되었습니다.") }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let url = recorder.url
        let message = "녹음 인코딩 오류: \(error?.localizedDescription ?? "알 수 없는 오류")"
        Task { @MainActor [weak self] in self?.failIfCurrent(url, message: message) }
    }

    private func failIfCurrent(_ url: URL, message: String) {
        guard audioRecorder?.url == url else { return }
        audioRecorder?.stop()
        audioRecorder = nil
        startedAt = nil
        hideRecordingStatus()
        errorMessage = message
    }
}
