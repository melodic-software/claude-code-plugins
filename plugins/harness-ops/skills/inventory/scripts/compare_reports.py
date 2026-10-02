#!/usr/bin/env python3
"""Diff two inventory JSON reports and classify every changed value.

Built to gate a reader change: run `inventory.py --binary-only --binary <path>`
before and after, then compare. A value the reader stopped reading or newly
reads is expected; a value that changed into a different value is a wrong
value somewhere, so it fails unless an `--allow` file names it.

Classes, per changed leaf (a JSON pointer, RFC 6901):

  wrong->unresolved     a concrete value became unresolved
  unresolved->resolved  an unresolved value became concrete
  value->value          a concrete value became a different concrete value,
                        or an unresolved one a different unresolved one
  added / removed       the key or list item exists on one side only

A value is unresolved when its field's sibling `<field>_source` is `partial`
or `unresolved`, when it is that source field itself holding one of those, or
when it is a string holding the reader's `…` runtime placeholder.

Run metadata is ignored: `/host`, and `elapsed_seconds`, `path` and
`selected_by` anywhere under `/sources`.

Allow file: a JSON list of {"pointer": "/a/b", "reason": "..."}. An entry
allows a value->value change at that pointer or under it.

Exit: 0 no disallowed change, 1 a disallowed value->value change, 2 usage or
input error.

Run: python3 compare_reports.py before.json after.json [--allow allow.json] [--json]
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

UNRESOLVED_SOURCES = frozenset({"partial", "unresolved"})
ELLIPSIS = "…"
METADATA_KEYS = frozenset({"elapsed_seconds", "path", "selected_by"})
CLASSES = (
    "value->value",
    "wrong->unresolved",
    "unresolved->resolved",
    "added",
    "removed",
)

_MISSING = object()


def _escape(key: str) -> str:
    return key.replace("~", "~0").replace("/", "~1")


def _ignored(pointer: str, key: str) -> bool:
    if pointer == "" and key == "host":
        return True
    return pointer.startswith("/sources") and key in METADATA_KEYS


def _unresolved(value: Any, source: Any) -> bool:
    if source in UNRESOLVED_SOURCES:
        return True
    if isinstance(value, list):
        return any(isinstance(v, str) and ELLIPSIS in v for v in value)
    return isinstance(value, str) and ELLIPSIS in value


def _scalar(value: Any) -> bool:
    return not isinstance(value, (dict, list))


def _diff(
    old: Any, new: Any, pointer: str, src_old: Any, src_new: Any, out: list
) -> None:
    if isinstance(old, dict) and isinstance(new, dict):
        for key in sorted(old.keys() | new.keys()):
            if _ignored(pointer, key):
                continue
            child = pointer + "/" + _escape(key)
            a, b = old.get(key, _MISSING), new.get(key, _MISSING)
            if a is _MISSING or b is _MISSING:
                out.append(_change(child, a, b))
                continue
            if key.endswith("_source"):
                sa, sb = a, b
            else:
                sa = old.get(key + "_source", src_old)
                sb = new.get(key + "_source", src_new)
            _diff(a, b, child, sa, sb, out)
        return
    if isinstance(old, list) and isinstance(new, list):
        # A list of names reads as a whole, so an inserted name does not
        # shift every later index into a spurious value->value.
        if all(map(_scalar, old + new)):
            if old != new:
                out.append(_change(pointer, old, new, src_old, src_new))
            return
        for i in range(max(len(old), len(new))):
            a = old[i] if i < len(old) else _MISSING
            b = new[i] if i < len(new) else _MISSING
            child = f"{pointer}/{i}"
            if a is _MISSING or b is _MISSING:
                out.append(_change(child, a, b))
            else:
                _diff(a, b, child, src_old, src_new, out)
        return
    if old == new and type(old) is type(new):
        return
    out.append(_change(pointer, old, new, src_old, src_new))


def _change(
    pointer: str, old: Any, new: Any, src_old: Any = None, src_new: Any = None
) -> dict:
    if old is _MISSING:
        cls = "added"
    elif new is _MISSING:
        cls = "removed"
    else:
        was, now = _unresolved(old, src_old), _unresolved(new, src_new)
        if was == now:
            cls = "value->value"
        elif now:
            cls = "wrong->unresolved"
        else:
            cls = "unresolved->resolved"
    rec: dict[str, Any] = {"pointer": pointer, "class": cls}
    if old is not _MISSING:
        rec["old"] = old
    if new is not _MISSING:
        rec["new"] = new
    return rec


def _covers(allowed: str, pointer: str) -> bool:
    # RFC 6901: `/a/` names the empty-key child of `/a`, and `/` is not the
    # whole document, so the entry is matched as written.
    return pointer == allowed or pointer.startswith(allowed + "/")


def compare(old: Any, new: Any, allow: list[dict] | None = None) -> dict:
    """The classified changes from `old` to `new`, with `failed` set when a
    value->value change is not covered by `allow`."""
    changes: list[dict] = []
    _diff(old, new, "", None, None, changes)
    allow = allow or []
    used: set[str] = set()
    for rec in changes:
        if rec["class"] != "value->value":
            continue
        covering = [e for e in allow if _covers(e["pointer"], rec["pointer"])]
        if covering:
            rec["allowed"] = covering[0]["reason"]
            used.update(e["pointer"] for e in covering)
    counts = {c: sum(1 for r in changes if r["class"] == c) for c in CLASSES}
    disallowed = [
        r for r in changes if r["class"] == "value->value" and "allowed" not in r
    ]
    return {
        "counts": counts,
        "changes": changes,
        "disallowed": len(disallowed),
        "unused_allow": [e["pointer"] for e in allow if e["pointer"] not in used],
        "failed": bool(disallowed),
    }


def _load_allow(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, list) or not all(
        isinstance(e, dict)
        and isinstance(e.get("pointer"), str)
        and isinstance(e.get("reason"), str)
        and e["reason"].strip()
        for e in data
    ):
        raise ValueError(
            'allow file must be a JSON list of {"pointer": str, "reason": non-empty str}'
        )
    return data


def _short(value: Any) -> str:
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= 120 else text[:117] + "..."


def render(result: dict) -> str:
    lines = ["changes: " + ", ".join(f"{c} {n}" for c, n in result["counts"].items())]
    for cls in CLASSES:
        group = [r for r in result["changes"] if r["class"] == cls]
        if not group:
            continue
        lines.append(f"\n{cls} ({len(group)})")
        for r in group:
            tail = f"  [allowed: {r['allowed']}]" if "allowed" in r else ""
            lines.append(f"  {r['pointer']}{tail}")
            if "old" in r:
                lines.append(f"    - {_short(r['old'])}")
            if "new" in r:
                lines.append(f"    + {_short(r['new'])}")
    for p in result["unused_allow"]:
        lines.append(f"\nwarning: allow entry {p} matched no value->value change")
    if result["failed"]:
        n = result["disallowed"]
        lines.append(f"\nFAIL: {n} value->value change(s) not in --allow")
    else:
        lines.append("\nOK: no disallowed value->value change")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Classify the value changes between two inventory reports."
    )
    ap.add_argument("before", help="report from the current reader")
    ap.add_argument("after", help="report from the changed reader")
    ap.add_argument(
        "--allow", help="JSON list of {pointer, reason} for intended value changes"
    )
    ap.add_argument("--json", action="store_true", help="print the result as JSON")
    args = ap.parse_args(argv)
    try:
        with open(args.before, encoding="utf-8") as fh:
            old = json.load(fh)
        with open(args.after, encoding="utf-8") as fh:
            new = json.load(fh)
        allow = _load_allow(args.allow) if args.allow else []
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    result = compare(old, new, allow)
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(render(result))
    return 1 if result["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
