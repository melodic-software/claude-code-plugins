"""Tests for lane_legs.py: chosen CI lane runs resolved to their legs through a sink's metrics.jsonl.

Every sink is built in tmp_path from hand-written rows; no real sink is read.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "lane_legs.py"
URL = "https://github.com/acme/widgets/actions/runs"


def row(run: int, leg: str, *, attempt: int = 1, lane: str = "pr-verify", date: str = "2026-11-01", hour: int = 10, outcome: str = "success", is_error: bool = False, model: str = "model-a", neutral: bool = True, transcript: str | None = "auto") -> dict:
    created = f"{date}T{hour:02d}:00:00Z"
    stored = f"transcripts/{date}/{lane}/{run}-{attempt}-{leg}.json.gz" if transcript == "auto" else transcript
    out = {
        "artifact_id": run * 100 + len(leg),
        "run_id": run,
        "run_attempt": attempt,
        "job_id": leg,
        "lane": lane,
        "workflow": lane,
        "event": "pull_request",
        "head_branch": "feat/x",
        "run_conclusion": "success",
        "created_at": created,
        "date": date,
        "model": model,
        "models": [model],
        "outcome": outcome,
        "subtype": "success" if outcome != "error" else "error_during_execution",
        "is_error": is_error,
        "num_turns": 3,
        "duration_ms": 1000,
        "transcript": stored,
    }
    if neutral:
        out.update(provider="github", run_ref=str(run), run_url=f"{URL}/{run}/attempts/{attempt}", leg_key=leg)
    return out


def sink_with(tmp_path: Path, rows: list[dict]) -> Path:
    sink = tmp_path / "sink"
    sink.mkdir()
    (sink / "metrics.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    return sink


def resolve(*args: str) -> tuple[int, dict | None, str]:
    done = subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, timeout=30)
    try:
        body = json.loads(done.stdout)
    except ValueError:
        body = None
    return done.returncode, body, done.stderr


def legs_of(body: dict) -> list[tuple[str, str, str | None, int | None]]:
    return [(r["run_ref"], leg["leg_key"], leg["kind"], leg["chunk"]) for r in body["runs"] for leg in r["legs"]]


def test_a_run_url_resolves_to_every_leg_of_that_run(tmp_path):
    sink = sink_with(tmp_path, [row(7, "check-intent"), row(7, "check-intent-subscription", hour=11), row(8, "check-intent")])

    code, body, _ = resolve("--sink", str(sink), f"{URL}/7/job/123")

    assert code == 0
    assert legs_of(body) == [("7", "check-intent", "key", None), ("7", "check-intent-subscription", "subscription", None)]
    assert body["runs"][0]["run_url"] == f"{URL}/7/attempts/1"
    assert body["runs"][0]["legs"][0]["transcript"] == str(sink / "transcripts/2026-11-01/pr-verify/7-1-check-intent.json.gz")


def test_a_bare_run_id_resolves_and_an_attempt_in_the_url_narrows_it(tmp_path):
    sink = sink_with(tmp_path, [row(7, "check-intent"), row(7, "check-intent", attempt=2, hour=12)])

    _, by_id, _ = resolve("--sink", str(sink), "7")
    _, by_attempt, _ = resolve("--sink", str(sink), f"{URL}/7/attempts/2")

    assert [r["run_attempt"] for r in by_id["runs"]] == [2, 1]
    assert [r["run_attempt"] for r in by_attempt["runs"]] == [2]


def test_review_legs_carry_their_kind_and_chunk(tmp_path):
    lane = "pr-review-main"
    legs = ["review-claude-review", "review-claude-review-2", "review-fallback-claude-security-review-3", "code-review-subscription-4"]
    sink = sink_with(tmp_path, [row(9, leg, lane=lane, hour=10 + i) for i, leg in enumerate(legs)])

    _, body, _ = resolve("--sink", str(sink), "9")

    assert [(k, c) for _, _, k, c in legs_of(body)] == [("key", 1), ("key", 2), ("fallback", 3), ("subscription", 4)]


def test_a_writer_that_records_kind_and_chunk_wins_over_the_key(tmp_path):
    stored = {**row(9, "leg-a"), "leg_kind": "fallback", "leg_chunk": 2}
    sink = sink_with(tmp_path, [stored])

    _, body, _ = resolve("--sink", str(sink), "9")

    assert legs_of(body) == [("9", "leg-a", "fallback", 2)]


def test_lane_and_last_take_the_newest_runs_of_that_lane(tmp_path):
    rows = [row(n, "check-intent", hour=n) for n in (1, 2, 3)] + [row(4, "triage", lane="intake-triage", hour=20)]
    sink = sink_with(tmp_path, rows)

    _, body, _ = resolve("--sink", str(sink), "--lane", "pr-verify", "--last", "2")

    assert [r["run_ref"] for r in body["runs"]] == ["3", "2"]


def test_branch_keeps_only_runs_on_that_head_branch(tmp_path):
    rows = [row(1, "check-intent"), {**row(2, "check-intent", hour=11), "head_branch": "feat/x-2"}, {**row(3, "triage", hour=12), "head_branch": None}]
    sink = sink_with(tmp_path, rows)

    code, body, _ = resolve("--sink", str(sink), "--branch", "feat/x")

    assert code == 0
    assert [r["run_ref"] for r in body["runs"]] == ["1"]


def test_a_date_window_with_outcome_and_model_keeps_only_matching_legs(tmp_path):
    rows = [
        row(1, "a", date="2026-10-30"),
        row(2, "a", date="2026-11-01", outcome="error", is_error=True),
        row(2, "b", date="2026-11-01", hour=11),
        row(3, "a", date="2026-11-01", outcome="error", is_error=True, model="model-b"),
        row(4, "a", date="2026-11-03", outcome="error", is_error=True),
    ]
    sink = sink_with(tmp_path, rows)

    _, body, _ = resolve("--sink", str(sink), "--since", "2026-11-01", "--until", "2026-11-02", "--outcome", "error", "--model", "model-a")

    assert legs_of(body) == [("2", "a", "key", None)]


def test_outcome_error_matches_a_row_stored_as_success_with_is_error_true(tmp_path):
    sink = sink_with(tmp_path, [row(5, "a", outcome="success", is_error=True), row(6, "a")])

    _, errors, _ = resolve("--sink", str(sink), "--since", "2026-11-01", "--outcome", "error")
    _, successes, _ = resolve("--sink", str(sink), "--since", "2026-11-01", "--outcome", "success")

    assert [r["run_ref"] for r in errors["runs"]] == ["5"]
    assert [r["run_ref"] for r in successes["runs"]] == ["6"]


def test_a_row_written_before_the_neutral_fields_reads_from_the_github_ones(tmp_path):
    sink = sink_with(tmp_path, [row(7, "check-intent-fallback", neutral=False)])

    _, body, _ = resolve("--sink", str(sink), "7")

    (run,) = body["runs"]
    assert (run["provider"], run["run_ref"], run["run_url"]) == ("github", "7", None)
    assert run["legs"][0]["leg_key"] == "check-intent-fallback"
    assert run["legs"][0]["kind"] == "fallback"


def test_a_pruned_leg_is_kept_with_no_transcript_and_its_stored_tokens(tmp_path):
    sink = sink_with(tmp_path, [{**row(7, "a", transcript=None), "input_tokens": 12, "output_tokens": 34}])

    code, body, _ = resolve("--sink", str(sink), "7")

    leg = body["runs"][0]["legs"][0]
    assert code == 0
    assert leg["transcript"] is None
    assert (leg["input_tokens"], leg["output_tokens"]) == (12, 34)
    assert body["pruned_legs"] == 1


def test_an_unmatched_run_is_listed_and_no_match_at_all_exits_1(tmp_path):
    sink = sink_with(tmp_path, [row(7, "a")])

    code, body, _ = resolve("--sink", str(sink), "7", "99")
    none_code, none_body, _ = resolve("--sink", str(sink), "99")

    assert (code, body["unmatched"]) == (0, ["99"])
    assert (none_code, none_body["runs"], none_body["unmatched"]) == (1, [], ["99"])


def test_run_references_and_filters_do_not_mix(tmp_path):
    sink = sink_with(tmp_path, [row(7, "a")])

    code, _, err = resolve("--sink", str(sink), "7", "--lane", "pr-verify")

    assert code == 2
    assert "either" in err


def test_selection_is_required(tmp_path):
    sink = sink_with(tmp_path, [row(7, "a")])

    assert resolve("--sink", str(sink))[0] == 2


def test_a_relative_or_missing_sink_exits_2(tmp_path):
    assert resolve("--sink", "relative/sink", "7")[0] == 2
    assert resolve("--sink", str(tmp_path / "absent"), "7")[0] == 2


def test_a_bad_date_exits_2(tmp_path):
    sink = sink_with(tmp_path, [row(7, "a")])

    assert resolve("--sink", str(sink), "--since", "11/01/2026")[0] == 2


def test_a_cut_short_last_line_is_not_a_row(tmp_path):
    sink = sink_with(tmp_path, [row(7, "a")])
    with (sink / "metrics.jsonl").open("a", encoding="utf-8") as handle:
        handle.write('{"run_id": 8, "job_id"')

    code, body, _ = resolve("--sink", str(sink), "--since", "2026-01-01")

    assert code == 0
    assert [r["run_ref"] for r in body["runs"]] == ["7"]


def test_no_transcript_text_reaches_the_output(tmp_path):
    sink = sink_with(tmp_path, [row(7, "a")])
    stored = sink / "transcripts/2026-11-01/pr-verify"
    stored.mkdir(parents=True)
    (stored / "7-1-a.json.gz").write_bytes(b"marker-5d21")

    _, body, _ = resolve("--sink", str(sink), "7")

    assert "marker-5d21" not in json.dumps(body)
