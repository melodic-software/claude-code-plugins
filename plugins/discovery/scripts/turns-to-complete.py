#!/usr/bin/env python3
"""Measure how many assistant turns discovery subagent dispatches take to finish.

When --root is omitted and the session-flow plugin is installed with a collected
audit-sessions store, reads per-dispatch rows from session-flow's store through
session-flow's scripts/dispatches.py across every source collected into the store.
When session-flow or its store is absent, falls back to reading Claude Code session
transcripts directly through the shared reader (lib/transcript_reader.py): every
subagents/agent-*.jsonl that has a sibling agent-*.meta.json under each local source
the sources file lists (lib/transcript_sources.py; with no --sources-file, the local
configuration directory). A turn is counted in the unit `maxTurns` uses (see
plugins/discovery/reference/parent-contract.md): one assistant message, however
many parallel tool calls it holds, so assistant records are grouped by
message.id and the distinct ids are counted.

Without --root, the report header (`header` in --json) names whether the session-flow
store or local sources were read, plus any collection gaps, stale sources, records
lacking per-dispatch rows, local lookup gaps (with retry command and optional
--diagnostics-dir record), or unread remote sources in local fallback mode. With
--root it reads that one directory and has no header.

Only counts, dates and agent types are printed, never transcript content. The markdown is
published output: it passes through the publish redactor (lib/publish.py over --sources-file and
--redact-identifiers), and when that fails closed nothing is printed and the exit is 2; --json is not.

Exit 0 = report written (an empty result is still a report)
Exit 2 = the --root cannot be read, the sources file is malformed, the session-flow store
         returned an error, the publish redactor fails closed, or a usage error

Usage:
  python3 turns-to-complete.py [--root DIR] [--agent-type A,B] [--since YYYY-MM-DD]
                               [--ceiling N] [--json] [--sources-file F]
                               [--redact-identifiers LIST] [--diagnostics-dir DIR]
                               [--session-flow-script FILE] [--session-flow-data-dir DIR]

A dispatch enters the statistics only when it finished: its last assistant
message has a stop_reason other than tool_use, or it reached the ceiling. Running,
cancelled and aborted dispatches are counted in a stderr note, not in the table.

Columns:
  turns        distinct assistant message ids in the dispatch
  hit_ceiling  yes when turns >= --ceiling (default 40) or a record carries
               stop_reason "max_turns"; else no
  resumed      yes when a user record that is not a tool result follows the
               ceiling turn in the same transcript; unknown at the ceiling
               without one (a resume that leaves no record is undetectable);
               n/a below the ceiling
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
sys.dont_write_bytecode = True

import publish  # noqa: E402  (the generated shared copy in ../lib)
import transcript_reader  # noqa: E402  (the generated shared copy in ../lib)
import transcript_sources  # noqa: E402  (the generated shared copy in ../lib)

DEFAULT_TYPES = (
    "discovery:researcher,discovery:explorer,"
    "discovery:intent-tracer,discovery:research-verifier"
)
DISPATCHES_SCHEMA = "audit-sessions.dispatches/v1"


def _is_tool_result(content: object) -> bool:
    return (
        isinstance(content, list)
        and bool(content)
        and all(isinstance(b, dict) and b.get("type") == "tool_result" for b in content)
    )


def analyze(jsonl: Path, ceiling: int) -> dict | None:
    """Return date, turns, hit_ceiling and resumed for one transcript, or None if unreadable."""
    ids: set[str] = set()
    first_ts = None
    stopped = False
    last_stop = None
    resumed = False
    try:
        for rec in transcript_reader.iter_records(jsonl):
            first_ts = first_ts or rec.get("timestamp")
            msg = rec.get("message")
            msg = msg if isinstance(msg, dict) else {}
            if rec.get("type") == "assistant" and msg.get("id"):
                ids.add(msg["id"])
                last_stop = msg.get("stop_reason")
                stopped = stopped or last_stop == "max_turns"
            elif (
                rec.get("type") == "user"
                and (len(ids) >= ceiling or stopped)
                and not _is_tool_result(msg.get("content"))
            ):
                resumed = True
    except OSError:
        return None
    hit = len(ids) >= ceiling or stopped
    return {
        "complete": hit or last_stop not in (None, "tool_use"),
        "date": first_ts[:10]
        if isinstance(first_ts, str) and len(first_ts) >= 10
        else "unknown",
        "turns": len(ids),
        "hit_ceiling": hit,
        "resumed": ("yes" if resumed else "unknown") if hit else "n/a",
    }


def _read_json(path: Path) -> dict | None:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return doc if isinstance(doc, dict) else None


def _derive_data_dir(plugin_root: Path) -> Path | None:
    """`<config>/plugins/data/<plugin@marketplace>` from an installed cache root, else None."""
    version_dir = plugin_root
    plugin_dir = version_dir.parent
    marketplace_dir = plugin_dir.parent
    cache_dir = marketplace_dir.parent
    if cache_dir.name != "cache" or cache_dir.parent.name != "plugins":
        return None
    plugin_id = re.sub(r"[^A-Za-z0-9_-]", "-", f"{plugin_dir.name}@{marketplace_dir.name}")
    return cache_dir.parent / "data" / plugin_id


_SCOPE_RANK = {"user": 0, "project": 1, "local": 2, "managed": 3}
_MANAGED_DIRS = {
    "darwin": Path("/Library/Application Support/ClaudeCode"),
    "linux": Path("/etc/claude-code"),
    "win32": Path(r"C:\Program Files\ClaudeCode"),
}


def _same_dir(a: str, b: Path | None) -> bool:
    if not a or b is None:
        return False
    try:
        return os.path.realpath(os.path.expanduser(a)) == os.path.realpath(b)
    except OSError:
        return False


def _project_dir() -> Path | None:
    env_dir = os.environ.get("CLAUDE_PROJECT_DIR", "").strip()
    if env_dir:
        return Path(env_dir).expanduser()
    try:
        done = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=5,
        )
        if done.returncode == 0 and done.stdout.strip():
            return Path(done.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        return Path.cwd()
    except OSError:
        return None


def _managed_settings_files() -> list[Path]:
    managed_dir = _MANAGED_DIRS.get(sys.platform)
    if managed_dir is None:
        return []
    files = [managed_dir / "managed-settings.json"]
    dropin = managed_dir / "managed-settings.d"
    try:
        names = sorted(n for n in os.listdir(dropin) if n.endswith(".json") and not n.startswith("."))
    except OSError:
        names = []
    files.extend(dropin / name for name in names)
    return files


def _enabled_plugins(config_dir: Path, project_dir: Path | None) -> tuple[bool, dict[str, bool]]:
    """Read `enabledPlugins` across Claude Code's settings layers; `(found, state)`."""
    files = [config_dir / "settings.json", config_dir / "settings.local.json"]
    if project_dir is not None:
        files.extend([project_dir / ".claude" / "settings.json", project_dir / ".claude" / "settings.local.json"])
    session_file = os.environ.get("SESSION_SETTINGS_FILE", "").strip()
    if session_file:
        files.append(Path(session_file).expanduser().resolve())
    files.extend(_managed_settings_files())
    found = False
    state: dict[str, bool] = {}
    for path in files:
        doc = _read_json(path)
        if doc is None:
            continue
        plugins = doc.get("enabledPlugins")
        if isinstance(plugins, dict) and all(isinstance(v, bool) for v in plugins.values()):
            found = True
            state.update(plugins)
    return found, state


def find_session_flow(
    config_dir: Path,
    *,
    script_override: str = "",
    data_dir_override: str = "",
    project_dir: Path | None = None,
) -> tuple[Path, Path] | None:
    """Locate `(scripts/dispatches.py, plugin_data_dir)` for an installed session-flow plugin, else None."""
    if script_override:
        script = Path(script_override).expanduser()
        if not script.is_file():
            return None
        data_dir = Path(data_dir_override).expanduser() if data_dir_override else _derive_data_dir(script.resolve().parents[1])
        return (script, data_dir) if data_dir is not None else None

    registry = _read_json(config_dir / "plugins" / "installed_plugins.json")
    plugins = registry.get("plugins") if registry is not None else None
    if not isinstance(plugins, dict):
        return None

    project = project_dir if project_dir is not None else _project_dir()
    has_enabled, enabled = _enabled_plugins(config_dir, project)
    for plugin_id in sorted(plugins):
        if not isinstance(plugin_id, str):
            continue
        if plugin_id != "session-flow" and not plugin_id.startswith("session-flow@"):
            continue
        if has_enabled and enabled.get(plugin_id) is not True:
            continue
        raw_entries = plugins[plugin_id]
        entries = raw_entries if isinstance(raw_entries, list) else [raw_entries]
        best_rank = -1
        best_script: Path | None = None
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("installPath"), str):
                continue
            scope = entry.get("scope", "user")
            if scope not in _SCOPE_RANK:
                continue
            if scope in ("project", "local") and not _same_dir(str(entry.get("projectPath") or ""), project):
                continue
            script = Path(entry["installPath"]).expanduser() / "scripts" / "dispatches.py"
            if not script.is_file():
                continue
            if _SCOPE_RANK[scope] >= best_rank:
                best_rank = _SCOPE_RANK[scope]
                best_script = script
        if best_script is not None:
            data_dir = (
                Path(data_dir_override).expanduser()
                if data_dir_override
                else config_dir / "plugins" / "data" / re.sub(r"[^A-Za-z0-9_-]", "-", plugin_id)
            )
            return best_script, data_dir
    return None


def read_store(
    script: Path,
    data_dir: Path,
    *,
    sources_file: str,
    agent_type: str,
    since: str | None,
    ceiling: int,
) -> tuple[dict | None, str, str | None]:
    """Invoke session-flow's dispatches.py; `(data, fallback_reason, error)`."""
    argv = [sys.executable or "python3", "-I", str(script), "--data-dir", str(data_dir), "--ceiling", str(ceiling)]
    if sources_file:
        argv += ["--sources-file", sources_file]
    if agent_type:
        argv += ["--agent-type", agent_type]
    if since:
        argv += ["--since", since]
    try:
        done = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", timeout=120)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, "", f"session-flow store reader failed to run: {exc}"
    if done.returncode == 3:
        return None, "no session-flow store yet; run /session-flow:audit-sessions to collect", None
    try:
        envelope = json.loads(done.stdout)
    except ValueError:
        envelope = None
    if done.returncode != 0:
        summary = envelope.get("summary") if isinstance(envelope, dict) else None
        detail = summary or done.stderr.strip() or f"exit {done.returncode}"
        return None, "", f"session-flow store reader failed: {detail}"
    if (
        not isinstance(envelope, dict)
        or envelope.get("schema") != DISPATCHES_SCHEMA
        or not isinstance(envelope.get("data"), dict)
        or not isinstance(envelope["data"].get("dispatches"), list)
        or not isinstance(envelope["data"].get("header"), list)
    ):
        return None, "", "session-flow store reader returned an unexpected payload"
    return envelope["data"], "", None


def scan_local_roots(
    roots: list[Path], wanted: set[str], since: str | None, ceiling: int
) -> tuple[list[dict], int, int]:
    rows: list[dict] = []
    skipped = 0
    unfinished = 0
    for dirpath, _, files in (walked for root in roots for walked in os.walk(root)):
        for name in files:
            if not (name.startswith("agent-") and name.endswith(".jsonl")):
                continue
            meta = Path(dirpath, name[: -len(".jsonl")] + ".meta.json")
            if not meta.is_file():
                continue
            try:
                agent = json.loads(meta.read_text(encoding="utf-8")).get("agentType")
            except (OSError, ValueError, AttributeError):
                skipped += 1
                continue
            if agent not in wanted:
                continue
            info = analyze(Path(dirpath, name), ceiling)
            if info is None:
                skipped += 1
            elif not since or (info["date"][:1].isdigit() and info["date"] >= since):
                if info["complete"]:
                    rows.append({"agentType": agent, **info})
                else:
                    unfinished += 1
    return rows, skipped, unfinished


def percentile(sorted_vals: list[int], p: float) -> int:
    return sorted_vals[max(1, math.ceil(p * len(sorted_vals))) - 1]


def summarize(rows: list[dict]) -> list[dict]:
    out = []
    for agent in sorted({r["agentType"] for r in rows}):
        mine = [r for r in rows if r["agentType"] == agent]
        turns = sorted(r["turns"] for r in mine)
        out.append(
            {
                "agentType": agent,
                "n": len(turns),
                "min": turns[0],
                "p50": percentile(turns, 0.5),
                "p90": percentile(turns, 0.9),
                "max": turns[-1],
                "at_ceiling": sum(r["hit_ceiling"] for r in mine),
            }
        )
    return out


def table(headers: list[str], body: list[list[object]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "|" + "|".join("---" for _ in headers) + "|",
    ]
    lines += ["| " + " | ".join(str(c) for c in row) + " |" for row in body]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", help="one transcripts root; default: session-flow store, else each local source's projects directory")
    ap.add_argument(
        "--agent-type", default=DEFAULT_TYPES, help="comma-separated agentType filter"
    )
    ap.add_argument("--since", type=date.fromisoformat, metavar="YYYY-MM-DD")
    ap.add_argument("--ceiling", type=int, default=40, help="turn ceiling (default 40)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    ap.add_argument("--sources-file", default="", help="a transcript sources file, whose identifiers markdown redacts")
    ap.add_argument("--redact-identifiers", default="", help="comma-separated names and paths markdown also redacts")
    ap.add_argument("--diagnostics-dir", help="write a lookup gap here as a diagnostics record")
    ap.add_argument("--session-flow-script", default="", help="path to session-flow's scripts/dispatches.py")
    ap.add_argument("--session-flow-data-dir", default="", help="path to session-flow's plugin data directory")
    args = ap.parse_args()

    wanted = {t.strip() for t in args.agent_type.split(",") if t.strip()}
    since = args.since.isoformat() if args.since else None
    sources = None
    header: list[str] = []
    rows: list[dict] = []
    skipped = 0
    unfinished = 0

    if args.root:
        roots = [Path(args.root).expanduser()]
        try:
            list(os.scandir(roots[0]))
        except OSError as exc:
            print(f"error: cannot read root {roots[0]}: {exc.strerror}", file=sys.stderr)
            return 2
        rows, skipped, unfinished = scan_local_roots(roots, wanted, since, args.ceiling)
    else:
        try:
            sources = transcript_sources.load(args.sources_file)
        except transcript_sources.SourcesError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        for warning in sources.warnings:
            print(warning, file=sys.stderr)

        sf = find_session_flow(
            Path(transcript_sources.local_config_dir(os.environ)),
            script_override=args.session_flow_script,
            data_dir_override=args.session_flow_data_dir,
        )
        store_data = None
        fallback_reason = "session-flow not installed"
        if sf is not None:
            store_data, fallback_reason, err = read_store(
                sf[0],
                sf[1],
                sources_file=args.sources_file,
                agent_type=args.agent_type,
                since=since,
                ceiling=args.ceiling,
            )
            if err is not None:
                print(f"error: {err}", file=sys.stderr)
                return 2

        if store_data is not None:
            header = ["Source: session-flow store", *store_data["header"]]
            rows = store_data["dispatches"]
            unfinished = int(store_data.get("unfinished") or 0)
        else:
            gaps = transcript_sources.lookup_gaps(
                sources, transcript_sources.retry_argv(__file__, sys.argv[1:])
            )
            diag_path = (
                transcript_sources.write_lookup(args.diagnostics_dir, gaps)
                if args.diagnostics_dir
                else None
            )
            gap_header = transcript_sources.report_header(diag_path, gaps, [])
            unread = {gap.source for gap in gaps}
            roots = [Path(e.config_dir) / "projects" for e in sources.local() if e.name not in unread]
            header = [
                f"Source: local sources ({fallback_reason})",
                *gap_header,
                *(
                    f"Not read by this skill: {entry.name} (remote; this skill reads this host's sources only)"
                    for entry in sources.all()
                    if not entry.is_local
                ),
            ]
            rows, skipped, unfinished = scan_local_roots(roots, wanted, since, args.ceiling)

    rows.sort(key=lambda r: (r["date"], r["agentType"]))
    summary = summarize(rows)
    if skipped:
        print(f"note: {skipped} unreadable transcript(s) skipped", file=sys.stderr)
    if unfinished:
        print(
            f"note: {unfinished} unfinished dispatch(es) excluded "
            "(no final stop_reason, below the ceiling)",
            file=sys.stderr,
        )
    if args.json:
        print(json.dumps({"header": header, "dispatches": rows, "summary": summary}, indent=2))
        return 0
    try:
        publisher = publish.publisher(args.sources_file, args.redact_identifiers, sources=sources)
    except publish.PublishError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    dispatches = (
        table(
            ["date", "agentType", "turns", "hit_ceiling", "resumed"],
            [
                [
                    r["date"],
                    r["agentType"],
                    r["turns"],
                    "yes" if r["hit_ceiling"] else "no",
                    r["resumed"],
                ]
                for r in rows
            ],
        )
    )
    cols = ("agentType", "n", "min", "p50", "p90", "max", "at_ceiling")
    totals = table(list(cols), [[s[k] for k in cols] for s in summary])
    lead = "\n".join(transcript_sources.report_header_md(header)) + ("\n" if header else "")
    print(publisher.redact(f"{lead}{dispatches}\n\n{totals}"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
