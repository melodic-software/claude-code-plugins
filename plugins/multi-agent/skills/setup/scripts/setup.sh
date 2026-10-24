#!/usr/bin/env bash
# setup.sh: inspect or write one layer of the multi-agent role map.
#
#   setup.sh check [session=<alias>]
#       The resolved map through the route wrapper (JSON on stdout, notes on
#       stderr), then one row on the personal overlay's gitignore state.
#   setup.sh apply --layer user|team|local [--write] <key>=<value> ...
#       Merges the pairs into that layer's existing keys. `<key>=` with no
#       value removes the key. Without --write it prints the target path and a
#       diff and writes nothing; with --write it writes, then reads the file
#       back. The candidate is resolved before anything is written: a key the
#       resolver would reject or ignore stops the run with exit 1.
#
# Layers (reference/config.md):
#   user   <home>/.claude/multi-agent.yaml
#   team   <root>/<home>/multi-agent.yaml, <home> being the convention home the
#          repository binds, else docs/conventions. While that file is absent,
#          the keys of the legacy team file the resolver still reads for one
#          release seed it; the legacy file is left as it is.
#   local  <root>/.claude/multi-agent.local.yaml
# team and local are refused unless lib/config-root.sh classifies <root> as repo.
# A layer file is rewritten whole, so comments in it are not kept.
#
# Options for tests: --root <dir> (default CLAUDE_PROJECT_DIR, else the git
# toplevel), --home <dir> (default $HOME).
#
# Exit: 0 done (or nothing to change); 1 the candidate does not resolve
# cleanly, or the existing layer does not parse; 2 usage error or a refused layer.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/../../.."
ROUTE="$SCRIPT_DIR/../../route/scripts/route.sh"
RESOLVER="$PLUGIN_DIR/scripts/resolve-roles.sh"
PARSER="$PLUGIN_DIR/scripts/yaml-subset.awk"
# shellcheck source=../../../lib/config-root.sh
. "$PLUGIN_DIR/lib/config-root.sh"

die() {
  printf 'setup: %s\n' "$1" >&2
  exit 2
}

ACTION="${1:-check}"
[[ $# -gt 0 ]] && shift
LAYER="" WRITE=0 ROOT="" HOME_DIR="${HOME:-}"
SESSION=() PAIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --layer | --root | --home)
    [[ $# -gt 1 ]] || die "$1 needs a value"
    case "$1" in
    --layer) LAYER="$2" ;;
    --root) ROOT="$2" ;;
    *) HOME_DIR="$2" ;;
    esac
    shift
    ;;
  --write) WRITE=1 ;;
  session=*) SESSION=("$1") ;;
  *=*) PAIRS+=("$1") ;;
  *) die "unknown argument '$1'" ;;
  esac
  shift
done
[[ -n "$ROOT" ]] || ROOT="$(config_root_resolve)"
CLASS="$(HOME="$HOME_DIR" config_root_classify "$ROOT")"
LOCATE=(--root "$ROOT" --home "$HOME_DIR")

check() {
  "$ROUTE" all "${SESSION[@]+"${SESSION[@]}"}" "${LOCATE[@]}" || return
  if [[ "$CLASS" != repo ]]; then
    printf 'INFO overlay: not applicable at a %s root\n' "$CLASS"
  elif git -C "$ROOT" check-ignore -q .claude/multi-agent.local.yaml; then
    printf 'PASS overlay: .claude/multi-agent.local.yaml is gitignored\n'
  else
    printf 'WARN overlay: .claude/multi-agent.local.yaml is not gitignored; the recommended line is .claude/**/*.local.*\n'
  fi
}

# Render sorted `dotted.key<TAB>value` records as the YAML subset.
render() {
  LC_ALL=C sort -t $'\t' -k1,1 | awk -F '\t' '
    BEGIN { print "schema: 1"; prev_depth = 0 }
    {
      n = split($1, p, ".")
      c = 0
      while (c < n - 1 && c < prev_depth && p[c + 1] == pp[c + 1]) c++
      for (i = c + 1; i < n; i++) printf "%" (2 * (i - 1)) "s%s:\n", "", p[i]
      printf "%" (2 * (n - 1)) "s%s: %s\n", "", p[n], $2
      prev_depth = n - 1
      for (i = 1; i <= n; i++) pp[i] = p[i]
    }'
}

# The convention home the repository binds, else docs/conventions.
convention_home() {
  local out
  out="$(bash "$PLUGIN_DIR/lib/resolve-convention-home.sh" --root "$ROOT" 2>/dev/null)" && printf '%s' "$out" ||
    printf 'docs/conventions'
}

apply() {
  local target existing="" records body old_label seed="" seed_block=0
  case "$LAYER" in
  user)
    [[ -n "$HOME_DIR" ]] || die "no home directory to hold the user layer"
    target="$HOME_DIR/.claude/multi-agent.yaml"
    ;;
  team | local)
    [[ "$CLASS" == repo ]] ||
      die "the $LAYER layer is not applicable at a $CLASS root; run from the repository, or use --layer user"
    if [[ "$LAYER" == local ]]; then
      target="$ROOT/.claude/multi-agent.local.yaml"
    else
      target="$ROOT/$(convention_home)/multi-agent.yaml"
      # Until the YAML exists, the legacy team file the resolver still reads
      # seeds it, so the first write carries those keys over.
      if [[ ! -f "$target" ]]; then
        if [[ -f "$ROOT/docs/conventions/multi-agent.md" ]] &&
          [[ "$(awk -v BLOCK=1 -f "$PARSER" "$ROOT/docs/conventions/multi-agent.md")" == block$'\t'* ]]; then
          seed="$ROOT/docs/conventions/multi-agent.md" seed_block=1
        elif [[ -f "$ROOT/.claude/multi-agent.yaml" ]]; then
          seed="$ROOT/.claude/multi-agent.yaml"
        fi
      fi
    fi
    ;;
  "") die "apply needs --layer user|team|local" ;;
  *) die "unknown layer '$LAYER' (user, team or local)" ;;
  esac
  # A repository can commit a symlink at a team or local path; reading or
  # writing through it would reach a file outside the repository.
  if [[ "$LAYER" != user ]]; then
    local p="$target"
    while [[ "$p" == "$ROOT"/* ]]; do
      [[ -L "$p" ]] && die "refusing $target: $p is a symlink"
      p=$(dirname "$p")
    done
  fi
  ((${#PAIRS[@]})) || die "apply needs at least one <key>=<value>"

  local source_file="$target"
  [[ -f "$target" ]] || source_file="$seed"
  if [[ -n "$source_file" && -f "$source_file" ]]; then
    if [[ "$source_file" == "$seed" && "$seed_block" == 1 ]]; then
      records="$(awk -v BLOCK=1 -f "$PARSER" "$source_file")"
    else
      records="$(awk -f "$PARSER" "$source_file")"
    fi || {
      printf 'setup: %s does not parse (%s); fix or remove it before apply\n' \
        "$source_file" "$(awk -F '\t' '$1=="error"{print "line " $2 ": " $3}' <<<"$records")" >&2
      exit 1
    }
    existing="$(awk -F '\t' '$1!="schema" && $1!="block"' <<<"$records")"
  fi

  local pair key value
  for pair in "${PAIRS[@]}"; do
    key="${pair%%=*}" value="${pair#*=}"
    [[ "$key" =~ ^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$ && "$key" != schema ]] || die "invalid key '$key'"
    [[ "$value" != *[$'\t\n\r#']* ]] || die "invalid value for $key"
    existing="$(awk -F '\t' -v k="$key" '$1!=k' <<<"$existing")"
    [[ -n "$value" ]] && existing+=$'\n'"$key"$'\t'"$value"
  done
  body="$(grep -v '^$' <<<"$existing" | render)"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/repo/.claude" "$tmp/home"
  git -C "$tmp/repo" init -q
  printf '%s\n' "$body" >"$tmp/repo/.claude/multi-agent.local.yaml"
  if ! "$RESOLVER" --root "$tmp/repo" --home "$tmp/home" all >/dev/null 2>"$tmp/notes" ||
    [[ -s "$tmp/notes" ]]; then
    printf 'setup: the layer would not resolve cleanly; nothing written:\n' >&2
    sed 's/^resolve-roles: overlay/  candidate/; s/^resolve-roles: /  /' "$tmp/notes" >&2
    exit 1
  fi

  printf '%s\n' "$body" >"$tmp/body"
  cp "$tmp/body" "$tmp/new"
  : >"$tmp/old"
  old_label=/dev/null
  [[ -f "$target" ]] && cp "$target" "$tmp/old" && old_label="$target"

  if cmp -s "$tmp/old" "$tmp/new"; then
    printf 'unchanged: %s\n' "$target"
    return 0
  fi
  if ((!WRITE)); then
    printf 'would write: %s (%s layer)\n' "$target" "$LAYER"
    grep -q '#' "$tmp/old" &&
      printf 'note: the file is rewritten whole; its comments are not kept\n'
    grep -q '^  frontier_guard: false$' "$tmp/body" &&
      printf 'note: fanout.frontier_guard false lets fan-out stages run on a frontier session model\n'
    diff -u --label "$old_label" --label "$target" "$tmp/old" "$tmp/new"
    return 0
  fi
  mkdir -p "$(dirname "$target")" || die "cannot create $(dirname "$target")"
  if ! { cp "$tmp/new" "$target.tmp.$$" && mv -f "$target.tmp.$$" "$target"; }; then
    rm -f "$target.tmp.$$"
    die "cannot write $target"
  fi
  printf 'wrote: %s (%s layer)\n' "$target" "$LAYER"
  printf 'stored:\n'
  awk -f "$PARSER" "$target" |
    awk -F '\t' '$1!="block" { print "  " $1 ": " $2 }'
}

case "$ACTION" in
check) check ;;
apply) apply ;;
*) die "unknown action '$ACTION' (check or apply)" ;;
esac
