#!/usr/bin/env bash
# PostToolUse hook (async): judge the test blocks a write created or changed,
# soon after the write, so the task-end Stop hook mostly finds verdicts ready.
#
# It waits TEST_JUDGE_DEBOUNCE seconds (default 20), exits if the file changed
# meanwhile (the newer write's job owns it), then judges every in-doubt block
# of the file that has no verdict, in one run, under the key locks and one of
# the machine's judge slots, and writes the verdicts to the ledger. It never
# prints: nothing reaches the session mid-task. See judge-lib.sh for the state.
#
# test-judge.sh also starts it, detached with no debounce and
# TEST_JUDGE_HANDOFF=1, for the keys past its per-Stop cap; the Stop hook
# writes the pending marker for it.
#
# Opt-in: hooks.json starts it through exec-bash.mjs --require-true
# TEST_GUARDS_ENABLED --require-true TEST_JUDGE_ENABLED on test-scan's `if`
# rows; the checks below keep a direct run honest.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_ENABLED:-false}" == "true" ]] || exit 0
[[ "${CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED:-false}" == "true" ]] || exit 0
[[ "${TEST_JUDGE_ACTIVE:-}" == 1 ]] && exit 0

INPUT=""
IFS= read -r -d '' -t "${CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT:-2}" INPUT
exec >/dev/null 2>&1

IFS=$'\t' read -r SID call TPATH pcwd file < <(jq -r '[.session_id, .tool_use_id, .transcript_path,
  (.cwd // ""), .tool_input.file_path] | map(. // "" | tostring) | @tsv' <<<"$INPUT" 2>/dev/null)
[[ "${SID:-}" =~ ^[A-Za-z0-9_-]+$ && "${call:-}" =~ ^[A-Za-z0-9_-]+$ && -n "${TPATH:-}" && -n "${file:-}" ]] || exit 0

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=scanner-run.sh
source "$HOOK_DIR/scanner-run.sh"
testing::data_dir
testing::pkey "${CLAUDE_PROJECT_DIR:-$pcwd}" "$TPATH" || exit 0
# shellcheck source=judge-lib.sh
source "$HOOK_DIR/judge-lib.sh"

# Two `if` rows can match one path and each starts this job; one runs.
mkdir -p "$DATA/marks" "$DATA/pending/$PKEY/$SID"
[[ -n "${TEST_JUDGE_HANDOFF:-}" ]] || (set -o noclobber && : >"$DATA/marks/judge-$SID-$call") 2>/dev/null || exit 0

HELD=()
pend="$DATA/pending/$PKEY/$SID/$call"
judge::now
printf '%s %s %s\n%s\n' "$$" "$JUDGE_HOST" "$NOW" "$file" >"$pend"
trap 'rm -f "$pend" ${HELD[@]+"${HELD[@]}"}' EXIT

h0="$(judge::sha "$file" 2>/dev/null)"
sleep "${TEST_JUDGE_DEBOUNCE:-20}"
[[ "$(judge::sha "$file" 2>/dev/null)" == "$h0" ]] || exit 0

own="$DATA/sessions/$PKEY/$SID/$call.json"
[[ -f "$own" ]] && file="$(jq -r '.file // empty' "$own" 2>/dev/null)"
[[ -f "$file" ]] || exit 0
judge::session_set
judge::load
info=""
for i in ${INFOS[@]+"${INFOS[@]}"}; do
  [[ "$(jq -r .file <<<"$i")" == "$file" ]] && info="$i"
done
# No record for this write: test-scan skipped it (a gitignored or excluded
# path) or has not written yet. Judge the whole file unless it is ignored; a
# path the scanner excludes lists no block.
if [[ ! -f "$own" && -z "${TEST_JUDGE_HANDOFF:-}" ]]; then
  git -C "${file%/*}" check-ignore -q "$file" 2>/dev/null && exit 0
  info="$(jq -cn --arg f "$file" --arg r "$(git -C "${file%/*}" rev-parse --show-toplevel 2>/dev/null)" --arg s "$SID" \
    --argjson i "${info:-null}" '{file: $f, repo: (if $r == "" then null else $r end), names: [], base_ok: 0, lines: [],
      writers: [{sid: $s, agent: ""}], owner: $s} + ($i // {}) + {whole: true}')"
fi
[[ -n "$info" ]] || exit 0

judge::derive "$info"
keys=""
while read -r kh rest; do
  [[ -n "$kh" ]] || continue
  judge::verdict "$kh" && continue
  (($(judge::attempts "$kh") < 2)) || continue
  # A write-time job leaves a held key to its holder. A job the Stop hook
  # handed a late key waits for the Stop's own dying run to let go of it.
  if ! judge::lock "$kh"; then
    [[ -n "${TEST_JUDGE_HANDOFF:-}" ]] || continue
    judge::wait_lock "$kh" || continue
    judge::lock "$kh" || continue
  fi
  HELD+=("$DATA/locks/$kh")
  # Another holder may have finished, or failed, between the check and the lock.
  judge::verdict "$kh" && continue
  (($(judge::attempts "$kh") < 2)) || continue
  keys+="$kh $rest"$'\n'
done <<<"$KEYS"
[[ -n "$keys" ]] && judge::runs_left || exit 0

judge::now
judge::slot $((NOW + JUDGE_STALE)) || exit 0
HELD+=("$SLOT")
judge::run "$info" "$keys" "$JUDGE_RUN_TIMEOUT" "$HINT"
