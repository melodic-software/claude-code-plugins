# -*- coding: utf-8 -*-
"""Paths and file writes the session-flow scripts share.

- `data_root(env, plugin_root)` is the plugin data directory: `CLAUDE_PLUGIN_DATA` when its last
  path segment is `session-flow` or starts with `session-flow-` (another plugin's hook can export
  its own directory under that name, and a `--plugin-dir` run gets `session-flow-inline`), else
  derived from an installed plugin root `<config>/plugins/cache/<marketplace>/<plugin>/<version>`
  as `<config>/plugins/data/<plugin@marketplace>` with every character outside `[A-Za-z0-9_-]`
  replaced by `-`, else None. A Bash-tool command never receives `CLAUDE_PLUGIN_DATA`, so the
  derivation is the normal case there (plugins manifest reference, "Environment variables").
- `write_atomic(path, text)` writes through a private temp file beside `path` and `os.replace`,
  retrying while Windows refuses the replace because a reader holds the target open; False when
  that outlasts the retries. The file is created 0600.
- `run_git(directory, *args, timeout=None)` is `git -C <directory> <args>` as a completed process,
  or None when git cannot start or runs past `timeout`.
- `file_lock(path, wait)` holds an exclusive lock on `path` (created 0600, its folder must exist)
  and yields True, or yields False without the lock when another holder kept it past `wait`
  seconds.

Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import contextlib
import os
import re
import subprocess
import tempfile
import time
from collections.abc import Iterator, Mapping
from pathlib import Path

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


PLUGIN_NAME = "session-flow"
SELF_IGNORE = ".gitignore"
REPLACE_RETRIES = 20
REPLACE_RETRY_SECONDS = 0.05
LOCK_POLL_SECONDS = 0.01

_CONVENTION_BEGIN = "<!-- BEGIN GENERATED: convention-home -->"
_CONVENTION_END = "<!-- END GENERATED: convention-home -->"
_CONVENTION_SEG_RE = re.compile(r"^[A-Za-z0-9._-]+$")
_BACKTICK_RE = re.compile(r"`([^`]+)`")
_YAML_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$")


def data_root(env: Mapping[str, str], plugin_root: str | os.PathLike | None) -> Path | None:
    configured = env.get("CLAUDE_PLUGIN_DATA", "")
    segment = Path(configured.rstrip("/\\")).name if configured else ""
    if segment == PLUGIN_NAME or segment.startswith(f"{PLUGIN_NAME}-"):
        return Path(configured).expanduser()
    if plugin_root is None:
        return None
    version_dir = Path(plugin_root)
    plugin_dir = version_dir.parent
    marketplace_dir = plugin_dir.parent
    cache_dir = marketplace_dir.parent
    if cache_dir.name != "cache" or cache_dir.parent.name != "plugins":
        return None
    plugin_id = re.sub(r"[^A-Za-z0-9_-]", "-", f"{plugin_dir.name}@{marketplace_dir.name}")
    return cache_dir.parent / "data" / plugin_id


def write_atomic(path: Path, text: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        for _ in range(REPLACE_RETRIES):
            try:
                os.replace(tmp, path)
                return True
            except PermissionError:
                time.sleep(REPLACE_RETRY_SECONDS)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise
    Path(tmp).unlink(missing_ok=True)
    return False


@contextlib.contextmanager
def file_lock(path: Path, wait: float) -> Iterator[bool]:
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        deadline = time.monotonic() + wait
        while True:
            try:
                _try_lock(fd)
                break
            except OSError:
                if time.monotonic() > deadline:
                    yield False
                    return
                time.sleep(LOCK_POLL_SECONDS)
        try:
            yield True
        finally:
            _unlock(fd)
    finally:
        os.close(fd)


def run_git(directory: str | os.PathLike, *args: str, timeout: float | None = None) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(
            ["git", "-C", str(directory), *args], capture_output=True, text=True, check=False, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def git_toplevel(path: str | os.PathLike) -> Path | None:
    """Resolve the enclosing Git work-tree root for ``path``, walking up if ``path`` does not yet exist."""
    probe = Path(path)
    while not probe.exists() and probe.parent != probe:
        probe = probe.parent
    result = run_git(probe, "rev-parse", "--show-toplevel")
    if result is None or result.returncode != 0:
        return None
    top = result.stdout.strip()
    return Path(top).resolve() if top else None


def default_memory_dir(
    cwd: str | os.PathLike | None = None,
    env: Mapping[str, str] | None = None,
    plugin_root: str | os.PathLike | None = None,
) -> Path | None:
    """Default memory root: ``.work`` inside a Git repo, else ``<data_root>/artifacts``."""
    cwd_path = Path.cwd() if cwd is None else Path(cwd)
    if git_toplevel(cwd_path) is not None:
        return Path(".work")
    env_map = os.environ if env is None else env
    root = data_root(env_map, plugin_root)
    return root / "artifacts" if root is not None else None


def is_self_ignored(root: str | os.PathLike) -> bool:
    """True when ``<root>/.gitignore`` contains a bare ``*`` or ``**`` line."""
    try:
        lines = (Path(root) / SELF_IGNORE).read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return False
    return any(line.strip() in ("*", "**") for line in lines)


def is_repo_root(path: str | os.PathLike, repo_top: Path | None = None) -> bool:
    """True when ``path`` is a Git repository or worktree root."""
    resolved = Path(path).resolve()
    if (resolved / ".git").exists():
        return True
    return repo_top is not None and resolved == repo_top.resolve()


def validate_memory_root(
    path: str | os.PathLike,
    repo_top: Path | None = None,
    *,
    require_self_ignore: bool = False,
) -> Path:
    """Validate and resolve a memory root.

    Rejects a repository root (every top-level directory there would look like a slice
    and writing ``.gitignore`` would overwrite the repository's own file) and rejects an
    existing directory outside the repository unless its ``.gitignore`` carries a bare
    ``*`` or ``**`` self-ignore guard. When ``require_self_ignore`` is True, the guard is
    required regardless of whether ``path`` sits inside or outside the repository.
    """
    memory = Path(path).resolve()
    top = repo_top.resolve() if repo_top is not None else git_toplevel(memory)
    if is_repo_root(memory, top):
        raise ValueError(
            f"memory root {memory.as_posix()} is the repository root; "
            "it must be a dedicated directory below it"
        )
    outside = top is None or not memory.is_relative_to(top)
    if require_self_ignore:
        if not is_self_ignored(memory):
            raise ValueError(
                f"memory root {memory.as_posix()} lacks the self-ignore guard: "
                f"{(memory / SELF_IGNORE).as_posix()} must contain a line '*'"
            )
    elif outside and memory.is_dir() and not is_self_ignored(memory):
        raise ValueError(
            f"memory root {memory.as_posix()} is outside the repository and "
            f"lacks the self-ignore guard: {(memory / SELF_IGNORE).as_posix()} "
            "must contain a line '*'"
        )
    return memory


def _parse_convention_home_region(text: str) -> str | None:
    """Return the bound repo-relative home path, ``'declined'``, or None when absent/invalid."""
    in_region = False
    found: str | None = None
    saw_declined = False
    for raw in text.splitlines():
        line = raw.lstrip("\ufeff").rstrip("\r").strip()
        if line == _CONVENTION_BEGIN:
            if in_region:
                return None
            in_region = True
            continue
        if line == _CONVENTION_END:
            if not in_region:
                return None
            if saw_declined and found is not None:
                return None
            return "declined" if saw_declined else found
        if not in_region:
            continue
        if line == "declined":
            saw_declined = True
            continue
        match = _BACKTICK_RE.search(line)
        if match:
            if found is not None:
                return None
            found = match.group(1)
    return None


def _valid_convention_relpath(token: str) -> Path | None:
    cleaned = token.rstrip("/")
    if not cleaned or cleaned.startswith(("/", "~")) or "\\" in cleaned:
        return None
    parts = cleaned.split("/")
    for seg in parts:
        if not seg or not _CONVENTION_SEG_RE.fullmatch(seg):
            return None
        lower = seg.rstrip(".").lower()
        if seg in (".", "..") or lower == ".git":
            return None
    return Path(*parts)


def resolve_convention_home(
    repo_top: Path | None, home: Path | None = None
) -> Path | None:
    """Resolve a repository's ADR 0075 convention home, or fallback ``docs/conventions``."""
    if repo_top is None:
        return None
    top = repo_top.resolve()
    user_home = (home if home is not None else Path.home()).resolve()
    if top == user_home or top in user_home.parents:
        return None

    for candidate_name in ("AGENTS.md", "CLAUDE.md"):
        doc = top / candidate_name
        if not doc.is_file() or doc.is_symlink():
            continue
        try:
            text = doc.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        non_blank = [ln.strip() for ln in text.splitlines() if ln.strip()]
        if candidate_name == "CLAUDE.md" and non_blank == ["@AGENTS.md"]:
            continue
        token = _parse_convention_home_region(text)
        if token == "declined":
            return None
        if token is not None:
            rel = _valid_convention_relpath(token)
            if rel is None:
                return None
            target = top / rel
            if target.is_dir() and not target.is_symlink():
                try:
                    resolved = target.resolve()
                except OSError:
                    return None
                if resolved.is_relative_to(top):
                    return resolved
            return None

    default_dir = top / "docs" / "conventions"
    if default_dir.is_dir() and not default_dir.is_symlink():
        try:
            resolved = default_dir.resolve()
        except OSError:
            return None
        if resolved.is_relative_to(top):
            return resolved
    return None


def _strip_yaml_comment(raw: str) -> str:
    in_single = False
    in_double = False
    for idx, ch in enumerate(raw):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double and (idx == 0 or raw[idx - 1].isspace()):
            return raw[:idx].rstrip()
    return raw.rstrip()


def _unquote_yaml_scalar(value: str) -> str:
    s = value.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


def read_session_flow_yaml(
    repo_top: Path | None, home: Path | None = None
) -> dict[str, object]:
    """Read top-level scalars and string lists from ``<convention_home>/session-flow.yaml``."""
    conv_home = resolve_convention_home(repo_top, home)
    if conv_home is None:
        return {}
    cfg_path = conv_home / "session-flow.yaml"
    if not cfg_path.is_file() or cfg_path.is_symlink():
        return {}
    try:
        lines = cfg_path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return {}

    parsed: dict[str, object] = {}
    current_list_key: str | None = None
    for raw in lines:
        stripped = _strip_yaml_comment(raw.rstrip("\r"))
        if not stripped.strip():
            continue
        if stripped[0].isspace():
            item_text = stripped.lstrip()
            if current_list_key is not None and item_text.startswith("-"):
                rest = item_text[1:].strip()
                if rest:
                    lst = parsed.setdefault(current_list_key, [])
                    if isinstance(lst, list):
                        lst.append(_unquote_yaml_scalar(rest))
            continue
        current_list_key = None
        match = _YAML_KEY_RE.match(stripped)
        if not match:
            continue
        key, val = match.group(1), match.group(2).strip()
        if not val:
            parsed[key] = []
            current_list_key = key
        elif val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            if not inner:
                parsed[key] = []
            else:
                parsed[key] = [
                    _unquote_yaml_scalar(part)
                    for part in inner.split(",")
                    if part.strip()
                ]
        else:
            parsed[key] = _unquote_yaml_scalar(val)
    return parsed
