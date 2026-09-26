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


if __name__ == "__main__":
    unittest.main()
