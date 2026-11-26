#!/usr/bin/env python3
# GENERATED from lib/claude_projects.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""Shared Claude Code ``projects/`` slug encoder, resolver, and orphan detector.

Claude Code stores session transcripts under
``${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>``. A directory name encodes the
session's working directory by replacing every UTF-16 code unit that is not an
ASCII letter or digit with ``-``; past 200 characters the name keeps its first
200 characters and appends a hash. ``CLAUDE_CODE_PROJECT_DIR_NAME`` (active only
when ``CLAUDE_CONFIG_DIR`` is set too, and excluding Windows reserved device
names) pins one directory name for every session.

Read-only, Python 3.10+, standard library only, zero cross-imports. The plugin
copies are generated from lib/claude_projects.py (scripts/shared-copies.txt).
"""

from __future__ import annotations

import argparse
import dataclasses
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import zlib
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path
from typing import Protocol, runtime_checkable

PROJECT_NAME_CAP = 200

_PINNED_NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_WIN_RESERVED_RE = re.compile(r"^(?:con|prn|aux|nul|com[0-9]|lpt[0-9])$", re.IGNORECASE)
_WIN_DRIVE_SLUG_RE = re.compile(r"^([A-Za-z])--(.*)$")
_WIN_DRIVE_PATH_RE = re.compile(r"^([A-Za-z]):(.*)$")


def encode_project_slug(path: str) -> str:
    """Encode ``path`` using Claude Code's UTF-16 code-unit rule.

    Every UTF-16 code unit that is not an ASCII letter or digit becomes ``-``.
    A BMP non-ASCII character (U+0080..U+FFFF) is one code unit (``-``); a
    supplementary-plane character (> U+FFFF) is a surrogate pair, so two code
    units (``--``).
    """
    out: list[str] = []
    for ch in path:
        code = ord(ch)
        if 0x30 <= code <= 0x39 or 0x41 <= code <= 0x5A or 0x61 <= code <= 0x7A:
            out.append(ch)
        elif code > 0xFFFF:
            out.append("--")
        else:
            out.append("-")
    return "".join(out)


def resolve_projects_dir(
    claude_dir: str | Path | None = None,
    *,
    env: Mapping[str, str] | None = None,
    home: Path | None = None,
) -> Path:
    """Return ``<claude_dir>/projects`` honoring ``CLAUDE_CONFIG_DIR``."""
    if claude_dir is not None and str(claude_dir):
        return Path(claude_dir).expanduser() / "projects"
    mapping = os.environ if env is None else env
    cfg = mapping.get("CLAUDE_CONFIG_DIR")
    if cfg:
        return Path(cfg).expanduser() / "projects"
    base = Path.home() if home is None else home
    return base / ".claude" / "projects"


def validated_pinned_dir_name(env: Mapping[str, str] | None = None) -> str | None:
    """Return the validated ``CLAUDE_CODE_PROJECT_DIR_NAME`` when active, else None.

    Active only when ``CLAUDE_CONFIG_DIR`` is set and non-empty. Rejects names
    outside ``^[A-Za-z0-9_-]{1,64}$`` and Windows reserved device names
    (``con``, ``prn``, ``aux``, ``nul``, ``com0``-``com9``, ``lpt0``-``lpt9``).
    """
    mapping = os.environ if env is None else env
    if not mapping.get("CLAUDE_CONFIG_DIR"):
        return None
    pinned = mapping.get("CLAUDE_CODE_PROJECT_DIR_NAME") or ""
    if not _PINNED_NAME_RE.match(pinned):
        return None
    if _WIN_RESERVED_RE.match(pinned):
        return None
    return pinned


def normalize_path_for_compare(path: str) -> str:
    """Normalize slashes and leading Windows drive letter case for prefix comparison."""
    p = path.replace("\\", "/")
    match = _WIN_DRIVE_PATH_RE.match(p)
    if match:
        p = f"{match.group(1).lower()}:{match.group(2)}"
    if len(p) > 1 and not (len(p) == 3 and p[1:3] == ":/"):
        p = p.rstrip("/")
    return p


def _path_is_root_or_child(candidate: str, root: str) -> bool:
    c = normalize_path_for_compare(candidate)
    r = normalize_path_for_compare(root)
    if not c or not r:
        return False
    if c == r:
        return True
    prefix = r if r.endswith("/") else r + "/"
    return c.startswith(prefix)


def newest_transcript(project_dir: Path) -> Path | None:
    """Return the newest ``*.jsonl`` regular file inside ``project_dir``, or None."""
    newest_path: Path | None = None
    newest_mtime = -1
    try:
        with os.scandir(project_dir) as entries:
            for entry in entries:
                if not entry.name.endswith(".jsonl"):
                    continue
                try:
                    if not entry.is_file(follow_symlinks=True):
                        continue
                    mtime = entry.stat(follow_symlinks=True).st_mtime_ns
                except OSError:
                    continue
                if mtime > newest_mtime:
                    newest_mtime = mtime
                    newest_path = Path(entry.path)
    except OSError:
        return None
    return newest_path


def first_cwd_from_jsonl(path: Path) -> str | None:
    """Return the ``cwd`` of the first JSON object carrying a non-empty string one."""
    try:
        if path.suffix == ".gz":
            fh_ctx = gzip.open(path, "rt", encoding="utf-8", errors="replace")
        else:
            fh_ctx = path.open("r", encoding="utf-8", errors="replace")
        with fh_ctx as fh:
            for line in fh:
                stripped = line.strip()
                if not stripped:
                    continue
                if stripped.startswith("["):
                    try:
                        arr = json.loads(stripped)
                    except ValueError:
                        continue
                    if isinstance(arr, list):
                        for item in arr:
                            if isinstance(item, dict):
                                cwd = item.get("cwd")
                                if isinstance(cwd, str) and cwd:
                                    return cwd
                    continue
                try:
                    record = json.loads(stripped)
                except ValueError:
                    continue
                if isinstance(record, dict):
                    cwd = record.get("cwd")
                    if isinstance(cwd, str) and cwd:
                        return cwd
    except (OSError, zlib.error, EOFError):
        return None
    return None


@runtime_checkable
class TranscriptCwdPort(Protocol):
    """Read-only port returning the recorded ``cwd`` for a project transcript directory."""

    def read_cwd(self, project_dir: Path) -> str | None: ...


class TranscriptReaderCwdAdapter:
    """Read ``cwd`` from the newest ``*.jsonl`` file in ``project_dir``."""

    def __init__(
        self, first_cwd_fn: Callable[[Path], str | None] | None = None
    ) -> None:
        self._first_cwd = first_cwd_fn or first_cwd_from_jsonl

    def read_cwd(self, project_dir: Path) -> str | None:
        newest = newest_transcript(project_dir)
        if newest is None:
            return None
        try:
            cwd = self._first_cwd(newest)
        except Exception:
            return None
        return cwd if isinstance(cwd, str) and cwd else None


class NullTranscriptCwdAdapter:
    """Stat-only adapter that never opens any transcript file."""

    def read_cwd(self, project_dir: Path) -> str | None:
        return None


class InMemoryTranscriptCwdAdapter:
    """Hermetic test adapter mapping project directory paths or names to recorded ``cwd``."""

    def __init__(self, cwds: Mapping[Path | str, str | None]) -> None:
        self._by_str: dict[str, str | None] = {
            str(k): v for k, v in cwds.items()
        }

    def read_cwd(self, project_dir: Path) -> str | None:
        if str(project_dir) in self._by_str:
            return self._by_str[str(project_dir)]
        return self._by_str.get(project_dir.name)


@dataclasses.dataclass(frozen=True)
class ProjectResolution:
    """Outcome of resolving one ``projects/<slug>`` directory."""

    slug: str
    path: Path
    status: str
    source_path: str | None
    via: str
    reason: str


@dataclasses.dataclass(frozen=True)
class _DirListing:
    exact: dict[str, str]
    dirs: tuple[tuple[str, str], ...]


def _default_drive_roots() -> dict[str, Path]:
    if os.name != "nt":
        return {}
    found: dict[str, Path] = {}
    for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        root = Path(f"{letter}:\\")
        try:
            if root.exists():
                found[letter] = root
        except OSError:
            pass
    return found


class ProjectSlugResolver:
    """Cached resolver for Claude Code ``projects/`` slug directories.

    Caches ``os.scandir`` listings per parent directory for the lifetime of the
    resolver instance so resolving N sibling project slugs walks shared
    ancestors once instead of N times.
    """

    def __init__(
        self,
        *,
        fs_root: Path = Path("/"),
        drive_roots: Mapping[str, Path] | None = None,
        cwd_port: TranscriptCwdPort | None = None,
        env: Mapping[str, str] | None = None,
    ) -> None:
        self.fs_root = Path(fs_root)
        self._custom_fs_root = self.fs_root != Path("/")
        if drive_roots is not None:
            self.drive_roots = {k.upper(): Path(v) for k, v in drive_roots.items()}
        elif not self._custom_fs_root:
            self.drive_roots = _default_drive_roots()
        else:
            self.drive_roots = {}
        self.cwd_port: TranscriptCwdPort = (
            cwd_port if cwd_port is not None else NullTranscriptCwdAdapter()
        )
        self.env = env
        self._dir_cache: dict[Path, _DirListing | None] = {}

    def _list_dir(self, base: Path) -> _DirListing | None:
        if base in self._dir_cache:
            return self._dir_cache[base]
        try:
            with os.scandir(base) as it:
                raw = sorted(it, key=lambda e: e.name)
                exact: dict[str, str] = {}
                dirs: list[tuple[str, str]] = []
                for entry in raw:
                    code = encode_project_slug(entry.name)
                    exact.setdefault(code, entry.name)
                    try:
                        if entry.is_dir(follow_symlinks=True):
                            dirs.append((entry.name, code))
                    except OSError:
                        pass
            listing = _DirListing(exact=exact, dirs=tuple(dirs))
        except OSError:
            listing = None
        self._dir_cache[base] = listing
        return listing

    def _walk(self, base: Path, rest: str) -> Path | None:
        listing = self._list_dir(base)
        if listing is None:
            return None
        direct = listing.exact.get(rest)
        if direct is not None:
            return base / direct
        for name, code in listing.dirs:
            if rest.startswith(code + "-"):
                found = self._walk(base / name, rest[len(code) + 1 :])
                if found is not None:
                    return found
        return None

    def _source_exists(self, source_path: str) -> bool | None:
        """Check whether ``source_path`` exists, respecting ``fs_root`` and ``drive_roots``.

        Returns None when the path belongs to a drive root that is unavailable
        on this host (for example a Windows drive letter on POSIX without a
        configured ``drive_roots`` entry).
        """
        win_match = _WIN_DRIVE_PATH_RE.match(source_path)
        if win_match:
            drive = win_match.group(1).upper()
            tail = win_match.group(2).replace("\\", "/").lstrip("/")
            root = self.drive_roots.get(drive)
            if root is None:
                return None
            return (root / tail).exists() if tail else root.exists()
        if source_path.startswith("/"):
            rel = source_path.lstrip("/")
            candidate = self.fs_root / rel if rel else self.fs_root
            return candidate.exists()
        return Path(source_path).exists()

    def decode_slug(self, slug: str) -> str | None:
        """Return the existing source path decoded from ``slug`` via cached walk, or None."""
        if not slug or len(slug) > PROJECT_NAME_CAP:
            return None
        if slug.startswith("-"):
            if slug == "-":
                return "/" if self.fs_root.exists() else None
            found = self._walk(self.fs_root, slug[1:])
            if found is None:
                return None
            return "/" + found.relative_to(self.fs_root).as_posix()
        win_match = _WIN_DRIVE_SLUG_RE.match(slug)
        if win_match:
            drive = win_match.group(1).upper()
            rest = win_match.group(2)
            root = self.drive_roots.get(drive)
            if root is None:
                return None
            if not rest:
                return f"{drive}:\\"
            found = self._walk(root, rest)
            if found is None:
                return None
            rel = found.relative_to(root).as_posix().replace("/", "\\")
            return f"{drive}:\\{rel}"
        return None

    def _cwd_matches_slug(self, cwd: str, slug: str, pinned: str | None) -> bool:
        if pinned is not None and slug == pinned:
            return True
        enc = encode_project_slug(cwd)
        if not enc:
            return False
        if slug == enc:
            return True
        if len(enc) >= PROJECT_NAME_CAP and slug.startswith(enc[:PROJECT_NAME_CAP]):
            return True
        return False

    def resolve_dir(self, project_dir: Path) -> ProjectResolution:
        """Resolve one ``projects/<slug>`` directory to ``exists``, ``orphan``, ``pinned``, or ``unknown``."""
        slug = project_dir.name
        pinned = validated_pinned_dir_name(self.env)

        win_match = _WIN_DRIVE_SLUG_RE.match(slug)
        if pinned is None or slug != pinned:
            if len(slug) <= PROJECT_NAME_CAP and (
                slug.startswith("-")
                or (win_match and win_match.group(1).upper() in self.drive_roots)
            ):
                source = self.decode_slug(slug)
                if source is not None:
                    return ProjectResolution(
                        slug=slug,
                        path=project_dir,
                        status="exists",
                        source_path=source,
                        via="tree-walk",
                        reason=f"transcripts of {source}, which still exists",
                    )

        cwd = self.cwd_port.read_cwd(project_dir)
        if cwd and self._cwd_matches_slug(cwd, slug, pinned):
            exists = self._source_exists(cwd)
            if exists is True:
                return ProjectResolution(
                    slug=slug,
                    path=project_dir,
                    status="exists",
                    source_path=cwd,
                    via="transcript-cwd",
                    reason=f"transcripts of {cwd}, which still exists",
                )
            if exists is False:
                return ProjectResolution(
                    slug=slug,
                    path=project_dir,
                    status="orphan",
                    source_path=cwd,
                    via="transcript-cwd",
                    reason=f"transcripts of {cwd}, whose source path no longer exists",
                )
            return ProjectResolution(
                slug=slug,
                path=project_dir,
                status="unknown",
                source_path=cwd,
                via="transcript-cwd",
                reason=f"recorded cwd {cwd} is on a root not accessible on this host",
            )

        if pinned is not None and slug == pinned:
            return ProjectResolution(
                slug=slug,
                path=project_dir,
                status="pinned",
                source_path=None,
                via="pinned",
                reason="pinned by CLAUDE_CODE_PROJECT_DIR_NAME under CLAUDE_CONFIG_DIR",
            )

        if len(slug) > PROJECT_NAME_CAP:
            return ProjectResolution(
                slug=slug,
                path=project_dir,
                status="unknown",
                source_path=None,
                via="unresolvable",
                reason="the name is hash-truncated past 200 characters and no transcript cwd confirmed it",
            )

        if slug.startswith("-"):
            return ProjectResolution(
                slug=slug,
                path=project_dir,
                status="orphan",
                source_path=None,
                via="tree-walk",
                reason="transcripts of a project whose source path no longer exists",
            )

        if win_match:
            drive = win_match.group(1).upper()
            if drive not in self.drive_roots:
                return ProjectResolution(
                    slug=slug,
                    path=project_dir,
                    status="unknown",
                    source_path=None,
                    via="unresolvable",
                    reason="the name is a Windows drive path encoding not accessible on this host",
                )
            return ProjectResolution(
                slug=slug,
                path=project_dir,
                status="orphan",
                source_path=None,
                via="tree-walk",
                reason="transcripts of a project whose source path no longer exists",
            )

        return ProjectResolution(
            slug=slug,
            path=project_dir,
            status="unknown",
            source_path=None,
            via="unresolvable",
            reason="the name is not a decodable POSIX path encoding",
        )

    def resolve_all(self, projects_dir: Path) -> list[ProjectResolution]:
        """Resolve every child directory under ``projects_dir`` sharing one directory cache."""
        try:
            with os.scandir(projects_dir) as entries:
                children = sorted(
                    Path(e.path) for e in entries if e.is_dir(follow_symlinks=False)
                )
        except OSError:
            return []
        return [self.resolve_dir(child) for child in children]

    def match_roots(
        self,
        projects_dir: Path,
        roots: Sequence[str],
        *,
        scope: str = "worktree",
    ) -> list[Path]:
        """Return matching project directories for ``scope`` (``worktree`` | ``repo`` | ``all``)."""
        pinned = validated_pinned_dir_name(self.env)
        if pinned is not None:
            candidate = projects_dir / pinned
            return [candidate] if candidate.is_dir() else []

        try:
            with os.scandir(projects_dir) as entries:
                store_dirs = sorted(
                    (e.name, Path(e.path))
                    for e in entries
                    if e.is_dir(follow_symlinks=True)
                )
        except OSError:
            return []

        if scope == "all":
            return [path for _, path in store_dirs]

        by_name = dict(store_dirs)
        matched: list[Path] = []
        seen: set[str] = set()

        def add(path: Path) -> None:
            key = str(path)
            if key not in seen:
                seen.add(key)
                matched.append(path)

        for root in roots:
            enc = encode_project_slug(root)
            if not enc:
                continue
            exact = by_name.get(enc)
            if exact is not None:
                add(exact)
            long_prefix = enc[:PROJECT_NAME_CAP] if len(enc) >= PROJECT_NAME_CAP else ""
            for name, path in store_dirs:
                if name == enc or str(path) in seen:
                    continue
                if name.startswith(enc + "-") or (
                    long_prefix and name.startswith(long_prefix)
                ):
                    cwd = self.cwd_port.read_cwd(path)
                    if cwd and _path_is_root_or_child(cwd, root):
                        add(path)
        return matched


def _win_form(path: str) -> str:
    if shutil.which("cygpath"):
        try:
            proc = subprocess.run(
                ["cygpath", "-w", path],
                capture_output=True,
                text=True,
                check=False,
            )
            out = proc.stdout.rstrip("\r\n")
            if proc.returncode == 0 and out:
                return out
        except OSError:
            pass
    return path


def _discover_git_roots(scope: str) -> list[str]:
    here_root = ""
    in_repo = False
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode == 0:
            here_root = proc.stdout.strip().replace("\r", "")
            in_repo = bool(here_root)
    except OSError:
        pass
    if not here_root:
        here_root = os.getcwd()
    roots = [_win_form(here_root)]
    if scope == "repo" and in_repo:
        try:
            proc = subprocess.run(
                ["git", "worktree", "list", "--porcelain"],
                capture_output=True,
                text=True,
                check=False,
            )
            if proc.returncode == 0:
                for raw_line in proc.stdout.splitlines():
                    line = raw_line.replace("\r", "")
                    if line.startswith("worktree "):
                        wt = _win_form(line[len("worktree ") :])
                        if wt not in roots:
                            roots.append(wt)
        except OSError:
            pass
    return roots


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="claude_projects.py",
        description="Resolve Claude Code projects/ transcript directories.",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    cmd = sub.add_parser(
        "resolve-project-dirs",
        help="Print matching Claude Code project transcript directories, one per line.",
    )
    cmd.add_argument(
        "--scope",
        required=True,
        choices=("worktree", "repo", "all"),
        help="Scope of project directories to list.",
    )
    cmd.add_argument(
        "--projects-dir",
        default=None,
        help="Override projects store path (default: ${CLAUDE_CONFIG_DIR:-~/.claude}/projects).",
    )
    cmd.add_argument(
        "--root",
        action="append",
        default=None,
        help="Explicit worktree/repo root path (repeatable; auto-discovered via git if omitted).",
    )

    try:
        args = parser.parse_args(list(argv) if argv is not None else None)
    except SystemExit as exc:
        return int(exc.code) if isinstance(exc.code, int) else 2

    if args.command == "resolve-project-dirs":
        projects_dir = (
            Path(args.projects_dir).expanduser()
            if args.projects_dir
            else resolve_projects_dir()
        )
        roots: list[str]
        if args.scope == "all":
            roots = []
        elif args.root:
            roots = list(args.root)
        else:
            roots = _discover_git_roots(args.scope)

        resolver = ProjectSlugResolver(cwd_port=TranscriptReaderCwdAdapter())
        for path in resolver.match_roots(projects_dir, roots, scope=args.scope):
            sys.stdout.write(f"{path}\n")
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
