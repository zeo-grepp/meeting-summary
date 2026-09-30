# meeting-summary

회의 녹음을 전사하고 Markdown 회의록으로 요약합니다.
전사는 로컬(mlx-whisper), 요약은 Claude API로 합니다.

## 준비물

- macOS (Apple Silicon), Python 3.12+
- `ffmpeg`
- `pip install mlx-whisper questionary`
- Claude API 키

## 키 설정

환경변수를 먼저 보고, 없으면 프로젝트 폴더의 `claude_config.json`을 읽습니다.
메뉴바 앱은 Finder에서 실행되어 셸 환경변수를 물려받지 못하므로 파일 쪽을 씁니다.
두 자리 모두 `.gitignore` 대상이며 레포에 올라가지 않습니다.

```sh
export ANTHROPIC_API_KEY=...
export ANTHROPIC_BASE_URL=...   # 선택, 게이트웨이를 쓸 때만
export ANTHROPIC_MODEL=...      # 선택
```

```json
{
  "api_key": "...",
  "base_url": "...",
  "model": "..."
}
```

전사에 쓸 고유명사 프롬프트가 필요하면 `whisper_prompt.txt`에 적습니다(역시 gitignore).

## 실행

```sh
python meeting.py                 # 녹음 파일을 골라서 전사 + 요약
python meeting.py --audio a.m4a
python summarize.py transcripts/a.txt   # 이미 있는 녹취록만 요약
```

키가 없으면 전사까지는 끝나고 요약 단계에서 멈춥니다. `transcripts/*.txt`는 남습니다.

## 테스트

```sh
python -m unittest discover tests
```

macOS 메뉴바 앱은 [macos/MeetingAssistant/README.md](macos/MeetingAssistant/README.md)를 참고하세요.
