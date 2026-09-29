import Foundation
import Observation

/// 녹음 파일 하나를 전사하고 요약해 회의록 .md로 떨군다.
/// 한 번에 하나만 돌리고 나머지는 줄을 세운다.
@MainActor @Observable
final class MeetingSummaryRunner {
    enum Stage { case transcribing, summarizing, uploading }

    private(set) var stage: Stage?
    private(set) var lastSummaryURL: URL?
    /// 업로드에 성공했을 때만 찬다. 완료 알림을 누르면 로컬 .md 대신 여기를 연다.
    private(set) var lastNotionURL: URL?
    /// 마지막으로 시도한 녹음. 실패했을 때 "다시 만들기"가 쓴다.
    private(set) var lastAudioURL: URL?
    private(set) var errorMessage: String?
    /// 모델 로드가 최초 1분을 넘는다. 회의마다 새로 만들지 않도록 하나를 들고 쓴다.
    @ObservationIgnored private let transcriber = Transcriber()
    @ObservationIgnored private let summarizer = ClaudeSummarizer()
    @ObservationIgnored private let notion = NotionUploader()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pending: [(audio: URL, projectRoot: URL)] = []
    @ObservationIgnored var onFinish: ((URL) -> Void)?

    var isRunning: Bool { stage != nil }
    var stageText: String? {
        switch stage {
        case .transcribing: "전사 중 (1/2)"
        case .summarizing: "요약 중 (2/2)"
        case .uploading: "노션에 올리는 중 (3/3)"
        case nil: nil
        }
    }

    func run(audio: URL, projectRoot: URL?) {
        guard let projectRoot else {
            errorMessage = "설정에서 저장 폴더를 먼저 선택해주세요."
            return
        }
        guard !isRunning else {
            pending.append((audio, projectRoot))
            return
        }
        task = Task { await execute(audio: audio, projectRoot: projectRoot) }
    }

    /// 요약을 기다리지 않고 앱을 끄는 경로. 녹음 파일은 이미 저장돼 있으므로 잃는 것은 없다.
    func cancel() {
        pending.removeAll()
        task?.cancel()
    }

    private func execute(audio: URL, projectRoot: URL) async {
        lastAudioURL = audio
        errorMessage = nil
        let stem = audio.deletingPathExtension().lastPathComponent

        do {
            stage = .transcribing
            await transcriber.setPrompt(Self.transcriptionPrompt(in: projectRoot))
            let transcript = try await transcriber.transcribe(audio)
            try write(transcript, to: projectRoot.appending(path: "transcripts/\(stem).txt"))

            stage = .summarizing
            let summary = try await summarizer.summarize(transcript: transcript)
            let summaryURL = projectRoot.appending(path: "summaries/\(stem).md")
            try write(Self.markdown(summary, recordedAt: Self.recordedDate(of: audio)), to: summaryURL)

            lastSummaryURL = summaryURL
            lastNotionURL = nil

            // 여기서부터는 실패해도 회의록은 이미 디스크에 있다. 사유만 남기고 완료로 친다.
            if notion.isEnabled {
                stage = .uploading
                do {
                    lastNotionURL = try await notion.upload(
                        title: summary.title, markdown: summary.content,
                        date: Self.recordedDate(of: audio))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
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
        task = Task { await execute(audio: next.audio, projectRoot: next.projectRoot) }
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 팀마다 자주 나오는 고유명사가 다르다. meeting.py와 같은 파일을 읽는다.
    /// Phase 3에서 설정 필드로 올린다.
    private static func transcriptionPrompt(in projectRoot: URL) -> String {
        let file = projectRoot.appending(path: "whisper_prompt.txt")
        return (try? String(contentsOf: file, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 어제 녹음을 오늘 처리해도 회의 날짜는 녹음한 날이다.
    private static func recordedDate(of audio: URL) -> Date {
        (try? audio.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    private static func markdown(_ summary: ClaudeSummarizer.Summary, recordedAt: Date) -> String {
        let date = recordedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return """
            # \(summary.title)

            `\(date)`

            \(summary.content)

            """
    }
}
