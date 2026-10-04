#!/usr/bin/env bash
# /code-metrics:audit-suppressions entry point: every lint and type-checker
# suppression in scope, with its rule ids, its reason, and whether it names a
# rule listed in `suppressions.correctness_rules`.
#
#   audit-suppressions.sh [--json] [--all] [--base <ref>] [--config <resolved.json>] [<path>...]
#
# The scope is the dispatcher's (scope.exclude and lane opt-outs apply).
# With no path and no --all, the change: only the lines the commits since
# the merge-base with the default branch (or --base) add. --all and paths scan
# whole files. Prints the markdown report; --json prints the document
# instead. Exit 0 report produced, 2 usage error or a scan that failed.
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
DISPATCH="$PLUGIN_ROOT/scripts/dispatch.sh"
SCANNER="$SCRIPT_DIR/suppression-scan.py"
# shellcheck source=../../../scripts/entry-common.sh
source "$PLUGIN_ROOT/scripts/entry-common.sh"

die_usage() {
  printf 'audit-suppressions.sh: %s\n' "$1" >&2
  exit 2
}

JSON=0
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    JSON=1
    shift
    ;;
  --help | -h)
    cm_usage_banner "${BASH_SOURCE[0]}" 11
    exit 0
    ;;
  *)
    ARGS+=("$1")
    shift
    ;;
  esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=../../../scripts/python-resolve.sh
source "$PLUGIN_ROOT/scripts/python-resolve.sh"
if ! cm_resolve_python; then
  die_usage "Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); it is a required prerequisite"
fi

cm_split_config "${ARGS[@]}"
if [[ -z "$CM_CONFIG" ]]; then
  CM_CONFIG="$WORK/config.json"
  cm_resolve_config "$CM_CONFIG" || exit 2
fi

# The scope mode, read the way the dispatcher reads it: --all or a path
# widens to whole files; scope.default `all` applies only when the command
# line named neither and no --base.
MODE=change
BASE=""
BASE_SET=0
set -- "${CM_PASS_ARGS[@]}"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --all) MODE=all ;;
  --base)
    [[ $# -ge 2 ]] || die_usage "--base needs a value"
    BASE="$2"
    BASE_SET=1
    shift
    ;;
  --) MODE=paths ;;
  -*) die_usage "unknown option: $1" ;;
  *) [[ "$MODE" == all ]] || MODE=paths ;;
  esac
  shift
done
read -r CFG_DEFAULT CFG_BASE < <("${PY[@]}" -c '
import json, sys
scope = json.load(open(sys.argv[1], encoding="utf-8")).get("scope") or {}
base = scope.get("base")
print(scope.get("default") or "change", base.strip() if isinstance(base, str) and base.strip() else "auto")
' "$CM_CONFIG")
if [[ "$MODE" == change && "$BASE_SET" -eq 0 && "$CFG_DEFAULT" == all ]]; then MODE=all; fi
[[ "$BASE_SET" -eq 1 ]] || BASE="$CFG_BASE"

bash "$DISPATCH" audit-suppressions --measures file_lines --print-scope --config "$CM_CONFIG" \
  "${CM_PASS_ARGS[@]}" >"$WORK/lanes" || exit 2
cut -f2- "$WORK/lanes" >"$WORK/scope"

BASE_SHA=""
SCAN_ARGS=(--paths-from "$WORK/scope")
if [[ "$MODE" == change ]]; then
  if [[ "$BASE" == auto ]]; then
    BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [[ -z "$BASE" ]]; then
      for candidate in origin/main origin/master main master; do
        if git rev-parse --verify --quiet "$candidate" >/dev/null; then
          BASE="$candidate"
          break
        fi
      done
    fi
    [[ -n "$BASE" ]] || die_usage "cannot find a default branch for the merge-base; pass --base <ref>"
  fi
  [[ "$BASE" != -* ]] || die_usage "a base ref must not start with '-': $BASE"
  BASE_SHA="$(git merge-base HEAD "$BASE" 2>/dev/null || true)"
  [[ -n "$BASE_SHA" ]] || die_usage "no merge-base between HEAD and $BASE; pass --base <ref>"
  SCAN_ARGS+=(--diff "$BASE_SHA")
fi

# The correctness list travels as a file, one rule id per line.
"${PY[@]}" -c '
import json, sys
config = json.load(open(sys.argv[1], encoding="utf-8"))
rules = (config.get("suppressions") or {}).get("correctness_rules") or []
print("\n".join(str(r) for r in rules if str(r).strip()))
' "$CM_CONFIG" >"$WORK/rules" || exit 2
SCAN_ARGS+=(--correctness-rules "$WORK/rules")

if [[ -s "$WORK/scope" ]]; then
  "${PY[@]}" "$SCANNER" "${SCAN_ARGS[@]}" >"$WORK/found.json" || exit 2
else
  # An empty list would read as "scan the repository".
  printf '[]\n' >"$WORK/found.json"
fi

"${PY[@]}" -c '
import datetime, json, sys
config_path, found_path, mode, base, scope_path = sys.argv[1:6]
config = json.load(open(config_path, encoding="utf-8"))
found = json.load(open(found_path, encoding="utf-8"))
with open(scope_path, encoding="utf-8", errors="replace") as handle:
    files = sum(1 for line in handle if line.strip())
rules = (config.get("suppressions") or {}).get("correctness_rules") or []
layer = (config.get("_layers") or {}).get("suppressions.correctness_rules", "bundled default")
print(json.dumps({
    "schema": "code-metrics/suppressions/v1",
    "skill": "audit-suppressions",
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "scope": {"mode": mode, "base": base[:12] or None, "files": files},
    "correctness_rules": {"rules": [str(r) for r in rules], "layer": layer},
    "counts": {
        "suppressions": len(found),
        "unjustified": sum(1 for r in found if not r["justified"]),
        "correctness": sum(1 for r in found if r.get("correctness")),
    },
    "suppressions": found,
}, indent=2))
' "$CM_CONFIG" "$WORK/found.json" "$MODE" "$BASE_SHA" "$WORK/scope" >"$WORK/report.json" || exit 2

if [[ "$JSON" -eq 1 ]]; then
  cat "$WORK/report.json"
  exit 0
fi

# shellcheck source=../../../scripts/persist-report.sh
source "$PLUGIN_ROOT/scripts/persist-report.sh"
KEPT="$(cm_persist_report audit-suppressions "$WORK/report.json")" || KEPT=""

# shellcheck disable=SC2016 # the backticks are Markdown code spans in Python source, not substitutions
"${PY[@]}" -c '
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
kept = sys.argv[2]
CAP = 200

def cell(value):
    return str(value).replace("\\", "\\\\").replace("|", "\\|").replace("`", "\\`")

scope, counts = doc["scope"], doc["counts"]
where = {"change": "lines added since %s" % scope["base"], "all": "the whole tree", "paths": "the named paths"}[scope["mode"]]
print("# Suppressions: %s (%d files in scope)\n" % (where, scope["files"]))
listed = doc["correctness_rules"]
summary = "%d suppressions, %d without a reason (or without a rule id where the tool can name one)" % (
    counts["suppressions"], counts["unjustified"])
if listed["rules"]:
    summary += ", %d naming a correctness rule" % counts["correctness"]
print(summary + ".\n")
if listed["rules"]:
    print("Correctness rules (%s): %s\n" % (listed["layer"], ", ".join("`%s`" % cell(r) for r in listed["rules"])))
else:
    print("Correctness rules: none listed (`suppressions.correctness_rules`).\n")
rows = sorted(doc["suppressions"], key=lambda r: (not r.get("correctness"), r["justified"], r["file"], r["line"]))
if rows:
    print("| File | Line | Tool | Rules | Justified | Correctness | Reason |")
    print("|---|---|---|---|---|---|---|")
    for r in rows[:CAP]:
        print("| %s | %d | %s | %s | %s | %s | %s |" % (
            cell(r["file"]), r["line"], r["tool"], cell(", ".join(r["rules"]) or "-"),
            "yes" if r["justified"] else "no", "yes" if r.get("correctness") else "no",
            cell(r["reason"] or "-")))
    if len(rows) > CAP:
        print("\n%d more rows are in the document." % (len(rows) - CAP))
if kept:
    print("\nDocument: %s" % kept)
elif len(rows) > CAP:
    print("\nRe-run with --json for every row.")
' "$WORK/report.json" "$KEPT" || exit 2
exit 0
