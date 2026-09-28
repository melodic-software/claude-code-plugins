#!/usr/bin/env python3
"""Fail closed when a CI review skill returns no body (#4306).

An empty Skill result is ``Execute skill: review:code-review`` (or
``review:security-review``) and nothing else. The body never loaded. A later
hand review of the diff is a failed lane, not a green review.

Subcommands:

  classify-tool-result   stdin is one tool-result JSON object. Exit 3 when
                         the content is only that empty Execute skill line
                         for a lane skill, else 0.
  classify-posted        stdin is one posted comment or review body. Exit 3
                         when it is the fail-closed marker for LANE_SKILL or
                         the empty-invocation confession, else 0.
  check-lane             read the lane bot's reviews for EVENT_HEAD_SHA and
                         its issue comments updated during this Actions run.
                         Exit 3 when any body classifies as degrade, 0 when
                         none do, 2 when the read cannot be done.
                         FAIL_CLOSED_BODIES (a JSON array of strings) skips
                         the GitHub read so tests stay offline.
  hook                   stdin is a Claude Code hook payload. On a lane
                         session whose skill body never loaded, print
                         ``{"continue": false, ...}`` and exit 0. Otherwise
                         print nothing and exit 0.

Exit 3 is the failed-lane verdict. Exit 0 is not a review of the diff.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

MARKER_PREFIX = "review-lane-fail-closed:"
LANE_SKILLS = ("review:code-review", "review:security-review")
EMPTY_EXECUTE = re.compile(r"Execute skill:\s*(\S+)\s*\Z")
HAND_PHRASES = (
    "fell back",
    "performing the review directly",
    "manual fallback",
    "reviewed the diff directly",
)


def lane_short(skill: str) -> str:
    return skill.split(":", 1)[1] if skill.startswith("review:") else skill


def content_text(payload: object) -> str:
    if isinstance(payload, str):
        return payload
    if isinstance(payload, list):
        parts: list[str] = []
        for block in payload:
            if isinstance(block, str):
                parts.append(block)
            elif isinstance(block, dict):
                text = block.get("text", block.get("content", ""))
                parts.append(text if isinstance(text, str) else "")
        return "\n".join(parts)
    if isinstance(payload, dict):
        if "content" in payload:
            return content_text(payload.get("content"))
        if "error" in payload:
            return content_text(payload.get("error"))
    return ""


def empty_lane_skill(text: str) -> str | None:
    match = EMPTY_EXECUTE.fullmatch(text.strip())
    if match is None:
        return None
    skill = match.group(1)
    if skill in LANE_SKILLS:
        return skill
    return None


def classify_tool_result(payload: dict) -> str:
    text = content_text(payload.get("content", payload.get("error", "")))
    if empty_lane_skill(text):
        return "degrade"
    return "ok"


def marker_line(text: str, lane_skill: str) -> bool:
    want = f"{MARKER_PREFIX} {lane_skill}"
    for line in text.splitlines():
        cleaned = line.strip().strip("`").strip()
        if cleaned == want:
            return True
    return False


def classify_posted(text: str, lane_skill: str) -> str:
    if marker_line(text, lane_skill):
        return "degrade"
    full = f"review:{lane_skill}"
    if full not in text:
        return "ok"
    lower = text.lower()
    has_execute = "Execute skill:" in text
    has_empty = "no further content" in lower
    has_errored = "skill invocation errored" in lower
    has_hand = any(phrase in lower for phrase in HAND_PHRASES)
    if has_execute and has_empty and (has_errored or has_hand):
        return "degrade"
    if has_errored and has_hand:
        return "degrade"
    return "ok"


def stop_payload(skill: str) -> dict[str, object]:
    short = lane_short(skill)
    reason = (
        f"{MARKER_PREFIX} {short}\n"
        "The skill body never loaded. Do not review the diff yourself."
    )
    return {"continue": False, "stopReason": reason}


def read_transcript(path: str) -> str:
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as handle:
            head = handle.read(65536)
            tail = b""
            if size > 65536:
                handle.seek(max(0, size - 524288))
                tail = handle.read()
    except OSError:
        return ""
    return b"\n".join((head, tail)).decode("utf-8", errors="replace")


def occurrence_is_empty(text: str, at: int, skill: str) -> bool:
    """True when this Execute skill occurrence has no body after the name."""
    rest = text[at + len(f"Execute skill: {skill}") :]
    if rest.startswith("\\n") or rest.startswith("\n"):
        body = rest[2:] if rest.startswith("\\n") else rest[1:]
        return body.strip(" \t\r\"',}") == ""
    if rest.startswith((" ", "\t")):
        return rest.splitlines()[0].strip() == ""
    return rest[:1] in ("", '"', "'", ",", "}")


def failed_lane_skill(text: str) -> str | None:
    """A lane skill whose latest empty Execute line is after any Launching line."""
    failed: str | None = None
    failed_at = -1
    for skill in LANE_SKILLS:
        needle = f"Execute skill: {skill}"
        execute_at = text.rfind(needle)
        if execute_at < 0 or not occurrence_is_empty(text, execute_at, skill):
            continue
        launch_at = text.rfind(f"Launching skill: {skill}")
        if launch_at > execute_at:
            continue
        if execute_at >= failed_at:
            failed = skill
            failed_at = execute_at
    return failed


def lane_prompt(text: str) -> bool:
    return (
        "Invoke /review:code-review" in text or "Invoke /review:security-review" in text
    )


def hook_decision(payload: dict) -> dict[str, object] | None:
    event = str(payload.get("hook_event_name") or "")
    if event == "PostToolUseFailure" and payload.get("tool_name") == "Skill":
        error = content_text(payload.get("error", ""))
        skill = empty_lane_skill(error)
        if skill is None:
            tool_input = payload.get("tool_input")
            if isinstance(tool_input, dict):
                named = str(tool_input.get("skill") or "")
                if named in LANE_SKILLS and empty_lane_skill(error or f"Execute skill: {named}"):
                    skill = named
        if skill:
            return stop_payload(skill)
        return None

    transcript = ""
    path = payload.get("transcript_path")
    if isinstance(path, str) and path:
        transcript = read_transcript(os.path.expanduser(path))

    if event == "Stop":
        message = payload.get("last_assistant_message")
        if isinstance(message, str):
            for skill in LANE_SKILLS:
                if classify_posted(message, lane_short(skill)) == "degrade":
                    return stop_payload(skill)
        if lane_prompt(transcript):
            skill = failed_lane_skill(transcript)
            if skill:
                return stop_payload(skill)
        return None

    if event == "PreToolUse" and lane_prompt(transcript):
        skill = failed_lane_skill(transcript)
        if skill:
            return stop_payload(skill)
    return None


def emit_verdict(verdict: str) -> int:
    if verdict == "degrade":
        print("degrade")
        return 3
    print("ok")
    return 0


def load_stdin_json() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        print("fail-closed-skill-invocation: empty JSON on stdin", file=sys.stderr)
        raise SystemExit(2)
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"fail-closed-skill-invocation: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc
    if not isinstance(payload, dict):
        print("fail-closed-skill-invocation: JSON value must be an object", file=sys.stderr)
        raise SystemExit(2)
    return payload


def gh_items(path: str) -> list[dict]:
    proc = subprocess.run(
        ["gh", "api", "--paginate", "--jq", ".[]", path],
        check=False,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "gh api failed").strip()
        print(f"fail-closed-skill-invocation: {detail}", file=sys.stderr)
        raise SystemExit(2)
    items: list[dict] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        item = json.loads(line)
        if isinstance(item, dict):
            items.append(item)
    return items


def fetch_bodies() -> list[str]:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    pr = os.environ.get("PR_NUMBER", "")
    sha = os.environ.get("EVENT_HEAD_SHA", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if not repo or not pr or not sha or not run_id:
        print(
            "fail-closed-skill-invocation: GITHUB_REPOSITORY, PR_NUMBER, "
            "EVENT_HEAD_SHA, and GITHUB_RUN_ID are required",
            file=sys.stderr,
        )
        raise SystemExit(2)
    started_proc = subprocess.run(
        ["gh", "api", f"repos/{repo}/actions/runs/{run_id}", "--jq", ".run_started_at"],
        check=False,
        capture_output=True,
        text=True,
    )
    if started_proc.returncode != 0:
        detail = (started_proc.stderr or "could not read the run start").strip()
        print(f"fail-closed-skill-invocation: {detail}", file=sys.stderr)
        raise SystemExit(2)
    started = started_proc.stdout.strip()
    login = os.environ.get("REVIEWER_LOGIN", "claude[bot]")
    bodies: list[str] = []
    for review in gh_items(f"repos/{repo}/pulls/{pr}/reviews"):
        user = review.get("user") if isinstance(review.get("user"), dict) else {}
        if user.get("login") != login:
            continue
        if review.get("commit_id") != sha:
            continue
        bodies.append(str(review.get("body") or ""))
    for comment in gh_items(f"repos/{repo}/issues/{pr}/comments"):
        user = comment.get("user") if isinstance(comment.get("user"), dict) else {}
        if user.get("login") != login:
            continue
        updated = str(comment.get("updated_at") or "")
        if updated < started:
            continue
        bodies.append(str(comment.get("body") or ""))
    return bodies


def check_lane() -> int:
    lane = os.environ.get("LANE_SKILL", "")
    if lane not in ("code-review", "security-review"):
        print(
            "fail-closed-skill-invocation: LANE_SKILL must be code-review or security-review",
            file=sys.stderr,
        )
        return 2
    raw_bodies = os.environ.get("FAIL_CLOSED_BODIES")
    if raw_bodies is not None:
        try:
            parsed = json.loads(raw_bodies)
        except json.JSONDecodeError as exc:
            print(f"fail-closed-skill-invocation: {exc}", file=sys.stderr)
            return 2
        if not isinstance(parsed, list) or not all(isinstance(item, str) for item in parsed):
            print(
                "fail-closed-skill-invocation: FAIL_CLOSED_BODIES must be a JSON array of strings",
                file=sys.stderr,
            )
            return 2
        bodies = parsed
    else:
        bodies = fetch_bodies()
    for body in bodies:
        if classify_posted(body, lane) == "degrade":
            print(
                f"fail-closed-skill-invocation: {lane} posted an empty skill "
                "invocation or a hand review. The lane fails closed (#4306).",
                file=sys.stderr,
            )
            return 3
    print(f"fail-closed-skill-invocation: {lane} posted no empty-invocation confession")
    return 0


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else ""
    if command in ("-h", "--help"):
        print(__doc__)
        return 0
    if command == "classify-tool-result":
        return emit_verdict(classify_tool_result(load_stdin_json()))
    if command == "classify-posted":
        lane = os.environ.get("LANE_SKILL", "")
        if lane not in ("code-review", "security-review"):
            print(
                "fail-closed-skill-invocation: LANE_SKILL must be code-review or security-review",
                file=sys.stderr,
            )
            return 2
        return emit_verdict(classify_posted(sys.stdin.read(), lane))
    if command == "check-lane":
        return check_lane()
    if command == "hook":
        decision = hook_decision(load_stdin_json())
        if decision is not None:
            json.dump(decision, sys.stdout)
            sys.stdout.write("\n")
        return 0
    print(
        "fail-closed-skill-invocation: expected classify-tool-result, "
        "classify-posted, check-lane, or hook",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
