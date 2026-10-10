#!/usr/bin/env bash
# /code-metrics:audit-suppressions entry point: every lint and type-checker
# suppression in scope, with its rule ids, its reason, and whether it names a
# rule listed in `suppressions.correctness_rules`.
#
#   audit-suppressions.sh [--json | --findings [--memory-dir <dir>]] [--all] [--base <ref>]
#                         [--config <resolved.json>] [<path>...]
#
# The scope is the dispatcher's (scope.exclude and lane opt-outs apply).
# With no path and no --all, the change: only the lines the commits since
# the merge-base with the default branch (or --base) add. --all and paths scan
# whole files. Prints the markdown report; --json prints the document
# instead. --findings also writes a review-findings file to
# <memory-dir>/reviews/<branch-slug>/ (memory dir `.work` under the repository
# root unless named) and prints its path; with no current branch it writes
# nothing and exits 2. Exit 0 report produced, 2 usage error or a scan that failed.
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
FINDINGS=0
MEMORY_DIR=.work
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    JSON=1
    shift
    ;;
  --findings)
    FINDINGS=1
    shift
    ;;
  --memory-dir)
    [[ $# -ge 2 && -n "$2" ]] || die_usage "--memory-dir needs a value"
    MEMORY_DIR="$2"
    shift 2
    ;;
  --help | -h)
    cm_usage_banner "${BASH_SOURCE[0]}" 16
    exit 0
    ;;
  *)
    ARGS+=("$1")
    shift
    ;;
  esac
done

# The relay admits a findings file only on an exact `branch:` match, so with
# no branch there is no file it could ever read: refuse before scanning.
BRANCH=""
if [[ "$FINDINGS" -eq 1 ]]; then
  [[ "$JSON" -eq 0 ]] || die_usage "--findings prints the markdown report; drop --json"
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || die_usage "--findings: no current branch (detached HEAD or not a git repository); no findings file written"
fi

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

[[ "$FINDINGS" -eq 1 ]] || exit 0

# The findings file, under docs/conventions/detector-findings/README.md: rule
# ids, tiers and auto-applicability are that file's crosswalk rows, looked up
# here, never chosen per finding. Every value read from a source file (path,
# tool, rule ids, reason) is data: it is escaped into a table cell and never
# reaches a shell.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die_usage "--findings: not inside a git repository"
# shellcheck disable=SC2016 # the backticks are Markdown code spans in Python source, not substitutions
"${PY[@]}" -c '
import datetime, json, os, re, sys

doc_path, branch, root, memory_dir = sys.argv[1:5]
doc = json.load(open(doc_path, encoding="utf-8"))
scope = doc["scope"]
if scope["files"] == 0:
    print("\nNo findings file: 0 files in scope, so the run examined nothing to record.")
    sys.exit(0)

SURFACE = "code-metrics:audit-suppressions"
NO_REASON = "code-metrics/audit-suppressions/rule-no-reason"
NO_RULE_ID = "code-metrics/audit-suppressions/rule-no-rule-id"
TIER = "IMPORTANT"  # both rules, per their crosswalk rows
DEFAULT_SLOT = "in a comment after the directive on the same line"
SLOTS = {
    "eslint": "after ` -- ` at the end of the directive",
    "rubocop": "after ` -- ` at the end of the directive",
    "csharp": "in the `Justification` argument of the attribute",
    "csharp-pragma": "in a `//` comment after the pragma on the same line",
    "powershell": "in a `Justification` argument on the attribute",
    "markdownlint": "in a second `<!-- -->` comment on the same line",
}


def cell(value):
    text = str(value).replace("\\", "\\\\").replace("|", "\\|")
    return text.replace("\r", " ").replace("\n", " ")


def subject(r):
    if r["rules"]:
        return "%s suppression of %s" % (r["tool"], ", ".join(r["rules"]))
    if r["tool"] == "typescript":
        return "typescript directive (it cannot name an error code)"
    return "%s suppression naming no rule id" % r["tool"]


def is_pragma(rel, line):
    # A C# pragma has no Justification argument, so its reason slot differs
    # from the attribute form the scanner reports under the same tool name.
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as handle:
            for number, text in enumerate(handle, 1):
                if number == line:
                    return re.match(r"\s*#\s*pragma\s+warning\s+disable\b", text) is not None
    except OSError:
        pass
    return False


def action_no_reason(r, rel):
    if r["tool"] == "typescript":
        return ("Decide whether the silenced error is a false positive. If it is, write the reason as "
                "text after the directive on the same line; if it is not, fix the code and delete the directive.")
    name = "" if r["rules"] else "name the rule id it silences in the directive and "
    tool = "csharp-pragma" if r["tool"] == "csharp" and is_pragma(rel, r["line"]) else r["tool"]
    return ("Decide whether the silenced check is a false positive. If it is, %swrite the reason %s; "
            "if it is not, fix the code and delete the suppression." % (name, SLOTS.get(tool, DEFAULT_SLOT)))


def action_no_rule_id(r):
    return ("The directive silences every rule the tool checks on its span. Name the rule id the stated "
            "reason is about in the directive; if the reason covers no single rule, fix the code and "
            "delete the suppression.")


# The scanner prints paths relative to the repository root; one outside it
# cannot be a repo-relative Location, so it is counted rather than emitted.
root = os.path.realpath(root)
rows, outside = [], 0
declined = {"reason-on-line": 0, "rule-id-on-line": 0, "tool-names-no-rule": 0}
for r in doc["suppressions"]:
    rel = os.path.relpath(os.path.normpath(os.path.join(root, r["file"])), root).replace(os.sep, "/")
    if rel == ".." or rel.startswith("../"):
        outside += 1
        continue
    where = "%s:%d" % (rel, r["line"])
    if not r["reason"]:
        rows.append((rel, r["line"], where, "%s: %s, no reason on the line" % (NO_REASON, subject(r)), action_no_reason(r, rel)))
        continue
    declined["reason-on-line"] += 1
    if not r["justified"]:
        rows.append((rel, r["line"], where, "%s: %s, reason \"%s\"" % (NO_RULE_ID, subject(r), r["reason"]), action_no_rule_id(r)))
    elif r["rules"]:
        declined["rule-id-on-line"] += 1
    else:
        declined["tool-names-no-rule"] += 1
rows.sort(key=lambda row: (row[0], row[1]))

slug = re.sub(r"[^a-z0-9._-]", "-", branch.lower())
memory = memory_dir if os.path.isabs(memory_dir) else os.path.join(root, memory_dir)
target_dir = os.path.join(memory, "reviews", slug)
os.makedirs(target_dir, exist_ok=True)
ignore = os.path.join(memory, ".gitignore")
if not os.path.exists(ignore):
    with open(ignore, "w", encoding="utf-8") as handle:
        handle.write("*\n")
    print("audit-suppressions.sh: created %s holding * so the memory root stays out of git" % ignore, file=sys.stderr)

now = datetime.datetime.now(datetime.timezone.utc)
stem = os.path.join(target_dir, now.strftime("%Y%m%dT%H%M%SZ") + "-suppressions")
n = 1
while True:
    path = stem + (".md" if n == 1 else "-%d.md" % n)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        break
    except FileExistsError:
        n += 1

mode = {"change": "lines added since %s" % scope["base"], "all": "the whole tree", "paths": "the named paths"}[scope["mode"]]
emitted = {row[3].split(":", 1)[0] for row in rows}
quiet = [rule for rule in (NO_REASON, NO_RULE_ID) if rule not in emitted]
out = ["---", "type: review-findings", "date: %s" % now.strftime("%Y-%m-%dT%H:%M:%SZ"), "branch: %s" % branch, "---", "",
       "## Findings", "",
       "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |",
       "|------|------|------------|----------|------------|---------|--------|"]
for rank, row in enumerate(rows, 1):
    out.append("| %d | %s | high | %s | %s | %s | %s |" % (rank, TIER, cell(row[2]), SURFACE, cell(row[3]), cell(row[4])))
ran = "Ran: [%s (%s, %d files in scope, %d suppressions examined)]." % (SURFACE, mode, scope["files"], len(doc["suppressions"]))
if quiet:
    ran += " Returned no result: [%s]." % ", ".join(quiet)
out += ["", "## Surfaces", "", ran]
out.append("Declined candidates: %s count=%d reason=reason-on-line" % (NO_REASON, declined["reason-on-line"]))
out.append("Declined candidates: %s count=%d reason=rule-id-on-line" % (NO_RULE_ID, declined["rule-id-on-line"]))
out.append("Declined candidates: %s count=%d reason=tool-names-no-rule" % (NO_RULE_ID, declined["tool-names-no-rule"]))
if outside:
    out.append("Not examined: %d suppressions outside the repository root." % outside)
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
    handle.write("\n".join(out) + "\n")
print("\nFindings file: %s" % path)
' "$WORK/report.json" "$BRANCH" "$ROOT" "$MEMORY_DIR" || exit 2
exit 0
