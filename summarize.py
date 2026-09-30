from argparse import ArgumentParser
from datetime import date
from pathlib import Path

from meeting import summarize


def main():
    parser = ArgumentParser(
        description="회의 녹취록을 Claude를 사용해 Markdown 회의록으로 요약합니다.",
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
