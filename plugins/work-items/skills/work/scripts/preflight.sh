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
#   main-local  : <main-checkout>/.claude/settings.local.json — since Claude Code
#                 v2.1.211 "don't ask again" approvals save here (resolved through
#                 worktrees to the main checkout) and apply in every worktree of
#                 the repository, so this file is read in every mode — but only
#                 when the main checkout is VERIFIED. When it cannot be
#                 determined the layer goes unread and the run reports
#                 PREFLIGHT: INCOMPLETE rather than an unqualified OK; no path is
#                 ever named as the main checkout unverified.
# The cwd probed for (a) is $PREFLIGHT_FIXTURE_DIR (tests) else $PWD. Project
# settings are read from --project-root (default: the cwd checkout) resolved to
# its git toplevel; pass the worker worktree the lane dispatches into so its own
# project settings are checked rather than the cwd checkout's, which could
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
                    coverage reads keep the MAIN checkout's settings.local.json (its
                    rules apply in every worktree since Claude Code v2.1.211) and
                    exclude only a linked-worktree cwd's own local file, which a
                    fresh worker would not inherit
  --project-root P  read project settings from P's checkout instead of the cwd's
                    (also read from PREFLIGHT_PROJECT_ROOT) — pass the dispatched
                    worker worktree so ITS OWN grants (incl. its settings.local.json)
                    are checked rather than the cwd checkout's; a VERIFIED main
                    checkout's settings.local.json is read in every mode
  --count           print the integer GAP count only (NOTEs excluded); exit 0
  --help            this message

Reports three conditions from the effective settings — (a) cwd not a git repo,
(b) a probed git/gh verb denied or missing from permissions.allow, (c) the
worktree root not covered by additionalDirectories. When the main checkout
cannot be verified its settings.local.json goes unread and the summary is
PREFLIGHT: INCOMPLETE, never a bare OK. Report-only: never edits settings,
always exits 0. Remediation is operator-side (see reference/permission-preflight.md).
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
# Since Claude Code v2.1.211, "Yes, don't ask again" saves the rule to
# .claude/settings.local.json at the repository root, resolved through worktrees
# to the MAIN checkout, and the rule applies to sessions anywhere in the
# repository — every linked worktree included (docs/en/permissions#permission-system).
# Resolving that checkout has three outcomes, and the report distinguishes them:
#   verified  — main_root names a directory PROVEN to be this repository's main
#               working tree (main_state=verified).
#   bare      — the repository has no main working tree at all, so no main-local
#               layer can exist and nothing is missing (main_state=bare).
#   unresolved— the main working tree cannot be determined; the layer is UNREAD
#               and the report says so loudly (main_state=unresolved + reason).
# Only "verified" may be named as the main checkout, and only it is read.
main_gitdir="$(git -C "$proj_src" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
own_gitdir="$(git -C "$proj_src" rev-parse --path-format=absolute --git-dir 2>/dev/null | tr -d '\r')"

norm_path() {
  # Fold a path to one comparable form: expand a leading ~, backslashes →
  # slashes, lower-case and de-colon a leading Windows drive (D:\repos →
  # /d/repos, matching the git-bash /d/repos spelling), strip a trailing slash.
  # Literal only — no symlink resolution, since permission rules match the
  # command string literally. Also folds git's native "C:/…" answers against the
  # shell's "/c/…" spelling, so the resolution predicates below compare equal.
  #
  # Answers in $NORM_OUT rather than on stdout, and uses only builtins: this runs
  # on every path comparison, and on Windows a fork per call (the command
  # substitution, plus a printf|tr pipeline inside it) dominates the runtime.
  # normalize_path wraps it for the call sites that want a value.
  local p="$1" home="${HOME:-${USERPROFILE:-}}"
  # A leading ~ (~ alone, or ~/… / ~\… — both separators, since a Windows entry
  # may be written ~\…) expands to the user home so a tilde-form
  # additionalDirectories entry compares equal to the absolute probed root the
  # harness derives from that same home. HOME first, then USERPROFILE (its
  # backslashes, and any in the stripped remainder, are folded by the tr below);
  # neither set leaves ~ literal.
  if [[ -n "$home" ]]; then
    # Strip one trailing separator (either form — HOME=/, USERPROFILE=…\) so the
    # join below cannot double it; normalize_path does not collapse an internal
    # //, so //.worktrees would never match an absolute /.worktrees/… root.
    home="${home%/}"
    home="${home%\\}"
    # shellcheck disable=SC2088  # the literal ~ arms are patterns being matched, not paths to expand
    case "$p" in
      "~") p="$home" ;;
      "~/"* | "~\\"*) p="$home/${p:2}" ;;
      *) ;;
    esac
  fi
  p="${p//\\//}"
  case "$p" in
    [A-Za-z]:/*)
      # Windows filesystems are case-insensitive: fold the WHOLE path, not just
      # the drive letter, so D:/Repos/.Worktrees and /d/repos/.worktrees compare
      # equal. Non-drive (POSIX) paths stay case-sensitive.
      p="${p,,}"
      p="/${p%%:*}${p#*:}"
      ;;
    /[A-Za-z]/*)
      # Git-bash drive spelling (/d/Repos/…) is the same case-insensitive
      # Windows filesystem — fold it too. A true POSIX single-letter root
      # directory is the accepted (rare, documented) collision.
      p="${p,,}"
      ;;
    *) ;;
  esac
  case "$p" in
    ?*/) p="${p%/}" ;;
    *) ;;
  esac
  NORM_OUT="$p"
}

normalize_path() {
  norm_path "$1"
  printf '%s' "$NORM_OUT"
}

is_main_worktree() {
  # is_main_worktree <candidate> — true when <candidate> is THE main working
  # tree of the repository whose common dir is $main_gitdir. All three legs are
  # required: the candidate is a toplevel (not a subdirectory of one), it belongs
  # to THIS repository, and its own git dir is the common dir (so it is the main
  # worktree, not a linked one). One rev-parse answers all three; paths are
  # normalized because git answers in native "C:/…" spelling while shell paths
  # arrive as "/c/…", and an unnormalized compare would silently never match.
  # On success MAIN_TOP carries git's own spelling of the verified toplevel, so
  # every arm below reports one consistent form whatever the candidate's origin.
  local cand="$1" facts top cdir gdir want
  [[ -n "$cand" && -d "$cand" ]] || return 1
  facts="$(git -C "$cand" rev-parse --path-format=absolute \
    --show-toplevel --git-common-dir --git-dir 2>/dev/null | tr -d '\r')"
  [[ -n "$facts" ]] || return 1
  { read -r top && read -r cdir && read -r gdir; } <<<"$facts" || return 1
  norm_path "$cand"
  want="$NORM_OUT"
  norm_path "$top"
  [[ "$NORM_OUT" == "$want" ]] || return 1
  norm_path "$cdir"
  [[ "$NORM_OUT" == "$main_gitdir_n" ]] || return 1
  norm_path "$gdir"
  [[ "$NORM_OUT" == "$main_gitdir_n" ]] || return 1
  MAIN_TOP="$top"
  return 0
}

resolve_main_root() {
  # Sets main_root / main_state / main_reason. Candidates are proposed cheapest
  # first and each is put through is_main_worktree before being trusted; a
  # candidate that fails verification is discarded, never named.
  local cand own_n
  main_root=""
  main_state="unresolved"
  main_reason=""

  if [[ -z "$main_gitdir" ]]; then
    main_reason="'$proj_src' is not a git repository"
    return
  fi
  norm_path "$main_gitdir"
  main_gitdir_n="$NORM_OUT"

  # 1. The probed checkout is itself the main checkout (own git dir IS the common
  #    one) — true whatever the git dir is named, so a --separate-git-dir or
  #    submodule MAIN checkout resolves here.
  norm_path "$own_gitdir"
  own_n="$NORM_OUT"
  if [[ "$own_n" == "$main_gitdir_n" ]] && is_main_worktree "$proj_base"; then
    main_root="$MAIN_TOP"
    main_state="verified"
    return
  fi

  # 2. A bare repository has no main working tree, so there is no main-local
  #    layer to read and nothing is being missed.
  if [[ "$(git --git-dir="$main_gitdir" rev-parse --is-bare-repository 2>/dev/null | tr -d '\r')" == "true" ]]; then
    main_state="bare"
    return
  fi

  # 3. core.worktree in the common dir's config points at the working tree,
  #    relative to the common dir. Git sets it for submodules, which is what
  #    makes a submodule's <super>/.git/modules/<name> shape resolvable at all.
  #    Read the file directly: `git --git-dir=<dir> rev-parse --show-toplevel`
  #    silently falls back to the PROCESS cwd when core.worktree is unset.
  cand="$(git config -f "$main_gitdir/config" --get core.worktree 2>/dev/null | tr -d '\r')"
  if [[ -n "$cand" ]]; then
    case "$cand" in
      /* | [A-Za-z]:[/\\]*) ;;
      *) cand="$main_gitdir/$cand" ;;
    esac
    # core.worktree is spelled with ".." segments ("../../../sub"), which the
    # is-this-a-toplevel leg compares as a literal string — canonicalize first
    # or that leg rejects the true working tree.
    cand="$(cd "$cand" 2>/dev/null && pwd)"
    if is_main_worktree "$cand"; then
      main_root="$MAIN_TOP"
      main_state="verified"
      return
    fi
  fi

  # 4. The conventional "<root>/.git" spelling: the parent of the common dir.
  case "$main_gitdir" in
    */.git)
      cand="${main_gitdir%/.git}"
      if is_main_worktree "$cand"; then
        main_root="$MAIN_TOP"
        main_state="verified"
        return
      fi
      ;;
    *) ;;
  esac

  main_reason="the common git dir '$main_gitdir' names no verifiable working tree"
}

resolve_main_root
# main_root and proj_base come from different producers (git's native "C:/…"
# answers, a config-relative path, the shell's own spelling), so the identity
# test between them goes through the normalized forms.
main_is_proj_base=""
if [[ "$main_state" == "verified" ]]; then
  norm_path "$main_root"
  main_root_n="$NORM_OUT"
  norm_path "$proj_base"
  [[ "$main_root_n" == "$NORM_OUT" ]] && main_is_proj_base="yes"
fi

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
  # project settings + the MAIN checkout's settings.local.json (always: its rules
  # apply in every worktree since v2.1.211, a fresh worker included), plus the
  # project checkout's OWN settings.local.json only when <local-mode> is
  # "with-local". A rule saved inside a linked worktree by a pre-2.1.211 harness
  # (or hand-placed there) applies only to sessions started in that worktree, so
  # in the pre-dispatch autonomous (--worktree-root) path a worktree cwd's local
  # grants would mask a worker-side gap; the coverage reads drop that file there.
  # Deny always keeps it: erring wide on deny cannot mask a gap among the layers
  # actually read. Only a VERIFIED main checkout is read — an unresolved one
  # contributes nothing and is reported as an unread layer instead of being
  # guessed at.
  local path="$1" local_mode="$2"
  read_array "$user_settings" "$path"
  read_array "$proj_base/.claude/settings.json" "$path"
  if [[ "$main_state" == "verified" && -z "$main_is_proj_base" ]]; then
    read_array "$main_root/.claude/settings.local.json" "$path"
  fi
  if [[ "$local_mode" == "with-local" || -n "$main_is_proj_base" ]]; then
    read_array "$proj_base/.claude/settings.local.json" "$path"
  fi
}

# Checkout-own local-settings scope for the COVERAGE reads (allow +
# additionalDirectories); a VERIFIED main checkout's local file is in scope
# regardless:
#   - A DISTINCT --project-root (a worker worktree whose toplevel differs from this
#     checkout) names a real, existing checkout — read ITS OWN settings.local.json
#     (legacy rules saved there still apply to sessions started there).
#   - Otherwise, --worktree-root (the autonomous signal) is pre-dispatch: the worker
#     is not yet created, so exclude a worktree cwd's own gitignored
#     settings.local.json, which a fresh worker would not inherit, lest a
#     worktree-local-only grant mask a gap. When the cwd checkout IS the main
#     checkout this exclusion is a no-op — its local file follows the worker.
#   - The interactive/default path keeps local.
# Deny always reads every local layer that resolves; erring wide on deny cannot
# mask a gap among those layers, but it cannot widen a main checkout that never
# resolved — which is why an unresolved one is reported rather than passed over.
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

dir_covered() {
  # dir_covered <path> — true when some additionalDirectories entry equals the
  # path or is an ancestor of it, after normalization.
  local want entry
  want="$(normalize_path "$1")"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    entry="$(normalize_path "$entry")"
    # Filesystem root authorizes every absolute path ("" after the trailing-slash
    # strip would otherwise expand to //* and match nothing).
    [[ "$entry" == "/" || "$entry" == "" ]] && return 0
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

# A path is named as "the main checkout" only when resolution VERIFIED it. When
# it did not, the layer is UNREAD and every mode says so — including the
# interactive one, which prints no header otherwise and would otherwise drop a
# main-local deny in silence.
main_unread=""
if [[ "$main_state" == "unresolved" ]]; then
  main_unread="yes"
fi

if [[ -n "$local_excluded" ]]; then
  if [[ -n "$main_is_proj_base" ]]; then
    echo "PREFLIGHT: autonomous mode (--worktree-root, no distinct --project-root) — coverage read includes this main checkout's settings.local.json: since Claude Code v2.1.211 its rules apply in every worktree, the fresh worker included."
  elif [[ "$main_state" == "verified" ]]; then
    echo "PREFLIGHT: autonomous mode (--worktree-root, no distinct --project-root) — coverage read includes the main checkout's settings.local.json ('$main_root', applies in every worktree since Claude Code v2.1.211) but excludes this worktree's own local file, which a fresh worker would not inherit; deny rules still include it."
  else
    echo "PREFLIGHT: autonomous mode (--worktree-root, no distinct --project-root) — coverage read excludes this checkout's gitignored settings.local.json, which a fresh worktree would not carry; deny rules still include it."
  fi
elif [[ -n "$distinct_project_root" ]]; then
  if [[ "$main_state" == "verified" && -z "$main_is_proj_base" ]]; then
    echo "PREFLIGHT: reading project settings (incl. settings.local.json) from --project-root '$proj_base', plus the main checkout's shared settings.local.json ('$main_root')."
  else
    echo "PREFLIGHT: reading project settings (incl. settings.local.json) from --project-root '$proj_base'."
  fi
fi

if [[ -n "$main_unread" ]]; then
  echo "PREFLIGHT: UNREAD LAYER — the main checkout's settings.local.json was NOT read: $main_reason. Its rules apply in every worktree since Claude Code v2.1.211, so a grant there is not credited (a verb may be over-reported as a gap) and, worse, a DENY there is not reported at all. Findings below are incomplete. Run the preflight from the main checkout, or pass --project-root naming it, to read that layer."
fi

if [[ "${#findings[@]}" -gt 0 ]]; then
  printf '%s\n' "${findings[@]}"
fi

# INCOMPLETE outranks BOTH OK branches: an unread main-checkout layer means the
# probe never saw every rule, so "OK" would assert more than the run checked.
if [[ -n "$main_unread" ]]; then
  echo "PREFLIGHT: INCOMPLETE — main-checkout layer unread ($main_reason); $gapcount gap(s) found among the layers that were read. Report-only: exit 0 regardless (see reference/permission-preflight.md)."
elif [[ "${#findings[@]}" -eq 0 ]]; then
  echo "PREFLIGHT: OK — cwd is a git repo, probed grants present, worktree root covered."
elif [[ "$gapcount" -eq 0 ]]; then
  echo "PREFLIGHT: OK — ${#findings[@]} note(s), 0 gap(s)."
else
  echo "PREFLIGHT: $gapcount gap(s) — remediate operator-side before the unattended loop; the assistant cannot self-apply (see reference/permission-preflight.md)."
fi
exit 0
