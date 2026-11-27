#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2

MAP="$REPO_ROOT/docs/conventions/lifecycle-map/README.md"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"

usage() {
  printf 'usage: %s [--check] [--map FILE] [--marketplace FILE] [--workflows-dir DIR]\n' "${0##*/}" >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --check) shift ;;
    --map)
      (($# >= 2)) || usage
      MAP="$2"
      shift 2
      ;;
    --marketplace)
      (($# >= 2)) || usage
      MARKETPLACE="$2"
      shift 2
      ;;
    --workflows-dir)
      (($# >= 2)) || usage
      WORKFLOWS_DIR="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "check-lifecycle-map: jq is required but not installed" >&2
  exit 2
fi

if [[ ! -f "$MAP" || ! -r "$MAP" ]]; then
  echo "check-lifecycle-map: map file not found or unreadable: $MAP" >&2
  exit 2
fi
if [[ ! -f "$MARKETPLACE" || ! -r "$MARKETPLACE" ]]; then
  echo "check-lifecycle-map: marketplace file not found or unreadable: $MARKETPLACE" >&2
  exit 2
fi
if [[ ! -d "$WORKFLOWS_DIR" ]]; then
  echo "check-lifecycle-map: workflows directory not found: $WORKFLOWS_DIR" >&2
  exit 2
fi

if ! mp_plugins="$(jq -er '.plugins | if type == "array" then .[].name else error("plugins is not an array") end' "$MARKETPLACE" 2>/dev/null | tr -d '\r')"; then
  echo "check-lifecycle-map: failed to read plugin names from $MARKETPLACE" >&2
  exit 2
fi

disk_workflows=""
shopt -s nullglob
for wf in "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml; do
  [[ -f "$wf" ]] || continue
  disk_workflows+="${wf##*/}"$'\n'
done
shopt -u nullglob

parsed="$(
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function emit_ymls(tag, text, lno,   rest, token) {
      rest = text
      while (match(rest, /`[A-Za-z0-9._-]+\.ya?ml`/)) {
        token = substr(rest, RSTART + 1, RLENGTH - 2)
        printf "%s\t%s\t%d\n", tag, token, lno
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    function emit_backticks(tag, text, lno,   rest, token) {
      rest = text
      while (match(rest, /`[A-Za-z0-9][A-Za-z0-9._-]*`/)) {
        token = substr(rest, RSTART + 1, RLENGTH - 2)
        printf "%s\t%s\t%d\n", tag, token, lno
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    BEGIN {
      section = "tasks"
      subsection = ""
      saw_plugins = 0
      saw_on_map = 0
      saw_not_auto = 0
      in_fence = 0
    }
    { sub(/\r$/, "") }
    /^[ \t]*(```|~~~)/ { in_fence = !in_fence; next }
    in_fence { next }
    /^##[ \t]+/ {
      if ($0 ~ /^##[ \t]+Plugins[ \t]*$/) {
        section = "plugins"
        subsection = ""
        saw_plugins = 1
      } else if (section == "plugins") {
        section = "after_plugins"
        subsection = ""
      }
      next
    }
    section == "plugins" && /^###[ \t]+/ {
      if ($0 ~ /^###[ \t]+On the map[ \t]*$/) {
        subsection = "on_map"
        saw_on_map = 1
      } else if ($0 ~ /^###[ \t]+Not an automated task[ \t]*$/) {
        subsection = "not_auto"
        saw_not_auto = 1
      } else {
        subsection = "other"
      }
      next
    }
    section == "tasks" && /^\|/ {
      n = split($0, cols, "|")
      if (n < 4) next
      task = trim(cols[2])
      shape = trim(cols[3])
      if (task == "" || task == "Task" || task ~ /^[-: ]+$/) next
      if (match(task, /`[A-Za-z0-9._-]+\.ya?ml`/)) {
        emit_ymls("WF_TASK", task, NR)
        emit_ymls("WF_REF", shape, NR)
      } else {
        if (match(shape, /step in `[A-Za-z0-9._-]+\.ya?ml`/)) {
          wf = substr(shape, RSTART + 9, RLENGTH - 10)
          printf "WF_STEP\t%s\t%d\t%s\n", wf, NR, task
        }
        emit_ymls("WF_REF", shape, NR)
      }
      next
    }
    section == "plugins" && subsection == "on_map" && /^\|/ {
      n = split($0, cols, "|")
      if (n < 3) next
      p = trim(cols[2])
      if (p == "" || p == "Plugin" || p ~ /^[-: ]+$/) next
      if (p ~ /^`[A-Za-z0-9][A-Za-z0-9._-]*`$/) {
        printf "PLUGIN\t%s\t%d\ton_map\n", substr(p, 2, length(p) - 2), NR
      }
      next
    }
    section == "plugins" && subsection == "not_auto" {
      emit_backticks("PLUGIN_NOT_AUTO", $0, NR)
      next
    }
    END {
      if (!saw_plugins) print "ERR\tmissing ## Plugins heading"
      if (!saw_on_map) print "ERR\tmissing ### On the map heading"
      if (!saw_not_auto) print "ERR\tmissing ### Not an automated task heading"
    }
  ' "$MAP"
)" || {
  echo "check-lifecycle-map: failed to parse $MAP" >&2
  exit 2
}

TAB=$'\t'
parse_errors=""
declare -A wf_task_lines=()
declare -A wf_placed=()
declare -A wf_step_rows=()
declare -A wf_refs=()
declare -A plugin_lines=()
declare -A plugin_counts=()
declare -A mp_set=()
declare -A disk_wf_set=()

while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  mp_set["$p"]=1
done <<<"$mp_plugins"

while IFS= read -r w; do
  [[ -n "$w" ]] || continue
  disk_wf_set["$w"]=1
done <<<"$disk_workflows"

errors=0
report() {
  echo "$1" >&2
  errors=$((errors + 1))
}

while IFS="$TAB" read -r kind a b c; do
  [[ -n "$kind" ]] || continue
  case "$kind" in
    ERR)
      parse_errors+="$a"$'\n'
      ;;
    WF_TASK)
      wf_placed["$a"]=1
      wf_refs["$a"]="${wf_refs[$a]:-${b}}"
      if [[ -n "${wf_task_lines[$a]:-}" ]]; then
        report "DUPLICATE WORKFLOW: '$a' is listed in Task cells at lines ${wf_task_lines[$a]} and $b of $MAP"
      fi
      wf_task_lines["$a"]="${wf_task_lines[$a]:+${wf_task_lines[$a]}, }$b"
      ;;
    WF_STEP)
      wf_placed["$a"]=1
      wf_refs["$a"]="${wf_refs[$a]:-${b}}"
      key="${a}${TAB}${c}"
      if [[ -n "${wf_step_rows[$key]:-}" ]]; then
        report "DUPLICATE WORKFLOW ROW: '$a' task '$c' is listed at lines ${wf_step_rows[$key]} and $b of $MAP"
      else
        wf_step_rows["$key"]="$b"
      fi
      ;;
    WF_REF)
      wf_refs["$a"]="${wf_refs[$a]:-${b}}"
      ;;
    PLUGIN)
      plugin_counts["$a"]=$((${plugin_counts[$a]:-0} + 1))
      plugin_lines["$a"]="${plugin_lines[$a]:+${plugin_lines[$a]}, }line $b (On the map)"
      ;;
    PLUGIN_NOT_AUTO)
      plugin_counts["$a"]=$((${plugin_counts[$a]:-0} + 1))
      plugin_lines["$a"]="${plugin_lines[$a]:+${plugin_lines[$a]}, }line $b (Not an automated task)"
      ;;
    *) ;;
  esac
done <<<"$parsed"

if [[ -n "$parse_errors" ]]; then
  echo "check-lifecycle-map: $MAP is missing required structure:" >&2
  while IFS= read -r msg; do
    [[ -n "$msg" ]] || continue
    echo "  $msg" >&2
  done <<<"$parse_errors"
  exit 2
fi

while IFS= read -r w; do
  [[ -n "$w" ]] || continue
  if [[ -z "${wf_placed[$w]:-}" ]]; then
    report "MISSING WORKFLOW: '$w' exists in $WORKFLOWS_DIR but is not placed in any task row of $MAP"
  fi
done < <(printf '%s' "$disk_workflows" | LC_ALL=C sort)

for w in $(printf '%s\n' "${!wf_refs[@]}" | LC_ALL=C sort); do
  [[ -n "$w" ]] || continue
  if [[ -z "${disk_wf_set[$w]:-}" ]]; then
    report "STALE WORKFLOW: '$w' is referenced in $MAP (line ${wf_refs[$w]}) but does not exist in $WORKFLOWS_DIR"
  fi
done

while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  cnt="${plugin_counts[$p]:-0}"
  if ((cnt == 0)); then
    report "MISSING PLUGIN: '$p' is in $MARKETPLACE but is not listed under ## Plugins in $MAP"
  elif ((cnt > 1)); then
    report "DUPLICATE PLUGIN: '$p' is listed $cnt times under ## Plugins in $MAP (${plugin_lines[$p]})"
  fi
done < <(printf '%s\n' "$mp_plugins" | LC_ALL=C sort -u)

for p in $(printf '%s\n' "${!plugin_counts[@]}" | LC_ALL=C sort); do
  [[ -n "$p" ]] || continue
  if [[ -z "${mp_set[$p]:-}" ]]; then
    report "STALE PLUGIN: '$p' is listed under ## Plugins in $MAP (${plugin_lines[$p]}) but is not in $MARKETPLACE"
  fi
done

if ((errors > 0)); then
  echo "check-lifecycle-map: $errors parity defect(s) in $MAP" >&2
  exit 1
fi

wf_count="$(printf '%s' "$disk_workflows" | grep -c . || true)"
mp_count="$(printf '%s\n' "$mp_plugins" | LC_ALL=C sort -u | grep -c . || true)"
echo "check-lifecycle-map: $MAP matches all $wf_count workflow(s) and all $mp_count plugin(s)"
exit 0
