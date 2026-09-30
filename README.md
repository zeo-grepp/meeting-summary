# meeting-summary

회의를 녹음하면 회의록이 나옵니다. 메뉴바 앱이 녹음하고, 전사는 이 맥에서(mlx-whisper),
요약은 Claude API로 합니다.

Apple Silicon Mac에서만 동작합니다.

## 설치

**1. 도구를 받습니다.**

```sh
git clone https://github.com/zeo-grepp/meeting-summary.git
cd meeting-summary
git checkout feat-script-deploy
./install.sh
```

`git checkout`을 빠뜨리면 안 됩니다. 기본 브랜치(`main`)에는 아직 이 내용이 없습니다.

`install.sh`가 ffmpeg·가상환경·패키지를 설치하고 `claude_config.json`을 만들어 둡니다.
몇 분 걸립니다. 이미 있는 것은 건너뛰므로 다시 돌려도 됩니다. Homebrew만 미리 있어야
합니다 — 없으면 [brew.sh](https://brew.sh)를 먼저 봅니다.

**2. `claude_config.json`에 API 키를 채웁니다.**

```json
{
  "api_key": "...",
  "base_url": "",
  "model": ""
}
```

`base_url`과 `model`은 사내 게이트웨이를 쓸 때만 채웁니다. 비워 두면 공개 API로 갑니다.
이 파일은 `.gitignore` 대상이라 커밋되지 않습니다.

**3. 메뉴바 앱을 설치합니다.**

[Releases](https://github.com/zeo-grepp/meeting-summary/releases)에서 **`script-v`로
시작하는** 가장 최근 zip을 내려받습니다. `app-v`는 Python 없이 도는 다른 앱이라 이 설치
절차와 맞지 않습니다. 앱만 들어 있고 전사·요약은 1번에서 clone한 폴더의 Python이 하므로, 둘 다
있어야 합니다. 풀어서 `/Applications`에 넣고:

```sh
xattr -d com.apple.quarantine /Applications/MeetingAssistant.app
```

이 한 줄이 필요한 이유는 Apple Developer ID 인증서가 아직 없어서입니다. 인증서가 생기면
없어질 단계입니다. 실행하면 마이크와 화면·시스템 오디오 녹음 권한을 한 번씩 물어봅니다.

**4. 앱 설정에서 프로젝트 폴더를 고릅니다.**

메뉴바 아이콘 → 설정… → **프로젝트 폴더 선택…**에서 1번에서 clone한 `meeting-summary`
폴더를 고릅니다. `meeting.py`가 있는 폴더입니다.

## 쓰기

메뉴바에서 **녹음 시작** → 회의가 끝나면 **녹음 종료**. 파일 이름을 물어본 뒤 전사와
요약이 이어서 돌고, 끝나면 알림이 옵니다. 1시간 회의면 몇 분 걸립니다.

결과는 clone한 폴더 안에 쌓입니다.

```
recordings/   녹음 .m4a
transcripts/  녹취록 .txt
summaries/    회의록 .md
```

감시할 앱(회의에 쓰는 통화 앱 등)을 설정에 추가해 두면, 그 앱이 마이크를 잡을 때
"녹음할까요?" 알림이 옵니다. 녹음은 화면 전체 소리를 받으므로 어느 앱에서 회의가
열리든 잡힙니다.

## 터미널에서 쓰기

앱 없이도 됩니다.

```sh
.venv/bin/python meeting.py                      # 녹음 파일을 골라 전사 + 요약
.venv/bin/python meeting.py --audio 회의.m4a
.venv/bin/python summarize.py transcripts/회의.txt   # 이미 있는 녹취록만 요약
```

## 잘 안 될 때

| 증상 | 원인 |
|---|---|
| "설정에서 meeting.py가 있는 프로젝트 폴더를…" | 앱 설정의 프로젝트 폴더가 비었거나 엉뚱한 폴더입니다. 4번을 다시 합니다 |
| "Claude API 키가 없습니다" | `claude_config.json`의 `api_key`가 비어 있습니다. 녹취록은 `transcripts/`에 남아 있으니 키를 채우고 `summarize.py`로 이어서 하면 됩니다 |
| "Claude가 회의록을 반환하지 않았습니다" | 녹취록에 회의 내용이 없어 모델이 요약을 거절한 경우입니다. 짧은 테스트 녹음에서 납니다 |
| 앱이 "손상되었다"며 안 열림 | 3번의 `xattr` 줄을 안 돌렸습니다 |
| 전사가 실패 | ffmpeg가 없습니다. `./install.sh`를 다시 돌립니다 |

회의록에 넣고 싶은 고유명사가 자꾸 잘못 받아써지면 `whisper_prompt.txt`에 적어 둡니다.
전사할 때 힌트로 들어갑니다. 이 파일도 커밋되지 않습니다.

## 배포하는 사람

```sh
macos/MeetingAssistant/release.sh
```

Release 빌드를 ad-hoc으로 서명해 `MeetingAssistant-<버전>.zip`을 만듭니다. 버전은
`Info.plist`의 `CFBundleShortVersionString`입니다.

앱 자체를 손보려면 [macos/MeetingAssistant/README.md](macos/MeetingAssistant/README.md)를 봅니다.

## 테스트

```sh
python -m unittest discover tests
```
