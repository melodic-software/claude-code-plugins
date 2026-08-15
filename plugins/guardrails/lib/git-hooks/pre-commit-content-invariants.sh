#!/usr/bin/env bash
# guardrails-pre-commit-content-invariants v1
# Installed into <repo>/.git/hooks/pre-commit by /guardrails:setup apply
# install-pre-commit-content (personal lane). Safe to remove: delete this file
# and the guardrails-content-lib/ directory beside it; nothing else references
# them.
#
# WHAT THIS IS — the write-path-independent DEPTH layer for the content
# invariants the PreToolUse secret-pattern and hardcoded-path guards enforce
# on Write|Edit only. A Bash staged write (`jq … > /tmp/x && mv /tmp/x dest`)
# skips those tool-matched guards; this hook scans the staged blob at commit
# time so the damage class cannot ride any write path into history.
#
# SENTINEL: the "guardrails-pre-commit-content-invariants" marker above is
# load-bearing. Hook-manager / inference tooling must not treat this file as an
# independent policy signal — it is derived from the same pattern libs the
# CC-layer guards use.
#
# NO BYPASS ADVICE BY DESIGN: the failure message says how to FIX the content,
# never to pass --no-verify — in Claude Code sessions the guardrails
# block-no-verify guard refuses --no-verify anyway.
#
# CHAINING: if a pre-existing pre-commit hook was present at install time, the
# installer renamed it to pre-commit.pre-guardrails and this hook runs it FIRST
# (its verdict stands — a rejection there rejects the commit), then applies the
# content scan. Removing this hook: restore pre-commit.pre-guardrails back to
# pre-commit.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Chain a pre-existing hook first; its rejection is final.
if [[ -x "$HOOK_DIR/pre-commit.pre-guardrails" ]]; then
  "$HOOK_DIR/pre-commit.pre-guardrails" "$@" || exit $?
elif [[ -f "$HOOK_DIR/pre-commit.pre-guardrails" ]]; then
  bash "$HOOK_DIR/pre-commit.pre-guardrails" "$@" || exit $?
fi

# Lib resolution: installed copy lives in guardrails-content-lib/ beside this
# hook (secret-detection/ + path-detection/ trees). Contract tests and an
# in-tree invocation set GUARDRAILS_CONTENT_LIB_DIR to the plugin's lib/, or
# fall back to the parent of this file when that parent holds both trees.
LIB_DIR="${GUARDRAILS_CONTENT_LIB_DIR:-}"
if [[ -z "$LIB_DIR" ]]; then
  if [[ -d "$HOOK_DIR/guardrails-content-lib/secret-detection" ]]; then
    LIB_DIR="$HOOK_DIR/guardrails-content-lib"
  else
    LIB_DIR="$(cd "$HOOK_DIR/.." && pwd)"
  fi
fi

# shellcheck source=/dev/null
source "$LIB_DIR/secret-detection/secret-patterns.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/path-detection/hardcoded-path-patterns.sh"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

# Staged paths that still exist in the index (Added/Copied/Modified/Renamed).
mapfile -t STAGED < <(git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR -z |
  tr '\0' '\n' | sed '/^$/d')

[[ ${#STAGED[@]} -gt 0 ]] || exit 0

# Allowlist mirrors the PreToolUse secret-pattern / hardcoded-path exemptions
# that still make sense at commit time.
allowlisted() {
  local f="${1//\\//}"
  case "$f" in
  *.claude/hooks/* | *.lefthook/*) return 0 ;;
  *settings.local.json | *CLAUDE.local.md) return 0 ;;
  */.venv/* | .venv/* | */node_modules/* | node_modules/*) return 0 ;;
  *.env.example | *.env.sample | *.env.template) return 0 ;;
  *tests/fixtures/* | *tests/testdata/* | *Tests/fixtures/* | *Tests/testdata/*) return 0 ;;
  *.claude/skills/*/context/* | *.claude/skills/*/completed/*) return 0 ;;
  */lib/secret-detection/* | */lib/path-detection/*) return 0 ;;
  */guardrails-content-lib/*) return 0 ;;
  *) return 1 ;;
  esac
}

# Home-checkout suppression for the repo-path branch — same predicate as
# hardcoded-path-check.sh.
SCAN_ROOT=""
_toplevel="$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null)"
if [[ -n "$_toplevel" ]]; then
  _tl="${_toplevel//\\//}"
  _tl="${_tl%/}"
  _home="${HOME:-${USERPROFILE:-}}"
  _home="${_home//\\//}"
  _home="${_home%/}"
  if [[ -n "$_home" && ("$_tl" == "$_home" || "$_home" == "$_tl"/*) ]]; then
    SCAN_ROOT=""
  else
    SCAN_ROOT="$REPO_ROOT"
  fi
fi

is_git_binary() {
  local rel="$1"
  # Binary numstat lines are `-       -       <path>` (literal dashes, not zero).
  git -C "$REPO_ROOT" diff --cached --numstat -- "$rel" 2>/dev/null |
    awk -F '\t' 'NF >= 3 && $1 == "-" && $2 == "-" { found = 1 } END { exit !found }'
}

failed=0
for rel in "${STAGED[@]}"; do
  allowlisted "$rel" && continue
  if git -C "$REPO_ROOT" check-ignore -q -- "$rel" 2>/dev/null; then
    continue
  fi
  # Skip binaries git itself classifies as non-text — images and the like are
  # not the Write|Edit damage class this backstop closes. A text blob that
  # somehow carries a NUL is still fail-closed below.
  if is_git_binary "$rel"; then
    continue
  fi
  content=$(git -C "$REPO_ROOT" show ":$rel" 2>/dev/null) || continue
  # Bash command substitution cannot preserve NUL bytes, so a text blob that
  # embeds one is scanned only up to the first NUL — the same ceiling the
  # PreToolUse guards hit once jq has delivered the field. Git-classified
  # binaries are skipped above; no further NUL probe is reliable in-shell.

  secret_out=$(
    secrets::scan_text "$content"
    printf x
  )
  secret_out=${secret_out%x}
  if [[ -n "$secret_out" ]]; then
    {
      echo "pre-commit (guardrails): secret/credential pattern(s) in staged $rel:"
      printf '%s\n' "$secret_out"
      echo "Remove the secret from the index and commit again."
      echo "Never pass --no-verify to skip this check."
    } >&2
    failed=1
  fi

  path_out=$(
    hpp::scan_text "$content" "$SCAN_ROOT" "$REPO_ROOT/$rel"
    printf x
  )
  path_out=${path_out%x}
  if [[ -n "$path_out" ]]; then
    {
      echo "pre-commit (guardrails): hardcoded machine-specific path(s) in staged $rel:"
      printf '%s' "$path_out"
      echo "Use portable alternatives and commit again. Never pass --no-verify to skip this check."
    } >&2
    failed=1
  fi
done

((failed)) && exit 1
exit 0
