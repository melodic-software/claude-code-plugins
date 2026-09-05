#!/usr/bin/env bash
# The code-metrics dispatcher: resolve the scope, detect lanes, walk the
# collector ladder, and print one `code-metrics/v1` document (design T1, T3,
# T5). Every audit skill's entry script (skills/<name>/scripts/<name>.sh) calls this; skill-specific options are the
# skill's own and never reach here.
#
#   dispatch.sh <skill> --measures <m1,m2,...> [--all] [--base <ref>]
#               [--config <resolved.json>] [--ladder <file.tsv>]
#               [--lane-globs <lane>=<glob>[,<glob>...]]... [--disable-lane <lane>]...
#               [--scope-file <file>] [--] [<path>...]
#
# Scope: `<path>...` measures those files and directories (an explicitly named
# path that does not exist is a usage error, exit 2); `--all` measures every
# tracked or untracked-but-not-ignored file under the paths (or the whole
# repository); with neither, the default is the change: files that differ from
# the merge-base with the default branch plus uncommitted and untracked files.
# `--scope-file` reads the file list from a file (one path per line) instead.
# Every path is emitted with forward slashes.
#
# Configuration: without `--config`, the cascade is resolved here through
# scripts/resolve-config.py (bundled defaults, then ~/.claude/code-metrics.yaml,
# .claude/code-metrics.yaml, .claude/code-metrics.local.yaml, plus the
# consumer's .claude/ecosystems/<lane>.yaml files); CODE_METRICS_HOME overrides
# the home directory the user-global layer is read from. `--config` takes a
# pre-resolved JSON document (the resolver's output) instead. Either way the
# resolved document supplies the references, `scope.exclude`, the per-lane
# collector overrides, and the ecosystem globs and opt-outs.
#
# Exit: 0 the document was produced (including an `empty` run); 2 usage or
# environment error; 3 a resolved collector ran and produced no parseable
# output (the document is still produced, with the failure in `run[]`).
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
COLLECTORS="$PLUGIN_ROOT/scripts/collectors"
REPORT="$PLUGIN_ROOT/scripts/report.py"
DETECT="$PLUGIN_ROOT/scripts/detect-lanes.sh"
LADDER="$PLUGIN_ROOT/scripts/collector-ladder.tsv"
RESOLVER="$PLUGIN_ROOT/scripts/resolve-config.py"
PATHGLOB="$PLUGIN_ROOT/scripts/pathglob.py"
CONFIG=""

usage() {
  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

die_usage() {
  printf 'dispatch.sh: %s\n' "$1" >&2
  exit 2
}

# shellcheck source=python-resolve.sh
source "$PLUGIN_ROOT/scripts/python-resolve.sh"

SKILL=""
MEASURES=""
MODE="change"
BASE="auto"
SCOPE_FILE=""
DETECT_ARGS=()
PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --measures)
    [[ $# -ge 2 ]] || die_usage "--measures needs a value"
    MEASURES="$2"
    shift 2
    ;;
  --all)
    MODE="all"
    shift
    ;;
  --base)
    [[ $# -ge 2 ]] || die_usage "--base needs a value"
    BASE="$2"
    shift 2
    ;;
  --config)
    [[ $# -ge 2 ]] || die_usage "--config needs a value"
    CONFIG="$2"
    shift 2
    ;;
  --ladder)
    [[ $# -ge 2 ]] || die_usage "--ladder needs a value"
    LADDER="$2"
    shift 2
    ;;
  --lane-globs)
    [[ $# -ge 2 ]] || die_usage "--lane-globs needs a value"
    DETECT_ARGS+=(--globs "$2")
    shift 2
    ;;
  --disable-lane)
    [[ $# -ge 2 ]] || die_usage "--disable-lane needs a value"
    DETECT_ARGS+=(--disable "$2")
    shift 2
    ;;
  --scope-file)
    [[ $# -ge 2 ]] || die_usage "--scope-file needs a value"
    SCOPE_FILE="$2"
    MODE="paths"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  --)
    shift
    PATHS+=("$@")
    break
    ;;
  -*)
    die_usage "unknown option $1"
    ;;
  *)
    if [[ -z "$SKILL" ]]; then
      SKILL="$1"
    else
      PATHS+=("$1")
    fi
    shift
    ;;
  esac
done
[[ -n "$SKILL" ]] || die_usage "a skill name is required"
[[ -n "$MEASURES" ]] || die_usage "--measures is required"
[[ -f "$LADDER" ]] || die_usage "ladder file not found: $LADDER"
[[ -z "$CONFIG" || -f "$CONFIG" ]] || die_usage "config file not found: $CONFIG"
[[ ${#PATHS[@]} -gt 0 && "$MODE" == "change" ]] && MODE="paths"

if ! cm_resolve_python; then
  die_usage "Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); it is a required prerequisite"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FILES_LIST="$WORK/files"
: >"$FILES_LIST"

# ---- configuration -----------------------------------------------------------
if [[ -z "$CONFIG" ]]; then
  CONFIG="$WORK/config.json"
  "${PY[@]}" "$RESOLVER" --ladder "$LADDER" --home "${CODE_METRICS_HOME:-${HOME:-/}}" >"$CONFIG" ||
    die_usage "the configuration could not be resolved (see the message above)"
fi
# Ecosystem globs and lane opt-outs from the resolved document come first, so
# an explicit command-line --lane-globs/--disable-lane wins over them.
mapfile -t config_detect_args < <("${PY[@]}" "$RESOLVER" --from-json "$CONFIG" --format dispatch-args)
CONFIG_DETECT_ARGS=()
for line in "${config_detect_args[@]}"; do
  [[ -n "$line" ]] || continue
  case "${line%% *}" in
  --lane-globs) CONFIG_DETECT_ARGS+=(--globs "${line#* }") ;;
  --disable-lane) CONFIG_DETECT_ARGS+=(--disable "${line#* }") ;;
  *) die_usage "unexpected resolver output: $line" ;;
  esac
done
DETECT_ARGS=("${CONFIG_DETECT_ARGS[@]}" "${DETECT_ARGS[@]}")
LADDER_OVERRIDES="$WORK/ladder-overrides.tsv"
"${PY[@]}" "$RESOLVER" --from-json "$CONFIG" --format ladder-overrides >"$LADDER_OVERRIDES"
mapfile -t EXCLUDE_GLOBS < <("${PY[@]}" "$RESOLVER" --from-json "$CONFIG" --format excludes)

# ---- scope -------------------------------------------------------------------
in_git="$(git rev-parse --is-inside-work-tree 2>/dev/null || true)"

list_tracked_under() {
  # Tracked plus untracked-but-not-ignored files under a path, or a plain
  # walk outside git. Directories only; files are appended by the caller.
  if [[ "$in_git" == "true" ]] && git ls-files --error-unmatch --cached --others --exclude-standard -- "$1" >/dev/null 2>&1; then
    git ls-files --cached --others --exclude-standard -- "$1"
  else
    # Outside git, or a path outside this repository (git refuses it).
    find "$1" -type f
  fi
}

expand_path() {
  local p="$1"
  if [[ -d "$p" ]]; then
    list_tracked_under "$p"
  elif [[ -f "$p" ]]; then
    printf '%s\n' "$p"
  else
    die_usage "path does not exist: $p"
  fi
}

BASE_SHA=""
case "$MODE" in
all)
  if [[ ${#PATHS[@]} -gt 0 ]]; then
    for p in "${PATHS[@]}"; do expand_path "$p"; done >>"$FILES_LIST"
  elif [[ "$in_git" == "true" ]]; then
    git ls-files --cached --others --exclude-standard >>"$FILES_LIST"
  else
    find . -type f >>"$FILES_LIST"
  fi
  ;;
paths)
  if [[ -n "$SCOPE_FILE" ]]; then
    [[ -f "$SCOPE_FILE" ]] || die_usage "scope file does not exist: $SCOPE_FILE"
    while IFS= read -r p; do
      [[ -n "$p" ]] && expand_path "$p"
    done <"$SCOPE_FILE" >>"$FILES_LIST"
  fi
  for p in "${PATHS[@]}"; do expand_path "$p"; done >>"$FILES_LIST"
  ;;
change)
  [[ "$in_git" == "true" ]] || die_usage "change scope needs a git repository; pass paths or --all"
  if [[ "$BASE" == "auto" ]]; then
    default_ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [[ -z "$default_ref" ]]; then
      for candidate in origin/main origin/master main master; do
        if git rev-parse --verify --quiet "$candidate" >/dev/null; then
          default_ref="$candidate"
          break
        fi
      done
    fi
    [[ -n "$default_ref" ]] || die_usage "cannot find a default branch for the merge-base; pass --base <ref>"
    BASE_SHA="$(git merge-base HEAD "$default_ref" 2>/dev/null || true)"
    [[ -n "$BASE_SHA" ]] || die_usage "no merge-base between HEAD and $default_ref; pass --base <ref>"
  else
    BASE_SHA="$(git rev-parse --verify --quiet "$BASE" 2>/dev/null || true)"
    [[ -n "$BASE_SHA" ]] || die_usage "base ref not found: $BASE"
  fi
  # Both listings are asked for root-relative names (`git diff` always prints
  # them; `ls-files` prints cwd-relative ones and limits itself to the cwd
  # without a pathspec), then rebased onto the cwd, so a run from a
  # subdirectory keeps the whole change and every path stays cwd-relative
  # like an explicitly named one.
  root_prefix="$(git rev-parse --show-prefix 2>/dev/null || true)"
  climb=""
  if [[ -n "$root_prefix" ]]; then
    slashes="${root_prefix//[^\/]/}"
    for ((i = 0; i < ${#slashes}; i++)); do climb+="../"; done
  fi
  {
    git diff --name-only --diff-filter=d "$BASE_SHA"
    git ls-files --others --exclude-standard --modified --full-name -- ':/'
  } | while IFS= read -r p; do
    if [[ -z "$root_prefix" ]]; then
      printf '%s\n' "$p"
    elif [[ "$p" == "$root_prefix"* ]]; then
      printf '%s\n' "${p#"$root_prefix"}"
    else
      printf '%s\n' "$climb$p"
    fi
  done >>"$FILES_LIST"
  ;;
*)
  die_usage "unknown scope mode $MODE"
  ;;
esac

# Normalize: forward slashes, drop `./`, dedupe, keep existing regular files
# that are not binary.
SCOPED="$WORK/scoped"
tr -d '\r' <"$FILES_LIST" | sed 's#\\#/#g; s#^\./##' | awk 'NF && !seen[$0]++' >"$WORK/dedup"
: >"$SCOPED"
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  # Binary sniff without GNU grep -I: a NUL in the first 8000 bytes.
  head_bytes="$(head -c 8000 "$f" | wc -c | tr -d ' ')"
  text_bytes="$(head -c 8000 "$f" | LC_ALL=C tr -d '\000' | wc -c | tr -d ' ')"
  [[ "$head_bytes" == "$text_bytes" ]] || continue
  printf '%s\n' "$f" >>"$SCOPED"
done <"$WORK/dedup"
# scope.exclude: drop every file a configured glob matches, counting them.
EXCLUDED=0
if [[ ${#EXCLUDE_GLOBS[@]} -gt 0 && -s "$SCOPED" ]]; then
  mapfile -t candidates <"$SCOPED"
  : >"$WORK/excluded"
  for pattern in "${EXCLUDE_GLOBS[@]}"; do
    [[ -n "$pattern" ]] || continue
    "${PY[@]}" "$PATHGLOB" "$pattern" "${candidates[@]}" >>"$WORK/excluded"
  done
  if [[ -s "$WORK/excluded" ]]; then
    sort -u "$WORK/excluded" >"$WORK/excluded.sorted"
    EXCLUDED="$(wc -l <"$WORK/excluded.sorted" | tr -d ' ')"
    sort "$SCOPED" | comm -23 - "$WORK/excluded.sorted" >"$WORK/kept"
    # comm sorted the list; restore the scope order.
    awk 'NR == FNR { keep[$0] = 1; next } keep[$0]' "$WORK/kept" "$SCOPED" >"$WORK/scoped.kept"
    mv "$WORK/scoped.kept" "$SCOPED"
  fi
fi
FILE_COUNT="$(wc -l <"$SCOPED" | tr -d ' ')"

# ---- lanes -------------------------------------------------------------------
LANES_TSV="$WORK/lanes"
if [[ "$FILE_COUNT" -gt 0 ]]; then
  mapfile -t scoped_files <"$SCOPED"
  bash "$DETECT" "${DETECT_ARGS[@]}" -- "${scoped_files[@]}" >"$LANES_TSV" || exit 2
else
  : >"$LANES_TSV"
fi

# ---- ladder ------------------------------------------------------------------
ladder_tools() {
  # Print the ordered tool list for a lane/measure; `*` rows apply when the
  # measure has no explicit row. Each line: tool<TAB>note.
  # A `lanes.<lane>.collectors.<measure>` override from the resolved config
  # replaces the bundled rows for that lane and measure (contracts.md §1).
  local lane="$1" measure="$2" explicit
  explicit="$(awk -F'\t' -v l="$lane" -v m="$measure" 'NF >= 3 && $1 == l && $2 == m { print $3 "\t" }' "$LADDER_OVERRIDES")"
  [[ -n "$explicit" ]] ||
    explicit="$(awk -F'\t' -v l="$lane" -v m="$measure" '!/^#/ && NF >= 3 && $1 == l && $2 == m { print $3 "\t" $4 }' "$LADDER")"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
  else
    awk -F'\t' -v l="$lane" '!/^#/ && NF >= 3 && $1 == l && $2 == "*" { print $3 "\t" $4 }' "$LADDER"
  fi
}

RUN="$WORK/run.jsonl"
ROWS="$WORK/measures.jsonl"
: >"$RUN"
: >"$ROWS"
COLLECT_FAILED=0

json_str() {
  "${PY[@]}" -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

run_row() {
  # run_row <lane> <measure> <collector-or-empty> <status> <reason-or-empty>
  local collector reason
  if [[ -n "$3" ]]; then collector="$(json_str "$3")"; else collector=null; fi
  if [[ -n "$5" ]]; then reason="$(json_str "$5")"; else reason=null; fi
  printf '{"lane": %s, "measure": %s, "collector": %s, "status": %s, "reason": %s}\n' \
    "$(json_str "$1")" "$(json_str "$2")" "$collector" "$(json_str "$4")" "$reason" >>"$RUN"
}

IFS=',' read -r -a MEASURE_LIST <<<"$MEASURES"
mapfile -t LANES < <(cut -f1 "$LANES_TSV" | awk 'NF && !seen[$0]++' | sort)

if [[ "$FILE_COUNT" -eq 0 || ${#LANES[@]} -eq 0 ]]; then
  run_row '*' '*' '' not-applicable 'no measurable files in scope'
fi

for lane in "${LANES[@]}"; do
  mapfile -t lane_files < <(awk -F'\t' -v l="$lane" '$1 == l { print $2 }' "$LANES_TSV")
  for measure in "${MEASURE_LIST[@]}"; do
    resolved=0
    reasons=""
    while IFS=$'\t' read -r tool note; do
      [[ -n "$tool" ]] || continue
      case "$tool" in
      none)
        run_row "$lane" "$measure" '' unavailable "${note:-no collector}"
        resolved=1
        break
        ;;
      n/a)
        run_row "$lane" "$measure" '' not-applicable "${note:-not applicable}"
        resolved=1
        break
        ;;
      deferred)
        run_row "$lane" "$measure" '' deferred "${note:-deferred}"
        resolved=1
        break
        ;;
      *) ;;
      esac
      adapter="$COLLECTORS/$tool.py"
      if [[ ! -f "$adapter" ]]; then
        reasons+="${reasons:+; }$tool: adapter not shipped"
        continue
      fi
      # A failed probe's stderr is the specific reason (a binary present but a
      # dependency it needs absent); "not found" is the fallback wording.
      probe_err="$WORK/probe.$lane.$measure.$tool"
      if ! version="$("${PY[@]}" "$adapter" probe 2>"$probe_err")"; then
        hint="$("${PY[@]}" "$adapter" install_hint 2>/dev/null || true)"
        why="$(tr '\n' ' ' <"$probe_err" | cut -c1-200)"
        why="${why% }"
        reasons+="${reasons:+; }$tool: ${why:-not found}${hint:+ ($hint)}"
        continue
      fi
      errf="$WORK/err.$lane.$measure.$tool"
      outf="$WORK/out.$lane.$measure.$tool"
      "${PY[@]}" "$adapter" collect "$lane" "$measure" "${lane_files[@]}" >"$outf" 2>"$errf"
      rc=$?
      if [[ $rc -eq 0 ]]; then
        cat "$outf" >>"$ROWS"
        run_row "$lane" "$measure" "$tool $version" ok ''
      else
        COLLECT_FAILED=1
        run_row "$lane" "$measure" "$tool $version" unavailable "collect failed (exit $rc): $(tr '\n' ' ' <"$errf" | cut -c1-500)"
      fi
      resolved=1
      break
    done < <(ladder_tools "$lane" "$measure")
    if [[ $resolved -eq 0 ]]; then
      run_row "$lane" "$measure" '' unavailable "${reasons:-no ladder entry for $lane/$measure}"
    fi
  done
done

# ---- assemble ----------------------------------------------------------------
SCOPE_JSON="$WORK/scope.json"
base_json=null
[[ -n "$BASE_SHA" ]] && base_json="$(json_str "${BASE_SHA:0:12}")"
# `files` counts every file in scope; `unclassified` is how many of them
# belong to no lane (a markdown file in a source tree), so `files` minus
# `unclassified` reconciles with the measured file count.
CLASSIFIED="$(cut -f2 "$LANES_TSV" | awk 'NF && !seen[$0]++' | wc -l | tr -d ' ')"
printf '{"mode": %s, "base": %s, "files": %s, "unclassified": %s, "excluded": %s}\n' \
  "$(json_str "$MODE")" "$base_json" "$FILE_COUNT" "$((FILE_COUNT - CLASSIFIED))" "$EXCLUDED" >"$SCOPE_JSON"

THRESHOLDS="$WORK/thresholds.json"
# The ladder's `halstead` measure reports several values; the reference is on
# difficulty, which is the threshold entry's name.
threshold_measures=""
for measure in "${MEASURE_LIST[@]}"; do
  [[ "$measure" == "halstead" ]] && measure="halstead_difficulty"
  [[ "$measure" == "function_lines" ]] && measure="function_lines_pct"
  threshold_measures+="${threshold_measures:+,}$measure"
done
"${PY[@]}" "$REPORT" thresholds --config "$CONFIG" --measures "$threshold_measures" >"$THRESHOLDS" || exit 2

"${PY[@]}" "$REPORT" assemble --skill "$SKILL" --scope "$SCOPE_JSON" --run "$RUN" --measures "$ROWS" --thresholds "$THRESHOLDS" || exit 2

[[ $COLLECT_FAILED -eq 0 ]] || exit 3
exit 0
