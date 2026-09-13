#!/usr/bin/env bash
# assemble.sh — §7 assembly: the epoch-scoped append-only partial becomes
# `findings.json`, and `findings.json` becomes the human-readable `report.md`.
#
# WHY THIS EXISTS. Assembly decides WHICH ROWS REACH THE REPORT, and it shipped
# as prose for the run to perform. That put the one step whose output every
# determinism property is stated over into the same class as the steps a run
# improvises: a selection rule performed differently on two runs is a P1 failure
# the gate cannot attribute, because both runs believe they followed the rule.
#
# And a run whose only artifact is `findings.json` has done the work and
# delivered none of it. That file is large, deeply nested, and lives at a
# key-derived path under the plugin data directory, which a remote session
# cannot open and a terminal cannot usefully print. `report.md` is a RENDERING
# and never a source: it carries no fact the assembled document does not,
# nothing reads it back, and `--resume` still reads the partial.
#
# THE SELECTION RULES, from §7:
#   - read only the HIGHEST EPOCH partial present. A fenced writer appends to
#     its own superseded file, so lower epochs are evidence of an adoption and
#     are retained, never read.
#   - per lane, take the HIGHEST-ORDINAL attempt that has a TERMINATING record,
#     and discard every other attempt's rows outright, including any
#     complete-looking prefix. An attempt with a start record and no terminator
#     is abandoned by definition, whatever it managed to append.
#   - completion is read from the terminator's STATE, not from its presence:
#     `handed-back`, `declined`, and an ordinary completion mark the lane
#     complete; `open` marks it INCOMPLETE so `--resume` re-runs it.
#
# EVERY SECTION IS RENDERED, INCLUDING THE EMPTY ONES. An absent `skipped`
# section and an empty one look identical on the page and mean opposite things,
# and the whole contract turns on keeping "clean" and "not read" apart. An empty
# section renders its heading and the word `none`.
#
# SCOPE OF WRITES. `findings.json` and `report.md`, in the directory named by
# `--out-dir`, which defaults to the run directory. Nothing else, and never
# inside a target repository unless the caller points it there deliberately,
# having already cleared the destination gate in §2.
#
# PORTABILITY. Needs `python3`. Where it is absent this exits 2 naming the
# prerequisite, and the run performs the selection itself against the rules
# above, which is why §7 still states them in full rather than deferring to this
# file. A jq-only second implementation would be a second selection rule to keep
# in agreement, which is the defect one level down.
#
# Usage:
#   assemble.sh assemble  --run-dir <dir> [--out-dir <dir>] [--meta <json-file>]
#   assemble.sh render    --findings <path> [--out <path>]
#   assemble.sh epoch     --run-dir <dir>
#
# `--meta <json-file>` supplies the run-level fields the partial does not carry:
# run id, target, both captures, the gate verdict, the comparability verdict, the
# lane set, and whether the run was partial-scope. Absent, those render as
# `unknown`, which is honest and visible rather than fabricated.
#
# Exit codes:
#   0  the artifacts were written; their paths are on stdout
#   2  usage error, rejected argument, or a missing prerequisite

set -uo pipefail

PROG="assemble.sh"

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
assemble.sh — §7 assembly and the report.md rendering for audit-pass.

  assemble.sh assemble --run-dir <dir> [--out-dir <dir>] [--meta <json-file>]
  assemble.sh render   --findings <path> [--out <path>]
  assemble.sh epoch    --run-dir <dir>

assemble reads the highest-epoch findings.partial.<epoch>.jsonl, takes per lane
the highest-ordinal attempt carrying a terminating record, and writes
findings.json plus report.md. render re-renders report.md from an existing
findings.json. epoch prints the highest epoch present.
EOF
}

require_python() {
  command -v python3 >/dev/null 2>&1 ||
    die "python3 is required for assembly; without it the run performs §7's selection itself"
}

# The highest epoch present, from the partial filenames. Assembly reads only
# that one: lower epochs belong to writers a stale-lease adoption fenced, and
# they are retained as the evidence that an adoption happened.
highest_epoch() {
  local run_dir="$1" f base ep best=""
  for f in "$run_dir"/findings.partial.*.jsonl; do
    [[ -e "$f" ]] || continue
    base="${f##*/}"
    ep="${base#findings.partial.}"
    ep="${ep%.jsonl}"
    [[ "$ep" =~ ^[0-9]+$ ]] || continue
    if [[ -z "$best" || "$ep" -gt "$best" ]]; then
      best="$ep"
    fi
  done
  printf '%s' "$best"
}

cmd_epoch() {
  local run_dir="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a value"
      run_dir="$2"
      shift 2
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ -n "$run_dir" ]] || die "--run-dir is required"
  [[ -d "$run_dir" ]] || die "--run-dir is not a directory: $run_dir"
  local ep
  ep="$(highest_epoch "$run_dir")"
  [[ -n "$ep" ]] || die "no findings.partial.<epoch>.jsonl under $run_dir"
  printf '%s\n' "$ep"
}

cmd_assemble() {
  local run_dir="" out_dir="" meta="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a value"
      run_dir="$2"
      shift 2
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || die "--out-dir needs a value"
      out_dir="$2"
      shift 2
      ;;
    --meta)
      [[ $# -ge 2 ]] || die "--meta needs a value"
      meta="$2"
      shift 2
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ -n "$run_dir" ]] || die "--run-dir is required"
  [[ -d "$run_dir" ]] || die "--run-dir is not a directory: $run_dir"
  [[ -z "$meta" || -r "$meta" ]] || die "--meta is not readable: $meta"
  require_python

  local epoch partial
  epoch="$(highest_epoch "$run_dir")"
  [[ -n "$epoch" ]] || die "no findings.partial.<epoch>.jsonl under $run_dir"
  partial="$run_dir/findings.partial.$epoch.jsonl"

  [[ -n "$out_dir" ]] || out_dir="$run_dir"
  mkdir -p "$out_dir" || die "could not create --out-dir: $out_dir"

  AP_PARTIAL="$partial" AP_EPOCH="$epoch" AP_META="$meta" AP_OUT="$out_dir" \
    python3 - <<'PY' || die "assembly failed"
import json
import os
import sys

partial = os.environ["AP_PARTIAL"]
epoch = int(os.environ["AP_EPOCH"])
meta_path = os.environ.get("AP_META") or ""
out_dir = os.environ["AP_OUT"]

OWNERSHIP = "audit-pass/report/v1"
SCHEMA_VERSION = "audit-pass/findings/1"

meta = {}
if meta_path:
    with open(meta_path, encoding="utf-8") as fh:
        meta = json.load(fh)

rows = []
with open(partial, encoding="utf-8") as fh:
    for lineno, line in enumerate(fh, 1):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except Exception as exc:
            # A malformed row in an append-only artifact is permanent, and
            # assembly is one of its only two readers. Refusing here is what
            # keeps a quoting slip from silently costing a lane's findings.
            sys.stderr.write(
                "assemble.sh: %s line %d is not well-formed JSON: %s\n" % (partial, lineno, exc)
            )
            sys.exit(2)


def attempt_key(row):
    att = row.get("attempt") or {}
    if isinstance(att, dict):
        return (att.get("lane"), att.get("ordinal"))
    if isinstance(att, list) and len(att) == 2:
        return (att[0], att[1])
    return (row.get("lane"), None)


# Per lane, the highest-ordinal attempt that HAS a terminating record. An
# attempt with a start record and no terminator is abandoned by definition,
# whatever it managed to append, so every other attempt's rows are discarded
# outright rather than merged.
terminated = {}
for row in rows:
    if row.get("record") != "terminator":
        continue
    lane, ordinal = attempt_key(row)
    if lane is None:
        continue
    ordinal = ordinal if isinstance(ordinal, int) else 0
    prev = terminated.get(lane)
    if prev is None or ordinal > prev[0]:
        terminated[lane] = (ordinal, row)

# A supersession record names the lane and the ordinal it retires, so the
# retirement is in the artifact rather than inferred from ordering. It is read
# for the report, never for the selection: the highest terminated ordinal
# already decides that, and deriving it twice invites the two to disagree.
superseded = [r for r in rows if r.get("record") == "supersession"]

sections = {
    "inventory": [],
    "mechanical": [],
    "behavioral": [],
    "suppressed": [],
    "notes": [],
    "delegated": [],
    "skipped": [],
    "verification": [],
}

TIER_SECTION = {
    "derived": "mechanical",
    "judged": "behavioral",
    "delegated": "delegated",
    "note": "notes",
}

lane_states = {}
for lane, (ordinal, term) in sorted(terminated.items()):
    state = term.get("state", "complete")
    lane_states[lane] = {
        "lane": lane,
        "attempt": ordinal,
        "state": state,
        # `open` is an ASSEMBLY TERMINATOR, not a completion: it lets assembly
        # render the lane while leaving it incomplete so --resume re-runs it.
        "complete": state != "open",
        "verification": term.get("verification", "skipped"),
    }
    for key in ("skipped", "suppressed", "verification", "inventory"):
        for item in term.get(key, []) or []:
            sections[key].append(item)

for row in rows:
    kind = row.get("record")
    if kind not in ("finding", "note"):
        continue
    lane, ordinal = attempt_key(row)
    winner = terminated.get(lane)
    if winner is None:
        continue
    if (ordinal if isinstance(ordinal, int) else 0) != winner[0]:
        continue
    tier = row.get("tier", "judged")
    sections[TIER_SECTION.get(tier, "behavioral")].append(row)

for lane, info in sorted(lane_states.items()):
    sections["verification"].append({"lane": lane, "mode": info["verification"]})

doc = {
    "ownership": OWNERSHIP,
    "schemaVersion": SCHEMA_VERSION,
    "run": meta.get("run", {}),
    "target": meta.get("target", "unknown"),
    "epoch": epoch,
    "partialScope": bool(meta.get("partialScope", False)),
    "lanes": sorted(lane_states.values(), key=lambda r: r["lane"]),
    "superseded": superseded,
    "gate": meta.get("gate", {"verdict": "unknown"}),
    "comparability": meta.get("comparability", {"verdict": "unknown"}),
    "catalogs": meta.get("catalogs", []),
    "sections": sections,
}

findings_path = os.path.join(out_dir, "findings.json")
with open(findings_path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")

print(findings_path)
PY

  render_report "$out_dir/findings.json" "$out_dir/report.md"
  printf '%s\n' "$out_dir/report.md"
}

# The rendering. Kept in one place and called by both `assemble` and `render`,
# so a report.md produced by re-rendering an existing findings.json is the same
# document as the one assembly wrote.
render_report() {
  require_python
  export AP_FINDINGS="$1" AP_REPORT="$2"
  python3 - <<'PY' || die "rendering failed"
import json
import os

findings_path = os.environ["AP_FINDINGS"]
report_path = os.environ["AP_REPORT"]

with open(findings_path, encoding="utf-8") as fh:
    doc = json.load(fh)

sections = doc.get("sections", {})
lanes = doc.get("lanes", [])
run = doc.get("run", {}) or {}
gate = doc.get("gate", {}) or {}
comparability = doc.get("comparability", {}) or {}

TIERS = [("mechanical", "derived tier"), ("behavioral", "judged tier")]
ORDER = ["notes", "suppressed", "delegated", "skipped", "verification", "inventory"]

out = []
# The ownership line is FIRST, because §2 decides whether a destination path is
# ours by the artifact's own identifying header and never by its filename.
out.append("<!-- %s -->" % doc.get("ownership", "audit-pass/report/v1"))
out.append("")
out.append("# audit-pass report")
out.append("")

out.append("## Header")
out.append("")
out.append("| | |")
out.append("|---|---|")
out.append("| Run | `%s` |" % run.get("id", "unknown"))
out.append("| Target | `%s` |" % doc.get("target", "unknown"))
out.append("| Report directory | `%s` |" % os.path.dirname(os.path.abspath(report_path)))
out.append("| HEAD at scan baseline | `%s` |" % run.get("headBaseline", "unknown"))
out.append("| HEAD at audit endpoint | `%s` |" % run.get("headEndpoint", "unknown"))
out.append("| Harness | `%s` |" % run.get("harness", "unknown"))
out.append("| Arguments | `%s` |" % run.get("arguments", "none"))
lane_names = ", ".join("`%s`" % lane["lane"] for lane in lanes) or "none"
# A narrowed run is marked here, so no later reader mistakes it for a full pass.
scope_prefix = "partial-scope: " if doc.get("partialScope") else ""
out.append("| Lane set | %s%s |" % (scope_prefix, lane_names))
out.append("")

out.append("## Verdict")
out.append("")
out.append("- Determinism gate: **%s**" % gate.get("verdict", "unknown"))
if gate.get("reason"):
    out.append("  - %s" % gate["reason"])
out.append("- Comparability: **%s**" % comparability.get("verdict", "unknown"))
if comparability.get("movedInput"):
    out.append("  - input that moved: `%s`" % comparability["movedInput"])
props = gate.get("properties") or {}
if props:
    for name in sorted(props):
        out.append("- %s: **%s**" % (name, props[name]))
else:
    out.append("- P1-P6: **not evaluated**, no verdict supplied")
out.append("")

counts = {name: len(sections.get(name, []) or []) for name in sections}
headline = (
    "%d derived, %d judged, %d notes, %d suppressed, %d skipped, across %d lanes"
    % (
        counts.get("mechanical", 0),
        counts.get("behavioral", 0),
        counts.get("notes", 0),
        counts.get("suppressed", 0),
        counts.get("skipped", 0),
        len(lanes),
    )
)
out.append("## Headline")
out.append("")
out.append(headline)
out.append("")


def render_finding(row):
    ident = row.get("identity") or {}
    sites = ident.get("sites") or []
    where = ", ".join("`%s` @ `%s`" % (s.get("surface"), s.get("anchor")) for s in sites)
    bits = [
        "- **%s** `%s`" % (row.get("severity", "info"), ident.get("check", "unknown")),
        "  - claim: `%s`" % ident.get("claim", "unknown"),
        "  - site: %s" % (where or "none"),
        "  - id: `%s`" % row.get("finding_id/v1", "unknown"),
    ]
    if row.get("group"):
        bits.append("  - group: `%s`" % row["group"])
    if row.get("prose"):
        bits.append("  - %s" % row["prose"])
    return bits


for key, label in TIERS:
    out.append("## Findings, %s" % label)
    out.append("")
    rows = sections.get(key) or []
    if not rows:
        # Rendered even when empty. An absent section and an empty one look
        # identical on the page and mean opposite things.
        out.append("none")
    else:
        by_lane = {}
        for row in rows:
            by_lane.setdefault(row.get("lane", "unknown"), []).append(row)
        for lane in sorted(by_lane):
            out.append("### %s" % lane)
            out.append("")
            for row in by_lane[lane]:
                out.extend(render_finding(row))
            out.append("")
    out.append("")

for key in ORDER:
    out.append("## %s" % key.capitalize())
    out.append("")
    rows = sections.get(key) or []
    if not rows:
        out.append("none")
    else:
        for row in rows:
            if isinstance(row, dict):
                out.append("- " + ", ".join("%s: `%s`" % (k, row[k]) for k in sorted(row)))
            else:
                out.append("- %s" % row)
    out.append("")

with open(report_path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out).rstrip("\n") + "\n")

print(headline)
PY
}

cmd_render() {
  local findings="" out="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    --findings)
      [[ $# -ge 2 ]] || die "--findings needs a value"
      findings="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || die "--out needs a value"
      out="$2"
      shift 2
      ;;
    *) die "unknown argument: $arg" ;;
    esac
  done
  [[ -n "$findings" ]] || die "--findings is required"
  [[ -r "$findings" ]] || die "--findings is not readable: $findings"
  [[ -n "$out" ]] || out="$(dirname "$findings")/report.md"

  render_report "$findings" "$out"
  printf '%s\n' "$out"
}

main() {
  [[ $# -ge 1 ]] || {
    usage >&2
    exit 2
  }
  local cmd="$1"
  shift
  case "$cmd" in
  assemble) cmd_assemble "$@" ;;
  render) cmd_render "$@" ;;
  epoch) cmd_epoch "$@" ;;
  --help | -h | help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
}

main "$@"
