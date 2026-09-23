import json
from argparse import ArgumentParser
from datetime import date
from pathlib import Path

from ollama import chat


MODEL = "gemma4:31b-mlx"

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
제목(`#`)은 content에 포함하지 않는다.
""".strip()


RESPONSE_FORMAT = {
    "type": "object",
    "properties": {
        "title": {
            "type": "string",
            "description": "회의의 핵심 주제를 나타내는 짧고 구체적인 한국어 제목",
        },
        "content": {
            "type": "string",
            "description": "Markdown 형식의 회의록 본문",
        },
    },
    "required": ["title", "content"],
}


def summarize(transcript: str) -> tuple[str, str]:
    response = chat(
        model=MODEL,
        messages=[
            {
                "role": "system",
                "content": SYSTEM_PROMPT,
            },
            {
                "role": "user",
                "content": f"다음 녹취록을 회의록으로 정리해줘.\n\n{transcript}",
            },
        ],
        format=RESPONSE_FORMAT,
        stream=False,
        think=False,
        options={
            "temperature": 0,
        },
    )

    result = json.loads(response.message.content)

    return result["title"].strip(), result["content"].strip()


def main():
    parser = ArgumentParser(
        description="회의 녹취록을 Ollama를 사용해 Markdown 회의록으로 요약합니다.",
    )

    parser.add_argument(
        "transcript",
        help="요약할 transcript txt 파일",
    )

    parser.add_argument(
        "--title",
        help="회의 제목. 지정하지 않으면 AI가 녹취록을 기반으로 생성합니다.",
    )

    parser.add_argument(
        "--date",
        default=date.today().isoformat(),
        help="회의 날짜 (기본값: 오늘, YYYY-MM-DD)",
    )

    parser.add_argument(
        "-o",
        "--output",
        help="저장할 Markdown 파일",
    )

    args = parser.parse_args()

    transcript_path = Path(args.transcript)

    if not transcript_path.exists():
        raise FileNotFoundError(
            f"녹취록 파일을 찾을 수 없습니다: {transcript_path}"
        )

    if not transcript_path.is_file():
        raise ValueError(
            f"파일이 아닙니다: {transcript_path}"
        )

    transcript = transcript_path.read_text(encoding="utf-8").strip()

    if not transcript:
        raise ValueError(
            f"녹취록이 비어 있습니다: {transcript_path}"
        )

    output_path = (
        Path(args.output)
        if args.output
        else Path("summaries") / f"{transcript_path.stem}.md"
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"회의록 생성 중: {transcript_path}")
    print(f"모델: {MODEL}")

    generated_title, content = summarize(transcript)

    # --title을 입력했다면 사용자 입력을 우선 사용
    title = args.title or generated_title

    markdown = f"""# {title}

`{args.date}`

{content}
"""

    output_path.write_text(markdown, encoding="utf-8")

    print(f"완료: {output_path}")
    print(f"회의 제목: {title}")


if __name__ == "__main__":
    main()
