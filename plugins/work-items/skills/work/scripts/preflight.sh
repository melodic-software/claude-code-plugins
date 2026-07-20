#!/usr/bin/env bash
# preflight.sh — loop-start permission preflight for the unattended work /
# babysit lanes. Detects and REPORTS, once and up front, the conditions that
# otherwise surface as mid-cycle permission prompts:
#   (a) the working directory is not a git repository — a NOTE, since a lane
#       that operates in an out-of-tree worktree can still proceed once (c) is
#       covered; the SKILL interprets it against the lane's needs.
#   (b) a core git/gh working verb (probe set: git add, git commit, git push,
#       gh pr create, gh issue comment) is blocked by a matching deny rule, or
#       is missing from the effective allow-list. Deny wins over allow.
#   (c) the configured out-of-tree worktree root is not covered by any
#       permissions.additionalDirectories entry, so acceptEdits prompts on
#       every write into it.
#
# REPORT-ONLY by design: the assistant cannot self-apply the
# remediation — the auto-mode classifier blocks an agent editing its own
# permissions.allow, and a permissions block shipped in a plugin settings.json
# is inert (docs/conventions/permission-rule-hygiene). This script never edits
# settings; it prints the exact operator remediation and ALWAYS exits 0.
# Findings never fail the run.
#
# Effective settings (union of permissions.allow / additionalDirectories):
#   user-global : ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json (applies everywhere)
#   project     : <project-root>/.claude/settings.json, .../settings.local.json
# The cwd probed for (a) is $PREFLIGHT_FIXTURE_DIR (tests) else $PWD. Project
# settings are read from --project-root (default: the cwd checkout) resolved to
# its git toplevel; pass the worker worktree the lane dispatches into so its own
# project settings are checked rather than the main checkout's, which could
# otherwise mask a worker-side gap. $PREFLIGHT_PROJECT_ROOT is the env fallback.
#
# Requires jq (exits 2 when absent).
#
# Usage:
#   preflight.sh [--worktree-root <path>] [--project-root <path>]   # report; exit 0
#   preflight.sh --count [--worktree-root <path>] [--project-root <path>]   # gap count
#   preflight.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
preflight.sh — report the loop-start permission gaps for the work/babysit lanes.

Usage: preflight.sh [--worktree-root <path>] [--project-root <path>] [--count] [--help]

  (no arg)          print one line per condition, then a PREFLIGHT summary; exit 0
  --worktree-root P check that some permissions.additionalDirectories entry covers P
                    (also read from PREFLIGHT_WORKTREE_ROOT); omitted → NOTE, not checked.
                    The autonomous signal: unless a distinct --project-root is given,
                    coverage reads exclude this checkout's gitignored settings.local.json
                    (a not-yet-created worktree lacks it)
  --project-root P  read project settings from P's checkout instead of the cwd's
                    (also read from PREFLIGHT_PROJECT_ROOT) — pass the dispatched
                    worker worktree so ITS OWN grants (incl. its settings.local.json)
                    are checked, not the main checkout's
  --count           print the integer GAP count only (NOTEs excluded); exit 0
  --help            this message

Reports three conditions from the effective settings — (a) cwd not a git repo,
(b) a probed git/gh verb denied or missing from permissions.allow, (c) the
worktree root not covered by additionalDirectories. Report-only: never edits
settings, always exits 0. Remediation is operator-side (see reference/permission-preflight.md).
Requires jq (exit 2 when absent).
EOF
}

mode="report"
worktree_root="${PREFLIGHT_WORKTREE_ROOT:-}"
project_root="${PREFLIGHT_PROJECT_ROOT:-}"
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
    --project-root)
      shift
      [[ "$#" -gt 0 ]] || {
        echo "ERROR: --project-root requires a path" >&2
        exit 2
      }
      project_root="$1"
      shift
      ;;
    --project-root=*)
      project_root="${1#--project-root=}"
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
# (a) is about the actual cwd; project settings are read from --project-root when
# given (the worker worktree the orchestrator is dispatching into), else the cwd
# checkout. Reading the dispatched worktree's own project settings is what keeps
# the main checkout's grants from masking a worker-side gap. User-global settings
# apply everywhere and are read regardless.
CHECK_DIR="${PREFLIGHT_FIXTURE_DIR:-$PWD}"
repo_root="$(git -C "$CHECK_DIR" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
proj_src="${project_root:-$CHECK_DIR}"
proj_toplevel="$(git -C "$proj_src" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
proj_base="${proj_toplevel:-$proj_src}"
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
  # collect <jq-path> <local-mode> — union the path across user-global + tracked
  # project settings, plus the gitignored project settings.local.json only when
  # <local-mode> is "with-local". A fresh linked worktree carries the tracked
  # .claude/settings.json but NOT the gitignored settings.local.json, so in the
  # autonomous (--worktree-root) path this checkout's local grants would mask a
  # worker-side gap; the coverage reads drop local there. Deny always keeps local
  # (erring wide on deny never masks a gap).
  local path="$1" local_mode="$2"
  read_array "$user_settings" "$path"
  read_array "$proj_base/.claude/settings.json" "$path"
  [[ "$local_mode" == "with-local" ]] && read_array "$proj_base/.claude/settings.local.json" "$path"
}

# Local-settings scope for the COVERAGE reads (allow + additionalDirectories):
#   - A DISTINCT --project-root (a worker worktree whose toplevel differs from this
#     checkout) names a real, existing checkout — read ITS OWN settings.local.json
#     (the worker's file, not this parent's); nothing is masked.
#   - Otherwise, --worktree-root (the autonomous signal) is pre-dispatch: the worker
#     is not yet created, so exclude this checkout's gitignored settings.local.json,
#     which a fresh worktree would not carry, lest a local-only grant mask a gap.
#   - The interactive/default path keeps local.
# Deny always reads local (erring wide on deny never masks a gap).
distinct_project_root=""
if [[ -n "$project_root" && "$proj_base" != "$repo_root" ]]; then
  distinct_project_root="yes"
fi
local_excluded=""
if [[ -n "$worktree_root" && -z "$distinct_project_root" ]]; then
  local_excluded="yes"
fi
if [[ -n "$local_excluded" ]]; then
  cov_local="no-local"
else
  cov_local="with-local"
fi
ALL_ALLOW="$(collect '.permissions.allow' "$cov_local")"
ALL_DENY="$(collect '.permissions.deny' "with-local")"
ALL_ADDDIRS="$(collect '.permissions.additionalDirectories' "$cov_local")"

# --- Matchers -----------------------------------------------------------------
verb_in_rules() {
  # verb_in_rules <verb> <rules> <mode> — true when some Bash()/PowerShell() rule
  # in the newline-separated <rules> grants <verb> in a shape the <mode> accepts:
  #   open-glob-only — the open-glob form only (`git commit *` / `git commit:*`).
  #                    Used for COVERAGE: a bare-exact `Bash(git commit)` permits
  #                    only the argumentless command, and a work-lane invocation
  #                    always carries args, so bare does NOT cover.
  #   bare           — open-glob OR the argumentless bare verb (`git commit`).
  #                    Used for DENY: erring wide is safe (a bare deny still
  #                    signals the verb is off-limits).
  #   bare-exact-only — the bare verb only. Used to sharpen the gap message when
  #                    open-glob coverage is absent but a bare-only grant exists
  #                    (it serves an argumentless caller like babysit's plain
  #                    `git push`, but not the work lane's argument-carrying call).
  # A rule whose next token is a specific flag or argument (`git commit --amend`,
  # a force-with-lease-only push) never matches — it is a narrower slice.
  # Exact-shape only, by deliberate design: this does NOT simulate glob semantics,
  # so a broader deny pattern that would match the verb at runtime is not detected
  # here. The `'*'` is a quoted literal asterisk, so each arm matches one exact
  # rule spelling, not a prefix. Runs in the current shell (heredoc, not a pipe)
  # so return escapes.
  local verb="$1" rules="$2" mode="$3" rule inner
  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    case "$rule" in
      "Bash("*")") inner="${rule#Bash(}" ;;
      "PowerShell("*")") inner="${rule#PowerShell(}" ;;
      *) continue ;;
    esac
    inner="${inner%)}"
    if [[ "$mode" != "bare-exact-only" ]]; then
      case "$inner" in
        "$verb "'*' | "$verb:"'*') return 0 ;;
        *) ;;
      esac
    fi
    if [[ "$mode" == "bare" || "$mode" == "bare-exact-only" ]]; then
      [[ "$inner" == "$verb" ]] && return 0
    fi
  done <<RULES
$rules
RULES
  return 1
}

verb_covered() { verb_in_rules "$1" "$ALL_ALLOW" "open-glob-only"; }
verb_denied() { verb_in_rules "$1" "$ALL_DENY" "bare"; }
verb_bare_exact() { verb_in_rules "$1" "$ALL_ALLOW" "bare-exact-only"; }

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
      # Windows filesystems are case-insensitive: fold the WHOLE path, not just
      # the drive letter, so D:/Repos/.Worktrees and /d/repos/.worktrees compare
      # equal. Non-drive (POSIX) paths stay case-sensitive.
      p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
      drive="${p%%:*}"
      rest="${p#*:}"
      p="/$drive$rest"
      ;;
    /[A-Za-z]/*)
      # Git-bash drive spelling (/d/Repos/…) is the same case-insensitive
      # Windows filesystem — fold it too. A true POSIX single-letter root
      # directory is the accepted (rare, documented) collision.
      p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
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

# (b) probed working verbs blocked by deny, or missing from the effective
# allow-list. Deny is checked first because deny wins over allow in the
# permission model — an allowed-but-denied verb is still unrunnable.
while IFS= read -r verb; do
  [[ -n "$verb" ]] || continue
  if verb_denied "$verb"; then
    emit_gap "(b) '$verb' is DENIED by a matching deny rule (deny wins over allow), so the unattended lane cannot run it even if allowed. Resolve the deny rule operator-side before relying on this verb. See reference/permission-preflight.md."
    continue
  fi
  verb_covered "$verb" && continue
  if verb_bare_exact "$verb"; then
    emit_gap "(b) '$verb' has only a bare-exact allow rule: it covers argumentless invocations (e.g. the babysit fix cycle's plain \`git push\`) but not argument-carrying ones (the work lane's \`$verb …\`). Grant the open glob (\`$verb *\`) operator-side. See reference/permission-preflight.md."
    continue
  fi
  emit_gap "(b) no Bash()/PowerShell() allow rule covers '$verb'. Apply the fleet permission floor operator-side (standards components/claude-permissions, composed into settings via dotfiles#233) — never a plugin self-grant. See reference/permission-preflight.md."
done <<PROBES
git add
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

if [[ -n "$local_excluded" ]]; then
  echo "PREFLIGHT: autonomous mode (--worktree-root, no distinct --project-root) — coverage read excludes this checkout's gitignored settings.local.json, which a fresh worktree would not carry; deny rules still include it."
elif [[ -n "$distinct_project_root" ]]; then
  echo "PREFLIGHT: reading project settings (incl. settings.local.json) from --project-root '$proj_base'."
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
