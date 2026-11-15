#!/usr/bin/env bash
# Regression tests for the audit-size entry point (audit-size.sh): option parsing,
# JSON versus markdown output, and exit-code passthrough from dispatch.sh.
# test-scope: plugins/code-metrics/scripts/collectors/*.py plugins/code-metrics/scripts/fixtures/* plugins/code-metrics/skills/audit/SKILL.md plugins/code-metrics/skills/audit/actions/size.md
# test-scope: plugins/code-metrics/scripts/yaml_subset.py
# test-scope: .claude/ecosystems/*.yaml # runs from the repo root, so the config resolver reads its lanes
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-size.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SOURCES="plugins/code-metrics/scripts/fixtures/sources"
cd "$REPO_ROOT" || exit 2

FAILED=0
CASE_NUM=0
# shellcheck source=../../../scripts/test-helpers.sh
source "$PLUGIN_ROOT/scripts/test-helpers.sh"

unset CODE_METRICS_DISABLE_BUNDLED
REPORTS="$(mktemp -d)"
EMPTY_PATH="$(mktemp -d)"
NO_PYTHON="$(mktemp -d)"
trap 'rm -rf "$REPORTS" "$EMPTY_PATH" "$NO_PYTHON"' EXIT
export CODE_METRICS_REPORT_DIR="$REPORTS"

out="$(bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "--json exits 0" 0 "$rc"
assert_doc "--json prints a code-metrics/v2 document for audit-size" "$out" \
  'd["schema"]=="code-metrics/v2" and d["skill"]=="audit-size" and d["run"]'

out="$(bash "$SCRIPT" --all "$SOURCES")"
rc=$?
assert_eq "markdown exits 0" 0 "$rc"
assert_contains "markdown carries the run table" "$out" "## Coverage of this run"
assert_contains "markdown carries the plugin-default reference" "$out" "| file_lines | 1000 |"
assert_contains "markdown lists the python fixture" "$out" "cm_sample.py"

# A host scc would still measure; the tool-free PATH keeps every collector away.
# shellcheck source=../../../scripts/tool-free-path.sh
source "$PLUGIN_ROOT/scripts/tool-free-path.sh"
cm_assert_tool_free_path "$EMPTY_PATH"
out="$(CODE_METRICS_DISABLE_BUNDLED=1 PATH="$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES" 2>/dev/null || true)"
assert_contains "all-unavailable run renders the Measured nothing headline" "$out" "Measured nothing"

bash "$SCRIPT" "$SOURCES/does-not-exist.py" >/dev/null 2>&1
assert_eq "a missing explicit path exits 2" 2 "$?"

out="$(bash "$SCRIPT" --json --all --file-lines 10 "$SOURCES")"
assert_eq "--file-lines exits 0" 0 "$?"
assert_doc "--file-lines replaces the reference and names itself as the layer" "$out" \
  'next(t for t in d["thresholds"] if t["measure"]=="file_lines")["reference"]==10 and next(t for t in d["thresholds"] if t["measure"]=="file_lines")["layer"]=="this run (--file-lines)"'
assert_doc "--file-lines counts files against the new reference" "$out" \
  'any("file_lines" in (m.get("over_reference") or []) for m in d["measures"])'
out="$(bash "$SCRIPT" --json --all "$SOURCES")"
assert_doc "without --file-lines no fixture is over the reference" "$out" \
  'not any(m.get("over_reference") for m in d["measures"])'
for bad in 0 -5 12x ""; do
  err="$(bash "$SCRIPT" --all --file-lines "$bad" "$SOURCES" 2>&1 >/dev/null)"
  assert_eq "--file-lines '$bad' exits 2" 2 "$?"
  assert_contains "--file-lines '$bad' names the option" "$err" "--file-lines takes a positive whole number"
done
bash "$SCRIPT" --all "$SOURCES" --file-lines >/dev/null 2>&1
assert_eq "--file-lines with no value exits 2" 2 "$?"

# --commits-since against a scratch repository: one long file committed three
# times (once by a bot), one long file committed once, one short file.
CHURN="$(mktemp -d)"
(
  cd "$CHURN" || exit 2
  git init -q && git symbolic-ref HEAD refs/heads/main
  commit() { git -c user.name="$1" -c user.email=t@example.invalid commit -q -m "$2"; }
  seq 1 30 >busy.txt && seq 1 40 >quiet.txt && echo one >short.txt
  git add busy.txt quiet.txt short.txt && commit dev "add"
  echo 31 >>busy.txt && git add busy.txt && commit dev "busy again"
  echo 32 >>busy.txt && git add busy.txt && commit 'release[bot]' "bot touch"
)
out="$(cd "$CHURN" && bash "$SCRIPT" --json --all --file-lines 20 --commits-since "10 years ago")"
assert_eq "--commits-since exits 0" 0 "$?"
assert_doc "--commits-since lists only files at or above the reference, most commits first, bots left out" "$out" \
  '[(r["file"], r["commits"]) for r in d["file_commits"]["rows"]] == [("busy.txt", 2), ("quiet.txt", 1)]'
out="$(cd "$CHURN" && bash "$SCRIPT" --all --file-lines 20 --commits-since "10 years ago")"
assert_contains "--commits-since renders its table in markdown" "$out" "| busy.txt | 32 | 2 |"
out="$(bash "$SCRIPT" --json --all "$SOURCES")"
assert_doc "no --commits-since, no file_commits key" "$out" '"file_commits" not in d'
bash "$SCRIPT" --all "$SOURCES" --commits-since >/dev/null 2>&1
assert_eq "--commits-since with no value exits 2" 2 "$?"
rm -rf "${CHURN:?}"

grep -q 'audit-size.sh \[--json\]' < <(bash "$SCRIPT" --help 2>&1)
assert_eq "--help prints usage" 0 "$?"

# No interpreter passes the floor probe: the shared cm_require_python prints
# the prerequisite line under this script's name and exits 2. Failing stubs go
# in front of the whole PATH, as python-resolve.test.sh does, rather than on a
# bare PATH, so bash and the coreutils the script runs first still resolve.
for name in python3 python py; do
  printf '#!/usr/bin/env bash\nexit 1\n' >"$NO_PYTHON/$name"
  chmod +x "$NO_PYTHON/$name"
done
floor="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$PLUGIN_ROOT/scripts/report.py")"
err="$(PATH="$NO_PYTHON:$PATH" bash "$SCRIPT" --all "$SOURCES" 2>&1 >/dev/null)"
rc=$?
assert_eq "no Python exits 2" 2 "$rc"
assert_eq "no Python prints the prerequisite line" \
  "audit-size.sh: Python ${floor}+ not found (tried python3, python, py -3); it is a required prerequisite" "$err"

# The 1000-line provenance is one sentence, owned by the bundled defaults and
# repeated verbatim where a reader meets the number without the report: the
# size action body and the principles threshold table. A rewording in one place
# is a second story about where the number came from.
provenance="$("$PY" -c '
import json, sys
doc = json.load(open(sys.argv[1]))
print(next(t["provenance"] for t in doc["thresholds"] if t["measure"] == "file_lines"))
' "$PLUGIN_ROOT/scripts/config-defaults.json")"
for surface in "$SCRIPT_DIR/../actions/size.md" "$SCRIPT_DIR/../../principles/reference/thresholds.md"; do
  # Markdown wraps the sentence across lines; compare with whitespace folded.
  folded="$(tr -s '[:space:]' ' ' <"$surface")"
  case "$folded" in
  *"$provenance"*) pass "${surface##*/} carries the file_lines provenance verbatim" ;;
  *) fail "${surface##*/} carries the file_lines provenance verbatim" "$provenance" "$(printf '%s' "$folded" | grep -o '.\{0,80\}ISO-backed.\{0,80\}' | head -1)" ;;
  esac
done

# The router's description names `--all` as a scope in its own right and no
# longer disowns the whole-tree run, and stays inside the field maximum.
description="$(sed -n '2p' "$SCRIPT_DIR/../SKILL.md")"
case "$description" in
*"wrong tool"*) fail "the description no longer disowns --all" "no 'wrong tool' clause" "$description" ;;
*"(\`--all\`)"*) pass "the description no longer disowns --all" ;;
*) fail "the description no longer disowns --all" "names --all" "$description" ;;
esac
length="$("$PY" -c 'import sys; print(len(sys.argv[1]))' "$description")"
if [[ "$length" -lt 1024 ]]; then pass "the description is under 1024 codepoints ($length)"; else fail "the description is under 1024 codepoints" "< 1024" "$length"; fi

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
