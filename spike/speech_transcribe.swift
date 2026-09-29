// Phase 0 스파이크 — macOS 26 SpeechTranscriber 전사 품질을 whisper와 비교하기 위한 일회용 코드.
// 앱에 붙이지 않는다. 판정이 끝나면 버린다.
//
//   swiftc -O spike/speech_transcribe.swift -o /tmp/speech_transcribe
//   /tmp/speech_transcribe recordings/회의.m4a [출력.txt]

import AVFoundation
import Foundation
import Speech

// whisper_prompt.txt와 같은 역할. 고유명사 인식 보정.
// 사내 용어는 레포에 넣지 않는다. SPEECH_TERMS에 쉼표로 구분해 넘긴다.
let contextualStrings = (ProcessInfo.processInfo.environment["SPEECH_TERMS"] ?? "")
    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }

func transcribe(_ url: URL) async throws -> String {
    let requested = Locale(identifier: "ko-KR")
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
        throw Failure("ko-KR을 지원하지 않는다. 지원 로케일: \(await SpeechTranscriber.supportedLocales.map(\.identifier))")
    }

    let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

    // 모델은 시스템이 받아서 관리한다. 처음 한 번만 다운로드가 걸린다.
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        FileHandle.standardError.write(Data("모델을 내려받는 중…\n".utf8))
        try await request.downloadAndInstall()
    }

    let context = AnalysisContext()
    context.contextualStrings = [.general: contextualStrings]

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    try await analyzer.setContext(context)

    // 결과 스트림은 분석과 동시에 비워야 한다. 끝나고 읽으면 늦다.
    let collected = Task {
        var text = AttributedString()
        for try await result in transcriber.results {
            text += result.text
        }
        return String(text.characters)
    }

    let file = try AVAudioFile(forReading: url)
    _ = try await analyzer.analyzeSequence(from: file)
    try await analyzer.finalizeAndFinishThroughEndOfInput()

    return try await collected.value
}

struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

let arguments = CommandLine.arguments

guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("사용법: speech_transcribe <오디오> [출력.txt]\n".utf8))
    exit(2)
}

let audioURL = URL(fileURLWithPath: arguments[1])
let started = Date()

do {
    let text = try await transcribe(audioURL)
    let elapsed = Int(Date().timeIntervalSince(started))

    if arguments.count >= 3 {
        try text.write(to: URL(fileURLWithPath: arguments[2]), atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("완료 (\(elapsed)초, \(text.count)자) → \(arguments[2])\n".utf8))
    } else {
        print(text)
        FileHandle.standardError.write(Data("완료 (\(elapsed)초, \(text.count)자)\n".utf8))
    }
} catch {
    FileHandle.standardError.write(Data("실패: \(error.localizedDescription)\n".utf8))
    exit(1)
}
