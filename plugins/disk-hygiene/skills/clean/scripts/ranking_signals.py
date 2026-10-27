"""Review-order signals for disk-hygiene scan entries.

Each signal reads fields the walk already recorded on every entry
(``SIGNAL_READS`` names them); none opens, stats or reads a path, so ranking
adds no collection pass and cannot turn a bounded scan into an unbounded one.

A signal is evidence about where an entry came from, never proof that it is
disposable. The rank orders what the operator reviews and nothing else: no
eligibility, tick or blocker decision reads ``review_rank`` or
``review_ranking``, so a rank cannot make an entry eligible, ineligible, ticked
or approved. Like every snapshot field, both are covered by the approval
token's snapshot digest.

Every ranked entry carries the signals that placed it. An entry no signal
reached is ``unranked`` with a null position, never a middle one, so missing
evidence stays visible as missing.
"""

from __future__ import annotations

from collections import defaultdict
from pathlib import PurePosixPath
from typing import Any

SIGNAL_HINT = "discovery-hint"
SIGNAL_MTIME_CLUSTER = "sibling-mtime-cluster"
SIGNAL_SIZE_COLLISION = "size-collision"
# Fixed order: it is the order signals are listed on an entry and the order
# that picks the group an entry is presented under.
SIGNALS = (SIGNAL_HINT, SIGNAL_MTIME_CLUSTER, SIGNAL_SIZE_COLLISION)
SIGNAL_READS = {
    SIGNAL_HINT: ["hints"],
    SIGNAL_MTIME_CLUSTER: ["path", "kind", "mtime_ns"],
    SIGNAL_SIZE_COLLISION: ["path", "kind", "stat_size", "device", "inode"],
}
# Siblings whose modification times chain together with no gap wider than this
# are one cluster: one write-second plus the neighbor it rounds into.
MTIME_CLUSTER_WINDOW_NS = 2_000_000_000
RANKING_BASIS = (
    "Presentation order only. A signal is evidence, never proof an entry is "
    "disposable; no eligibility, tick or blocker decision reads the rank. An "
    "unranked entry is one no signal reached, not one ranked in the middle. "
    "Each entry's signals name a group; the group's detail is in groups."
)


def parent_of(relative: str) -> str:
    """The snapshot-relative parent directory; ``.`` for the target's own children."""
    return PurePosixPath(relative).parent.as_posix()


def hint_groups(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """One group per discovery hint id, holding every entry that hint matched."""
    members: dict[str, list[str]] = defaultdict(list)
    for entry in entries:
        for hint in entry.get("hints") or ():
            if isinstance(hint, dict) and isinstance(hint.get("id"), str):
                members[hint["id"]].append(entry["path"])
    return [
        {
            "id": f"{SIGNAL_HINT}:{hint_id}",
            "signal": SIGNAL_HINT,
            "hint_id": hint_id,
            "paths": sorted(paths),
            "detail": f"name matches discovery hint {hint_id}",
        }
        for hint_id, paths in sorted(members.items())
    ]


def mtime_cluster_groups(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Siblings whose modification times chain within ``MTIME_CLUSTER_WINDOW_NS``.

    Files and directories that share a parent and were last written within
    seconds of each other were most likely written by one operation, so they
    are presented as one group. A cluster needs two or more members.
    """
    by_parent: dict[str, list[tuple[int, str]]] = defaultdict(list)
    for entry in entries:
        mtime = entry.get("mtime_ns")
        if entry.get("kind") in {"file", "directory"} and isinstance(mtime, int):
            by_parent[parent_of(entry["path"])].append((mtime, entry["path"]))
    groups = []
    for parent, items in sorted(by_parent.items()):
        items.sort()
        clusters: list[list[tuple[int, str]]] = []
        for item in items:
            if clusters and item[0] - clusters[-1][-1][0] <= MTIME_CLUSTER_WINDOW_NS:
                clusters[-1].append(item)
            else:
                clusters.append([item])
        for cluster in clusters:
            if len(cluster) < 2:
                continue
            first, last = cluster[0][0], cluster[-1][0]
            groups.append(
                {
                    "id": f"{SIGNAL_MTIME_CLUSTER}:{parent}@{first}",
                    "signal": SIGNAL_MTIME_CLUSTER,
                    "parent": parent,
                    "paths": sorted(path for _, path in cluster),
                    "span_ns": last - first,
                    "detail": (
                        f"{len(cluster)} siblings in {parent} written within "
                        f"{(last - first) / 1e9:.3f}s of each other"
                    ),
                }
            )
    return groups


def size_collision_groups(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Non-empty files of one byte size in one directory or in sibling directories.

    A file's scope is its directory together with that directory's siblings,
    written ``<grandparent>/*``, so ``a/x`` and ``b/y`` collide while ``a/x``
    and ``a/sub/y`` do not. The target's own files have no sibling directories
    and collide only among themselves, scope ``.``. Hard-linked names of one
    object do not collide with each other: a group needs two distinct objects.
    """
    by_key: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for entry in entries:
        size = entry.get("stat_size")
        if entry.get("kind") == "file" and isinstance(size, int) and size > 0:
            parent = parent_of(entry["path"])
            scope = "." if parent == "." else f"{parent_of(parent)}/*"
            by_key[(scope, size)].append(entry)
    groups = []
    for (scope, size), members in sorted(by_key.items()):
        objects = {
            (entry.get("device"), entry.get("inode"))
            if entry.get("inode")
            else ("path", entry["path"])
            for entry in members
        }
        if len(objects) < 2:
            continue
        groups.append(
            {
                "id": f"{SIGNAL_SIZE_COLLISION}:{scope}:{size}",
                "signal": SIGNAL_SIZE_COLLISION,
                "scope": scope,
                "stat_size": size,
                "paths": sorted(entry["path"] for entry in members),
                "detail": (
                    f"{len(members)} files of exactly {size} bytes in {scope}: "
                    "duplicates or one process writing the same output again"
                ),
            }
        )
    return groups


def annotate(entries: list[dict[str, Any]]) -> dict[str, Any]:
    """Give every entry a ``review_rank`` and return the snapshot's ``review_ranking``.

    Entries reached by more distinct signals come first. Within one signal
    count, entries sharing their first group sit together, then path order
    breaks ties; an entry in two groups appears once, so a group's members are
    adjacent only within one signal count. Each entry lists ``signal`` and
    ``group`` per signal; the group's member count and detail are in the
    returned ``groups``, said once rather than on every member. Nothing about
    an entry is read or written beyond its ``review_rank`` field.
    """
    groups = [
        *hint_groups(entries),
        *mtime_cluster_groups(entries),
        *size_collision_groups(entries),
    ]
    reached: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for group in groups:
        for path in group["paths"]:
            reached[path].append({"signal": group["signal"], "group": group["id"]})
    for signals in reached.values():
        signals.sort(key=lambda item: (SIGNALS.index(item["signal"]), item["group"]))

    def order(path: str) -> tuple[int, str, str]:
        signals = reached[path]
        return (-len({item["signal"] for item in signals}), signals[0]["group"], path)

    positions = {path: index for index, path in enumerate(sorted(reached, key=order), 1)}
    for entry in entries:
        path = entry["path"]
        if path in positions:
            entry["review_rank"] = {
                "status": "ranked",
                "position": positions[path],
                "signals": reached[path],
            }
        else:
            entry["review_rank"] = {"status": "unranked", "position": None, "signals": []}
    by_signal = dict.fromkeys(SIGNALS, 0)
    for signals in reached.values():
        for signal in {item["signal"] for item in signals}:
            by_signal[signal] += 1
    return {
        "basis": RANKING_BASIS,
        "signal_reads": {signal: list(fields) for signal, fields in SIGNAL_READS.items()},
        "mtime_cluster_window_ns": MTIME_CLUSTER_WINDOW_NS,
        "ranked_entries": len(positions),
        "unranked_entries": len(entries) - len(positions),
        "entries_by_signal": by_signal,
        "groups": [
            {key: value for key, value in group.items() if key != "paths"}
            | {"members": len(group["paths"])}
            for group in groups
        ],
    }
