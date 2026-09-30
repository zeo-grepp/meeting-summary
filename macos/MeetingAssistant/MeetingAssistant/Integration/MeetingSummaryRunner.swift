import Foundation
import Observation

/// 녹음 파일 하나를 전사하고 요약해 회의록 .md로 떨군다.
/// 한 번에 하나만 돌리고 나머지는 줄을 세운다.
@MainActor @Observable
final class MeetingSummaryRunner {
    enum Stage { case transcribing, summarizing, uploading }

    /// 실패한 녹음 하나. 성공할 때까지 남아 있어야 한다 —
    /// 다음 녹음이 시작한다고 앞 건의 실패가 사라지면 아무도 모르고 지나간다.
    struct Failure: Identifiable {
        let audio: URL
        /// 사람이 다음에 뭘 해야 하는지까지 적은 한 줄.
        let reason: String
        /// 전사까지는 됐으면 녹취록이 남아 있다. 회의가 통째로 날아간 게 아니라는 증거다.
        let transcript: URL?

        var id: String { audio.path }
    }

    private(set) var stage: Stage?
    private(set) var lastSummaryURL: URL?
    /// 업로드에 성공했을 때만 찬다. 완료 알림을 누르면 로컬 .md 대신 여기를 연다.
    private(set) var lastNotionURL: URL?
    /// 마지막으로 시도한 녹음. 실패했을 때 "다시 만들기"가 쓴다.
    private(set) var lastAudioURL: URL?
    private(set) var failures: [Failure] = []
    /// 모델 로드가 최초 1분을 넘는다. 회의마다 새로 만들지 않도록 하나를 들고 쓴다.
    @ObservationIgnored private let transcriber = Transcriber()
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pending: [(audio: URL, projectRoot: URL)] = []
    @ObservationIgnored var onFinish: ((URL) -> Void)?
    @ObservationIgnored var onFailure: ((Failure) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
    }

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
            record(Failure(audio: audio, reason: "설정에서 저장 폴더를 먼저 선택해주세요.", transcript: nil))
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
        let stem = audio.deletingPathExtension().lastPathComponent
        // 전사가 끝나야 채워진다. 실패 메시지에서 "녹취록은 남아 있다"를 말할 수 있는지가 여기에 달렸다.
        var transcriptURL: URL?

        do {
            stage = .transcribing
            await transcriber.setPrompt(settings.transcriptionPrompt)
            let transcript = try await transcriber.transcribe(audio)
            let url = projectRoot.appending(path: "transcripts/\(stem).txt")
            try write(transcript, to: url)
            transcriptURL = url

            stage = .summarizing
            let summary = try await summarize(transcript)
            let summaryURL = projectRoot.appending(path: "summaries/\(stem).md")
            try write(Self.markdown(summary, recordedAt: Self.recordedDate(of: audio)), to: summaryURL)

            lastSummaryURL = summaryURL
            lastNotionURL = nil
            failures.removeAll { $0.audio == audio }

            // 여기서부터는 실패해도 회의록은 이미 디스크에 있다. 사유만 남기고 완료로 친다.
            let notion = NotionUploader(settings: settings)
            if notion.isEnabled {
                stage = .uploading
                do {
                    lastNotionURL = try await notion.upload(
                        title: summary.title, markdown: summary.content,
                        date: Self.recordedDate(of: audio))
                } catch {
                    record(Failure(audio: audio,
                                   reason: "회의록은 만들었지만 노션에 올리지 못했습니다 — \(Self.reason(for: error))",
                                   transcript: transcriptURL))
                }
            }
            stage = nil
            onFinish?(summaryURL)
        } catch {
            stage = nil
            record(Failure(audio: audio, reason: Self.reason(for: error), transcript: transcriptURL))
        }
        drainPending()
    }

    /// 사내 게이트웨이는 VPN 밖에서 안 잡힌다. 자리를 비운 사이 잠깐 끊긴 경우가 대부분이라
    /// 한 번은 말없이 더 해보고, 그래도 안 되면 사람에게 넘긴다.
    private func summarize(_ transcript: String) async throws -> ClaudeSummarizer.Summary {
        let claude = ClaudeSummarizer(settings: settings)
        do {
            return try await claude.summarize(transcript: transcript)
        } catch where Self.isNetworkFailure(error) {
            try await Task.sleep(for: .seconds(5))
            return try await claude.summarize(transcript: transcript)
        }
    }

    /// 같은 녹음의 실패는 하나만 남긴다. 다시 만들기를 눌러 또 실패해도 줄이 늘지 않는다.
    private func record(_ failure: Failure) {
        failures.removeAll { $0.audio == failure.audio }
        failures.append(failure)
        onFailure?(failure)
    }

    func dismiss(_ failure: Failure) {
        failures.removeAll { $0.id == failure.id }
    }

    /// 사유마다 사람이 할 일이 전혀 다르다. localizedDescription을 그대로 보여주면
    /// "VPN을 켠다"와 "키를 고친다"와 "이 녹음은 포기한다"가 한 덩어리로 보인다.
    static func reason(for error: Error) -> String {
        if isNetworkFailure(error) {
            return "네트워크에 연결하지 못했습니다. 사내 게이트웨이를 쓴다면 VPN을 확인해주세요."
        }
        switch error {
        case ClaudeSummarizer.SummarizerError.noAPIKey:
            return "설정에서 Claude API 키를 넣어주세요."
        case ClaudeSummarizer.SummarizerError.noNotes:
            return "녹취록에 회의 내용이 없어 요약하지 못했습니다. 녹음이 너무 짧지 않은지 확인해주세요."
        case let ClaudeSummarizer.SummarizerError.badResponse(detail):
            return httpReason(detail) ?? "Claude 응답을 읽지 못했습니다 — \(detail)"
        default:
            return error.localizedDescription
        }
    }

    /// 상태 코드만으로 다음 할 일이 갈린다. 본문은 게이트웨이마다 형식이 달라 믿지 않는다.
    private static func httpReason(_ detail: String) -> String? {
        guard let code = detail.firstMatch(of: /HTTP (\d{3})/)?.1, let status = Int(code) else { return nil }
        switch status {
        case 401, 403: return "API 키가 거부됐습니다(\(status)). 설정에서 키를 확인해주세요."
        case 404: return "게이트웨이 주소를 찾지 못했습니다(404). 설정의 주소를 확인해주세요."
        case 429: return "요청이 몰렸습니다(429). 잠시 뒤 다시 만들기를 눌러주세요."
        case 500...599: return "서버 쪽 오류입니다(\(status)). 잠시 뒤 다시 만들기를 눌러주세요."
        default: return nil
        }
    }

    /// 재시도로 살아날 수 있는 실패. 키가 틀린 경우처럼 사람이 고쳐야 하는 것은 여기 넣지 않는다.
    static func isNetworkFailure(_ error: Error) -> Bool {
        guard let url = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                .cannotConnectToHost, .dnsLookupFailed, .timedOut,
                .secureConnectionFailed, .internationalRoamingOff,
                .dataNotAllowed].contains(url.code)
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
