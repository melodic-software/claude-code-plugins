"""Investigated-entry catalog for disk-hygiene.

A record remembers what an investigation or an operator concluded about one
entry. It is a hint for the next report. Preview and apply never read it, so a
record cannot grant deletion authority or shorten any approval step.
"""

from __future__ import annotations

from typing import Any

from engine_grammar import TIERS

CATALOG_VERSION = 1
RECORD_KEYS = frozenset(
    {
        "target",
        "path",
        "identity",
        "descendant_set",
        "owner",
        "provenance",
        "evidence",
        "disposition",
        "tier",
        "size",
        "first_seen_run",
        "last_seen_run",
        "last_verified",
        "source",
        "question",
    }
)
DISPOSITIONS = frozenset({"keep", "remove", "review"})


def descendant_set(path: str, entries: list[dict[str, Any]]) -> list[str]:
    """Inventoried paths strictly below ``path``, in stable order."""
    prefix = f"{path}/"
    return sorted(
        entry["path"]
        for entry in entries
        if isinstance(entry.get("path"), str) and entry["path"].startswith(prefix)
    )


def descendants_of(
    entry: dict[str, Any], entries: list[dict[str, Any]]
) -> list[str] | None:
    """The entry's descendant set, or ``None`` when its subtree was not walked."""
    if "not-walked" in (entry.get("size_qualifiers") or []):
        return None
    return descendant_set(entry["path"], entries)


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
    A set that was never walked, on either side, cannot be compared and is not
    a change.
    """
    if record.get("identity") != identity_of(entry):
        return False
    stored = record.get("descendant_set")
    current = descendants_of(entry, entries)
    return stored is None or current is None or stored == current


def _question(path: str) -> str:
    return f"Who owns {path}? No owner is recorded."


def _unresolved_provenance(path: str) -> str:
    return f"No owner was established for {path}. It stays keep until answered."


def _unresolved_record(
    target: str,
    entry: dict[str, Any],
    entries: list[dict[str, Any]],
    run_id: str,
    previous: dict[str, Any] | None,
) -> dict[str, Any]:
    path = entry["path"]
    return {
        "target": target,
        "path": path,
        "identity": identity_of(entry),
        "descendant_set": descendants_of(entry, entries),
        "owner": None,
        "provenance": _unresolved_provenance(path),
        "evidence": [],
        "disposition": "keep",
        "tier": None,
        "size": _size(entry),
        "first_seen_run": (previous or {}).get("first_seen_run") or run_id,
        "last_seen_run": run_id,
        "last_verified": run_id,
        "source": "engine",
        "question": _question(path),
    }


def _size(entry: dict[str, Any]) -> int | None:
    size = entry.get("logical_size")
    return size if isinstance(size, int) else None


def _evidence(raw: Any) -> list[dict[str, str]]:
    if not isinstance(raw, list):
        return []
    return [
        {"source": item["source"].strip()}
        for item in raw
        if isinstance(item, dict)
        and isinstance(item.get("source"), str)
        and item["source"].strip()
    ]


def _text(value: Any) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _apply(record: dict[str, Any], conclusion: dict[str, Any], source: str) -> None:
    """Write a conclusion onto a record.

    An engine conclusion without an owner is not a conclusion: the record stays
    ``keep`` and keeps its question. An operator answer always retires the
    question, with or without an owner, and so is not asked again while identity
    holds.
    """
    owner = _text(conclusion.get("owner"))
    unresolved = source == "engine" and owner is None
    disposition = conclusion.get("disposition")
    if unresolved or disposition not in DISPOSITIONS:
        disposition = "keep"
    if unresolved:
        fallback = _unresolved_provenance(record["path"])
    elif source == "human":
        fallback = "Answered by the operator."
    else:
        fallback = "An owner was recorded without a narrative."
    record.update(
        owner=owner,
        disposition=disposition,
        tier=conclusion["tier"] if conclusion.get("tier") in TIERS else None,
        evidence=_evidence(conclusion.get("evidence")),
        source=source,
        provenance=_text(conclusion.get("provenance")) or fallback,
        question=_question(record["path"]) if unresolved else None,
    )


def _records_by_key(catalog: dict[str, Any] | None) -> dict[tuple[str, str], dict]:
    records = (catalog or {}).get("records")
    if not isinstance(records, list):
        return {}
    return {
        (record["target"], record["path"]): record
        for record in records
        if _well_formed(record)
    }


def _well_formed(record: Any) -> bool:
    """A record this module wrote. Anything else is ignored, not trusted."""
    return (
        isinstance(record, dict)
        and record.keys() >= RECORD_KEYS
        and isinstance(record["target"], str)
        and isinstance(record["path"], str)
        and isinstance(record["identity"], dict)
        and record["identity"].keys() == {"device", "inode", "kind"}
        and isinstance(record["descendant_set"], list | None)
        and record["evidence"] == _evidence(record["evidence"])
    )


def sync_catalog(
    snapshot: dict[str, Any],
    existing: dict[str, Any] | None,
    findings: list[dict[str, Any]],
    answers: list[dict[str, Any]],
    run_id: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Merge findings and operator answers into the catalog. Return it and the report.

    Records for entries this snapshot did not inventory are kept as they are:
    not seen is not changed. A record for an entry that was inventoried, and
    whose identity or descendant set changed, is replaced by an unresolved one,
    so its question returns.
    """
    target = str(snapshot["target"])
    entries = snapshot.get("entries") or []
    by_path = {entry["path"]: entry for entry in entries}
    records = _records_by_key(existing)
    state: dict[str, str] = {}
    for path, entry in by_path.items():
        previous = records.get((target, path))
        if previous is None:
            continue
        if identity_holds(previous, entry, entries):
            stored = previous["descendant_set"]
            records[(target, path)] = {
                **previous,
                "descendant_set": (
                    descendants_of(entry, entries) if stored is None else stored
                ),
                "size": _size(entry),
                "last_seen_run": run_id,
                "last_verified": run_id,
            }
            state[path] = "unchanged"
        else:
            records[(target, path)] = _unresolved_record(
                target, entry, entries, run_id, previous
            )
            state[path] = "changed"
    unmatched: list[str] = []
    for source, conclusions in (("engine", findings), ("human", answers)):
        for conclusion in conclusions:
            path = conclusion.get("path") if isinstance(conclusion, dict) else None
            if not isinstance(path, str) or path not in by_path:
                unmatched.append(str(path))
                continue
            if (target, path) not in records:
                records[(target, path)] = _unresolved_record(
                    target, by_path[path], entries, run_id, None
                )
                state[path] = "new"
            record = records[(target, path)]
            if (
                source == "engine"
                and record["source"] == "human"
                and state[path] == "unchanged"
            ):
                continue
            before = dict(record)
            _apply(record, conclusion, source)
            if state[path] == "unchanged" and record != before:
                state[path] = "changed"
    catalog = {
        "version": CATALOG_VERSION,
        "records": [records[key] for key in sorted(records)],
    }
    return catalog, _report(target, records, state, unmatched)


def _report(
    target: str,
    records: dict[tuple[str, str], dict[str, Any]],
    state: dict[str, str],
    unmatched: list[str],
) -> dict[str, Any]:
    """New or changed entries first, unchanged entries one line each."""
    new_or_changed = []
    unchanged = []
    questions = []
    for path in sorted(state):
        record = records[(target, path)]
        if state[path] == "unchanged":
            unchanged.append(
                f"{path} | {record['disposition']} | {record['owner'] or 'unknown'}"
            )
        else:
            new_or_changed.append(
                {
                    "path": path,
                    "state": state[path],
                    "owner": record["owner"],
                    "disposition": record["disposition"],
                    "source": record["source"],
                    "provenance": record["provenance"],
                }
            )
        if record["question"]:
            questions.append({"path": path, "question": record["question"]})
    return {
        "new_or_changed": new_or_changed,
        "unchanged": unchanged,
        "questions": questions,
        "unmatched": unmatched,
    }


def annotate_entries(snapshot: dict[str, Any], catalog: dict[str, Any]) -> None:
    """Set ``prior_disposition`` on entries whose record identity still holds.

    The field is a report hint. It is not an approval and no plan copies it.
    ``prior_unresolved`` marks a record that still has an open question, so an
    unknown owner does not read as a settled keep.
    """
    target = str(snapshot.get("target"))
    entries = snapshot.get("entries") or []
    records = _records_by_key(catalog)
    for entry in entries:
        record = records.get((target, entry["path"]))
        entry.pop("prior_disposition", None)
        entry.pop("prior_unresolved", None)
        if record is None or not identity_holds(record, entry, entries):
            continue
        entry["prior_disposition"] = record.get("disposition")
        if record.get("question"):
            entry["prior_unresolved"] = True


def render_markdown(catalog: dict[str, Any], report: dict[str, Any]) -> str:
    """Operator-readable catalog. The run section leads with what changed."""
    lines = [
        "# Investigated catalog",
        "",
        "A record is a hint. It does not authorize deletion, skip a preview,",
        "or shorten approval. An unknown owner stays unknown until an operator",
        "answers, and an unanswered entry stays `keep`.",
        "",
        "## This run",
        "",
        "### New or changed",
        "",
    ]
    changed = report["new_or_changed"]
    if not changed:
        lines += ["None.", ""]
    for item in changed:
        lines += [
            f"- `{item['path']}` ({item['state']})",
            f"  - owner: {item['owner'] or 'unknown'}",
            f"  - disposition: {item['disposition']}",
            f"  - source: {item['source']}",
            f"  - provenance: {item['provenance']}",
            "",
        ]
    lines += ["### Unchanged", ""]
    lines += [f"- {line}" for line in report["unchanged"]] or ["None."]
    lines += ["", "### Questions", ""]
    lines += [
        f"{index}. `{item['path']}`: {item['question']}"
        for index, item in enumerate(report["questions"], start=1)
    ] or ["None."]
    lines += ["", "## Records", ""]
    for record in catalog["records"]:
        identity = record["identity"]
        lines += [
            f"### `{record['path']}`",
            "",
            f"- target: `{record['target']}`",
            f"- owner: {record['owner'] or 'unknown'}",
            f"- disposition: {record['disposition']}",
            f"- tier: {record['tier']}",
            f"- size: {record['size']}",
            f"- source: {record['source']}",
            f"- identity: device {identity['device']}, inode {identity['inode']}, "
            f"kind {identity['kind']}",
            f"- first seen: {record['first_seen_run']}",
            f"- last seen: {record['last_seen_run']}",
            f"- last verified: {record['last_verified']}",
            f"- provenance: {record['provenance']}",
        ]
        if record["question"]:
            lines.append(f"- question: {record['question']}")
        lines.append("- evidence:")
        lines += [f"  - {item['source']}" for item in record["evidence"]] or [
            "  - none"
        ]
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"
