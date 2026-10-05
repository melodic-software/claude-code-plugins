"""Tests for recall_scan.py, run as a subprocess over transcripts written into a temp store."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCAN = HERE / "recall_scan.py"
PLUGIN_ROOT = HERE.parents[2]

# Built at run time so no token-shaped literal sits in the repository.
SEEDED_TOKEN = "ghp_" + "Q7" * 18


def user(session: str, stamp: str, text: str) -> dict:
    return {
        "type": "user",
        "sessionId": session,
        "timestamp": stamp,
        "message": {"role": "user", "content": text},
    }


def assistant(session: str, stamp: str, text: str) -> dict:
    return {
        "type": "assistant",
        "sessionId": session,
        "timestamp": stamp,
        "message": {"role": "assistant", "content": [{"type": "text", "text": text}]},
    }


def write_transcript(directory: Path, session: str, records: list[dict]) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{session}.jsonl"
    path.write_text("".join(json.dumps(r) + "\n" for r in records), encoding="utf-8")
    return path


def tree(root: Path) -> list[str]:
    return sorted(str(p.relative_to(root)) for p in root.rglob("*"))


class RecallScanTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="recall-scan-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.store = self.tmp / "projects"
        self.alpha = self.store / "-work-orders-api"
        self.beta = self.store / "-work-orders-api-wt-retry"
        self.gamma = self.store / "-work-unrelated"

    def run_scan(
        self, *args: str, script: Path = SCAN
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(script), *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            cwd=self.tmp,
            timeout=60,
        )

    def lines(self, result: subprocess.CompletedProcess[str]) -> list[dict]:
        return [json.loads(line) for line in result.stdout.splitlines()]

    def test_lists_matches_from_both_directories_and_nothing_else(self) -> None:
        write_transcript(
            self.alpha,
            "s-alpha",
            [
                user(
                    "s-alpha",
                    "2026-09-01T10:00:00Z",
                    "Try a retry budget of three on the webhook client.",
                ),
                assistant(
                    "s-alpha",
                    "2026-09-01T10:01:00Z",
                    "Added the retry budget; tests pass.",
                ),
                user("s-alpha", "2026-09-01T10:02:00Z", "Now rename the module."),
            ],
        )
        write_transcript(
            self.beta,
            "s-beta",
            [
                assistant(
                    "s-beta",
                    "2026-09-03T09:00:00Z",
                    "Reverted the Retry Budget change: it hid timeouts.",
                )
            ],
        )
        write_transcript(
            self.gamma,
            "s-gamma",
            [
                user(
                    "s-gamma", "2026-09-04T09:00:00Z", "retry budget in another project"
                )
            ],
        )
        before = tree(self.tmp)

        result = self.run_scan(
            "--dir", str(self.alpha), "--dir", str(self.beta), "--term", "retry budget"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        found = self.lines(result)
        self.assertEqual(len(found), 3)
        for line in found:
            self.assertEqual(
                set(line) - {"term"}, {"session", "file", "time", "role", "snippet"}
            )
        self.assertEqual({line["session"] for line in found}, {"s-alpha", "s-beta"})
        self.assertEqual(
            sorted(line["role"] for line in found), ["assistant", "assistant", "user"]
        )
        self.assertIn(
            ("s-beta", "2026-09-03T09:00:00Z", str(self.beta / "s-beta.jsonl")),
            {(line["session"], line["time"], line["file"]) for line in found},
        )
        self.assertNotIn("rename the module", result.stdout)
        self.assertEqual(tree(self.tmp), before)

    def test_regex_metacharacters_match_literally(self) -> None:
        write_transcript(
            self.alpha,
            "s-meta",
            [
                user("s-meta", "2026-09-01T10:00:00Z", "the cache0 warmup is slow"),
                user(
                    "s-meta",
                    "2026-09-01T10:05:00Z",
                    "drop the cache[0].* glob from the config",
                ),
            ],
        )

        result = self.run_scan("--dir", str(self.alpha), "--term", "cache[0].*")

        self.assertEqual(result.returncode, 0, result.stderr)
        found = self.lines(result)
        self.assertEqual([line["time"] for line in found], ["2026-09-01T10:05:00Z"])

    def test_shell_text_and_tab_stay_one_json_string(self) -> None:
        text = "deploy step ran $(touch PWNED)\tthen stopped"
        write_transcript(
            self.alpha, "s-shell", [user("s-shell", "2026-09-02T08:00:00Z", text)]
        )

        result = self.run_scan("--dir", str(self.alpha), "--term", "deploy step")

        self.assertEqual(result.returncode, 0, result.stderr)
        raw = result.stdout.splitlines()
        self.assertEqual(len(raw), 1)
        self.assertIn("\\t", raw[0])
        self.assertEqual(json.loads(raw[0])["snippet"], text)
        self.assertEqual(list(self.tmp.rglob("PWNED")), [])
        self.assertFalse(Path("PWNED").exists())

    def test_seeded_token_is_redacted(self) -> None:
        write_transcript(
            self.alpha,
            "s-secret",
            [
                assistant(
                    "s-secret",
                    "2026-09-02T08:00:00Z",
                    f"The release token {SEEDED_TOKEN} worked once.",
                )
            ],
        )

        result = self.run_scan("--dir", str(self.alpha), "--term", "release token")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(SEEDED_TOKEN, result.stdout)
        self.assertNotIn(SEEDED_TOKEN, result.stderr)
        (line,) = self.lines(result)
        self.assertIn("<redacted:", line["snippet"])

    def test_snippet_is_bounded_and_keeps_the_term(self) -> None:
        text = "x" * 3000 + " flaky webhook " + "y" * 3000
        write_transcript(
            self.alpha, "s-long", [user("s-long", "2026-09-02T08:00:00Z", text)]
        )

        result = self.run_scan("--dir", str(self.alpha), "--term", "flaky webhook")

        (line,) = self.lines(result)
        self.assertLessEqual(len(line["snippet"]), 240)
        self.assertIn("flaky webhook", line["snippet"])

    def test_matches_per_session_are_capped_and_the_cap_is_reported(self) -> None:
        records = [
            user("s-many", f"2026-09-02T08:{n:02d}:00Z", f"queue drain attempt {n}")
            for n in range(15)
        ]
        write_transcript(self.alpha, "s-many", records)

        result = self.run_scan("--dir", str(self.alpha), "--term", "queue drain")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.lines(result)), 10)
        self.assertIn("capped", result.stderr)

    def test_skip_session_leaves_that_session_out(self) -> None:
        write_transcript(
            self.alpha,
            "s-now",
            [
                user(
                    "s-now",
                    "2026-09-05T08:00:00Z",
                    "what did we try for the retry budget",
                )
            ],
        )
        write_transcript(
            self.alpha,
            "s-then",
            [user("s-then", "2026-09-01T08:00:00Z", "set the retry budget to 3")],
        )

        result = self.run_scan(
            "--dir",
            str(self.alpha),
            "--term",
            "retry budget",
            "--skip-session",
            "s-now",
        )

        self.assertEqual([line["session"] for line in self.lines(result)], ["s-then"])

    def test_redactor_failing_closed_prints_no_snippet_and_exits_1(self) -> None:
        copy = self.tmp / "plugin"
        (copy / "skills" / "recall" / "scripts").mkdir(parents=True)
        (copy / "scripts").mkdir()
        (copy / "skills" / "audit-sessions" / "scripts").mkdir(parents=True)
        rules = copy / "skills" / "audit-sessions" / "vendor" / "gitleaks"
        rules.mkdir(parents=True)
        shutil.copy(SCAN, copy / "skills" / "recall" / "scripts" / "recall_scan.py")
        shutil.copy(PLUGIN_ROOT / "scripts" / "transcript_reader.py", copy / "scripts")
        shutil.copy(
            PLUGIN_ROOT / "skills" / "audit-sessions" / "scripts" / "redact.py",
            copy / "skills" / "audit-sessions" / "scripts",
        )
        (rules / "gitleaks-rules.json").write_text(
            '{"rules": [{"id": "broken", "regex": "("}]}', encoding="utf-8"
        )
        write_transcript(
            self.alpha,
            "s-closed",
            [user("s-closed", "2026-09-02T08:00:00Z", "retry budget notes")],
        )

        result = self.run_scan(
            "--dir",
            str(self.alpha),
            "--term",
            "retry budget",
            script=copy / "skills" / "recall" / "scripts" / "recall_scan.py",
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("retry budget notes", result.stderr)

    def test_missing_directory_exits_2(self) -> None:
        write_transcript(
            self.alpha,
            "s-alpha",
            [user("s-alpha", "2026-09-01T10:00:00Z", "retry budget")],
        )

        result = self.run_scan(
            "--dir",
            str(self.alpha),
            "--dir",
            str(self.store / "gone"),
            "--term",
            "retry budget",
        )

        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_empty_term_exits_2(self) -> None:
        self.alpha.mkdir(parents=True)

        result = self.run_scan("--dir", str(self.alpha), "--term", "")

        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
