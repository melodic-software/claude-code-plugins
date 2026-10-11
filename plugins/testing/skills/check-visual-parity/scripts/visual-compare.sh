#!/usr/bin/env bash
# Pixel comparison for /testing:check-visual-parity, and the reader of its
# pixel_tolerance setting.
#
# Usage:
#   visual-compare.sh install [--deps-dir <base>] [--dry-run]
#   visual-compare.sh config --repo <dir> [--user pixel_tolerance=<value>]
#   visual-compare.sh manifest --dir <d> --browser <name and version> --viewport <W>x<H> --scale <n>
#   visual-compare.sh compare --baseline <d> --after <d> --tolerance <n> [--reason <text>]
#                             --diff-dir <d> [--deps-dir <base>] [--dry-run]
#   visual-compare.sh --help
#
# install   Installs pixelmatch and pngjs from the committed lockfile with
#           `npm ci --ignore-scripts --no-audit --no-fund` into
#           <base>/visual-compare/<first 12 hex of the lockfile's sha256>/,
#           through a sibling directory and a rename. The base is --deps-dir,
#           else $CLAUDE_PLUGIN_DATA when its last segment names testing, else
#           .work/testing in a marketplace checkout, else
#           <config dir>/plugins/data/testing-melodic-software. compare
#           installs the same way on first use.
# config    Prints `pixel_tolerance=<n> source=<layer> reason=<text>`. Layers:
#           the team docs/conventions/testing.yaml read from origin's default
#           branch (the working tree only when there is no origin),
#           ~/.claude/testing.yaml, <repo>/.claude/testing.local.yaml and the
#           --user option. The lowest valid value wins, so a personal layer can
#           lower the team value and never raise it. An invalid layer is named
#           on stderr and dropped; a config value never makes this exit 2.
# manifest  Writes <d>/manifest.json: the sha256 of every PNG in <d>, the OS,
#           browser, viewport, scale and `git rev-parse HEAD`. Refuses when the
#           file exists, so a baseline is never rewritten.
# compare   Checks every image against its manifest and the two manifests'
#           host fields, then prints per image
#           `differing=<n> tolerance=<t> verdict=<pass|fail> name=<image>`.
#           Diff images go under --diff-dir only. A tolerance above 0 needs
#           --reason.
# --dry-run Prints the install directory and the npm ci line, and installs,
#           writes and compares nothing.
#
# Exit: 0 done (compare: every image passed), 1 compare found a failing image,
# 2 usage error, a missing or broken install (with one repair line on stderr),
# or a manifest, hash or host mismatch.
set -uo pipefail

case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)" ;;
  *) SCRIPT_DIR="$(pwd)" ;;
esac
MJS="$SCRIPT_DIR/visual-compare.mjs"
PKG="$SCRIPT_DIR/package.json"
LOCK="$SCRIPT_DIR/package-lock.json"
PCV="$SCRIPT_DIR/../../../scripts/parse-concern-value.sh"
DATA_ID="testing-melodic-software"
NPM_FLAGS=(--ignore-scripts --no-audit --no-fund)

USAGE='usage: visual-compare.sh install [--deps-dir <base>] [--dry-run]
       visual-compare.sh config --repo <dir> [--user pixel_tolerance=<value>]
       visual-compare.sh manifest --dir <d> --browser <name and version> --viewport <W>x<H> --scale <n>
       visual-compare.sh compare --baseline <d> --after <d> --tolerance <n> [--reason <text>] --diff-dir <d> [--deps-dir <base>] [--dry-run]
       visual-compare.sh --help'

err() {
  printf 'visual-compare: %s\n' "$1" >&2
  exit 2
}
warn() { printf 'visual-compare: warning: %s\n' "$1" >&2; }
usage() { err "$1"$'\n'"$USAGE"; }

# need_value <flag> <argc>: the flag must be followed by a value.
need_value() { (($2 >= 2)) || usage "$1 needs a value"; }

# --- install ------------------------------------------------------------------

sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
psq() {
  local s="$1" c
  for c in "'" "‘" "’" "‚" "‛"; do s="${s//"$c"/"$c$c"}"; done
  printf "'%s'" "$s"
}

platform() {
  if [[ -n "${VISUAL_COMPARE_PLATFORM:-}" ]]; then
    printf '%s' "$VISUAL_COMPARE_PLATFORM"
  elif [[ "${OS:-}" == Windows_NT ]]; then
    printf 'win32'
  else
    printf 'posix'
  fi
}

lock_hash() {
  local h
  if command -v sha256sum >/dev/null 2>&1; then
    h="$(sha256sum "$LOCK")"
  else
    h="$(shasum -a 256 "$LOCK" 2>/dev/null)"
  fi || err "cannot hash $LOCK"
  h="${h:0:12}"
  [[ "$h" =~ ^[0-9a-f]{12}$ ]] || err "cannot hash $LOCK"
  printf '%s' "$h"
}

# checkout_root: the marketplace checkout this script runs from, when its .work/
# is gitignored.
checkout_root() {
  local root line
  root="$(cd "$SCRIPT_DIR/../../../../.." && pwd)" || return 1
  [[ -e "$root/.git" && -d "$root/.claude-plugin" && -f "$root/.gitignore" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == ".work/" || "$line" == ".work" ]]; then
      printf '%s' "$root"
      return 0
    fi
  done <"$root/.gitignore"
  return 1
}

# resolve_base <explicit>: sets BASE and RULE.
resolve_base() {
  local root data="${CLAUDE_PLUGIN_DATA:-}" name
  if [[ -n "$1" ]]; then
    BASE="$1" RULE="--deps-dir"
    return
  fi
  name="${data%/}"
  name="${name##*/}"
  if [[ -n "$data" && ("$name" == testing || "$name" == testing-*) ]]; then
    BASE="${data%/}" RULE="CLAUDE_PLUGIN_DATA"
  elif root="$(checkout_root)"; then
    BASE="$root/.work/testing" RULE="checkout .work/"
  else
    BASE="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/plugins/data/$DATA_ID" RULE="plugin data directory"
  fi
}

# wq <path>: a Windows path, PowerShell-quoted.
wq() {
  if command -v cygpath >/dev/null 2>&1; then psq "$(cygpath -w "$1")"; else psq "$1"; fi
}

repair_line() {
  local target="$1"
  if [[ "$(platform)" == win32 ]]; then
    printf "& { \$ErrorActionPreference = 'Stop'; Remove-Item -LiteralPath %s -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path %s | Out-Null; Copy-Item -LiteralPath %s, %s -Destination %s; npm.cmd ci --prefix %s %s }" \
      "$(wq "$target")" "$(wq "$target")" "$(wq "$PKG")" "$(wq "$LOCK")" "$(wq "$target")" "$(wq "$target")" "${NPM_FLAGS[*]}"
  else
    printf 'rm -rf %s && mkdir -p %s && cp %s %s %s/ && npm ci --prefix %s %s' \
      "$(sq "$target")" "$(sq "$target")" "$(sq "$PKG")" "$(sq "$LOCK")" "$(sq "$target")" "$(sq "$target")" "${NPM_FLAGS[*]}"
  fi
}

broken() {
  printf 'visual-compare: %s\nrepair: %s\n' "$1" "$(repair_line "$2")" >&2
  exit 2
}

need_node() {
  command -v node >/dev/null 2>&1 ||
    err "node is not on PATH; install Node.js (https://nodejs.org/en/download) and rerun. Reinstalling the packages would not help."
}

probe() { [[ -d "$1" ]] && node "$MJS" probe --deps "$1" >/dev/null 2>&1; }

# ensure_installed <target>: install the locked packages into <target> unless
# they already load there.
ensure_installed() {
  local target="$1" partial rc
  need_node
  probe "$target" && return 0
  command -v npm >/dev/null 2>&1 || broken "npm is not on PATH, so pixelmatch and pngjs cannot be installed (install Node.js, which ships npm)" "$target"
  # A killed install leaves a .partial- sibling; one older than 20 minutes is
  # no live npm ci.
  find "${target%/*}" -maxdepth 1 -name "${target##*/}.partial-*" -mmin +20 -exec rm -rf -- {} + 2>/dev/null
  partial="$target.partial-$$"
  rm -rf -- "$partial"
  if ! mkdir -p -- "$partial" || ! cp -- "$PKG" "$LOCK" "$partial/"; then
    broken "cannot create $partial" "$target"
  fi
  rc=0
  (cd -- "$partial" && npm ci "${NPM_FLAGS[@]}") >&2 || rc=$?
  if ((rc != 0)); then
    rm -rf -- "$partial"
    broken "npm ci failed (exit $rc)" "$target"
  fi
  if ! probe "$partial"; then
    rm -rf -- "$partial"
    broken "the installed packages do not load" "$target"
  fi
  [[ ! -e "$target" ]] || probe "$target" || rm -rf -- "$target"
  if [[ -e "$target" ]] || ! mv -- "$partial" "$target"; then
    # Another run finished first; its copy is accepted when it loads.
    rm -rf -- "$partial"
    probe "$target" || broken "cannot move the install into $target" "$target"
  fi
}

# install_target <explicit base>: sets TARGET.
install_target() {
  resolve_base "$1"
  TARGET="${BASE%/}/visual-compare/$(lock_hash)"
}

dry_run_report() {
  printf 'install_dir=%s\nchosen_by=%s\ninstalled=%s\nwould_run=npm ci %s (in a sibling of install_dir, then renamed into place)\n' \
    "$TARGET" "$RULE" "$([[ -d "$TARGET/node_modules" ]] && echo yes || echo no)" "${NPM_FLAGS[*]}"
}

cmd_install() {
  local deps="" dry=0
  while (($#)); do
    case "$1" in
      --deps-dir)
        need_value "$1" $#
        deps="$2"
        shift
        ;;
      --dry-run) dry=1 ;;
      *) usage "unknown argument to install: $1" ;;
    esac
    shift
  done
  install_target "$deps"
  if ((dry)); then
    dry_run_report
    return 0
  fi
  ensure_installed "$TARGET"
  printf 'install_dir=%s\nchosen_by=%s\ninstalled=yes\n' "$TARGET" "$RULE"
}

# --- config -------------------------------------------------------------------

# Each valid layer that sets pixel_tolerance.pixels lands in these arrays.
L_NAME=() L_LABEL=() L_PIXELS=() L_REASON=()

# under_link <file> <root>: true when <file>, or a directory above it inside
# <root>, is a symlink.
under_link() {
  local d="$1" root="$2"
  while [[ "$d" == "$root"/* ]]; do
    [[ ! -L "$d" ]] || return 0
    d="${d%/*}"
  done
  return 1
}

# pcv <where> <args...>: the shared reader, run in <where>.
pcv() {
  local where="$1"
  shift
  (cd -- "$where" && bash "$PCV" --strict "$@")
}

# has_children <where> <file> [--ref <ref>]: true when the layer holds any
# record under pixel_tolerance.pixels (a list or a map). The shared reader
# only answers exact keys, so this runs its parser on the same text.
has_children() {
  local where="$1" file="$2" text
  if (($# > 2)); then
    text="$(git -C "$where" show --end-of-options "$4:$file" 2>/dev/null)" || return 1
  else
    text="$(<"$file")" || return 1
  fi
  LC_ALL=C awk -f "${PCV%/*}/yaml-subset.awk" <<<"$text" |
    LC_ALL=C awk -F '\t' 'index($1, "pixel_tolerance.pixels.") == 1 { found = 1 } END { exit !found }'
}

# read_layer <name> <label> <where> <file> [--ref <ref>]: validate one layer
# and record it when it sets pixels.
read_layer() {
  local name="$1" label="$2" where="$3" file="$4" ref=() scalar items pixels reason
  shift 4
  ref=("$@")
  local failed="$label: the shared reader could not read this layer; this layer is dropped"
  scalar="$(pcv "$where" "${ref[@]}" "$file" pixel_tolerance)" ||
    {
      warn "$label: does not parse as YAML; this layer is dropped"
      return
    }
  items="$(pcv "$where" "${ref[@]}" --list "$file" pixel_tolerance)" || {
    warn "$failed"
    return
  }
  if [[ -n "$scalar" || -n "$items" ]]; then
    warn "$label: pixel_tolerance: '${scalar:-a list}' is not a map of pixels and reason; this layer is dropped"
    return
  fi
  if ! pixels="$(pcv "$where" "${ref[@]}" "$file" pixel_tolerance.pixels)" ||
    ! reason="$(pcv "$where" "${ref[@]}" "$file" pixel_tolerance.reason)"; then
    warn "$failed"
    return
  fi
  if [[ -z "$pixels" ]]; then
    if has_children "$where" "$file" "${ref[@]}"; then
      warn "$label: pixel_tolerance.pixels: '<list or map>' is not a whole number, 0 or more; this layer is dropped"
    fi
    return 0
  fi
  add_layer "$name" "$label" "pixel_tolerance.pixels" "$pixels" "$reason"
}

# add_layer <name> <label> <key> <pixels> <reason>
add_layer() {
  local name="$1" label="$2" key="$3" pixels="$4" reason="$5"
  if [[ ! "$pixels" =~ ^[0-9]{1,9}$ ]]; then
    warn "$label: $key: '$pixels' is not a whole number, 0 or more; this layer is dropped"
    return
  fi
  pixels=$((10#$pixels))
  if ((pixels > 0)) && [[ "$name" != user-option && -z "$reason" ]]; then
    warn "$label: pixel_tolerance.reason: '' is empty, and a layer whose pixels is above 0 needs a reason; this layer is dropped"
    return
  fi
  L_NAME+=("$name") L_LABEL+=("$label") L_PIXELS+=("$pixels") L_REASON+=("$reason")
}

# default_ref <repo>: origin's default branch as origin/<name>, or nothing.
default_ref() {
  local ref
  ref="$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || ref=""
  if [[ -z "$ref" ]]; then
    for ref in origin/main origin/master ""; do
      [[ -z "$ref" ]] || git -C "$1" rev-parse --verify --quiet "refs/remotes/$ref^{commit}" >/dev/null && break
    done
  fi
  [[ "$ref" =~ ^origin/[A-Za-z0-9._/-]+$ && "$ref" != *..* ]] || ref=""
  printf '%s' "$ref"
}

cmd_config() {
  local repo="" user="" have_user=0 ref team_name file i name best=-1 n v team_reason="" reason
  while (($#)); do
    case "$1" in
      --repo)
        need_value "$1" $#
        repo="$2"
        shift
        ;;
      --user)
        need_value "$1" $#
        [[ "$2" == pixel_tolerance=* ]] || usage "--user takes pixel_tolerance=<value>"
        user="${2#pixel_tolerance=}" have_user=1
        shift
        ;;
      *) usage "unknown argument to config: $1" ;;
    esac
    shift
  done
  [[ -n "$repo" ]] || usage "config needs --repo"
  [[ -d "$repo" ]] || err "--repo is not a directory: $repo"
  repo="$(cd -- "$repo" && pwd -P)" || err "cannot enter --repo: $repo"

  file="docs/conventions/testing.yaml"
  if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    ref="$(default_ref "$repo")"
    if [[ -n "$ref" ]]; then
      team_name="team (origin default branch)"
      read_layer team "$team_name: $ref:$file" "$repo" "$file" --ref "$ref"
    else
      warn "origin has no default branch ref (run git remote set-head origin --auto); the team layer is not read"
    fi
  else
    team_name="team (working tree, no origin)"
    if under_link "$repo/$file" "$repo"; then
      warn "skipping a layer that is a symlink or under a symlinked directory: $repo/$file"
    elif [[ -f "$repo/$file" ]]; then
      read_layer team "$repo/$file" "$repo" "$repo/$file"
    fi
  fi
  file="$repo/.claude/testing.local.yaml"
  if under_link "$file" "$repo"; then
    warn "skipping a layer that is a symlink or under a symlinked directory: $file"
  elif [[ -f "$file" ]]; then
    read_layer overlay "$file" "$repo" "$file"
  fi
  file="${HOME:-}/.claude/testing.yaml"
  [[ -z "${HOME:-}" || ! -f "$file" ]] || read_layer user-global "$file" "$repo" "$file"
  # An unrendered ${user_config.pixel_tolerance}, or an empty one, is unset.
  # shellcheck disable=SC2016 # the placeholder's opening is literal text
  if ((have_user)) && [[ -n "$user" && "$user" != '${'* ]]; then
    add_layer user-option "userConfig option" "--user pixel_tolerance" "$user" ""
  fi

  # The team value, or the default 0 when the team sets none, is the ceiling.
  # On a tie the team is named first, then overlay, user-global, the option.
  local cap=0 cap_name=default
  for i in "${!L_NAME[@]}"; do
    if [[ "${L_NAME[i]}" == team ]]; then
      cap="${L_PIXELS[i]}" cap_name="$team_name" team_reason="${L_REASON[i]}"
    fi
  done
  v="$cap" n="$cap_name" reason="$team_reason"
  for name in overlay user-global user-option; do
    for i in "${!L_NAME[@]}"; do
      [[ "${L_NAME[i]}" == "$name" ]] || continue
      if ((L_PIXELS[i] > cap)); then
        warn "${L_LABEL[i]}: pixel_tolerance.pixels ${L_PIXELS[i]} is above the team value $cap; a personal layer can only lower it, so the raise is ignored"
      elif ((L_PIXELS[i] < v)) || [[ "$n" == default && "${L_PIXELS[i]}" == "$v" ]]; then
        v="${L_PIXELS[i]}" n="$name" best="$i"
      fi
    done
  done
  if ((best >= 0)); then
    reason="${L_REASON[best]}"
    [[ "${L_NAME[best]}" != user-option ]] || reason="$team_reason (narrowed by the user option)"
  fi
  ((v > 0)) || reason=""
  printf 'pixel_tolerance=%s source=%s reason=%s\n' "$v" "$n" "$reason"
}

# --- manifest -----------------------------------------------------------------

cmd_manifest() {
  local dir="" browser="" viewport="" scale="" head
  while (($#)); do
    case "$1" in
      --dir | --browser | --viewport | --scale)
        need_value "$1" $#
        case "$1" in
          --dir) dir="$2" ;;
          --browser) browser="$2" ;;
          --viewport) viewport="$2" ;;
          *) scale="$2" ;;
        esac
        shift
        ;;
      *) usage "unknown argument to manifest: $1" ;;
    esac
    shift
  done
  [[ -n "$dir" && -n "$browser" && -n "$viewport" && -n "$scale" ]] ||
    usage "manifest needs --dir, --browser, --viewport and --scale"
  [[ "$viewport" =~ ^[0-9]{1,5}x[0-9]{1,5}$ ]] || usage "--viewport takes <W>x<H>: $viewport"
  [[ "$scale" =~ ^[0-9]{1,2}(\.[0-9]{1,3})?$ ]] || usage "--scale takes a number: $scale"
  [[ -d "$dir" ]] || err "--dir is not a directory: $dir"
  [[ ! -e "$dir/manifest.json" && ! -L "$dir/manifest.json" ]] ||
    err "$dir/manifest.json exists; a baseline is never rewritten. Capture into a new directory."
  need_node
  head="$(git rev-parse HEAD 2>/dev/null)" || head=""
  [[ "$head" =~ ^[0-9a-f]{40}$ ]] || head=""
  node "$MJS" manifest --dir "$dir" --browser "$browser" --viewport "$viewport" --scale "$scale" --head "$head"
}

# --- compare ------------------------------------------------------------------

cmd_compare() {
  local baseline="" after="" tolerance="" reason="" have_reason=0 diff="" deps="" dry=0 rc
  while (($#)); do
    case "$1" in
      --baseline | --after | --tolerance | --reason | --diff-dir | --deps-dir)
        need_value "$1" $#
        case "$1" in
          --baseline) baseline="$2" ;;
          --after) after="$2" ;;
          --tolerance) tolerance="$2" ;;
          --reason) reason="$2" have_reason=1 ;;
          --diff-dir) diff="$2" ;;
          *) deps="$2" ;;
        esac
        shift
        ;;
      --dry-run) dry=1 ;;
      *) usage "unknown argument to compare: $1" ;;
    esac
    shift
  done
  [[ -n "$baseline" && -n "$after" && -n "$tolerance" && -n "$diff" ]] ||
    usage "compare needs --baseline, --after, --tolerance and --diff-dir"
  [[ "$tolerance" =~ ^[0-9]{1,9}$ ]] || usage "--tolerance takes a whole number, 0 or more: $tolerance"
  tolerance=$((10#$tolerance))
  if ((tolerance > 0)) && [[ $have_reason == 0 || -z "$reason" ]]; then
    usage "--tolerance above 0 needs --reason: a tolerance is accepted only with a recorded reason"
  fi
  install_target "$deps"
  if ((dry)); then
    dry_run_report
    return 0
  fi
  ensure_installed "$TARGET"
  rc=0
  node "$MJS" compare --deps "$TARGET" --baseline "$baseline" --after "$after" \
    --tolerance "$tolerance" --reason "$reason" --diff-dir "$diff" || rc=$?
  ((rc <= 2)) || rc=2
  return "$rc"
}

# --- main ---------------------------------------------------------------------

(($#)) || usage "no subcommand"
sub="$1"
shift
case "$sub" in
  -h | --help) printf '%s\n' "$USAGE" ;;
  install) cmd_install "$@" ;;
  config) cmd_config "$@" ;;
  manifest) cmd_manifest "$@" ;;
  compare) cmd_compare "$@" ;;
  *) usage "unknown subcommand: $sub" ;;
esac
