#!/bin/sh
# shellcheck shell=bash

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=powershell-format
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=powershell
PSF_SETTINGS=PSScriptAnalyzerSettings.psd1
PSF_INSTALL='see https://learn.microsoft.com/powershell/scripting/install/installing-powershell'
PSF_INSTALL_MOD='pwsh -Command Install-Module PSScriptAnalyzer -Scope CurrentUser'
case "${BASH_SOURCE[0]}" in
*/*) PSF_HERE="${BASH_SOURCE[0]%/*}" ;;
*) PSF_HERE=. ;;
esac

rt_wants() {
  case "$1" in
  .githooks/* | *$'\n'*) return 1 ;;
  *.ps1 | *.psm1 | *.psd1) return 0 ;;
  *) return 1 ;;
  esac
}

psf__walk() {
  local dir="$1"
  while :; do
    if [[ -f "$dir/$PSF_SETTINGS" ]]; then
      PSF_DIR="$dir"
      return 0
    fi
    [[ "$dir" == "$2" || "$dir" != */* ]] && return 1
    dir="${dir%/*}"
    [[ -n "$dir" ]] || return 1
  done
}

psf__detail() {
  local rel="${1#"$2"}"
  rel="${rel#/}"
  RT_DETAIL="config ${rel:+$rel/}$PSF_SETTINGS; binary pwsh on PATH"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entries
rt_adapter() {
  local f="$2"
  [[ "$f" == /* || "$f" == [A-Za-z]:[\\/]* ]] || f="$3/$f"
  f="${f%/*}"
  psf__walk "$f" "$3" || return 1
  RT_ADAPTER=psscriptanalyzer RT_TOOL=pwsh RT_BIN=pwsh RT_DIR="$PSF_DIR" RT_INSTALL="$PSF_INSTALL"
  RT_CONFIGS="$PSF_SETTINGS"
  psf__detail "$PSF_DIR" "$3"
  # shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN, PSF_PS1 and the files
  RT_SCRIPT='"$RT_BIN" -NoProfile -NonInteractive -File "$PSF_PS1" '"$1"' "$@"'
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() {
  local f dir="$2"
  if [[ ! -f "$2/$PSF_SETTINGS" ]]; then
    f="$(git -C "$2" ls-files -- ":(glob)**/$PSF_SETTINGS" 2>/dev/null | head -1)"
    if [[ -z "$f" ]]; then
      RT_DETAIL="no $PSF_SETTINGS"
      return 1
    fi
    dir="$2/${f%/*}"
  fi
  RT_ADAPTER=psscriptanalyzer RT_TOOL=pwsh RT_BIN=pwsh
  psf__detail "$dir" "$2"
}

psf_pwsh_path() {
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32) command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" 2>/dev/null && return ;;
  *) ;;
  esac
  printf '%s' "$1"
}

psf_init() {
  local common
  PSF_ROOT="$1"
  PSF_STATE=""
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [[ -z "$common" ]] || PSF_STATE="$common/powershell-format"
  if [[ "$PSF_STATE" == [A-Za-z]:\\* ]] && command -v cygpath >/dev/null 2>&1; then
    PSF_STATE="$(cygpath -u "$PSF_STATE" 2>/dev/null || printf '%s' "$PSF_STATE")"
  fi
  PSF_STATE_ARG=""
  [[ -z "$PSF_STATE" ]] || PSF_STATE_ARG="$(psf_pwsh_path "$PSF_STATE")"
  PSF_ROOT_ARG="$(psf_pwsh_path "$1")"
  [[ "$PSF_HERE" == /* || "$PSF_HERE" == [A-Za-z]:[\\/]* ]] || PSF_HERE="$PWD/$PSF_HERE"
  PSF_PS1_ARG="$(psf_pwsh_path "$PSF_HERE/psscriptanalyzer.ps1")"
  PSF_LINT_CACHE=""
  common="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
  [[ -z "$common" ]] || PSF_LINT_CACHE="$common/powershell-format-lint"
  psf__path_without_9p
}

psf__path_without_9p() {
  local mnt type m d parts=() mounts=() keep=() tab="${PSF_MOUNTS:-/proc/self/mounts}"
  PSF_PATH="$PATH" PSF_BIN="${RT_BIN:-pwsh}"
  [[ -r "$tab" ]] || return 0
  while read -r _ mnt type _; do
    [[ "$type" == 9p ]] && mounts+=("$mnt")
  done <"$tab"
  ((${#mounts[@]})) || return 0
  IFS=: read -ra parts <<<"$PATH"
  for d in "${parts[@]}"; do
    for m in "${mounts[@]}"; do
      [[ "$d" == "$m" || "$d" == "$m"/* ]] && continue 2
    done
    keep+=("$d")
  done
  PSF_BIN="$(command -v "$PSF_BIN" 2>/dev/null || printf "%s" "$PSF_BIN")"
  PSF_PATH="$(IFS=:; printf '%s' "${keep[*]}")"
}

psf_settings_rel() {
  local rel="${RT_DIR#"$PSF_ROOT"}"
  rel="${rel#/}"
  printf '%s' "${rel:+$rel/}$PSF_SETTINGS"
}

psf_run() {
  local dir="$RT_DIR" rc
  RT_DIR="$1"
  shift
  PATH="$PSF_PATH" RT_BIN="$PSF_BIN" PSF_PS1="$PSF_PS1_ARG" PSSA_LINT_OUT="${PSF_LINT_OUT:+$(psf_pwsh_path "$PSF_LINT_OUT")}" \
    PSSA_SETTINGS="$(psf_pwsh_path "$dir/$PSF_SETTINGS")" PSSA_REPO_ROOT="$PSF_ROOT_ARG" PSSA_STATE_BASE="$PSF_STATE_ARG" rt_run "$@"
  rc=$?
  RT_DIR="$dir"
  return "$rc"
}

psf_module_missing() {
  if checks_skip_listed PSScriptAnalyzer; then
    printf 'SKIPPED: PSScriptAnalyzer (missing)\n' >&2
    return 1
  fi
  if checks_is_agent; then
    printf 'FAIL: PSScriptAnalyzer missing. Install: %s\n' "$PSF_INSTALL_MOD" >&2
    printf 'To skip only while PSScriptAnalyzer is missing: git -c checks.skipmissing=PSScriptAnalyzer %s ...\n' "$(checks_git_verb)" >&2
    return 2
  fi
  printf 'NOTICE: PSScriptAnalyzer missing, so this check did not run. Install: %s\n' "$PSF_INSTALL_MOD" >&2
  return 1
}

psf_trust_notice() {
  local line verdict="" marker="" msg settings
  settings="$(psf_settings_rel)"
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
    "PSSA_TRUST GATE "*)
      verdict=GATE
      marker="${line#PSSA_TRUST GATE }"
      ;;
    "PSSA_TRUST NOSTORE") verdict=NOSTORE ;;
    "PSSA_TRUST UNVERIFIABLE") verdict=UNVERIFIABLE ;;
    "PSSA_TRUST UNPINNABLE") verdict=UNPINNABLE ;;
    *) ;;
    esac
  done <"$1"
  msg="powershell-format trust gate: $2 skipped for files under $settings;"
  case "$verdict" in
  GATE)
    msg="$msg it loads repository rule modules and is not approved. Approval is the user's."
    if ! checks_is_agent && [[ -n "$PSF_STATE" && -n "$marker" ]]; then
      msg="$msg Review that file and every rule module it references, then run: mkdir -p '${PSF_STATE%/}/trust-approvals/$marker' (any change to them revokes the approval)."
    fi
    ;;
  UNVERIFIABLE) msg="$msg it cannot be verified free of repository rule modules, so $2 stays off." ;;
  UNPINNABLE) msg="$msg a rule module it references loads code no approval can pin, so $2 stays off." ;;
  *) msg="$msg it loads repository rule modules and there is no approval store, so $2 stays off." ;;
  esac
  printf '%s\n' "$msg" >&2
}

psf_broken() {
  printf 'powershell-format: %s failed under %s:\n' "$2" "$(psf_settings_rel)" >&2
  sed -e 's/^PSSA_ERROR //' -e 's/\r$//' "$1" >&2
}

psf_lint_key() {
  local dir=$1
  shift
  { printf '%s\n' "$dir" "$@" && git hash-object -- "$dir/$PSF_SETTINGS" "$@"; } | git hash-object --stdin
}

psf_lint_off() {
  local f v
  v="$(git config --type=bool --get checks.powershell-format.lint.declined 2>/dev/null)" ||
    v="$(git config --type=bool --get checks.powershell-format.powershell-check.declined 2>/dev/null)" ||
    v="$(git config --type=bool --get checks.git-hooks.declined 2>/dev/null)"
  [[ "$v" == true ]] && return 0
  for f in lefthook-local.yml lefthook-local.yaml .lefthook-local.yml .lefthook-local.yaml; do
    [[ -f "$f" ]] && psf__job_skipped powershell-format-remote-lint <"$f" && return 0
  done
  return 1
}

psf__job_skipped() {
  awk -v job="$1" '
    function close_items(min, d) {
      for (d = top; d >= min; d--) {
        if (open[d] && name[d] == job && tolower(skip[d]) == "true") found = 1
        open[d] = 0
      }
    }
    function scalar(v) {
      sub(/^[ \t]+/, "", v)
      if (v ~ /^"/) { sub(/^"/, "", v); sub(/".*$/, "", v); return v }
      if (v ~ /^\047/) { sub(/^\047/, "", v); sub(/\047.*$/, "", v); return v }
      sub(/[ \t]+#.*$/, "", v)
      sub(/[ \t]+$/, "", v)
      return v
    }
    function key(d, line, k) {
      k = line
      sub(/:.*/, "", k)
      sub(/^[^:]*:/, "", line)
      if (k == "name") name[d] = scalar(line)
      else if (k == "skip") skip[d] = scalar(line)
    }
    { sub(/\r$/, "") }
    /^[ \t]*(#|$)/ { next }
    {
      match($0, /^ */)
      ind = RLENGTH
      line = substr($0, ind + 1)
      if (line ~ /^- /) {
        close_items(ind)
        open[ind] = 1; name[ind] = ""; skip[ind] = ""
        if (ind > top) top = ind
        rest = substr(line, 3)
        sub(/^ +/, "", rest)
        if (rest ~ /^[A-Za-z_]+:/) key(ind, rest)
        next
      }
      close_items(ind - 1)
      if (ind >= 2 && open[ind - 2] && line ~ /^[A-Za-z_]+:/) key(ind - 2, line)
    }
    END { close_items(0); exit !found }
  '
}

psf_lint_store() {
  local rc=$1 out=$2 dir=$3 key r lrc=0
  shift 3
  [[ -n "$PSF_LINT_CACHE" && -n "${PSF_LINT_OUT:-}" ]] || return 0
  case $rc in
  0 | 4)
    [[ -f "$PSF_LINT_OUT.rc" ]] || return 0
    while IFS= read -r r || [[ -n "$r" ]]; do
      r="${r%$'\r'}"
      [[ "$r" =~ ^[0-9]+$ ]] || return 0
      ((r > lrc)) && lrc=$r
    done <"$PSF_LINT_OUT.rc"
    out="$PSF_LINT_OUT"
    ;;
  3 | 6) lrc=$rc ;;
  *) return 0 ;;
  esac
  key="$(psf_lint_key "$dir" "$@")" && [[ -n "$key" ]] || return 0
  mkdir -p "$PSF_LINT_CACHE" && cp "$out" "$PSF_LINT_CACHE/$key.out" &&
    printf '%s\n' "$lrc" >"$PSF_LINT_CACHE/$key.rc"
}

psf_lint_take() {
  local out=$1 key c
  shift
  [[ -n "$PSF_LINT_CACHE" && -d "$PSF_LINT_CACHE" ]] || return 1
  key="$(psf_lint_key "$@")" && [[ -n "$key" ]] || return 1
  c="$PSF_LINT_CACHE/$key"
  [[ -f "$c.rc" ]] || return 1
  PSF_LINT_RC=""
  read -r PSF_LINT_RC <"$c.rc"
  if [[ "$PSF_LINT_RC" =~ ^[0-9]+$ ]] && mv -f "$c.out" "$out"; then
    rm -f "$c.rc"
    return 0
  fi
  rm -f "$c.rc" "$c.out"
  return 1
}
