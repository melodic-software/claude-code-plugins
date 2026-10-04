#!/usr/bin/env bash
# /code-metrics:audit-duplication entry point: clone groups across the scope,
# minus the replication the target repository declares about itself.
#
#   audit-duplication.sh [--json] [--all] [--base <ref>] [--config <resolved.json>]
#                        [--registry <file>]... [--keep] [<path>...]
#
# Prints the markdown report and keeps its document, the baseline the next
# run's clone trend compares against; `--json` prints the `code-metrics/v2`
# document instead and keeps it only with `--keep`. Scope, lanes, and the collector ladder are the dispatcher's
# (scripts/dispatch.sh in the plugin root); this script owns the merge of the
# detector's clone pairs into clone classes (cluster-clones.py), `--registry`,
# and the duplication tunables it exports for the collector adapters
# (CODE_METRICS_DUP_MIN_TOKENS, CODE_METRICS_DUP_MIN_LINES,
# CODE_METRICS_DUP_IGNORE, CODE_METRICS_DUP_MAX_LINES, CODE_METRICS_DUP_MAX_SIZE,
# from `duplication.*` in the resolved config; a null or 0 cap exports empty).
# Registries come from every `--registry` plus `duplication.registries`, each
# resolved against the repository root; a named registry that does not exist is
# a usage error. Exit codes are the dispatcher's: 0 report produced, 2 usage
# error, 3 a collector ran and produced nothing parseable.
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
DISPATCH="$PLUGIN_ROOT/scripts/dispatch.sh"
REPORT="$PLUGIN_ROOT/scripts/report.py"
CLUSTER="$SCRIPT_DIR/cluster-clones.py"
FILTER="$SCRIPT_DIR/registry-filter.py"
# shellcheck source=../../../scripts/entry-common.sh
source "$PLUGIN_ROOT/scripts/entry-common.sh"

JSON=0
KEEP=0
CONFIG=""
REGISTRY_ARGS=()
PASS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    JSON=1
    shift
    ;;
  --keep)
    KEEP=1
    shift
    ;;
  --registry)
    if [[ $# -lt 2 ]]; then
      echo "audit-duplication.sh: --registry needs a value" >&2
      exit 2
    fi
    REGISTRY_ARGS+=("$2")
    shift 2
    ;;
  --config)
    if [[ $# -lt 2 ]]; then
      echo "audit-duplication.sh: --config needs a value" >&2
      exit 2
    fi
    CONFIG="$2"
    shift 2
    ;;
  --help | -h)
    cm_usage_banner "${BASH_SOURCE[0]}" 20
    exit 0
    ;;
  *)
    PASS_ARGS+=("$1")
    shift
    ;;
  esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=../../../scripts/python-resolve.sh
source "$PLUGIN_ROOT/scripts/python-resolve.sh"
if ! cm_resolve_python; then
  echo "audit-duplication.sh: Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); it is a required prerequisite" >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || ROOT="$PWD"

# Resolve the configuration once (or take the caller's --config), so the
# tunables the adapters read and the registries this script applies come from
# the same document the dispatcher measures against.
if [[ -z "$CONFIG" ]]; then
  CONFIG="$WORK/config.json"
  cm_resolve_config "$CONFIG" || exit 2
fi

# Six tunables (a cap of null or 0 is exported empty, which the adapter reads
# as "no cap"), then the registries from the resolver's own format
# (`scope.registries`, or `duplication.registries` as its older name), so this
# script and the dispatcher read the same list the same way.
if ! "${PY[@]}" -c '
import json, sys

section = json.load(open(sys.argv[1])).get("duplication") or {}


def number(key, fallback):
    value = section.get(key)
    return value if isinstance(value, int) and not isinstance(value, bool) else fallback


def cap(key):
    value = section.get(key)
    if value is None or isinstance(value, bool):
        return ""
    if isinstance(value, (int, float)):
        return str(int(value)) if value > 0 else ""
    text = str(value).strip()
    return "" if text in ("", "0") else text


def rollup_depth():
    value = section.get("rollup_depth", 2)
    if isinstance(value, bool) or not isinstance(value, int):
        sys.stderr.write(
            "audit-duplication.sh: duplication.rollup_depth must be an integer (got %r)\n"
            % (value,)
        )
        raise SystemExit(2)
    return value


print(number("min_tokens", 50))
print(number("min_lines", 5))
ignore = section.get("ignore")
print(",".join(str(item) for item in ignore) if isinstance(ignore, list) else "")
print(cap("max_lines"))
print(cap("max_size"))
print(rollup_depth())
' "$CONFIG" >"$WORK/dup-fields"; then
  exit 2
fi
mapfile -t DUP <"$WORK/dup-fields"
if [[ ${#DUP[@]} -lt 6 ]]; then
  echo "audit-duplication.sh: the resolved configuration could not be read" >&2
  exit 2
fi
export CODE_METRICS_DUP_MIN_TOKENS="${DUP[0]}"
export CODE_METRICS_DUP_MIN_LINES="${DUP[1]}"
export CODE_METRICS_DUP_IGNORE="${DUP[2]}"
export CODE_METRICS_DUP_MAX_LINES="${DUP[3]}"
export CODE_METRICS_DUP_MAX_SIZE="${DUP[4]}"
ROLLUP_DEPTH="${DUP[5]}"
if ! "${PY[@]}" "$PLUGIN_ROOT/scripts/resolve-config.py" --from-json "$CONFIG" --format registries >"$WORK/registries"; then
  echo "audit-duplication.sh: the configured registries could not be read (see the message above)" >&2
  exit 2
fi
mapfile -t CONFIGURED_REGISTRIES <"$WORK/registries"

FILTER_ARGS=(--root "$ROOT")
resolve_registry() {
  # A registry path as given, else the same path under the repository root.
  if [[ -f "$1" ]]; then
    printf '%s\n' "$1"
  elif [[ -f "$ROOT/$1" ]]; then
    printf '%s\n' "$ROOT/$1"
  else
    return 1
  fi
}
for registry in "${REGISTRY_ARGS[@]:-}" "${CONFIGURED_REGISTRIES[@]:-}"; do
  [[ -n "$registry" ]] || continue
  if ! resolved="$(resolve_registry "$registry")"; then
    echo "audit-duplication.sh: registry not found: $registry" >&2
    exit 2
  fi
  FILTER_ARGS+=(--registry "$resolved")
done

# The clone pairs come cwd-relative: the merge and the registry filter rebase
# them onto `--root` themselves. The final document is anchored once, below.
bash "$DISPATCH" audit-duplication --measures duplication --config "$CONFIG" --no-anchor ${PASS_ARGS[@]+"${PASS_ARGS[@]}"} >"$WORK/report.json"
rc=$?
[[ $rc -eq 0 || $rc -eq 3 ]] || exit "$rc"

# Merge the pairs the detector reports into clone classes, exclude the declared
# replication, recompute the totals from what survived, then state the zero the
# recomputation drops when every group was excluded.
"${PY[@]}" "$CLUSTER" --root "$ROOT" <"$WORK/report.json" >"$WORK/clustered.json" || exit 2
"${PY[@]}" "$FILTER" "${FILTER_ARGS[@]}" <"$WORK/clustered.json" >"$WORK/filtered.json" || exit 2
"${PY[@]}" "$REPORT" resummarize --root "$ROOT" <"$WORK/filtered.json" >"$WORK/summed.json" || exit 2
"${PY[@]}" "$FILTER" --zero-floor --root "$ROOT" <"$WORK/summed.json" >"$WORK/final.json" || exit 2

cm_anchor_document "$WORK/final.json" || exit 2

# The clone trend: this run's clone-class count beside the newest earlier
# persisted document of the same project (the persisted-report directory is
# per project) and the same scope mode, read before this run's own document is
# persisted. A document that measured nothing has no count and is passed over;
# with no earlier document the run carries no `trend` and prints no trend line.
# A failure here leaves the document as it was.
# shellcheck source=../../../scripts/persist-report.sh
source "$PLUGIN_ROOT/scripts/persist-report.sh"
if REPORT_DIR="$(cm_report_dir 2>/dev/null)" && [[ -d "$REPORT_DIR" ]]; then
  "${PY[@]}" -c '
import json, os, re, stat, sys

directory, current_path, line_path = sys.argv[1:4]
NAME = re.compile(r"^audit-duplication-(\d{8}T\d{6}Z)(?:-(\d+))?\.json$")
STAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")
MAX_BYTES = 5 * 1024 * 1024
MAX_COUNT = 10**9


class Rejected(Exception):
    pass


def natural(value):
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= MAX_COUNT:
        raise Rejected("not an integer from 0 to MAX_COUNT")
    return value


def mapping(value):
    if not isinstance(value, dict):
        raise Rejected("not an object")
    return value


def count(doc):
    summary = mapping(doc.get("summary", {}))
    if doc.get("status") == "empty" or "duplicated_lines" not in summary:
        raise Rejected("measured nothing")
    return natural(summary.get("clone_groups", 0))


def mode(doc):
    return mapping(doc.get("scope", {})).get("mode")


def classes(doc):
    """Each clone class as (first instance, copies, lines)."""
    rows = doc.get("measures", [])
    if not isinstance(rows, list):
        raise Rejected("measures is not a list")
    found = []
    for row in rows:
        instances = mapping(row).get("instances")
        if instances is None:
            continue
        if not isinstance(instances, list) or not instances:
            raise Rejected("instances is not a non-empty list")
        keys = []
        for instance in instances:
            instance = mapping(instance)
            name = instance.get("file")
            if not isinstance(name, str) or "\n" in name or "\r" in name:
                raise Rejected("instance file is not a one-line string")
            keys.append((name, natural(instance.get("start_line"))))
        lines = mapping(row.get("values", {})).get("lines")
        lines = lines if isinstance(lines, int) and not isinstance(lines, bool) and 0 <= lines <= MAX_COUNT else None
        found.append((sorted(keys), len(keys), lines))
    return found


def load(path):
    # Open without following a link and without blocking on a FIFO, then
    # read only a regular file under the size cap.
    flags = os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES:
            raise Rejected("not a regular file under the size cap")
        data = handle.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise Rejected("over the size cap")
    return mapping(json.loads(data.decode("utf-8")))


with open(current_path, encoding="utf-8") as handle:
    current = json.load(handle)
try:
    now = count(current)
    now_classes = classes(current)
    now_mode = mode(current)
except Exception:
    raise SystemExit(1)
earlier = []
for name in os.listdir(directory):
    match = NAME.match(name)
    if match:
        earlier.append(((match.group(1), int(match.group(2) or 0)), name))
for _, name in sorted(earlier, reverse=True):
    path = os.path.join(directory, name)
    try:
        previous = load(path)
        stamp = previous.get("generated_at")
        if not isinstance(stamp, str) or not STAMP.fullmatch(stamp):
            raise Rejected("generated_at is not a timestamp")
        if mode(previous) != now_mode or previous.get("schema") != current.get("schema"):
            continue
        before = count(previous)
        copies_before = {}
        for keys, copies, _ in classes(previous):
            for key in keys:
                copies_before[key] = max(copies, copies_before.get(key, 0))
    except Exception:
        continue
    new_classes, grown_classes = [], []
    for keys, copies, lines in now_classes:
        entry = {"file": keys[0][0], "start_line": keys[0][1], "copies": copies, "lines": lines}
        matched = [copies_before[key] for key in keys if key in copies_before]
        if not matched:
            new_classes.append(entry)
        elif max(matched) < copies:
            entry["previous_copies"] = max(matched)
            grown_classes.append(entry)
    current["trend"] = {
        "clone_groups": now,
        "previous_clone_groups": before,
        "delta": now - before,
        "previous_generated_at": stamp,
        "previous_document": path,
        "new_classes": new_classes,
        "grown_classes": grown_classes,
    }
    with open(current_path, "w", encoding="utf-8") as handle:
        json.dump(current, handle, indent=2)
        handle.write("\n")
    with open(line_path, "w", encoding="utf-8") as handle:
        handle.write(
            "Clone trend: %d clone class(es) now, %d in the previous run (%s), delta %+d; "
            "%d class(es) new since then, %d with more copies.\n"
            % (now, before, stamp, now - before, len(new_classes), len(grown_classes))
        )
    raise SystemExit(0)
raise SystemExit(1)
' "$REPORT_DIR" "$WORK/final.json" "$WORK/trend-line" 2>/dev/null || true
fi

if [[ "$JSON" -eq 1 && "$KEEP" -eq 1 ]]; then
  # stdout carries only the document; a directory that cannot be written says
  # so on stderr and the run goes on.
  cm_persist_report audit-duplication "$WORK/final.json" >/dev/null || true
fi
cm_emit_document audit-duplication "$JSON" "$WORK/final.json" --rollup-depth "$ROLLUP_DEPTH" || exit 2
if [[ "$JSON" -eq 0 && -s "$WORK/trend-line" ]]; then
  cat "$WORK/trend-line"
fi
exit "$rc"
