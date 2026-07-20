#!/usr/bin/env bash
# preflight.sh — loop-start permission preflight for the unattended work /
# babysit lanes. Detects and REPORTS, once and up front, the conditions that
# otherwise surface as mid-cycle permission prompts:
#   (a) the working directory is not a git repository — a NOTE, since a lane
#       that operates in an out-of-tree worktree can still proceed once (c) is
#       covered; the SKILL interprets it against the lane's needs.
#   (b) a core git/gh working verb is missing from the effective allow-list
#       (probe set: git commit, git push, gh pr create, gh issue comment).
#   (c) the configured out-of-tree worktree root is not covered by any
#       permissions.additionalDirectories entry, so acceptEdits prompts on
#       every write into it.
#
# REPORT-ONLY by design (issue #495): the assistant cannot self-apply the
# remediation — the auto-mode classifier blocks an agent editing its own
# permissions.allow, and a permissions block shipped in a plugin settings.json
# is inert (docs/conventions/permission-rule-hygiene). This script never edits
# settings; it prints the exact operator remediation and ALWAYS exits 0.
# Findings never fail the run.
#
# Effective settings (union of permissions.allow / additionalDirectories):
#   user-global : ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json
#   project     : <root>/.claude/settings.json, <root>/.claude/settings.local.json
# Probe root: $PREFLIGHT_FIXTURE_DIR (tests) else $PWD; project settings resolve
# against the git toplevel of that root when it is a repo, else the root itself.
#
# Requires jq (exits 2 when absent).
#
# Usage:
#   preflight.sh [--worktree-root <path>]   # report lines; exit 0
#   preflight.sh --count [--worktree-root <path>]   # gap count only; exit 0
#   preflight.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
preflight.sh — report the loop-start permission gaps for the work/babysit lanes.

Usage: preflight.sh [--worktree-root <path>] [--count] [--help]

  (no arg)          print one line per condition, then a PREFLIGHT summary; exit 0
  --worktree-root P check that some permissions.additionalDirectories entry covers P
                    (also read from PREFLIGHT_WORKTREE_ROOT); omitted → NOTE, not checked
  --count           print the integer GAP count only (NOTEs excluded); exit 0
  --help            this message

Reports three conditions from the effective settings — (a) cwd not a git repo,
(b) a probed git/gh verb missing from permissions.allow, (c) the worktree root
not covered by additionalDirectories. Report-only: never edits settings, always
exits 0. The remediation is operator-side (see reference/permission-preflight.md).
Requires jq (exit 2 when absent).
EOF
}

mode="report"
worktree_root="${PREFLIGHT_WORKTREE_ROOT:-}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --count)
      mode="count"
      shift
      ;;
    --worktree-root)
      shift
      [[ "$#" -gt 0 ]] || {
        echo "ERROR: --worktree-root requires a path" >&2
        exit 2
      }
      worktree_root="$1"
      shift
      ;;
    --worktree-root=*)
      worktree_root="${1#--worktree-root=}"
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

# --- Settings resolution ------------------------------------------------------
CHECK_DIR="${PREFLIGHT_FIXTURE_DIR:-$PWD}"
repo_root="$(git -C "$CHECK_DIR" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
proj_base="${repo_root:-$CHECK_DIR}"
user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

read_array() {
  # read_array <file> <jq-path> — one element per line; silent on a missing or
  # non-JSON file (a settings file may legitimately not exist).
  local file="$1" path="$2"
  [[ -f "$file" ]] || return 0
  tr -d '\r' <"$file" | jq -e . >/dev/null 2>&1 || return 0
  tr -d '\r' <"$file" | jq -r "$path // [] | .[]" 2>/dev/null | tr -d '\r'
}

collect() {
  # collect <jq-path> — union the path across user-global + project settings.
  local path="$1"
  read_array "$user_settings" "$path"
  read_array "$proj_base/.claude/settings.json" "$path"
  read_array "$proj_base/.claude/settings.local.json" "$path"
}

ALL_ALLOW="$(collect '.permissions.allow')"
ALL_ADDDIRS="$(collect '.permissions.additionalDirectories')"

# --- Matchers -----------------------------------------------------------------
verb_covered() {
  # verb_covered <verb> — true when some Bash()/PowerShell() allow rule grants
  # <verb> exactly or as a boundary-prefixed command. The boundary (space, ':',
  # '*', or end) keeps a distinct verb (git commit-tree) from covering 'git
  # commit'. Runs in the current shell (heredoc, not a pipe) so return escapes.
  local verb="$1" rule inner
  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    case "$rule" in
      "Bash("*")") inner="${rule#Bash(}" ;;
      "PowerShell("*")") inner="${rule#PowerShell(}" ;;
      *) continue ;;
    esac
    inner="${inner%)}"
    [[ "$inner" == "$verb" ]] && return 0
    case "$inner" in
      "$verb "* | "$verb:"* | "$verb"'*'*) return 0 ;;
      *) ;;
    esac
  done <<RULES
$ALL_ALLOW
RULES
  return 1
}

normalize_path() {
  # Fold a path to one comparable form: backslashes → slashes, lower-case and
  # de-colon a leading Windows drive (D:\repos → /d/repos, matching the git-bash
  # /d/repos spelling), strip a trailing slash. Literal only — no symlink
  # resolution, since permission rules match the command string literally.
  local p="$1" drive rest
  # shellcheck disable=SC1003  # '\\' is tr's escaped backslash (one char), not a quote escape
  p="$(printf '%s' "$p" | tr '\\' '/')"
  case "$p" in
    [A-Za-z]:/*)
      drive="$(printf '%s' "${p%%:*}" | tr '[:upper:]' '[:lower:]')"
      rest="${p#*:}"
      p="/$drive$rest"
      ;;
    *) ;;
  esac
  case "$p" in
    ?*/) p="${p%/}" ;;
    *) ;;
  esac
  printf '%s' "$p"
}

dir_covered() {
  # dir_covered <path> — true when some additionalDirectories entry equals the
  # path or is an ancestor of it, after normalization.
  local want entry
  want="$(normalize_path "$1")"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    entry="$(normalize_path "$entry")"
    [[ "$want" == "$entry" ]] && return 0
    case "$want" in
      "$entry"/*) return 0 ;;
      *) ;;
    esac
  done <<DIRS
$ALL_ADDDIRS
DIRS
  return 1
}

# --- Checks -------------------------------------------------------------------
findings=()
gapcount=0
emit_gap() {
  findings+=("GAP $1")
  gapcount=$((gapcount + 1))
}
emit_note() { findings+=("NOTE $1"); }

# (a) cwd not a git repo — informational; a worktree-operating lane may still run.
if [[ -z "$repo_root" ]]; then
  emit_note "(a) '$CHECK_DIR' is not a git repository. A lane that needs a checkout at the cwd cannot claim, branch, or push here; a lane that operates in an out-of-tree worktree proceeds once (c) is covered."
fi

# (b) probed working verbs missing from the effective allow-list.
while IFS= read -r verb; do
  [[ -n "$verb" ]] || continue
  verb_covered "$verb" && continue
  emit_gap "(b) no Bash()/PowerShell() allow rule covers '$verb'. Apply the fleet permission floor operator-side (standards components/claude-permissions, composed into settings via dotfiles#233) — never a plugin self-grant. See reference/permission-preflight.md."
done <<PROBES
git commit
git push
gh pr create
gh issue comment
PROBES

# (c) worktree root not covered by additionalDirectories.
if [[ -n "$worktree_root" ]]; then
  if ! dir_covered "$worktree_root"; then
    emit_gap "(c) no permissions.additionalDirectories entry covers the worktree root '$worktree_root'; acceptEdits will prompt on every out-of-tree write. Add it operator-side. See reference/permission-preflight.md."
  fi
else
  emit_note "(c) worktree root not provided (--worktree-root / PREFLIGHT_WORKTREE_ROOT unset) — additionalDirectories coverage not checked. Pass the lane's out-of-tree worktree root to verify it."
fi

# --- Output -------------------------------------------------------------------
if [[ "$mode" == "count" ]]; then
  printf '%s\n' "$gapcount"
  exit 0
fi

if [[ "${#findings[@]}" -eq 0 ]]; then
  echo "PREFLIGHT: OK — cwd is a git repo, probed grants present, worktree root covered."
  exit 0
fi

printf '%s\n' "${findings[@]}"
if [[ "$gapcount" -eq 0 ]]; then
  echo "PREFLIGHT: OK — ${#findings[@]} note(s), 0 gap(s)."
else
  echo "PREFLIGHT: $gapcount gap(s) — remediate operator-side before the unattended loop; the assistant cannot self-apply (see reference/permission-preflight.md)."
fi
exit 0
