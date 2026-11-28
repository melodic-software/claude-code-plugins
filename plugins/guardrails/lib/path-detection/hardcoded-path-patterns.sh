# shellcheck shell=bash

# shellcheck source=machine-path-patterns.sh
source "${BASH_SOURCE[0]%/*}/machine-path-patterns.sh"

hpp::prefilter() {
  HPP_GATE=grep HPP_GATE_ROOT=""
  local content="$1" project_root="${2:-}" hpp_lc_set=${LC_ALL+x} hpp_lc=${LC_ALL-} hpp_nc=0
  local hpp_non_ascii=$'[!\x01-\x7f]' hpp_non_ascii_nl=$'[!\x01-\x09\x0b-\x7f]'
  if [[ -n "$project_root" ]]; then
    HPP_GATE_ROOT="${project_root//\\//}"
    HPP_GATE_ROOT="${HPP_GATE_ROOT%/}"
    HPP_GATE_ROOT="${HPP_GATE_ROOT##*/}"
  fi
  local hpp_attr=r
  if ((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 404)); then
    case $- in
    *u*)
      set +u
      eval 'hpp_attr=${LC_ALL@a}'
      set -u
      ;;
    *) eval 'hpp_attr=${LC_ALL@a}' ;;
    esac
  fi
  if [[ $hpp_attr != *r* ]]; then
    LC_ALL=C
    case $content in
    *Users* | */home/* | *repos* | *Repos* | *projects* | *Projects* | *dev* | *Dev*) HPP_GATE=scan ;;
    *$hpp_non_ascii*) ;;
    *)
      case $HPP_GATE_ROOT in
      *$hpp_non_ascii_nl*) ;;
      "") HPP_GATE=clean ;;
      *)
        shopt -q nocasematch && hpp_nc=1
        shopt -s nocasematch
        HPP_GATE=clean
        [[ $content == *"$HPP_GATE_ROOT"* ]] && HPP_GATE=scan
        ((hpp_nc)) || shopt -u nocasematch
        ;;
      esac
      ;;
    esac
    { if [[ -n "$hpp_lc_set" ]]; then LC_ALL=$hpp_lc; else unset LC_ALL; fi; } 2>/dev/null
  fi
}

hpp::_drop_exempt() {
  local cands="$1" exempt="$2" defused="$3" regex="$4" keep
  if [[ "$cands" != *"$exempt"* ]]; then
    printf '%s\n' "$cands" | head -3
    return 0
  fi
  keep=$(printf '%s\n' "$cands" |
    sed -e 's|^[0-9]*:||' -e "s|${exempt}\([^A-Za-z0-9._-]\)|${defused}\1|g" -e "s|${exempt}\$|${defused}|" |
    grep -nE "$regex" 2>/dev/null | cut -d: -f1 | head -3) || true
  printf '%s\n' "$cands" | awk -v keep="$keep" '
    BEGIN { n = split(keep, a, "\n"); for (i = 1; i <= n; i++) k[a[i]] = 1 }
    k[NR]' | head -3
}

hpp::scan_text() {
  local content="$1" project_root="${2:-}" file_path="${3:-}"
  local violations="" match cands re nl=$'\n'

  hpp::prefilter "$content" "$project_root"
  local hpp_gate=$HPP_GATE gate_root=$HPP_GATE_ROOT
  [[ $hpp_gate == clean ]] && return 0
  if [[ $hpp_gate == grep ]] && ! grep -qE -- 'Users|/home/|repos|Repos|projects|Projects|dev|Dev' < <(printf '%s' "$content") 2>/dev/null; then
    if [[ -z "$gate_root" ]] || ! grep -qFi -- "$gate_root" < <(printf '%s' "$content") 2>/dev/null; then
      return 0
    fi
  fi

  local norm_file="${file_path//\\//}"
  norm_file=$(printf '%s' "$norm_file" | tr '[:upper:]' '[:lower:]')

  local windows_context="" macos_context="" linux_context=""
  case "$norm_file" in
  *.ps1 | *.psm1 | *.psd1 | *.cmd | *.bat | *.reg | */scripts/windows/* | */tests/windows/* | *-windows.* | *-win32.*)
    windows_context=1
    ;;
  *) ;;
  esac
  case "$norm_file" in
  */scripts/macos/* | *-macos.* | *-osx.* | *-darwin.*) macos_context=1 ;;
  *) ;;
  esac
  case "$norm_file" in
  */scripts/linux/* | *-linux.*) linux_context=1 ;;
  *) ;;
  esac

  if [[ -z "$windows_context" ]]; then
    match=$(printf '%s' "$content" | grep -nE "$HPP_WIN_USER_BODY" 2>/dev/null | head -3)
    [[ -n "$match" ]] && violations+="Windows user path detected:${nl}${match}${nl}${nl}"
  fi

  local _posix_boundary="(^|[[:space:]\"'\`(=:]|file://)"

  if [[ -z "$macos_context" ]]; then
    re="${_posix_boundary}${HPP_MACOS_USER_BODY}"
    cands=$(printf '%s' "$content" | grep -nE "$re" 2>/dev/null | grep -vE '[A-Za-z]:[/\\]') || true
    if [[ -n "$cands" ]]; then
      match=$(hpp::_drop_exempt "$cands" '/Use''rs/Shared' '/Use''rs-Shared' "$re")
      [[ -n "$match" ]] && violations+="macOS user path detected:${nl}${match}${nl}${nl}"
    fi
  fi

  if [[ -z "$linux_context" ]]; then
    re="${_posix_boundary}${HPP_LINUX_USER_BODY}"
    cands=$(printf '%s' "$content" | grep -nE "$re" 2>/dev/null) || true
    if [[ -n "$cands" ]]; then
      match=$(hpp::_drop_exempt "$cands" '/ho''me/runner' '/ho''me-runner' "$re")
      [[ -n "$match" ]] && violations+="Linux user path detected:${nl}${match}${nl}${nl}"
    fi
  fi

  if [[ -z "$windows_context" ]]; then
    match=$(printf '%s' "$content" | grep -nE "$HPP_WIN_REPO_BODY" 2>/dev/null | head -3)
    [[ -n "$match" ]] && violations+="Windows repo path detected:${nl}${match}${nl}${nl}"

    match=$(printf '%s' "$content" | grep -nE "$HPP_ESCAPED_WIN_REPO_BODY" 2>/dev/null | head -3)
    [[ -n "$match" ]] && violations+="Escaped Windows repo path detected:${nl}${match}${nl}${nl}"
  fi

  if [[ -n "$project_root" ]]; then
    local root_fwd root_bslash root_escaped candidate
    root_fwd=${project_root//\\//}
    root_fwd=${root_fwd%/}
    root_bslash=${root_fwd//\//\\}
    root_escaped=${root_bslash//\\/\\\\}

    for candidate in "$root_fwd" "$root_bslash" "$root_escaped"; do
      [[ -n "$candidate" ]] || continue
      match=$(printf '%s' "$content" | grep -nFi -- "$candidate" 2>/dev/null | head -3)
      [[ -n "$match" ]] && violations+="Machine-specific repo path detected:${nl}${match}${nl}${nl}"
    done
  fi

  [[ -n "$violations" ]] || return 0
  printf '%s' "$violations"
  return 1
}

# shellcheck disable=SC2034  # SCAN_ROOT is the caller's result
hpp::resolve_scan_root() {
  local root="$1" toplevel tl_norm="" home_norm=""
  SCAN_ROOT=""
  [[ -n "$root" ]] || return 0
  if (($# > 1)); then
    toplevel=$2
  else
    toplevel="$(hook::git_untrusted_exec -C "$root" rev-parse --show-toplevel 2>/dev/null)"
  fi
  [[ -n "$toplevel" ]] || return 0
  hook::normalize_path_to tl_norm "$toplevel"
  tl_norm="${tl_norm%/}"
  hook::normalize_path_to home_norm "${HOME:-${USERPROFILE:-}}"
  home_norm="${home_norm%/}"
  [[ -n "$home_norm" && ("$tl_norm" == "$home_norm" || "$home_norm" == "$tl_norm"/*) ]] || SCAN_ROOT="$root"
}
