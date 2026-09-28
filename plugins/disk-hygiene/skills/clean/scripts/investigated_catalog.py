"""Investigated-entry catalog for disk-hygiene.

A record remembers what an investigation concluded. It is a hint. Nothing in
this module grants deletion authority, and preview and apply do not read it.
"""

from __future__ import annotations

import re
from typing import Any

CATALOG_VERSION = 1
DISPOSITIONS = frozenset({"keep", "remove", "review"})
RECORD_SOURCES = frozenset({"engine", "human"})
# The local investigation procedure. Each evidence item names one of these.
INVESTIGATION_SOURCES = frozenset(
    {
        "manifest",
        "readme",
        "config",
        "command-resolution",
        "running-process",
        "scheduled-task",
        "path",
        "installed-program",
        "git",
        "dotfile-reference",
    }
)
# Basenames a reader can place without an investigation. An entry whose path
# does not meet one of these, and that has no hint and no protected reason, is
# out of place and must be catalogued.
RECOGNIZABLE = frozenset(
    {
        ".aws",
        ".azure",
        ".bash_profile",
        ".bashrc",
        ".cache",
        ".cargo",
        ".config",
        ".docker",
        ".editorconfig",
        ".git",
        ".gitconfig",
        ".github",
        ".gitignore",
        ".gnupg",
        ".idea",
        ".kube",
        ".local",
        ".npm",
        ".npmrc",
        ".nvm",
        ".profile",
        ".pyenv",
        ".pypirc",
        ".rustup",
        ".ssh",
        ".vscode",
        ".zshrc",
        "AppData",
        "Application Data",
        "Applications",
        "Desktop",
        "Documents",
        "Downloads",
        "Library",
        "Music",
        "Pictures",
        "Videos",
        "bin",
        "node_modules",
        "src",
    }
)


def grants_deletion_authority(record: dict[str, Any] | None) -> bool:
    """A catalog disposition never authorizes deletion, preview, or apply."""
    del record
    return False


def descendant_set(path: str, entries: list[dict[str, Any]]) -> list[str]:
    """Inventoried paths strictly below ``path``, in stable order."""
    prefix = f"{path}/"
    return sorted(
        entry["path"]
        for entry in entries
        if isinstance(entry.get("path"), str) and entry["path"].startswith(prefix)
    )


def identity_of(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "device": entry.get("device"),
        "inode": entry.get("inode"),
        "kind": entry.get("kind"),
    }


def identity_holds(
    record: dict[str, Any], entry: dict[str, Any], entries: list[dict[str, Any]]
) -> bool:
    """False when the device, inode, kind, or descendant set changed.

    A moved inode or a changed child set means the thing being described is not
    the thing that was described, so the record is not evidence for this entry.
    """
    stored = record.get("identity")
    if not isinstance(stored, dict):
        return False
    if stored.get("device") != entry.get("device"):
        return False
    if stored.get("inode") != entry.get("inode"):
        return False
    if stored.get("kind") != entry.get("kind"):
        return False
    stored_descendants = record.get("descendant_set")
    if not isinstance(stored_descendants, list):
        return False
    return stored_descendants == descendant_set(str(record.get("path")), entries)


def _recognizable(name: str) -> bool:
    return name in RECOGNIZABLE


def _empty(entry: dict[str, Any]) -> bool:
    qualifiers = entry.get("size_qualifiers") or []
    if "not-walked" in qualifiers:
        return False
    return entry.get("logical_size") == 0


def _out_of_place(entry: dict[str, Any]) -> bool:
    if entry.get("protected_reasons") or entry.get("hints"):
        return False
    parts = str(entry.get("path", "")).split("/")
    return not any(_recognizable(part) for part in parts if part)


def scope_paths(entries: list[dict[str, Any]]) -> dict[str, str]:
    """Paths to catalogue, mapped to why they are in scope.

    Every immediate child is included. Hinted, empty, and out-of-place entries
    at any depth are included. A deeper entry under a recognizable owner is
    recorded on that owner, not once per file.
    """
    by_path = {
        entry["path"]: entry
        for entry in entries
        if isinstance(entry.get("path"), str)
    }
    selected: dict[str, str] = {}
    for entry in entries:
        path = entry.get("path")
        if not isinstance(path, str) or path in {"", "."}:
            continue
        if "/" not in path:
            selected[path] = "immediate-child"
            continue
        if not (entry.get("hints") or _empty(entry) or _out_of_place(entry)):
            continue
        owner = path.split("/", 1)[0]
        owner_entry = by_path.get(owner)
        if owner_entry is not None and _recognizable(owner):
            selected.setdefault(owner, "owner")
        else:
            selected[path] = "entry"
    return selected


def _sentences(text: str) -> int:
    return len([part for part in re.split(r"[.!?]+", text) if part.strip()])


def _question(path: str) -> str:
    return f"Who owns {path}? The local investigation did not find an owner."


def _unresolved_provenance(path: str) -> str:
    return (
        f"No owner was established for {path}. "
        "The entry stays keep until an operator answer is recorded."
    )


def _normalize_evidence(raw: Any) -> list[dict[str, str]]:
    if not isinstance(raw, list):
        return []
    evidence: list[dict[str, str]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        source = item.get("source")
        ref = item.get("ref")
        if source in INVESTIGATION_SOURCES and isinstance(ref, str) and ref.strip():
            evidence.append({"source": source, "ref": ref.strip()})
    return evidence


def _base_record(
    entry: dict[str, Any],
    entries: list[dict[str, Any]],
    run_id: str,
    *,
    previous: dict[str, Any] | None,
) -> dict[str, Any]:
    path = str(entry["path"])
    first_seen = run_id
    if previous and previous.get("first_seen_run"):
        first_seen = str(previous["first_seen_run"])
    size = entry.get("logical_size")
    return {
        "path": path,
        "identity": identity_of(entry),
        "descendant_set": descendant_set(path, entries),
        "owner": None,
        "provenance": _unresolved_provenance(path),
        "evidence": [],
        "disposition": "keep",
        "tier": None,
        "size": size if isinstance(size, int) else None,
        "first_seen_run": first_seen,
        "last_seen_run": run_id,
        "last_verified": run_id,
        "source": "engine",
        "question": _question(path),
    }


def _apply_conclusion(
    record: dict[str, Any],
    conclusion: dict[str, Any],
    *,
    source: str,
) -> dict[str, Any]:
    owner = conclusion.get("owner")
    owner_text = owner.strip() if isinstance(owner, str) and owner.strip() else None
    provenance = conclusion.get("provenance")
    if not isinstance(provenance, str) or not (2 <= _sentences(provenance) <= 4):
        provenance = record["provenance"]
    disposition = conclusion.get("disposition")
    if disposition not in DISPOSITIONS:
        disposition = "keep"
    tier = conclusion.get("tier")
    if tier not in {"high", "medium", "low"}:
        tier = None
    evidence = _normalize_evidence(conclusion.get("evidence"))
    record["owner"] = owner_text
    record["provenance"] = provenance
    record["evidence"] = evidence
    record["tier"] = tier
    record["source"] = source
    # Unknown stays keep, and stays visibly unknown. An owner is what retires
    # the question. A remove disposition with no owner is not a conclusion.
    if owner_text is None:
        record["disposition"] = "keep"
        record["question"] = _question(record["path"])
    else:
        record["disposition"] = disposition
        record["question"] = None
    return record


def empty_catalog() -> dict[str, Any]:
    return {"version": CATALOG_VERSION, "records": []}


def sync_catalog(
    entries: list[dict[str, Any]],
    existing: dict[str, Any] | None,
    findings: list[dict[str, Any]],
    answers: list[dict[str, Any]],
    run_id: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Merge findings and operator answers. Return the catalog and the report.

    A human record whose identity still holds is not re-investigated and its
    question is not asked again. An identity or descendant-set change drops the
    previous record, so the question returns.
    """
    by_path = {
        entry["path"]: entry
        for entry in entries
        if isinstance(entry.get("path"), str)
    }
    previous_records = {}
    if isinstance(existing, dict):
        for record in existing.get("records") or []:
            if isinstance(record, dict) and isinstance(record.get("path"), str):
                previous_records[record["path"]] = record
    scoped = scope_paths(entries)
    kept: dict[str, dict[str, Any]] = {}
    report_class: dict[str, str] = {}
    for path, record in previous_records.items():
        entry = by_path.get(path)
        if entry is not None and identity_holds(record, entry, entries):
            kept[path] = dict(record)
            report_class[path] = "unchanged"
        elif path in scoped:
            report_class[path] = "changed"
    for path in scoped:
        entry = by_path[path]
        if path not in kept:
            kept[path] = _base_record(
                entry,
                entries,
                run_id,
                previous=previous_records.get(path),
            )
            report_class.setdefault(path, "new")
        else:
            kept[path]["last_seen_run"] = run_id
            kept[path]["last_verified"] = run_id
            kept[path]["identity"] = identity_of(entry)
            kept[path]["descendant_set"] = descendant_set(path, entries)
            size = entry.get("logical_size")
            kept[path]["size"] = size if isinstance(size, int) else None
    for finding in findings:
        if not isinstance(finding, dict) or not isinstance(finding.get("path"), str):
            continue
        path = finding["path"]
        if path not in scoped or path not in by_path:
            continue
        current = kept[path]
        if current.get("source") == "human" and report_class.get(path) == "unchanged":
            continue
        _apply_conclusion(current, finding, source="engine")
    for answer in answers:
        if not isinstance(answer, dict) or not isinstance(answer.get("path"), str):
            continue
        path = answer["path"]
        if path not in by_path:
            continue
        if path not in kept:
            kept[path] = _base_record(
                by_path[path], entries, run_id, previous=previous_records.get(path)
            )
            report_class.setdefault(path, "new")
        _apply_conclusion(kept[path], answer, source="human")
        report_class[path] = "unchanged"
    records = [kept[path] for path in sorted(kept)]
    catalog = {"version": CATALOG_VERSION, "records": records}
    return catalog, build_report(scoped, kept, report_class)


def build_report(
    scoped: dict[str, str],
    records: dict[str, dict[str, Any]],
    report_class: dict[str, str],
) -> dict[str, Any]:
    """New or changed entries first. Unchanged entries are one line each."""
    new_or_changed = []
    unchanged = []
    for path in sorted(scoped):
        record = records.get(path)
        if record is None:
            continue
        if report_class.get(path) == "unchanged":
            unchanged.append(_one_line(record))
            continue
        new_or_changed.append(
            {
                "path": path,
                "scope": scoped[path],
                "owner": record.get("owner"),
                "disposition": record.get("disposition"),
                "source": record.get("source"),
                "provenance": record.get("provenance"),
            }
        )
    questions = [
        {"path": path, "question": records[path]["question"]}
        for path in sorted(scoped)
        if records.get(path, {}).get("question")
    ]
    return {
        "new_or_changed": new_or_changed,
        "unchanged": unchanged,
        "questions": questions,
    }


def _one_line(record: dict[str, Any]) -> str:
    owner = record.get("owner") or "unknown"
    return f"{record['path']} | {record.get('disposition')} | {owner}"


def annotate_entries(
    entries: list[dict[str, Any]], catalog: dict[str, Any]
) -> dict[str, Any]:
    """Set ``prior_disposition`` only where identity still holds.

    The field is a report hint. It is not an approval and it is not copied
    onto any plan.
    """
    by_path = {
        record["path"]: record
        for record in catalog.get("records") or []
        if isinstance(record, dict) and isinstance(record.get("path"), str)
    }
    scoped = scope_paths(entries)
    report_class: dict[str, str] = {}
    for entry in entries:
        path = entry.get("path")
        if not isinstance(path, str):
            continue
        record = by_path.get(path)
        entry.pop("prior_disposition", None)
        if record is None or path not in scoped:
            if path in scoped:
                report_class[path] = "new"
            continue
        if identity_holds(record, entry, entries):
            entry["prior_disposition"] = record.get("disposition")
            report_class[path] = "unchanged"
        else:
            report_class[path] = "changed"
    records = {path: by_path[path] for path in scoped if path in by_path}
    for path in scoped:
        if path not in records:
            entry = next(
                (item for item in entries if item.get("path") == path), None
            )
            if entry is None:
                continue
            records[path] = _base_record(entry, entries, "scan", previous=None)
    return build_report(scoped, records, report_class)


def render_markdown(catalog: dict[str, Any], report: dict[str, Any]) -> str:
    """Operator-readable catalog. The run section leads with what changed."""
    lines = [
        "# Investigated catalog",
        "",
        "A record is a hint. It does not authorize deletion, skip a preview,",
        "or shorten approval. Unknown owners stay unknown until an operator",
        "answers, and an unanswered entry stays `keep`.",
        "",
        "## This run",
        "",
        "### New or changed",
        "",
    ]
    changed = report.get("new_or_changed") or []
    if not changed:
        lines.append("None.")
        lines.append("")
    for item in changed:
        lines.append(f"- `{item['path']}` ({item['scope']})")
        lines.append(f"  - owner: {item.get('owner') or 'unknown'}")
        lines.append(f"  - disposition: {item.get('disposition')}")
        lines.append(f"  - source: {item.get('source')}")
        lines.append(f"  - provenance: {item.get('provenance')}")
        lines.append("")
    lines.append("### Unchanged")
    lines.append("")
    unchanged = report.get("unchanged") or []
    if not unchanged:
        lines.append("None.")
    else:
        lines.extend(f"- {line}" for line in unchanged)
    lines.append("")
    lines.append("### Questions")
    lines.append("")
    questions = report.get("questions") or []
    if not questions:
        lines.append("None.")
    else:
        for index, item in enumerate(questions, start=1):
            lines.append(f"{index}. `{item['path']}`: {item['question']}")
    lines.extend(["", "## Records", ""])
    for record in catalog.get("records") or []:
        lines.append(f"### `{record['path']}`")
        lines.append("")
        owner = record.get("owner") or "unknown"
        lines.append(f"- owner: {owner}")
        lines.append(f"- disposition: {record.get('disposition')}")
        lines.append(f"- tier: {record.get('tier')}")
        lines.append(f"- size: {record.get('size')}")
        lines.append(f"- source: {record.get('source')}")
        identity = record.get("identity") or {}
        lines.append(
            "- identity: "
            f"device {identity.get('device')}, "
            f"inode {identity.get('inode')}, "
            f"kind {identity.get('kind')}"
        )
        lines.append(f"- first seen: {record.get('first_seen_run')}")
        lines.append(f"- last seen: {record.get('last_seen_run')}")
        lines.append(f"- last verified: {record.get('last_verified')}")
        lines.append(f"- provenance: {record.get('provenance')}")
        if record.get("question"):
            lines.append(f"- question: {record['question']}")
        lines.append("- evidence:")
        evidence = record.get("evidence") or []
        if not evidence:
            lines.append("  - none")
        for item in evidence:
            lines.append(f"  - {item['source']}: {item['ref']}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"
