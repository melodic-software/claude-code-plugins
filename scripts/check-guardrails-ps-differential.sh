#!/usr/bin/env bash
set -uo pipefail

PROG=check-guardrails-ps-differential

for _tool in jq git tar; do
  if ! command -v "$_tool" >/dev/null 2>&1; then
    echo "$PROG: $_tool is required" >&2
    exit 2
  fi
done
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
  echo "$PROG: bash 4.3 or newer is required (wait -n)" >&2
  exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/gate-entry.sh
. "$SCRIPT_DIR/lib/gate-entry.sh" || exit 2
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "$PROG: not inside a git work tree" >&2
  exit 2
fi
TOP="$(git rev-parse --show-toplevel)" || exit 2
cd "$TOP" || exit 2

usage() {
  echo "usage: $PROG [--corpus <file>] [--jobs <n>] <base-ref> | --harvest" >&2
  exit 2
}

CORPUS="$SCRIPT_DIR/guardrails-ps-differential-corpus.jsonl"
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || JOBS=2
BASE_REF=""
HARVEST=0
while (($#)); do
  case "$1" in
  --corpus)
    [[ -n "${2-}" ]] || usage
    CORPUS=$2
    shift 2
    ;;
  --jobs)
    [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || usage
    JOBS=$2
    shift 2
    ;;
  --harvest)
    HARVEST=1
    shift
    ;;
  -*) usage ;;
  *)
    [[ -z "$BASE_REF" ]] || usage
    BASE_REF=$1
    shift
    ;;
  esac
done
if ((HARVEST)); then
  [[ -z "$BASE_REF" ]] || usage
else
  [[ -n "$BASE_REF" ]] || usage
fi

BRANCH_ROOT="$TOP/plugins/guardrails"
if [[ ! -f "$BRANCH_ROOT/lib/powershell/ps-command.sh" ]]; then
  echo "$PROG: $BRANCH_ROOT/lib/powershell/ps-command.sh not found" >&2
  exit 2
fi

CONSUMERS=(block-dangerous-git block-no-verify block-convention-violation block-noncanonical-commit block-root-delete-target)
TOKENS=(dynamic-invocation launcher special-construct herestring-unbalanced herestring-subexpr)

while IFS= read -r _v; do
  case "$_v" in
  CLAUDE_PLUGIN_OPTION_* | HOOK_TELEMETRY_SINK | CLAUDE_PLUGIN_ROOT | CLAUDE_PROJECT_DIR) unset "$_v" ;;
  *) ;;
  esac
done < <(compgen -e)

WORK="$(mktemp -d "${TMPDIR:-/tmp}/$PROG.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
NEUTRAL="$WORK/cwd"
mkdir -p "$NEUTRAL" "$WORK/data" "$WORK/payload" "$WORK/res" || exit 2

TIMEOUT=()
command -v timeout >/dev/null 2>&1 && TIMEOUT=(timeout 120)

if ((HARVEST)); then
  mkdir -p "$WORK/harvest/plugins" || exit 2
  cp -R "$BRANCH_ROOT" "$WORK/harvest/plugins/" || exit 2
  hu="$WORK/harvest/plugins/guardrails/hooks/hook-utils.sh"
  # shellcheck disable=SC2016  # the anchor is source text, matched literally
  anchor='  printf -v "$__hu_dest" '"'%s'"' "$__hu_input"'
  if [[ "$(grep -cxF -- "$anchor" "$hu")" != 1 ]]; then
    echo "$PROG: --harvest: the payload anchor in hook-utils.sh moved; update it here" >&2
    exit 2
  fi
  # shellcheck disable=SC2016  # written into the copy verbatim
  record='  [[ -n "${PS_DIFF_HARVEST_LOG:-}" ]] && printf '"'\\036%s\\n'"' "$__hu_input" >>"$PS_DIFF_HARVEST_LOG"'
  PS_DIFF_ANCHOR=$anchor PS_DIFF_RECORD=$record \
    awk '$0 == ENVIRON["PS_DIFF_ANCHOR"] { print ENVIRON["PS_DIFF_RECORD"] } { print }' "$hu" >"$hu.new" &&
    mv "$hu.new" "$hu" || exit 2
  pids=()
  for suite in "${CONSUMERS[@]}" flag-commit-pr-skill-bypass block-windows-drive-tmp block-exported-msys-pathconv run-guards; do
    PS_DIFF_HARVEST_LOG="$WORK/harvest-$suite.seq" \
      bash "$WORK/harvest/plugins/guardrails/hooks/$suite.test.sh" >/dev/null 2>&1 &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
  cat "$WORK"/harvest-*.seq 2>/dev/null |
    jq --seq -c 'select(type == "object" and .tool_name == "PowerShell") | .tool_input.command | strings' 2>/dev/null |
    tr -d '\036' | LC_ALL=C sort -u
  exit 0
fi

gate_entry::require_base "$BASE_REF" "$PROG: base ref not resolvable: $BASE_REF"
mkdir -p "$WORK/base" || exit 2
if ! git archive --format=tar "$BASE_REF" plugins/guardrails | tar -xf - -C "$WORK/base"; then
  echo "$PROG: could not extract plugins/guardrails from $BASE_REF" >&2
  exit 2
fi
BASE_ROOT="$WORK/base/plugins/guardrails"

for t in "${TOKENS[@]}"; do
  if ! grep -qF -- "ps-unparsable-$t" "$BASE_ROOT/lib/powershell/ps-command.sh"; then
    echo "$PROG: the base classifier no longer names allow token ps-unparsable-$t; update TOKENS here" >&2
    exit 2
  fi
done

row_args_of() {
  local cmd
  cmd=$(jq -r '
    .hooks.PreToolUse[]
    | select(.matcher == "Bash|PowerShell")
    | .hooks[]
    | ((.args // []) | map(tostring) | join(" ")) as $args
    | if ($args | contains("run-guards.sh")) then
        $args
      elif (.command | tostring | contains("run-guards.sh")) then
        .command
      else
        empty
      end
  ' "$1/hooks/hooks.json" 2>/dev/null) || return 1
  [[ -n "$cmd" && "$cmd" != *$'\n'* ]] || return 1
  printf '%s' "${cmd#*run-guards.sh }"
}
BASE_ROW=$(row_args_of "$BASE_ROOT") || {
  echo "$PROG: no Bash|PowerShell run-guards.sh row in the base hooks.json" >&2
  exit 2
}
BRANCH_ROW=$(row_args_of "$BRANCH_ROOT") || {
  echo "$PROG: no Bash|PowerShell run-guards.sh row in the branch hooks.json" >&2
  exit 2
}

if [[ ! -f "$CORPUS" ]]; then
  echo "$PROG: corpus not found: $CORPUS" >&2
  exit 2
fi
if ! jq -R -c --arg cwd "$NEUTRAL" '
    select(test("^\\s*(#|$)") | not) # portability-ok: jq regex class, not a GNU grep word boundary
    | fromjson
    | if type == "string" then . else error("corpus line is not a JSON string") end
    | {hook_event_name: "PreToolUse", tool_name: "PowerShell", tool_input: {command: .}, cwd: $cwd}' \
  "$CORPUS" >"$WORK/payloads.jsonl"; then
  echo "$PROG: corpus is not one JSON string per line: $CORPUS" >&2
  exit 2
fi
N=0
while IFS= read -r line; do
  printf '%s\n' "$line" >"$WORK/payload/$N.json"
  N=$((N + 1))
done <"$WORK/payloads.jsonl"
if ((N == 0)); then
  echo "$PROG: corpus holds no command: $CORPUS" >&2
  exit 2
fi

mask_tokens() {
  local m=$1 i out=""
  for i in "${!TOKENS[@]}"; do
    ((m & (1 << i))) && out+="${out:+,}ps-unparsable-${TOKENS[i]}"
  done
  printf '%s' "$out"
}

run_cell() {
  local tree=$1 target=$2 idx=$3 mask=$4 root row rc=0 allow
  local -a argv env_add=()
  if [[ "$tree" == base ]]; then
    root=$BASE_ROOT row=$BASE_ROW
  else
    root=$BRANCH_ROOT row=$BRANCH_ROW
  fi
  if [[ "$target" == row ]]; then
    read -r -a argv <<<"$row"
    argv=(bash "$root/hooks/run-guards.sh" "${argv[@]}")
  else
    argv=(bash "$root/hooks/$target.sh")
  fi
  allow=$(mask_tokens "$mask")
  [[ -n "$allow" ]] && env_add=("CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=$allow")
  (
    cd "$NEUTRAL" || exit 2
    env ${env_add[@]+"${env_add[@]}"} CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PLUGIN_DATA="$WORK/data/$tree" \
      CLAUDE_PROJECT_DIR="$NEUTRAL" ${TIMEOUT[@]+"${TIMEOUT[@]}"} "${argv[@]}" \
      <"$WORK/payload/$idx.json" >/dev/null 2>&1
  ) || rc=$?
  printf '%s' "$rc" >"$WORK/res/${tree}_${target}_${idx}_${mask}"
}

run_cells() {
  local n=0 tree target idx mask
  while read -r tree target idx mask; do
    run_cell "$tree" "$target" "$idx" "$mask" &
    n=$((n + 1))
    if ((n >= JOBS)); then
      wait -n
      n=$((n - 1))
    fi
  done <"$1"
  wait
}

result() {
  local f="$WORK/res/${1}_${2}_${3}_${4}"
  if [[ -f "$f" ]]; then cat "$f"; else printf 'missing'; fi
}

: >"$WORK/cells1"
for ((i = 0; i < N; i++)); do
  for target in "${CONSUMERS[@]}" row; do
    printf '%s %s %d 0\n' base "$target" "$i" branch "$target" "$i" >>"$WORK/cells1"
  done
done
run_cells "$WORK/cells1"

NMASK=$(((1 << ${#TOKENS[@]}) - 1))
REFUSED=()
for ((i = 0; i < N; i++)); do
  [[ "$(result base block-dangerous-git "$i" 0)" == 2 ]] && REFUSED+=("$i")
done
: >"$WORK/cells2"
for i in ${REFUSED[@]+"${REFUSED[@]}"}; do
  for ((m = 1; m <= NMASK; m++)); do
    printf '%s %s %d %d\n' base block-dangerous-git "$i" "$m" branch block-dangerous-git "$i" "$m" >>"$WORK/cells2"
  done
done
run_cells "$WORK/cells2"

command_of() { jq -r '.tool_input.command' "$WORK/payload/$1.json"; }

declare -A T_CELLS=() T_BASE2=() T_BRANCH2=() T_LOST=() T_GAINED=()
LOST=0
report_cell() {
  local label=$1 b r tokens
  b=$(result base "$2" "$3" "$4")
  r=$(result branch "$2" "$3" "$4")
  T_CELLS[$label]=$((${T_CELLS[$label]:-0} + 1))
  [[ "$b" == 2 ]] && T_BASE2[$label]=$((${T_BASE2[$label]:-0} + 1))
  [[ "$r" == 2 ]] && T_BRANCH2[$label]=$((${T_BRANCH2[$label]:-0} + 1))
  tokens=$(mask_tokens "$4")
  if [[ "$b" == 2 && "$r" != 2 ]]; then
    T_LOST[$label]=$((${T_LOST[$label]:-0} + 1))
    LOST=$((LOST + 1))
    printf '%s: %s%s: base exits 2, branch exits %s: %q\n' \
      "$PROG" "$2" "${tokens:+ with $tokens}" "$r" "$(command_of "$3")" >&2
  elif [[ "$r" == 2 && "$b" != 2 ]]; then
    T_GAINED[$label]=$((${T_GAINED[$label]:-0} + 1))
    printf 'new refusal: %s%s: base exits %s, branch exits 2: %q\n' \
      "$2" "${tokens:+ with $tokens}" "$b" "$(command_of "$3")"
  fi
}

LABELS=()
for target in "${CONSUMERS[@]}" row; do
  label=$target
  [[ "$target" == row ]] && label="run-guards.sh (Bash row)"
  LABELS+=("$label")
  for ((i = 0; i < N; i++)); do report_cell "$label" "$target" "$i" 0; done
done
label="block-dangerous-git, $NMASK token subsets"
LABELS+=("$label")
for i in ${REFUSED[@]+"${REFUSED[@]}"}; do
  for ((m = 1; m <= NMASK; m++)); do report_cell "$label" block-dangerous-git "$i" "$m"; done
done

printf '\n| cells | count | base exits 2 | branch exits 2 | base 2, branch not | branch 2, base not |\n'
printf '|---|---|---|---|---|---|\n'
for label in "${LABELS[@]}"; do
  printf '| %s | %d | %d | %d | %d | %d |\n' "$label" "${T_CELLS[$label]:-0}" "${T_BASE2[$label]:-0}" \
    "${T_BRANCH2[$label]:-0}" "${T_LOST[$label]:-0}" "${T_GAINED[$label]:-0}"
done
printf '\n'

if ((LOST)); then
  echo "$PROG: $LOST cell(s) where $BASE_REF refuses a PowerShell command and the working tree does not" >&2
  exit 1
fi
echo "$PROG: $N commands against $BASE_REF: the working tree refuses every PowerShell command $BASE_REF refuses"
exit 0
