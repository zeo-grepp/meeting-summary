import Foundation
import Observation

/// 녹음 파일 하나를 프로젝트의 meeting.py에 넘겨 전사·요약시킨다.
/// 한 번에 하나만 돌리고 나머지는 줄을 세운다.
@MainActor @Observable
final class MeetingSummaryRunner {
    enum Stage { case transcribing, summarizing }

    private(set) var stage: Stage?
    private(set) var lastSummaryURL: URL?
    /// 마지막으로 시도한 녹음. 실패했을 때 "다시 만들기"가 쓴다.
    private(set) var lastAudioURL: URL?
    private(set) var errorMessage: String?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var pending: [(audio: URL, projectRoot: URL)] = []
    @ObservationIgnored var onFinish: ((URL) -> Void)?

    var isRunning: Bool { stage != nil }
    var stageText: String? {
        switch stage {
        case .transcribing: "전사 중 (1/2)"
        case .summarizing: "요약 중 (2/2)"
        case nil: nil
        }
    }

    func run(audio: URL, projectRoot: URL?) {
        guard let projectRoot else {
            errorMessage = "설정에서 프로젝트 폴더를 먼저 선택해주세요."
            return
        }
        guard !isRunning else {
            pending.append((audio, projectRoot))
            return
        }
        Task { await execute(audio: audio, projectRoot: projectRoot) }
    }

    /// 요약을 기다리지 않고 앱을 끄는 경로. 녹음 파일은 이미 저장돼 있으므로 잃는 것은 없다.
    func cancel() {
        pending.removeAll()
        process?.terminate()
    }

    private func execute(audio: URL, projectRoot: URL) async {
        lastAudioURL = audio
        errorMessage = nil
        recentLines = []
        let python = projectRoot.appending(path: ".venv/bin/python")
        let script = projectRoot.appending(path: "meeting.py")
        // 5분 뒤가 아니라 지금 알려준다.
        for url in [python, script] where !FileManager.default.fileExists(atPath: url.path) {
            errorMessage = "\(url.lastPathComponent)을(를) 찾을 수 없습니다: \(url.path(percentEncoded: false))"
            drainPending()
            return
        }

        stage = .transcribing
        let summaryURL = projectRoot.appending(path: "summaries/\(audio.deletingPathExtension().lastPathComponent).md")
        do {
            let output = try await runProcess(python: python, script: script, audio: audio, projectRoot: projectRoot)
            guard FileManager.default.fileExists(atPath: summaryURL.path) else {
                throw RunnerError.noSummary(output)
            }
            lastSummaryURL = summaryURL
            stage = nil
            onFinish?(summaryURL)
        } catch {
            stage = nil
            errorMessage = "회의록을 만들지 못했습니다: \(error.localizedDescription)"
        }
        drainPending()
    }

    private func drainPending() {
        guard !pending.isEmpty else { return }
        let next = pending.removeFirst()
        Task { await execute(audio: next.audio, projectRoot: next.projectRoot) }
    }

    /// 표준 출력과 오류를 한 파이프로 모아 계속 읽는다. 쌓아두면 64KB에서 파이프가 막힌다.
    private func runProcess(python: URL, script: URL, audio: URL, projectRoot: URL) async throws -> String {
        let process = Process()
        process.executableURL = python
        process.arguments = [script.path, "--audio", audio.path]
        process.currentDirectoryURL = projectRoot
        // GUI로 실행된 앱의 PATH에는 Homebrew가 없다. whisper가 내부에서 부르는 ffmpeg를 못 찾는다.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.process = process
        defer { self.process = nil }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consume(text) }
        }
        defer { pipe.fileHandleForReading.readabilityHandler = nil }

        // run() 뒤에 핸들러를 걸면 즉시 실패하는 프로세스의 종료를 놓쳐 영원히 깨어나지 못한다.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() }
            catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        let tail = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
        consume(tail)
        guard process.terminationStatus == 0 else {
            throw RunnerError.exited(process.terminationStatus, recentOutput)
        }
        return recentOutput
    }

    @ObservationIgnored private var recentLines: [String] = []
    /// 메뉴 한 줄에 들어가야 한다. 파이썬 역추적의 마지막 줄이 곧 원인이므로 그것만 쓴다.
    private var recentOutput: String {
        String((recentLines.last ?? "알 수 없는 오류").prefix(120))
    }

    private func consume(_ text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            // meeting.py가 이미 찍는 진행 표시를 그대로 쓴다.
            if line.hasPrefix("[1/2]") { stage = .transcribing }
            if line.hasPrefix("[2/2]") { stage = .summarizing }
            // whisper의 진행 막대는 개행 없이 흘러 마지막 줄을 차지한다. 원인 줄을 가리지 않게 버린다.
            guard !line.contains("s]") else { continue }
            recentLines.append(String(line.prefix(200)))
        }
        recentLines = Array(recentLines.suffix(20))
    }

    private enum RunnerError: LocalizedError {
        case exited(Int32, String), noSummary(String)

        var errorDescription: String? {
            switch self {
            case let .exited(code, output): "meeting.py 종료 코드 \(code) — \(output)"
            case let .noSummary(output): "요약 파일이 생성되지 않았습니다 — \(output)"
            }
        }
    }
}
