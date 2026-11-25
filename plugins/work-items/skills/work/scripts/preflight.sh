#!/usr/bin/env bash
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
                    rules apply across worktrees where saved at the repository root,
                    not on Windows, with the root equal to $HOME, or with a root not
                    owned by the user) and exclude only a linked-worktree cwd's own
                    local file, which a fresh worker would not inherit
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
  --count) mode="count" ;;
  --worktree-root | --project-root)
    [[ "$#" -gt 1 ]] || {
      echo "ERROR: $1 requires a path" >&2
      exit 2
    }
    if [[ "$1" == "--worktree-root" ]]; then
      worktree_root="$2"
    else
      project_root="$2"
    fi
    shift
    ;;
  --worktree-root=*) worktree_root="${1#*=}" ;;
  --project-root=*) project_root="${1#*=}" ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    exit 2
    ;;
  esac
  shift
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

CHECK_DIR="${PREFLIGHT_FIXTURE_DIR:-$PWD}"
repo_root="$(git -C "$CHECK_DIR" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
proj_src="${project_root:-$CHECK_DIR}"
proj_toplevel="$(git -C "$proj_src" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
proj_base="${proj_toplevel:-$proj_src}"
user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
main_gitdir="$(git -C "$proj_src" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
own_gitdir="$(git -C "$proj_src" rev-parse --path-format=absolute --git-dir 2>/dev/null | tr -d '\r')"

norm_path() {
  local p="$1" home="${HOME:-${USERPROFILE:-}}"
  if [[ -n "$home" ]]; then
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
    p="${p,,}"
    p="/${p%%:*}${p#*:}"
    ;;
  /[A-Za-z]/*)
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

is_main_worktree() {
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

accept_main_worktree() {
  is_main_worktree "$1" || return 1
  main_root="$MAIN_TOP"
  main_state="verified"
}

resolve_main_root() {
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

  norm_path "$own_gitdir"
  own_n="$NORM_OUT"
  if [[ "$own_n" == "$main_gitdir_n" ]] && accept_main_worktree "$proj_base"; then
    return
  fi

  if [[ "$(git --git-dir="$main_gitdir" rev-parse --is-bare-repository 2>/dev/null | tr -d '\r')" == "true" ]]; then
    main_state="bare"
    return
  fi

  cand="$(GIT_DIR="$main_gitdir" git config --get core.worktree 2>/dev/null | tr -d '\r')"
  if [[ -n "$cand" ]]; then
    case "$cand" in
    /* | [A-Za-z]:[/\\]*) ;;
    *) cand="$main_gitdir/$cand" ;;
    esac
    cand="$(cd "$cand" 2>/dev/null && pwd)"
    if accept_main_worktree "$cand"; then
      return
    fi
  fi

  if [[ "$main_gitdir" == */.git ]] && accept_main_worktree "${main_gitdir%/.git}"; then
    return
  fi

  main_reason="the common git dir '$main_gitdir' names no verifiable working tree"
}

resolve_main_root
main_is_proj_base=""
if [[ "$main_state" == "verified" ]]; then
  norm_path "$main_root"
  main_root_n="$NORM_OUT"
  norm_path "$proj_base"
  [[ "$main_root_n" == "$NORM_OUT" ]] && main_is_proj_base="yes"
fi

detect_layout() {
  layout="shared"
  layout_causes=""
  layout_reason=""
  [[ "$main_state" == "verified" ]] || return 0
  local uname_s="${PREFLIGHT_UNAME-$(uname -s 2>/dev/null)}" home="${HOME:-${USERPROFILE:-}}"
  local cur_uid tag entry owner root_n home_n root_p home_p
  [[ -n "$uname_s" ]] || layout_reason="the platform (uname -s) is unreadable"
  case "$uname_s" in
  MINGW* | MSYS* | CYGWIN*)
    layout="per-worktree"
    layout_causes="Windows"
    return 0
    ;;
  *) ;;
  esac
  if [[ -n "$home" ]]; then
    norm_path "$main_root"
    root_n="$NORM_OUT"
    norm_path "$home"
    home_n="$NORM_OUT"
    root_p="$(cd -P -- "$main_root" 2>/dev/null && pwd -P)"
    home_p="$(cd -P -- "$home" 2>/dev/null && pwd -P)"
    if [[ "$root_n" == "$home_n" || (-n "$root_p" && "$root_p" == "$home_p") ]]; then
      layout_causes="repository root is the home directory"
    fi
  else
    layout_reason="neither HOME nor USERPROFILE is set, so a repository root equal to the home directory cannot be ruled out"
  fi
  cur_uid="${PREFLIGHT_UID:-$(id -u 2>/dev/null)}"
  case "$cur_uid" in
  "" | *[!0-9]*) layout_reason="the current user id is unreadable ('$cur_uid')" ;;
  *)
    for tag in ROOT GIT CLAUDE; do
      case "$tag" in
      ROOT) entry="$main_root" owner="${PREFLIGHT_OWNER_ROOT:-}" ;;
      GIT) entry="$main_root/.git" owner="${PREFLIGHT_OWNER_GIT:-}" ;;
      *) entry="$main_root/.claude" owner="${PREFLIGHT_OWNER_CLAUDE:-}" ;;
      esac
      if [[ ! -e "$entry" ]]; then
        [[ "$tag" == "CLAUDE" ]] && continue
        layout_reason="'$entry' does not exist, so its owner cannot be read"
        continue
      fi
      if [[ -z "$owner" ]]; then
        # portability-ok: GNU-first rung of a dual-dialect ladder; the BSD -f spelling is the || fallback, and a non-numeric owner falls to "unknown"
        owner="$(stat -c %u "$entry" 2>/dev/null || stat -f %u "$entry" 2>/dev/null)"
      fi
      case "$owner" in
      "" | *[!0-9]*) layout_reason="the owner of '$entry' is unreadable" ;;
      "$cur_uid") ;;
      *)
        layout_causes="${layout_causes:+$layout_causes, }root, .git or .claude not owned by the user"
        break
        ;;
      esac
    done
    ;;
  esac
  if [[ -n "$layout_causes" ]]; then
    layout="per-worktree"
  elif [[ -n "$layout_reason" ]]; then
    layout="unknown"
  fi
}

detect_layout

read_array() {
  local file="$1" path="$2" json
  [[ -f "$file" ]] || return 0
  json="$(tr -d '\r' <"$file")" || return 0
  jq -e . <<<"$json" >/dev/null 2>&1 || return 0
  jq -r "$path // [] | .[]" <<<"$json" 2>/dev/null | tr -d '\r'
}

collect() {
  local path="$1" local_mode="$2" kind="${3:-}" main_shared=""
  [[ "$layout" == "shared" || "$kind" == "deny" ]] && main_shared="yes"
  read_array "$user_settings" "$path"
  read_array "$proj_base/.claude/settings.json" "$path"
  if [[ "$main_state" == "verified" && -z "$main_is_proj_base" && -n "$main_shared" ]]; then
    read_array "$main_root/.claude/settings.local.json" "$path"
  fi
  if [[ "$local_mode" == "with-local" || (-n "$main_is_proj_base" && -n "$main_shared") ]]; then
    read_array "$proj_base/.claude/settings.local.json" "$path"
  fi
}

distinct_project_root=""
[[ -n "$project_root" && "$proj_base" != "$repo_root" ]] && distinct_project_root="yes"
cov_local="with-local"
[[ -n "$worktree_root" && -z "$distinct_project_root" ]] && cov_local="no-local"
layout_unread=""
[[ "$layout" == "unknown" && (-z "$main_is_proj_base" || "$cov_local" == "no-local") ]] && layout_unread="yes"
ALL_ALLOW="$(collect '.permissions.allow' "$cov_local")"
ALL_DENY="$(collect '.permissions.deny' "with-local" deny)"
ALL_ADDDIRS="$(collect '.permissions.additionalDirectories' "$cov_local")"

verb_in_rules() {
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
  local want entry
  norm_path "$1"
  want="$NORM_OUT"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    norm_path "$entry"
    entry="$NORM_OUT"
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

findings=()
gapcount=0
emit_gap() {
  findings+=("GAP $1")
  gapcount=$((gapcount + 1))
}
emit_note() { findings+=("NOTE $1"); }

if [[ -z "$repo_root" ]]; then
  emit_note "(a) '$CHECK_DIR' is not a git repository. A lane that needs a checkout at the cwd cannot claim, branch, or push here; a lane that operates in an out-of-tree worktree proceeds once (c) is covered."
fi

for verb in "git add" "git commit" "gh pr create" "gh issue comment"; do
  if verb_denied "$verb"; then
    emit_gap "(b) '$verb' is DENIED by a matching deny rule (deny wins over allow), so the unattended lane cannot run it even if allowed. Resolve the deny rule operator-side before relying on this verb. See reference/permission-preflight.md."
    continue
  fi
  verb_covered "$verb" && continue
  if verb_bare_exact "$verb"; then
    emit_gap "(b) '$verb' has only a bare-exact allow rule: it covers argumentless invocations but not argument-carrying ones (the work lane's \`$verb …\`). Grant the open glob (\`$verb *\`) operator-side. See reference/permission-preflight.md."
    continue
  fi
  emit_gap "(b) no Bash()/PowerShell() allow rule covers '$verb'. Apply the fleet permission floor operator-side (standards components/claude-permissions, composed into settings via dotfiles#233) — never a plugin self-grant. See reference/permission-preflight.md."
done

if [[ -n "$worktree_root" ]]; then
  if ! dir_covered "$worktree_root"; then
    emit_gap "(c) no permissions.additionalDirectories entry covers the worktree root '$worktree_root'; every out-of-tree write will prompt. Add it operator-side. See reference/permission-preflight.md."
  fi
else
  emit_note "(c) worktree root not provided (--worktree-root / PREFLIGHT_WORKTREE_ROOT unset) — additionalDirectories coverage not checked. Pass the lane's out-of-tree worktree root to verify it."
fi

if [[ "$mode" == "count" ]]; then
  printf '%s\n' "$gapcount"
  exit 0
fi

if [[ "$layout" == "per-worktree" ]]; then
  echo "PREFLIGHT: per-worktree approvals layout ($layout_causes) — Claude Code keeps an approval with the worktree it was granted in, so the main checkout's settings.local.json is not credited to a worktree; only the worktree's own local file is. Deny rules still include the main checkout's file."
elif [[ -n "$layout_unread" ]]; then
  echo "PREFLIGHT: UNREAD LAYER — the main checkout's settings.local.json was not credited: whether Claude Code shares approvals through the repository root here cannot be determined ($layout_reason). A grant there is not credited (a verb may be over-reported as a gap); deny rules still include it. Findings below are incomplete."
fi

if [[ "$cov_local" == "no-local" ]]; then
  if [[ -n "$main_is_proj_base" && "$layout" == "shared" ]]; then
    echo "PREFLIGHT: autonomous mode (--worktree-root, no distinct --project-root) — coverage read includes this main checkout's settings.local.json: where approvals save at the repository root its rules apply in every worktree, the fresh worker included."
  elif [[ "$main_state" == "verified" && "$layout" == "shared" ]]; then
    echo "PREFLIGHT: autonomous mode (--worktree-root, no distinct --project-root) — coverage read includes the main checkout's settings.local.json ('$main_root', shared across worktrees where approvals save at the repository root) but excludes this worktree's own local file, which a fresh worker would not inherit; deny rules still include it."
  else
    echo "PREFLIGHT: autonomous mode (--worktree-root, no distinct --project-root) — coverage read excludes this checkout's gitignored settings.local.json, which a fresh worktree would not carry; deny rules still include it."
  fi
elif [[ -n "$distinct_project_root" ]]; then
  if [[ "$main_state" == "verified" && -z "$main_is_proj_base" && "$layout" == "shared" ]]; then
    echo "PREFLIGHT: reading project settings (incl. settings.local.json) from --project-root '$proj_base', plus the main checkout's shared settings.local.json ('$main_root')."
  else
    echo "PREFLIGHT: reading project settings (incl. settings.local.json) from --project-root '$proj_base'."
  fi
fi

if [[ "$main_state" == "unresolved" ]]; then
  echo "PREFLIGHT: UNREAD LAYER — the main checkout's settings.local.json was not read: $main_reason. Where approvals save at the repository root its rules apply in every worktree, so a grant there is not credited (a verb may be over-reported as a gap) and, worse, a deny there is not reported at all. Findings below are incomplete. Run the preflight from the main checkout, or pass --project-root naming it, to read that layer."
fi

if [[ "${#findings[@]}" -gt 0 ]]; then
  printf '%s\n' "${findings[@]}"
fi

if [[ "$main_state" == "unresolved" ]]; then
  echo "PREFLIGHT: INCOMPLETE — main-checkout layer unread ($main_reason); $gapcount gap(s) found among the layers that were read. Report-only: exit 0 regardless (see reference/permission-preflight.md)."
elif [[ -n "$layout_unread" ]]; then
  echo "PREFLIGHT: INCOMPLETE — approvals layout undeterminable ($layout_reason), main-checkout settings.local.json not credited; $gapcount gap(s) found among the layers that were read. Report-only: exit 0 regardless (see reference/permission-preflight.md)."
elif [[ "${#findings[@]}" -eq 0 ]]; then
  echo "PREFLIGHT: OK — cwd is a git repo, probed grants present, worktree root covered."
elif [[ "$gapcount" -eq 0 ]]; then
  echo "PREFLIGHT: OK — ${#findings[@]} note(s), 0 gap(s)."
else
  echo "PREFLIGHT: $gapcount gap(s) — remediate operator-side before the unattended loop; the assistant cannot self-apply (see reference/permission-preflight.md)."
fi
exit 0
