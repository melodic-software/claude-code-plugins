#!/usr/bin/env bash
# Exit codes:
#   0  status emitted, in every state above including a failed fetch
#   3  invalid argument, or an unreadable --ledger or --changelog path

set -uo pipefail

VERSION_RE='[0-9]+\.[0-9]+\.[0-9]+'

err() { printf 'ERROR: %s\n' "$*" >&2; }
usage() {
  cat <<'EOF'
changelog-status.sh: where a repository stands against the Claude Code changelog.

Usage:
  changelog-status.sh [--ledger <file>] [--changelog <file> | --no-fetch]
                      [--range <A..B> | --range <X>]
                      [--cap-releases <n>] [--cap-items <n>]

  --ledger <file>     upstream ledger holding the read marker
                      (default $HARNESS_OPS_CHANGELOG_LEDGER, else docs/upstream/claude-code.md)
  --changelog <file>  changelog to read instead of fetching it
  --no-fetch          fetch nothing
  --range A..B | X    inclusive release range, or one release; ignores the marker
  --cap-releases <n>  replay cap in releases (default $HARNESS_OPS_CHANGELOG_CAP_RELEASES, else 10)
  --cap-items <n>     replay cap in core items (default $HARNESS_OPS_CHANGELOG_CAP_ITEMS, else 300)

Marker resolution, range, cap and output lines: context/read-actions.md.

Exit codes:
  0  status emitted, in every state including a failed fetch
  3  invalid argument, or an unreadable --ledger or --changelog path
EOF
}

ledger_arg=""
changelog_arg=""
no_fetch=0
range_arg=""
cap_releases="${HARNESS_OPS_CHANGELOG_CAP_RELEASES:-10}"
cap_items="${HARNESS_OPS_CHANGELOG_CAP_ITEMS:-300}"

# shellcheck source=../../../lib/opt-value.sh
opt_value_dir="${BASH_SOURCE[0]%/*}"
[[ "$opt_value_dir" != "${BASH_SOURCE[0]}" ]] || opt_value_dir=.
source "$opt_value_dir/../../../lib/opt-value.sh"
OPT_VALUE_EXIT=3

while (($#)); do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --ledger)
    require_opt_value changelog-status.sh "$@"
    ledger_arg="$2"
    shift 2
    ;;
  --changelog)
    require_opt_value changelog-status.sh "$@"
    changelog_arg="$2"
    shift 2
    ;;
  --no-fetch)
    no_fetch=1
    shift
    ;;
  --range)
    require_opt_value changelog-status.sh "$@"
    range_arg="$2"
    shift 2
    ;;
  --cap-releases)
    require_opt_value changelog-status.sh "$@"
    cap_releases="$2"
    shift 2
    ;;
  --cap-items)
    require_opt_value changelog-status.sh "$@"
    cap_items="$2"
    shift 2
    ;;
  *)
    err "unknown argument: $1 (see --help)"
    exit 3
    ;;
  esac
done

for cap in "$cap_releases" "$cap_items"; do
  if ! [[ "$cap" =~ ^[0-9]+$ ]]; then
    err "cap must be a non-negative integer, got: $cap"
    exit 3
  fi
done

range_first=""
range_last=""
if [[ -n "$range_arg" ]]; then
  if [[ "$range_arg" =~ ^v?($VERSION_RE)\.\.v?($VERSION_RE)$ ]]; then
    range_first="${BASH_REMATCH[1]}"
    range_last="${BASH_REMATCH[2]}"
  elif [[ "$range_arg" =~ ^v?($VERSION_RE)$ ]]; then
    range_first="${BASH_REMATCH[1]}"
    range_last="${BASH_REMATCH[1]}"
  else
    err "--range takes A..B or X, versions as X.Y.Z with an optional v prefix; got: $range_arg"
    exit 3
  fi
fi

if [[ -n "$changelog_arg" && ! -r "$changelog_arg" ]]; then
  err "changelog file is not readable: $changelog_arg"
  exit 3
fi
if [[ -n "$ledger_arg" && -e "$ledger_arg" && ! -r "$ledger_arg" ]]; then
  err "ledger file is not readable: $ledger_arg"
  exit 3
fi

vsort() { sort -t. -k1,1n -k2,2n -k3,3n; }
vmax() { printf '%s\n' "$@" | grep -E "^$VERSION_RE\$" | vsort | tail -1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
in_repo=1
if [[ -z "$repo_root" ]]; then
  repo_root="$(pwd)"
  in_repo=0
else
  canon="$(cd "$repo_root" 2>/dev/null && pwd -P)" && repo_root="$canon"
fi

if [[ -n "$ledger_arg" ]]; then
  ledger="$ledger_arg"
elif [[ -n "${HARNESS_OPS_CHANGELOG_LEDGER:-}" ]]; then
  ledger="$HARNESS_OPS_CHANGELOG_LEDGER"
else
  ledger="$repo_root/docs/upstream/claude-code.md"
fi

last=""
source="none"
ledger_state="absent"
if [[ -f "$ledger" ]]; then
  ledger_state="present"
  last="$(grep -oE 'Last audited upstream state:\*\* changelog through `'"$VERSION_RE"'`' "$ledger" 2>/dev/null |
    grep -oE "$VERSION_RE" | head -1)"
  [[ -n "$last" ]] && source="ledger:$ledger"
fi

if [[ -z "$last" ]] && ((in_repo)); then
  subject_versions="$(git log --format='%s' 2>/dev/null | tr -d '\r' |
    grep -E '^[a-z]+(\([^)]*\))?!?: .*address Claude Code v'"$VERSION_RE"'(\.\.v?'"$VERSION_RE"')? changelog' |
    grep -oE 'address Claude Code v'"$VERSION_RE"'(\.\.v?'"$VERSION_RE"')? changelog' |
    grep -oE "$VERSION_RE" || true)"
  if [[ -n "$subject_versions" ]]; then
    # shellcheck disable=SC2086
    last="$(vmax $subject_versions)"
    [[ -n "$last" ]] && source="git-subject"
  fi
fi

installed="$(claude --version 2>/dev/null | tr -d '\r' | grep -oE "$VERSION_RE" | head -1)"
[[ -n "$installed" ]] || installed="unknown"

printf 'last-applied: %s\n' "${last:-none}"
printf 'source: %s\n' "$source"
printf 'ledger: %s (%s)\n' "$ledger" "$ledger_state"
printf 'installed: %s\n' "$installed"

plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
tmp_dir=""
trap '[[ -n "$tmp_dir" ]] && rm -rf "$tmp_dir"' EXIT

changelog=""
not_computed=""
fetch_changelog="$plugin_root/scripts/fetch-changelog.sh"
if [[ -n "$changelog_arg" ]]; then
  if bash "$fetch_changelog" --check "$changelog_arg"; then
    changelog="$changelog_arg"
    printf 'changelog: %s\n' "$changelog"
  else
    first_heading="$(grep -m1 -E '^# ' "$changelog_arg" | tr -d '\r')"
    not_computed="body is not the changelog (first heading: ${first_heading:-none})"
  fi
elif ((no_fetch)); then
  not_computed="no changelog source: --no-fetch and no --changelog"
else
  tmp_dir="$(mktemp -d)"
  if fetched="$(bash "$fetch_changelog" --out "$tmp_dir")"; then
    changelog="$tmp_dir/changelog.md"
    printf '%s\n' "$fetched"
  else
    not_computed="fetch of the changelog failed (${fetched#unread: }); pass --changelog <file> or retry"
  fi
fi

finish_without_range() {
  printf 'latest: unknown\n'
  printf 'range: not computed (%s)\n' "$1"
  if [[ -z "$last" ]]; then
    printf 'recommend: no read marker. Run a docs-conformance recheck of the components against the current docs, then create %s with the marker line at the newest published release and diff only from there\n' "$ledger"
  fi
  exit 0
}

[[ -n "$changelog" ]] || finish_without_range "$not_computed"

mode="after"
[[ -n "$range_first" ]] && mode="between"
rows="$(bash "$plugin_root/scripts/changelog-releases.sh" "$changelog")"
mapfile -t in_range < <(printf '%s\n' "$rows" | awk -F'\t' -v mode="$mode" -v last="$last" -v lo="$range_first" -v hi="$range_last" '
  function vcmp(a, b,   A, B, i) {
    split(a, A, "."); split(b, B, ".")
    for (i = 1; i <= 3; i++) {
      if (A[i] + 0 < B[i] + 0) return -1
      if (A[i] + 0 > B[i] + 0) return 1
    }
    return 0
  }
  function wanted(v) {
    if (mode == "between") return vcmp(v, lo) >= 0 && vcmp(v, hi) <= 0
    return last == "" || vcmp(v, last) > 0
  }
  $1 == "release" { if (wanted($2)) n[$2] += 0 }
  $1 == "item" && $3 !~ /\[VSCode\]/ { if (wanted($2)) n[$2]++ }
  END { for (v in n) print v "\t" n[v] }
' | vsort)

latest="$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "release" { print $2 }' | vsort | tail -1)"
printf 'latest: %s\n' "${latest:-unknown}"

if [[ -z "$latest" ]]; then
  printf 'range: not computed (no release markers parsed from the changelog body; the page markup may have changed)\n'
  exit 0
fi

rel_count="${#in_range[@]}"
if ((rel_count == 0)); then
  if [[ -n "$range_first" ]]; then
    printf 'range: not computed (no release between %s and %s in the changelog)\n' "$range_first" "$range_last"
  else
    printf 'range: up to date\n'
  fi
  exit 0
fi

range_versions=("${in_range[@]%%[[:space:]]*}")
last_in_range="${range_versions[rel_count - 1]}"
item_count="$(printf '%s\n' "${in_range[@]}" | awk -F'\t' '{ s += $2 } END { print s + 0 }')"

printf 'range: %s..%s (%d releases, %d core items)\n' "${range_versions[0]}" "$last_in_range" "$rel_count" "$item_count"

if ((rel_count > cap_releases)); then
  printf 'releases: (%d releases, list omitted beyond the cap)\n' "$rel_count"
else
  printf 'releases: %s\n' "${range_versions[*]}"
fi
if ((rel_count > cap_releases || item_count > cap_items)); then
  printf 'cap: exceeded (%d releases / %d items)\n' "$cap_releases" "$cap_items"
  printf 'recommend: replay cost scales with items and the current docs carry the cumulative state. Run a docs-conformance recheck of the components, then set the marker in %s to %s and diff only from there\n' "$ledger" "$last_in_range"
else
  printf 'cap: within budget (%d releases / %d items)\n' "$cap_releases" "$cap_items"
  if [[ -z "$last" ]]; then
    printf 'recommend: no read marker. After this range is applied, create %s with the marker line at %s\n' "$ledger" "$last_in_range"
  fi
fi

if [[ "$installed" != "unknown" && "$(vmax "$installed" "$last_in_range")" != "$installed" ]]; then
  printf 'warn: installed %s is older than the newest release in the range %s; update Claude Code before applying changes that reference it\n' "$installed" "$last_in_range"
fi
exit 0
