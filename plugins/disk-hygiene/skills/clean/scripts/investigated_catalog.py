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
# Optional on a record: absent means the record describes its own entry only.
OWNER_LEVEL_KEY = "owner_level"
DISPOSITIONS = frozenset({"keep", "remove", "review"})
SOURCES = frozenset({"engine", "human"})


def _prefix(path: str) -> str:
    """The text every descendant path starts with. The scan target is ``.``."""
    return "" if path == "." else f"{path}/"


def descendant_set(path: str, entries: list[dict[str, Any]]) -> list[str]:
    """Inventoried paths strictly below ``path``, in stable order."""
    prefix = _prefix(path)
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
    a change. Sets compare below their own entry, so a record made from one scan
    target still holds for the same entry reached from another.
    """
    if record.get("identity") != identity_of(entry):
        return False
    stored = record.get("descendant_set")
    current = descendants_of(entry, entries)
    if stored is None or current is None:
        return True
    return _below(record["path"], stored) == _below(entry["path"], current)


def _below(path: str, descendants: list[str]) -> list[str]:
    prefix = _prefix(path)
    return [item.removeprefix(prefix) for item in descendants]


def _human_by_identity(
    records: dict[tuple[str, str], dict[str, Any]],
) -> dict[tuple[Any, Any, Any], list[dict[str, Any]]]:
    """Operator answers indexed by the filesystem object they describe.

    A missing device or inode cannot tell one object from another, so such a
    record is never reused outside its own target and path.
    """
    index: dict[tuple[Any, Any, Any], list[dict[str, Any]]] = {}
    for record in records.values():
        identity = record["identity"]
        if record["source"] == "human" and identity["device"] and identity["inode"]:
            key = (identity["device"], identity["inode"], identity["kind"])
            index.setdefault(key, []).append(record)
    return index


def _other_target_answer(
    index: dict[tuple[Any, Any, Any], list[dict[str, Any]]],
    target: str,
    entry: dict[str, Any],
    entries: list[dict[str, Any]],
    local: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """An operator answer recorded under another scan target for this same entry.

    ``local`` is this target's record for the entry when its identity holds. It
    settles the entry unless it still has an open question, which an answer from
    another target retires.
    """
    if local is not None and not local["question"]:
        return None
    identity = identity_of(entry)
    for record in index.get(
        (identity["device"], identity["inode"], identity["kind"]), []
    ):
        if record["target"] != target and identity_holds(record, entry, entries):
            return record
    return None


def catalog_scope(snapshot: dict[str, Any], positional: bool) -> dict[str, list[str]]:
    """The entries a catalog must account for, each with why it is in scope.

    Every immediate child; every hinted or genuinely empty entry at any depth;
    and, at a user-home or root-children target (``positional``), every
    immediate child with no protection and no hint, the loose entry that
    belongs to no recognizable convention. Any other deeper entry is ordinary
    and is covered at owner level instead. Only snapshot fields are read.
    """
    scope: dict[str, list[str]] = {}
    for entry in snapshot.get("entries") or []:
        path = entry["path"]
        hinted = bool(entry.get("hints"))
        reasons = []
        if "/" not in path:
            reasons.append("immediate-child")
            if positional and not hinted and not entry.get("protected_reasons"):
                reasons.append("out-of-place")
        if hinted:
            reasons.append("hinted")
        if _size(entry) == 0 and not entry.get("size_qualifiers"):
            reasons.append("empty")
        if reasons:
            scope[path] = reasons
    return scope


def _uncataloged(
    target: str,
    scope: dict[str, list[str]],
    records: dict[tuple[str, str], dict[str, Any]],
    reused: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    """In-scope entries with no record of their own and no owner-level ancestor."""
    owners = {
        path
        for (record_target, path), record in records.items()
        if record_target == target and record.get(OWNER_LEVEL_KEY)
    }

    def covered(path: str) -> bool:
        parts = path.split("/")
        return any("/".join(parts[:end]) in owners for end in range(1, len(parts)))

    return [
        {"path": path, "reasons": reasons}
        for path, reasons in sorted(scope.items())
        if (target, path) not in records and path not in reused and not covered(path)
    ]


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
    holds. ``owner_level: true`` with an owner makes the record cover every
    entry below its path: one record per owning tool, not one per file.
    """
    owner = _text(conclusion.get("owner"))
    if owner and conclusion.get(OWNER_LEVEL_KEY) is True:
        record[OWNER_LEVEL_KEY] = True
    else:
        record.pop(OWNER_LEVEL_KEY, None)
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
        and (
            record["descendant_set"] is None
            or (
                isinstance(record["descendant_set"], list)
                and all(isinstance(item, str) for item in record["descendant_set"])
            )
        )
        and isinstance(record.get(OWNER_LEVEL_KEY, False), bool)
        and record["evidence"] == _evidence(record["evidence"])
        and record["disposition"] in DISPOSITIONS
        and (record["tier"] is None or record["tier"] in TIERS)
        and record["source"] in SOURCES
        and (record["owner"] is None or isinstance(record["owner"], str))
        and (record["question"] is None or isinstance(record["question"], str))
        and isinstance(record["provenance"], str)
        and (record["size"] is None or type(record["size"]) is int)
        and all(
            isinstance(record[key], str)
            for key in ("first_seen_run", "last_seen_run", "last_verified")
        )
    )


def sync_catalog(
    snapshot: dict[str, Any],
    existing: dict[str, Any] | None,
    findings: list[dict[str, Any]],
    answers: list[dict[str, Any]],
    run_id: str,
    positional: bool = False,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Merge findings and operator answers into the catalog. Return it and the report.

    Records for entries this snapshot did not inventory are kept as they are:
    not seen is not changed. A record for an entry that was inventoried, and
    whose identity or descendant set changed, is replaced by an unresolved one,
    so its question returns. The report lists every in-scope entry that has no
    record, so nothing that looks out of place is skipped without a trace.
    """
    target = str(snapshot["target"])
    entries = snapshot.get("entries") or []
    by_path = {entry["path"]: entry for entry in entries}
    records = _records_by_key(existing)
    answers_elsewhere = _human_by_identity(records)
    state: dict[str, str] = {}
    reused: dict[str, dict[str, Any]] = {}
    for path, entry in by_path.items():
        previous = records.get((target, path))
        holds = previous is not None and identity_holds(previous, entry, entries)
        if answer := _other_target_answer(
            answers_elsewhere, target, entry, entries, previous if holds else None
        ):
            records.pop((target, path), None)
            reused[path] = answer
        elif holds:
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
        elif previous is not None:
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
            if source == "engine" and path in reused:
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
    uncataloged = _uncataloged(
        target, catalog_scope(snapshot, positional), records, reused
    )
    return catalog, _report(target, records, state, reused, unmatched, uncataloged)


def _report(
    target: str,
    records: dict[tuple[str, str], dict[str, Any]],
    state: dict[str, str],
    reused: dict[str, dict[str, Any]],
    unmatched: list[str],
    uncataloged: list[dict[str, Any]],
) -> dict[str, Any]:
    """New or changed entries first, unchanged entries one line each.

    An entry matched to an operator answer recorded under another scan target
    has no record of its own here. It is unchanged, and its line names the
    target that holds the answer.
    """
    new_or_changed = []
    unchanged = []
    questions = []
    for path in sorted(state):
        record = records[(target, path)]
        if state[path] == "unchanged":
            owner = record["owner"] or "unknown"
            unchanged.append((path, f"{path} | {record['disposition']} | {owner}"))
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
    for path, answer in reused.items():
        if path not in state:
            owner = answer["owner"] or "unknown"
            unchanged.append(
                (
                    path,
                    f"{path} | {answer['disposition']} | {owner}"
                    f" | answered under {answer['target']}",
                )
            )
    return {
        "new_or_changed": new_or_changed,
        "unchanged": [line for _, line in sorted(unchanged)],
        "questions": questions,
        "uncataloged": uncataloged,
        "unmatched": unmatched,
    }


def annotate_entries(snapshot: dict[str, Any], catalog: dict[str, Any]) -> None:
    """Set ``prior_disposition`` on entries whose record identity still holds.

    The record under this target and path decides first, unless it still has an
    open question. An operator answer recorded under another scan target
    matches the same entry by identity and decides in its place, and the scan
    target itself, which is not an entry, gets ``target_prior_disposition``.

    The field is a report hint. It is not an approval and no plan copies it.
    ``prior_unresolved`` marks a record that still has an open question, so an
    unknown owner does not read as a settled keep.
    """
    target = str(snapshot.get("target"))
    entries = snapshot.get("entries") or []
    records = _records_by_key(catalog)
    answers_elsewhere = _human_by_identity(records)
    for entry in entries:
        entry.pop("prior_disposition", None)
        entry.pop("prior_unresolved", None)
        record = records.get((target, entry["path"]))
        if record is not None and not identity_holds(record, entry, entries):
            record = None
        record = (
            _other_target_answer(answers_elsewhere, target, entry, entries, record)
            or record
        )
        if record is None:
            continue
        entry["prior_disposition"] = record.get("disposition")
        if record.get("question"):
            entry["prior_unresolved"] = True
    snapshot.pop("target_prior_disposition", None)
    identity = snapshot.get("target_identity")
    if isinstance(identity, dict):
        answer = _other_target_answer(
            answers_elsewhere, target, {**identity, "path": "."}, entries
        )
        if answer is not None:
            snapshot["target_prior_disposition"] = answer["disposition"]


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
    lines += ["", "### Uncataloged", ""]
    lines += [
        f"- `{item['path']}` ({', '.join(item['reasons'])})"
        for item in report["uncataloged"]
    ] or ["None."]
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
            *(
                ["- owner level: covers every entry below"]
                if record.get(OWNER_LEVEL_KEY)
                else []
            ),
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
