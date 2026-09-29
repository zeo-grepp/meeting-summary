# Meeting Assistant 구현 계획

작성일: 2026-09-23. 이번 작업은 조사와 계획 작성이며 앱 구현은 포함하지 않는다.

> **이 문서는 최초 설계 기록이다. 아래 내용은 지금과 다르다.**
> Python(`meeting.py`, `.venv`, mlx-whisper, Ollama)은 전부 제거했다. 전사는 WhisperKit,
> 요약은 Claude API, 회의록은 노션 DB 업로드로 바뀌었고 키는 Keychain에 둔다.
> 여기 나오는 "Phase 4"는 그때의 Python 연동 단계를 가리키며, 지금의 배포 단계와 무관하다.
> 현재 구조는 `macos/MeetingAssistant/README.md`를 본다.

## 1. 현재 프로젝트에서 확인한 사실

```text
meeting-summary/
├── meeting.py       # 녹음 선택 → 전사 → 요약
├── summarize.py     # 기존 전사 텍스트를 요약하는 별도 CLI
├── .venv/
├── recordings/
├── transcripts/     # .txt
└── summaries/       # .md
```

- `meeting.py:17–24`: 경로는 스크립트 디렉터리 기준. Whisper 모델은 `mlx-community/whisper-large-v3-turbo`, Ollama 모델은 `gemma4:31b-mlx`다. 기획 문서와 달리 Markdown은 `transcripts/`가 아닌 `summaries/`에 저장한다.
- `meeting.py:114–146`: `recordings/*.m4a`를 questionary로 선택한다.
- `meeting.py:153–232`: 현재 Python과 같은 디렉터리의 `mlx_whisper` 실행 파일을 우선 사용하고 subprocess로 전사한다.
- `meeting.py:239–322`: Ollama 응답을 파싱해 `summaries/<녹음명>.md`로 저장한다.
- `meeting.py:329–373`: 현재 인자는 `--title`, `--date`뿐이다. 파일 경로를 전달하는 비대화형 호출은 아직 없다.
- `summarize.py:113–190`: 전사 파일 인자를 받는 독립 CLI다. `meeting.py`에서 호출하지 않는다. Swift 연동을 위해 두 스크립트를 합칠 필요는 없다.
- 현재 디렉터리에는 Git 메타데이터가 없으며 `git status`는 저장소가 아니라고 반환했다. 확인한 소스 목록에는 Swift 프로젝트, 테스트, 의존성 선언 파일이 없다. 이번 작업에서 Git 초기화는 하지 않는다.
- 설치 환경: macOS 26.6, Xcode 27.0, Python 3.14.6. 가상환경 패키지 메타데이터: mlx-whisper 0.4.3, mlx 0.32.2, ollama 0.6.2, questionary 2.1.1. 모델 설치 여부나 실제 전사/요약 실행 성공은 이번에 검증하지 않았다.

## 2. 배치와 지원 환경 제안

같은 프로젝트 아래 `macos/MeetingAssistant/`에 독립 Xcode 앱을 추가하는 것이 적절하다. 기존 CLI와 녹음 저장 경로를 공유하고 변경을 함께 관리할 수 있다. Python을 앱에 번들링하거나 Swift 라이브러리로 다시 구현하지 않는다.

- 네이티브 macOS App target 하나와 테스트 target 하나. SwiftUI `MenuBarExtra`, `Settings`, `LSUIElement = YES`를 사용한다.
- 로컬 개인용 앱을 우선하며 App Sandbox는 끄는 구성을 제안한다. 이후 외부 `.venv`와 스크립트를 실행할 요구를 고려한 선택이다. Hardened Runtime과 App Sandbox는 별개이며 녹음 entitlement는 아래와 같이 관리한다.
- 초기 deployment target은 macOS 26.0을 제안하고, 실제 검증 환경은 26.6으로 명시한다. 구버전 지원을 목표로 추측성 fallback을 먼저 만들지 않는다. MenuBarExtra 자체는 macOS 13.0부터 제공된다.
- Core Audio 프로세스 속성의 최초 도입 버전은 확인한 Apple 문서 metadata와 현재 헤더에 명시되어 있지 않았다. **14.2 이상 등으로 단정하지 않는다.** 구버전 지원은 해당 OS 검증 후 별도 확정한다.
- 실행 시 `AudioObjectHasProperty`와 반환 상태를 검사한다. 미지원 또는 조회 실패는 “감지 불가”로 표시하고 수동 녹음은 유지한다.
- 설정에서 프로젝트 루트를 선택해 저장한다. 개발자 개인 절대 경로나 앱 번들 상대 위치에 의존하지 않는다. `recordings/`, 이후 `.venv/bin/python`과 `meeting.py`를 이 경로에서 찾는다.

## 3. 마이크 상태 API 조사와 선택

| 후보 | 확인한 계약 | 판단 |
| --- | --- | --- |
| `kAudioDevicePropertyDeviceIsRunningSomewhere` | 장치가 시스템 내 어느 프로세스에서든 실행 중이면 1 | 장치 실행을 뜻하며 입력 전용 활성 상태를 계약으로 보장하지 않는다. 이것만으로 마이크 사용이라고 단정하지 않는다. |
| `kAudioHardwarePropertyProcessObjectList` | HAL에 연결된 클라이언트 프로세스의 AudioObjectID 목록 | 감시 대상 오디오 프로세스 열거에 사용한다. |
| `kAudioProcessPropertyIsRunningInput` | 프로세스가 I/O를 실행하고 활성 입력 스트림이 하나 이상이면 1 | 각 프로세스 값을 OR하여 전체 입력 사용 상태를 만든다. MVP의 우선 검증 경로다. |
| `AudioObjectAddPropertyListenerBlock` / `RemovePropertyListenerBlock` | 속성 변경 listener 등록/해제 | 목록 변경과 각 프로세스 입력 상태 변경을 구독한다. 주기적 polling은 기본 방식으로 사용하지 않는다. |

근거는 Apple 공식 [장치 실행 속성](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertydeviceisrunningsomewhere), [프로세스 목록](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertyprocessobjectlist), [입력 활성 속성](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertyisrunninginput) 및 설치 SDK의 `CoreAudio.framework/Headers/AudioHardware.h`다. 현재 헤더의 상세 의미는 각각 918–920, 586–588, 1962–1965행에서 확인했다.

이 방법은 서비스 API나 앱별 오디오 프로세스 귀속을 요구하지 않는다. 단, 관측하는 것은 **오디오 입력 스트림 활성 상태**이며 실제 발화, 물리 마이크만의 사용, 특정 앱의 회의 여부를 보장하지 않는다. 가상 입력 장치도 입력 스트림에 포함될 수 있다.

실행 확인:

- `/tmp/meeting-assistant-audio-probe.c`를 CoreAudio에 링크해 컴파일하고 일회성 읽기 전용 조회를 실행했다. 녹음하거나 다른 앱을 실행하지 않았다.
- 도구 sandbox 내부: 속성 존재, 프로세스 0개.
- 도구 sandbox 외부: 속성 존재, 프로세스 38개, 활성 입력 0개, 조회 실패 0개.
- 이는 현재 환경의 목록/속성 읽기 성공만 입증한다. 앱 자체의 App Sandbox 동작이나 TCC 무권한 상태, 이벤트 전달, 활성→비활성 전환은 입증하지 않는다.

Phase 2 첫 작업에서 서명된 앱으로 입력 시작/종료, 출력만 사용, 기본 장치 외 입력, 프로세스 생성/종료, USB/Bluetooth 연결 변경과 잠자기 복귀를 검증한다. listener 해제에는 등록 시의 queue와 block을 보존한다. 목록 변경 시 새 프로세스를 구독하고 종료한 프로세스의 구독을 정리한 뒤 전체 상태를 다시 계산한다. 등록 직후 재조회하여 초기 스냅샷과 구독 사이의 변화를 놓치지 않도록 한다.

## 4. 권한

| 기능 | 요청/설정 | 시점 |
| --- | --- | --- |
| 알림 | `UNUserNotificationCenter.requestAuthorization`의 alert, 필요하면 sound | 첫 설정에서 알림 사용을 선택할 때 |
| 실행 앱 목록 | NSWorkspace 사용 | 별도의 Accessibility/Automation 요청 없이 시작 |
| 입력 상태 조회 | 오디오를 캡처하지 않고 HAL 속성 읽기 | 별도 권한 불필요 여부는 서명된 앱과 미허용 상태에서 검증. 이번 CLI 조회만으로 확정하지 않음 |
| 실제 마이크 녹음 | `NSMicrophoneUsageDescription`, `AVCaptureDevice`의 audio 접근 승인 | 사용자가 녹음 시작을 선택할 때 |
| Hardened Runtime 녹음 | `com.apple.security.device.audio-input` | Phase 3 앱 서명 설정 |
| 향후 App Sandbox 사용 시 | `com.apple.security.device.microphone`와 파일 접근 정책 재검토 | 배포 방식 변경 시 |

MVP는 Screen Recording, Accessibility, 브라우저 기록, Calendar, 서비스 OAuth를 사용하지 않는다. 상태 감지를 위해 녹음 세션을 여는 방식도 사용하지 않는다. 마이크 거부 시 recording 상태로 전환하지 않고 원인과 설정 안내를 표시한다.

근거: Apple [캡처 승인](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos), [Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input), [Sandbox와 Hardened Runtime 구분에 대한 DTS 설명](https://developer.apple.com/forums/thread/825449).

## 5. MVP 구성과 데이터 흐름

```text
SettingsStore → AppDetector → 실행 중인 감시 앱 집합 ┐
MicrophoneDetector → unknown / inactive / active    ├→ DetectionCoordinator
Recorder → idle / starting / recording / stopping  ┘          ↓
                                                    NotificationManager
                                                            ↓ 명시적 시작 액션
                                                         Recorder
                                                            ↓ Phase 4
                                                   MeetingSummaryRunner
```

- **SettingsStore / WatchedApplication**: `{bundleIdentifier, displayName, isEnabled}`를 Codable 데이터로 UserDefaults에 보관한다. `.app` 선택 패널에서 bundle ID와 표시 이름을 읽어 추가하고 중복 ID는 합친다. 목록 추가/삭제/활성화와 프로젝트 루트, 알림 활성화를 설정한다. 감시 앱은 사용자가 고르며 Detector에 Slack/Discord 분기를 넣지 않는다. 두 감지 조건은 MVP의 고정 AND 조건이다.
- **AppDetector**: NSWorkspace.runningApplications의 초기 값과 KVO 변경을 관찰하고 bundle ID로 설정과 교집합을 구한다. Apple 문서에서 launch notification은 LSUIElement/백그라운드 앱을 제외하므로, 임의의 앱을 선택할 수 있는 이번 요구에는 runningApplications KVO를 우선한다. 설정 변경도 즉시 반영한다. [Apple 근거](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications)
- **MicrophoneDetector**: 위 HAL 속성만 관찰하고 전체 입력 상태를 내보낸다. 읽기 오류를 inactive로 바꾸지 않는다. 활성 프로세스가 확인되면 active, 모두 성공적으로 비활성이면 inactive, 활성 근거 없이 일부 조회가 실패하면 unknown으로 취급한다.
- **DetectionCoordinator**: 회의 후보를 판단하는 유일한 위치다. `inactive → active && watchedApps 비어 있지 않음 && 녹음 시작/진행/종료 중 아님 && 알림 활성화 && cooldown 지남`일 때 후보를 생성한다. 초기 unknown→active는 시작 전환으로 간주하지 않는다. 앱 실행/설정 변경만으로 이미 활성 상태에 대한 알림을 만들지 않는다.
- 초기 cooldown은 전역 1분으로 단순화한다. 알림 등록 성공 시 시작하고, 만료만으로 재알림하지 않는다. 새 inactive→active 전환이 필요하다. 이번만 무시는 해당 후보를 종료한다. 여러 감시 앱이 동시에 실행되어도 후보 알림은 하나다.
- **NotificationManager**: 권한과 category/actions, 전달 오류, delegate를 관리한다. 제목은 “회의가 시작되었나요?”, 본문은 “Discord가 실행 중이며 오디오 입력 사용이 시작되었습니다.”로 표시한다. 특정 앱이 마이크를 사용했다는 귀속은 하지 않는다. `녹음 시작`과 `이번만 무시`를 등록한다. 본문 클릭은 앱을 열 뿐 녹음을 시작하지 않는다. [Apple 액션 문서](https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types)
- 알림 시작 액션과 메뉴바 수동 시작은 같은 녹음 진입점으로 연결한다. 시작 중 중복 요청은 무시하고, Recorder 시작 직전부터 감지 알림을 억제해 자체 입력 활성으로 재알림하지 않는다. 오래된 알림은 입력 종료 시 정리하며 응답 시 후보 유효성을 확인한다.
- 상태/UI는 main actor에서 갱신하고 Core Audio callback은 전달만 한다. 각 Detector는 start/stop과 callback을 갖는 구체 타입으로 시작한다. 범용 signal bus, associatedtype 프로토콜, 별도 MeetingDetector 계층은 지금 만들지 않는다.

## 6. 녹음과 기존 CLI 연동 범위

Phase 3은 AVAudioRecorder로 기본 입력을 AAC `.m4a`로 저장한다. 실제 시작 성공 후에만 recording을 표시하고 경과 시간을 보여준다. 종료 및 인코딩 오류를 구분하고 생성된 파일을 확인한다. 파일명은 초 단위 시각에 짧은 UUID를 붙여 충돌을 피한다. 저장 위치는 선택한 프로젝트의 `recordings/`다.

**이 MVP는 마이크 입력 녹음이다. 헤드폰으로 들리는 회의 상대방의 시스템/앱 오디오는 포함하지 않는다.** 양방향 회의 음성 녹음이 필수라면 Phase 3 범위를 변경하고 시스템 오디오 캡처와 믹싱/권한 설계를 먼저 해야 한다. 이를 마이크 녹음만으로 해결했다고 간주하지 않는다.

Phase 4에서 `meeting.py --audio <절대경로>`를 추가한다. 인자가 없을 때 기존 대화형 선택은 유지한다. 입력 파일을 검증한 뒤 기존 transcribe/create_summary를 그대로 사용한다. Runner는 프로젝트의 `.venv/bin/python`을 `Process.executableURL`로, 스크립트와 인자를 `arguments`로 전달한다. shell 문자열이나 `source activate`는 쓰지 않는다. 작업 디렉터리와 실행 중 상태, 종료 코드, stderr를 관리하고 출력은 파일 또는 계속 읽는 pipe로 배출한다. 실패해도 원본 녹음은 보존한다.

이 단계에서 Python/Whisper 실행 파일과 Ollama 실행 환경을 확인하고, GUI 실행이 셸 PATH를 물려받는다고 가정하지 않는다. 실제 전사·요약 성공 확인 전 “요약 완료”를 표시하지 않는다.

## 7. 단계별 파일 계획과 완료 기준

아래 파일은 필요 단계에서만 생성한다. Phase 1에 향후 빈 구현을 미리 만들지 않는다.

| 단계 | 추가/변경 파일 | 완료 기준 |
| --- | --- | --- |
| Phase 1 | `macos/MeetingAssistant/MeetingAssistant.xcodeproj/project.pbxproj`, 공유 scheme, `MeetingAssistant/App/MeetingAssistantApp.swift`, `App/MenuBarView.swift`, `Settings/SettingsView.swift`, `Settings/SettingsStore.swift`, `Settings/WatchedApplication.swift`, `Notification/NotificationManager.swift`, `Info.plist`, `README.md` | 앱 번들 빌드, 메뉴바 상주/Dock 숨김, 설정창 열기, 앱 추가·선택 재실행 후 유지, 알림 허용/거부 상태 표시. 아직 감지/녹음이 구현되지 않았음을 표시 |
| Phase 2a | `MeetingAssistant/Detection/MicrophoneDetector.swift` | 서명된 앱에서 읽기와 listener 전환/권한 검증. 실패하면 자동 감지 완료로 표시하지 않음 |
| Phase 2b | `Detection/AppDetector.swift`, `Detection/DetectionCoordinator.swift`, 기존 App/Notification 파일, `MeetingAssistantTests/DetectionCoordinatorTests.swift` | 감시 앱 실행 + 입력 시작 시 알림 하나, 초기 활성/앱 없음/unknown/cooldown 중에는 없음. 무시와 시작 액션 전달 확인. 실제 녹음 기능 완성 전 recording 상태를 흉내 내지 않음 |
| Phase 3 | `Recording/Recorder.swift`, `MeetingAssistant.entitlements`, 기존 Info.plist/App/MenuBar/Settings/Coordinator | 명시적 시작 → 권한 → 실제 녹음 → 종료 → 재생 가능한 m4a. 기존 CLI에서 해당 파일 선택·처리 가능. 이 단계가 기획의 MVP 완료 |
| Phase 4 | `Integration/MeetingSummaryRunner.swift`, `meeting.py`, `tests/test_meeting_cli.py`, 기존 UI/Settings | 비대화형 파일 경로 처리, 기존 선택 흐름 유지, 종료 후 자동 처리 옵션과 성공/실패 표시 |

테스트는 작은 XCTest 상태 전이 테스트부터 작성한다. 초기 active, inactive→active, 반복 active, 앱 없음, cooldown 경계, 녹음 중 억제, unknown 이후 복구를 검증한다. 실제 Core Audio/TCC/알림은 모킹만으로 통과했다고 판단하지 않고 앱 번들에서 수동 확인한다. Phase 3에서는 권한 거부, 중복 시작, 저장 실패, 정상 종료 파일을 확인한다. Python CLI 분기 검사는 표준 unittest와 mock으로 무거운 모델을 실행하지 않고 수행하고, 실제 m4a 전사·요약은 별도로 한 번 검증한다.

BrowserDetector, Calendar, application audio, scoring, 로그인 자동 실행은 이번 MVP에 넣지 않는다. 추후 신호가 생길 때 Coordinator 입력을 확장한다.

## 8. 아직 검증하지 않은 항목

- 프로세스 입력 상태 속성의 정확한 최초 지원 OS와 구버전 동작.
- 서명된 앱에서 마이크 권한 미허용/거부 상태의 읽기 전용 감지 동작.
- Discord/Slack 실제 입력 전환, 외장/가상 장치와 listener 이벤트 신뢰성.
- 알림 액션과 실제 녹음, 모델 실행을 포함한 end-to-end 동작.

권장 시작 단위는 Phase 1이다. 이 계획을 기준으로 범위를 확정한 뒤 구현하고, Phase 2a 검증을 통과하기 전 감지 기능이 완료되었다고 보고하지 않는다.

## Phase 1 진행 기록 — 2026-09-24

`macos/MeetingAssistant/`에 Xcode 앱과 설정 저장 테스트 target을 추가했다. 메뉴바, 앱 선택/삭제/활성화 저장, 프로젝트 경로 검증, 알림 권한 요청/조회까지 구현했다. 감지·녹음·Python 연동은 추가하지 않았다.

Debug 빌드와 XCTest 2개가 통과했다. 앱 프로세스 실행도 확인했지만 UI 자동화의 앱 연결이 시간 초과되어 메뉴바/설정창과 실제 권한 허용·거부 화면은 확인하지 못했다. 실행법과 수동 검증 항목은 `macos/MeetingAssistant/README.md`에 기록했다.

## Phase 2 진행 기록 — 2026-09-24

실행 중인 감시 앱을 NSWorkspace KVO로, Core Audio 프로세스별 입력 활성 상태를 속성 listener로 관찰한다. 입력 비활성→활성 전환과 감시 앱 실행이 동시에 충족될 때만 알림을 보내며 전역 1분 쿨다운을 적용한다. 입력 종료·감시 앱 종료·설정 해제 시 기존 후보를 정리한다. 알림의 무시 액션은 후보를 닫고 시작 액션은 Phase 3 안내를 표시한다. 실제 녹음 상태로 전환하지 않는다.

Xcode 실행과 XCTest 상태 전이 검증을 완료했다. Discord 음성 채널 종료·재연결에서 입력 상태 전환과 후보 알림 배너·소리를 확인했다. 알림 액션은 아직 수동 검증이 필요하다. 검증 절차는 `macos/MeetingAssistant/README.md`에 기록했다.

후속 검증에서 Discord 입력을 Core Audio 일회성 조회는 활성(1)으로 보고했지만 앱의 속성 listener가 전환을 전달하지 않은 사례를 확인했다. 누락된 전환을 회복하도록 실행 중 2초 간격 재조회를 추가했다. 수정된 앱에서 음성 채널 재연결 시 입력 전환, 후보 알림 발송, 배너 표시를 확인했다.
