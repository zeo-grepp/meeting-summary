import AVFAudio
import AVFoundation
import AppKit
import Observation
import ScreenCaptureKit

@MainActor @Observable
final class Recorder: NSObject {
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var recordingOutput: SCRecordingOutput?
    @ObservationIgnored private var temporaryURL: URL?
    @ObservationIgnored private var outputURL: URL?
    @ObservationIgnored private var finishContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var elapsedTimer: Timer?
    private(set) var isStarting = false
    private(set) var isFinishing = false
    private(set) var startedAt: Date?
    private(set) var elapsedSeconds = 0
    private(set) var lastSavedURL: URL?
    private(set) var errorMessage: String?

    var isRecording: Bool { startedAt != nil }
    var isBusy: Bool { isStarting || isRecording || isFinishing }
    /// 메뉴바는 자리가 좁다. 1시간을 넘기기 전에는 시(時) 자리를 쓰지 않는다.
    var elapsedText: String {
        let hours = elapsedSeconds / 3600, minutes = elapsedSeconds / 60 % 60, seconds = elapsedSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    func start(in directory: URL?, appBundleIdentifier: String?) async throws {
        guard !isBusy else { return }
        guard let directory, FileManager.default.fileExists(atPath: directory.deletingLastPathComponent()
            .appendingPathComponent("meeting.py").path) else { throw RecordingError.projectNotSelected }
        guard let appBundleIdentifier else { throw RecordingError.appNotRunning }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        guard await AVAudioApplication.requestRecordPermission() else { throw RecordingError.microphoneDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first,
              let app = content.applications.first(where: { $0.bundleIdentifier == appBundleIdentifier })
        else { throw RecordingError.appNotRunning }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(Self.filenameDateFormatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
        let temporaryURL = directory.appendingPathComponent(".\(name)-capture.mp4")
        let outputURL = directory.appendingPathComponent("\(name).m4a")
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 16
        configuration.height = 16
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let fileConfiguration = SCRecordingOutputConfiguration()
        fileConfiguration.outputURL = temporaryURL
        let recordingOutput = SCRecordingOutput(configuration: fileConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.temporaryURL = temporaryURL
        self.outputURL = outputURL
        do { try await stream.startCapture() }
        catch {
            clearCapture()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        guard self.stream != nil else { throw RecordingError.couldNotStart }
        startedAt = Date()
        startElapsedTimer()
    }

    @discardableResult
    func stop() async throws -> URL? {
        guard let stream, !isFinishing else { return nil }
        isFinishing = true
        defer { isFinishing = false }
        stopElapsedTimer()
        startedAt = nil
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            finishContinuation = continuation
            Task {
                do { try await stream.stopCapture() }
                catch { finishRecording(with: error) }
            }
        }
        return try await exportCapture()
    }

    // stop()으로 정상 종료했을 때든, macOS의 화면 녹화 중지 버튼 등으로
    // 스트림이 예기치 않게 끊겼을 때든 항상 이 함수를 거쳐야 파일이 .m4a로 저장된다.
    private func exportCapture() async throws -> URL? {
        guard let temporaryURL, let outputURL else {
            clearCapture()
            return nil
        }
        do {
            let asset = AVURLAsset(url: temporaryURL)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard audioTracks.count == 1 else { throw RecordingError.exportFailed }
            let composition = AVMutableComposition()
            guard let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                               preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw RecordingError.exportFailed }
            let duration = try await asset.load(.duration)
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                           of: audioTracks[0], at: .zero)
            guard let exporter = AVAssetExportSession(asset: composition,
                                                      presetName: AVAssetExportPresetPassthrough)
            else { throw RecordingError.exportFailed }
            try await exporter.export(to: outputURL, as: .m4a)
            guard (try AVAudioPlayer(contentsOf: outputURL)).duration > 0 else {
                throw RecordingError.emptyFile
            }
            try FileManager.default.removeItem(at: temporaryURL)
            lastSavedURL = outputURL
            errorMessage = nil
            clearCapture()
            return outputURL
        } catch {
            errorMessage = "녹음 저장 실패: \(error.localizedDescription)"
            clearCapture()
            throw error
        }
    }

    private func finishRecording(with error: Error? = nil) {
        guard let continuation = finishContinuation else {
            guard let stream else { return }
            stopElapsedTimer()
            startedAt = nil
            isFinishing = true
            self.stream = nil
            recordingOutput = nil
            Task { @MainActor [weak self] in
                try? await stream.stopCapture()
                _ = try? await self?.exportCapture()
                self?.isFinishing = false
            }
            return
        }
        finishContinuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    private func clearCapture() {
        stream = nil
        recordingOutput = nil
        temporaryURL = nil
        outputURL = nil
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private func startElapsedTimer() {
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedSeconds = 0
    }

    private enum RecordingError: LocalizedError {
        case projectNotSelected, appNotRunning, microphoneDenied, couldNotStart, exportFailed, emptyFile

        var errorDescription: String? {
            switch self {
            case .projectNotSelected: "설정에서 meeting.py가 있는 프로젝트 폴더를 먼저 선택해주세요."
            case .appNotRunning: "녹음할 감시 앱을 실행한 뒤 다시 시도해주세요."
            case .microphoneDenied: "마이크 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 Meeting Assistant를 허용해주세요."
            case .couldNotStart: "앱 소리 녹음을 시작하지 못했습니다. 화면·시스템 오디오 녹음 권한을 확인해주세요."
            case .exportFailed: "녹음을 .m4a 파일로 변환하지 못했습니다."
            case .emptyFile: "녹음 파일이 비어 있습니다. 입력 장치를 확인한 뒤 다시 시도해주세요."
            }
        }
    }
}

extension Recorder: SCRecordingOutputDelegate, SCStreamDelegate {
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.finishRecording() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.errorMessage = "녹음 실패: \(error.localizedDescription)"
            self?.finishRecording(with: error)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.errorMessage = "앱 소리 캡처 중단: \(error.localizedDescription)"
            self?.finishRecording(with: error)
        }
    }
}
