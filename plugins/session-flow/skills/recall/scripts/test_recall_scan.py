# test-scope: plugins/session-flow/scripts/*.py plugins/session-flow/lib/claude_projects.py
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCAN = HERE / "recall_scan.py"
PLUGIN_ROOT = HERE.parents[2]
sys.path.insert(0, str(PLUGIN_ROOT / "scripts"))

import transcript_run  # noqa: E402  (scripts/transcript_run.py)
import transcript_sources  # noqa: E402  (scripts/transcript_sources.py)

LOCK_NAME = f"claude-transcript-run.t-{uuid.uuid4().hex[:16]}"

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
            [sys.executable, str(script), *args, "--lock-name", LOCK_NAME],
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

    def test_run_stops_at_200_matches_and_skips_the_oldest_transcripts(self) -> None:
        for n in range(25):
            session = f"s-{n:02d}"
            path = write_transcript(
                self.alpha,
                session,
                [
                    user(session, "2026-09-02T08:00:00Z", f"cache miss {k}")
                    for k in range(10)
                ],
            )
            os.utime(path, (1_700_000_000 + n, 1_700_000_000 + n))

        result = self.run_scan("--dir", str(self.alpha), "--term", "cache miss")

        self.assertEqual(result.returncode, 0, result.stderr)
        sessions = [line["session"] for line in self.lines(result)]
        self.assertEqual(len(sessions), 200)
        self.assertEqual(sorted(set(sessions)), [f"s-{n:02d}" for n in range(5, 25)])
        self.assertIn(
            "stopped at 200 matches; older transcripts were not read", result.stderr
        )

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

    def test_redactor_failing_closed_prints_no_snippet_and_exits_2(self) -> None:
        copy = self.tmp / "plugin"
        (copy / "skills" / "recall" / "scripts").mkdir(parents=True)
        (copy / "scripts").mkdir()
        rules = copy / "vendor" / "gitleaks"
        rules.mkdir(parents=True)
        shutil.copy(SCAN, copy / "skills" / "recall" / "scripts" / "recall_scan.py")
        for module in (PLUGIN_ROOT / "scripts").glob("*.py"):
            shutil.copy(module, copy / "scripts")
        (copy / "lib").mkdir()
        shutil.copy(PLUGIN_ROOT / "lib" / "claude_projects.py", copy / "lib")
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

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("nothing published: the secret redaction rules did not load", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("retry budget notes", result.stderr)

    def sources_file(self, **defaults: object) -> Path:
        path = self.tmp / "sources.json"
        path.write_text(json.dumps({"schema": "transcript-sources/v1", "defaults": defaults, "sources": [
            {"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": str(self.tmp)},
            {"name": "host-b-wsl", "host": "host-b", "platform": "wsl", "config_dir": "/srv/user-b/.claude", "via": ["ssh", "host-b"]},
        ]}), encoding="utf-8")
        return path

    def make_store(self) -> Path:
        store = self.tmp / "data" / "audit-sessions" / "store" / "v2"
        (store / transcript_sources.DIAGNOSTICS_DIR).mkdir(parents=True)
        return store

    def test_header_gaps_and_stale(self) -> None:
        store = self.make_store()
        finished = (datetime.now(timezone.utc) - timedelta(days=20)).strftime("%Y-%m-%dT%H:%M:%SZ")
        retry = ["python3", "/srv/plugin/scripts/collect.py", "collect", "--data-dir", "/srv/data", "--source", "host-b-wsl"]
        record = store / transcript_sources.DIAGNOSTICS_DIR / "run-1.json"
        record.write_text(json.dumps({
            "schema": "transcript-run.diagnostics/v1", "kind": "ingest", "started_at": finished, "finished_at": finished,
            "sources": [{"name": "host-a-wsl", "gaps": 0, "cleanup_period_days": 30}, {"name": "host-b-wsl", "gaps": 1, "cleanup_period_days": 30}],
            "gaps": [{"source": "host-b-wsl", "kind": "unreachable", "detail": "ssh exited 255", "holder_pid": None, "retry_argv": retry}],
        }), encoding="utf-8")
        write_transcript(self.alpha, "s-alpha", [user("s-alpha", "2026-09-01T10:00:00Z", "retry budget")])

        result = self.run_scan(
            "--dir", str(self.alpha), "--term", "retry budget", "--data-dir", str(self.tmp / "data"),
            "--sources-file", str(self.sources_file()),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        header = [line for line in result.stderr.splitlines() if line.split(":")[0] in ("Gap", "Stale", "Diagnostics")]
        self.assertEqual(len(header), 4, result.stderr)
        self.assertEqual(header, [
            "Gap: host-b-wsl unreachable: ssh exited 255. Retry: " + " ".join(retry),
            f"Stale: host-a-wsl was last collected without a gap at {finished}, past half its cleanupPeriodDays of 30.",
            "Stale: host-b-wsl has no collection without a gap in the retained diagnostics.",
            f"Diagnostics: {record}",
        ])

    def write_history(self, store: Path, key: str, session: str, project: str) -> None:
        prompt = store / "host-a-wsl" / "history" / f"{key}.json"
        prompt.parent.mkdir(parents=True, exist_ok=True)
        prompt.write_text(json.dumps({
            "schema": "history-prompt/v1", "key": key, "session_id": session, "project": project,
            "time": {"start": "2026-08-01T09:00:00Z", "end": "2026-08-01T09:00:00Z"},
            "excerpt": "what retry budget did we settle on", "pastes": {"restored": 0, "missing": 0},
        }), encoding="utf-8")

    def test_history_only_prompts_match_from_the_store(self) -> None:
        self.write_history(self.make_store(), "aaaabbbbaaaabbbb", "s-gone", "/work/orders/api")
        self.alpha.mkdir(parents=True)

        result = self.run_scan("--dir", str(self.alpha), "--term", "retry budget", "--data-dir", str(self.tmp / "data"))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.lines(result), [{
            "session": "s-gone", "file": "history.jsonl", "time": "2026-08-01T09:00:00Z", "role": "user",
            "term": "retry budget", "snippet": "what retry budget did we settle on", "history": True,
        }])

    def test_a_history_prompt_from_another_project_is_kept_only_under_the_all_scope(self) -> None:
        self.write_history(self.make_store(), "ccccddddccccdddd", "s-elsewhere", "/elsewhere/other-repo")
        self.alpha.mkdir(parents=True)
        args = ("--dir", str(self.alpha), "--term", "retry budget", "--data-dir", str(self.tmp / "data"))

        worktree = self.run_scan(*args)
        everything = self.run_scan(*args, "--scope", "all")

        self.assertEqual((worktree.returncode, everything.returncode), (0, 0), worktree.stderr + everything.stderr)
        self.assertEqual(self.lines(worktree), [], "a worktree scan reads no other project's prompts")
        self.assertEqual([line["session"] for line in self.lines(everything)], ["s-elsewhere"])

    def test_a_held_host_lock_is_a_gap_and_reads_nothing(self) -> None:
        self.make_store()
        write_transcript(self.alpha, "s-alpha", [user("s-alpha", "2026-09-01T10:00:00Z", "retry budget")])
        holder = transcript_run.local_lock(LOCK_NAME)
        self.addCleanup(holder.release)
        if holder.mechanism == "missing":
            self.skipTest("no per-host lock on this platform")

        result = self.run_scan(
            "--dir", str(self.alpha), "--term", "retry budget", "--data-dir", str(self.tmp / "data"),
            "--sources-file", str(self.sources_file(lock_timeout_s=0)),
        )

        self.assertEqual((result.returncode, result.stdout), (1, ""), result.stderr)
        self.assertRegex(result.stderr, r"(?m)^Gap: host-a-wsl busy: another reader holds the host lock")
        retry = next(line for line in result.stderr.splitlines() if line.startswith("Gap: ")).split(". Retry: ", 1)[1]
        self.assertTrue(retry.endswith(f"--lock-name {LOCK_NAME}"), retry)
        records = list((self.tmp / "data" / "audit-sessions" / "store" / "v2" / transcript_sources.DIAGNOSTICS_DIR).glob("*.json"))
        self.assertEqual([json.loads(r.read_text(encoding="utf-8"))["kind"] for r in records], ["lookup"])

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

    def test_snippet_and_file_carry_no_host_home_path_or_email(self) -> None:
        home_b = "/" + "home/user-b"
        sources = self.tmp / "sources.json"
        sources.write_text(
            json.dumps(
                {
                    "schema": "transcript-sources/v1",
                    "sources": [
                        {"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": str(self.tmp)},
                        {
                            "name": "host-b-wsl",
                            "host": "host-b",
                            "platform": "wsl",
                            "config_dir": "/srv/user-b/.claude",
                            "via": ["ssh", "host-b"],
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        text = f"retry budget on host-b in {home_b}/notes, ask ops-b" + "@" + "example.org"
        write_transcript(self.alpha, "s-fleet", [user("s-fleet", "2026-09-02T08:00:00Z", text)])

        result = self.run_scan(
            "--dir", str(self.alpha), "--term", "retry budget", "--sources-file", str(sources)
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        (line,) = self.lines(result)
        self.assertEqual(line["snippet"], "retry budget on <host-2> in ~/notes, ask <email>")
        self.assertEqual(line["file"], "<host-1:config>/projects/-work-orders-api/s-fleet.jsonl")
        for value in ("host-b", home_b, "example.org", str(self.tmp)):
            self.assertNotIn(value, result.stdout)

    def test_empty_term_exits_2(self) -> None:
        self.alpha.mkdir(parents=True)

        result = self.run_scan("--dir", str(self.alpha), "--term", "")

        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
