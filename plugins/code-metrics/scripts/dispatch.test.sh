#!/usr/bin/env bash
# Regression tests for dispatch.sh: scope, ladder walk, run rows, status, exit
# codes. Collectors are stubbed at runtime: a temporary bin/ prepended to PATH
# carries a fake `scc` that replays fixtures/tool-output/scc.json (design T13;
# nothing executable is committed). The adapters themselves (scc.py,
# line-counter.py) and report.py are exercised through the dispatcher.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/dispatch.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SOURCES="plugins/code-metrics/scripts/fixtures/sources"
CAPTURE="$SCRIPT_DIR/fixtures/tool-output/scc.json"
cd "$REPO_ROOT" || exit 2

PY=python3
command -v python3 >/dev/null 2>&1 || PY=python

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
# jq-free JSON assertions: a Python expression over the parsed document `d`.
assert_doc() {
  # assert_doc <name> <json> <python-expression>
  if printf '%s' "$2" | "$PY" -c "import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if ($3) else 1)" 2>/dev/null; then
    pass "$1"
  else
    fail "$1" "$3" "$(printf '%s' "$2" | head -c 600)"
  fi
}

STUBS="$(mktemp -d)"
EMPTY_PATH="$(mktemp -d)"
trap 'rm -rf "$STUBS" "$EMPTY_PATH"' EXIT
cat >"$STUBS/scc" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf 'scc version 3.7.0\n'; exit 0; fi
cat "$CAPTURE"
EOF
chmod +x "$STUBS/scc"
# EMPTY_PATH is the caller's PATH with every collector removed: a directory of
# symlinks to each executable on PATH except the tools the ladder names, so
# the coreutils, git, and the interpreter stay reachable while `scc` does not.
COLLECTOR_NAMES=" scc lizard radon multimetric jscpd gocyclo gocognit dupl shellmetrics type-coverage mypy pmd eslint "
IFS=':' read -r -a path_dirs <<<"$PATH"
for dir in "${path_dirs[@]}"; do
  [[ -d "$dir" ]] || continue
  for exe in "$dir"/*; do
    [[ -f "$exe" && -x "$exe" ]] || continue
    name="${exe##*/}"
    [[ "$COLLECTOR_NAMES" == *" $name "* ]] && continue
    [[ -e "$EMPTY_PATH/$name" ]] || ln -s "$exe" "$EMPTY_PATH/$name"
  done
done
unset CODE_METRICS_DISABLE_BUNDLED

# 1. scc absent: the bundled counter is used and the run row names it.
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --all "$SOURCES")"
rc=$?
assert_eq "exit 0 with the bundled counter" 0 "$rc"
assert_doc "schema, skill, and status complete" "$out" \
  'd["schema"]=="code-metrics/v1" and d["skill"]=="audit-size" and d["status"]=="complete"'
assert_doc "every lane row is ok on line-counter" "$out" \
  'all(r["status"]=="ok" and r["collector"].startswith("line-counter") for r in d["run"]) and len(d["run"])==5'
assert_doc "rows carry comment-agnostic label and non-blank counts" "$out" \
  'all("comment-agnostic" in r["labels"] and r["values"]["lines_non_blank"]>0 for r in d["measures"]) and d["summary"]["files"]==7'
assert_doc "markdown fixture is outside every lane" "$out" 'not any(r["file"].endswith("cm-notes.md") for r in d["measures"])'
# The five lane fixtures by name (cm-sample.ts, cm_sample.py, cm-sample.sh, cm-sample.go,
# CmSample.cs) plus the two byte-identical bash copies of the duplication cluster fixture
# (cluster/{alpha,beta}/shared/shared-utils.sh): the assertion is also what maps them to this suite.
assert_doc "every lane fixture is measured exactly once" "$out" \
  'sorted(r["file"].rsplit("/",1)[1] for r in d["measures"])==["CmSample.cs","cm-sample.go","cm-sample.sh","cm-sample.ts","cm_sample.py","shared-utils.sh","shared-utils.sh"]'
assert_doc "threshold carries the plugin-default provenance" "$out" \
  'd["thresholds"][0]["measure"]=="file_lines" and d["thresholds"][0]["reference"]==1000 and "not normative" in d["thresholds"][0]["provenance"]'

# 2. scc present: the ladder prefers it and comment counts appear.
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --all "$SOURCES")"
rc=$?
assert_eq "exit 0 with the scc stub" 0 "$rc"
assert_doc "every lane row names scc 3.7.0" "$out" 'all(r["collector"]=="scc 3.7.0" for r in d["run"])'
assert_doc "python row has scc comment and code counts" "$out" \
  'next(r for r in d["measures"] if r["file"].endswith("cm_sample.py"))["values"]=={"lines_total":20,"lines_blank":4,"lines_comment":8,"lines_code":8,"lines_non_blank":16}'

# 3. All lanes unavailable: exit 0, status empty, every run row non-ok with a reason.
out="$(PATH="$EMPTY_PATH" CODE_METRICS_DISABLE_BUNDLED=1 bash "$SCRIPT" audit-size --measures file_lines --all "$SOURCES")"
rc=$?
assert_eq "exit 0 when nothing could be measured" 0 "$rc"
assert_doc "status empty and every row unavailable with a reason" "$out" \
  'd["status"]=="empty" and d["run"] and all(r["status"]!="ok" and r["reason"] for r in d["run"]) and len(d["unavailable"])==5 and d["measures"]==[]'
assert_doc "the reason names both rungs and the install hint" "$out" \
  '"scc: scc not on PATH" in d["run"][0]["reason"] and "line-counter: disabled by CODE_METRICS_DISABLE_BUNDLED" in d["run"][0]["reason"] and "boyter/scc" in d["run"][0]["reason"]'

# 4. A ladder row whose adapter does not exist is reported, not skipped.
ladder="$(mktemp)"
printf 'python\tfile_lines\tnot-a-tool\n' >"$ladder"
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --ladder "$ladder" "$SOURCES/cm_sample.py")"
assert_doc "adapter not shipped is the reason" "$out" \
  'd["run"][0]["status"]=="unavailable" and d["run"][0]["reason"]=="not-a-tool: adapter not shipped"'
rm -f "$ladder"

# 5. A measure with a `*` deferred row and a lane with an explicit `none` row.
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" audit-complexity --measures cyclomatic,cognitive --all "$SOURCES")"
rc=$?
assert_eq "exit 0 with deferred and none rows" 0 "$rc"
assert_doc "dotnet cyclomatic is deferred with the research tag" "$out" \
  'any(r["lane"]=="dotnet" and r["measure"]=="cyclomatic" and r["status"]=="deferred" and "probe:dotnet-metrics-linux" in r["reason"] for r in d["run"])'
assert_doc "python cognitive is unavailable with the validated-date reason" "$out" \
  'any(r["lane"]=="python" and r["measure"]=="cognitive" and r["status"]=="unavailable" and "2026-09-04" in r["reason"] for r in d["run"])'
assert_doc "typescript cyclomatic lists both rungs with their probe reasons and hints" "$out" \
  'any(r["lane"]=="typescript" and r["measure"]=="cyclomatic" and r["status"]=="unavailable" and r["reason"].startswith("lizard: ") and "; eslint-complexity: " in r["reason"] and r["reason"].count("(")>=2 for r in d["run"])'

# 6. Explicit missing path is a usage error.
PATH="$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines "$SOURCES/missing.py" >/dev/null 2>&1
assert_eq "missing explicit path exits 2" 2 "$?"
PATH="$EMPTY_PATH" bash "$SCRIPT" --measures file_lines >/dev/null 2>&1
assert_eq "missing skill name exits 2" 2 "$?"

# 7. Empty scope: status empty with the not-applicable row.
empty_dir="$(mktemp -d)"
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --all "$empty_dir")"
assert_doc "empty scope yields one not-applicable row" "$out" \
  'd["status"]=="empty" and d["scope"]["files"]==0 and d["run"]==[{"lane":"*","measure":"*","collector":None,"status":"not-applicable","reason":"no measurable files in scope"}]'
rmdir "$empty_dir"

# 8. A collector that probes but fails in collect: exit 3, row unavailable.
broken="$(mktemp -d)"
cat >"$broken/scc" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then printf 'scc version 9.9.9\n'; exit 0; fi
printf 'boom\n' >&2
printf 'not json\n'
exit 1
EOF
chmod +x "$broken/scc"
out="$(PATH="$broken:$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines "$SOURCES/cm_sample.py")"
rc=$?
assert_eq "collect failure exits 3" 3 "$rc"
assert_doc "collect failure row is unavailable with the stderr relayed" "$out" \
  'd["run"][0]["status"]=="unavailable" and d["run"][0]["collector"]=="scc 9.9.9" and "collect failed" in d["run"][0]["reason"] and "boom" in d["run"][0]["reason"]'
rm -rf "$broken"

# 9. Change scope resolves in a throwaway repository.
repo="$(mktemp -d)"
(
  cd "$repo" || exit 1
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  printf 'x = 1\n' >base.py
  git add base.py && git commit -q -m base
  git checkout -q -b feature
  printf 'y = 2\n' >changed.py
  printf 'echo hi\n' >untracked.sh
  git add changed.py && git commit -q -m change
)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines)"
rc=$?
assert_eq "change scope exits 0" 0 "$rc"
assert_doc "change scope is the committed diff plus untracked files, base recorded" "$out" \
  'd["scope"]["mode"]=="change" and d["scope"]["base"] and sorted(r["file"] for r in d["measures"])==["changed.py","untracked.sh"]'
rm -rf "$repo"

# 10. The config cascade: a team file sets the reference, an exclusion, and a
#     lane opt-out; an ecosystem file redefines the bash lane by globs. The
#     resolver reads them from the repo root and a home directory with no
#     user-global layer (CODE_METRICS_HOME).
repo="$(mktemp -d)"
home="$(mktemp -d)"
mkdir -p "$repo/.claude/ecosystems" "$repo/gen"
cat >"$repo/.claude/code-metrics.yaml" <<'EOF'
size:
  file_lines: 5
scope:
  exclude: ["gen/**"]
lanes:
  dotnet:
    enabled: false
EOF
printf 'globs: ["*.bats"]\n' >"$repo/.claude/ecosystems/bash.yaml"
printf 'a = 1\nb = 2\nc = 3\nd = 4\ne = 5\nf = 6\n' >"$repo/a.py"
printf 'g = 1\n' >"$repo/gen/b.py"
printf 'run() { :; }\n' >"$repo/x.bats"
printf 'echo plain\n' >"$repo/plain.sh"
printf 'class C {}\n' >"$repo/C.cs"
(cd "$repo" && git init -q -b main && git config user.email t@example.com && git config user.name t && git add -A && git commit -q -m fixture)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$home" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --all)"
rc=$?
assert_eq "cascade run exits 0" 0 "$rc"
assert_doc "team reference 5 with layer team; a.py is over it" "$out" \
  'next(t for t in d["thresholds"] if t["measure"]=="file_lines")["reference"]==5 and next(t for t in d["thresholds"] if t["measure"]=="file_lines")["layer"]=="team" and next(r for r in d["measures"] if r["file"]=="a.py")["over_reference"]==["file_lines"]'
assert_doc "scope.exclude drops gen/b.py and counts it" "$out" \
  'd["scope"]["excluded"]==1 and not any(r["file"]=="gen/b.py" for r in d["measures"])'
assert_doc "ecosystem globs redefine the bash lane" "$out" \
  'any(r["file"]=="x.bats" and r["lane"]=="bash" for r in d["measures"]) and not any(r["file"]=="plain.sh" for r in d["measures"])'
assert_doc "lanes.dotnet.enabled false opts the lane out" "$out" \
  'not any(r["lane"]=="dotnet" for r in d["run"]) and not any(r["file"]=="C.cs" for r in d["measures"])'
rm -rf "$repo" "$home"

# 11. --config with a pre-resolved document: the collector override narrows the
#     typescript cyclomatic ladder to lizard alone.
resolved="$(mktemp)"
"$PY" "$SCRIPT_DIR/resolve-config.py" "$SCRIPT_DIR/fixtures/config/user.yaml" "$SCRIPT_DIR/fixtures/config/team.yaml" --ladder "$SCRIPT_DIR/collector-ladder.tsv" >"$resolved"
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" audit-complexity --measures cyclomatic --config "$resolved" "$SOURCES/cm-sample.ts")"
assert_doc "ladder override lists lizard only for typescript cyclomatic" "$out" \
  'd["run"][0]["lane"]=="typescript" and d["run"][0]["reason"].startswith("lizard: ") and "eslint-complexity" not in d["run"][0]["reason"]'
assert_doc "pre-resolved thresholds carry their layer" "$out" \
  'next(t for t in d["thresholds"] if t["measure"]=="cyclomatic")["reference"]==15 and next(t for t in d["thresholds"] if t["measure"]=="cyclomatic")["layer"]=="team"'
rm -f "$resolved"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
