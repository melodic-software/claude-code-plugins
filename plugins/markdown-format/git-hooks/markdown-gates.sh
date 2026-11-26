#!/usr/bin/env bash
md_classify() {
  local code=1
  case "$1" in
    *.cjs | *.mjs)
      code=0
      if [[ "${1##*/}" == .markdownlint-cli2.* && -z "$MD_TRUST_BLOCK" ]] &&
        grep -Eq 'customRules|markdownItPlugins|outputFormatters' "$1" 2>/dev/null; then
        MD_TRUST_BLOCK=unpinnable
      fi
      ;;
    *markdownlint-cli2.jsonc | *markdownlint-cli2.yaml)
      grep -Eq 'customRules|markdownItPlugins|outputFormatters' "$1" 2>/dev/null && code=0
      if grep -Eq $'"[^"]*\\\\' "$1" 2>/dev/null; then
        code=0
        MD_TRUST_BLOCK=unverifiable
      fi
      if [[ "$1" == *.yaml ]] && grep -Eq '\\$|!![A-Za-z]' "$1" 2>/dev/null; then
        code=0
        MD_TRUST_BLOCK=unverifiable
      fi
      ;;
    *) ;;
  esac
  ((code == 0)) || return 1
  MD_CODE_CONFIGS+=("$1")
}

md_scan_dir() {
  md_scan_family "$1" .markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.cjs .markdownlint-cli2.mjs
  md_scan_family "$1" .markdownlint.jsonc .markdownlint.json .markdownlint.yaml .markdownlint.yml .markdownlint.cjs .markdownlint.mjs
}

md_scan_family() {
  local dir="$1" c
  shift
  for c in "$@"; do
    if [[ -f "$dir/$c" ]]; then
      md_note_config "$dir/$c"
      return 0
    fi
  done
}

md_note_config() {
  [[ -n "$MD_NEAREST" ]] || MD_NEAREST="$1"
  if md_classify "$1"; then
    MD_STATE=code
  elif [[ "$MD_STATE" != code ]]; then
    MD_STATE=plain
  fi
}

md_config_state() {
  local dir="${1%/*}" root="$2"
  [[ "$dir" == "$1" ]] && dir=.
  MD_STATE=none
  MD_NEAREST=""
  MD_CODE_CONFIGS=()
  MD_TRUST_BLOCK=""
  if [[ "$root" != . ]]; then
    case "$dir/" in
      "${root%/}"/*) ;;
      *) return 0 ;;
    esac
  fi
  while :; do
    md_scan_dir "$dir"
    [[ "$dir" == "$root" || "$dir" == . || "$dir" == / ]] && break
    case "$dir" in
      */*)
        dir="${dir%/*}"
        [[ -n "$dir" ]] || dir=/
        ;;
      *) dir=. ;;
    esac
  done
}

md_abs() {
  local d="${1%/*}"
  [[ "$d" == "$1" ]] && d=.
  [[ -n "$d" ]] || d=/
  d="$(cd -P -- "$d" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s' "${d%/}" "${1##*/}"
}

md_unpinnable_js() {
  grep -Eq \
    -e "(require[[:space:]]*\([[:space:]]*|from[[:space:]]*)[\"'](node:)?path[\"']" \
    -e "(require[[:space:]]*\([[:space:]]*|import[[:space:]]*\([[:space:]]*|from[[:space:]]*)[\"']#" \
    -e 'path[[:space:]]*\.[[:space:]]*(join|resolve|normalize)[[:space:]]*\(' \
    -e 'require[[:space:]]*\.[[:space:]]*resolve[[:space:]]*\(' \
    -e 'import[[:space:]]*\.[[:space:]]*meta' \
    -e 'process[[:space:]]*\.' \
    -e '__dirname|__filename' \
    -e '\$\{' \
    -e "[\"'][[:space:]]*\+|\+[[:space:]]*[\"']" \
    -e "[\"'][^\"']*\\\\[uxUX0-7]" \
    "$1" 2>/dev/null && return 0
  grep -Eq "(^|[^A-Za-z0-9_\$])(require($|[^A-Za-z0-9_\$])|import[[:space:]]*\()" \
    < <(sed -E "s/(require|import)[[:space:]]*\([[:space:]]*(\"[^\"]*\"|'[^']*')/ /g" "$1" 2>/dev/null)
}

md_collect_modules() {
  local root="$1" item dir str tag base cand res scanned=0
  local seen_scan=$'\n' seen_mod=$'\n' queue=()
  shift
  for item in "$@"; do
    if [[ -L "$item" ]]; then
      MD_TRUST_BLOCK=unpinnable
      return 1
    fi
    res="$(md_abs "$item")" || return 1
    queue+=("$res")
  done
  while ((${#queue[@]} > 0)); do
    item="${queue[0]}"
    if ((${#queue[@]} > 1)); then queue=("${queue[@]:1}"); else queue=(); fi
    case "$seen_scan" in *$'\n'"$item"$'\n'*) continue ;; *) ;; esac
    seen_scan+="$item"$'\n'
    scanned=$((scanned + 1))
    if ((scanned > 64)); then
      MD_TRUST_BLOCK=unpinnable
      return 1
    fi
    case "$item" in
      *.cjs | *.mjs | *.js)
        if md_unpinnable_js "$item"; then
          MD_TRUST_BLOCK=unpinnable
          return 1
        fi
        ;;
      *) ;;
    esac
    dir="${item%/*}"
    while IFS= read -r str; do
      tag="${str:0:1}"
      str="${str:1}"
      if [[ "$tag" == Q ]]; then
        str="${str#?}"
        str="${str%?}"
      else
        case "$str" in */* | *.*) ;; *) continue ;; esac
      fi
      [[ -n "$str" ]] || continue
      for base in "$dir/$str" "$root/$str"; do
        for cand in "$base" "$base.cjs" "$base.mjs" "$base.js" "$base.json" "$base.node" \
          "$base/package.json" "$base/index.js" "$base/index.cjs" "$base/index.mjs"; do
          [[ -f "$cand" ]] || continue
          if [[ -L "$cand" ]]; then
            MD_TRUST_BLOCK=unpinnable
            return 1
          fi
          res="$(md_abs "$cand")" || continue
          case "$res" in
            "$root"/*) ;;
            *)
              MD_TRUST_BLOCK=unpinnable
              return 1
              ;;
          esac
          case "$seen_mod" in
            *$'\n'"$res"$'\n'*) ;;
            *)
              seen_mod+="$res"$'\n'
              MD_MODULES+=("$res")
              queue+=("$res")
              ;;
          esac
        done
      done
    done < <(
      grep -oE "\"[^\"]+\"|'[^']+'" "$item" 2>/dev/null | sed 's/^/Q/'
      grep -oE '[A-Za-z0-9_.@~/+-]+' "$item" 2>/dev/null | sed 's/^/P/'
    )
  done
  return 0
}

MD_TRUST_CACHE=$'\n'
md_trust() {
  local root key hit base common sig f h
  MD_TRUST="" MD_TRUST_DIR=""
  key="$1|${MD_TRUST_BLOCK}|${MD_CODE_CONFIGS[*]}"
  case "$MD_TRUST_CACHE" in
    *$'\n'"$key"$'\t'*)
      hit="${MD_TRUST_CACHE#*$'\n'"$key"$'\t'}"
      hit="${hit%%$'\n'*}"
      MD_TRUST="${hit%%$'\t'*}"
      MD_TRUST_DIR="${hit#*$'\t'}"
      return 0
      ;;
    *) ;;
  esac
  MD_TRUST="$MD_TRUST_BLOCK"
  if [[ -z "$MD_TRUST" ]]; then
    MD_MODULES=()
    if ! root="$(cd -P -- "$1" 2>/dev/null && pwd -P)"; then
      MD_TRUST=unverifiable
    elif ! md_collect_modules "$root" "${MD_CODE_CONFIGS[@]}"; then
      MD_TRUST="${MD_TRUST_BLOCK:-unpinnable}"
    fi
  fi
  if [[ -z "$MD_TRUST" ]]; then
    base=""
    if common="$(rt_git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
      base="$common/markdown-format"
    fi
    if [[ "$base" == [A-Za-z]:[\\/]* ]] && command -v cygpath >/dev/null 2>&1; then
      base="$(cygpath -u "$base" 2>/dev/null)" || base=""
    fi
    [[ -n "$base" ]] || MD_TRUST=nostore
  fi
  if [[ -z "$MD_TRUST" ]]; then
    if sig="$(
      printf '%s\n' "$root"
      for f in "${MD_CODE_CONFIGS[@]}"; do
        f="$(md_abs "$f")" || exit 1
        h="$(rt_git hash-object --no-filters -- "$f")" || exit 1
        printf 'config\t%s\t%s\n' "$f" "$h"
      done
      if ((${#MD_MODULES[@]} > 0)); then
        for f in "${MD_MODULES[@]}"; do
          h="$(rt_git hash-object --no-filters -- "$f")" || exit 1
          printf 'module\t%s\t%s\n' "$f" "$h"
        done
      fi
    )" && sig="$(rt_git hash-object --no-filters --stdin <<<"$sig")" && [[ -n "$sig" ]]; then
      MD_TRUST_DIR="${base%/}/trust-approvals/md-$sig"
      MD_TRUST=gate
      [[ -d "$MD_TRUST_DIR" ]] && MD_TRUST=approved
    else
      MD_TRUST=unverifiable
    fi
  fi
  MD_TRUST_CACHE+="$key"$'\t'"$MD_TRUST"$'\t'"$MD_TRUST_DIR"$'\n'
}

md_local_bin() {
  local dir="$1" root cand target link tdir here parent depth
  root="$(cd -P -- "$2" 2>/dev/null && pwd -P)" || return 1
  while :; do
    cand="$dir/node_modules/.bin/markdownlint-cli2"
    if [[ -f "$cand" && -x "$cand" && -z "$(rt_git -C "$dir" ls-files -- ':(literal)node_modules' 2>/dev/null)" ]]; then
      target="$cand"
      depth=0
      while [[ -L "$target" ]]; do
        depth=$((depth + 1))
        ((depth <= 32)) || return 1
        link="$(readlink "$target" 2>/dev/null)" || return 1
        case "$link" in
          /*) target="$link" ;;
          *) target="${target%/*}/$link" ;;
        esac
      done
      if [[ -f "$target" && -x "$target" ]]; then
        tdir="$(cd -P -- "${target%/*}" 2>/dev/null && pwd -P)" || tdir=""
        case "$tdir/${target##*/}" in
          "$root"/node_modules/* | "$root"/*/node_modules/*)
            printf '%s' "$cand"
            return 0
            ;;
          *) ;;
        esac
      fi
    fi
    here="$(cd -P -- "$dir" 2>/dev/null && pwd -P)" || return 1
    [[ "$here" == "$root" || "$here" == / ]] && return 1
    case "$dir" in
      */*)
        parent="${dir%/*}"
        [[ -n "$parent" ]] || parent=/
        ;;
      *) parent=. ;;
    esac
    [[ "$parent" == "$dir" ]] && return 1
    dir="$parent"
  done
}
