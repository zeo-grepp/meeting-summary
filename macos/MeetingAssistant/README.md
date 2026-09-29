# Meeting Assistant

macOS 26.0 이상을 대상으로 하는 로컬 메뉴바 앱입니다. 현재 검증 환경은 macOS 26.6 / Xcode 27.0입니다. 전사에 WhisperKit(SPM)을 사용합니다.

## 실행

1. `MeetingAssistant.xcodeproj`를 Xcode에서 엽니다.
2. `MeetingAssistant` scheme과 `My Mac`을 선택하고 Run합니다.
3. 메뉴바의 마이크 아이콘 → **설정…**을 엽니다. Dock에는 표시하지 않습니다.
4. **앱 추가…**에서 감시할 `.app`을 선택합니다. 체크 해제/삭제가 가능하며 bundle ID로 중복을 구분합니다.
5. **저장 폴더 선택…**에서 녹음·녹취록·회의록을 모아둘 폴더를 선택합니다. 하위에 `recordings/`, `transcripts/`, `summaries/`를 앱이 만듭니다.
6. **요약 (Claude API)**에 키를 넣고 연결 테스트를 누릅니다. 사내 게이트웨이를 쓰면 주소와 모델 이름도 함께 바꿉니다.
7. (선택) **노션 업로드**에 토큰과 회의록 DB id를 넣고 연결 테스트를 누릅니다. 토큰을 만들 때 그 DB를 접근 허용 목록에 넣어야 합니다.
8. **회의 감지 시 녹음 여부 알림**을 켜면 macOS 배너·소리 권한을 요청합니다. 거부한 권한은 시스템 설정 → 알림 → Meeting Assistant에서 변경할 수 있습니다. 앱으로 돌아오면 권한 상태를 새로 조회합니다.
9. 감시 앱이 실행 중일 때 오디오 입력 사용이 새로 시작되면 회의 후보 알림을 보냅니다. 알림 배너에 **녹음 시작** 버튼이 바로 보입니다. 본문 클릭도 같습니다. 배너의 **닫기(X)**가 이번만 무시입니다. macOS 배너는 액션이 둘 이상이면 "옵션" 메뉴로 접기 때문에 액션은 하나만 등록합니다.
10. 메뉴바의 **녹음 시작**도 같은 동작입니다. 처음 시작할 때 macOS 마이크와 화면·시스템 오디오 녹음 권한을 허용합니다. 감시 앱(예: Discord)이 실행 중이어야 하며, 그 앱의 출력 소리와 마이크를 함께 녹음합니다. 끝날 때 시간 표시를 눌러 **녹음 종료**를 선택하면 `recordings/`에 `.m4a` 파일이 저장됩니다.

알림 권한 요청에 `Notifications are not allowed for this application`이 표시되고 시스템 설정 목록에도 앱이 없다면, 다른 위치에서 실행 중인 Meeting Assistant를 모두 종료한 뒤 Xcode의 **Run**으로 다시 실행해 **알림 권한 요청**을 누릅니다. 이번 환경에서는 `/tmp`에서 실행된 별도 검증용 앱의 요청은 실패했지만, Xcode에서 실행한 앱의 요청은 성공했고 시스템 설정 목록에 앱이 표시되었습니다. 목록의 **Meeting Assistant** 알림 스위치를 켜면 됩니다.

Xcode에서 돌릴 때는 `Apple Development`로 서명합니다. 팀원에게 나눠줄 빌드는 아래 **배포**를 봅니다. App Sandbox는 꺼져 있습니다 — 켜면 사용자가 고른 저장 폴더에 보안 스코프 북마크가 필요해지는데, 공증만으로 배포가 되므로 그 값을 치르지 않습니다. Hardened Runtime은 켜져 있습니다. 설정은 `com.zeo.MeetingAssistant`의 UserDefaults에 저장하고, API 키와 노션 토큰은 Keychain에만 둡니다. 저장소 파일에는 쓰지 않습니다.

## 구현 범위

- SwiftUI MenuBarExtra와 설정창
- 감시 앱 추가·삭제·활성화 및 재실행 후 설정 복원
- 프로젝트 경로 선택·검증, 기존 `recordings/` 폴더 열기
- 알림 사용 설정과 macOS 권한 요청·조회·오류 표시
- 실행 중인 감시 앱과 Core Audio 입력 활성 상태 관찰
- Core Audio 상태 변경 listener가 전환을 놓치는 경우 2초마다 입력 상태를 재확인
- 두 신호가 맞고 입력이 비활성→활성으로 바뀔 때 후보 알림 발송, 1분 재알림 제한
- 입력 종료·감시 앱 종료·알림 설정 해제 시 후보 알림 정리, 알림 액션 및 닫기(무시) 처리
- 명시적 시작 시 마이크와 화면·시스템 오디오 권한 요청, 감시 앱 출력과 마이크 동시 캡처, 녹음 중 재알림 억제, 종료 시 `.m4a` 파일 저장 및 재생 확인

앱 실행만으로 권한을 요청하거나 녹음을 시작하지 않습니다. 녹음 중간에는 숨김 `.mp4` 파일을 사용하고, 정상 종료 후 오디오만 `.m4a`로 변환해 중간 파일을 제거합니다. 권한을 새로 허용한 경우 macOS가 앱 재시작을 요구할 수 있습니다. 녹음이 끝나면 앱이 이어서 전사(WhisperKit)와 요약(Claude API)을 돌려 `summaries/`에 회의록 `.md`를 남깁니다. 요약에는 Claude API 키가 필요하고, 노션 업로드를 켜면 회의록 DB에 페이지도 만듭니다. 둘 다 **설정**에서 입력하며 키와 토큰은 Keychain에 저장합니다(설정 화면의 연결 테스트로 미리 확인할 수 있습니다). 노션을 비워두면 로컬 `.md`까지만 만듭니다. 오디오 입력 사용은 특정 앱의 회의나 발화를 뜻하지 않습니다.

## 배포

```sh
./release.sh
```

archive → Developer ID 서명 → 공증 → staple → `.zip`까지 한 번에 합니다. 결과물을 GitHub Releases에 올리고 링크를 보내면 됩니다. 자동 업데이트는 넣지 않습니다.

미리 준비할 것이 둘 있습니다.

1. **Developer ID Application 인증서.** 유료 Apple Developer Program 멤버십이 필요합니다. `Apple Development` 서명본은 그 팀의 프로비저닝이 등록된 맥에서만 열립니다.
2. **공증 자격증명.** 한 번만 저장해두면 스크립트가 알아서 씁니다.

   ```sh
   xcrun notarytool store-credentials meeting-assistant \
     --apple-id <계정> --team-id <팀 id> --password <앱 전용 암호>
   ```

팀 id와 프로파일 이름은 `TEAM_ID`, `NOTARY_PROFILE` 환경변수로 덮을 수 있습니다.

받는 사람은 `.zip`을 풀어 `/Applications`에 넣고 열면 됩니다. 설정에서 키를 채우는 것 외에 할 일이 없습니다.

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

2026-09-24 Phase 2 검증: Xcode 앱 실행과 XCTest 3개 통과. Discord 음성 채널을 나간 뒤 입력 `active → inactive`, 재연결 시 `inactive → active` 및 회의 후보 알림 배너와 소리를 확인했습니다. 2초 재확인 추가 후에도 재연결 알림 배너를 확인했습니다.

수동 확인 항목:

- 메뉴바 아이콘 → 설정창 열기 및 Dock 숨김
- 실제 앱 추가/체크 해제 후 앱 종료·재실행 시 화면 복원
- 프로젝트 선택 패널, 녹음 폴더 열기
- macOS 알림 권한 허용/거부와 시스템 설정 변경 후 상태 갱신
- 감시 앱 실행 상태에서 마이크 입력 시작·종료 시 알림 한 번과 정리 동작
- 알림의 **이번만 무시**와 **녹음 시작**, 1분 내 재알림 제한
- 마이크 권한 허용/거부, 메뉴바 수동 시작과 종료, 저장된 `.m4a` 재생 재생

