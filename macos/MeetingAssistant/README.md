# Meeting Assistant — Phase 1

macOS 26.0 이상을 대상으로 하는 로컬 메뉴바 앱입니다. 현재 검증 환경은 macOS 26.6 / Xcode 27.0입니다. 외부 Swift 패키지는 사용하지 않습니다.

## 실행

1. `MeetingAssistant.xcodeproj`를 Xcode에서 엽니다.
2. `MeetingAssistant` scheme과 `My Mac`을 선택하고 Run합니다.
3. 메뉴바의 마이크 아이콘 → **설정…**을 엽니다. Dock에는 표시하지 않습니다.
4. **앱 추가…**에서 감시할 `.app`을 선택합니다. 체크 해제/삭제가 가능하며 bundle ID로 중복을 구분합니다.
5. **프로젝트 폴더 선택…**에서 `meeting.py`가 있는 `meeting-summary` 폴더를 선택합니다.
6. **회의 감지 시 녹음 여부 알림**을 켜면 macOS 알림 권한을 요청합니다. 거부한 권한은 시스템 설정 → 알림 → Meeting Assistant에서 변경할 수 있습니다. 앱으로 돌아오면 권한 상태를 새로 조회합니다.

알림 권한 요청에 `Notifications are not allowed for this application`이 표시되고 시스템 설정 목록에도 앱이 없다면, 다른 위치에서 실행 중인 Meeting Assistant를 모두 종료한 뒤 Xcode의 **Run**으로 다시 실행해 **알림 권한 요청**을 누릅니다. 이번 환경에서는 `/tmp`에서 실행된 별도 검증용 앱의 요청은 실패했지만, Xcode에서 실행한 앱의 요청은 성공했고 시스템 설정 목록에 앱이 표시되었습니다. 목록의 **Meeting Assistant** 알림 스위치를 켜면 됩니다.

기본 서명은 개인 로컬 실행용 ad-hoc입니다. App Sandbox는 꺼져 있습니다. 배포용 서명/공증 설정은 포함하지 않습니다. 설정은 앱의 UserDefaults(`local.meeting-summary.MeetingAssistant`)에 저장하며 저장소 파일에는 쓰지 않습니다.

## 구현 범위

- SwiftUI MenuBarExtra와 설정창
- 감시 앱 추가·삭제·활성화 및 재실행 후 설정 복원
- 프로젝트 경로 선택·검증, 기존 `recordings/` 폴더 열기
- 알림 사용 설정과 macOS 권한 요청·조회·오류 표시

회의 감지, 알림 발송/액션, 녹음, Python 자동 실행은 아직 구현하지 않았습니다. 메뉴에 준비 중으로 표시하며 녹음 버튼은 비활성화되어 있습니다. 앱 실행만으로 권한을 요청하거나 녹음을 시작하지 않습니다.

## 빌드와 테스트

이 디렉터리에서 실행합니다.

```sh
xcodebuild -project MeetingAssistant.xcodeproj -scheme MeetingAssistant \
  -configuration Debug -derivedDataPath /tmp/meeting-assistant-build build

xcodebuild -project MeetingAssistant.xcodeproj -scheme MeetingAssistant \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/meeting-assistant-build test
```

테스트는 별도의 임시 UserDefaults suite와 임시 파일을 사용합니다. 실제 사용자 설정은 변경하지 않습니다. 앱 target과 모델 소스를 공유하는 host 없는 XCTest target으로 다음을 확인합니다.

- 감시 앱의 활성 상태·알림 설정·프로젝트 경로 저장 및 복원
- 같은 bundle ID 중복 추가 시 선택 상태 유지
- 잘못된 앱/프로젝트 경로 거부와 기존 설정 유지
- 앱 삭제 저장, 손상된 JSON 오류 표시와 원본 보존

2026-09-24 검증: Debug 앱 빌드 성공(arm64/x86_64), arm64 XCTest 2개 통과, plist 검사 통과, 앱 프로세스 실행 확인. UI 자동화는 앱 연결 시간 초과로 아래 항목을 검증하지 못했습니다.

수동 확인 항목:

- 메뉴바 아이콘 → 설정창 열기 및 Dock 숨김
- 실제 앱 추가/체크 해제 후 앱 종료·재실행 시 화면 복원
- 프로젝트 선택 패널, 녹음 폴더 열기
- macOS 알림 권한 허용/거부와 시스템 설정 변경 후 상태 갱신

현재 단계는 권한 관리만 제공하므로 알림 배너/액션 동작은 Phase 2에서 검증합니다.
