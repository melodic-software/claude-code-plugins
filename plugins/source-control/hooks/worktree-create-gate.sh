#!/usr/bin/env bash
# worktree-create-gate.sh — WorktreeCreate hook: place every worktree Claude Code
# creates at the configured EXTERNAL root, never the in-repo `.claude/worktrees/`.
#
# The `/worktree create` skill already routes through scripts/worktree-create.sh,
# but three creation paths bypass the skill entirely — `claude --worktree`, a
# subagent with `isolation: "worktree"`, and a background session. Those land in
# the in-repo default — the nested placement the nesting invariant exists to
# avoid; that claim is owned, measured and dated in exactly one place, and this
# comment does not restate it: see
# skills/worktree/SKILL.md § "The nesting invariant, verified".
# This hook is the seam that covers those three paths,
# and it is a thin stdin adapter over the same helper so there is one placement
# implementation rather than two.
#
# Contract (measured, not inferred — see the stamp at the end of this header):
#   * stdin is one JSON object: session_id, transcript_path, cwd,
#     hook_event_name="WorktreeCreate", name — `name` being the requested
#     worktree name, `cwd` the session's repository.
#   * stdout's LAST NON-EMPTY LINE is taken as the worktree path. Extra lines are
#     tolerated: a hook printing a banner line before the path still succeeds and
#     the session lands in the printed directory. (The contrary claim — that any
#     output but the path fails the session — was tested and is false.) This hook
#     still prints the path alone; the tolerance is the safety margin, not the
#     interface.
#   * The hook REPLACES git's own worktree creation. Nothing registers a worktree
#     unless the hook does it, which is why this delegates to the helper rather
#     than merely computing a path. Printing a path the hook did not create is
#     refused by the harness: "worktree directory <p> does not exist or is not a
#     directory. The path came from a WorktreeCreate hook — the hook must print
#     the directory it created as the last line of its stdout."
#   * A user-scope hook fires. Verified with settings.json under a
#     CLAUDE_CONFIG_DIR, on a headless run, before login was even resolved.
#   * ${CLAUDE_PROJECT_DIR} is the project root the session started in — never the
#     worktree being created. The repository is taken from stdin's `cwd` for the
#     same reason: it is the value the event itself carries.
#
# There is NO stand-down channel. Both failure shapes fail the creation:
#   * a non-zero exit — "Any non-zero exit code causes worktree creation to fail";
#   * exit 0 with no path — "Hook failure or missing path fails creation", which
#     the harness reports as "hook succeeded but returned no worktree path".
# So a WorktreeCreate hook cannot say "not applicable, use your own default". The
# only way this hook can decline is to fail the creation, which is why the
# disabled path below exits NON-ZERO rather than exiting 0 silently.
#
# Which channel a message reaches:
#   * a NON-ZERO exit surfaces this hook's stderr — ALL of it, not merely the
#     first line — inside the harness's own error text, prefixed with the hook
#     command. That is the only user-visible channel this hook has, so every
#     refusal below leads with the remedy and follows with the diagnosis.
#   * an exit-0 stderr line is DROPPED: it reaches the debug log and nothing else.
#     Measured — an exit-0 probe hook's stderr marker was absent from the harness
#     output while its exit-3 sibling's two lines both appeared.
#
# Fail-closed by design. A hook failure fails the creation, and that is the
# correct direction here: falling through to Claude Code's default would place the
# worktree at exactly the nested path this exists to prevent. The unconfigured
# case is not a failure — it resolves to the plugin data directory, which is also
# outside every repository.
#
# `worktree_create_gate_enabled=false` does NOT hand placement back to Claude
# Code — per the paragraph above, no such channel exists. It makes this hook
# refuse, which fails every harness-driven creation path. The harness-side
# stand-down is `worktree.bgIsolation: "none"`, or disabling the plugin.
#
# ── Verification stamp (docs/conventions/upstream-drift) ────────────────────────
# Claim: the four harness behaviors above — last-non-empty-line path read, hook
#   must create the directory, both failure shapes fail creation, and the
#   exit-0-stderr/non-zero-stderr channel split.
# Basis: <https://code.claude.com/docs/en/hooks> raw markdown (`hooks.md`,
#   "WorktreeCreate output" and the exit-code tables), plus a four-arm probe of
#   `claude -p --worktree <name> --settings <file>` in throwaway repos — control
#   (no hook), exit-0-no-path, exit-3-with-stderr, and path-without-directory.
#   The probe is recorded in `skills/worktree/fixtures/README.md`.
# As-of: 2026-08-11, Claude Code 2.1.228.
# Recheck trigger: a Claude Code release note naming `WorktreeCreate`, worktree
#   isolation, or hook stderr surfacing; or the hooks page's "WorktreeCreate
#   output" section changing what a hook must return.
# ───────────────────────────────────────────────────────────────────────────────

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hook-utils.sh
. "$HOOK_DIR/hook-utils.sh"

# Every refusal in this hook goes through here, so the remedy always leads.
#
# The harness prints a failing hook's whole stderr inside its own error text, and
# a reader stops at the first line that tells them what to do. Diagnosis second,
# remedy first — the reverse order is what made the previous messages useless: the
# only line guaranteed to be read named a symptom nobody could act on.
#
# Exit 1 uniformly. The exit code is not a channel here — every non-zero value
# fails the creation identically and none of them reaches the user — so the
# taxonomy lives in the TEXT, which is the part that is actually surfaced.
gate::refuse() {
  local remedy="$1"
  shift
  printf 'worktree-create-gate: %s\n' "$remedy" >&2
  local line
  for line in "$@"; do
    printf 'worktree-create-gate:   %s\n' "$line" >&2
  done
  exit 1
}

# Disabled does NOT mean "let Claude Code use its own default" — see the header:
# no such channel exists, and the exit-0/empty-stdout shape this used to take
# fails the creation anyway, with a generic harness error that never mentions the
# option the user just set. So the disabled path refuses OUT LOUD instead, and
# the one thing it must do is name the real stand-downs.
#
# The flag is read directly rather than through `hook::check_enabled`, which EXITS
# 0 itself instead of returning — anything a caller writes after it is dead code,
# and an exit-0 skip is precisely the shape being removed here.
if [[ "${CLAUDE_PLUGIN_OPTION_WORKTREE_CREATE_GATE_ENABLED:-true}" != "true" ]]; then
  gate::refuse \
    'to let Claude Code place worktrees itself, set worktree.bgIsolation to "none" in settings, or disable this plugin — turning this option off cannot hand placement back' \
    'the gate is disabled by worktree_create_gate_enabled=false, so it declined to place this worktree' \
    'a WorktreeCreate hook has no "not applicable" channel: both refusing and returning no path fail the creation'
fi

# The status matters: an empty or unreadable buffer is a DIFFERENT failure from a
# payload that parsed but carried no `.name`, and reporting the second for the
# first sent readers hunting a harness that had in fact sent nothing.
if ! payload="$(hook::buffer_stdin)"; then
  gate::refuse \
    'rerun the worktree creation; if it repeats, run with hook debugging on to capture the WorktreeCreate payload' \
    'nothing readable arrived on stdin — the WorktreeCreate payload was empty or could not be buffered' \
    'this is not the same as a payload missing its .name field, which is reported separately'
fi

# jq is the primary reader; the fallback exists because failing the creation over
# an absent optional CLI would be a worse outcome than a bounded string extract of
# two flat, harness-generated string fields.
json_field() {
  local field="$1" value=""
  if command -v jq >/dev/null 2>&1; then
    value="$(hook::jq_field "$payload" ".$field")" || value=""
  fi
  if [[ -z "$value" ]]; then
    value="$(printf '%s' "$payload" |
      sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
      head -n 1 | tr -d '\r')"
    # The harness emits JSON-escaped Windows paths, so a fallback read has to undo
    # the one escape those paths actually carry.
    value="${value//\\\\/\\}"
  fi
  printf '%s' "$value"
}

name="$(json_field name)"
repo_dir="$(json_field cwd)"

if [[ -z "$name" ]]; then
  gate::refuse \
    'name the worktree explicitly (claude --worktree <name>); if a name was supplied, this is a harness defect worth reporting' \
    'the WorktreeCreate payload parsed but carried no .name, and guessing a worktree name is worse than refusing'
fi
if [[ -z "$repo_dir" ]]; then
  repo_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

# Root resolution mirrors the skill's, and deliberately reads the option from the
# environment rather than substituting `${user_config.worktree_root}` into a
# command: a value substituted into a shell field would be executed by the shell,
# which is why Claude Code rejects that form outright and exports
# CLAUDE_PLUGIN_OPTION_<KEY> instead.
root="${CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT:-}"
# An unexpanded placeholder is an unset value wearing a string's clothes.
# SC2016: the single-quoted ${user_config token is matched literally on purpose —
# the UNexpanded placeholder is exactly what is being detected, so expanding it
# here would defeat the check. Same rationale and same form as
# scripts/worktree-create.sh:230.
# shellcheck disable=SC2016
case "$root" in
*'${user_config'*) root="" ;;
*) ;;
esac

helper="$HOOK_DIR/../scripts/worktree-create.sh"
if [[ ! -f "$helper" ]]; then
  gate::refuse \
    'reinstall or update the source-control plugin — its worktree-creation helper is missing from the installed tree' \
    "expected the helper at $helper"
fi

args=(--name "$name" --repo-dir "$repo_dir")
if [[ -n "$root" ]]; then
  args+=(--root "$root")
else
  # No configured root: fall back to the plugin data directory, which is harness
  # state rather than a checkout, so it satisfies the outside-every-repository
  # invariant on its own. Passed through the helper's file channel because that is
  # the interface the helper documents for a value it must read verbatim.
  data_root="${CLAUDE_PLUGIN_DATA:-}"
  if [[ -z "$data_root" ]]; then
    gate::refuse \
      'set the worktree_root plugin option to a directory outside every repository, then retry' \
      'neither worktree_root nor CLAUDE_PLUGIN_DATA is set, so there is no root outside the repository to place this worktree under' \
      'letting it land inside the repository is the one outcome this gate exists to prevent'
  fi
  root_file="$(mktemp "${TMPDIR:-/tmp}/worktree-create-gate.XXXXXX")" || {
    gate::refuse \
      'check that TMPDIR points at a writable directory with space free, then retry' \
      'could not create a temp file for the data-root handoff'
  }
  trap 'rm -f "$root_file"' EXIT
  printf '%s' "$data_root" >"$root_file"
  args+=(--data-root-file "$root_file")
fi

# The assignment stands alone so `$?` is the HELPER's status. Inside the body of
# `if ! cmd`, `$?` is the status of the negated compound — which is 0 exactly when
# `cmd` failed — so the previous form reported a constant 0 for every failure. A
# constant that looks like a real exit code is worse than no code at all: it is
# what produced, and cost a verification pass to unwind, the theory that a hook
# had exited 0 while failing.
path="$(bash "$helper" "${args[@]}")"
status=$?

# The helper's stderr is not captured, so its own guidance has already reached the
# user by the time this runs. What is added here is the translation of its
# documented exit taxonomy (worktree-create.sh, "Exit codes") into a remedy — the
# taxonomy used to be discarded, collapsing "not a repository", "no worktree_root
# configured" and "illegal branch name" into one indistinguishable line.
if ((status != 0)); then
  case "$status" in
  2)
    gate::refuse \
      "choose a worktree name git accepts as a branch — no '..', no trailing '.lock', no reserved name like HEAD" \
      "the helper rejected the request as a usage error (exit 2) for name: $name"
    ;;
  3)
    gate::refuse \
      'set the worktree_root plugin option to a directory outside every repository, then retry' \
      'the helper found no usable external root (exit 3) and refused rather than falling back to the in-repo default'
    ;;
  4)
    gate::refuse \
      "if $repo_dir is not a git repository, set worktree.bgIsolation to \"none\" in settings so Claude Code edits in place instead of isolating" \
      "the helper hit an environment error (exit 4): either $repo_dir is not a git repository, or git worktree add itself failed" \
      'the git error above this line, if any, is the authoritative detail'
    ;;
  *)
    gate::refuse \
      'read the helper output above for the failure, then retry' \
      "the helper exited $status, which is outside its documented 0/2/3/4 taxonomy"
    ;;
  esac
fi

if [[ -z "$path" ]]; then
  gate::refuse \
    'reinstall or update the source-control plugin — its worktree-creation helper returned success without a path, which it is never supposed to do' \
    'the helper exited 0 but printed no worktree path, so there is nothing to hand back to Claude Code'
fi

printf '%s\n' "$path"
