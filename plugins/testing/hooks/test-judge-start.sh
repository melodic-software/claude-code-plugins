#!/usr/bin/env bash
# SessionStart hook: the task-end test judge's catch-up. It names, once, the
# ledger verdicts of this project's sessions whose last write is over an hour
# old and that were never relayed (the session ended mid-task), as a
# systemMessage with the findings file, then marks them relayed. A session
# active within the hour is left to the Stop hook of its /clear or fork
# successor, which this hook marks: source `clear` or `fork` writes
# successors/<pkey>/<session_id> holding the start time. Exits 0 on every path.
#
# Opt-in: hooks.json starts it through exec-bash.mjs --require-true
# TEST_GUARDS_ENABLED --require-true TEST_JUDGE_ENABLED. See judge-lib.sh.

set -uo pipefail
trap 'exit 0' EXIT

[[ "${TEST_JUDGE_ACTIVE:-}" == 1 ]] && exit 0
[[ "${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_ENABLED:-false}" == "true" ]] || exit 0
[[ "${CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED:-false}" == "true" ]] || exit 0

INPUT=""
IFS= read -r -d '' -t "${CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT:-2}" INPUT
IFS=$'\t' read -r SID TPATH pcwd src < <(jq -r '[.session_id, .transcript_path, (.cwd // ""), (.source // "")]
  | map(. // "" | tostring) | @tsv' <<<"$INPUT" 2>/dev/null)
[[ "${SID:-}" =~ ^[A-Za-z0-9_-]+$ && -n "${TPATH:-}" ]] || exit 0

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=scanner-run.sh
source "$HOOK_DIR/scanner-run.sh"
testing::data_dir
testing::pkey "${CLAUDE_PROJECT_DIR:-$pcwd}" "$TPATH" || exit 0
if [[ "$src" == clear || "$src" == fork ]]; then
  mkdir -p "$DATA/successors/$PKEY" && printf '%s\n' "${EPOCHSECONDS:-$(date +%s)}" >"$DATA/successors/$PKEY/$SID"
fi
[[ -d "$DATA/verdicts/$PKEY" ]] || exit 0
# shellcheck source=judge-lib.sh
source "$HOOK_DIR/judge-lib.sh"
exec 3>&1 >/dev/null 2>>"$JUDGE_LOG"

judge::now
relay="" marks=()
for d in "$DATA/verdicts/$PKEY"/*/; do
  s="${d%/}" && s="${s##*/}"
  [[ -d "$d" && "$s" != "$SID" ]] || continue
  last="$(judge::last_write "$s")" || continue
  ((NOW - last > 3600)) || continue
  for v in "$d"*.json; do
    [[ -f "$v" ]] || continue
    kh="${v##*/}" && kh="${kh%.json}"
    [[ -e "$DATA/relayed/$PKEY/$s/$kh" ]] && continue
    relay+="$(judge::validate "$v")"$'\n'
    marks+=("$s/$kh")
  done
done
[[ -n "$relay" ]] || exit 0

judge::findings "$relay"
for m in "${marks[@]}"; do
  mkdir -p "$DATA/relayed/$PKEY/${m%/*}" && : >"$DATA/relayed/$PKEY/$m"
done
jq -cn --arg m "test judge: an earlier session ended before these verdicts were shown: $(judge::counts "$relay"). Findings: $FINDINGS" \
  '{systemMessage: $m}' >&3
