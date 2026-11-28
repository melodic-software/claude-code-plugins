#!/usr/bin/env python3
"""The per-session focus file the PreCompact hook prints to steer compaction.

One file per Claude Code session, `<plugin data>/focus/<session>.md`: a fixed lead line and up to
five `## ` sections (Goal, Handoff, Task file, Posture, Note), each replaced only by its own flag.
This script is the only code that opens `focus/`.

CLI, every command keyed by `--session <id>`:

    set [--goal TEXT] [--handoff PATH] [--task-file PATH] [--posture orchestrator|off] [--note TEXT]
        [--enabled VALUE]
    clear (--goal | --handoff | --task-file | --posture | --note | --all)
    print
    hook PreCompact|UserPromptSubmit   (hook input on stdin)

The data root is `--data-root` when given (the Bash tool lacks `CLAUDE_PLUGIN_DATA`), else
`plugin_paths.data_root`. `compact_focus_enabled` gates every write and every print to the
PreCompact hook: the user's own value (`--enabled`, else `CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED`)
wins when set, else the repository's `docs/conventions/session-flow.yaml`, else on
(docs/contracts/hook-enablement/README.md, "Precedence"). `print` is read-only and exits 0.
`hook` always exits 0, prints only the focus file on PreCompact, and logs to stderr only.
Exit codes elsewhere: 0 done or skipped, 2 usage, invalid session id or no data root.
Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import sys
import time
import traceback
from collections.abc import Iterator, Mapping
from pathlib import Path

SCRIPT = Path(__file__).resolve()
sys.path.insert(0, str(SCRIPT.parent))
import plugin_paths  # noqa: E402

PLUGIN_ROOT = SCRIPT.parent.parent
FOLDER = "focus"
SESSION_RE = re.compile(r"[A-Za-z0-9_-]{1,128}")
SETTING = "compact_focus_enabled"
OPTION_ENV = "CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED"
REPO_FILE = Path("docs") / "conventions" / "session-flow.yaml"
REPO_LINE = re.compile(rf"^{SETTING}:[ \t]*(?P<value>[^#\r\n]*?)[ \t]*(?:#.*)?$", re.MULTILINE)
CAP = 9000
LOCK_WAIT_SECONDS = 2.0
SWEEP_AGE_SECONDS = 14 * 86400
GOAL_CUT = " (cut; full condition in the handoff file)"
# Pointer: https://code.claude.com/docs/en/goal#clear-a-goal
GOAL_CLEAR_ALIASES = frozenset({"clear", "stop", "off", "reset", "none", "cancel"})
GOAL_DIRECTIVE = re.compile(r"/goal\s+(?P<argument>.*)", re.DOTALL)

LEAD = (
    "Session focus from session-flow. Keep each item below in the summary verbatim. Where it "
    "conflicts with the user's own /compact instructions, the user's instructions win."
)
SECTIONS = ("Goal", "Handoff", "Task file", "Posture", "Note")
RENDER = {
    "Goal": "If this /goal is still active, its condition: {}",
    "Handoff": (
        "This session resumed from {}; its Reminders and Environment to re-establish still apply, "
        "so read them again after compaction."
    ),
    "Task file": "Step-away task file: {}",
    "Posture": "{}",
    "Note": "{}",
}
FLAGS = {"goal": "Goal", "handoff": "Handoff", "task_file": "Task file", "posture": "Posture", "note": "Note"}
POSTURES = {
    "orchestrator": (
        "Step-away orchestrator posture is on: invoke /session-flow:orchestrate if its imperatives are "
        "not in context, and follow the Orchestrator posture section of the away rules."
    ),
    "off": "",
}
PATH_SECTIONS = frozenset({"Handoff", "Task file"})


class FocusError(Exception):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def log(event: str, **fields: object) -> None:
    detail = "".join(f" {key}={value}" for key, value in fields.items())
    print(f"focus: event={event}{detail}", file=sys.stderr)


def valid_session(value: object) -> bool:
    return isinstance(value, str) and SESSION_RE.fullmatch(value) is not None


def resolve_data_root(given: str | None, env: Mapping[str, str]) -> Path:
    if given and not given.startswith("${"):
        return Path(given).expanduser()
    root = plugin_paths.data_root(env, PLUGIN_ROOT)
    if root is None:
        raise FocusError("no_data_root")
    return root


def focus_paths(root: Path, session: str) -> tuple[Path, Path]:
    if not valid_session(session):
        raise FocusError("invalid_session")
    folder = root / FOLDER
    return folder / f"{session}.md", folder / f"{session}.lock"


def _boolean(value: str | None) -> bool | None:
    return {"true": True, "false": False}.get(value) if value is not None else None


def _user_value(given: str | None, env: Mapping[str, str]) -> str | None:
    """The user layer, or None when unset. From a skill's `${user_config.<key>}`, the literal
    placeholder and a value equal to the default `true` both count as unset, since a rendered
    default cannot be told from no choice (reference/config.md, Resolution). Claude Code exports
    `CLAUDE_PLUGIN_OPTION_<KEY>` only for an option the user set
    (docs/contracts/hook-config-delivery/README.md, fact 3)."""
    if given is not None:
        return None if given in ("", "true") or given.startswith("${") else given
    return env.get(OPTION_ENV) or None


def _git_root(start: Path) -> Path | None:
    for directory in (start, *start.parents):
        if (directory / ".git").exists():
            return directory
    return None


def _repo_value(project_dir: Path, home: Path) -> str | None:
    root = _git_root(project_dir)
    if root is None or root == home or root in home.parents:
        return None
    try:
        text = (root / REPO_FILE).read_text(encoding="utf-8")
    except OSError:
        return None
    match = REPO_LINE.search(text)
    return match.group("value") if match else None


def enabled(env: Mapping[str, str], project_dir: Path, user_given: str | None = None) -> bool:
    user = _user_value(user_given, env)
    if user is not None:
        decided = _boolean(user)
        if decided is not None:
            return decided
        log("invalid_setting", key=SETTING, layer="user_option", value=json.dumps(user))
    home = Path(env.get("HOME") or Path.home()).resolve()
    repo = _repo_value(project_dir.resolve(), home)
    if repo is not None:
        decided = _boolean(repo)
        if decided is not None:
            return decided
        log("invalid_setting", key=SETTING, layer=str(REPO_FILE), value=json.dumps(repo))
    return True


def parse(text: str) -> dict[str, str]:
    sections: dict[str, str] = {}
    current: str | None = None
    lines: list[str] = []
    for line in text.splitlines():
        heading = line[3:] if line.startswith("## ") else None
        if heading in SECTIONS:
            if current is not None:
                sections[current] = "\n".join(lines)
            current, lines = heading, []
        elif current is not None:
            lines.append(line)
    if current is not None:
        sections[current] = "\n".join(lines)
    return sections


def _guard(value: str) -> str:
    return "\n".join(f" {line}" if line.startswith("## ") else line for line in value.splitlines())


def _join(sections: Mapping[str, str]) -> str:
    return "\n".join([LEAD, *(f"## {name}\n{sections[name]}" for name in SECTIONS if name in sections)]) + "\n"


def render(sections: Mapping[str, str]) -> str:
    text = _join(sections)
    goal = sections.get("Goal")
    if goal is None or len(text) <= CAP:
        return text
    keep = max(0, len(goal) - (len(text) - CAP) - len(GOAL_CUT))
    return _join({**sections, "Goal": goal[:keep] + GOAL_CUT})


def section_text(name: str, value: str) -> str:
    if name in PATH_SECTIONS:
        value = os.path.abspath(value)
    return RENDER[name].format(_guard(value))


@contextlib.contextmanager
def locked(path: Path) -> Iterator[bool]:
    path.parent.mkdir(parents=True, exist_ok=True)
    with plugin_paths.file_lock(path, LOCK_WAIT_SECONDS) as held:
        yield held


def read_sections(path: Path) -> dict[str, str]:
    try:
        return parse(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def update(root: Path, session: str, changes: Mapping[str, str | None]) -> bool:
    """Apply `changes` (section name to rendered text, or None to remove) under the lock; False
    when the lock wait ran out and nothing was written."""
    path, lock = focus_paths(root, session)
    with locked(lock) as held:
        if not held:
            log("write_skipped", reason="lock_timeout", session=session)
            return False
        sections = read_sections(path)
        for name, text in changes.items():
            if text is None:
                sections.pop(name, None)
            else:
                sections[name] = text
        if sections:
            if not plugin_paths.write_atomic(path, render(sections)):
                log("write_skipped", reason="replace_refused", session=session)
                return False
        else:
            path.unlink(missing_ok=True)
    return True


def sweep(folder: Path, now: float) -> None:
    cutoff = now - SWEEP_AGE_SECONDS
    for entry in folder.glob("*"):
        if entry.suffix not in (".md", ".lock"):
            continue
        try:
            if entry.stat().st_mtime >= cutoff:
                continue
            if entry.suffix == ".lock" and entry.with_suffix(".md").exists():
                continue
            entry.unlink()
        except OSError as error:
            log("sweep_skipped", file=entry.name, error=type(error).__name__)


def focus_text(root: Path, session: str) -> str:
    path, _ = focus_paths(root, session)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return ""
    return text[:CAP]


def cmd_set(args: argparse.Namespace, root: Path) -> int:
    if not enabled(os.environ, Path.cwd(), args.enabled):
        print(f"focus=skipped ({SETTING} is off)")
        return 0
    changes: dict[str, str | None] = {}
    for flag, name in FLAGS.items():
        value = getattr(args, flag)
        if value is not None:
            changes[name] = section_text(name, value) if value.strip() else None
    if not changes:
        raise FocusError("nothing_to_set")
    path, _ = focus_paths(root, args.session)
    if update(root, args.session, changes):
        sweep(path.parent, time.time())
        print(f"focus={path}")
    else:
        print("focus=skipped (lock held)")
    return 0


def cmd_clear(args: argparse.Namespace, root: Path) -> int:
    names = SECTIONS if args.all else [name for flag, name in FLAGS.items() if getattr(args, flag)]
    if not names:
        raise FocusError("nothing_to_clear")
    path, _ = focus_paths(root, args.session)
    if not path.exists():
        return 0
    update(root, args.session, dict.fromkeys(names))
    return 0


def cmd_print(args: argparse.Namespace, root: Path) -> int:
    sys.stdout.write(focus_text(root, args.session))
    return 0


def goal_change(prompt: str) -> str | None | bool:
    """The Goal text a typed prompt sets, None when it clears the goal, False when it is no
    `/goal <argument>` directive."""
    match = GOAL_DIRECTIVE.match(prompt)
    if match is None:
        return False
    argument = match.group("argument").strip()
    if not argument:
        return False
    if argument in GOAL_CLEAR_ALIASES:
        return None
    return section_text("Goal", argument)


def run_hook(event: str, stdin: str, env: Mapping[str, str]) -> str:
    try:
        payload = json.loads(stdin)
    except json.JSONDecodeError:
        log("payload_skipped", reason="not_json", hook=event)
        return ""
    if not isinstance(payload, dict) or not valid_session(payload.get("session_id")):
        log("payload_skipped", reason="no_session", hook=event)
        return ""
    session = payload["session_id"]
    root = plugin_paths.data_root(env, PLUGIN_ROOT)
    if root is None:
        return ""
    project = Path(str(env.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or "."))
    if event == "UserPromptSubmit":
        prompt = payload.get("prompt")
        change = goal_change(prompt) if isinstance(prompt, str) else False
        if change is False:
            return ""
        if change is None and not (root / FOLDER / f"{session}.md").exists():
            return ""
        if enabled(env, project):
            update(root, session, {"Goal": change})
        return ""
    text = focus_text(root, session)
    return text if text and enabled(env, project) else ""


def cmd_hook(args: argparse.Namespace) -> int:
    try:
        sys.stdout.write(run_hook(args.event, sys.stdin.read(), os.environ))
    except Exception:
        log("hook_failed", hook=args.event)
        traceback.print_exc(file=sys.stderr)
    return 0


def posture_text(value: str) -> str:
    if value not in POSTURES:
        raise argparse.ArgumentTypeError(f"takes {' or '.join(POSTURES)}, not {value!r}")
    return POSTURES[value]


def parser() -> argparse.ArgumentParser:
    top = argparse.ArgumentParser(prog="focus.py", description=__doc__.split("\n\n")[0])
    commands = top.add_subparsers(dest="command", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--session", required=True)
    common.add_argument("--data-root")
    set_cmd = commands.add_parser("set", parents=[common], help="replace the named sections")
    set_cmd.add_argument("--goal")
    set_cmd.add_argument("--handoff")
    set_cmd.add_argument("--task-file")
    set_cmd.add_argument("--posture", type=posture_text, help="the posture away.py start printed; off removes it")
    set_cmd.add_argument("--note")
    set_cmd.add_argument("--enabled", help=f"the user's {SETTING} value; an unexpanded placeholder is unset")
    clear_cmd = commands.add_parser("clear", parents=[common], help="remove the named sections")
    for flag in ("--goal", "--handoff", "--task-file", "--posture", "--note", "--all"):
        clear_cmd.add_argument(flag, action="store_true")
    commands.add_parser("print", parents=[common], help="print the focus file, cut to the cap")
    hook_cmd = commands.add_parser("hook", help="hook entry; payload on stdin; always exits 0")
    hook_cmd.add_argument("event", choices=["PreCompact", "UserPromptSubmit"])
    return top


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    if args.command == "hook":
        return cmd_hook(args)
    try:
        root = resolve_data_root(args.data_root, os.environ)
        if not valid_session(args.session):
            raise FocusError("invalid_session")
        return {"set": cmd_set, "clear": cmd_clear, "print": cmd_print}[args.command](args, root)
    except FocusError as error:
        if args.command == "print":
            return 0
        log("usage_error", reason=error.reason, command=args.command)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
