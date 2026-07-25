#!/usr/bin/env bash
# guardrails-commit-msg-convention v1
# Installed into <repo>/.git/hooks/commit-msg by /guardrails:setup apply
# install-commit-msg (personal lane). Safe to remove: delete this file (and
# guardrails-resolve-convention.sh beside it); nothing else references them.
#
# WHAT THIS IS — the tool-agnostic DEPTH layer of commit-convention
# enforcement: unlike the Claude-Code-layer gates (which see only tool calls),
# a git commit-msg hook validates EVERY commit on this machine in this repo —
# editor commits, `git commit -F <file>`, IDE integrations, humans outside
# Claude. It enforces the same team-tracked pattern the CC-layer gate reads,
# through a copy of the same resolver (single parse contract, no drift).
#
# SENTINEL: the "guardrails-commit-msg-convention" marker above is load-bearing.
# Convention-INFERENCE tooling (e.g. /source-control:setup) must not read this
# hook as an independent convention signal — it is derived FROM the tracked
# config, and counting it would create an echo cycle. Tools detect the marker
# and skip this file.
#
# UNRESOLVED = NO ENFORCEMENT: no team-tracked `subject_pattern` (or a
# non-POSIX-ERE one) -> exit 0. Enforcement strength equals the strength of
# explicit team config; this hook never imposes a default.
#
# NO BYPASS ADVICE BY DESIGN: the failure message says how to FIX the subject,
# never to pass --no-verify — in Claude Code sessions the guardrails
# block-no-verify guard refuses --no-verify anyway, and suggesting it would
# wedge an agent between two guards (the designed exit is a compliant subject).
#
# CHAINING: if a pre-existing commit-msg hook was present at install time, the
# installer renamed it to commit-msg.pre-guardrails and this hook runs it FIRST
# (its verdict stands — a rejection there rejects the commit), then applies the
# convention check. Removing this hook: restore commit-msg.pre-guardrails back
# to commit-msg.

set -uo pipefail

MSG_FILE="${1:?commit-msg hook invoked without a message file}"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Chain a pre-existing hook first; its rejection is final.
if [[ -x "$HOOK_DIR/commit-msg.pre-guardrails" ]]; then
  "$HOOK_DIR/commit-msg.pre-guardrails" "$@" || exit $?
elif [[ -f "$HOOK_DIR/commit-msg.pre-guardrails" ]]; then
  bash "$HOOK_DIR/commit-msg.pre-guardrails" "$@" || exit $?
fi

# Repo root: commit-msg hooks run with cwd at the repo top level, but resolve
# explicitly so a hooks-dir invocation from elsewhere still reads the right
# config.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
RESOLVER="$HOOK_DIR/guardrails-resolve-convention.sh"
[[ -f "$RESOLVER" ]] || exit 0 # resolver removed -> no enforcement, never block blind

SUBJECT_ERE="$(bash "$RESOLVER" "$REPO_ROOT" subject_pattern 2>/dev/null)" || SUBJECT_ERE=""
[[ -n "$SUBJECT_ERE" ]] || exit 0

# First non-comment, non-empty line = the subject. Comment char per git config
# (core.commentChar, default '#'); 'auto' cannot be pre-known, treat as '#'.
comment_char="$(git config --get core.commentChar 2>/dev/null || true)"
[[ -n "$comment_char" && "$comment_char" != "auto" ]] || comment_char="#"

subject=""
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ -n "$line" ]] || continue
  [[ "${line:0:1}" == "$comment_char" ]] && continue
  subject="$line"
  break
done <"$MSG_FILE"

# Empty message: git aborts the commit itself; nothing to validate.
[[ -n "$subject" ]] || exit 0

# Fixup/squash autosquash subjects derive from an existing commit and are
# consumed by rebase --autosquash; validating the prefix form would block the
# documented workflow the CC-layer gate also exempts.
case "$subject" in
"fixup! "* | "squash! "* | "amend! "*) exit 0 ;;
*) ;; # an ordinary subject falls through to validation
esac

if ! printf '%s\n' "$subject" | grep -Eq -- "$SUBJECT_ERE"; then
  {
    echo "commit-msg (guardrails): subject violates the team convention."
    echo "  subject: $subject"
    echo "  pattern: $SUBJECT_ERE   (from .claude/source-control.md, team layer)"
    echo "Rewrite the subject to match the pattern and commit again."
    echo "(Convention home: .claude/source-control.md — change it there via PR if the"
    echo "pattern itself is wrong. This hook enforces only what the team tracked.)"
  } >&2
  exit 1
fi

exit 0
