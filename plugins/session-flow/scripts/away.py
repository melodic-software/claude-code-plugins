#!/usr/bin/env python3
"""Step-away state, return report, report check and hook entry for session-flow.

One absence is keyed by the Claude Code session id and lives in `<plugin data>/away/<session>/`:
`state.json` (replaced whole through a temp file), `refused.jsonl` (append-only, one refused
action per line with its `R<n>` id) and a `lock` file that serializes every read-modify-write.

CLI, every command keyed by `--session <id>`:

    start --kind bed|break|trip|until [--until ISO] [--scope TEXT] [--task-file PATH]
    status | refresh | check | end | deliver
    hook PermissionRequest|Elicitation|Stop|UserPromptSubmit   (hook input on stdin)

Settings come from `--setting key=value`, else `CLAUDE_PLUGIN_OPTION_<KEY>`, else the defaults
below. The data root is `CLAUDE_PLUGIN_DATA`, else derived from `--plugin-root` for a
marketplace install. `hook` always exits 0 and prints nothing unless the session is away; every
hook decision refuses, declines, records or holds the run, and none grants a permission.
Exit codes elsewhere: 0 done, 1 refused move or failed check, 2 usage or no data root.
Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable, Iterator, Mapping
from datetime import date, datetime, timedelta, timezone
from enum import Enum
from pathlib import Path
from typing import NamedTuple, TypeVar

try:
    import fcntl

    def _try_lock(fd: int) -> None:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def _unlock(fd: int) -> None:
        fcntl.flock(fd, fcntl.LOCK_UN)

except ImportError:
    import msvcrt

    def _try_lock(fd: int) -> None:
        os.lseek(fd, 0, os.SEEK_SET)
        msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)

    def _unlock(fd: int) -> None:
        os.lseek(fd, 0, os.SEEK_SET)
        msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)


SCRIPT = Path(__file__).resolve()
DEFAULT_PLUGIN_ROOT = SCRIPT.parent.parent
RULES = Path("skills") / "step-away" / "reference" / "rules.md"
SESSION_RE = re.compile(r"[A-Za-z0-9_-]{1,128}")
LOCK_WAIT_SECONDS = 10.0
GIT_TIMEOUT_SECONDS = 10
DETAIL_LIMIT = 300
FILES_LIMIT = 200
LIST_LIMIT = 10

HEADINGS = ("Needs you", "Decided while you were away", "Waiting on me", "Done", "Found", "Additional notes")
BLOCKS = {"refused": "Refused actions", "externals": "External actions", "files": "Files written"}
KINDS = ("bed", "break", "trip", "until")
EVENT_LABELS = {"PermissionRequest": "permission prompt", "Elicitation": "MCP question", "AutoModeDenial": "auto mode denial"}


class Status(str, Enum):
    ACTIVE = "active"
    ENDED = "ended"
    DELIVERED = "delivered"


MOVES: dict[Status | None, frozenset[Status]] = {
    None: frozenset({Status.ACTIVE}),
    Status.ACTIVE: frozenset({Status.ACTIVE, Status.ENDED}),
    Status.ENDED: frozenset({Status.ACTIVE, Status.ENDED, Status.DELIVERED}),
    Status.DELIVERED: frozenset({Status.ACTIVE, Status.DELIVERED}),
}

SETTING_DEFAULTS = {
    "away_night_start": "21:00",
    "away_report_by_workday": "09:00",
    "away_report_by_day_off": "10:00",
    "away_days_off": "Sat,Sun",
    "away_watched_folders": "",
}
DAY_NAMES = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
CLOCK_RE = re.compile(r"([01]?\d|2[0-3]):([0-5]\d)")

MANAGED_SETTINGS = (
    Path("/Library/Application Support/ClaudeCode/managed-settings.json"),
    Path("C:/Program Files/ClaudeCode/managed-settings.json"),
    Path("/etc/claude-code/managed-settings.json"),
)

GH_WRITE_RE = re.compile(
    r"\bgh\s+(?:pr|issue|release|repo|label|workflow|run|secret|variable|gist|project|ruleset|cache)\s+"
    r"(?:create|edit|merge|close|reopen|comment|delete|review|ready|lock|unlock|transfer|pin|unpin|rename|"
    r"archive|unarchive|fork|set|enable|disable|cancel|rerun|upload|develop|add|remove|sync|item-\w+)\b"
)
GH_API_WRITE_RE = re.compile(
    r"\bgh\s+api\b(?=.*?\s(?:(?:-X|--method)[\s=]*['\"]?(?:POST|PUT|PATCH|DELETE)\b|-f\b|-F\b|--field\b|"
    r"--raw-field\b|--input\b))",
    re.I | re.S,
)
GIT_PUSH_RE = re.compile(r"\bgit(?:\s+-[Cc]\s+\S+|\s+-{1,2}[\w.-]+(?:=\S+)?)*\s+push\b")
CLOUD_CLI_RE = re.compile(
    r"(?:^|[\s;&|(`])(?:az|aws|gcloud|gsutil|bq|pulumi|terraform|tofu|kubectl|helm|doctl|flyctl|wrangler|"
    r"vercel|netlify|heroku|firebase|oci|ibmcloud)\s"
)
HTTP_WRITE_RE = re.compile(
    r"\bcurl\b(?=.*?\s(?:(?:-X|--request)[\s=]*['\"]?(?:POST|PUT|PATCH|DELETE)\b|-d\b|--data\S*|-F\b|--form\b|"
    r"-T\b|--upload-file\b|--json\b))"
    r"|\bwget\b(?=.*?\s--(?:post-data|post-file|method)\b)"
    r"|\b(?:Invoke-WebRequest|Invoke-RestMethod|iwr|irm)\b(?=.*?-Method\s+['\"]?(?:Post|Put|Patch|Delete)\b)"
    r"|\bhttps?\s+(?:POST|PUT|PATCH|DELETE)\b",
    re.I | re.S,
)
EXTERNAL_PATTERNS = (GH_WRITE_RE, GH_API_WRITE_RE, GIT_PUSH_RE, CLOUD_CLI_RE, HTTP_WRITE_RE)

TASK_RE = re.compile(r"^\s*[-*+]\s+\[([ xX])\]\s+(.*\S)\s*$")
PARKED_RE = re.compile(r"\bparked\b", re.I)
ITEM_RE = re.compile(r"^[-*+]\s")
OPTIONS_RE = re.compile(r"\boptions?\b\W{0,3}:", re.I)
RECOMMENDATION_RE = re.compile(r"\brecommendation\b\W{0,3}:", re.I)

T = TypeVar("T")


class AwayError(Exception):
    """A CLI request this absence cannot carry out; the message is printed for the caller."""



def resolve_settings(env: Mapping[str, str], pairs: list[str]) -> dict[str, str]:
    settings = dict(SETTING_DEFAULTS)
    for key in SETTING_DEFAULTS:
        value = env.get(f"CLAUDE_PLUGIN_OPTION_{key.upper()}", "")
        if _given(value):
            settings[key] = value
    for pair in pairs:
        key, sep, value = pair.partition("=")
        if not sep or key not in SETTING_DEFAULTS:
            raise AwayError(f"--setting takes key=value with a key from: {', '.join(SETTING_DEFAULTS)}")
        if _given(value):
            settings[key] = value
    return settings


def _given(value: str) -> bool:
    """An empty value, or a placeholder the host left unsubstituted, means unset."""
    return bool(value.strip()) and not value.startswith("${")


def parse_clock(value: str, key: str = "time") -> timedelta:
    match = CLOCK_RE.fullmatch(value.strip())
    if not match:
        raise AwayError(f"{key} must be HH:MM, got {value!r}")
    return timedelta(hours=int(match[1]), minutes=int(match[2]))


def parse_days(value: str) -> frozenset[int]:
    days = set()
    for name in filter(None, (part.strip().lower()[:3] for part in value.split(","))):
        if name not in DAY_NAMES:
            raise AwayError(f"away_days_off takes day names such as Sat,Sun, got {value!r}")
        days.add(DAY_NAMES.index(name))
    return frozenset(days)


def _report_by_on(day: date, settings: Mapping[str, str], days_off: frozenset[int]) -> datetime:
    key = "away_report_by_day_off" if day.weekday() in days_off else "away_report_by_workday"
    return datetime.combine(day, datetime.min.time()) + parse_clock(settings[key], key)


def next_report_by(now: datetime, settings: Mapping[str, str]) -> datetime | None:
    """The next report-by time when `now` is inside the night window, else None.

    Works on naive local times. The window runs from night_start to the next report-by time,
    which is the day-off time on a day off and the workday time otherwise.
    """
    days_off = parse_days(settings["away_days_off"])
    due = _report_by_on(now.date(), settings, days_off)
    if due <= now:
        due = _report_by_on(now.date() + timedelta(days=1), settings, days_off)
    opens = datetime.combine(due.date(), datetime.min.time()) + parse_clock(settings["away_night_start"])
    if opens >= due:
        opens -= timedelta(days=1)
    return due if opens <= now else None


def parse_instant(value: str) -> datetime:
    """An ISO time as an aware datetime; a naive one is taken as machine local time."""
    parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.astimezone()



def data_root(env: Mapping[str, str], plugin_root: str | None) -> Path | None:
    """`CLAUDE_PLUGIN_DATA`, else `<plugins>/data/<name@marketplace>` from a cache install root.

    A skill-frontmatter hook gets only `${CLAUDE_PLUGIN_ROOT}` substituted, and a Bash-tool
    command gets neither variable, so the root is rebuilt from the install layout
    `<plugins>/cache/<marketplace>/<name>/<version>`. Any other layout yields None.
    """
    configured = env.get("CLAUDE_PLUGIN_DATA", "")
    if _given(configured):
        return Path(configured)
    if not plugin_root:
        return None
    parts = Path(plugin_root).parts
    for index in range(1, len(parts) - 2):
        if parts[index].casefold() == "cache" and parts[index - 1].casefold() == "plugins":
            plugin_id = re.sub(r"[^A-Za-z0-9_-]", "-", f"{parts[index + 2]}@{parts[index + 1]}")
            return Path(*parts[:index]) / "data" / plugin_id
    return None


class Paths(NamedTuple):
    dir: Path
    state: Path
    refused: Path
    lock: Path
    plugin_root: Path

    @property
    def rules(self) -> Path:
        return self.plugin_root / RULES


def session_paths(root: Path, session: str, plugin_root: Path) -> Paths:
    directory = root / "away" / session
    return Paths(directory, directory / "state.json", directory / "refused.jsonl", directory / "lock", plugin_root)


def valid_session(value: object) -> bool:
    return isinstance(value, str) and SESSION_RE.fullmatch(value) is not None


@contextlib.contextmanager
def locked(path: Path) -> Iterator[None]:
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        deadline = time.monotonic() + LOCK_WAIT_SECONDS
        while True:
            try:
                _try_lock(fd)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.01)
        try:
            yield
        finally:
            _unlock(fd)
    finally:
        os.close(fd)


def write_atomic(path: Path, text: str) -> None:
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", suffix=".tmp", delete=False
    )
    try:
        with handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(handle.name, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(handle.name)
        raise


def read_state(paths: Paths) -> dict | None:
    try:
        state = json.loads(paths.state.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    return state if isinstance(state, dict) else None


def update_state(paths: Paths, change: Callable[[dict], T]) -> T:
    with locked(paths.lock):
        state = read_state(paths)
        if state is None:
            raise AwayError("no away state for this session")
        result = change(state)
        write_atomic(paths.state, json.dumps(state, indent=2) + "\n")
        return result


def status_of(state: Mapping | None) -> Status | None:
    return Status(state["status"]) if state else None


def move(state: Mapping | None, target: Status) -> None:
    current = status_of(state)
    if target not in MOVES[current]:
        raise AwayError(f"cannot move an absence from {current.value if current else 'none'} to {target.value}")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()



def read_refused(paths: Paths) -> list[dict]:
    try:
        lines = paths.refused.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []
    entries = []
    for line in lines:
        with contextlib.suppress(ValueError):
            entry = json.loads(line)
            if isinstance(entry, dict) and isinstance(entry.get("id"), str):
                entries.append(entry)
    return entries


def _id_number(entry: Mapping) -> int:
    match = re.fullmatch(r"R(\d+)", str(entry.get("id", "")))
    return int(match[1]) if match else 0


def append_refusals(paths: Paths, entries: list[dict], unless_seen: str | None = None) -> list[str]:
    """Append each entry with the next `R<n>` id, under the lock so parallel hooks never share one.

    With `unless_seen`, an entry whose value for that key is already recorded is skipped.
    """
    with locked(paths.lock):
        existing = read_refused(paths)
        seen = {entry.get(unless_seen) for entry in existing} if unless_seen else set()
        number = max((_id_number(entry) for entry in existing), default=0)
        ids, lines = [], []
        for entry in entries:
            if unless_seen and entry.get(unless_seen) in seen:
                continue
            number += 1
            record = {"id": f"R{number}", "ts": now_iso(), **entry}
            ids.append(record["id"])
            lines.append(json.dumps(record) + "\n")
        if lines:
            with paths.refused.open("a", encoding="utf-8") as handle:
                handle.write("".join(lines))
                handle.flush()
                os.fsync(handle.fileno())
        return ids


_REDACTOR = None


def redact(text: str) -> str:
    global _REDACTOR
    if _REDACTOR is None:
        sys.path.insert(0, str(SCRIPT.parent))
        import redact as redact_module

        _REDACTOR = redact_module.load_redactor()
    excerpt = _REDACTOR.excerpt(" ".join(text.split()), DETAIL_LIMIT)
    return excerpt if excerpt is not None else "(withheld: the redaction rules did not load)"


def describe_tool(name: object, tool_input: object) -> str:
    if isinstance(tool_input, dict) and isinstance(tool_input.get("command"), str):
        return redact(tool_input["command"])
    return redact(f"{name} {json.dumps(tool_input, sort_keys=True)}")



def marker(name: str, edge: str) -> str:
    return f"<!-- away:{name}:{edge} -->"


def render_block(name: str, lines: list[str]) -> str:
    body = "\n".join(lines) if lines else "None."
    return f"{marker(name, 'begin')}\n### {BLOCKS[name]}\n\n{body}\n{marker(name, 'end')}"


def skeleton(state: Mapping) -> str:
    header = (
        "# Away report\n\n"
        f"- Started: {state['started']}\n"
        f"- Report by: {state['report_by'] or 'until you are back'}\n"
        f"- Kind: {state['kind']}\n"
        f"- Scope: {state.get('scope') or 'not stated'}\n"
        f"- Task file: {state.get('task_file') or 'none'}\n"
    )
    sections = []
    for heading in HEADINGS:
        if heading == "Found":
            body = "\n\n".join(render_block(name, []) for name in BLOCKS)
        else:
            body = "None."
        sections.append(f"## {heading}\n\n{body}\n")
    return header + "\n" + "\n".join(sections)


def replace_block(text: str, name: str, rendered: str) -> str:
    begin, end = marker(name, "begin"), marker(name, "end")
    start = text.find(begin)
    stop = text.find(end, start + 1) if start >= 0 else -1
    if start >= 0 and stop >= 0:
        return text[:start] + rendered + text[stop + len(end) :]
    anchor = text.find("\n## Additional notes")
    if anchor >= 0:
        return text[: anchor + 1] + rendered + "\n\n" + text[anchor + 1 :]
    return text.rstrip("\n") + "\n\n" + rendered + "\n"


def digest(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return ""


def _git(*args: str) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(
            ["git", *args], capture_output=True, text=True, timeout=GIT_TIMEOUT_SECONDS, check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def git_toplevel(cwd: Path) -> Path | None:
    result = _git("-C", str(cwd), "rev-parse", "--show-toplevel")
    if result is None or result.returncode != 0 or not result.stdout.strip():
        return None
    return Path(result.stdout.strip())


def choose_report_path(launch_root: Path | None, state_dir: Path, session: str) -> Path:
    if launch_root is not None:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        relative = f".work/away/{stamp}-{session[:8]}.md"
        ignored = _git("-C", str(launch_root), "check-ignore", "-q", "--", relative)
        if ignored is not None and ignored.returncode == 0:
            return launch_root / relative
    return state_dir / "report.md"



def _setting(path: Path, *keys: str) -> object:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def launch_warnings(config_dir: Path, project: Path) -> list[str]:
    user = config_dir / "settings.json"
    local, shared = project / ".claude" / "settings.local.json", project / ".claude" / "settings.json"
    warnings = []
    # A project or local file that sets the key turns the feature off when managed and user leave it
    # unset: https://code.claude.com/docs/en/settings-reference#autocontinueatusagelimit
    off = None
    for path in (*MANAGED_SETTINGS, user):
        value = _setting(path, "autoContinueAtUsageLimit")
        if value is not None:
            off = path if value is False else None
            break
    else:
        off = next((p for p in (local, shared) if _setting(p, "autoContinueAtUsageLimit") is not None), None)
    if off is not None:
        warnings.append(
            f"autoContinueAtUsageLimit is off ({off}): a usage limit ends the run instead of waiting for the reset."
        )
    for path in (*MANAGED_SETTINGS, local, shared, user):
        value = _setting(path, "sandbox", "enabled")
        if value is not None:
            if value is True:
                warnings.append(
                    f"sandboxing is on ({path}): a sandboxed command's network prompt cannot be refused by a "
                    "hook and will wait for the person."
                )
            break
    warnings.append("keep the machine awake: after a long sleep the usage-limit resume waits for Enter.")
    return warnings



def config_dir(env: Mapping[str, str]) -> Path:
    configured = env.get("CLAUDE_CONFIG_DIR", "")
    return Path(configured) if configured else Path.home() / ".claude"


def watched_folders(settings: Mapping[str, str]) -> list[str]:
    folders = [part.strip() for part in settings["away_watched_folders"].split(",") if part.strip()]
    return [str(Path(folder).expanduser()) for folder in folders] or [str(Path.home())]


def cmd_start(args: argparse.Namespace, paths: Paths) -> int:
    settings = resolve_settings(os.environ, args.setting)
    if args.kind == "until" and not args.until:
        raise AwayError("--kind until needs --until <ISO time>")
    if args.until:
        report_by = parse_instant(args.until)
    elif args.kind == "trip":
        report_by = None
    else:
        due = next_report_by(datetime.now(), settings)
        report_by = due.astimezone() if due else None
    cwd = Path.cwd()
    task_file = str((cwd / args.task_file).resolve()) if args.task_file else None
    paths.dir.mkdir(parents=True, exist_ok=True)

    def change(state: dict) -> dict:
        move(state or None, Status.ACTIVE)
        if status_of(state or None) is not Status.ACTIVE:
            launch_root = git_toplevel(cwd)
            state.clear()
            state.update(
                session_id=args.session,
                status=Status.ACTIVE.value,
                started=datetime.now().astimezone().isoformat(),
                report_path=str(choose_report_path(launch_root, paths.dir, args.session)),
                launch_root=str(launch_root) if launch_root else None,
                transcript_path=None,
                last_block_digest=None,
                mode_warned=False,
                scope=None,
                task_file=None,
            )
        state.update(kind=args.kind, report_by=report_by.isoformat() if report_by else None)
        state["watched"] = watched_folders(settings)
        if args.scope:
            state["scope"] = args.scope
        if task_file:
            state["task_file"] = task_file
        return state

    with locked(paths.lock):
        state = change(read_state(paths) or {})
        report = Path(state["report_path"])
        report.parent.mkdir(parents=True, exist_ok=True)
        if not report.exists():
            write_atomic(report, skeleton(state))
        write_atomic(paths.state, json.dumps(state, indent=2) + "\n")
    print(f"status={state['status']}")
    print(f"report={state['report_path']}")
    print(f"report_by={state['report_by'] or 'none'}")
    project = Path(state["launch_root"]) if state.get("launch_root") else cwd
    for warning in launch_warnings(config_dir(os.environ), project):
        print(f"warning={warning}")
    return 0


def require_state(paths: Paths) -> dict:
    state = read_state(paths)
    if state is None:
        raise AwayError("no away state for this session; run start first")
    return state


def cmd_status(args: argparse.Namespace, paths: Paths) -> int:
    state = read_state(paths) or {"session_id": args.session, "status": "none"}
    if state["status"] != "none":
        state["refused_count"] = len(read_refused(paths))
    print(json.dumps(state, indent=2))
    return 0


class Check(NamedTuple):
    criteria: dict[str, bool]
    open_items: list[str]

    @property
    def passed(self) -> bool:
        return all(self.criteria.values()) and not self.open_items


def _section(lines: list[str], heading: str) -> list[str] | None:
    try:
        start = lines.index(f"## {heading}")
    except ValueError:
        return None
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    return lines[start + 1 : end]


def _needs_you_ok(lines: list[str]) -> bool:
    section = _section(lines, "Needs you")
    if section is None:
        return False
    items: list[list[str]] = []
    for line in section:
        if ITEM_RE.match(line):
            items.append([line])
        elif items:
            items[-1].append(line)
    return all(OPTIONS_RE.search(" ".join(item)) and RECOMMENDATION_RE.search(" ".join(item)) for item in items)


def _since(state: Mapping, entries: list[dict]) -> list[dict]:
    started = parse_instant(state["started"])
    return [entry for entry in entries if _instant_or_none(entry.get("ts")) and parse_instant(entry["ts"]) >= started]


def _instant_or_none(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return parse_instant(value)
    except ValueError:
        return None


def _blocks_fresh(text: str, refused: list[dict]) -> bool:
    for name in BLOCKS:
        if text.count(marker(name, "begin")) != 1 or text.count(marker(name, "end")) != 1:
            return False
    listed = text.split(marker("refused", "begin"), 1)[1].split(marker("refused", "end"), 1)[0]
    return all(f"- {entry['id']} " in listed for entry in refused)


def open_tasks(task_file: str | None) -> list[str]:
    if not task_file:
        return []
    try:
        lines = Path(task_file).read_text(encoding="utf-8").splitlines()
    except OSError:
        return [f"(task file not readable: {task_file})"]
    open_items = []
    for line in lines:
        match = TASK_RE.match(line)
        if match and match[1] == " " and not PARKED_RE.search(match[2]):
            open_items.append(match[2])
    return open_items


def check_report(state: Mapping, paths: Paths) -> Check:
    try:
        text = Path(state["report_path"]).read_text(encoding="utf-8")
    except OSError:
        text = ""
    lines = [line.rstrip() for line in text.splitlines()]
    positions = [lines.index(f"## {h}") if lines.count(f"## {h}") == 1 else -1 for h in HEADINGS]
    criteria = {
        "headings": -1 not in positions and positions == sorted(positions),
        "needs_you": bool(text) and _needs_you_ok(lines),
        "blocks_fresh": bool(text) and _blocks_fresh(text, _since(state, read_refused(paths))),
    }
    return Check(criteria, open_tasks(state.get("task_file")))


def cmd_check(args: argparse.Namespace, paths: Paths) -> int:
    result = check_report(require_state(paths), paths)
    for name, ok in result.criteria.items():
        print(f"criterion={name} status={'pass' if ok else 'fail'}")
    print(f"open={len(result.open_items)}")
    return 0 if result.passed else 1



class ToolUse(NamedTuple):
    agent: str
    ts: str
    tool_use_id: str
    name: str
    input: object


class Scan(NamedTuple):
    uses: list[ToolUse]
    denials: list[dict]
    cwds: set[str]


def _transcripts(transcript: Path) -> Iterator[tuple[str, Path]]:
    import transcript_reader

    yield "main", transcript
    for sub in transcript_reader.iter_subagents(transcript):
        kind = (sub.meta or {}).get("agentType")
        label = f"subagent {sub.path.stem}" + (f" ({kind})" if isinstance(kind, str) and kind else "")
        yield label, sub.path


def scan_transcripts(transcript: Path, since: datetime) -> Scan:
    sys.path.insert(0, str(SCRIPT.parent))
    import transcript_reader

    uses: list[ToolUse] = []
    denials: list[dict] = []
    cwds: set[str] = set()
    for agent, path in _transcripts(transcript):
        by_id: dict[str, ToolUse] = {}
        for record in transcript_reader.iter_records(path):
            if isinstance(record.get("cwd"), str):
                cwds.add(record["cwd"])
            stamp = _instant_or_none(record.get("timestamp"))
            if stamp is None or stamp < since:
                continue
            content = (record.get("message") or {}).get("content") if isinstance(record.get("message"), dict) else None
            if record.get("type") == "assistant" and isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_use" and isinstance(block.get("name"), str):
                        use = ToolUse(agent, record["timestamp"], str(block.get("id", "")), block["name"], block.get("input"))
                        uses.append(use)
                        by_id[use.tool_use_id] = use
            event = transcript_reader.permission_event(record)
            if event and event["outcome"] == "denied" and event.get("cause") == "classifier":
                use = by_id.get(event["tool_use_id"] or "")
                denials.append(
                    {
                        "event": "AutoModeDenial",
                        "tool_use_id": event["tool_use_id"],
                        "tool_name": use.name if use else None,
                        "detail": describe_tool(use.name, use.input) if use else "(tool call not found)",
                        "reason": event.get("reason"),
                        "agent": agent,
                    }
                )
    return Scan(uses, denials, cwds)


def is_external(use: ToolUse) -> bool:
    if use.name.startswith("mcp__"):
        return True
    command = use.input.get("command") if isinstance(use.input, dict) else None
    return isinstance(command, str) and any(pattern.search(command) for pattern in EXTERNAL_PATTERNS)


def _repo_of(path: str) -> str | None:
    current = Path(path)
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists():
            return os.path.realpath(candidate)
    return None


def run_roots(state: Mapping, cwds: set[str]) -> set[str]:
    roots = {repo for repo in map(_repo_of, cwds) if repo}
    launch = state.get("launch_root")
    if launch:
        roots.add(os.path.realpath(launch))
        listed = _git("-C", launch, "worktree", "list", "--porcelain")
        if listed is not None and listed.returncode == 0:
            for line in listed.stdout.splitlines():
                if line.startswith("worktree "):
                    roots.add(os.path.realpath(line[len("worktree ") :]))
    return roots


def scan_files(watched: list[str], since: float, prune: set[str]) -> list[str]:
    found = []
    for folder in watched:
        top = os.path.realpath(folder)
        if not os.path.isdir(top):
            continue
        for dirpath, dirnames, filenames in os.walk(top):
            dirnames[:] = sorted(
                d for d in dirnames if not d.startswith(".") and os.path.join(dirpath, d) not in prune
            )
            for name in sorted(filenames):
                if name.startswith("."):
                    continue
                path = os.path.join(dirpath, name)
                with contextlib.suppress(OSError):
                    if os.lstat(path).st_mtime >= since and os.path.isfile(path):
                        found.append(path)
    return found


def _limited(lines: list[str], limit: int) -> list[str]:
    return lines if len(lines) <= limit else [*lines[:limit], f"- … and {len(lines) - limit} more"]


def refresh(state: dict, paths: Paths) -> None:
    started = parse_instant(state["started"])
    transcript = Path(state["transcript_path"]) if state.get("transcript_path") else None
    externals: list[str]
    if transcript is not None and transcript.is_file():
        scan = scan_transcripts(transcript, started)
        append_refusals(paths, scan.denials, unless_seen="tool_use_id")
        externals = [
            f"- {use.ts} {use.agent}: {use.name if use.name.startswith('mcp__') else describe_tool(use.name, use.input)}"
            for use in scan.uses
            if is_external(use)
        ]
        cwds = scan.cwds
    else:
        externals = ["- The transcript is not recorded yet; the next Stop or prompt records it."]
        cwds = set()

    refused = []
    for entry in _since(state, read_refused(paths)):
        where = f" in {entry['agent']}" if entry.get("agent") not in (None, "main") else ""
        where += f" in agent {entry['agent_id']}" if entry.get("agent_id") else ""
        reason = f" [{entry['reason']}]" if entry.get("reason") else ""
        label = EVENT_LABELS.get(entry.get("event"), entry.get("event"))
        refused.append(f"- {entry['id']} {label}{reason}{where}, {entry.get('tool_name')}: {entry.get('detail')}")
    write_blocks(state, {"refused": refused, "externals": _limited(externals, FILES_LIMIT)})

    clock = time.monotonic()
    watched = state.get("watched") or [str(Path.home())]
    files = scan_files(watched, started.timestamp(), run_roots(state, cwds))
    seconds = time.monotonic() - clock
    file_lines = [f"Watched: {', '.join(watched)}; scanned in {seconds:.1f} s.", ""]
    file_lines += _limited([f"- {path}" for path in files], FILES_LIMIT) or ["None."]
    write_blocks(state, {"files": file_lines})


def write_blocks(state: Mapping, blocks: Mapping[str, list[str]]) -> None:
    """Rewrite the named script-owned blocks; the slow file scan writes apart from the others."""
    report = Path(state["report_path"])
    report.parent.mkdir(parents=True, exist_ok=True)
    text = report.read_text(encoding="utf-8") if report.exists() else skeleton(state)
    for name, lines in blocks.items():
        text = replace_block(text, name, render_block(name, lines))
    write_atomic(report, text)


def cmd_refresh(args: argparse.Namespace, paths: Paths) -> int:
    refresh(require_state(paths), paths)
    return 0


def cmd_end(args: argparse.Namespace, paths: Paths) -> int:
    state = require_state(paths)
    move(state, Status.ENDED)
    if status_of(state) is Status.ENDED:
        return 0

    def change(current: dict) -> None:
        move(current, Status.ENDED)
        current["status"] = Status.ENDED.value
        current["ended"] = datetime.now().astimezone().isoformat()

    update_state(paths, change)
    refresh(state, paths)
    report, beside = Path(state["report_path"]), paths.dir / "report.md"
    if report.exists() and os.path.realpath(report) != os.path.realpath(beside):
        shutil.copyfile(report, beside)
    print(f"status=ended\nreport={report}")
    return 0


def cmd_deliver(args: argparse.Namespace, paths: Paths) -> int:
    def change(state: dict) -> None:
        move(state, Status.DELIVERED)
        if status_of(state) is not Status.DELIVERED:
            state["status"] = Status.DELIVERED.value
            state["delivered"] = datetime.now().astimezone().isoformat()

    require_state(paths)
    update_state(paths, change)
    print("status=delivered")
    return 0


COMMANDS: dict[str, Callable[[argparse.Namespace, Paths], int]] = {
    "start": cmd_start,
    "status": cmd_status,
    "refresh": cmd_refresh,
    "check": cmd_check,
    "end": cmd_end,
    "deliver": cmd_deliver,
}



class Hook(NamedTuple):
    payload: dict
    paths: Paths
    state: dict

    @property
    def status(self) -> Status:
        return Status(self.state["status"])

    @property
    def command(self) -> str:
        return f'python3 "{SCRIPT}"'

    @property
    def session(self) -> str:
        return self.payload["session_id"]


def on_permission_request(hook: Hook) -> dict | None:
    if hook.status is not Status.ACTIVE:
        return None
    entry = {
        "event": "PermissionRequest",
        "tool_name": hook.payload.get("tool_name"),
        "detail": describe_tool(hook.payload.get("tool_name"), hook.payload.get("tool_input")),
    }
    if isinstance(hook.payload.get("agent_id"), str):
        entry["agent_id"] = hook.payload["agent_id"]
    try:
        [rid] = append_refusals(hook.paths, [entry])
        label = f"{rid}: refused"
    except OSError as exc:
        _log("PermissionRequest refusal not recorded", exc)
        label = "Refused (not recorded)"
    message = (
        f"{label} because the person is away and nothing that prompts may run until they are back. "
        "Do not retry this action another way; it waits in the away report. Continue with other work."
    )
    return {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "deny", "message": message}}}


def on_elicitation(hook: Hook) -> dict | None:
    if hook.status is not Status.ACTIVE:
        return None
    server = hook.payload.get("mcp_server_name")
    entry = {
        "event": "Elicitation",
        "tool_name": f"MCP server {server}",
        "detail": redact(f"{server}: {hook.payload.get('message', '')} (mode {hook.payload.get('mode', 'form')})"),
    }
    if isinstance(hook.payload.get("agent_id"), str):
        entry["agent_id"] = hook.payload["agent_id"]
    try:
        append_refusals(hook.paths, [entry])
    except OSError as exc:
        _log("Elicitation decline not recorded", exc)
    return {"hookSpecificOutput": {"hookEventName": "Elicitation", "action": "decline"}}


def _block(reason: str) -> dict:
    return {"decision": "block", "reason": reason}


def on_stop(hook: Hook) -> dict | None:
    if hook.status is not Status.ACTIVE:
        return None
    payload, paths = hook.payload, hook.paths
    report = Path(hook.state["report_path"])
    now_digest = digest(report)
    mode = payload.get("permission_mode")
    transcript = payload.get("transcript_path")

    def first_look(state: dict) -> tuple[bool, object]:
        if isinstance(transcript, str) and transcript and not payload.get("agent_id"):
            state["transcript_path"] = transcript
        warn = isinstance(mode, str) and mode != "auto" and not state.get("mode_warned")
        if warn:
            state["mode_warned"] = True
            state["last_block_digest"] = now_digest
        return warn, state.get("last_block_digest")

    warn, last_digest = update_state(paths, first_look)
    if warn:
        return _block(
            f"Away mode: this session's permission mode is {mode}, not auto, so every action that would "
            "prompt is refused instead of judged by auto mode. Tell the person now, before they leave, and "
            "offer to continue in auto mode. Then carry on."
        )
    if payload.get("background_tasks"):
        return None
    if payload.get("stop_hook_active") is True and now_digest == last_digest:
        return None
    result = check_report(hook.state, paths)
    if result.passed:
        return None
    update_state(paths, lambda state: state.update(last_block_digest=now_digest))
    parts = ["Away mode: the work is not finished."]
    if result.open_items:
        shown = "; ".join(result.open_items[:LIST_LIMIT])
        more = f" (and {len(result.open_items) - LIST_LIMIT} more)" if len(result.open_items) > LIST_LIMIT else ""
        parts.append(f"Open items in {hook.state.get('task_file')}: {shown}{more}.")
        parts.append("Work the next one, or mark it parked in the task file once it waits on the person.")
    failed = [name for name, ok in result.criteria.items() if not ok]
    if failed:
        parts.append(f"Report checks failing: {', '.join(failed)}.")
    parts.append(f"Run `{hook.command} refresh --session {hook.session}` after each finished piece.")
    parts.append(f"Re-read {paths.rules} if the away rules are not in context.")
    return _block(" ".join(parts))


def on_user_prompt_submit(hook: Hook) -> dict | None:
    state, status = hook.state, hook.status
    if status is Status.DELIVERED:
        return None
    if status is Status.ACTIVE:
        transcript = hook.payload.get("transcript_path")
        if isinstance(transcript, str) and transcript and transcript != state.get("transcript_path"):
            update_state(hook.paths, lambda current: current.update(transcript_path=transcript))
        due = state.get("report_by") or "when the person is back"
        text = (
            f"Away mode is on for this session: report due {due}, report at {state['report_path']}. "
            f"Re-read {hook.paths.rules} if the away rules are not in context. "
            f"Run `{hook.command} end --session {hook.session}` only when this message reads as the person "
            "being back: subagent reports, /loop and cron prompts and other sessions' messages also arrive here."
        )
    else:
        text = (
            f"The person is back. Show them the away report at {state['report_path']} once, leading with "
            f"Needs you, then run `{hook.command} deliver --session {hook.session}` so later turns do not "
            "show it again."
        )
    return {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": text}}


HANDLERS: dict[str, Callable[[Hook], dict | None]] = {
    "PermissionRequest": on_permission_request,
    "Elicitation": on_elicitation,
    "Stop": on_stop,
    "UserPromptSubmit": on_user_prompt_submit,
}


def _log(what: str, exc: BaseException) -> None:
    sys.stderr.write(f"away.py: {what}: {type(exc).__name__}: {exc}\n")


def run_hook(argv: list[str]) -> int:
    """Answer one hook event. Exits 0 on every path; stdout carries only the decision JSON."""
    try:
        parser = argparse.ArgumentParser(prog="away.py hook", add_help=False)
        parser.add_argument("event")
        parser.add_argument("--plugin-root")
        args, _ = parser.parse_known_args(argv)
        handler = HANDLERS.get(args.event)
        if handler is None:
            return 0
        payload = json.loads(sys.stdin.read() or "null")
        if not isinstance(payload, dict) or not valid_session(payload.get("session_id")):
            return 0
        plugin_root = Path(args.plugin_root) if args.plugin_root else DEFAULT_PLUGIN_ROOT
        root = data_root(os.environ, str(plugin_root))
        if root is None:
            return 0
        paths = session_paths(root, payload["session_id"], plugin_root)
        state = read_state(paths)
        if state is None:
            return 0
        output = handler(Hook(payload, paths, state))
        if output is not None:
            sys.stdout.write(json.dumps(output) + "\n")
    except (Exception, SystemExit) as exc:
        _log("hook failed open", exc)
    return 0



def _session_arg(value: str) -> str:
    if not valid_session(value):
        raise argparse.ArgumentTypeError("a session id is 1-128 letters, digits, '_' or '-'")
    return value


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--session", required=True, type=_session_arg)
    common.add_argument("--plugin-root", help="the plugin root, to find the data root without CLAUDE_PLUGIN_DATA")
    common.add_argument("--setting", action="append", default=[], metavar="KEY=VALUE")
    parser = argparse.ArgumentParser(prog="away.py", description=__doc__.split("\n\n", 1)[0])
    commands = parser.add_subparsers(dest="command", required=True)
    start = commands.add_parser("start", parents=[common])
    start.add_argument("--kind", required=True, choices=KINDS)
    start.add_argument("--until")
    start.add_argument("--scope")
    start.add_argument("--task-file")
    for name in ("status", "refresh", "check", "end", "deliver"):
        commands.add_parser(name, parents=[common])
    return parser


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["hook"]:
        return run_hook(argv[1:])
    args = build_parser().parse_args(argv)
    plugin_root = Path(args.plugin_root) if args.plugin_root else DEFAULT_PLUGIN_ROOT
    root = data_root(os.environ, str(plugin_root))
    if root is None:
        print(
            "away.py: no data root: CLAUDE_PLUGIN_DATA is unset and --plugin-root is not a marketplace install",
            file=sys.stderr,
        )
        return 2
    paths = session_paths(root, args.session, plugin_root)
    try:
        return COMMANDS[args.command](args, paths)
    except AwayError as exc:
        print(f"away.py {args.command}: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"away.py {args.command}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
