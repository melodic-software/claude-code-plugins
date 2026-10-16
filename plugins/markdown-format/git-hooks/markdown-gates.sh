#!/usr/bin/env bash
# Gates shared by the PostToolBatch rewrite (hooks/markdown-format.sh) and the
# pre-commit entry (git-hooks/markdown-check.sh), so both decide the same way
# which files markdownlint-cli2 may touch and which binary runs. Sourced, never
# run; the installer copies it beside the entry script.
#
#   md_config_state <file> <root>   set MD_STATE for the file: "none" when no
#                                   markdownlint config governs it, "plain" when
#                                   one does, "code" when a governing config can
#                                   run repository code (MD_CODE_CONFIGS lists
#                                   those configs)
#   md_trust <root>                 after a "code" state, set MD_TRUST to
#                                   approved, gate, nostore, unverifiable or
#                                   unpinnable, and MD_TRUST_DIR to the approval
#                                   directory for gate and approved
#   md_local_bin <dir> <root>       print a repo-local node_modules/.bin shim
#                                   whose physical target stays inside <root>
#
# A markdownlint config is the opt-in: markdownlint-cli2 ships a default rule
# set, so a run without one would impose a style the repository never chose.
# The candidates are the files markdownlint-cli2 discovers on its own (its README
# "Configuration" section); a package.json property is honored only under an
# explicit --config flag, so it is no opt-in.
#
# A config that can run code (.cjs or .mjs, or customRules, markdownItPlugins and
# outputFormatters keys) runs only once the user approves its exact content
# state. The key test is a plain-text over-approximation, so a double-quoted
# string holding a backslash, or a YAML escape or tag able to spell a key
# differently, counts as code too, and as unverifiable: text whose meaning the
# scan cannot read gets no approval route.

# md_classify <config>: 0 and the config added to MD_CODE_CONFIGS when it can
# run code, with MD_TRUST_BLOCK set when no approval can cover it; 1 otherwise.
md_classify() {
  local code=1
  case "$1" in
    *.cjs | *.mjs)
      code=0
      # An executable cli2 config resolves these keys' entries itself, from any
      # expression that yields a string, so the module scan cannot pin them.
      case "${1##*/}" in
        .markdownlint-cli2.*)
          if grep -Eq 'customRules|markdownItPlugins|outputFormatters' "$1" 2>/dev/null; then
            [[ -n "$MD_TRUST_BLOCK" ]] || MD_TRUST_BLOCK=unpinnable
          fi
          ;;
        *) ;;
      esac
      ;;
    *markdownlint-cli2.jsonc | *markdownlint-cli2.yaml)
      grep -Eq 'customRules|markdownItPlugins|outputFormatters' "$1" 2>/dev/null && code=0
      if grep -Eq $'"[^"]*\\\\' "$1" 2>/dev/null; then
        code=0
        MD_TRUST_BLOCK=unverifiable
      fi
      case "$1" in
        *.yaml)
          if grep -Eq '\\$|!![A-Za-z]' "$1" 2>/dev/null; then
            code=0
            MD_TRUST_BLOCK=unverifiable
          fi
          ;;
        *) ;;
      esac
      ;;
    *) ;;
  esac
  ((code == 0)) || return 1
  MD_CODE_CONFIGS+=("$1")
}

# The first config of each family wins in a directory, as markdownlint-cli2
# resolves it, so a shadowed executable config does not count.
md_scan_dir() {
  local c
  for c in .markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.cjs .markdownlint-cli2.mjs; do
    if [[ -f "$1/$c" ]]; then
      md_note_config "$1/$c"
      break
    fi
  done
  for c in .markdownlint.jsonc .markdownlint.json .markdownlint.yaml .markdownlint.yml .markdownlint.cjs .markdownlint.mjs; do
    if [[ -f "$1/$c" ]]; then
      md_note_config "$1/$c"
      break
    fi
  done
}

md_note_config() {
  if md_classify "$1"; then
    MD_STATE=code
  elif [[ "$MD_STATE" != code ]]; then
    MD_STATE=plain
  fi
}

# Walks from the file's directory up to <root> inclusive; <root> is "." for a
# repo-relative path or an absolute directory the file lies under. A directory
# above the root is never read: a walk past the repository would adopt someone
# else's config as this repository's opt-in.
md_config_state() {
  local dir="${1%/*}" root="$2"
  [[ "$dir" == "$1" ]] && dir=.
  MD_STATE=none
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

# md_abs <path>: the physical absolute path, its directory resolved through
# symlinks; 1 when the directory does not resolve.
md_abs() {
  local d="${1%/*}"
  [[ "$d" == "$1" ]] && d=.
  [[ -n "$d" ]] || d=/
  d="$(cd -P -- "$d" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s' "${d%/}" "${1##*/}"
}

# md_unpinnable_js <file>: 0 when a JS source names code this text scan cannot
# pin to a file. Path-building machinery anywhere (the path module, string
# concatenation, a template, __dirname, process.*) refuses it, as does a loader
# call left over once every plainly written require("x") or import("x") is
# deleted: a loader the plain pattern did not consume takes an argument the scan
# cannot read. A letter-capable escape in a string refuses it too, since Node
# decodes it to another path, and so does a "#" specifier, which package.json
# "imports" maps to a file the scan never sees. POSIX ERE only, no \b, so BSD grep reads it alike.
# Deliberately over-approximating: the cost of a false refusal is a skipped run.
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

# md_collect_modules <physical root> <config>...: add to MD_MODULES every
# repository file the configs could load, so the approval covers the code that
# would run and not only the config naming it. Resolving the real module graph
# would mean running Node, the thing being gated, so every string literal and
# path-shaped bare token is tried as a path from the file's directory and from
# the root, with Node's extension and directory-entry candidates, and each hit is
# scanned the same way in turn (at most 64 files). 1, with MD_TRUST_BLOCK set to
# unpinnable, for a JS source md_unpinnable_js refuses, a symlinked module, or a
# module that resolves outside the root: no signature over repository content
# covers those. A bare package name resolves to node_modules, which the user
# installs separately, so it stays outside the signature.
md_collect_modules() {
  local root="$1" item dir str tag base cand res scanned=0
  local seen_scan=$'\n' seen_mod=$'\n' queue=()
  shift
  for item in "$@"; do
    # A symlinked config loads its requires from the link target's directory,
    # which the scan below would not read.
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

# md_trust <root>: judge the code-capable configs the last md_config_state
# found. The approval store is markdown-format/ under the repository's git
# common directory, so the batch row, the Stop row and every commit read one
# store; CLAUDE_PLUGIN_DATA is not used, since an agent's shell can carry
# another plugin's value. The approval is a directory there named for a signature over the root, every config and every
# module md_collect_modules reaches, so a change to any of them, a branch switch
# included, revokes it. Only the user creates that directory: the pre-commit
# entry never hands an agent the command. Verdicts are cached per config set.
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
    if common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
      base="$common/markdown-format"
    fi
    if [[ "$base" == [A-Za-z]:\\* ]] && command -v cygpath >/dev/null 2>&1; then
      base="$(cygpath -u "$base" 2>/dev/null)" || base=""
    fi
    [[ -n "$base" ]] || MD_TRUST=nostore
  fi
  if [[ -z "$MD_TRUST" ]]; then
    if sig="$(
      printf '%s\n' "$root"
      for f in "${MD_CODE_CONFIGS[@]}"; do
        f="$(md_abs "$f")" || exit 1
        h="$(git hash-object --no-filters -- "$f")" || exit 1
        printf 'config\t%s\t%s\n' "$f" "$h"
      done
      if ((${#MD_MODULES[@]} > 0)); then
        for f in "${MD_MODULES[@]}"; do
          h="$(git hash-object --no-filters -- "$f")" || exit 1
          printf 'module\t%s\t%s\n' "$f" "$h"
        done
      fi
    )" && sig="$(git hash-object --no-filters --stdin <<<"$sig")" && [[ -n "$sig" ]]; then
      MD_TRUST_DIR="${base%/}/trust-approvals/md-$sig"
      MD_TRUST=gate
      [[ -d "$MD_TRUST_DIR" ]] && MD_TRUST=approved
    else
      MD_TRUST=unverifiable
    fi
  fi
  MD_TRUST_CACHE+="$key"$'\t'"$MD_TRUST"$'\t'"$MD_TRUST_DIR"$'\n'
}

# Walks from <dir> up to <root>, so a monorepo workspace install is found. A
# shim is accepted only after its symlinks are followed and the physical target
# lies in this repository's node_modules tree, which rejects a checked-in or
# replaced .bin symlink that points out of the repository.
md_local_bin() {
  local dir="$1" root cand target link tdir here parent depth
  root="$(cd -P -- "$2" 2>/dev/null && pwd -P)" || return 1
  while :; do
    cand="$dir/node_modules/.bin/markdownlint-cli2"
    # A node_modules the repository commits is its code, not the user's install.
    if [[ -f "$cand" && -x "$cand" && -z "$(git -C "$dir" ls-files -- ':(literal)node_modules' 2>/dev/null)" ]]; then
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
