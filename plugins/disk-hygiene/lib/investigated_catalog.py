"""Persistent catalog of investigated disk-hygiene entries.

A record is a hint. It never authorizes deletion, never shortens preview, and
never skips revalidation. Identity or descendant-set change drops the old
conclusion. An unanswered owner stays ``keep``.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

CATALOG_JSON_NAME = "catalog.json"
CATALOG_MD_NAME = "CATALOG.md"
DISPOSITIONS = frozenset({"keep", "remove", "review"})
RECORD_SOURCES = frozenset({"engine", "human"})

# Home-directory names that are a recognizable app or config convention.
# Anything else with no protection and no hint is out of place.
RECOGNIZABLE_NAMES = frozenset(
    {
        ".cache",
        ".config",
        ".git",
        ".gnupg",
        ".local",
        ".npm",
        ".ssh",
        "appdata",
        "desktop",
        "documents",
        "downloads",
        "library",
        "music",
        "pictures",
        "videos",
    }
)

INVESTIGATION_SOURCES = (
    "manifests and READMEs",
    "config file contents",
    "Get-Command or the platform equivalent (command -v / Get-Command)",
    "running processes",
    "scheduled tasks",
    "PATH, user and machine",
    "installed programs",
    "git remotes and status",
    "dotfile and settings references",
)


class CatalogError(ValueError):
    """The catalog or an operator answer file is not usable."""


def empty_catalog() -> dict[str, Any]:
    return {"schema_version": 1, "records": []}


def _entry_map(entries: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {
        entry["path"]: entry
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }


def _name(path: str) -> str:
    return path.replace("\\", "/").rstrip("/").split("/")[-1].casefold()


def is_empty_entry(entry: dict[str, Any]) -> bool:
    qualifiers = entry.get("size_qualifiers") or []
    if "not-walked" in qualifiers:
        return False
    return entry.get("logical_size") == 0 and entry.get("kind") in {"file", "directory"}


def is_hinted(entry: dict[str, Any]) -> bool:
    hints = entry.get("hints")
    return isinstance(hints, list) and bool(hints)


def is_out_of_place(entry: dict[str, Any]) -> bool:
    """No protected reason, no hint, and not a recognizable app or config name."""
    reasons = entry.get("protected_reasons") or []
    if reasons or is_hinted(entry):
        return False
    return _name(str(entry.get("path", ""))) not in RECOGNIZABLE_NAMES


def owner_level(path: str, entry: dict[str, Any]) -> str:
    """Immediate children stay themselves. Deeper files collapse to their directory."""
    parts = path.split("/")
    if len(parts) <= 1:
        return path
    if entry.get("kind") == "file":
        return "/".join(parts[:-1])
    return path


def select_catalog_paths(entries: list[dict[str, Any]]) -> list[str]:
    """Immediate children, plus hinted, empty, and out-of-place entries at owner level."""
    by_path = _entry_map(entries)
    chosen: set[str] = set()
    for path, entry in by_path.items():
        if "/" not in path:
            chosen.add(path)
            continue
        if is_hinted(entry) or is_empty_entry(entry) or is_out_of_place(entry):
            chosen.add(owner_level(path, entry))
    return sorted(path for path in chosen if path in by_path)


def identity_of(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "device": entry.get("device"),
        "inode": entry.get("inode"),
        "kind": entry.get("kind"),
    }


def descendant_set(path: str, paths: set[str]) -> list[str]:
    prefix = path + "/"
    return sorted(name for name in paths if name.startswith(prefix))


def identity_holds(record: dict[str, Any], entry: dict[str, Any], paths: set[str]) -> bool:
    ident = record.get("identity")
    if not isinstance(ident, dict) or ident != identity_of(entry):
        return False
    recorded = record.get("descendants")
    if not isinstance(recorded, list):
        return False
    return recorded == descendant_set(str(record.get("path")), paths)


def _blank_record(path: str, entry: dict[str, Any], paths: set[str], run_id: str) -> dict[str, Any]:
    size = entry.get("logical_size")
    return {
        "path": path,
        "identity": identity_of(entry),
        "descendants": descendant_set(path, paths),
        "owner": None,
        "provenance": "",
        "evidence": [],
        "disposition": "keep",
        "tier": None,
        "size": size if isinstance(size, int) else None,
        "first_seen_run": run_id,
        "last_seen_run": run_id,
        "last_verified": run_id,
        "source": "engine",
        "question_open": True,
    }


def load_answers(payload: object) -> dict[str, dict[str, Any]]:
    if not isinstance(payload, dict) or payload.get("version") != 1:
        raise CatalogError("answers version must be 1")
    rows = payload.get("answers")
    if not isinstance(rows, list):
        raise CatalogError("answers must be an array")
    normalized: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("path"), str):
            raise CatalogError("each answer needs a path")
        path = row["path"]
        if path in normalized:
            raise CatalogError(f"duplicate answer: {path}")
        owner = row.get("owner")
        provenance = row.get("provenance")
        if not isinstance(owner, str) or not owner.strip():
            raise CatalogError(f"answer needs an owner: {path}")
        if not isinstance(provenance, str) or not provenance.strip():
            raise CatalogError(f"answer needs provenance: {path}")
        disposition = row.get("disposition", "keep")
        if disposition not in DISPOSITIONS:
            raise CatalogError(f"answer disposition is not keep, remove, or review: {path}")
        evidence = row.get("evidence") or [{"source": "human"}]
        if not isinstance(evidence, list) or not evidence:
            raise CatalogError(f"answer evidence must be a non-empty list: {path}")
        normalized[path] = {
            "owner": owner.strip(),
            "provenance": provenance.strip(),
            "disposition": disposition,
            "evidence": evidence,
        }
    return normalized


def sync_catalog(
    snapshot: dict[str, Any],
    catalog: dict[str, Any] | None,
    run_id: str,
    answers: dict[str, dict[str, Any]] | None = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Return the updated catalog and the lead / unchanged / questions report."""
    book = empty_catalog() if not catalog else catalog
    if book.get("schema_version") != 1 or not isinstance(book.get("records"), list):
        raise CatalogError("catalog schema_version must be 1")
    entries = [
        entry
        for entry in snapshot.get("entries", [])
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    ]
    by_path = _entry_map(entries)
    paths = set(by_path)
    previous = {
        record["path"]: record
        for record in book["records"]
        if isinstance(record, dict) and isinstance(record.get("path"), str)
    }
    lead: list[dict[str, Any]] = []
    unchanged: list[dict[str, Any]] = []
    questions: list[dict[str, Any]] = []
    records: list[dict[str, Any]] = []
    for path in select_catalog_paths(entries):
        entry = by_path[path]
        prior = previous.get(path)
        if prior is None:
            record = _blank_record(path, entry, paths, run_id)
            change = "new"
        elif not identity_holds(prior, entry, paths):
            record = _blank_record(path, entry, paths, run_id)
            record["first_seen_run"] = prior.get("first_seen_run") or run_id
            change = "invalidated"
        else:
            record = dict(prior)
            record["descendants"] = descendant_set(path, paths)
            record["last_seen_run"] = run_id
            record["last_verified"] = run_id
            size = entry.get("logical_size")
            record["size"] = size if isinstance(size, int) else record.get("size")
            change = None
        answer = (answers or {}).get(path)
        if answer and identity_holds(record, entry, paths):
            record["owner"] = answer["owner"]
            record["provenance"] = answer["provenance"]
            record["evidence"] = answer["evidence"]
            record["disposition"] = answer["disposition"]
            record["source"] = "human"
            record["question_open"] = False
            if change is None:
                change = "answered"
        if record.get("question_open") or not record.get("owner"):
            record["disposition"] = "keep"
            record["question_open"] = True
            questions.append(
                {
                    "path": path,
                    "question": f"Who owns {path}?",
                }
            )
        elif record.get("source") == "human":
            record["question_open"] = False
        records.append(record)
        row = {
            "path": path,
            "disposition": record["disposition"],
            "owner": record.get("owner"),
            "source": record["source"],
        }
        if change is None:
            unchanged.append(row)
        else:
            lead.append({**row, "change": change})
    updated = {"schema_version": 1, "records": records}
    report = {
        "status": "catalog-synced",
        "run_id": run_id,
        "lead": lead,
        "unchanged": unchanged,
        "questions": questions,
        "investigation_sources": list(INVESTIGATION_SOURCES),
    }
    return updated, report


def annotate_snapshot(snapshot: dict[str, Any], catalog: dict[str, Any]) -> None:
    """Set ``prior_disposition`` only while identity and descendants still hold."""
    entries = [
        entry
        for entry in snapshot.get("entries", [])
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    ]
    paths = {entry["path"] for entry in entries}
    by_record = {
        record["path"]: record
        for record in catalog.get("records", [])
        if isinstance(record, dict) and isinstance(record.get("path"), str)
    }
    for entry in entries:
        record = by_record.get(entry["path"])
        if record and identity_holds(record, entry, paths):
            entry["prior_disposition"] = record.get("disposition")
        else:
            entry.pop("prior_disposition", None)


def render_markdown(catalog: dict[str, Any]) -> str:
    lines = [
        "# Investigated catalog",
        "",
        "A row is a hint. It does not authorize deletion.",
        "",
        "| Path | Owner | Disposition | Source | Question |",
        "|---|---|---|---|---|",
    ]
    for record in catalog.get("records", []):
        owner = record.get("owner") or "unknown"
        question = "open" if record.get("question_open") else "answered"
        lines.append(
            f"| {record.get('path')} | {owner} | {record.get('disposition')} | "
            f"{record.get('source')} | {question} |"
        )
    lines.append("")
    return "\n".join(lines)


def write_catalog(data_root: Path, catalog: dict[str, Any]) -> tuple[Path, Path]:
    data_root.mkdir(parents=True, exist_ok=True)
    json_path = data_root / CATALOG_JSON_NAME
    md_path = data_root / CATALOG_MD_NAME
    json_path.write_text(
        json.dumps(catalog, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    md_path.write_text(render_markdown(catalog), encoding="utf-8")
    return json_path, md_path


def read_catalog(data_root: Path) -> dict[str, Any] | None:
    path = data_root / CATALOG_JSON_NAME
    if not path.is_file():
        return None
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise CatalogError("catalog root must be an object")
    return payload
