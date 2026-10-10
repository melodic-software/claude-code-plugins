#!/usr/bin/env bash
# Audit the test selector (scripts/affected-tests.sh) against what the suites
# actually do. Two questions, one subcommand each:
#
#   scripts/selection-audit.sh trace [--shard I/N] [--jobs N] [--budget S] [--out DIR] [SUITE...]
#       Run each suite under strace, collect the tracked files it opened, then
#       ask the selector, one synthetic single-file diff per file, whether a
#       change to that file selects the suite. Every (suite, file) pair the
#       selector would not take is a GAP: a change to that file could break the
#       suite on main while the pull request's affected run never started it.
#       Default corpus: every tracked *.test.sh, and every test_*.py outside
#       /evals/fixtures/, which holds data no lane runs, but this audit's own
#       suite; --shard keeps suites I, I+N, I+2N, ... of the sorted list. Each
#       suite gets 600 s under strace, and the slowest start first.
#
#   scripts/selection-audit.sh replay --suite S --good SHA --bad SHA
#       For each first-parent commit in GOOD..BAD, run that commit's own
#       selector on its own diff and say whether it selected S. A suite no
#       commit selected is a SELECTION MISS; one some commit selected is a
#       regression its pull-request run should have caught, or a flake. A
#       commit whose selector could not run is an error row, and a range with
#       errors and no selecting commit is INCONCLUSIVE, not a miss.
#
# An unmapped file counts as selecting a suite only when pr-require-checks.yml's UNMAPPED
# fallback runs that suite: in a tree whose pr-require-checks.yml plans its test lanes with
# scripts/plan-test-lanes.sh, the corpus of the file's language, which the
# selector adds itself under --unmapped-corpus; in an older tree, the corpus
# fallback_corpus reads from pr-require-checks.yml.
#
#   scripts/selection-audit.sh red-replay --run-id ID [--repo OWNER/REPO]
#       For a failed pr-require-checks run on main: read the failing suites from its job logs
#       (FAIL: lines), find each suite's last green run (the newest earlier
#       successful run whose job logs name the suite), and replay that
#       range. Needs gh with actions: read.
#
#   scripts/selection-audit.sh reads <strace-log> <root>
#       Print the files under <root> a trace opened, repo-relative. Internal;
#       public so the suite can test the parser on a fixture.
#
# A read is a successful open(2)/openat(2): strace -y prints the opened file's
# resolved path on the return value, so a relative path or a dirfd-relative
# open resolves without replaying the process's working directory. Reads
# through git objects (`git show HEAD:path`) and existence probes (stat, `-f`)
# are not opens, so the trace cannot see them.
#
# Three root files are read by almost every suite through its tools, not its
# logic: node reads package.json for the module type, the version manager reads
# .node-version, and git reads .gitignore. A read of one is no gap; a change to
# one is the toolchain's to gate, and as a scope it would select every suite.
#
# Writes report.md, gaps.tsv and suites.tsv (trace) or report.md (replay,
# red-replay) under --out, and appends report.md to $GITHUB_STEP_SUMMARY when
# set. Never opens or edits an issue.
#
# Exit: 0 no gap and no miss; 1 gaps or misses reported; 2 usage or a tool
# missing.
set -uo pipefail

SELECTOR="${SELECTION_AUDIT_SELECTOR:-scripts/affected-tests.sh}"
SUMMARY_ROWS=200

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

die() {
  echo "error: $*" >&2
  exit 2
}

publish() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    cat "$1" >>"$GITHUB_STEP_SUMMARY"
  fi
  cat "$1"
}

# reads <log> <root>: the opened paths under <root>, repo-relative, sorted.
reads() {
  local root
  root="$(cd "$2" && pwd -P)/"
  awk -v root="$root" '
    / = [0-9]+<[^>]*>$/ {
      p = $0
      sub(/.* = [0-9]+</, "", p)
      sub(/>$/, "", p)
      if (index(p, root) == 1) {
        p = substr(p, length(root) + 1)
        if (p !~ /^\.git\//) print p
      }
    }' "$1" | sort -u
}

# gate_workflow: this tree's gate workflow; a tree from before the rename
# names it ci.yml.
gate_workflow() { if [[ -f .github/workflows/ci.yml ]]; then echo .github/workflows/ci.yml; else echo .github/workflows/pr-require-checks.yml; fi; }

# planned: this tree's gate workflow takes its test lanes from scripts/plan-test-lanes.sh,
# whose selection already holds an unmapped file's language corpus.
planned() { grep -q 'scripts/plan-test-lanes\.sh' "$(gate_workflow)" 2>/dev/null; }

# unmapped_flag: the selector flag that answers for an unmapped file the way
# this tree's gate workflow does.
unmapped_flag() { if planned; then echo --unmapped-corpus; else echo --allow-unmapped; fi; }

# fallback_corpus: the suites an older gate workflow's UNMAPPED fallback runs, one per line,
# read from the commands in that branch of the workflow rather than assumed. Of its
# runners only run-plugin-tests.sh runs a suite of this corpus (it lists what
# it discovers); run-outside-node-suites.sh runs Node packages' npm test.
# Prints nothing when the branch runs no run-plugin-tests.sh; exit 1 when the
# branch or the list cannot be read.
fallback_corpus() {
  local block
  planned && return 0
  block="$(awk '/grep -q .\^UNMAPPED:/ { f = 1 } f && /^[[:space:]]*else$/ { exit } f' \
    "$(gate_workflow)" 2>/dev/null)"
  [[ -n "$block" ]] || return 1
  grep -q 'scripts/run-plugin-tests\.sh' <<<"$block" || return 0
  bash scripts/run-plugin-tests.sh --list 2>/dev/null
}

# --- trace -----------------------------------------------------------------

# trace_one <out> <index:suite>: run one suite under strace and write its read
# set. Called by xargs from cmd_trace; records "not traced" past the budget.
trace_one() {
  local out="$1" keyed="$2" key suite rc=0 start runner
  key="${keyed%%:*}"
  suite="${keyed#*:}"
  if ((AUDIT_DEADLINE > 0 && $(date +%s) >= AUDIT_DEADLINE)); then
    printf '%s\tnot-traced\t0\t0\n' "$suite" >"$out/suites/$key"
    return 0
  fi
  case "$suite" in
  *.py) runner=(python3 -m pytest -q -p no:cacheprovider "$suite") ;;
  *) runner=(bash "$suite") ;;
  esac
  start="$(date +%s)"
  # -k: a daemon a suite leaves behind stays traced, and strace outlives a TERM waiting for it.
  timeout -k 10 600 strace -f -y -z -qq --seccomp-bpf -e trace=open,openat -e signal=none \
    -o "$out/strace.$key" "${runner[@]}" >"$out/logs/$key.log" 2>&1 || rc=$?
  reads "$out/strace.$key" "$ROOT" | grep -vxF -e "$suite" -e package.json -e .node-version -e .gitignore |
    awk 'NR == FNR { t[$0] = 1; next } t[$0]' "$out/tracked" - >"$out/reads/$key"
  rm -f "$out/strace.$key"
  printf '%s\t%s\t%s\t%s\n' "$suite" "$rc" "$(($(date +%s) - start))" "$(wc -l <"$out/reads/$key")" >"$out/suites/$key"
}

# select_one <out> <index:file>: the selector's answer for a one-file diff.
select_one() {
  local out="$1" keyed="$2" key file rc=0
  key="${keyed%%:*}"
  file="${keyed#*:}"
  if ((AUDIT_DEADLINE > 0 && $(date +%s) >= AUDIT_DEADLINE + AUDIT_SELECT_GRACE)); then
    echo "not checked: audit budget spent" >"$out/sel/$key.err"
    : >"$out/sel/$key.out"
    return 0
  fi
  timeout 120 bash "$SELECTOR" --explain "$AUDIT_UNMAPPED_FLAG" -- "$file" \
    >"$out/sel/$key.out" 2>"$out/sel/$key.err" || rc=$?
  [[ "$rc" -eq 4 && "$AUDIT_UNMAPPED_FLAG" == --unmapped-corpus ]] && rc=0
  [[ "$rc" -eq 0 ]] || echo "not checked: selector exit $rc" >>"$out/sel/$key.err"
}

cmd_trace() {
  local shard="0/1" jobs=3 budget=0 out="" i n
  local -a suites=()
  while (($#)); do
    case "$1" in
    --shard) shard="${2:-}" && shift 2 ;;
    --jobs) jobs="${2:-}" && shift 2 ;;
    --budget) budget="${2:-}" && shift 2 ;;
    --out) out="${2:-}" && shift 2 ;;
    -*) die "unknown trace option: $1" ;;
    *) suites+=("$1") && shift ;;
    esac
  done
  [[ "$shard" =~ ^[0-9]+/[1-9][0-9]*$ ]] || die "--shard wants I/N; got: $shard"
  i=$((10#${shard%/*}))
  n=$((10#${shard#*/}))
  ((i < n)) || die "--shard index must be below the total; got: $shard"
  [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "--jobs wants a positive integer; got: $jobs"
  [[ "$budget" =~ ^[0-9]+$ ]] || die "--budget wants seconds; got: $budget"
  command -v strace >/dev/null || die "strace is required (Linux only)"
  out="${out:-$(mktemp -d "${TMPDIR:-/tmp}/selection-audit.XXXXXX")}"
  mkdir -p "$out/suites" "$out/reads" "$out/logs" "$out/sel" || exit 2
  out="$(cd "$out" && pwd -P)"

  git ls-files >"$out/tracked"
  fallback_corpus >"$out/fallback" || die "cannot derive the suites pr-require-checks.yml's UNMAPPED fallback runs"
  if ((${#suites[@]} == 0)); then
    # A Python eval fixture is data no lane runs (scripts/plan-test-lanes.sh);
    # a *.test.sh there would still run in the bash lane, so it stays traced.
    # This suite runs strace itself, which fails under the audit's own strace.
    mapfile -t suites < <(grep -E '(\.test\.sh|(^|/)test_[^/]*\.py)$' "$out/tracked" | grep -vE '/evals/fixtures/(.*/)?test_[^/]*\.py$' |
      grep -vxF scripts/selection-audit.test.sh | awk -v i="$i" -v n="$n" '(NR - 1) % n == i')
  fi
  ((${#suites[@]})) || die "no suites to trace"
  # Slowest first by scripts/suite-seconds.txt, so a long suite starts while the
  # budget still has room for it to finish and for its reads to be checked.
  if [[ -f scripts/suite-seconds.txt ]]; then
    mapfile -t suites < <(printf '%s\n' "${suites[@]}" |
      awk 'NR == FNR { if (!/^#/) s[$1] = $2; next } { print ($0 in s ? s[$0] : 0) "\t" $0 }' scripts/suite-seconds.txt - |
      sort -s -t $'\t' -k1,1nr | cut -f2-)
  fi

  AUDIT_UNMAPPED_FLAG="$(unmapped_flag)"
  export AUDIT_DEADLINE=0 AUDIT_SELECT_GRACE=$((budget * 2 / 5)) AUDIT_UNMAPPED_FLAG
  ((budget > 0)) && AUDIT_DEADLINE=$(($(date +%s) + budget * 3 / 5))
  export -f trace_one select_one reads
  export ROOT SELECTOR

  local k=0 s
  for s in "${suites[@]}"; do
    printf '%06d:%s\n' "$k" "$s"
    k=$((k + 1))
  done | xargs -d '\n' -P "$jobs" -I{} bash -c "trace_one \"\$1\" \"\$2\"" _ "$out" {}

  # One selector call per distinct file, shared by every suite that read it.
  local f
  cat "$out"/reads/* 2>/dev/null | sort -u >"$out/files"
  awk '{ printf "%06d:%s\n", NR - 1, $0 }' "$out/files" |
    xargs -d '\n' -P "$jobs" -I{} bash -c "select_one \"\$1\" \"\$2\"" _ "$out" {}

  # edges.tsv: suite, file it read. selected.tsv: file, suite a change to it
  # selects. verdicts.tsv: file, the selector's answer in words.
  local key
  cat "$out"/suites/* | sort >"$out/suites.tsv"
  for f in "$out"/suites/*; do
    key="${f##*/}"
    awk -v s="$(cut -f1 "$f")" '{ print s "\t" $0 }' "$out/reads/$key" 2>/dev/null
  done >"$out/edges.tsv"
  : >"$out/selected.tsv"
  : >"$out/verdicts.tsv"
  k=0
  while IFS= read -r f; do
    key="$(printf '%06d' "$k")"
    k=$((k + 1))
    awk -v f="$f" '{ print f "\t" $0 }' "$out/sel/$key.out" >>"$out/selected.tsv"
    if grep -q '^not checked' "$out/sel/$key.err"; then
      echo "not checked: $(sed -n 's/^not checked: //p' "$out/sel/$key.err" | head -n1)"
    elif grep -q '^UNMAPPED:' "$out/sel/$key.err"; then
      echo "unmapped: CI runs its fallback corpus"
    elif [[ -s "$out/sel/$key.out" ]]; then
      echo "selects $(wc -l <"$out/sel/$key.out") other suite(s)"
    else
      grep -m1 -E "^(no-suite|deleted)" "$out/sel/$key.err" || echo 'selects no suite'
    fi | awk -v f="$f" '{ print f "\t" $0 }' >>"$out/verdicts.tsv"
  done <"$out/files"
  # gaps.tsv: suite, file, verdict, for every read the selector would not
  # take. An unmapped file is no gap for a suite the fallback runs, and a gap
  # for one it does not; an unchecked file is counted apart.
  awk -F'\t' '
    FILENAME ~ /fallback$/ { fb[$0] = 1; next }
    FILENAME ~ /selected.tsv$/ { sel[$1 SUBSEP $2] = 1; next }
    FILENAME ~ /verdicts.tsv$/ { v[$1] = $2; next }
    v[$2] ~ /^not checked/ || (($2 SUBSEP $1) in sel) { next }
    v[$2] ~ /^unmapped/ { if ($1 in fb) next; print $1 "\t" $2 "\tunmapped: the fallback corpus does not run this suite"; next }
    { print $1 "\t" $2 "\t" v[$2] }
  ' "$out/fallback" "$out/selected.tsv" "$out/verdicts.tsv" "$out/edges.tsv" | sort >"$out/gaps.tsv"

  local traced not_traced failed gaps gap_suites unchecked
  traced=$(awk -F'\t' '$2 != "not-traced"' "$out/suites.tsv" | wc -l)
  not_traced=$(awk -F'\t' '$2 == "not-traced"' "$out/suites.tsv" | wc -l)
  failed=$(awk -F'\t' '$2 != "not-traced" && $2 != 0' "$out/suites.tsv" | wc -l)
  gaps=$(wc -l <"$out/gaps.tsv")
  gap_suites=$(cut -f1 "$out/gaps.tsv" | sort -u | wc -l)
  unchecked=$(grep -c $'\tnot checked' "$out/verdicts.tsv" || true)
  {
    echo "## Test-selection trace audit"
    echo
    echo "Commit \`$(git rev-parse --short=9 HEAD)\`, shard $shard, ${#suites[@]} suite(s): $traced traced" \
      "($failed exited non-zero; their reads still count), $not_traced not traced (budget)."
    echo "$(wc -l <"$out/files") distinct tracked file(s) read; $unchecked not checked against the selector (budget spent or selector error)."
    echo
    if ((gaps == 0)); then
      echo "No gap: every file a traced suite read selects that suite."
    else
      echo "**$gaps gap(s) in $gap_suites suite(s)**: the suite read the file, and the selector" \
        "(\`$SELECTOR --explain\` on a one-file diff) does not select the suite for a change to it."
      echo
      echo "| suite | file it read | selector on that file |"
      echo "| --- | --- | --- |"
      awk -F'\t' -v max="$SUMMARY_ROWS" 'NR <= max { printf "| `%s` | `%s` | %s |\n", $1, $2, $3 }' "$out/gaps.tsv"
      ((gaps > SUMMARY_ROWS)) && echo && echo "First $SUMMARY_ROWS of $gaps rows; gaps.tsv in the artifact has all of them."
    fi
  } >"$out/report.md"
  publish "$out/report.md"
  echo "Artifacts: $out (report.md, gaps.tsv, suites.tsv, reads/, logs/)" >&2
  ((gaps == 0))
}

# --- replay ----------------------------------------------------------------

# replay_rows <suite> <good> <bad> <worktree>: one TSV row per commit.
replay_rows() {
  local suite="$1" good="$2" bad="$3" wt="$4" c verdict rc fallback flag
  local -a files
  for c in $(git rev-list --first-parent --reverse "$good..$bad"); do
    mapfile -t files < <(git diff --name-only "$c^" "$c")
    git -C "$wt" checkout -q --detach "$c" || {
      printf '%s\terror: checkout failed\n' "$c"
      continue
    }
    rc=0
    flag="$(cd "$wt" && unmapped_flag)"
    (cd "$wt" && bash scripts/affected-tests.sh "$flag" -- "${files[@]}") \
      >"$wt.out" 2>"$wt.err" || rc=$?
    [[ "$rc" -eq 4 && "$flag" == --unmapped-corpus ]] && rc=0
    if grep -qxF -- "$suite" "$wt.out"; then
      verdict="selected"
    elif grep -q '^UNMAPPED:' "$wt.err" && [[ "$flag" == --unmapped-corpus ]]; then
      verdict="not selected (unmapped file: its language corpus does not run it)"
    elif grep -q '^UNMAPPED:' "$wt.err"; then
      if ! fallback="$(cd "$wt" && fallback_corpus)"; then
        verdict="error: cannot derive the unmapped fallback's suites"
      elif grep -qxF -- "$suite" <<<"$fallback"; then
        verdict="selected (unmapped file: the full-corpus fallback runs it)"
      else
        verdict="not selected (unmapped file: the full-corpus fallback does not run it)"
      fi
    elif ((rc != 0)); then
      verdict="error: selector exit $rc"
    else
      verdict="not selected"
    fi
    printf '%s\t%s\t%s\n' "$c" "$verdict" "$(git log -1 --format=%s "$c")"
  done
}

# replay_report <suite> <good> <bad> <report>: append one suite's section;
# return 1 on a selection miss. A commit the selector could not be run on is
# an error row, neither selected nor not: with no selecting commit, any error
# makes the range inconclusive rather than a miss.
replay_report() {
  local suite="$1" good="$2" bad="$3" report="$4" wt rows selected total errors
  wt="$(mktemp -d "${TMPDIR:-/tmp}/selection-replay.XXXXXX")/wt"
  git worktree add -q --detach "$wt" "$bad" || die "cannot add a worktree at $bad"
  rows="$(replay_rows "$suite" "$good" "$bad" "$wt")"
  git worktree remove --force "$wt"
  rm -rf "$(dirname "$wt")"
  total=$(printf '%s' "$rows" | grep -c . || true)
  selected=$(printf '%s\n' "$rows" | grep -c $'\tselected' || true)
  errors=$(printf '%s\n' "$rows" | grep -c $'\terror:' || true)
  {
    echo "### \`$suite\`"
    echo
    echo "Last green \`${good:0:9}\`, failed at \`${bad:0:9}\`: $total commit(s) in between."
    echo
    if ((total == 0)); then
      echo "No commit in the range; nothing to replay."
    elif ((selected == 0 && errors > 0)); then
      echo "**Inconclusive**: $errors of $total commit(s) could not be replayed and no other commit selected this suite; not counted as a selection miss."
    elif ((selected == 0)); then
      echo "**Selection miss**: no commit's pull-request selection included this suite."
    else
      echo "Selected by $selected of $total commit(s): a regression the pull-request run should have caught, or a flake."
    fi
    echo
    if ((total > 0)); then
      echo "| commit | selector verdict | subject |"
      echo "| --- | --- | --- |"
      printf '%s\n' "$rows" | awk -F'\t' '{ printf "| `%s` | %s | %s |\n", substr($1, 1, 9), $2, $3 }'
      echo
    fi
  } >>"$report"
  ((total == 0 || selected > 0 || errors > 0))
}

cmd_replay() {
  local suite="" good="" bad="" out=""
  while (($#)); do
    case "$1" in
    --suite) suite="${2:-}" && shift 2 ;;
    --good) good="${2:-}" && shift 2 ;;
    --bad) bad="${2:-}" && shift 2 ;;
    --out) out="${2:-}" && shift 2 ;;
    *) die "unknown replay option: $1" ;;
    esac
  done
  [[ -n "$suite" && -n "$good" && -n "$bad" ]] || die "replay needs --suite, --good and --bad"
  out="${out:-$(mktemp -d "${TMPDIR:-/tmp}/selection-audit.XXXXXX")}"
  mkdir -p "$out" || exit 2
  echo "## Red replay" >"$out/report.md"
  echo >>"$out/report.md"
  local rc=0
  replay_report "$suite" "$(git rev-parse "$good")" "$(git rev-parse "$bad")" "$out/report.md" || rc=1
  publish "$out/report.md"
  return "$rc"
}

# job_logs <repo> <run-id> <dir> [failure]: save each job's log of a run as
# <dir>/<run-id>.<job-id>.log; with "failure", only the failed jobs'.
job_logs() {
  local repo="$1" run="$2" dir="$3" want="${4:-}" id conclusion
  gh api --paginate "repos/$repo/actions/runs/$run/jobs?per_page=100" \
    --jq '.jobs[] | [.id, .conclusion] | @tsv' |
    while IFS=$'\t' read -r id conclusion; do
      [[ -z "$want" || "$conclusion" == "$want" ]] || continue
      [[ -s "$dir/$run.$id.log" ]] ||
        gh run view "$run" -R "$repo" --job "$id" --log >"$dir/$run.$id.log" 2>/dev/null || true
    done
}

cmd_red_replay() {
  local run="" repo="${GITHUB_REPOSITORY:-}" out="" max_runs=30
  while (($#)); do
    case "$1" in
    --run-id) run="${2:-}" && shift 2 ;;
    --repo) repo="${2:-}" && shift 2 ;;
    --out) out="${2:-}" && shift 2 ;;
    *) die "unknown red-replay option: $1" ;;
    esac
  done
  [[ "$run" =~ ^[0-9]+$ && -n "$repo" ]] || die "red-replay needs --run-id and --repo (or GITHUB_REPOSITORY)"
  command -v gh >/dev/null || die "gh is required"
  out="${out:-$(mktemp -d "${TMPDIR:-/tmp}/selection-audit.XXXXXX")}"
  mkdir -p "$out/logs" || exit 2

  local bad workflow created
  IFS=$'\t' read -r bad workflow created < <(gh api "repos/$repo/actions/runs/$run" \
    --jq '[.head_sha, .workflow_id, .created_at] | @tsv') || die "cannot read run $run"
  job_logs "$repo" "$run" "$out/logs" failure
  # Failing suites: run-plugin-tests.sh and affected-tests.sh print
  # `FAIL: <suite>`; pytest prints `FAILED <file>::<test>`. A case name that
  # merely looks like a path is dropped unless the failed commit has that file.
  local -a failing=()
  local s
  while IFS= read -r s; do
    git cat-file -e "$bad:$s" 2>/dev/null && failing+=("$s")
  done < <(cat "$out"/logs/"$run".*.log 2>/dev/null | tr -d '\r' |
    sed -nE 's/\x1b\[[0-9;]*m//g; s/^.*[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z //;
      s/^FAIL: ([^ ]+).*/\1/p; s/^FAILED ([^: ]+)::.*/\1/p' |
    grep -E '(\.test\.sh|(^|/)test_[^/]*\.py)$' | sort -u)

  local report="$out/report.md" rc=0 suite green sha good
  {
    echo "## Red replay of pr-require-checks run [$run](https://github.com/$repo/actions/runs/$run)"
    echo
    echo "Failed at \`${bad:0:9}\`; ${#failing[@]} failing suite(s) found in the failed jobs' logs."
    echo
  } >"$report"
  if ((${#failing[@]} == 0)); then
    echo "No \`FAIL: <suite>\` line in a failed job: the red came from a gate, not a suite, so there is no selection to replay." >>"$report"
    publish "$report"
    return 0
  fi
  gh api "repos/$repo/actions/workflows/$workflow/runs?branch=main&status=success&created=%3C$created&per_page=$max_runs" \
    --jq '.workflow_runs[] | select(.event == "push" or .event == "schedule") | [.id, .head_sha] | @tsv' \
    >"$out/green-runs.tsv" || die "cannot list earlier runs"
  for suite in "${failing[@]}"; do
    good=""
    while IFS=$'\t' read -r green sha; do
      job_logs "$repo" "$green" "$out/logs"
      if grep -qF -- "$suite" "$out"/logs/"$green".*.log 2>/dev/null; then
        good="$sha"
        break
      fi
    done <"$out/green-runs.tsv"
    if [[ -z "$good" ]]; then
      printf '### %s\n\nNo green run among the last %s successful runs names this suite; not replayed.\n\n' \
        "\`$suite\`" "$max_runs" >>"$report"
      continue
    fi
    replay_report "$suite" "$good" "$bad" "$report" || rc=1
  done
  publish "$report"
  return "$rc"
}

case "${1:-}" in
trace | replay | red-replay)
  if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ! cd "$ROOT"; then
    die "not inside a git work tree"
  fi
  cmd="cmd_${1/-/_}"
  shift && "$cmd" "$@"
  ;;
reads)
  [[ $# -eq 3 ]] || die "reads needs <strace-log> <root>"
  reads "$2" "$3"
  ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
