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
# symlinks to each executable on PATH except the tools the ladder names (and
# the binaries those adapters look up), so the coreutils, git, and the
# interpreter stay reachable while `scc` does not.
# shellcheck source=tool-free-path.sh
source "$SCRIPT_DIR/tool-free-path.sh"
cm_fill_tool_free_path "$EMPTY_PATH"
leftover="$(cm_resolvable_ladder_collectors "$EMPTY_PATH" | sort -u | tr '\n' ' ')"
leftover="${leftover% }"
if [[ -z "$leftover" ]]; then
  pass "no ladder collector is resolvable on the tool-free PATH"
else
  fail "no ladder collector is resolvable on the tool-free PATH" "none" "$leftover"
fi
unset CODE_METRICS_DISABLE_BUNDLED

# 1. scc absent: the bundled counter is used and the run row names it.
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --all "$SOURCES")"
rc=$?
assert_eq "exit 0 with the bundled counter" 0 "$rc"
assert_doc "schema, skill, and status complete" "$out" \
  'd["schema"]=="code-metrics/v1" and d["skill"]=="audit-size" and d["status"]=="complete"'
assert_doc "every lane row is ok on line-counter" "$out" \
  'all(r["status"]=="ok" and r["collector"].startswith("line-counter") for r in d["run"]) and len(d["run"])==6'
assert_doc "rows carry comment-agnostic label and non-blank counts" "$out" \
  'all("comment-agnostic" in r["labels"] and r["values"]["lines_non_blank"]>0 for r in d["measures"]) and d["summary"]["files"]==8'
assert_doc "markdown fixture is measured in the other lane" "$out" \
  'any(r["file"].endswith("cm-notes.md") and r["lane"]=="other" for r in d["measures"]) and d["scope"]["unclassified"]==0'
# The five language-lane fixtures by name (cm-sample.ts, cm_sample.py, cm-sample.sh,
# cm-sample.go, CmSample.cs), the markdown fixture (cm-notes.md) in the other lane, plus the
# two byte-identical bash copies of the duplication cluster fixture
# (cluster/{alpha,beta}/shared/shared-utils.sh): the assertion is also what maps them to this suite.
assert_doc "every fixture is measured exactly once" "$out" \
  'sorted(r["file"].rsplit("/",1)[1] for r in d["measures"])==["CmSample.cs","cm-notes.md","cm-sample.go","cm-sample.sh","cm-sample.ts","cm_sample.py","shared-utils.sh","shared-utils.sh"]'
assert_doc "threshold carries the plugin-default provenance" "$out" \
  'd["thresholds"][0]["measure"]=="file_lines" and d["thresholds"][0]["reference"]==1000 and "not normative" in d["thresholds"][0]["provenance"]'
assert_doc "a collector that said nothing leaves its ok row's reason null" "$out" \
  'all(r["reason"] is None for r in d["run"] if r["status"]=="ok")'

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
  'd["status"]=="empty" and d["run"] and all(r["status"]!="ok" and r["reason"] for r in d["run"]) and len(d["unavailable"])==6 and d["measures"]==[]'
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
# The other lane carries a line count and nothing else, so every other measure
# is not-applicable there, which never withholds a complete status.
assert_doc "the other lane is not-applicable for every complexity measure" "$out" \
  'sorted((r["measure"], r["status"]) for r in d["run"] if r["lane"]=="other")==[("cognitive","not-applicable"),("cyclomatic","not-applicable")] and all(r["reason"] for r in d["run"] if r["lane"]=="other")'
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

# 8b. A collector that succeeds while saying something on stderr: the ok row
# carries what it said as its reason (mypy's error count reaches the run
# table this way); a silent success leaves the reason null.
noisy="$(mktemp -d)"
cat >"$noisy/mypy" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf 'mypy 1.19.1 (compiled: yes)\n'; exit 0; fi
dir=""
prev=""
for arg in "\$@"; do
  [[ "\$prev" == "--any-exprs-report" ]] && dir="\$arg"
  prev="\$arg"
done
[[ -n "\$dir" ]] && mkdir -p "\$dir"
cp "$SCRIPT_DIR/fixtures/tool-output/mypy-any-exprs.txt" "\$dir/any-exprs.txt"
printf '%s\n' 'cm_sample.py:5: error: Incompatible return value type  [return-value]'
exit 1
EOF
chmod +x "$noisy/mypy"
out="$(PATH="$noisy:$EMPTY_PATH" bash "$SCRIPT" audit-type-debt --measures type_coverage "$SOURCES/cm_sample.py")"
rc=$?
assert_eq "a noisy success exits 0" 0 "$rc"
assert_doc "the ok row's reason is what the adapter said on stderr" "$out" \
  'any(r["lane"]=="python" and r["status"]=="ok" and r["reason"]=="mypy reported 1 error (0 missing stubs)" for r in d["run"])'
rm -rf "$noisy"

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
# 9b. Change scope from a subdirectory: git names diffed files from the
#     repository root, so the dispatcher rebases them onto the cwd instead of
#     dropping every file that is not under it.
(
  cd "$repo" || exit 1
  mkdir -p sub
  printf 'z = 3\n' >sub/inner.py
  git add sub/inner.py && git commit -q -m inner
)
out="$(cd "$repo/sub" && PATH="$EMPTY_PATH" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines)"
rc=$?
assert_eq "change scope from a subdirectory exits 0" 0 "$rc"
assert_doc "change scope from a subdirectory keeps the whole change, paths relative to the cwd" "$out" \
  'sorted(r["file"] for r in d["measures"])==["../changed.py","../untracked.sh","inner.py"]'
# `--all` means the whole repository, from a subdirectory too: an unanchored
# listing stops at the cwd, so the run would measure that subtree while its
# scope block still called itself `all`.
out="$(cd "$repo/sub" && PATH="$EMPTY_PATH" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --all)"
rc=$?
assert_eq "--all from a subdirectory exits 0" 0 "$rc"
assert_doc "--all from a subdirectory measures the whole repository, paths relative to the cwd" "$out" \
  'sorted(r["file"] for r in d["measures"])==["../base.py","../changed.py","../untracked.sh","inner.py"]'
# 9c. A change with nothing in it: the run row's reason is where the reader
#     learns how to widen the scope, since the skill body is not in front of
#     them when the report is.
(cd "$repo" && rm -f untracked.sh && git checkout -q main)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines)"
rc=$?
assert_eq "an empty change exits 0" 0 "$rc"
assert_doc "an empty change names the base and says how to widen the scope" "$out" \
  'd["status"]=="empty" and d["scope"]["mode"]=="change" and d["scope"]["files"]==0 and len(d["run"])==1 and d["run"][0]["status"]=="not-applicable" and d["scope"]["base"] in d["run"][0]["reason"] and "--all" in d["run"][0]["reason"] and "paths" in d["run"][0]["reason"]'
# 9d. A file in the other lane that cannot be read: the scope filter drops it
#     so one locked file does not turn the lane unavailable, names it on
#     stderr so it does not vanish unsaid, and the rest of the change is
#     measured. Root reads everything, so the case is skipped there.
(cd "$repo" && git checkout -q feature && printf '# notes\n' >locked.md && chmod 000 locked.md)
if [[ -r "$repo/locked.md" ]]; then
  pass "an unreadable other-lane file (skipped: this user can read a mode-000 file)"
  pass "the unreadable file is named on stderr (skipped)"
  pass "the unreadable file leaves the rest of the change measured (skipped)"
else
  err_file="$(mktemp)"
  out="$(cd "$repo" && PATH="$EMPTY_PATH" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines 2>"$err_file")"
  rc=$?
  assert_eq "an unreadable other-lane file still exits 0" 0 "$rc"
  case "$(cat "$err_file")" in
  *"cannot read: locked.md"*) pass "the unreadable file is named on stderr" ;;
  *) fail "the unreadable file is named on stderr" "mentions locked.md" "$(head -c 300 "$err_file")" ;;
  esac
  assert_doc "the unreadable file leaves the rest of the change measured" "$out" \
    'd["status"]=="complete" and not any("locked.md" in r["file"] for r in d["measures"]) and any(r["lane"]=="python" and r["status"]=="ok" for r in d["run"])'
  rm -f "$err_file"
fi
(cd "$repo" && chmod 644 locked.md && rm -f locked.md)
# An explicitly named directory holding only ignored files lists nothing. Asking
# git whether it listed anything cannot tell that apart from a path outside the
# repository, and reading it as "outside" walks the very tree the ignore rules
# exclude.
(
  cd "$repo" || exit 1
  mkdir -p vendored
  printf 'vendored/\n' >.gitignore
  printf 'a = 1\n' >vendored/ignored.py
  git add .gitignore && git commit -q -m ignore
)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines vendored)"
rc=$?
assert_eq "an ignored directory exits 0" 0 "$rc"
assert_doc "an ignored directory measures nothing rather than being walked" "$out" \
  'd["scope"]["files"]==0 and d["measures"]==[]'
# A scope.exclude glob the matcher cannot use is a configuration error: dropping
# it would measure the files the consumer asked to leave out, and still exit 0.
(cd "$repo" && mkdir -p .claude && printf 'scope:\n  exclude: ["[z-a]"]\n' >.claude/code-metrics.yaml)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --all 2>/dev/null)"
rc=$?
assert_eq "an unusable scope.exclude glob exits 2 rather than measuring anyway" "2:" "$rc:$out"
rm -rf "$repo"

# 13. A file whose name carries non-ASCII bytes. git quotes such a path by
#     default, and a quoted literal matches no file on disk, so the file left
#     the scope with nothing said and the document still called itself complete.
repo="$(mktemp -d)"
(
  cd "$repo" || exit 1
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  printf 'a = 1\n' >'café.py'
  printf 'b = 2\n' >'plain.py'
  git add -A && git commit -q -m accents
)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --all --print-scope)"
assert_eq "a non-ASCII filename stays in scope" "python	café.py
python	plain.py" "$(printf '%s\n' "$out" | sort)"

# 14. A repository whose listing fails. An empty listing and a failed listing
#     are the same on stdout, so an unread exit status turns a broken
#     repository into a document that says it measured nothing, at exit 0.
printf 'GARBAGE-NOT-AN-INDEX' >"$repo/.git/index"
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --all 2>/dev/null)"
rc=$?
assert_eq "a failed repository listing exits 2 rather than reporting an empty run" "2:" "$rc:$out"
rm -rf "$repo"

# 15. A repository reached through a symlink. `cd`/`pwd` are logical and keep
#     the symlink, while git reports the physical path, so a logical comparison
#     never matched and the ignored-tree guard fell through to a plain walk.
repo="$(mktemp -d)"
(
  cd "$repo" || exit 1
  mkdir -p real
  cd real || exit 1
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  mkdir -p sub vendored
  printf 'a = 1\n' >sub/keep.py
  printf 'junk = 1\n' >vendored/ignored.py
  printf 'vendored/\n' >.gitignore
  git add .gitignore sub/keep.py && git commit -q -m base
  ln -s "$repo/real" "$repo/link"
)
out="$(cd "$repo/link/sub" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --print-scope --all ../vendored 2>/dev/null)"
assert_eq "an ignored tree stays out of scope through a symlinked work tree" "" "$out"
rm -rf "$repo"

# 16. A team writes `scope.exclude` against the repository root, because a
#     configuration file cannot know which directory an audit will run from.
#     Matched against the cwd-relative scope, the same exclusion covers the
#     files from the root and covers nothing one directory down.
repo="$(mktemp -d)"
(
  cd "$repo" || exit 1
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  mkdir -p .claude src/vendor src/keep
  printf 'a = 1\n' >src/vendor/skip.py
  printf 'b = 2\n' >src/keep/keep.py
  printf 'scope:\n  exclude: ["src/vendor/**"]\n' >.claude/code-metrics.yaml
  git add -A && git commit -q -m base
)
from_root="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --all --print-scope)"
assert_eq "the exclusion applies from the repository root" "other	.claude/code-metrics.yaml
python	src/keep/keep.py" "$from_root"
from_sub="$(cd "$repo/src" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --all --print-scope)"
assert_eq "the same exclusion applies from a subdirectory" "other	../.claude/code-metrics.yaml
python	keep/keep.py" "$from_sub"
# 17. The same exclusion, reached through an explicitly scoped sibling. Mapping
#     a path back to the root by prefixing alone leaves the `..` in place, so
#     `src/keep/../vendor/skip.py` is what the matcher sees and a `src/vendor/**`
#     pattern does not match the text. The segments have to collapse first.
from_sibling="$(cd "$repo/src/keep" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --print-scope -- . ../vendor)"
assert_eq "the exclusion applies to an explicitly scoped sibling path" "python	keep.py" "$from_sibling"
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
# The ecosystem file's basename IS the lane name, and every lane name this
# repository knows is also the basename of a committed convention example. A
# literal `<lane>.yaml` here would make scripts/affected-tests.sh map that
# unrelated example to this suite, so the fixture name is composed instead
# (the same reason affected-tests.sh's own header declines to spell a
# colliding basename).
eco_lane=bash
printf 'globs: ["*.bats"]\n' >"$repo/.claude/ecosystems/$eco_lane.yaml"
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

# 12. Configured scope: `scope.base` and `scope.default` apply when the command
#     line names no --base, --all, or path; an explicit --base still wins; an
#     explicitly empty collector list runs nothing for that lane and measure;
#     and --print-scope prints the resolved lane/path rows and stops.
repo="$(mktemp -d)"
home="$(mktemp -d)"
(
  cd "$repo" || exit 1
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  printf 'x = 1\n' >base.py
  git add base.py && git commit -q -m base
  git checkout -q -b feature
  printf 'y = 2\n' >changed.py
  git add changed.py && git commit -q -m change
  git tag mark
  printf 'z = 3\n' >third.py
  git add third.py && git commit -q -m third
  mkdir -p .claude
  printf 'scope:\n  base: mark\n' >.claude/code-metrics.yaml
)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$home" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines)"
# The untracked configuration file is part of the change too, in the other lane.
assert_doc "a configured scope.base narrows the change to the commits after it" "$out" \
  'sorted(r["file"] for r in d["measures"])==[".claude/code-metrics.yaml","third.py"]'
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$home" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --base main)"
assert_doc "an explicit --base wins over the configured one" "$out" \
  'sorted(r["file"] for r in d["measures"])==[".claude/code-metrics.yaml","changed.py","third.py"]'
(cd "$repo" && printf 'scope:\n  default: all\nlanes:\n  python:\n    collectors:\n      file_lines: []\n' >.claude/code-metrics.yaml)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$home" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines)"
assert_doc "a configured scope.default of all widens the run to the tree" "$out" \
  'd["scope"]["mode"]=="all" and d["scope"]["files"]==4'
assert_doc "an empty collector list runs nothing for that lane and says so" "$out" \
  'any(r["lane"]=="python" and r["measure"]=="file_lines" and r["status"]=="unavailable" and "no collector" in r["reason"] for r in d["run"]) and not any(r["lane"]=="python" for r in d["measures"])'
# An explicit --base asks for a diff, so it beats a configured `default: all`
# the same way --all and a path do; widening to the tree would discard the ref.
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$home" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --base mark)"
assert_doc "an explicit --base beats a configured scope.default of all" "$out" \
  'd["scope"]["mode"]=="change" and d["scope"]["base"] and d["scope"]["files"] < 4'
# A named base is measured from the merge-base, not the ref's tip. `main` edits
# `base.py` after `feature` diverged; a two-dot diff against the tip would call
# that edit part of this change, which is a file the branch never touched.
(cd "$repo" && git checkout -q main && printf 'x = 1\nx = 2\n' >base.py &&
  git add base.py && git commit -q -m "main moves on" && git checkout -q feature)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$home" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --base main --print-scope)"
assert_eq "a base branch's own later edit is not part of the change" "other	.claude/code-metrics.yaml
python	changed.py
python	third.py" "$(printf '%s\n' "$out" | sort)"
listing="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$home" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --print-scope)"
assert_eq "--print-scope prints each measurable file with its lane" "other	.claude/code-metrics.yaml
python	base.py
python	changed.py
python	third.py" "$(printf '%s\n' "$listing" | sort)"
assert_eq "--print-scope lists a file no language lane claims under other" "other	.claude/code-metrics.yaml" \
  "$(printf '%s\n' "$listing" | grep 'code-metrics.yaml')"
# A value the resolver refuses must stop the run. Reading a derived format from
# a process substitution would report only the read's own success, so the audit
# would exit 0 having quietly dropped the configured scope and exclusions.
(cd "$repo" && printf 'scope:\n  exclude: ["gen/**\\n--disable-lane python"]\n' >.claude/code-metrics.yaml)
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$home" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --all 2>/dev/null)"
rc=$?
assert_eq "a refused config value stops the run instead of dropping the config" "2:" "$rc:$out"
err="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$home" CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR/.." bash "$SCRIPT" audit-size --measures file_lines --all 2>&1 >/dev/null)"
case "$err" in
*"scope.exclude"*) pass "the refusal names the offending key" ;;
*) fail "the refusal names the offending key" "mentions scope.exclude" "$err" ;;
esac
rm -rf "$repo" "$home"

# 20. The default scope exclusions drop dependency and build-output directories
# and the scope names each pattern's count.
repo="$(mktemp -d)"
(
  cd "$repo" || exit 1
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  mkdir -p src dist vendor
  printf 'def a():\n    return 1\n' >src/a.py
  printf 'def g():\n    return 1\n' >dist/gen.py
  printf 'echo lib\n' >vendor/lib.sh
  git add -A
  git commit -qm init
) >/dev/null 2>&1
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo/no-home" bash "$SCRIPT" audit-size --measures file_lines --all)"
assert_doc "the default exclusions drop dist and vendor and name each pattern's count" "$out" \
  'd["scope"]["excluded"]==2 and sorted((e["pattern"],e["files"]) for e in d["scope"]["exclusions"])==[("**/dist/**",1),("**/vendor/**",1)] and [r["file"] for r in d["measures"]]==["src/a.py"]'
# 21. An empty change scope says why it is empty and what widens it.
(cd "$repo" && git checkout -qb feature) >/dev/null 2>&1
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo/no-home" bash "$SCRIPT" audit-size --measures file_lines)"
assert_doc "a branch at its merge-base with a clean tree gets the merge-base reason and the --all hint" "$out" \
  'd["status"]=="empty" and "merge-base" in d["run"][0]["reason"] and "--all" in d["run"][0]["reason"] and d["scope"]["files"]==0'
# A markdown-only change is measured through the catch-all `other` lane; with
# that lane opted out through the team file the same change belongs to no lane
# and the reason says so.
(cd "$repo" && printf 'notes\n' >notes.md && git add -A && git commit -qm docs) >/dev/null 2>&1
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo/no-home" bash "$SCRIPT" audit-size --measures file_lines)"
assert_doc "a change holding only a markdown file is measured in the other lane" "$out" \
  'd["status"]=="complete" and [(r["file"], r["lane"]) for r in d["measures"]]==[("notes.md","other")] and d["scope"]["unclassified"]==0'
(cd "$repo" && mkdir -p .claude && printf 'lanes:\n  other:\n    enabled: false\n' >.claude/code-metrics.yaml && git add -A && git commit -qm config) >/dev/null 2>&1
out="$(cd "$repo" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$repo/no-home" bash "$SCRIPT" audit-size --measures file_lines)"
assert_doc "with lanes.other.enabled false, a change holding only files in no lane says so" "$out" \
  'd["status"]=="empty" and "belong to no lane" in d["run"][0]["reason"] and d["scope"]["files"]==2 and d["scope"]["unclassified"]==2'
rm -rf "$repo"

# 22. A sanctioned-replication registry collapses the copies of a shared file
# into one row per function or file, and a registry that does not exist is a
# usage error.
team="$(mktemp -d)"
printf 'scope:\n  registries: [plugins/code-metrics/scripts/fixtures/registry/cluster.txt]\n' >"$team/team.yaml"
"$PY" "$SCRIPT_DIR/resolve-config.py" "$team/team.yaml" --ladder "$SCRIPT_DIR/collector-ladder.tsv" >"$team/resolved.json"
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --config "$team/resolved.json" --all "$SOURCES")"
rc=$?
assert_eq "a registry run exits 0" 0 "$rc"
assert_doc "the two shared-utils copies collapse to one labelled row standing for both files" "$out" \
  'len([r for r in d["measures"] if r["file"].endswith("shared-utils.sh")])==1 and next(r for r in d["measures"] if r["file"].endswith("shared-utils.sh"))["replicas"]["count"]==2 and "replicated" in next(r for r in d["measures"] if r["file"].endswith("shared-utils.sh"))["labels"] and d["summary"]["files"]==8'
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --config "$team/resolved.json" --no-collapse --all "$SOURCES")"
assert_doc "--no-collapse keeps one row per copy, for a caller that collapses after its own join" "$out" \
  'len([r for r in d["measures"] if r["file"].endswith("shared-utils.sh")])==2 and not any("replicas" in r for r in d["measures"]) and d["summary"]["files"]==8'
printf 'scope:\n  registries: [nope/missing-registry.txt]\n' >"$team/missing.yaml"
"$PY" "$SCRIPT_DIR/resolve-config.py" "$team/missing.yaml" --ladder "$SCRIPT_DIR/collector-ladder.tsv" >"$team/missing.json"
PATH="$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --config "$team/missing.json" --all "$SOURCES" >/dev/null 2>&1
assert_eq "a registry that does not exist is a usage error" 2 "$?"
rm -rf "$team"

# 23. Collectors run in parallel; the run table and the rows come out in the
# same order whatever the concurrency, and progress is on stderr only for a
# run that asks for it or is large.
out1="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --all "$SOURCES")"
out2="$(PATH="$STUBS:$EMPTY_PATH" CODE_METRICS_JOBS=1 bash "$SCRIPT" audit-size --measures file_lines --all "$SOURCES")"
if printf '%s\n\x1e%s' "$out1" "$out2" | "$PY" -c '
import json, sys
a, b = (json.loads(part) for part in sys.stdin.read().split("\x1e"))
same = a["run"] == b["run"] and a["measures"] == b["measures"] and a["summary"] == b["summary"]
lanes = [(r["lane"], r["measure"]) for r in a["run"]]
raise SystemExit(0 if same and lanes == sorted(lanes) else 1)
'; then
  pass "the run table and rows are identical and lane-ordered at any concurrency"
else
  fail "the run table and rows are identical and lane-ordered at any concurrency" "identical documents" "$(printf '%s' "$out1" | head -c 300)"
fi
err="$(PATH="$EMPTY_PATH" CODE_METRICS_PROGRESS=1 bash "$SCRIPT" audit-size --measures file_lines --all "$SOURCES" 2>&1 >/dev/null)"
case "$err" in
*"file(s) in scope"*"finished in"*) pass "CODE_METRICS_PROGRESS=1 reports the scope and each collector on stderr" ;;
*) fail "CODE_METRICS_PROGRESS=1 reports the scope and each collector on stderr" "scope and finished lines" "$err" ;;
esac
err="$(PATH="$EMPTY_PATH" bash "$SCRIPT" audit-size --measures file_lines --all "$SOURCES" 2>&1 >/dev/null)"
assert_eq "a small run prints no progress by default" "" "$err"

# 24. An adapter whose collect exits 4 (the tool resolved but cannot run
# here: ESLint with no configuration for the files) gets an unavailable row
# carrying the tool's reason, and the run is not a failure.
noconf="$(mktemp -d)"
cat >"$noconf/eslint" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf 'v10.1.0\n'; exit 0; fi
cat "$SCRIPT_DIR/fixtures/tool-output/eslint-no-config.txt" >&2
exit 2
EOF
chmod +x "$noconf/eslint"
ladder="$(mktemp)"
printf 'typescript\tcyclomatic\teslint-complexity\n' >"$ladder"
out="$(PATH="$noconf:$EMPTY_PATH" bash "$SCRIPT" audit-complexity --measures cyclomatic --ladder "$ladder" "$SOURCES/cm-sample.ts")"
rc=$?
assert_eq "a collector that cannot run here exits 0" 0 "$rc"
assert_doc "the row is unavailable with the tool's own reason and no 'collect failed'" "$out" \
  'd["status"]=="empty" and d["run"][0]["status"]=="unavailable" and d["run"][0]["collector"]=="eslint-complexity 10.1.0" and "no configuration" in d["run"][0]["reason"] and "eslint.config" in d["run"][0]["reason"] and "collect failed" not in d["run"][0]["reason"] and d["measures"]==[]'
rm -rf "$noconf" "$ladder"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
