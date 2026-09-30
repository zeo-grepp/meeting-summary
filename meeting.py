import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from argparse import ArgumentParser
from datetime import date
from pathlib import Path

import questionary


# ─────────────────────────────────────
# Config
# ─────────────────────────────────────

PROJECT_DIR = Path(__file__).resolve().parent

RECORDINGS_DIR = PROJECT_DIR / "recordings"
TRANSCRIPTS_DIR = PROJECT_DIR / "transcripts"
SUMMARIES_DIR = PROJECT_DIR / "summaries"

WHISPER_MODEL = "mlx-community/whisper-large-v3-turbo"

# 키·게이트웨이 주소·모델 이름은 레포에 올리지 않는다. whisper_prompt.txt와 같은 방식이다.
CLAUDE_CONFIG_FILE = PROJECT_DIR / "claude_config.json"
DEFAULT_CLAUDE_BASE_URL = "https://api.anthropic.com"
DEFAULT_CLAUDE_MODEL = "claude-sonnet-5"
CLAUDE_MAX_TOKENS = 8192

# 팀마다 자주 나오는 고유명사가 다르다. 사내 용어를 레포에 올리지 않도록
# whisper_prompt.txt(gitignore됨)를 두면 그 내용이 아래 기본값을 대체한다.
WHISPER_PROMPT_FILE = PROJECT_DIR / "whisper_prompt.txt"
WHISPER_INITIAL_PROMPT = (
    WHISPER_PROMPT_FILE.read_text(encoding="utf-8")
    if WHISPER_PROMPT_FILE.exists()
    else """
개발팀 기술 회의입니다.
주요 용어: API, CSS, Markdown, 배포, 릴리스, 리팩터링, 마이그레이션.
"""
).strip()


SYSTEM_PROMPT = """
너는 개발팀 회의록을 작성하는 도우미다.

음성 인식으로 생성된 녹취록을 바탕으로 회의 제목과 회의록을 작성한다.

반드시 다음 규칙을 지킨다.

- 회의 제목은 녹취록의 핵심 주제를 나타내는 짧고 구체적인 제목으로 작성한다.
- "회의", "회의녹음", "미팅"처럼 내용이 드러나지 않는 제목은 사용하지 않는다.
- 녹취록에 명시적으로 존재하는 내용만 사용한다.
- 녹취록에 없는 내용을 추측해서 추가하지 않는다.
- 정확한 화자 정보가 없으면 누가 발언했는지 추측하지 않는다.
- 이름이 문장에 명시적으로 등장한 경우에만 이름을 사용한다.
- 제안, 질문, 개인 의견을 결정 사항으로 작성하지 않는다.
- 실제로 합의되거나 진행하기로 확정된 내용만 결정 사항으로 작성한다.
- 확정 여부가 애매한 내용은 미결 사항으로 작성한다.
- 담당자가 명확하게 지정된 경우에만 담당자를 액션 아이템에 기록한다.
- 음성 인식 오류로 보이는 반복 문장이나 의미 없는 문장은 무시한다.
- 같은 내용을 여러 섹션에 불필요하게 반복하지 않는다.
- 반드시 한국어로 작성한다.
- 개발 용어는 영어 그대로 사용한다.

content는 다음 Markdown 형식으로 작성한다.

## 회의 요약

- 핵심 내용

## 주요 논의 사항

### 주제

- 논의 내용

## 결정 사항

- 결정 내용

없으면 "없음"

## 액션 아이템

- [ ] 담당자: 할 일

할 일은 명확하지만 담당자가 정해지지 않았다면:

- [ ] 담당자 미정: 할 일

없으면 "없음"

## 미결 사항

- 미결 내용

없으면 "없음"

Markdown 문법 앞에 백슬래시를 붙이지 않는다.
제목(`#`)과 날짜는 content에 포함하지 않는다.
불필요한 서론, 후기, 자기평가를 출력하지 않는다.
""".strip()


RESPONSE_FORMAT = {
    "type": "object",
    "properties": {
        "title": {
            "type": "string",
            "description": "회의 핵심 주제를 나타내는 짧고 구체적인 한국어 제목",
        },
        "content": {
            "type": "string",
            "description": "Markdown 형식의 회의록 본문",
        },
    },
    "required": ["title", "content"],
}


# ─────────────────────────────────────
# Audio selection
# ─────────────────────────────────────

def select_audio_file() -> Path:
    audio_files = sorted(
        RECORDINGS_DIR.glob("*.m4a"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )

    if not audio_files:
        raise FileNotFoundError(
            f"{RECORDINGS_DIR} 폴더에 .m4a 녹음 파일이 없습니다."
        )

    selected = questionary.select(
        "녹음 파일을 선택하세요.",
        choices=[
            questionary.Choice(
                title=path.name,
                value=path,
            )
            for path in audio_files
        ],
        pointer="❯",
        use_arrow_keys=True,
        use_jk_keys=False,
    ).ask()

    if selected is None:
        raise KeyboardInterrupt

    print()
    print(f"선택: {selected.name}")

    return selected


# ─────────────────────────────────────
# Whisper
# ─────────────────────────────────────

def get_mlx_whisper_command() -> str:
    # 현재 실행 중인 Python과 같은 가상환경의 mlx_whisper를 우선 사용
    venv_command = Path(sys.executable).with_name("mlx_whisper")

    if venv_command.exists():
        return str(venv_command)

    # PATH에서 fallback
    command = shutil.which("mlx_whisper")

    if command:
        return command

    raise RuntimeError(
        "mlx_whisper 명령을 찾을 수 없습니다.\n"
        "가상환경에 mlx-whisper가 설치되어 있는지 확인해주세요."
    )


def transcribe(audio_path: Path) -> Path:
    TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)

    transcript_path = TRANSCRIPTS_DIR / f"{audio_path.stem}.txt"

    # 이전 전사 결과를 잘못 재사용하는 것을 방지
    if transcript_path.exists():
        transcript_path.unlink()

    print()
    print("[1/2] 음성을 텍스트로 변환합니다.")
    print(f"입력: {audio_path.name}")
    print(f"Whisper: {WHISPER_MODEL}")
    print()

    command = [
        get_mlx_whisper_command(),
        str(audio_path),
        "--model",
        WHISPER_MODEL,
        "--language",
        "ko",
        "--condition-on-previous-text",
        "False",
        "--word-timestamps",
        "True",
        "--hallucination-silence-threshold",
        "2",
        "--initial-prompt",
        WHISPER_INITIAL_PROMPT,
        "--output-dir",
        str(TRANSCRIPTS_DIR),
        "--output-format",
        "txt",
        "--verbose",
        "False",
    ]

    subprocess.run(
        command,
        check=True,
    )

    if not transcript_path.exists():
        raise RuntimeError(
            f"Whisper 전사 파일이 생성되지 않았습니다: {transcript_path}"
        )

    transcript = transcript_path.read_text(
        encoding="utf-8",
    ).strip()

    if not transcript:
        raise RuntimeError(
            f"Whisper 전사 결과가 비어 있습니다: {transcript_path}"
        )

    print()
    print(f"전사 완료: {transcript_path.relative_to(PROJECT_DIR)}")

    return transcript_path


# ─────────────────────────────────────
# Claude
# ─────────────────────────────────────

def claude_config() -> tuple[str, str, str]:
    """환경변수를 먼저 보고, 없으면 claude_config.json(gitignore됨)을 읽는다.
    Finder에서 띄운 앱의 환경에는 셸 export가 없어서 파일 경로가 필요하다."""
    file_values = (
        json.loads(CLAUDE_CONFIG_FILE.read_text(encoding="utf-8"))
        if CLAUDE_CONFIG_FILE.exists()
        else {}
    )

    def value(env_name: str, file_key: str, default: str = "") -> str:
        return (
            os.environ.get(env_name, "").strip()
            or str(file_values.get(file_key, "")).strip()
            or default
        )

    api_key = value("ANTHROPIC_API_KEY", "api_key")
    if not api_key:
        raise RuntimeError(
            "Claude API 키가 없습니다. ANTHROPIC_API_KEY 환경변수를 설정하거나 "
            f'{CLAUDE_CONFIG_FILE.name}에 {{"api_key": "..."}}를 넣어주세요.'
        )

    return (
        api_key,
        value("ANTHROPIC_BASE_URL", "base_url", DEFAULT_CLAUDE_BASE_URL),
        value("ANTHROPIC_MODEL", "model", DEFAULT_CLAUDE_MODEL),
    )


def messages_url(base_url: str) -> str:
    """게이트웨이 주소는 이미 /v1로 끝나는 경우가 있다.
    그대로 붙이면 /v1/v1/messages가 되어 404가 난다."""
    return f"{re.sub(r'/+(v1/*)?$', '', base_url.strip())}/v1/messages"


def summary_request_body(transcript: str, model: str) -> dict:
    # RESPONSE_FORMAT이 이미 유효한 JSON Schema다. tool 하나를 강제해 그 모양으로 받는다.
    # temperature는 보내지 않는다 — 최신 모델에서 deprecated이고 보내면 400이다.
    return {
        "model": model,
        "max_tokens": CLAUDE_MAX_TOKENS,
        "system": SYSTEM_PROMPT,
        "messages": [
            {
                "role": "user",
                "content": (
                    "다음 녹취록을 바탕으로 "
                    "회의 제목과 회의록을 작성해줘.\n\n"
                    f"{transcript}"
                ),
            },
        ],
        "tools": [
            {
                "name": "write_meeting_notes",
                "description": "회의 제목과 Markdown 회의록을 기록한다.",
                "input_schema": RESPONSE_FORMAT,
            },
        ],
        "tool_choice": {"type": "tool", "name": "write_meeting_notes"},
    }


def call_claude(body: dict, api_key: str, base_url: str) -> dict:
    request = urllib.request.Request(
        messages_url(base_url),
        data=json.dumps(body).encode("utf-8"),
        headers={
            "content-type": "application/json",
            "anthropic-version": "2023-06-01",
            "x-api-key": api_key,
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace").strip()
        raise RuntimeError(f"Claude 요청 실패 ({error.code}): {detail}") from error
    except OSError as error:
        raise RuntimeError(f"Claude 서버에 연결하지 못했습니다: {error}") from error

    for block in payload.get("content", []):
        if block.get("type") == "tool_use":
            return block["input"]

    raise RuntimeError("Claude가 회의록을 반환하지 않았습니다.")


def summarize(transcript: str) -> tuple[str, str]:
    api_key, base_url, model = claude_config()

    print()
    print("[2/2] 회의록을 생성합니다.")
    print(f"Claude: {model}")
    print()

    result = call_claude(summary_request_body(transcript, model), api_key, base_url)

    title = result.get("title", "").strip()
    content = result.get("content", "").strip()

    if not title:
        raise RuntimeError("AI가 회의 제목을 생성하지 못했습니다.")

    if not content:
        raise RuntimeError("AI가 회의록을 생성하지 못했습니다.")

    return title, content


# ─────────────────────────────────────
# Markdown
# ─────────────────────────────────────

def create_summary(
    transcript_path: Path,
    meeting_date: str,
    title_override: str | None = None,
) -> Path:
    transcript = transcript_path.read_text(
        encoding="utf-8",
    ).strip()

    generated_title, content = summarize(transcript)

    title = title_override or generated_title

    markdown = f"""# {title}

`{meeting_date}`

{content}
"""

    SUMMARIES_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    summary_path = SUMMARIES_DIR / f"{transcript_path.stem}.md"

    summary_path.write_text(
        markdown,
        encoding="utf-8",
    )

    print(f"회의 제목: {title}")
    print(f"회의록 생성 완료: {summary_path.relative_to(PROJECT_DIR)}")

    return summary_path


# ─────────────────────────────────────
# Main
# ─────────────────────────────────────

def main():
    parser = ArgumentParser(
        description="회의 녹음을 전사하고 Markdown 회의록으로 요약합니다.",
    )

    parser.add_argument(
        "--audio",
        help="녹음 파일 경로. 지정하지 않으면 recordings 폴더에서 직접 고릅니다.",
    )

    parser.add_argument(
        "--title",
        help="회의 제목. 지정하지 않으면 AI가 녹취록을 바탕으로 생성합니다.",
    )

    parser.add_argument(
        "--date",
        default=date.today().isoformat(),
        help="회의 날짜 (기본값: 오늘, YYYY-MM-DD)",
    )

    args = parser.parse_args()

    try:
        if args.audio:
            audio_path = Path(args.audio).expanduser()

            if not audio_path.is_file():
                parser.error(f"녹음 파일을 찾을 수 없습니다: {audio_path}")
        else:
            audio_path = select_audio_file()

        transcript_path = transcribe(audio_path)

        summary_path = create_summary(
            transcript_path=transcript_path,
            meeting_date=args.date,
            title_override=args.title,
        )

        print()
        print("완료!")
        print(
            f"녹취록: {transcript_path.relative_to(PROJECT_DIR)}"
        )
        print(
            f"회의록: {summary_path.relative_to(PROJECT_DIR)}"
        )

    except KeyboardInterrupt:
        print()
        print("취소되었습니다.")
        # 종료 코드 0으로 끝나면 호출한 쪽이 취소를 성공으로 읽는다.
        raise SystemExit(1)


if __name__ == "__main__":
    main()