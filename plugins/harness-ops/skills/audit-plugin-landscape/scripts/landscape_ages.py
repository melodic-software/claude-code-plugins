#!/usr/bin/env python3
"""Read-only age and flag report for installed plugins and known marketplaces.

For every installed plugin and every known marketplace this engine reports the
date of the last upstream commit touching the plugin's source path (the
marketplace's own manifest for a marketplace) and the flags below. It writes
nothing, files nothing and changes no installed state; its only side effect is
read-only ``gh api`` GET calls, which it issues concurrently and de-duplicated
per endpoint.

Flags: ``stale`` (no upstream commit in STALE_DAYS or more), ``archived``,
``moved`` (the repository now answers under a different name),
``repo-missing`` (the repository returns 404) and ``path-missing`` (the source
path no longer exists upstream). A call that fails for any other reason leaves
the row ``unknown`` with the error; it is never read as a flag.

Python 3.11+.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Callable
from urllib.parse import quote

MIN_PYTHON = (3, 11)
STALE_DAYS = 60
MARKETPLACE_MANIFEST = ".claude-plugin/marketplace.json"

# An api callable takes an endpoint and returns (http_status, parsed_body).
Api = Callable[[str], tuple[int, object]]


def gh_api(endpoint: str) -> tuple[int, object]:
    """One read-only ``gh api`` GET. Status 0 means the call could not be made."""
    try:
        proc = subprocess.run(
            ["gh", "api", endpoint], capture_output=True, text=True, timeout=60
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 0, str(exc)
    if proc.returncode == 0:
        try:
            return 200, json.loads(proc.stdout or "null")
        except json.JSONDecodeError:
            return 0, "unparsable response"
    match = re.search(r"HTTP (\d{3})", proc.stderr)
    return (int(match.group(1)) if match else 0), proc.stderr.strip()


def github_repo(source: object) -> str | None:
    """owner/name from a marketplace or plugin source, or None when not GitHub."""
    if isinstance(source, str):
        match = re.search(r"github\.com[/:]([^/]+/[^/]+?)(?:\.git)?/?$", source)
        return match.group(1) if match else None
    if isinstance(source, dict):
        if source.get("repo"):
            return str(source["repo"])
        return github_repo(source.get("url") or "")
    return None


def build_rows(installed: dict, known: dict, manifests: dict[str, dict]) -> list[dict]:
    """Rows to check. ``manifests`` maps a marketplace name to its marketplace.json."""
    rows: list[dict] = []
    for name, entry in sorted(known.items()):
        repo = github_repo(entry.get("source"))
        rows.append(
            {"kind": "marketplace", "id": name, "repo": repo, "path": MARKETPLACE_MANIFEST}
        )
    for key in sorted(installed.get("plugins", {})):
        plugin, _, market = key.partition("@")
        entry = next(
            (p for p in manifests.get(market, {}).get("plugins", []) if p.get("name") == plugin),
            None,
        )
        repo = github_repo(known.get(market, {}).get("source"))
        path, reason = "", None
        if entry is None:
            repo, reason = None, "not listed in the marketplace manifest, or the manifest is unreadable"
        else:
            src = entry.get("source")
            if isinstance(src, str):
                if not src.startswith(("./", "/")):
                    root = str(manifests[market].get("metadata", {}).get("pluginRoot", ""))
                    src = f"{root}/{src}"
                path = src.removeprefix("./").strip("/")
            else:
                repo = github_repo(src)
                path = str((src or {}).get("path", "")).strip("/")
                if repo is None:
                    reason = "plugin source is not a GitHub repository"
        rows.append({"kind": "plugin", "id": key, "repo": repo, "path": path, "reason": reason})
    return rows


def endpoints_for(row: dict) -> dict[str, str]:
    repo, path = row["repo"], row["path"]
    eps = {"repo": f"repos/{repo}"}
    if path:
        eps["commits"] = f"repos/{repo}/commits?path={quote(path, safe='')}&per_page=1"
        eps["contents"] = f"repos/{repo}/contents/{quote(path, safe='/')}"
    else:
        eps["commits"] = f"repos/{repo}/commits?per_page=1"
    return eps


def fetch_all(rows: list[dict], api: Api, workers: int = 8) -> dict[str, tuple[int, object]]:
    """Fetch every distinct endpoint once, concurrently."""
    wanted = sorted({ep for r in rows if r["repo"] for ep in endpoints_for(r).values()})
    with ThreadPoolExecutor(max_workers=workers) as pool:
        return dict(zip(wanted, pool.map(api, wanted)))


def evaluate(row: dict, fetched: dict[str, tuple[int, object]], today: date) -> dict:
    out = {
        "kind": row["kind"], "id": row["id"], "repo": row["repo"], "path": row["path"],
        "last_commit": None, "age_days": None, "flags": [], "unknown": None,
    }
    if not row["repo"]:
        out["unknown"] = row.get("reason") or "source is not a GitHub repository"
        return out
    eps = endpoints_for(row)
    repo_status, repo_body = fetched[eps["repo"]]
    if repo_status == 404:
        out["flags"].append("repo-missing")
        return out
    if repo_status != 200 or not isinstance(repo_body, dict):
        detail = str(repo_body).strip()[:200]
        out["unknown"] = f"repository lookup failed (status {repo_status}): {detail}"
        return out
    if repo_body.get("archived"):
        out["flags"].append("archived")
    full = str(repo_body.get("full_name", ""))
    if full and full.lower() != row["repo"].lower():
        out["flags"].append("moved")
        out["moved_to"] = full

    if "contents" in eps:
        status, _ = fetched[eps["contents"]]
        if status == 404:
            out["flags"].append("path-missing")
        elif status != 200:
            out["unknown"] = f"path lookup failed (status {status})"
    status, body = fetched[eps["commits"]]
    if status == 200 and isinstance(body, list) and body:
        stamp = body[0].get("commit", {}).get("committer", {}).get("date", "")
        try:
            last = datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone(timezone.utc)
        except ValueError:
            out["unknown"] = out["unknown"] or "unreadable commit date"
        else:
            out["last_commit"] = last.date().isoformat()
            out["age_days"] = (today - last.date()).days
            if out["age_days"] >= STALE_DAYS:
                out["flags"].append("stale")
    elif status == 200:
        if "path-missing" not in out["flags"]:
            out["flags"].append("path-missing")
    elif status != 404:
        out["unknown"] = out["unknown"] or f"commit lookup failed (status {status})"
    return out


def run(installed: dict, known: dict, manifests: dict, api: Api, today: date) -> list[dict]:
    rows = build_rows(installed, known, manifests)
    fetched = fetch_all(rows, api)
    return [evaluate(r, fetched, today) for r in rows]


def _load(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def main(argv: list[str] | None = None) -> int:
    if sys.version_info < MIN_PYTHON:
        print(f"error: Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required", file=sys.stderr)
        return 2
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--plugins-dir", default=str(Path.home() / ".claude" / "plugins"))
    ap.add_argument("--today", help="YYYY-MM-DD override, for reproducible runs")
    args = ap.parse_args(argv)
    base = Path(args.plugins_dir)
    installed = _load(base / "installed_plugins.json")
    known = _load(base / "known_marketplaces.json")
    if not installed or not known:
        print("error: installed_plugins.json or known_marketplaces.json missing or unreadable", file=sys.stderr)
        return 2
    manifests = {
        name: _load(Path(e.get("installLocation", "")) / MARKETPLACE_MANIFEST)
        for name, e in known.items()
    }
    today = date.fromisoformat(args.today) if args.today else datetime.now(timezone.utc).date()
    results = run(installed, known, manifests, gh_api, today)
    checked = [r for r in results if r["repo"]]
    if checked and all("(status 0)" in (r["unknown"] or "") for r in checked):
        print(
            "error: no repository could be checked (gh missing, unauthenticated or offline): "
            + (checked[0]["unknown"] or ""),
            file=sys.stderr,
        )
        return 3
    json.dump(results, sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
