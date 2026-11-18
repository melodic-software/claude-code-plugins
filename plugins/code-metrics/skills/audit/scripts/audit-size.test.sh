#!/usr/bin/env bash
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

CHURN="$(mktemp -d)"
(
  cd "$CHURN" || exit 2
  git init -q && git symbolic-ref HEAD refs/heads/main
  commit() { git -c user.name="$1" -c user.email=t@example.invalid commit -q -m "$2"; }
  seq 1 30 >busy.txt && seq 1 40 >quiet.txt && echo one >short.txt
  git add busy.txt quiet.txt short.txt && commit dev "add"
  echo 31 >>busy.txt && git add busy.txt && commit dev "busy again"
  echo 32 >>busy.txt && git add busy.txt && commit 'release[bot]' "bot touch"
  git mv busy.txt moved.txt && commit dev "move"
)
out="$(cd "$CHURN" && bash "$SCRIPT" --json --all --file-lines 20 --commits-since "10 years ago")"
assert_eq "--commits-since exits 0" 0 "$?"
assert_doc "--commits-since lists only files at or above the reference, most commits first, bots left out, renames followed" "$out" \
  '[(r["file"], r["commits"]) for r in d["file_commits"]["rows"]] == [("moved.txt", 3), ("quiet.txt", 1)]'
out="$(cd "$CHURN" && bash "$SCRIPT" --all --file-lines 20 --commits-since "10 years ago")"
assert_contains "--commits-since renders its table in markdown" "$out" "| moved.txt | 32 | 3 |"
out="$(bash "$SCRIPT" --json --all "$SOURCES")"
assert_doc "no --commits-since, no file_commits key" "$out" '"file_commits" not in d'
bash "$SCRIPT" --all "$SOURCES" --commits-since >/dev/null 2>&1
assert_eq "--commits-since with no value exits 2" 2 "$?"
rm -rf "${CHURN:?}"

GATE="$(mktemp -d)"
GATE_HOME="$(mktemp -d)"
(
  cd "$GATE" || exit 2
  git init -q && git symbolic-ref HEAD refs/heads/main
  seq 1 3 >small.txt && seq 1 6 >over.txt
  git add small.txt over.txt
  git -c user.name=dev -c user.email=t@example.invalid commit -q -m base
  mkdir -p docs/conventions .claude
)
team() { printf 'scope:\n  exclude: ["docs/**", ".claude/**"]\nsize:\n%s' "$1" >"$GATE/docs/conventions/code-metrics.yaml"; }
gate() { (cd "$GATE" && CODE_METRICS_HOME="$GATE_HOME" bash "$SCRIPT" --base HEAD "$@" 2>&1); }

team $'  file_lines: 5\n  check: crossing\n'
seq 1 6 >"$GATE/small.txt"
out="$(gate --check)"
assert_eq "--check fails a file that crossed the reference (exit 1)" 1 "$?"
assert_contains "--check names the crossing with both counts" "$out" "| small.txt | 3 | 6 | fails: crossed the reference |"
assert_contains "--check says what to do" "$out" "Split each failing file along a real responsibility boundary"
out="$(cd "$GATE" && CODE_METRICS_HOME="$GATE_HOME" bash "$SCRIPT" --json --base HEAD --check 2>/dev/null)"
assert_eq "--json --check keeps the failing exit" 1 "$?"
assert_doc "--json --check carries the size_check block" "$out" \
  'd["size_check"]["rule"]=="crossing" and d["size_check"]["layer"]=="team" and d["size_check"]["failed"]==1'
gate >/dev/null
assert_eq "without --check the crossing only reports (exit 0)" 0 "$?"
out="$(gate --check --all)"
assert_eq "--check over --all cannot decide (exit 2)" 2 "$?"
assert_contains "--check over --all says it needs the change scope" "$out" "needs the change scope"

printf '.claude/\n' >"$GATE/.gitignore"
printf 'size:\n  check: report\n' >"$GATE/.claude/code-metrics.local.yaml"
out="$(gate --check)"
assert_eq "a personal override of report wins over the team rule (exit 0)" 0 "$?"
assert_contains "the report names the personal layer" "$out" "\`size.check\` is \`report\` (local)"
rm -f "$GATE/.claude/code-metrics.local.yaml" "$GATE/.gitignore"

team $'  file_lines: 50\n  check: crossing\n'
gate --check >/dev/null
assert_eq "a raised team reference is honored (exit 0)" 0 "$?"
team $'  file_lines: 5\n  check: crossing\n'
gate --check --file-lines 50 >/dev/null
assert_eq "a raised --file-lines reference is honored (exit 0)" 0 "$?"
printf 'scope:\n  exclude: ["docs/**", ".claude/**", "small.txt"]\nsize:\n  file_lines: 5\n  check: crossing\n' >"$GATE/docs/conventions/code-metrics.yaml"
gate --check >/dev/null
assert_eq "an excluded file is not checked (exit 0)" 0 "$?"

team $'  file_lines: 5\n  check: report\n'
gate --check >/dev/null
assert_eq "check off passes whatever the sizes (exit 0)" 0 "$?"

seq 1 3 >"$GATE/small.txt"
seq 1 9 >"$GATE/over.txt"
team $'  file_lines: 5\n  check: crossing\n'
out="$(gate --check)"
assert_eq "an already-over file that grew passes under crossing (exit 0)" 0 "$?"
assert_contains "and is reported" "$out" "| over.txt | 6 | 9 | reported: already over, grew |"
team $'  file_lines: 5\n  check: crossing-or-growth\n'
gate --check >/dev/null
assert_eq "an already-over file that grew fails under crossing-or-growth (exit 1)" 1 "$?"

BROKEN="$(mktemp -d)"
cat >"$BROKEN/scc" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then printf 'scc version 9.9.9\n'; exit 0; fi
printf 'not json\n'
exit 1
EOF
chmod +x "$BROKEN/scc"
team $'  file_lines: 5\n  check: report\n'
(cd "$GATE" && CODE_METRICS_HOME="$GATE_HOME" PATH="$BROKEN:$PATH" bash "$SCRIPT" --base HEAD --check >/dev/null 2>&1)
assert_eq "--check under report keeps a failed collector's exit 3" 3 "$?"
team $'  file_lines: 5\n  check: crossing\n'
(cd "$GATE" && CODE_METRICS_HOME="$GATE_HOME" PATH="$BROKEN:$PATH" bash "$SCRIPT" --base HEAD --check >/dev/null 2>&1)
assert_eq "--check under a rule cannot decide past a failed collector (exit 2)" 2 "$?"
rm -rf "${BROKEN:?}"

team $'  file_lines: 5\n  check: true\n'
out="$(gate --check)"
assert_eq "an invalid size.check exits 2" 2 "$?"
assert_contains "the invalid value is named" "$out" "size.check must be report, crossing or crossing-or-growth"
rm -rf "${GATE:?}" "${GATE_HOME:?}"

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
  folded="$(tr -s '[:space:]' ' ' <"$surface")"
  case "$folded" in
  *"$provenance"*) pass "${surface##*/} carries the file_lines provenance verbatim" ;;
  *) fail "${surface##*/} carries the file_lines provenance verbatim" "$provenance" "$(printf '%s' "$folded" | grep -o '.\{0,80\}ISO-backed.\{0,80\}' | head -1)" ;;
  esac
done

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
