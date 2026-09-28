"""Batch recycle re-checks inside the approved process and never unlinks."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import batch_recycle
import destructive_guard as guard
import hygiene


class BatchRecycleTest(unittest.TestCase):
    def test_script_recycles_and_does_not_permanently_delete(self) -> None:
        script = Path(batch_recycle._RECYCLE_SCRIPT).read_text(encoding="utf-8")
        self.assertIn("SendToRecycleBin", script)
        self.assertNotIn("Remove-Item", script)
        self.assertFalse(batch_recycle.permanent_delete_used())
        source = Path(batch_recycle.__file__).read_text(encoding="utf-8")
        self.assertNotIn("os.remove", source)
        self.assertNotIn("unlink", source)
        self.assertNotIn("rmtree", source)

    def test_clear_path_is_rechecked_and_left_in_place_off_windows(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "target"
            data = root / "data"
            target.mkdir()
            data.mkdir()
            leaf = target / "note.tmp"
            leaf.write_text("x", encoding="utf-8")
            snap = data / "snapshot.json"
            self.assertEqual(
                0,
                self._main(
                    [
                        "scan",
                        "--target",
                        str(target),
                        "--output",
                        str(snap),
                        "--data-root",
                        str(data),
                    ]
                ),
            )
            code, payload = self._json_main(
                [
                    "batch-recycle",
                    "--snapshot",
                    str(snap),
                    "--tier",
                    "high",
                    "--path",
                    "note.tmp",
                    "--data-root",
                    str(data),
                ]
            )
            self.assertEqual(0, code)
            self.assertEqual("high", payload["tier"])
            self.assertEqual(1, payload["count"])
            self.assertFalse(payload["permanent_delete"])
            self.assertNotEqual("recycled", payload["results"][0]["action"])
            self.assertEqual("recycle-unsupported", payload["results"][0]["reason"])
            self.assertTrue(leaf.is_file())
            leaf.unlink()
            leaf.mkdir()
            _, again = self._json_main(
                [
                    "batch-recycle",
                    "--snapshot",
                    str(snap),
                    "--tier",
                    "high",
                    "--path",
                    "note.tmp",
                    "--data-root",
                    str(data),
                ]
            )
            self.assertNotEqual("recycled", again["results"][0]["action"])
            self.assertIn(
                again["results"][0]["reason"],
                {"type-changed", "drifted", "contested", "gone"},
            )
            self.assertTrue(leaf.is_dir())

    def test_more_than_32_paths_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "target"
            data = root / "data"
            target.mkdir()
            data.mkdir()
            (target / "a.tmp").write_text("x", encoding="utf-8")
            snap = data / "snapshot.json"
            self._main(
                [
                    "scan",
                    "--target",
                    str(target),
                    "--output",
                    str(snap),
                    "--data-root",
                    str(data),
                ]
            )
            argv = [
                "batch-recycle",
                "--snapshot",
                str(snap),
                "--tier",
                "low",
                "--data-root",
                str(data),
            ]
            for index in range(33):
                argv.extend(["--path", f"p{index}.tmp"])
            code, payload = self._json_main(argv)
            self.assertEqual(2, code)
            self.assertIn("at most", payload["error"])
            self.assertTrue((target / "a.tmp").is_file())

    def test_ask_reason_lists_tier_count_and_every_path(self) -> None:
        reason = guard.batch_recycle_ask_reason(
            "python hygiene.py batch-recycle --snapshot s --tier medium "
            "--path one.tmp --path two.tmp --data-root /data"
        )
        self.assertIn("tier medium", reason)
        self.assertIn("2 path(s)", reason)
        self.assertIn("one.tmp", reason)
        self.assertIn("two.tmp", reason)
        self.assertNotIn('"allow"', reason)

    def test_skill_states_the_prompt_rules(self) -> None:
        text = Path(__file__).resolve().parents[1].joinpath("SKILL.md").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "Settings allow rules cannot remove the deletion prompts.", text
        )
        self.assertIn("do not also ask `AskUserQuestion`", text)
        handoff = (
            Path(__file__).resolve().parents[1]
            / "reference"
            / "unsupported-platform-handoff.md"
        ).read_text(encoding="utf-8")
        self.assertIn("batch-recycle", handoff)
        self.assertIn("re-checks", handoff)

    def _main(self, argv: list[str]) -> int:
        with redirect_stdout(io.StringIO()):
            return hygiene.main(argv)

    def _json_main(self, argv: list[str]) -> tuple[int, dict]:
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            code = hygiene.main(argv)
        return code, json.loads(stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
