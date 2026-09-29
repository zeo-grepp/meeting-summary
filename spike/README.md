# Phase 0 스파이크 — 전사 엔진 선택

버릴 코드다. 앱에 붙이지 않는다. 판정 근거만 남기고 이 디렉터리는 지운다.

- `speech_transcribe.swift` — macOS 26 SpeechTranscriber
  `swiftc -O -swift-version 6 spike/speech_transcribe.swift -o /tmp/speech_transcribe`
- `wk/` — WhisperKit (argmaxinc/argmax-oss-swift, MIT)
  `swift build -c release --package-path spike/wk`
