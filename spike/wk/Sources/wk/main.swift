import Foundation
import WhisperKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("사용법: wk <오디오> <출력.txt>\n".utf8))
    exit(2)
}

// 사내 용어는 레포에 넣지 않는다. meeting.py와 같이 whisper_prompt.txt를 쓴다.
let initialPrompt = ProcessInfo.processInfo.environment["WHISPER_PROMPT"] ?? ""

let started = Date()

let pipe = try await WhisperKit(WhisperKitConfig(
    model: "large-v3-v20240930_turbo",
    verbose: false,
    logLevel: .error,
    download: true
))
let ready = Date()

var options = DecodingOptions(language: "ko", temperature: 0)
if !initialPrompt.isEmpty, let tokens = pipe.tokenizer?.encode(text: initialPrompt) {
    options.promptTokens = tokens
    options.usePrefillPrompt = true
}

let results = try await pipe.transcribe(audioPath: arguments[1], decodeOptions: options)
let text = results.map(\.text).joined(separator: " ")
try text.write(to: URL(fileURLWithPath: arguments[2]), atomically: true, encoding: .utf8)

let load = Int(ready.timeIntervalSince(started))
let total = Int(Date().timeIntervalSince(started))
FileHandle.standardError.write(Data("완료 (모델 \(load)초 + 전사 \(total - load)초, \(text.count)자)\n".utf8))
