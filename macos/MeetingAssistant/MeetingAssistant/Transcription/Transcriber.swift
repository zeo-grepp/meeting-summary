import Foundation
import WhisperKit

/// 녹음 파일을 글로 바꾼다. mlx-whisper와 같은 whisper-large-v3-turbo를 CoreML로 돌린다.
///
/// 모델 로드가 최초 70초·이후 6~7초 걸린다. 회의마다 새로 만들면 그만큼 매번 낸다.
/// 그래서 인스턴스를 하나 만들어 앱 수명 동안 들고 쓴다.
actor Transcriber {
    /// WhisperKit이 Hugging Face에서 내려받는 모델 이름. 최초 1회 약 1.5GB.
    private static let modelName = "large-v3-v20240930_turbo"

    private var pipe: WhisperKit?

    /// 고유명사 인식 보정. whisper의 initial_prompt와 같은 자리다.
    /// 팀마다 다르므로 Phase 3에서 설정값으로 뺀다.
    var prompt: String = ""

    func setPrompt(_ prompt: String) { self.prompt = prompt }

    /// 모델을 미리 받아둔다. 첫 회의가 끝난 뒤 70초를 기다리지 않게 앱 시작 때 부른다.
    func warmUp() async throws {
        _ = try await loadedPipe()
    }

    func transcribe(_ audio: URL) async throws -> String {
        let pipe = try await loadedPipe()
        var options = DecodingOptions(language: "ko", temperature: 0)
        if !prompt.isEmpty, let tokens = pipe.tokenizer?.encode(text: prompt) {
            options.promptTokens = tokens
            options.usePrefillPrompt = true
        }
        let results = try await pipe.transcribe(audioPath: audio.path, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriberError.empty }
        return text
    }

    private func loadedPipe() async throws -> WhisperKit {
        if let pipe { return pipe }
        let pipe = try await WhisperKit(WhisperKitConfig(
            model: Self.modelName,
            verbose: false,
            logLevel: .error,
            download: true
        ))
        self.pipe = pipe
        return pipe
    }

    enum TranscriberError: LocalizedError {
        case empty

        var errorDescription: String? {
            switch self {
            case .empty: "녹음에서 말소리를 찾지 못했습니다."
            }
        }
    }
}
