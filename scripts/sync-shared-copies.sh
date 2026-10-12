#!/usr/bin/env bash
# Generate, verify, or publish every per-plugin copy of a shared library.
#
#   scripts/sync-shared-copies.sh                      regenerate every registered copy
#   scripts/sync-shared-copies.sh --check              fail if any copy differs from what its
#                                                      canonical source generates; never writes
#   scripts/sync-shared-copies.sh --check-bump <ref>   fail if a canonical changed vs <ref> but a
#                                                      carrying plugin's manifest version did not
#                                                      move (or, in fragment mode, it added no
#                                                      fragment whose bump is not none)
#   scripts/sync-shared-copies.sh --print-manifest     emit each canonical and its copies as data
#
# Each line of scripts/shared-copies.txt registers one copy: `<canonical> <copy>`.
# A copy is the canonical with a generated-file header inserted after any shebang
# line, so a copy is output, never a place to edit. The decision is ADR 0019.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/gate-entry.sh
. "$script_dir/lib/gate-entry.sh" || exit 2
# shellcheck source=lib/changelog-fragments.sh
. "$script_dir/lib/changelog-fragments.sh" || exit 2

registry="scripts/shared-copies.txt"
self="scripts/sync-shared-copies.sh"

srcs=()                 # canonical paths, first-seen registry order
declare -A copies_of=() # canonical -> newline-separated copies
declare -A src_of=()    # copy -> canonical

load_registry() {
  local line src copy extra
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    read -r src copy extra <<<"$line" || true
    [[ -z "$src" ]] && continue
    if [[ -z "$copy" || -n "$extra" ]]; then
      echo "error: $registry: want '<canonical> <copy>', got: $line" >&2
      exit 2
    fi
    if [[ ! -f "$src" ]]; then
      echo "error: $registry: canonical $src does not exist." >&2
      exit 2
    fi
    if [[ "$copy" != plugins/?*/?* ]]; then
      echo "error: $registry: copy $copy is not inside a plugin (plugins/<name>/...)." >&2
      exit 2
    fi
    if [[ -n "${src_of[$copy]:-}" || -n "${copies_of[$copy]+set}" || -n "${src_of[$src]:-}" ]]; then
      echo "error: $registry: a path is registered twice, or as both a canonical and a copy: $line" >&2
      exit 2
    fi
    src_of["$copy"]="$src"
    [[ -n "${copies_of[$src]+set}" ]] || srcs+=("$src")
    copies_of["$src"]+="$copy"$'\n'
  done <"$registry"
}

# render <canonical>: the generated copy's bytes, on stdout. A shell, Python or
# JavaScript copy takes a two-line comment header after any shebang; a Markdown
# copy takes the same header as an HTML comment after any frontmatter block.
render() {
  local src="$1" prefix first="" close=""
  case "$src" in
  *.mjs | *.cjs | *.js | *.ts) prefix='//' ;;
  *.sh | *.bash | *.py | *.ps1 | *.psm1 | *.awk) prefix='#' ;;
  *.md)
    IFS= read -r first <"$src" || true
    if [[ "$first" == '---' ]]; then
      close="$(awk 'NR > 1 && /^---$/ { print NR; exit }' "$src")"
    fi
    if [[ -n "$close" ]]; then
      head -n "$close" "$src"
      printf '\n'
    fi
    printf '<!-- GENERATED from %s by %s. Do not edit this copy:\n' "$src" "$self"
    printf 'edit the canonical source, then rerun the script. -->\n'
    if [[ -n "$close" ]]; then
      tail -n +"$((close + 1))" "$src"
    else
      printf '\n'
      cat "$src"
    fi
    return 0
    ;;
  *)
    echo "error: no comment syntax known for $src; teach $self its extension." >&2
    return 2
    ;;
  esac
  IFS= read -r first <"$src" || true
  if [[ "$first" == '#!'* ]]; then
    printf '%s\n' "$first"
  fi
  printf '%s GENERATED from %s by %s. Do not edit this copy:\n' "$prefix" "$src" "$self"
  printf '%s edit the canonical source, then rerun the script.\n' "$prefix"
  if [[ "$first" == '#!'* ]]; then
    tail -n +2 "$src"
  else
    cat "$src"
  fi
}

# each_copy <fn>: calls <fn> <canonical> <copy> <rendered-file> per registered copy.
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
each_copy() {
  local fn="$1" src copy
  for src in "${srcs[@]}"; do
    render "$src" >"$rendered"
    while IFS= read -r copy; do
      [[ -z "$copy" ]] || "$fn" "$src" "$copy" "$rendered"
    done <<<"${copies_of[$src]}"
  done
}

write_copy() {
  local src="$1" copy="$2" rendered="$3"
  if [[ ! -e "$copy" ]]; then
    mkdir -p "${copy%/*}"
    cp "$src" "$copy" # carries the canonical's file mode onto a new copy
  fi
  if ! cmp -s "$rendered" "$copy"; then
    cat "$rendered" >"$copy"
    echo "generated: $copy"
  fi
  if [[ -x "$src" && ! -x "$copy" ]]; then
    chmod +x "$copy"
    echo "generated: $copy (executable bit)"
  elif [[ ! -x "$src" && -x "$copy" ]]; then
    chmod -x "$copy"
    echo "generated: $copy (executable bit)"
  fi
}

drifted=0
check_copy() {
  local src="$1" copy="$2" rendered="$3"
  if ! cmp -s "$rendered" "$copy"; then
    echo "DRIFT: $copy differs from the copy $src generates" >&2
    drifted=1
  fi
  if [[ -x "$src" && ! -x "$copy" ]] || [[ ! -x "$src" && -x "$copy" ]]; then
    echo "DRIFT: $copy has a different executable bit than $src" >&2
    drifted=1
  fi
}

# fragment_hint: print the one command that writes a patch fragment for every
# stale fragment-mode carrier, from check_bump's stale_plugins, stale_seen and
# stale_srcs. --carriers-of names them only when it would write exactly that
# set: every fragment-mode carrier of the stale canonicals is stale. Otherwise
# (a carrier already has its fragment, is new since the base, or only a copy
# changed) the stale plugins are listed by name.
fragment_hint() {
  local targets="" src copy plugin names="" exact=1
  for src in "${stale_srcs[@]}"; do
    targets+=" --carriers-of $src"
    names+="${names:+, }\`$(basename "$src")\`"
    while IFS= read -r copy; do
      [[ -n "$copy" ]] || continue
      plugin="${copy#plugins/}"
      plugin="${plugin%%/*}"
      [[ -z "${stale_seen[$plugin]:-}" ]] || continue
      # shellcheck disable=SC2310  # the non-zero return IS the answer; check_bump already read the list
      changelog_fragments::in_mode "$plugin" || continue
      exact=0
    done <<<"${copies_of[$src]}"
  done
  ((exact)) || targets=" ${stale_plugins[*]}"
  echo "Add a patch fragment for every carrying plugin in fragment mode; the release pull request bumps its version (ADR 0048). One command covers them all:" >&2
  echo "  scripts/new-changelog-fragment.sh --stdin$targets patch <<'EOF'" >&2
  printf '### Changed\n\n- Shared %s synced where this plugin carries it (<link to the change>); no other change to this plugin.\nEOF\n' "$names" >&2
}

check_bump() {
  local base="$1" src copy rest plugin manifest base_version head_version stale=0 changed=0 src_changed rc
  local -a stale_plugins=() stale_srcs=()
  local -A stale_seen=() src_seen=()
  gate_entry::require_base "$base" "error: base ref $base does not resolve to a commit."
  for src in "${srcs[@]}"; do
    src_changed=0
    while IFS= read -r copy; do
      [[ -n "$copy" ]] || continue
      # A copy can change with its canonical untouched: a new header, or a new registry entry.
      git diff --quiet "$base" -- "$src" "$copy" && continue
      src_changed=1
      rest="${copy#plugins/}"
      manifest="plugins/${rest%%/*}/.claude-plugin/plugin.json"
      # A plugin absent at the base ref is new in this change set; its initial
      # release already carries the new canonical content.
      base_version=$(git show "$base:$manifest" 2>/dev/null | jq -r '.version // empty' || true)
      [[ -n "$base_version" ]] || continue
      head_version=$(jq -r '.version // empty' "$manifest")
      plugin="${rest%%/*}"
      rc=0
      # shellcheck disable=SC2310  # the non-zero return IS the answer; rc 2 exits below
      changelog_fragments::bump_delivered "$base" "$plugin" "$base_version" "$head_version" || rc=$?
      ((rc < 2)) || exit 2
      if ((rc == 1)); then
        rest="${rest#*/}"
        # shellcheck disable=SC2310  # bump_delivered already read the list; rc 2 cannot recur
        if changelog_fragments::in_mode "$plugin"; then
          echo "STALE VERSION: $src or its copy $copy changed vs $base but $plugin, in fragment mode, has no fragment for it" >&2
          [[ -n "${stale_seen[$plugin]:-}" ]] || stale_plugins+=("$plugin")
          [[ -n "${src_seen[$src]:-}" ]] || stale_srcs+=("$src")
          stale_seen["$plugin"]=1
          src_seen["$src"]=1
        else
          echo "STALE VERSION: $src or its copy $copy changed vs $base but $manifest is still $head_version" >&2
          echo "  A bump that only carries the change gets the CHANGELOG entry: Shared \`$(basename "$src")\` synced (<link to the change>); no change to this plugin's ${rest%%/*}." >&2
          stale=1
        fi
      fi
    done <<<"${copies_of[$src]}"
    changed=$((changed + src_changed))
  done
  if ((stale)); then
    echo "Bump the version of every carrying plugin so consumers receive the change." >&2
  fi
  if ((${#stale_plugins[@]})); then
    fragment_hint
  fi
  if ((stale || ${#stale_plugins[@]})); then
    exit 1
  fi
  if ((changed)); then
    echo "$changed canonical source(s) or their copies changed vs $base; every carrying plugin bumped its version."
  else
    echo "No canonical source or copy changed vs $base; no version bumps required."
  fi
}

mode="${1:-sync}"
case "$mode" in
sync)
  load_registry
  each_copy write_copy
  ;;
--check)
  load_registry
  each_copy check_copy
  if ((drifted)); then
    echo "Run $self and commit the result." >&2
    exit 1
  fi
  echo "All ${#src_of[@]} registered copies match their canonical sources."
  ;;
--check-bump)
  base="${2:?usage: sync-shared-copies.sh --check-bump <base-ref>}"
  load_registry
  check_bump "$base"
  ;;
--print-manifest)
  load_registry
  for src in "${srcs[@]}"; do
    printf 'src\t%s\n' "$src"
    while IFS= read -r copy; do
      [[ -z "$copy" ]] || printf 'copy\t%s\n' "$copy"
    done <<<"${copies_of[$src]}"
  done
  ;;
*)
  echo "usage: sync-shared-copies.sh [--check | --check-bump <base-ref> | --print-manifest]" >&2
  exit 2
  ;;
esac
