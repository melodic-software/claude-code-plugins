#!/usr/bin/env bash
# PostToolUse hook: normalize a written file's working-tree line endings to its
# .gitattributes `eol=` value (symmetric, git check-attr-driven).
# Triggered on Write|Edit of any file in the consuming repo.
#
# ADVISORY / NON-BLOCKING: always exits 0. The normalization is best-effort;
# the consuming repo's commit hook / CI (editorconfig, git renormalize) remains
# the authoritative gate.
#
# CROSS-PLATFORM: both arms (CRLF->LF and LF->CRLF) run on every OS — the hook
# compensates for tool writes that bypass git's checkout smudge, and such
# writes happen on any platform.
#
# Uses the consuming repo's own .gitattributes — it ships no policy of its own.

set -uo pipefail

# The hook's own directory is derived with parameter expansion rather than
# `dirname`, and resolved ONCE for all three sources. On the Windows Git Bash
# host this hook is tuned for, an exec costs about a spawn and a command
# substitution costs half of one, and this hook runs on every Write and Edit.
# `${BASH_SOURCE[0]%/*}` equals `dirname` for every shape BASH_SOURCE takes;
# the fallback covers the one shape it does not, a bare filename with no
# separator, where the strip is a no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# Kill switch FIRST, before any library is sourced: a disabled hook must not
# pay to parse hook-utils.sh to learn it is off. Same predicate as
# hook::is_enabled; scripts/check-killswitch-hoist.sh pins the two together.
[[ "${CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED:-true}" == "true" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=rewrite-guard.sh
source "$HOOK_DIR/rewrite-guard.sh"

# Emit this run's telemetry envelope: $1 status, $2 action taken.
# Two guards: the high-res start stamp (empty on bash before 5.0, where
# telemetry is skipped so the hook still normalizes rather than aborting) and
# the sink opt-in. The data payload costs a jq subprocess, so it is built here
# after both guards — never on the unwired path. This hook's matcher is every
# file write, so that is the hottest path in the fleet.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data=""
  hook::data_json_to data "$TOOL" "$FILE_REL" "${HOOK_REWRITE_CHANGED:-}" action str "$2"
  hook::emit_telemetry "eol-normalizer" "PostToolUse" "$1" "$start" "$data" "$REPO_ROOT"
}

# The bundled EOL library (normalize_eol_file).
# Sourced from the plugin's own hooks dir so it is self-contained on install.
# shellcheck source=normalize-eol.sh
source "$HOOK_DIR/normalize-eol.sh"

# The whole prologue: the start stamp, the buffered payload, the jq gate, the
# parsed path with its basename and directory, and the repo root that anchors
# `git check-attr` (file-anchored, so it is correct for clones, linked
# worktrees and bare-hub clones, and CWD-independent — the hook process CWD is
# not guaranteed to be the repo root). TOOL and FILE_REL follow behind the sink
# opt-in. Exits 0 itself on every path this hook has nothing to do on.
#
# No glob list: this hook's matcher IS its filter — every written file in the
# consuming repo carries line endings the repo's .gitattributes governs.
hook::begin eol-normalizer PostToolUse

# Content-mutation disclosure (#1596): line-ending normalization is a structural
# rewrite the user did not request; name what changed on the user channel and
# stay silent on skip/no-op paths. Snapshot lifecycle lives in the shared
# rewrite-guard lib (#3409); the taken message doubles as the changed/unchanged
# verdict EFFECTIVE_ACTION needs.
#
# The library's decision is taken FIRST, and the rewrite runs only when that
# decision says the file has work to do. That ordering is what lets the
# disclosure snapshot be skipped entirely on the overwhelmingly common path, an
# already-LF file in a repository whose .gitattributes says `eol=lf`, where the
# old code paid for a mktemp, a cp, a rewrite that changed no bytes, a cmp and an
# rm to conclude nothing had happened. When no rewrite is attempted the guard is
# never armed, so hook::rewrite_take_disclosure below finds no snapshot and
# yields an empty message, which is exactly what the byte-identical comparison
# yielded before.
#
# ACTION keeps its old meaning and its old value: it names the arm that APPLIES
# to this file, not whether bytes moved. An already-LF file under `eol=lf` still
# reports `lf`, and the emptiness of HOOK_REWRITE_MESSAGE is still the only thing
# that decides EFFECTIVE_ACTION and the telemetry status.
#
# ONE DELIBERATE DEVIATION, and it is not a content or message difference: a file
# that needs no rewrite is no longer opened for writing, so its mtime is no
# longer touched by this hook. Nothing this hook reports changes.
EOL_PLAN=$(normalize_eol_plan "$REPO_ROOT" "$FILE")
ACTION="${EOL_PLAN%% *}"
if [[ "${EOL_PLAN##* }" == 1 ]]; then
  hook::rewrite_guard_begin "$FILE"
  normalize_eol_apply "$ACTION" "$FILE"
fi
# `basename` is a builtin strip for the reason given at the source line above:
# this runs on every Write and Edit, and FILE names an existing regular file, so
# there is no trailing slash for basename to handle differently.
case "$ACTION" in
lf) EOL_MSG="eol-normalizer: normalized line endings to LF in ${FILE##*/}." ;;
crlf) EOL_MSG="eol-normalizer: normalized line endings to CRLF in ${FILE##*/}." ;;
*) EOL_MSG="" ;;
esac
hook::rewrite_take_disclosure "$FILE" "$EOL_MSG"
if [[ -n "$HOOK_REWRITE_MESSAGE" ]]; then
  EFFECTIVE_ACTION="$ACTION"
else
  EFFECTIVE_ACTION="skip"
fi

# status "ok" when the file was actually normalized (lf/crlf); "skipped" when the
# attr was unspecified, the path is -text, content sniffed binary, or idempotent.
case "$EFFECTIVE_ACTION" in
lf | crlf) status="ok" ;;
*) status="skipped" ;;
esac

emit_tel "$status" "$ACTION"

[[ -n "$HOOK_REWRITE_MESSAGE" ]] && hook::emit_system_message "$HOOK_REWRITE_MESSAGE"

exit 0
