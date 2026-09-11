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

# Every arm exits through hook::finish: telemetry first, then the one JSON
# document. `--id` because the telemetry hook id is the script's name, not the
# `actionlint` label the skip notices carry. This hook never rewrites the file
# and never sources the rewrite guard, so no verdict is passed and the builder
# leaves the `changed` key off rather than guessing one.
#
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
  if hook::notice_once "actionlint-missing" "$INPUT"; then
    AL_NOTICE=""
    hook::tool_missing_notice_to AL_NOTICE \
      "actionlint: 'actionlint' was not found on this hook's PATH — workflow lint skipped for this edit" \
      matching ". Install: https://github.com/rhysd/actionlint/blob/main/docs/install.md"
    hook::emit_skip_notice PostToolUse "$AL_NOTICE"
  fi
  hook::finish --id actionlint-check skipped findings array '[]'
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
  hook::finish --id actionlint-check error findings array '[]'
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
  # The raw encode, not hook::findings_to's per-line one: a lint that did not
  # run leaves a diagnostic whose blank lines are part of the shape a sink is
  # meant to read back, so this branch keeps actionlint's stdout+stderr
  # verbatim. There is no agent-channel report on this arm.
  FINDINGS_JSON='[]'
  hook::findings_encode_to FINDINGS_JSON "$AL_OUTPUT"
  hook::finish --id actionlint-check error findings array "$FINDINGS_JSON"
fi

FINDINGS_JSON='[]'
AL_CTX=""
if [[ -n "$AL_OUTPUT" ]]; then
  hook::findings_to AL_CTX "actionlint: $FILE_BASE has findings:" \
    "$AL_OUTPUT" FINDINGS_JSON
fi

hook::finish --id actionlint-check --context "$AL_CTX" ok findings array "$FINDINGS_JSON"
