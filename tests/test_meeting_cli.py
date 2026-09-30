import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import meeting


class AudioArgumentTests(unittest.TestCase):
    """--audio 분기만 확인한다. 전사/요약은 막아 무거운 모델을 돌리지 않는다."""

    def run_main(self, argv: list[str]):
        with (
            patch.object(sys, "argv", ["meeting.py", *argv]),
            patch.object(meeting, "select_audio_file") as select,
            patch.object(meeting, "transcribe") as transcribe,
            patch.object(meeting, "create_summary") as create_summary,
        ):
            transcribe.return_value = meeting.TRANSCRIPTS_DIR / "x.txt"
            create_summary.return_value = meeting.SUMMARIES_DIR / "x.md"
            meeting.main()
            return select, transcribe

    def test_given_audio_path_is_used_without_prompting(self):
        with TemporaryDirectory() as directory:
            audio = Path(directory) / "meeting.m4a"
            audio.touch()

            select, transcribe = self.run_main(["--audio", str(audio)])

            select.assert_not_called()
            self.assertEqual(transcribe.call_args.args[0], audio)

    def test_missing_audio_path_exits_with_failure(self):
        with self.assertRaises(SystemExit) as raised:
            self.run_main(["--audio", "/tmp/does-not-exist.m4a"])

        self.assertNotEqual(raised.exception.code, 0)

    def test_without_audio_falls_back_to_interactive_selection(self):
        select, transcribe = self.run_main([])

        select.assert_called_once()
        self.assertEqual(transcribe.call_args.args[0], select.return_value)


class ClaudeRequestTests(unittest.TestCase):
    """네트워크는 타지 않는다. 주소 조립과 요청 본문만 본다."""

    def test_messages_path_is_appended_exactly_once(self):
        for base in [
            "https://gateway.example.com",
            "https://gateway.example.com/",
            "https://gateway.example.com/v1",
            " https://gateway.example.com/v1/ ",
        ]:
            with self.subTest(base=base):
                self.assertEqual(
                    meeting.messages_url(base),
                    "https://gateway.example.com/v1/messages",
                )

    def test_request_offers_one_tool_without_temperature_or_tool_choice(self):
        body = meeting.summary_request_body("녹취록", "test-model")

        # 게이트웨이가 둘 다 400으로 막는다.
        self.assertNotIn("temperature", body)
        self.assertNotIn("tool_choice", body)
        self.assertEqual(len(body["tools"]), 1)
        self.assertEqual(body["tools"][0]["input_schema"], meeting.RESPONSE_FORMAT)

    def test_json_in_plain_text_is_read_when_the_tool_is_skipped(self):
        payload = {"content": [{"type": "text", "text": '설명\n```json\n{"title": "제목", "content": "본문"}\n```'}]}

        with patch.object(meeting.urllib.request, "urlopen") as urlopen:
            urlopen.return_value.__enter__.return_value.read.return_value = json.dumps(payload)
            result = meeting.call_claude({}, "key", "https://gateway.example.com")

        self.assertEqual(result["title"], "제목")


if __name__ == "__main__":
    unittest.main()
