#!/usr/bin/env python3
"""Manage registry.json for the /claude-troubleshooting skill.

Zero external dependencies — stdlib only.

Usage:
    python registry_manager.py <action> [args] [--flags]

Actions:
    list      List issues, optionally filtered
    get       Find issue by number or fuzzy query
    add       Add new issue to registry
    update    Update fields on existing issue
    remove    Remove issue by number
    validate  Schema validation of registry.json
    stats     Summary dashboard

Exit codes:
    0 = success
    1 = not found
    2 = validation / input error
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from collections import Counter
from datetime import date, datetime
from pathlib import Path
from typing import Any

# ── Constants ───────────────────────────────────────────────────

VALID_CATEGORIES: set[str] = {
    "blocking",
    "degraded",
    "cosmetic",
    "fixed",
    "feature-request",
    "informational",
}

VALID_STATUSES: set[str] = {"open", "closed"}

REQUIRED_FIELDS: set[str] = {
    "number",
    "repo",
    "title",
    "url",
    "category",
    "status",
    "feature",
    "impact",
    "last_checked",
    "added",
}

REGISTRY_FILENAME = "registry.json"

_MUTATING_ACTIONS = frozenset({"add", "update", "remove"})


# ── Data access ─────────────────────────────────────────────────


def load_registry(data_dir: Path) -> dict[str, Any]:
    """Load and parse registry.json."""
    path = data_dir / REGISTRY_FILENAME
    if not path.exists():
        return {"version": 1, "schema_notes": "", "issues": []}
    try:
        text = path.read_text(encoding="utf-8")
        data = json.loads(text)
    except (json.JSONDecodeError, OSError) as exc:
        print(f"Error reading {path}: {exc}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(data.get("issues"), list):
        print(
            f"Invalid schema: 'issues' must be a list in {path}",
            file=sys.stderr,
        )
        sys.exit(2)
    return data


def save_registry(data_dir: Path, data: dict[str, Any]) -> None:
    """Atomic write: temp file, fsync, close, os.replace."""
    target = data_dir / REGISTRY_FILENAME
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        suffix=".tmp",
        prefix=".registry_",
        dir=data_dir,
        delete=False,
    ) as tmp_fd:
        temp_path = Path(tmp_fd.name)
        try:
            json.dump(data, tmp_fd, indent=2)
            tmp_fd.write("\n")
            tmp_fd.flush()
            os.fsync(tmp_fd.fileno())
        except Exception:
            temp_path.unlink(missing_ok=True)
            raise
    try:
        temp_path.replace(target)
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise


# ── Lookup helpers ──────────────────────────────────────────────


def find_by_key(
    issues: list[dict[str, Any]],
    number: int,
    repo: str | None = None,
) -> list[dict[str, Any]]:
    """Match by issue number, narrowed by repo when given.

    GitHub issue numbers are only unique within a repo, so identity is
    (repo, number); a bare number may legitimately match several entries.
    """
    matches = [i for i in issues if i.get("number") == number]
    if repo is not None:
        matches = [i for i in matches if i.get("repo") == repo]
    return matches


def _searchable_text(issue: dict[str, Any]) -> str:
    """Build lowercase search corpus from issue fields."""
    parts = [
        str(issue.get("number", "")),
        issue.get("title", ""),
        issue.get("feature", ""),
        issue.get("impact", ""),
        issue.get("workaround", "") or "",
        issue.get("blocked_work", "") or "",
    ]
    return " ".join(parts).lower()


def find_by_query(
    issues: list[dict[str, Any]],
    query: str,
) -> list[dict[str, Any]]:
    """Fuzzy case-insensitive substring match."""
    query_lower = query.lower()
    return [i for i in issues if query_lower in _searchable_text(i)]


# ── Validation helpers ──────────────────────────────────────────


def validate_issue(issue: dict[str, Any], index: int) -> list[str]:
    """Validate a single issue entry. Returns list of error strings."""
    errors: list[str] = []
    prefix = f"issues[{index}]"

    for field in REQUIRED_FIELDS:
        if field not in issue:
            errors.append(f"{prefix}: missing required field '{field}'")

    num = issue.get("number")
    if num is not None and not isinstance(num, int):
        errors.append(f"{prefix}: 'number' must be int, got {type(num).__name__}")

    cat = issue.get("category")
    if cat is not None and cat not in VALID_CATEGORIES:
        valid = ", ".join(sorted(VALID_CATEGORIES))
        errors.append(f"{prefix}: invalid category '{cat}'. Valid: {valid}")

    status = issue.get("status")
    if status is not None and status not in VALID_STATUSES:
        valid = ", ".join(sorted(VALID_STATUSES))
        errors.append(f"{prefix}: invalid status '{status}'. Valid: {valid}")

    url = issue.get("url", "")
    if url and not url.startswith("https://github.com/"):
        errors.append(f"{prefix}: url must start with https://github.com/")

    for date_field in ("last_checked", "added"):
        val = issue.get(date_field)
        if val is not None:
            try:
                date.fromisoformat(val)
            except (ValueError, TypeError):
                errors.append(f"{prefix}: invalid date in '{date_field}': {val}")

    # closedAt carries GitHub's raw timestamp (e.g. 2026-01-01T00:00:00Z);
    # accept a bare date too.
    closed = issue.get("closedAt")
    if closed is not None:
        try:
            datetime.fromisoformat(str(closed).replace("Z", "+00:00"))
        except (ValueError, TypeError):
            errors.append(
                f"{prefix}: invalid date/datetime in 'closedAt': {closed}"
            )

    affected = issue.get("affected_files")
    if affected is not None and not isinstance(affected, list):
        errors.append(f"{prefix}: 'affected_files' must be a list")

    related = issue.get("related")
    if related is not None and not isinstance(related, list):
        errors.append(f"{prefix}: 'related' must be a list")

    return errors


# ── Result helpers ──────────────────────────────────────────────


def _ok(action: str, message: str, data: Any) -> dict[str, Any]:
    return {
        "status": "ok",
        "action": action,
        "message": message,
        "data": data,
    }


def _not_found(action: str, message: str) -> dict[str, Any]:
    return {
        "status": "not_found",
        "action": action,
        "message": message,
        "data": {},
    }


def _error(action: str, message: str, data: Any = None) -> dict[str, Any]:
    return {
        "status": "error",
        "action": action,
        "message": message,
        "data": data if data is not None else {},
    }


def _invalid_choice(
    action: str, field: str, value: str, valid: set[str]
) -> dict[str, Any]:
    """Error result for an out-of-set category/status value."""
    choices = ", ".join(sorted(valid))
    return _error(action, f"Invalid {field} '{value}'. Valid: {choices}")


# ── Actions ─────────────────────────────────────────────────────


def action_list(
    issues: list[dict[str, Any]],
    *,
    category_filter: str | None = None,
    status_filter: str | None = None,
    feature_filter: str | None = None,
    stale_days: int | None = None,
) -> dict[str, Any]:
    """Filter and return issues."""
    filtered = issues

    if category_filter:
        filtered = [i for i in filtered if i.get("category") == category_filter]
    if status_filter:
        filtered = [i for i in filtered if i.get("status") == status_filter]
    if feature_filter:
        feat = feature_filter.lower()
        filtered = [i for i in filtered if feat in (i.get("feature", "")).lower()]
    if stale_days is not None:
        today = date.today()
        stale: list[dict[str, Any]] = []
        for i in filtered:
            checked = i.get("last_checked")
            if checked:
                try:
                    checked_date = date.fromisoformat(checked)
                    if (today - checked_date).days >= stale_days:
                        stale.append(i)
                except (ValueError, TypeError):
                    stale.append(i)
            else:
                stale.append(i)
        filtered = stale

    msg = f"Found {len(filtered)} issues"
    return _ok(
        "list",
        msg,
        {
            "issues": filtered,
            "total": len(filtered),
        },
    )


def action_get(
    issues: list[dict[str, Any]],
    query: str,
    repo: str | None = None,
) -> dict[str, Any]:
    """Find issue(s) by number or fuzzy query."""
    try:
        number = int(query)
        matches = find_by_key(issues, number, repo)
        if len(matches) == 1:
            return _ok("get", f"Found issue #{number}", {"issue": matches[0]})
        if matches:
            return _ok(
                "get",
                f"#{number} matches {len(matches)} repos — pass --repo",
                {"issues": matches, "count": len(matches)},
            )
        return _not_found("get", f"No issue with number {number}")
    except ValueError:
        pass

    matches = find_by_query(issues, query)
    if not matches:
        return _not_found("get", f"No issue matching '{query}'")
    if len(matches) == 1:
        return _ok("get", "Found 1 issue", {"issue": matches[0]})
    return _ok(
        "get",
        f"Found {len(matches)} issues",
        {"issues": matches, "count": len(matches)},
    )


def action_add(
    data: dict[str, Any],
    *,
    number: int,
    repo: str,
    title: str,
    url: str,
    category: str,
    feature: str,
    impact: str,
    status: str = "open",
    workaround: str | None = None,
    affected_files: list[str] | None = None,
    blocked_work: str | None = None,
    related: list[int] | None = None,
) -> dict[str, Any]:
    """Add new issue with duplicate detection."""
    if category not in VALID_CATEGORIES:
        return _invalid_choice("add", "category", category, VALID_CATEGORIES)
    if status not in VALID_STATUSES:
        return _invalid_choice("add", "status", status, VALID_STATUSES)
    if find_by_key(data["issues"], number, repo):
        return _error("add", f"Duplicate: {repo}#{number} already exists")

    today = date.today().isoformat()
    new_issue: dict[str, Any] = {
        "number": number,
        "repo": repo,
        "title": title,
        "url": url,
        "category": category,
        "status": status,
        "feature": feature,
        "impact": impact,
        "workaround": workaround,
        "affected_files": affected_files or [],
        "blocked_work": blocked_work,
        "last_checked": today,
        "added": today,
    }
    if related:
        new_issue["related"] = related

    data["issues"].append(new_issue)
    return _ok("add", f"Added issue #{number}", {"issue": new_issue})


def action_update(
    data: dict[str, Any],
    number: int,
    repo: str | None = None,
    **updates: Any,
) -> dict[str, Any]:
    """Update fields on existing issue."""
    matches = find_by_key(data["issues"], number, repo)
    if not matches:
        return _not_found("update", f"No issue with number {number}")
    if len(matches) > 1:
        repos = ", ".join(str(i.get("repo")) for i in matches)
        return _error(
            "update",
            f"#{number} is ambiguous across repos ({repos}) — pass --repo",
        )
    issue = matches[0]

    if "category" in updates and updates["category"] not in VALID_CATEGORIES:
        return _invalid_choice(
            "update", "category", updates["category"], VALID_CATEGORIES
        )
    if "status" in updates and updates["status"] not in VALID_STATUSES:
        return _invalid_choice("update", "status", updates["status"], VALID_STATUSES)

    changed: list[str] = []
    for key, value in updates.items():
        if value is not None and issue.get(key) != value:
            issue[key] = value
            changed.append(key)

    if not changed:
        return _ok("update", f"Issue #{number}: no changes", {"issue": issue})
    return _ok(
        "update",
        f"Issue #{number}: updated {', '.join(changed)}",
        {"issue": issue, "changed": changed},
    )


def action_remove(
    data: dict[str, Any],
    number: int,
    repo: str | None = None,
) -> dict[str, Any]:
    """Remove issue by (repo, number)."""
    matches = find_by_key(data["issues"], number, repo)
    if not matches:
        return _not_found("remove", f"No issue with number {number}")
    if len(matches) > 1:
        repos = ", ".join(str(i.get("repo")) for i in matches)
        return _error(
            "remove",
            f"#{number} is ambiguous across repos ({repos}) — pass --repo",
        )
    issue = matches[0]
    data["issues"] = [i for i in data["issues"] if i is not issue]
    return _ok("remove", f"Removed issue #{number}", {"removed": issue})


def action_validate(
    issues: list[dict[str, Any]],
) -> dict[str, Any]:
    """Validate all issues in registry."""
    all_errors: list[str] = []
    keys_seen: set[tuple[str, int]] = set()

    for idx, issue in enumerate(issues):
        errors = validate_issue(issue, idx)
        all_errors.extend(errors)

        num = issue.get("number")
        if isinstance(num, int):
            key = (str(issue.get("repo", "")), num)
            if key in keys_seen:
                all_errors.append(
                    f"issues[{idx}]: duplicate (repo, number) {key}"
                )
            keys_seen.add(key)

    if all_errors:
        return _error(
            "validate",
            f"Found {len(all_errors)} validation errors",
            {"errors": all_errors, "total_issues": len(issues)},
        )
    return _ok(
        "validate",
        f"All {len(issues)} issues pass validation",
        {"total_issues": len(issues)},
    )


def action_stats(
    issues: list[dict[str, Any]],
) -> dict[str, Any]:
    """Summary dashboard."""
    by_category: Counter[str] = Counter(i.get("category", "unknown") for i in issues)
    by_status: Counter[str] = Counter(i.get("status", "unknown") for i in issues)
    stale_count = 0
    today = date.today()

    for issue in issues:
        checked = issue.get("last_checked")
        if checked:
            try:
                checked_date = date.fromisoformat(checked)
                if (today - checked_date).days >= 7:
                    stale_count += 1
            except (ValueError, TypeError):
                stale_count += 1

    blocking = [
        {
            "number": i["number"],
            "title": i.get("title", ""),
            "feature": i.get("feature", ""),
        }
        for i in issues
        if i.get("category") == "blocking" and i.get("status") == "open"
    ]

    parts = [f"{len(issues)} issues", f"{stale_count} stale (>7d)"]
    if blocking:
        parts.append(f"{len(blocking)} open blocking")

    return _ok(
        "stats",
        ", ".join(parts),
        {
            "total": len(issues),
            "by_category": dict(by_category),
            "by_status": dict(by_status),
            "stale_count": stale_count,
            "open_blocking": blocking,
        },
    )


# ── CLI ─────────────────────────────────────────────────────────


def build_parser() -> argparse.ArgumentParser:
    """Build argparse parser with subcommands."""
    parser = argparse.ArgumentParser(
        description="Manage registry.json for the /claude-troubleshooting skill.",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=None,
        help="Override path to registry.json directory",
    )
    sub = parser.add_subparsers(dest="action", required=True)

    # list
    p_list = sub.add_parser("list", help="List issues, optionally filtered")
    p_list.add_argument("--category", choices=sorted(VALID_CATEGORIES))
    p_list.add_argument("--status", choices=sorted(VALID_STATUSES))
    p_list.add_argument("--feature", help="Filter by feature substring")
    p_list.add_argument(
        "--stale",
        type=int,
        metavar="DAYS",
        help="Only issues not checked in N days",
    )

    # get
    p_get = sub.add_parser("get", help="Find issue by number or fuzzy query")
    p_get.add_argument("query", help="Issue number (int) or search text")
    p_get.add_argument(
        "--repo", help="owner/repo (disambiguates a bare number)"
    )

    # add
    p_add = sub.add_parser("add", help="Add new issue to registry")
    p_add.add_argument("number", type=int, help="GitHub issue number")
    p_add.add_argument("--repo", required=True, help="owner/repo")
    p_add.add_argument("--title", required=True, help="Issue title")
    p_add.add_argument("--url", required=True, help="Issue URL")
    p_add.add_argument(
        "--category",
        required=True,
        choices=sorted(VALID_CATEGORIES),
    )
    p_add.add_argument("--feature", required=True, help="Feature area")
    p_add.add_argument("--impact", required=True, help="Impact description")
    p_add.add_argument(
        "--status",
        default="open",
        choices=sorted(VALID_STATUSES),
    )
    p_add.add_argument("--workaround", help="Known workaround")
    p_add.add_argument(
        "--affected-files",
        help="Comma-separated file paths",
    )
    p_add.add_argument("--blocked-work", help="What work is blocked")
    p_add.add_argument(
        "--related",
        help="Comma-separated related issue numbers",
    )

    # update
    p_up = sub.add_parser("update", help="Update existing issue")
    p_up.add_argument("number", type=int, help="Issue number to update")
    p_up.add_argument(
        "--repo", help="owner/repo (disambiguates a bare number)"
    )
    p_up.add_argument("--category", choices=sorted(VALID_CATEGORIES))
    p_up.add_argument("--status", choices=sorted(VALID_STATUSES))
    p_up.add_argument("--stateReason", help="Reason for closure")
    p_up.add_argument("--closedAt", help="Closure date (YYYY-MM-DD)")
    p_up.add_argument("--workaround", help="Updated workaround")
    p_up.add_argument(
        "--blocked-work",
        dest="blocked_work",
        help="Updated blocked work",
    )
    p_up.add_argument("--impact", help="Updated impact")
    p_up.add_argument(
        "--last-checked",
        dest="last_checked",
        help="Date last checked (YYYY-MM-DD), default: today",
    )
    p_up.add_argument(
        "--affected-files",
        dest="affected_files",
        help="Comma-separated file paths (replaces existing)",
    )
    p_up.add_argument(
        "--related",
        help="Comma-separated related issue numbers (replaces existing)",
    )

    # remove
    p_rm = sub.add_parser("remove", help="Remove issue by (repo, number)")
    p_rm.add_argument("number", type=int, help="Issue number to remove")
    p_rm.add_argument(
        "--repo", help="owner/repo (disambiguates a bare number)"
    )

    # validate
    sub.add_parser("validate", help="Validate registry.json schema")

    # stats
    sub.add_parser("stats", help="Summary dashboard")

    return parser


def _parse_csv_strings(raw: str | None) -> list[str] | None:
    if not raw:
        return None
    return [s.strip() for s in raw.split(",") if s.strip()]


def _parse_csv_ints(raw: str | None) -> list[int] | None:
    if not raw:
        return None
    result: list[int] = []
    for s in raw.split(","):
        s = s.strip()
        if s:
            try:
                result.append(int(s))
            except ValueError:
                print(f"Warning: ignoring non-integer '{s}'", file=sys.stderr)
    return result if result else None


def output_result(
    result: dict[str, Any],
    exit_code: int = 0,
) -> None:
    """Print JSON to stdout and exit."""
    print(json.dumps(result, indent=2))
    sys.exit(exit_code)


def resolve_data_dir(cli_data_dir: Path | None) -> Path:
    """Resolve the registry directory.

    Precedence: --data-dir flag, then the CLAUDE_PLUGIN_DATA directory the
    harness provisions for this plugin (survives plugin updates), then its
    conventional location under ~/.claude/plugins/data/. Never the plugin's
    own install directory — that is replaced on every update.
    """
    if cli_data_dir:
        return cli_data_dir.resolve()
    env_dir = os.environ.get("CLAUDE_PLUGIN_DATA")
    data_dir = (
        Path(env_dir).resolve()
        if env_dir
        else Path.home() / ".claude" / "plugins" / "data" / "claude-ops"
    )
    data_dir.mkdir(parents=True, exist_ok=True)
    return data_dir


def main() -> None:
    """Entry point."""
    parser = build_parser()
    args = parser.parse_args()
    data_dir = resolve_data_dir(args.data_dir)

    data = load_registry(data_dir)
    issues = data["issues"]

    match args.action:
        case "stats":
            result = action_stats(issues)
        case "list":
            result = action_list(
                issues,
                category_filter=args.category,
                status_filter=args.status,
                feature_filter=args.feature,
                stale_days=args.stale,
            )
        case "get":
            result = action_get(issues, args.query, repo=args.repo)
        case "add":
            result = action_add(
                data,
                number=args.number,
                repo=args.repo,
                title=args.title,
                url=args.url,
                category=args.category,
                feature=args.feature,
                impact=args.impact,
                status=args.status,
                workaround=args.workaround,
                affected_files=_parse_csv_strings(args.affected_files),
                blocked_work=args.blocked_work,
                related=_parse_csv_ints(args.related),
            )
        case "update":
            updates: dict[str, Any] = {
                "last_checked": args.last_checked or date.today().isoformat(),
            }
            for key in (
                "category",
                "status",
                "stateReason",
                "closedAt",
                "workaround",
                "impact",
                "blocked_work",
            ):
                if value := getattr(args, key):
                    updates[key] = value
            if args.affected_files:
                updates["affected_files"] = _parse_csv_strings(args.affected_files)
            if args.related:
                updates["related"] = _parse_csv_ints(args.related)
            result = action_update(data, args.number, repo=args.repo, **updates)
        case "remove":
            result = action_remove(data, args.number, repo=args.repo)
        case "validate":
            result = action_validate(issues)
        case _:
            msg = f"Unknown action: {args.action}"
            raise ValueError(msg)

    if args.action in _MUTATING_ACTIONS and result["status"] == "ok":
        save_registry(data_dir, data)

    exit_code = {"not_found": 1, "error": 2}.get(result["status"], 0)
    output_result(result, exit_code)


if __name__ == "__main__":
    main()
