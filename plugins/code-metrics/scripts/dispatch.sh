#!/usr/bin/env bash
set -uo pipefail

USAGE="$(
  cat <<'EOF'
The code-metrics dispatcher: resolve the scope, detect languages, walk the collector ladder,
and print one code-metrics/v2 document.
  dispatch.sh <skill> --measures <m1,m2,...> [options] [--] [<path>...]
  --measures <list>          measures to collect. Required.
  --all                      every tracked or untracked-but-not-ignored file under the paths
  --base <ref>               measure the change from the merge-base with <ref>
  --config <resolved.json>   a resolved configuration (default: resolve-config.py)
  --ladder <file.tsv>        collector ladder to walk
  --language-globs <language>=<glob> replace the language's extension mapping with these globs
  --disable-language <language>      turn a language off
  --scope-file <file>        read the file list from a file, one path per line
  --print-scope              print the scope as language<TAB>path rows and stop
  --no-collapse              keep sanctioned replicas as separate rows
  --no-anchor                leave paths cwd-relative
Exit: 0 the document was produced (including an empty run); 2 usage or environment error;
3 a collector ran and produced nothing parseable.
EOF
)"

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
COLLECTORS="$PLUGIN_ROOT/scripts/collectors"
REPORT="$PLUGIN_ROOT/scripts/report.py"
DETECT="$PLUGIN_ROOT/scripts/detect-languages.sh"
LADDER="$PLUGIN_ROOT/scripts/collector-ladder.tsv"
RESOLVER="$PLUGIN_ROOT/scripts/resolve-config.py"
PATHGLOB="$PLUGIN_ROOT/scripts/pathglob.py"
SCOPE_FILTER="$PLUGIN_ROOT/scripts/scope-filter.py"
CONFIG=""

usage() {
  cm_usage_banner --usage "$USAGE"
}

die_usage() {
  printf 'dispatch.sh: %s\n' "$1" >&2
  exit 2
}

# shellcheck source=python-resolve.sh
source "$PLUGIN_ROOT/scripts/python-resolve.sh"
# shellcheck source=entry-common.sh
source "$PLUGIN_ROOT/scripts/entry-common.sh"

SKILL=""
MEASURES=""
MODE="change"
BASE="auto"
MODE_SET=0
BASE_SET=0
PRINT_SCOPE=0
NO_COLLAPSE=0
NO_ANCHOR=0
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
    MODE_SET=1
    shift
    ;;
  --base)
    [[ $# -ge 2 ]] || die_usage "--base needs a value"
    BASE="$2"
    BASE_SET=1
    shift 2
    ;;
  --print-scope)
    PRINT_SCOPE=1
    shift
    ;;
  --no-collapse)
    NO_COLLAPSE=1
    shift
    ;;
  --no-anchor)
    NO_ANCHOR=1
    shift
    ;;
  --user-file)
    cm_set_user_file "$@" || exit 2
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
  --language-globs)
    [[ $# -ge 2 ]] || die_usage "--language-globs needs a value"
    DETECT_ARGS+=(--globs "$2")
    shift 2
    ;;
  --disable-language)
    [[ $# -ge 2 ]] || die_usage "--disable-language needs a value"
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
[[ "$MODE" == "paths" ]] && MODE_SET=1

if ! cm_resolve_python; then
  die_usage "Python ${CM_PYTHON_FLOOR}+ not found (tried python3, python, py -3); it is a required prerequisite"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FILES_LIST="$WORK/files"
: >"$FILES_LIST"

json_str() {
  "${PY[@]}" -I -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

count_lines() {
  wc -l <"$1" | tr -d ' '
}

capped_line() {
  tr '\n' ' ' <"$1" | cut -c1-"$2"
}

PROGRESS=0
progress() {
  [[ "$PROGRESS" -eq 1 ]] && printf 'code-metrics: %s\n' "$*" >&2
  return 0
}

if [[ -z "$CONFIG" ]]; then
  CONFIG="$WORK/config.json"
  cm_resolve_config "$CONFIG" "$LADDER" ||
    die_usage "the configuration could not be resolved (see the message above)"
fi
resolver_format() {
  if ! "${PY[@]}" "$RESOLVER" --from-json "$CONFIG" --format "$1" >"$2"; then
    die_usage "the configuration could not be read as $1 (see the message above)"
  fi
}
resolver_format dispatch-args "$WORK/dispatch-args"
mapfile -t config_detect_args <"$WORK/dispatch-args"
CONFIG_DETECT_ARGS=()
for line in "${config_detect_args[@]}"; do
  [[ -n "$line" ]] || continue
  case "${line%% *}" in
  --language-globs) CONFIG_DETECT_ARGS+=(--globs "${line#* }") ;;
  --disable-language) CONFIG_DETECT_ARGS+=(--disable "${line#* }") ;;
  --scope-default)
    if [[ "$MODE_SET" -eq 0 && "$BASE_SET" -eq 0 && "${line#* }" == "all" ]]; then MODE="all"; fi
    ;;
  --scope-base)
    if [[ "$BASE_SET" -eq 0 ]]; then BASE="${line#* }"; fi
    ;;
  *) die_usage "unexpected resolver output: $line" ;;
  esac
done
DETECT_ARGS=("${CONFIG_DETECT_ARGS[@]}" "${DETECT_ARGS[@]}")
LADDER_OVERRIDES="$WORK/ladder-overrides.tsv"
resolver_format ladder-overrides "$LADDER_OVERRIDES"
resolver_format excludes "$WORK/excludes"
mapfile -t EXCLUDE_GLOBS <"$WORK/excludes"
# shellcheck source=replica-collapse.sh
source "$PLUGIN_ROOT/scripts/replica-collapse.sh"
cm_registry_paths "$CONFIG" >/dev/null || exit 2

in_git="$(git rev-parse --is-inside-work-tree 2>/dev/null || true)"

inside_repo() {
  local top abs
  [[ "$in_git" == "true" ]] || return 1
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "$top" ]] || return 1
  abs="$(cd -P "$1" 2>/dev/null && pwd -P)" || return 1
  [[ "$abs" == "$top" || "$abs" == "$top"/* ]]
}

git_listing() {
  local out="$1"
  shift
  # core.quotePath=false stops git quoting bytes above 0x80 in output paths.
  # https://git-scm.com/docs/git-config
  if ! git -c core.quotePath=false "$@" >"$out"; then
    die_usage "the repository file listing failed: git $1 (see the message above)"
  fi
}

list_tracked_under() {
  if inside_repo "$1"; then
    git -c core.quotePath=false ls-files --cached --others --exclude-standard -- "$1"
  else
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

rebase_onto_cwd() {
  local root_prefix climb slashes i p
  root_prefix="$(git rev-parse --show-prefix 2>/dev/null || true)"
  climb=""
  if [[ -n "$root_prefix" ]]; then
    slashes="${root_prefix//[^\/]/}"
    for ((i = 0; i < ${#slashes}; i++)); do climb+="../"; done
  fi
  while IFS= read -r p; do
    if [[ -z "$root_prefix" ]]; then
      printf '%s\n' "$p"
    elif [[ "$p" == "$root_prefix"* ]]; then
      printf '%s\n' "${p#"$root_prefix"}"
    else
      printf '%s\n' "$climb$p"
    fi
  done
}

to_root_relative() {
  local root_prefix
  root_prefix="$(git rev-parse --show-prefix 2>/dev/null || true)"
  awk -v prefix="$root_prefix" '
    function normalize(path,   parts, count, i, kept, top, segment, out) {
      count = split(path, parts, "/")
      top = 0
      for (i = 1; i <= count; i++) {
        segment = parts[i]
        if (segment == "" || segment == ".") continue
        if (segment == ".." && top > 0 && kept[top] != "..") { top--; continue }
        kept[++top] = segment
      }
      out = ""
      for (i = 1; i <= top; i++) out = (i == 1) ? kept[i] : out "/" kept[i]
      return out
    }
    { print normalize(prefix $0) }
  '
}

BASE_SHA=""
case "$MODE" in
all)
  if [[ ${#PATHS[@]} -gt 0 ]]; then
    for p in "${PATHS[@]}"; do expand_path "$p"; done >>"$FILES_LIST"
  elif [[ "$in_git" == "true" ]]; then
    git_listing "$WORK/all-listing" ls-files --cached --others --exclude-standard --full-name -- ':/'
    rebase_onto_cwd <"$WORK/all-listing" >>"$FILES_LIST"
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
    base_merge="$(git merge-base HEAD "$BASE_SHA" 2>/dev/null || true)"
    [[ -n "$base_merge" ]] || die_usage "no merge-base between HEAD and $BASE"
    BASE_SHA="$base_merge"
  fi
  git_listing "$WORK/diff-listing" diff --name-only --diff-filter=d "$BASE_SHA"
  git_listing "$WORK/work-listing" ls-files --others --exclude-standard --modified --full-name -- ':/'
  cat "$WORK/diff-listing" "$WORK/work-listing" | rebase_onto_cwd >>"$FILES_LIST"
  ;;
*)
  die_usage "unknown scope mode $MODE"
  ;;
esac

SCOPED="$WORK/scoped"
if ! "${PY[@]}" "$SCOPE_FILTER" --paths-from "$FILES_LIST" >"$SCOPED"; then
  die_usage "the scope listing could not be filtered (see the message above)"
fi
EXCLUDED=0
EXCLUSION_ROWS=()
if [[ ${#EXCLUDE_GLOBS[@]} -gt 0 && -s "$SCOPED" ]]; then
  : >"$WORK/excluded-rootrel"
  to_root_relative <"$SCOPED" >"$WORK/scoped-rootrel"
  paste "$WORK/scoped-rootrel" "$SCOPED" >"$WORK/scope-map"
  for pattern in "${EXCLUDE_GLOBS[@]}"; do
    [[ -n "$pattern" ]] || continue
    if ! "${PY[@]}" "$PATHGLOB" "$pattern" --paths-from "$WORK/scoped-rootrel" >"$WORK/excluded-hits"; then
      die_usage "scope.exclude: the glob $pattern could not be used (see the message above)"
    fi
    if [[ -s "$WORK/excluded-hits" ]]; then
      hits="$(count_lines "$WORK/excluded-hits")"
      EXCLUSION_ROWS+=("$(printf '{"pattern": %s, "files": %s}' "$(json_str "$pattern")" "$hits")")
      cat "$WORK/excluded-hits" >>"$WORK/excluded-rootrel"
    fi
  done
  awk -F'\t' 'NR == FNR { hit[$0] = 1; next } hit[$1] { print $2 }' \
    "$WORK/excluded-rootrel" "$WORK/scope-map" >"$WORK/excluded"
  if [[ -s "$WORK/excluded" ]]; then
    sort -u "$WORK/excluded" >"$WORK/excluded.sorted"
    EXCLUDED="$(count_lines "$WORK/excluded.sorted")"
    sort "$SCOPED" | comm -23 - "$WORK/excluded.sorted" >"$WORK/kept"
    awk 'NR == FNR { keep[$0] = 1; next } keep[$0]' "$WORK/kept" "$SCOPED" >"$WORK/scoped.kept"
    mv "$WORK/scoped.kept" "$SCOPED"
  fi
fi
FILE_COUNT="$(count_lines "$SCOPED")"
if [[ "${CODE_METRICS_PROGRESS:-}" == "1" || ("${CODE_METRICS_PROGRESS:-}" != "0" && "$FILE_COUNT" -gt 200) ]]; then
  PROGRESS=1
fi
progress "$SKILL: $FILE_COUNT file(s) in scope ($MODE), $EXCLUDED excluded"

LANGUAGES_TSV="$WORK/languages"
if [[ "$FILE_COUNT" -gt 0 ]]; then
  bash "$DETECT" "${DETECT_ARGS[@]}" --paths-from "$SCOPED" >"$LANGUAGES_TSV" || exit 2
else
  : >"$LANGUAGES_TSV"
fi

if [[ "$PRINT_SCOPE" -eq 1 ]]; then
  cat "$LANGUAGES_TSV"
  exit 0
fi

ladder_tools() {
  local language="$1" measure="$2" explicit
  explicit="$(awk -F'\t' -v l="$language" -v m="$measure" 'NF >= 3 && $1 == l && $2 == m { print $3 "\t" }' "$LADDER_OVERRIDES")"
  [[ -n "$explicit" ]] ||
    explicit="$(awk -F'\t' -v l="$language" -v m="$measure" '!/^#/ && NF >= 3 && $1 == l && $2 == m { print $3 "\t" $4 }' "$LADDER")"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
  else
    awk -F'\t' -v l="$language" '!/^#/ && NF >= 3 && $1 == l && $2 == "*" { print $3 "\t" $4 }' "$LADDER"
  fi
}

language_shipped() {
  awk -F'\t' -v l="$1" '!/^#/ && $1 == l { found = 1; exit } END { exit !found }' "$LADDER"
}

RUN="$WORK/run.jsonl"
ROWS="$WORK/measures.jsonl"
: >"$RUN"
: >"$ROWS"
COLLECT_FAILED=0

run_row() {
  "${PY[@]}" -I -c '
import json, sys
language, measure, collector, status, reason, hint = sys.argv[1:7]
print(json.dumps({"language": language, "measure": measure, "collector": collector or None,
                  "status": status, "reason": reason or None, "hint": hint or None}))
' "$2" "$3" "$4" "$5" "$6" "${7:-}" >"$WORK/run.$1"
}

IFS=',' read -r -a MEASURE_LIST <<<"$MEASURES"
mapfile -t LANGUAGES < <(cut -f1 "$LANGUAGES_TSV" | awk 'NF && !seen[$0]++' | sort)

SLOT=0
if [[ "$FILE_COUNT" -eq 0 || ${#LANGUAGES[@]} -eq 0 ]]; then
  reason='no measurable files in scope'
  if [[ "$FILE_COUNT" -gt 0 ]]; then
    reason="no measurable files in scope: the $FILE_COUNT file(s) in scope belong to no language"
  elif [[ "$MODE" == "change" ]]; then
    reason="no measurable files in scope: the branch is at its merge-base with ${default_ref:-$BASE} (${BASE_SHA:0:12}) and the working tree holds no changed or untracked file; pass explicit paths or --all to measure the tree"
  fi
  run_row "$SLOT" '*' '*' '' not-applicable "$reason"
  SLOT=$((SLOT + 1))
fi

JOBS="${CODE_METRICS_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
[[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || JOBS=4
RUNNING=0
PIDS=()
COLLECT_SLOTS=()
S_LANGUAGE=()
S_MEASURE=()
S_TOOL=()
S_VERSION=()

reap_one() {
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))); then
    # wait -n needs bash 4.3.
    # https://cgit.git.savannah.gnu.org/cgit/bash.git/plain/NEWS
    wait -n
  else
    wait "${PIDS[0]}"
  fi
  PIDS=("${PIDS[@]:1}")
  RUNNING=$((RUNNING - 1))
}

launch_collect() {
  local slot="$1" adapter="$2" language="$3" measure="$4"
  shift 4
  printf '%s\n' "$@" >"$WORK/files.$slot"
  (
    started="$(date +%s)"
    CODE_METRICS_PARTIAL_REASON_FILE="$WORK/partial.$slot" \
      "${PY[@]}" "$adapter" collect "$language" "$measure" --paths-from "$WORK/files.$slot" >"$WORK/out.$slot" 2>"$WORK/err.$slot"
    rc=$?
    printf '%s %s\n' "$rc" "$(($(date +%s) - started))" >"$WORK/rc.$slot"
  ) &
  PIDS+=("$!")
  RUNNING=$((RUNNING + 1))
  if [[ "$RUNNING" -ge "$JOBS" ]]; then
    reap_one
  fi
}

for language in "${LANGUAGES[@]}"; do
  mapfile -t language_files < <(awk -F'\t' -v l="$language" '$1 == l { print $2 }' "$LANGUAGES_TSV")
  shipped=1
  language_shipped "$language" || shipped=0
  for measure in "${MEASURE_LIST[@]}"; do
    slot=$SLOT
    SLOT=$((SLOT + 1))
    tools="$(ladder_tools "$language" "$measure")"
    if [[ -z "$tools" && "$shipped" -eq 0 ]]; then
      if [[ "$measure" != "file_lines" ]]; then
        run_row "$slot" "$language" "$measure" '' unavailable "no shipped collector for the $language language"
        continue
      fi
      tools="$(ladder_tools other file_lines)"
    fi
    resolved=0
    reasons=""
    first_hint=""
    while IFS=$'\t' read -r tool note; do
      [[ -n "$tool" ]] || continue
      status=""
      case "$tool" in
      none) status=unavailable fallback="no collector" ;;
      n/a) status=not-applicable fallback="not applicable" ;;
      deferred) status=deferred fallback=deferred ;;
      *) ;;
      esac
      if [[ -n "$status" ]]; then
        run_row "$slot" "$language" "$measure" '' "$status" "${note:-$fallback}"
        resolved=1
        break
      fi
      adapter="$COLLECTORS/$tool.py"
      if [[ ! -f "$adapter" ]]; then
        reasons+="${reasons:+; }$tool: adapter not shipped"
        continue
      fi
      probe_err="$WORK/probe.$language.$measure.$tool"
      if ! version="$("${PY[@]}" "$adapter" probe 2>"$probe_err")"; then
        hint="$("${PY[@]}" "$adapter" install_hint 2>/dev/null || true)"
        why="$(capped_line "$probe_err" 200)"
        why="${why% }"
        reasons+="${reasons:+; }$tool: ${why:-not found}${hint:+ ($hint)}"
        [[ -n "$first_hint" || -z "$hint" ]] || first_hint="$hint"
        continue
      fi
      S_LANGUAGE[slot]="$language"
      S_MEASURE[slot]="$measure"
      S_TOOL[slot]="$tool"
      S_VERSION[slot]="$version"
      COLLECT_SLOTS+=("$slot")
      progress "$language/$measure: running $tool $version over ${#language_files[@]} file(s)"
      launch_collect "$slot" "$adapter" "$language" "$measure" "${language_files[@]}"
      resolved=1
      break
    done <<<"$tools"
    if [[ $resolved -eq 0 ]]; then
      run_row "$slot" "$language" "$measure" '' unavailable "${reasons:-no ladder entry for $language/$measure}" "$first_hint"
    fi
  done
done
wait

for slot in "${COLLECT_SLOTS[@]}"; do
  rc=1
  elapsed=""
  read -r rc elapsed <"$WORK/rc.$slot" || rc=1
  language="${S_LANGUAGE[slot]}"
  measure="${S_MEASURE[slot]}"
  tool="${S_TOOL[slot]}"
  version="${S_VERSION[slot]}"
  if [[ "${rc:-1}" -eq 0 ]]; then
    cat "$WORK/out.$slot" >>"$ROWS"
    if [[ -s "$WORK/partial.$slot" ]]; then
      run_row "$slot" "$language" "$measure" "$tool $version" partial "$(head -n 1 "$WORK/partial.$slot")"
    else
      note="$(capped_line "$WORK/err.$slot" 500)"
      run_row "$slot" "$language" "$measure" "$tool $version" ok "${note% }"
    fi
    progress "$language/$measure: $tool finished in ${elapsed:-?}s, $(count_lines "$WORK/out.$slot") row(s)"
  elif [[ "${rc:-1}" -eq 4 ]]; then
    run_row "$slot" "$language" "$measure" "$tool $version" unavailable "$(capped_line "$WORK/err.$slot" 500)"
    progress "$language/$measure: $tool cannot run here (see the run table)"
  else
    COLLECT_FAILED=1
    run_row "$slot" "$language" "$measure" "$tool $version" unavailable "collect failed (exit $rc): $(capped_line "$WORK/err.$slot" 500)"
    progress "$language/$measure: $tool failed (exit $rc) after ${elapsed:-?}s"
  fi
done
for ((i = 0; i < SLOT; i++)); do
  [[ -f "$WORK/run.$i" ]] && cat "$WORK/run.$i" >>"$RUN"
done

SCOPE_JSON="$WORK/scope.json"
base_json=null
[[ -n "$BASE_SHA" ]] && base_json="$(json_str "${BASE_SHA:0:12}")"
CLASSIFIED="$(cut -f2 "$LANGUAGES_TSV" | awk 'NF && !seen[$0]++' | wc -l | tr -d ' ')"
exclusions_json="[]"
if [[ ${#EXCLUSION_ROWS[@]} -gt 0 ]]; then
  exclusions_json="[$(
    IFS=,
    printf '%s' "${EXCLUSION_ROWS[*]}"
  )]"
fi
printf '{"mode": %s, "base": %s, "files": %s, "unclassified": %s, "excluded": %s, "exclusions": %s}\n' \
  "$(json_str "$MODE")" "$base_json" "$FILE_COUNT" "$((FILE_COUNT - CLASSIFIED))" "$EXCLUDED" "$exclusions_json" >"$SCOPE_JSON"

THRESHOLDS="$WORK/thresholds.json"
threshold_measures=""
for measure in "${MEASURE_LIST[@]}"; do
  case "$measure" in
  halstead) measure="halstead_difficulty" ;;
  function_lines) measure="function_lines_pct" ;;
  *) ;;
  esac
  threshold_measures+="${threshold_measures:+,}$measure"
done
"${PY[@]}" "$REPORT" thresholds --config "$CONFIG" --measures "$threshold_measures" >"$THRESHOLDS" || exit 2

"${PY[@]}" "$REPORT" assemble --skill "$SKILL" --scope "$SCOPE_JSON" --run "$RUN" --measures "$ROWS" --thresholds "$THRESHOLDS" >"$WORK/assembled.json" || exit 2

FINAL="$WORK/assembled.json"
if [[ "$NO_COLLAPSE" -eq 0 ]]; then
  cm_collapse_replicas "$CONFIG" "$WORK/assembled.json" "$WORK/collapsed.json" || exit 2
  FINAL="$WORK/collapsed.json"
fi
[[ "$NO_ANCHOR" -eq 1 ]] || cm_anchor_document "$FINAL" || exit 2
cat "$FINAL"

[[ $COLLECT_FAILED -eq 0 ]] || exit 3
exit 0
