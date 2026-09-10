#!/usr/bin/env bash
# PostToolUse hook: lint GitHub Actions workflow files via actionlint.
# Triggered on Write|Edit of .github/workflows/*.yml and *.yaml files.
#
# ADVISORY: always exits 0. actionlint findings surface via additionalContext
# but never block the edit. Make a commit hook or CI your hard gate.
#
# Graceful degrade: when actionlint (or jq) is not on PATH the hook skips
# (exit 0) with a visible once-per-session notice on both the agent and user
# channels — the plugin ships no binary of its own.

set -uo pipefail

# Kill switch FIRST, before any library is sourced: a disabled hook must not
# pay to parse hook-utils.sh to learn it is off. Same predicate as
# hook::is_enabled; scripts/check-killswitch-hoist.sh pins the two together.
[[ "${CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED:-true}" == "true" ]] || exit 0
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

# Emit this run's telemetry envelope: $1 status, $2 findings JSON array.
# Two guards: the high-res start stamp (empty on bash before 5.0, where
# telemetry is skipped so the hook still lints rather than aborting) and the
# sink opt-in. The data payload costs a jq subprocess, so it is built here
# after both guards — never on the unwired path. This hook never rewrites the
# file, so HOOK_REWRITE_CHANGED is never set and the builder leaves the
# `changed` key off rather than guessing a verdict.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data=""
  hook::data_json_to data "$TOOL" "$FILE_REL" "${HOOK_REWRITE_CHANGED:-}" findings array "$2"
  hook::emit_telemetry "actionlint-check" "PostToolUse" "$1" "$start" "$data" "$REPO_ROOT"
}

# The whole prologue: the start stamp, the buffered payload, the workflow-file
# filter (applied before the jq gate on the raw payload text, so a non-workflow
# edit never triggers the jq notice, and again on the parsed path), the jq
# gate, the parsed path with its basename and directory, the file-anchored repo
# root, and the telemetry-only TOOL behind the sink opt-in. Exits 0 itself on
# every path this hook has nothing to do on.
#
# --no-membership because hook::read_file_path's CLAUDE_PROJECT_DIR guard is
# wrong for an advisory PostToolUse linter: PostToolUse cannot block or undo
# the write, so the guard protects nothing and every false negative is a silent
# coverage loss. The concrete one: GNU realpath under Git Bash does not expand
# Windows 8.3 short names, so a short-form file_path (<drive>:\...\SOMEDIR~1\...)
# fails the prefix match against a long-form project dir and the lint silently
# never runs. The workflow-location globs are what bound this hook's scope.
#
# --relative because FILE_REL is also the argument actionlint runs on from the
# repo root, not just the schema-required data.file. A path the prefix strip
# could not make relative degrades to its basename, which is right for
# telemetry but names a DIFFERENT file against the repo root, so the invocation
# below reads FILE_REL_DEGRADED to know which of the two it holds.
hook::begin --no-membership --relative actionlint PostToolUse \
  '*/.github/workflows/*.yml' '*/.github/workflows/*.yaml'

# Graceful degrade: actionlint absent -> skip, made VISIBLE once per session on
# both channels (agent + user). Telemetry (opt-in) also records a "skipped"
# status so a consumer sink can observe the coverage gap.
if ! command -v actionlint >/dev/null 2>&1; then
  emit_tel "skipped" '[]'
  if hook::notice_once "actionlint-missing" "$INPUT"; then
    hook::emit_skip_notice PostToolUse "actionlint: 'actionlint' was not found on this hook's PATH — workflow lint skipped for this edit (probe re-runs on every matching edit; only this notice latches once per session — there is no skip latch). Hook processes inherit Claude Code's own environment, not the interactive shell's profile, so a version-manager install the Bash tool can see may be invisible here. Install: https://github.com/rhysd/actionlint/blob/main/docs/install.md
PATH probed: ${PATH:-<unset>}"
  fi
  exit 0
fi

# -shellcheck= and -pyflakes= disable actionlint's external run-block linters
# (embedded-bash ShellCheck, `shell: python` pyflakes). Both spawn a subprocess
# per `run:` block — ShellCheck deadlocks on large blocks under the Windows
# subprocess IPC path in actionlint 1.7.x, and either adds latency unsuited to
# an edit-time advisory hook. Native workflow diagnostics (the value of this
# hook) are unaffected; deep run-block linting belongs in a commit hook or CI.
# A failed cd (repo root vanished, permission) must never read as a clean
# pass: without this branch an empty AL_OUTPUT would fall through to the
# clean-workflow telemetry (status ok, findings []), indistinguishable from a
# real pass. Changing this process's cwd is safe -- the hook exits below.
if ! cd "$REPO_ROOT" 2>/dev/null; then
  emit_tel "error" '[]'
  exit 0
fi
# The lint target is the repo-relative path so diagnostics echo it, but only
# when it IS repo-relative. A degraded FILE_REL is a bare basename redacted for
# telemetry; resolved against the repo root it names a different workflow or
# none, and this advisory hook would drop real findings silently. Fall back to
# the absolute path there.
AL_TARGET="$FILE_REL"
((FILE_REL_DEGRADED == 0)) || AL_TARGET="$FILE"
AL_OUTPUT=$(actionlint -shellcheck= -pyflakes= -- "$AL_TARGET" 2>&1)
AL_STATUS=$?

# actionlint exits 0 (clean) or 1 (problems found); anything else -- 2 invalid
# CLI, 3 fatal, 126/127 launch failure -- means the lint DID NOT run. Report it
# as an error (output captured as findings for the sink), never as clean.
if [[ "$AL_STATUS" -ge 2 ]]; then
  FINDINGS_JSON='[]'
  # FINDINGS_JSON feeds the telemetry envelope and nothing else, so the encode
  # sits behind the sink opt-in, the same rule TOOL above already follows.
  # Without the guard a run reaching this branch paid two jq spawns on the
  # unwired default path for a value emit_tel then discards (measured with
  # strace -f -e trace=execve: 5 jq execs per run, 3 with the guard).
  #
  # The two-process `jq -R . | jq -s .` shape stays. Folding it into one
  # `jq -R -s 'split("\n")...'` was tried and is wrong: slurp mode decodes the
  # whole stream as a single string, so a truncated UTF-8 lead byte sitting
  # immediately before a newline absorbs that newline into one U+FFFD and
  # merges two output lines into one array element. Line mode splits on the raw
  # byte first and keeps them apart. That matters most here: this branch
  # encodes actionlint's raw stdout+stderr, blank lines and all, with none of
  # the per-line filtering the findings branch below applies.
  if [[ -n "$AL_OUTPUT" ]] && hook::telemetry_enabled; then
    FINDINGS_JSON=$(printf '%s' "$AL_OUTPUT" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
  fi
  emit_tel "error" "$FINDINGS_JSON"
  exit 0
fi

FINDINGS_JSON='[]'
if [[ -n "$AL_OUTPUT" ]]; then
  hook::ctx_reset
  hook::ctx_append "actionlint: $FILE_BASE has findings:"
  findings_raw=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hook::ctx_append "  $line"
    findings_raw+="$line"$'\n'
  done <<<"$AL_OUTPUT"
  hook::ctx_flush PostToolUse

  # Behind the sink opt-in, and the two-process jq shape kept, for the reasons
  # recorded at the AL_STATUS >= 2 branch above.
  if [[ -n "$findings_raw" ]] && hook::telemetry_enabled; then
    FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
  fi
fi

emit_tel "ok" "$FINDINGS_JSON"
exit 0
