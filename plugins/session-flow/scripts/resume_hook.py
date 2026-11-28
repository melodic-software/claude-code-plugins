#!/usr/bin/env python3
"""Inject the resume procedure when a pasted resume prompt starts with its handoff directive.

The UserPromptSubmit hook reads the prompt and looks for one anchored `Read @<absolute path to
<TS>-handoff-<topic>.md>, ...` directive: the prompt's first line, or, when the prompt is a typed
`/goal` paste, its last line (the goal region ends in the directive). The file must exist. On a
match it prints `reference/resume.md` as added context and records the handoff in this session's
focus file through focus.py; a focus file that already names this handoff means the procedure was
injected, so a second paste stays silent. A quoted or indented directive, a non-handoff `Read @`
and an ordinary prompt print nothing.

    resume_hook.py hook UserPromptSubmit   (hook input on stdin; always exits 0)

`resume_context_enabled` gates the injection: the user's own value
(`CLAUDE_PLUGIN_OPTION_RESUME_CONTEXT_ENABLED`) wins when set, else the repository's
`docs/conventions/session-flow.yaml`, else on (docs/contracts/hook-enablement/README.md,
"Precedence"). An invalid value is named on stderr and dropped. The focus-file write follows
`compact_focus_enabled`, which focus.py resolves; with it off no marker is written, so each paste
injects. Logs go to stderr only. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import json
import os
import re
import sys
import traceback
from collections.abc import Mapping
from pathlib import Path

SCRIPT = Path(__file__).resolve()
sys.path.insert(0, str(SCRIPT.parent))
import focus  # noqa: E402
import plugin_paths  # noqa: E402

PLUGIN_ROOT = SCRIPT.parent.parent
RESUME_MD = PLUGIN_ROOT / "reference" / "resume.md"
SETTING = "resume_context_enabled"
OPTION_ENV = "CLAUDE_PLUGIN_OPTION_RESUME_CONTEXT_ENABLED"
REPO_LINE = re.compile(
    rf"^{SETTING}:[ \t]*(?P<value>[^#\r\n]*?)[ \t]*(?:#.*)?$", re.MULTILINE
)
DIRECTIVE = re.compile(r"Read @(?P<head>[^,]+),")
STANDING_THEN = " then @"
HANDOFF_NAME = re.compile(r"\d{8}T\d{6}Z-handoff-[^/\\]+\.md")
LEAD = "session-flow resume procedure for {path} (injected once per session by the resume hook):"


def log(event: str, **fields: object) -> None:
    detail = "".join(f" {key}={value}" for key, value in fields.items())
    print(f"resume_hook: event={event}{detail}", file=sys.stderr)


def _repo_value(project_dir: Path, home: Path) -> str | None:
    root = next(
        (d for d in (project_dir, *project_dir.parents) if (d / ".git").exists()), None
    )
    if root is None or root == home or root in home.parents:
        return None
    try:
        text = (root / focus.REPO_FILE).read_text(encoding="utf-8")
    except OSError:
        return None
    match = REPO_LINE.search(text)
    return match.group("value") if match else None


def enabled(env: Mapping[str, str], project_dir: Path) -> bool:
    layers = (
        ("user_option", lambda: env.get(OPTION_ENV) or None),
        (
            str(focus.REPO_FILE),
            lambda: _repo_value(
                project_dir.resolve(), Path(env.get("HOME") or Path.home()).resolve()
            ),
        ),
    )
    for layer, read in layers:
        value = read()
        if value is None:
            continue
        decided = {"true": True, "false": False}.get(value)
        if decided is not None:
            return decided
        log("invalid_setting", key=SETTING, layer=layer, value=json.dumps(value))
    return True


def handoff_path(prompt: str) -> Path | None:
    lines = [line for line in prompt.splitlines() if line.strip()]
    if not lines:
        return None
    candidate = (
        lines[-1] if lines[0].startswith("/goal ") and len(lines) > 1 else lines[0]
    )
    match = DIRECTIVE.match(candidate)
    if match is None:
        return None
    head = match.group("head")
    path = head.split(STANDING_THEN, 1)[1] if STANDING_THEN in head else head
    path = path.strip()
    if not os.path.isabs(path) or not HANDOFF_NAME.fullmatch(Path(path).name):
        return None
    return Path(path) if Path(path).is_file() else None


def run_hook(stdin: str, env: Mapping[str, str]) -> str:
    try:
        payload = json.loads(stdin)
    except json.JSONDecodeError:
        log("payload_skipped", reason="not_json")
        return ""
    if not isinstance(payload, dict) or not focus.valid_session(
        payload.get("session_id")
    ):
        log("payload_skipped", reason="no_session")
        return ""
    prompt = payload.get("prompt")
    path = handoff_path(prompt) if isinstance(prompt, str) else None
    if path is None:
        return ""
    project = Path(str(env.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or "."))
    if not enabled(env, project):
        return ""
    session = payload["session_id"]
    root = plugin_paths.data_root(env, PLUGIN_ROOT)
    if root is not None:
        marker = focus.section_text("Handoff", str(path))
        held = focus.read_sections(focus.focus_paths(root, session)[0]).get("Handoff")
        if held == marker:
            return ""
        if focus.enabled(env, project):
            focus.update(root, session, {"Handoff": marker})
    log("injected", session=session)
    return LEAD.format(path=path) + "\n\n" + RESUME_MD.read_text(encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if args != ["hook", "UserPromptSubmit"]:
        print("usage: resume_hook.py hook UserPromptSubmit", file=sys.stderr)
        return 2
    try:
        sys.stdout.write(run_hook(sys.stdin.read(), os.environ))
    except Exception:
        log("hook_failed")
        traceback.print_exc(file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
