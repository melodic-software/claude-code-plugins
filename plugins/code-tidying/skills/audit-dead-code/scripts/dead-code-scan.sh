#!/usr/bin/env bash
# Dead-code CANDIDATES for /code-tidying:audit-dead-code. Read-only.
#
# Output: Lane / Note run-health lines, then File + Finding tier/shape/line/
# excerpt records separated by `---`, then Summary file / lanes / candidates /
# total lines. The script never writes a file into the repository and never
# edits source.
#
# Exit:
#   0  the scan ran (candidates or not, lanes healthy or not) — a read-only
#      audit must never fail its caller, so -e is omitted and no detector's
#      exit code is ever propagated.
#   2  usage error: unknown argument, missing option value, non-numeric --max,
#      unknown --lane, or an unusable temp directory.
#
# Exit codes are NEVER read as run health. Measured: knip exits 1 for BOTH
# findings and hard errors; vulture exits 3 for findings and 1 for an input
# error; gopls check always exits 0. Health comes from stderr, from stdout
# error lines, and from a direct node_modules probe — never from $?.
#
# Pipeline posture: `set -uo pipefail` is on and NO detector output is piped
# into an early-closing reader (`head`, `grep -q`). Measured: vulture raises
# BrokenPipeError and returns 1 when its stdout closes early, so a truncating
# pipe would fabricate a detector failure. Every detector writes to a temp file
# that is then read back in full.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dead-code-shapes.sh
source "$SCRIPT_DIR/lib/dead-code-shapes.sh"

# Where the caller invoked us. Explicit targets are relative to THIS, not to the
# repo root we cd into below, so they are anchored here before the cd.
INVOCATION_CWD="$PWD"
TAB=$'\t'

dc_anchor_path() {
  case "$1" in
  /* | ?:[\\/]*) printf '%s' "$1" ;;
  *) printf '%s/%s' "$INVOCATION_CWD" "$1" ;;
  esac
}

MAX=0
LANE_SEL='all'
TARGETS=()

usage() {
  cat <<'EOF'
dead-code-scan.sh — emit dead-code CANDIDATES for /code-tidying:audit-dead-code.

Usage:
  dead-code-scan.sh [target]...
  dead-code-scan.sh --max <n> [target]...
  dead-code-scan.sh --lane <knip|vulture|gopls|grep|all> [target]...
  dead-code-scan.sh --help

Candidate scope is the given targets (default: the whole repository). The
reference SEARCH is always repository-wide — a reference from anywhere still
saves a symbol, whatever the candidate scope.

--max <n> caps how many candidates are emitted, ordered by git recency,
OLDEST-UNTOUCHED FIRST (0 = no cap). The detectors carry no usable confidence
key to order by: vulture pins every symbol-level finding at 60 and knip has no
confidence field at all.

Exit: 0 on every scan path (findings or not, lanes healthy or not);
      2 on usage errors. A detector's own exit code is never propagated.
EOF
}

require_opt_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
    echo "dead-code-scan.sh: $opt requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --max)
    require_opt_value "$@"
    MAX="$2"
    shift 2
    ;;
  --lane)
    require_opt_value "$@"
    LANE_SEL="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    while [[ $# -gt 0 ]]; do
      TARGETS+=("$1")
      shift
    done
    ;;
  -*)
    echo "dead-code-scan.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  *)
    TARGETS+=("$1")
    shift
    ;;
  esac
done

if [[ ! "$MAX" =~ ^[0-9]+$ ]]; then
  echo "dead-code-scan.sh: --max requires a non-negative integer" >&2
  exit 2
fi
# Strip leading zeros so values like 08 are decimal, not octal, under arithmetic.
MAX=$((10#$MAX))

case "$LANE_SEL" in
all | knip | vulture | gopls | grep) ;;
*)
  echo "dead-code-scan.sh: --lane must be one of knip, vulture, gopls, grep, all" >&2
  exit 2
  ;;
esac

# Anchor caller-supplied paths BEFORE the cd, or they resolve against the repo
# root instead and silently miss.
if [[ ${#TARGETS[@]} -gt 0 ]]; then
  ANCHORED=()
  for target in "${TARGETS[@]}"; do
    ANCHORED+=("$(dc_anchor_path "$target")")
  done
  TARGETS=("${ANCHORED[@]}")
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
GIT_OK=1
if [[ -n "$REPO_ROOT" ]]; then
  cd "$REPO_ROOT" 2>/dev/null || true
else
  GIT_OK=0
  REPO_ROOT="$INVOCATION_CWD"
fi

WORK="$(mktemp -d)" || {
  echo "dead-code-scan.sh: could not create a temp directory" >&2
  exit 2
}
trap 'rm -rf "$WORK"' EXIT

CAND="$WORK/candidates.tsv"
LANES="$WORK/lanes.txt"
NOTES="$WORK/notes.txt"
: >"$CAND"
: >"$LANES"
: >"$NOTES"

NOW="$(date -u +%s 2>/dev/null || echo 0)"

lane_line() {
  printf 'Lane: %s | root=%s | state=%s | files=%s | detail=%s\n' \
    "$1" "$2" "$3" "$4" "$5" >>"$LANES"
}

note() {
  printf 'Note: %s\n' "$1" >>"$NOTES"
}

# The lanes disagree about what a path is: knip reports project-relative,
# vulture relativizes to cwd (which is the repo root here), and gopls reports
# ABSOLUTE paths with no flag to change that. Every Location this script emits
# is repo-relative, so the report reads as one document.
repo_relative() {
  local p="$1"
  case "$p" in
  "$REPO_ROOT"/*) printf '%s' "${p#"$REPO_ROOT"/}" ;;
  *) printf '%s' "$p" ;;
  esac
}

add_candidate() {
  printf '%s\t%s\t%s\t%s\n' "$(repo_relative "$1")" "${2:-0}" "$3" "$(dc_trim_excerpt "$4")" >>"$CAND"
}

# ---------------------------------------------------------------------------
# Candidate scope
# ---------------------------------------------------------------------------

list_repo_files() {
  local pattern="$1" f
  if [[ "$GIT_OK" == '1' ]]; then
    git ls-files -- "$pattern" 2>/dev/null
    return 0
  fi
  while IFS= read -r f; do
    printf '%s\n' "${f#./}"
  done < <(find . -type f -name "${pattern#\*}" 2>/dev/null)
}

list_scope_files() {
  local t f
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    if [[ "$GIT_OK" == '1' ]]; then
      git ls-files 2>/dev/null
    else
      while IFS= read -r f; do printf '%s\n' "${f#./}"; done < <(find . -type f 2>/dev/null)
    fi
    return 0
  fi
  for t in "${TARGETS[@]}"; do
    if [[ "$GIT_OK" == '1' ]]; then
      git ls-files -- "$t" 2>/dev/null
    else
      while IFS= read -r f; do printf '%s\n' "${f#./}"; done < <(find "$t" -type f 2>/dev/null)
    fi
  done
}

SCOPE=()
TS_FILES=()
PY_FILES=()
GO_FILES=()
SYM_FILES=()

while IFS= read -r scope_line; do
  scope_line="${scope_line//$'\r'/}"
  [[ -n "$scope_line" ]] || continue
  dc_is_excluded_path "$scope_line" && continue
  [[ -f "$scope_line" ]] || continue
  SCOPE+=("$scope_line")
  case "$(dc_lang_of_path "$scope_line")" in
  ts) TS_FILES+=("$scope_line") ;;
  py) PY_FILES+=("$scope_line") ;;
  go) GO_FILES+=("$scope_line") ;;
  shell | pwsh) SYM_FILES+=("$scope_line") ;;
  *) ;;
  esac
done < <(list_scope_files | LC_ALL=C sort -u)

# ---------------------------------------------------------------------------
# Project-root OWNERSHIP
#
# Roots are discovered one per manifest (package.json, go.mod), and a root may
# only ever speak for the files it OWNS: paths under that root and under no
# NESTED root. Running a detector AT a root does not by itself restrict what
# that run reports — knip walks the whole subtree, nested workspaces included —
# so the output is filtered here, and the input list is built from owned files.
#
# Measured on this marketplace before the filter existed: the repo-root knip run
# emitted 213 of its 288 candidates for files belonging to roots the SAME scan
# had already declared `degraded` and promised would "emit no records". Those
# candidates were manufactured by exactly the unrestored-node_modules runs the
# degraded state exists to withhold. SKILL.md: "Each root carries its own state
# — one degraded workspace does not condemn the others."
#
# The repo root stays a root even when its manifest declares no sources of its
# own (this repository's own package.json is a CI-toolchain-only manifest):
# deciding "declares no sources" means interpreting project config, which this
# scan refuses to do. Ownership makes keeping it safe — a source-less root owns
# nothing and reports `scanned-zero-files`, which is the honest state anyway.

# The roots in ARR_NAME that lie strictly INSIDE root, written to DST_NAME.
nested_roots() {
  local root="$1" arr_name="$2" dst_name="$3"
  local -n _dc_own_all="$arr_name"
  local -n _dc_own_nest="$dst_name"
  local prefix r
  _dc_own_nest=()
  if [[ "$root" == "." ]]; then prefix=""; else prefix="$root/"; fi
  for r in ${_dc_own_all[@]+"${_dc_own_all[@]}"}; do
    [[ "$r" == "$root" || "$r" == "." ]] && continue
    if [[ -z "$prefix" || "$r" == "$prefix"* ]]; then _dc_own_nest+=("$r"); fi
  done
}

# 0 when root OWNS the repo-relative path, 1 otherwise. A path inside a nested
# root belongs to that nested root's own run and to no other, and a path the
# scan already declared "never scanning input" (node_modules, dist, build,
# vendor, `**/evals/fixtures/**`) belongs to no root at all — a detector invoked
# at a root walks those directories even though this scan excluded them from
# candidate scope, and a finding there is not a candidate.
owns_path() {
  local root="$1" nest_name="$2" p="$3"
  local -n _dc_own_n="$nest_name"
  local prefix r
  if [[ "$root" == "." ]]; then prefix=""; else prefix="$root/"; fi
  [[ -z "$prefix" || "$p" == "$prefix"* ]] || return 1
  dc_is_excluded_path "$p" && return 1
  for r in ${_dc_own_n[@]+"${_dc_own_n[@]}"}; do
    [[ "$p" == "$r/"* ]] && return 1
  done
  return 0
}

# 0 when repo-relative path is in the caller's TS/JS candidate set.
in_ts_files() {
  local p="$1" f
  for f in ${TS_FILES[@]+"${TS_FILES[@]}"}; do
    [[ "$f" == "$p" ]] && return 0
  done
  return 1
}

count_owned() {
  local root="$1" nest_name="$2" arr_name="$3"
  local -n _dc_own_src="$arr_name"
  local f n=0
  for f in ${_dc_own_src[@]+"${_dc_own_src[@]}"}; do
    if owns_path "$root" "$nest_name" "$f"; then n=$((n + 1)); fi
  done
  printf '%s' "$n"
}

# The owned files, root-relative — the form a detector invoked at that root
# reads. A nested root's files are never handed to the outer root's run.
files_owned() {
  local root="$1" nest_name="$2" arr_name="$3" dst_name="$4"
  local -n _dc_own_src2="$arr_name"
  local -n _dc_own_dst="$dst_name"
  local prefix f
  _dc_own_dst=()
  if [[ "$root" == "." ]]; then prefix=""; else prefix="$root/"; fi
  for f in ${_dc_own_src2[@]+"${_dc_own_src2[@]}"}; do
    owns_path "$root" "$nest_name" "$f" || continue
    if [[ -z "$prefix" ]]; then
      _dc_own_dst+=("$f")
    else
      _dc_own_dst+=("${f#"$prefix"}")
    fi
  done
}

rebase_path() {
  local root="$1" p="${2:-}"
  if [[ -z "$p" || "$p" == '-' ]]; then
    printf '%s' "$root"
  elif [[ "$root" == "." || "$p" == /* ]]; then
    printf '%s' "$p"
  else
    printf '%s/%s' "$root" "$p"
  fi
}

project_roots() {
  local marker="$1" f root
  local -a roots=()
  while IFS= read -r f; do
    f="${f//$'\r'/}"
    [[ -n "$f" ]] || continue
    # The glob query can over-match (my-package.json); the basename decides.
    [[ "$(basename -- "$f")" == "$marker" ]] || continue
    dc_is_excluded_path "$f" && continue
    root="$(dirname -- "$f")"
    roots+=("$root")
  done < <(list_repo_files "*$marker")
  [[ ${#roots[@]} -eq 0 ]] && return 0
  printf '%s\n' "${roots[@]}" | LC_ALL=C sort -u
}

# ---------------------------------------------------------------------------
# Lane: knip (TS/JS) — measured 60% precision / 100% recall on trap fixtures
# ---------------------------------------------------------------------------

lane_knip() {
  local root_rel root_abs bin cfg nfiles rows foreign k_path
  # root_nested is read through a nameref by nested_roots/owns_path/count_owned,
  # which shellcheck cannot see (SC2034).
  # shellcheck disable=SC2034
  local -a roots=() root_nested=()
  mapfile -t roots < <(project_roots package.json)
  if [[ ${#roots[@]} -eq 0 ]]; then
    lane_line knip '-' skipped 0 'no package.json project root in this repository'
    return 0
  fi
  for root_rel in "${roots[@]}"; do
    # Ownership is computed BEFORE anything else, because it decides both what
    # this root is scanning FOR and what it is allowed to report.
    nested_roots "$root_rel" roots root_nested
    nfiles="$(count_owned "$root_rel" root_nested TS_FILES)"
    if [[ "$nfiles" -eq 0 ]]; then
      lane_line knip "$root_rel" scanned-zero-files 0 \
        'no TS/JS file owned by this root in candidate scope (files under a NESTED project root belong to that root) — a scan of nothing, not a clean bill'
      continue
    fi
    if [[ "$root_rel" == "." ]]; then root_abs="$REPO_ROOT"; else root_abs="$REPO_ROOT/$root_rel"; fi
    if ! dc_find_nonempty_node_modules "$root_abs" "$REPO_ROOT" >/dev/null; then
      lane_line knip "$root_rel" degraded "$nfiles" \
        'node_modules absent or empty by direct ancestor-walk probe — an unrestored knip run MANUFACTURES false unused-file findings, so this root emits no records'
      continue
    fi
    if ! bin="$(dc_locate_binary knip "$root_abs" "$REPO_ROOT")"; then
      lane_line knip "$root_rel" skipped "$nfiles" \
        'knip not resolvable in a repo-local node_modules/.bin nor on PATH — no package runner is invoked, so nothing was fetched'
      continue
    fi
    if ! dc_binary_invocable "$bin" --version; then
      lane_line knip "$root_rel" skipped "$nfiles" \
        "located at $bin but invocation failed — presence is proven by invocation, never by command -v"
      continue
    fi
    if cfg="$(dc_knip_config_module "$root_abs")"; then
      note "knip evaluated $(rebase_path "$root_rel" "$cfg") through jiti — a DISCLOSED exception to the no-project-code rule, narrower than a build and stated rather than hidden"
    fi
    (cd "$root_abs" && "$bin" --reporter json --no-progress) >"$WORK/knip.out" 2>"$WORK/knip.err" || true
    if dc_knip_stderr_is_degraded "$WORK/knip.err"; then
      lane_line knip "$root_rel" degraded "$nfiles" \
        'knip wrote an ERROR: line to stderr, which --reporter json discards; such a run manufactures FALSE POSITIVES, so this root emits no records'
      continue
    fi
    if [[ ! -s "$WORK/knip.out" ]]; then
      lane_line knip "$root_rel" ran "$nfiles" 'no unused file, export, type, or enum member reported'
      continue
    fi
    if dc_parse_knip_json <"$WORK/knip.out" >"$WORK/knip.rows"; then
      rows=0
      foreign=0
      while IFS="$TAB" read -r k_file k_line k_shape k_name; do
        [[ -n "$k_shape" ]] || continue
        k_path="$(repo_relative "$(rebase_path "$root_rel" "$k_file")")"
        # knip walks the whole subtree from where it was invoked, nested
        # workspaces included. A finding about a file this root does not own is
        # DROPPED here: it is the nested root's to report, and only when that
        # root's own run is healthy.
        if ! owns_path "$root_rel" root_nested "$k_path"; then
          foreign=$((foreign + 1))
          continue
        fi
        # knip has no per-file input mode that preserves cross-file usage, so
        # the invocation still walks the whole root. Candidate scope is the
        # caller's targets (TS_FILES); a finding for an owned file outside
        # that set is not a candidate.
        if ! in_ts_files "$k_path"; then
          foreign=$((foreign + 1))
          continue
        fi
        add_candidate "$k_path" "$k_line" "$k_shape" "$k_name"
        rows=$((rows + 1))
      done <"$WORK/knip.rows"
      if [[ "$foreign" -gt 0 ]]; then
        lane_line knip "$root_rel" ran "$nfiles" \
          "$rows candidate(s); $foreign finding(s) this root does not own dropped (a NESTED project root's file, or a path excluded from candidate scope) — each nested root reports its own, and only when its own run is healthy"
      else
        lane_line knip "$root_rel" ran "$nfiles" "$rows candidate(s)"
      fi
    else
      add_candidate "$root_rel" 0 detector-drift \
        'knip produced output no parser recognized — its JSON shape may have changed'
      lane_line knip "$root_rel" ran "$nfiles" 'output not recognized — recorded as T3 drift, never as clean'
    fi
  done
}

# ---------------------------------------------------------------------------
# Lane: vulture (Python) — measured 16.7% precision / 100% recall. High recall,
# low precision, and the confidence knob does not exist for these targets.
# ---------------------------------------------------------------------------

lane_vulture() {
  local bin rc=0 v_line row parsed=0 drift=0 unparsed=0
  # FP classes measured to matter, pre-applied. A consumer extends these through
  # the native whitelist, not by editing this script.
  local ignore_decorators='@app.route,@*.route,@pytest.fixture,@property,@*.setter,@*.command,@*.task'
  if [[ ${#PY_FILES[@]} -eq 0 ]]; then
    lane_line vulture '.' scanned-zero-files 0 \
      'no .py file in candidate scope — a scan of nothing, not a clean bill'
    return 0
  fi
  if ! bin="$(dc_locate_binary vulture "$REPO_ROOT" "$REPO_ROOT")"; then
    lane_line vulture '.' skipped "${#PY_FILES[@]}" \
      'vulture not resolvable in a repo-local .venv/bin nor on PATH — no package runner is invoked, so nothing was fetched'
    return 0
  fi
  if ! dc_binary_invocable "$bin" --version; then
    lane_line vulture '.' skipped "${#PY_FILES[@]}" \
      "located at $bin but invocation failed — presence is proven by invocation, never by command -v"
    return 0
  fi
  # Every file is passed in ONE invocation: vulture counts usages across the
  # whole set it is given, so chunking would fragment cross-file usage and
  # inflate false positives. The glob is filtered to *.py first because vulture
  # handed a non-Python file logs a parse error and skips that file.
  "$bin" --min-confidence 60 --ignore-names 'test_*,pytest_*' \
    --ignore-decorators "$ignore_decorators" -- "${PY_FILES[@]}" \
    >"$WORK/vulture.out" 2>"$WORK/vulture.err" || rc=$?
  # Health comes from the SHAPE of stderr, never from the exit code: measured,
  # vulture exits 1 for a lone unparsable input and 3 when findings coexist, so
  # the code cannot separate "one bad input file" from "the run is unsound".
  if dc_vulture_stderr_is_degraded "$WORK/vulture.err"; then
    lane_line vulture '.' degraded "${#PY_FILES[@]}" \
      "vulture wrote a non-input error to stderr (exit $rc) — its output is withheld"
    return 0
  fi
  # An input-parse-error line is an INPUT note, not a degraded run: every other
  # file was still analyzed, and treating it as degradation would let one stray
  # non-Python file suppress the whole lane.
  while IFS= read -r v_line; do
    [[ -n "$v_line" ]] || continue
    unparsed=$((unparsed + 1))
    note "vulture could not parse one input and skipped it (an input note, not a degraded run): $v_line"
  done < <(dc_vulture_unparsed_inputs "$WORK/vulture.err")
  while IFS= read -r v_line || [[ -n "$v_line" ]]; do
    v_line="${v_line//$'\r'/}"
    [[ -n "$v_line" ]] || continue
    if dc_parse_vulture_line "$v_line" row; then
      parsed=$((parsed + 1))
      IFS="$TAB" read -r p_file p_line p_shape p_excerpt <<<"$row"
      add_candidate "$p_file" "$p_line" "$p_shape" "$p_excerpt"
    else
      drift=$((drift + 1))
      add_candidate '-' 0 detector-drift "vulture line not in the finding grammar: $v_line"
    fi
  done <"$WORK/vulture.out"
  lane_line vulture '.' ran "${#PY_FILES[@]}" \
    "$parsed candidate(s), $drift unrecognized stdout line(s), $unparsed input file(s) skipped as unparsable"
}

# ---------------------------------------------------------------------------
# Lane: gopls (Go) — unexported symbols only, which is the lane's declared
# coverage, not a defect. `gopls check` runs go list plus its own front end and
# per official docs "does not run the actual compiler".
# ---------------------------------------------------------------------------

lane_gopls() {
  local root_rel root_abs bin nfiles g_line row parsed=0 drift=0 degraded=0
  local foreign=0 g_path
  # root_nested is read through a nameref (SC2034); mod_files is expanded below.
  # shellcheck disable=SC2034
  local -a roots=() mod_files=() root_nested=()
  mapfile -t roots < <(project_roots go.mod)
  if [[ ${#roots[@]} -eq 0 ]]; then
    lane_line gopls '-' skipped 0 'no go.mod module root in this repository'
    return 0
  fi
  for root_rel in "${roots[@]}"; do
    parsed=0
    drift=0
    degraded=0
    foreign=0
    nested_roots "$root_rel" roots root_nested
    nfiles="$(count_owned "$root_rel" root_nested GO_FILES)"
    if [[ "$nfiles" -eq 0 ]]; then
      lane_line gopls "$root_rel" scanned-zero-files 0 \
        'no .go file owned by this module in candidate scope (files under a NESTED go.mod belong to that module) — a scan of nothing, not a clean bill'
      continue
    fi
    if [[ "$root_rel" == "." ]]; then root_abs="$REPO_ROOT"; else root_abs="$REPO_ROOT/$root_rel"; fi
    if ! bin="$(dc_locate_binary gopls "$root_abs" "$REPO_ROOT")"; then
      lane_line gopls "$root_rel" skipped "$nfiles" 'gopls not resolvable on PATH'
      continue
    fi
    if ! dc_binary_invocable "$bin" version; then
      lane_line gopls "$root_rel" skipped "$nfiles" \
        "located at $bin but invocation failed — presence is proven by invocation, never by command -v"
      continue
    fi
    # Only the files this module OWNS are handed to gopls; a nested go.mod's
    # files belong to that module's own run.
    files_owned "$root_rel" root_nested GO_FILES mod_files
    (cd "$root_abs" && "$bin" check -severity=hint -- "${mod_files[@]}") \
      >"$WORK/gopls.out" 2>"$WORK/gopls.err" || true
    # Health is decided BEFORE a single record is made, the same order the knip
    # and vulture lanes use. Deciding it during the parse loop was a real defect:
    # add_candidate had already appended this module's rows by the time the gate
    # fired, so a lane line reading "emits no records" shipped alongside the
    # records it claimed to withhold.
    if [[ -s "$WORK/gopls.err" ]]; then
      degraded=1
    else
      while IFS= read -r g_line || [[ -n "$g_line" ]]; do
        g_line="${g_line//$'\r'/}"
        [[ -n "$g_line" ]] || continue
        if dc_gopls_stdout_is_degraded "$g_line"; then
          degraded=1
          break
        fi
      done <"$WORK/gopls.out"
    fi
    if [[ "$degraded" == '1' ]]; then
      lane_line gopls "$root_rel" degraded "$nfiles" \
        'module graph or workspace did not load (import error on stdout or a non-empty stderr, always with exit 0); hints are SUPPRESSED, so this module produces false NEGATIVES and emits no records'
      continue
    fi
    while IFS= read -r g_line || [[ -n "$g_line" ]]; do
      g_line="${g_line//$'\r'/}"
      [[ -n "$g_line" ]] || continue
      dc_parse_gopls_line "$g_line" row
      case "$?" in
      0)
        IFS="$TAB" read -r p_file p_line p_shape p_excerpt <<<"$row"
        g_path="$(repo_relative "$(rebase_path "$root_rel" "$p_file")")"
        # A diagnostic about a file this module does not own belongs to the
        # nested module that owns it, and only when that module's run is healthy.
        if ! owns_path "$root_rel" root_nested "$g_path"; then
          foreign=$((foreign + 1))
          continue
        fi
        parsed=$((parsed + 1))
        add_candidate "$g_path" "$p_line" "$p_shape" "$p_excerpt"
        ;;
      1) drift=$((drift + 1)) ;;
      *) ;;
      esac
    done <"$WORK/gopls.out"
    if [[ "$drift" -gt 0 ]]; then
      add_candidate "$root_rel" 0 detector-drift \
        "$drift gopls stdout line(s) were not diagnostics in the file:line:col form"
    fi
    if [[ "$foreign" -gt 0 ]]; then
      lane_line gopls "$root_rel" ran "$nfiles" \
        "$parsed unexported candidate(s), $drift unrecognized line(s); exported symbols are outside this lane; $foreign diagnostic(s) this module does not own dropped (a NESTED module's file, or a path excluded from candidate scope)"
    else
      lane_line gopls "$root_rel" ran "$nfiles" \
        "$parsed unexported candidate(s), $drift unrecognized line(s); exported symbols are outside this lane"
    fi
  done
}

# ---------------------------------------------------------------------------
# Lane: grep (shell and other symbol languages) — measured 4/4 true positives,
# 0 false positives over 546 .sh / 177,793 lines. High precision, acknowledged
# low recall. `grep -w -F` is the portable floor and -F is MANDATORY: without
# it `core.ts` matches `coreXts`.
# ---------------------------------------------------------------------------

lane_grep() {
  local f lang d_line d_name d_text cnt nm defs hits
  declare -A DEFS=()
  declare -A HITS=()
  if [[ ${#SYM_FILES[@]} -eq 0 ]]; then
    lane_line grep '.' scanned-zero-files 0 \
      'no shell or PowerShell file in candidate scope — a scan of nothing, not a clean bill'
    return 0
  fi
  printf 'dc_probe_symbol\n' >"$WORK/probe.txt"
  if ! grep -w -F -e 'dc_probe_symbol' -- "$WORK/probe.txt" >/dev/null 2>&1; then
    lane_line grep '.' skipped "${#SYM_FILES[@]}" \
      'grep -w -F did not run here — presence is proven by invocation, never by command -v'
    return 0
  fi
  : >"$WORK/defs.tsv"
  for f in "${SYM_FILES[@]}"; do
    lang="$(dc_lang_of_path "$f")"
    while IFS="$TAB" read -r d_line d_name d_text; do
      [[ -n "$d_name" ]] || continue
      printf '%s\t%s\t%s\t%s\n' "$f" "$d_line" "$d_name" "$d_text" >>"$WORK/defs.tsv"
      DEFS["$d_name"]=$((${DEFS["$d_name"]:-0} + 1))
    done < <(dc_symbol_defs "$f" "$lang")
  done
  if [[ ! -s "$WORK/defs.tsv" ]]; then
    lane_line grep '.' ran "${#SYM_FILES[@]}" 'no symbol definition matched the extractor set'
    return 0
  fi
  printf '%s\n' "${!DEFS[@]}" | LC_ALL=C sort -u >"$WORK/names.txt"
  # Reference search is REPOSITORY-WIDE and deliberately separate from candidate
  # scope: a reference from anywhere saves a symbol. -h drops filenames so the
  # counted token is the match itself; xargs splits the file list for us.
  : >"$WORK/hits.txt"
  if [[ "$GIT_OK" == '1' ]]; then
    git ls-files -z 2>/dev/null |
      xargs -0 grep -o -h -w -F -f "$WORK/names.txt" -- >>"$WORK/hits.txt" 2>/dev/null || true
  else
    find . -type f -print0 2>/dev/null |
      xargs -0 grep -o -h -w -F -f "$WORK/names.txt" -- >>"$WORK/hits.txt" 2>/dev/null || true
  fi
  while read -r cnt nm; do
    [[ -n "$nm" ]] || continue
    HITS["$nm"]="$cnt"
  done < <(LC_ALL=C sort "$WORK/hits.txt" | uniq -c)
  local emitted=0
  while IFS="$TAB" read -r f d_line d_name d_text; do
    [[ -n "$d_name" ]] || continue
    defs="${DEFS["$d_name"]:-1}"
    hits="${HITS["$d_name"]:-0}"
    # Only the definition sites themselves matched anywhere in the repository.
    if [[ "$hits" -le "$defs" ]]; then
      add_candidate "$f" "$d_line" 'unreferenced-symbol' "$d_text"
      emitted=$((emitted + 1))
    fi
  done <"$WORK/defs.tsv"
  lane_line grep '.' ran "${#SYM_FILES[@]}" \
    "$emitted candidate(s) from $(wc -l <"$WORK/names.txt" | tr -d ' ') distinct definition name(s)"
}

# ---------------------------------------------------------------------------
# Run the selected lanes
# ---------------------------------------------------------------------------

[[ "$LANE_SEL" == 'all' || "$LANE_SEL" == 'knip' ]] && lane_knip
[[ "$LANE_SEL" == 'all' || "$LANE_SEL" == 'vulture' ]] && lane_vulture
[[ "$LANE_SEL" == 'all' || "$LANE_SEL" == 'gopls' ]] && lane_gopls
[[ "$LANE_SEL" == 'all' || "$LANE_SEL" == 'grep' ]] && lane_grep

# ---------------------------------------------------------------------------
# Order, cap, and emit
# ---------------------------------------------------------------------------

declare -A FILE_TS=()

: >"$WORK/keyed.tsv"
while IFS="$TAB" read -r c_file c_line c_shape c_excerpt; do
  [[ -n "$c_shape" ]] || continue
  ts="${FILE_TS[$c_file]:-}"
  if [[ -z "$ts" ]]; then
    ts=""
    if [[ "$GIT_OK" == '1' && -f "$c_file" ]]; then
      ts="$(git log -1 --format=%ct -- "$c_file" 2>/dev/null | tr -d '\r')"
    fi
    # An untracked or unknown file has no commit recency; it sorts NEWEST so the
    # cap keeps the oldest-untouched code, which is what this skill is hunting.
    [[ -n "$ts" ]] || ts="$NOW"
    FILE_TS["$c_file"]="$ts"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$c_file" "$c_line" "$c_shape" "$c_excerpt" >>"$WORK/keyed.tsv"
done <"$CAND"

LC_ALL=C sort -t"$TAB" -k1,1n -k2,2 -k3,3n "$WORK/keyed.tsv" >"$WORK/sorted.tsv"
TOTAL_CAND="$(wc -l <"$WORK/sorted.tsv" | tr -d ' ')"
# The cap is applied with awk, never `head`: a truncating reader that closes its
# input early is exactly the shape this script refuses to build.
#
# T3 drift is EXEMPT from the cap. A drift record's file is `-` or a root name,
# so it has no commit recency, sorts newest, and was therefore the first thing a
# cap dropped — silently turning the one alarm this script raises about its own
# blindness into nothing at all. SKILL.md "T3 is the drift bucket": an
# unrecognized detector line is "recorded, never silently dropped".
if ((MAX > 0)); then
  awk -F"$TAB" -v m="$MAX" '$4 == "detector-drift" || ++n <= m' "$WORK/sorted.tsv" >"$WORK/capped.tsv"
else
  cp "$WORK/sorted.tsv" "$WORK/capped.tsv"
fi
# Drop the recency sort key now that ordering is fixed.
cut -f2- "$WORK/capped.tsv" >"$WORK/emitted.tsv"
EMITTED="$(wc -l <"$WORK/emitted.tsv" | tr -d ' ')"
DROPPED=$((TOTAL_CAND - EMITTED))

cat "$LANES"
cat "$NOTES"

lanes_ran=0
lanes_skipped=0
lanes_degraded=0
lanes_zero=0
while IFS= read -r l_line; do
  case "$l_line" in
  *'state=ran '*) lanes_ran=$((lanes_ran + 1)) ;;
  *'state=skipped '*) lanes_skipped=$((lanes_skipped + 1)) ;;
  *'state=degraded '*) lanes_degraded=$((lanes_degraded + 1)) ;;
  *'state=scanned-zero-files '*) lanes_zero=$((lanes_zero + 1)) ;;
  *) ;;
  esac
done <"$LANES"

total_t1=0
total_t2=0
total_t3=0
files_audited=0
cur_file=""
t1=0
t2=0
t3=0

flush_file() {
  [[ -n "$cur_file" ]] || return 0
  printf 'Summary file: %s | T1=%s T2=%s T3=%s\n' "$cur_file" "$t1" "$t2" "$t3"
}

while IFS="$TAB" read -r e_file e_line e_shape e_excerpt; do
  [[ -n "$e_shape" ]] || continue
  if [[ "$e_file" != "$cur_file" ]]; then
    flush_file
    cur_file="$e_file"
    files_audited=$((files_audited + 1))
    t1=0
    t2=0
    t3=0
  fi
  tier="$(dc_shape_tier "$e_shape")"
  printf 'File: %s\n' "$e_file"
  printf 'Finding tier: %s\n' "$tier"
  printf 'Finding shape: %s\n' "$e_shape"
  printf 'Finding line: %s\n' "$e_line"
  printf 'Finding excerpt: %s\n' "$e_excerpt"
  printf '%s\n' '---'
  case "$tier" in
  1) t1=$((t1 + 1)) total_t1=$((total_t1 + 1)) ;;
  2) t2=$((t2 + 1)) total_t2=$((total_t2 + 1)) ;;
  *) t3=$((t3 + 1)) total_t3=$((total_t3 + 1)) ;;
  esac
done <"$WORK/emitted.tsv"
flush_file

printf 'Summary lanes: ran=%s skipped=%s degraded=%s scanned-zero-files=%s\n' \
  "$lanes_ran" "$lanes_skipped" "$lanes_degraded" "$lanes_zero"
printf 'Summary candidates: total=%s emitted=%s dropped-by-cap=%s cap=%s\n' \
  "$TOTAL_CAND" "$EMITTED" "$DROPPED" "$MAX"
printf 'Summary total: files=%s T1=%s T2=%s T3=%s\n' \
  "$files_audited" "$total_t1" "$total_t2" "$total_t3"

if [[ "$TOTAL_CAND" -eq 0 ]]; then
  if [[ "$lanes_ran" -eq 0 ]]; then
    echo "Note: no lane ran — this is a scan of nothing, not a clean bill. Read the Lane lines above before reporting anything as clean."
  else
    echo "Note: no candidates from the lanes that ran — read their Lane lines for what each one actually covered."
  fi
fi

exit 0
