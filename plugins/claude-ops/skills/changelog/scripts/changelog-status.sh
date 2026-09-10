#!/usr/bin/env bash
# changelog-status.sh: where a repository stands against the Claude Code changelog.
#
# Reads the READ MARKER (the newest release this repository has been read against)
# from the consumer's upstream ledger, computes the default range from it to the
# newest published release, counts the core items in that range, and applies the
# replay cap. `/claude-ops:changelog status` prints this output; `diff` and `apply`
# take their default range from it.
#
# Usage:
#   changelog-status.sh [--ledger <file>] [--changelog <file> | --no-fetch]
#                       [--range <A..B> | --range <X>]
#                       [--cap-releases <n>] [--cap-items <n>]
#
# Marker resolution, first hit wins:
#   1. The ledger's marker line:
#        **Last audited upstream state:** changelog through `X.Y.Z`
#      Ledger path: --ledger, else $CLAUDE_OPS_CHANGELOG_LEDGER (verbatim), else
#      <git toplevel, or the working directory outside a repo>/docs/upstream/claude-code.md.
#   2. A Conventional Commits SUBJECT on the current branch naming an applied release:
#        <type>(<scope>): address Claude Code v<A>[..<B>] changelog
#      The highest version inside that phrase across such subjects wins; any other
#      dotted version in the subject is ignored. Commit BODIES are never read:
#      a body that says "verified against Claude Code v2.1.252" is a recency stamp,
#      not an apply, and reading bodies reported applies that never happened.
#   3. none.
#
# Changelog source: --changelog <file>; else a curl of
# https://code.claude.com/docs/en/changelog.md (the raw-markdown channel, rung 1 of
# the upstream-drift fetch route) into a temp file; --no-fetch skips the fetch.
# Whichever source is used, the body's first heading must read
# "# Claude Code changelog": a retired slug can serve another page's bytes under a
# 200, so identity is checked before any count is trusted. A body with the heading
# but no release blocks is a parse failure, not an empty range. In both cases the
# range is reported as not computed, with the reason.
#
# Range: the default is every release newer than the marker, oldest first, up to
# the newest published release. --range A..B (v prefix optional) is inclusive at
# both ends and ignores the marker; --range X is the single release X.
# Core items: bullet lines inside an <Update> block, excluding lines tagged [VSCode].
# Cap: --cap-releases (default $CLAUDE_OPS_CHANGELOG_CAP_RELEASES, else 10) and
# --cap-items (default $CLAUDE_OPS_CHANGELOG_CAP_ITEMS, else 300). Beyond the cap,
# replaying items costs more than it returns because the current docs already carry
# the cumulative state, so the output recommends a docs-conformance recheck of the
# components and a marker reset instead of a replay.
#
# Output, one `key: value` per line on stdout:
#   last-applied: <X.Y.Z|none>
#   source: ledger:<path> | git-subject | none
#   ledger: <path> (present|absent)
#   installed: <X.Y.Z|unknown>
#   latest: <X.Y.Z|unknown>
#   range: <A..B> (<n> releases, <m> core items) | up to date | not computed (<reason>)
#   releases: <space-separated versions in range, oldest first>   (only with a range;
#             the list is omitted when the release count alone exceeds the cap)
#   cap: within budget (<r> releases / <i> items) | exceeded (<r> releases / <i> items)
#   recommend: <next step>      when the cap is exceeded or no marker exists
#   warn: <text>                installed older than the newest release in the range
#
# Exit codes:
#   0  status emitted, in every state above including a failed fetch
#   3  invalid argument, or an unreadable --ledger or --changelog path

set -uo pipefail

CHANGELOG_URL="https://code.claude.com/docs/en/changelog.md"
CHANGELOG_HEADING="# Claude Code changelog"
VERSION_RE='[0-9]+\.[0-9]+\.[0-9]+'

err() { printf 'ERROR: %s\n' "$*" >&2; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

ledger_arg=""
changelog_arg=""
no_fetch=0
range_arg=""
cap_releases="${CLAUDE_OPS_CHANGELOG_CAP_RELEASES:-10}"
cap_items="${CLAUDE_OPS_CHANGELOG_CAP_ITEMS:-300}"

need_value() {
  if [[ $# -lt 2 || -z "$2" ]]; then
    err "$1 needs a value"
    exit 3
  fi
}

while (($#)); do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --ledger)
    need_value "$@"
    ledger_arg="$2"
    shift 2
    ;;
  --changelog)
    need_value "$@"
    changelog_arg="$2"
    shift 2
    ;;
  --no-fetch)
    no_fetch=1
    shift
    ;;
  --range)
    need_value "$@"
    range_arg="$2"
    shift 2
    ;;
  --cap-releases)
    need_value "$@"
    cap_releases="$2"
    shift 2
    ;;
  --cap-items)
    need_value "$@"
    cap_items="$2"
    shift 2
    ;;
  *)
    err "unknown argument: $1"
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

# Highest of the versions given, by numeric dotted compare. Portable across GNU
# and BSD sort, which do not agree on -V.
vmax() { printf '%s\n' "$@" | grep -E "^$VERSION_RE\$" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1; }

# --- Repository root -----------------------------------------------------------
# CR-stripped through an empty-means-fall-back test rather than `|| pwd`, so a
# not-in-a-repo failure still falls back instead of being swallowed by the pipe.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
[[ -n "$repo_root" ]] || repo_root="$(pwd)"

# --- Ledger and marker -----------------------------------------------------------
if [[ -n "$ledger_arg" ]]; then
  ledger="$ledger_arg"
elif [[ -n "${CLAUDE_OPS_CHANGELOG_LEDGER:-}" ]]; then
  ledger="$CLAUDE_OPS_CHANGELOG_LEDGER"
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

if [[ -z "$last" && -n "$(git rev-parse --show-toplevel 2>/dev/null)" ]]; then
  # SUBJECT only (%s). The version regex below deliberately reaches only the
  # `address Claude Code v<A>[..<B>] changelog` subject form.
  # Only the versions inside the `address Claude Code v<A>[..<B>] changelog` phrase count;
  # a subject can carry another dotted version (a plugin release) that is not an apply.
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

# --- Installed version -----------------------------------------------------------
installed="$(claude --version 2>/dev/null | tr -d '\r' | grep -oE "$VERSION_RE" | head -1)"
[[ -n "$installed" ]] || installed="unknown"

printf 'last-applied: %s\n' "${last:-none}"
printf 'source: %s\n' "$source"
printf 'ledger: %s (%s)\n' "$ledger" "$ledger_state"
printf 'installed: %s\n' "$installed"

# --- Changelog source ------------------------------------------------------------
tmp_changelog=""
trap '[[ -n "$tmp_changelog" ]] && rm -f "$tmp_changelog"' EXIT

changelog=""
not_computed=""
if [[ -n "$changelog_arg" ]]; then
  changelog="$changelog_arg"
elif ((no_fetch)); then
  not_computed="no changelog source: --no-fetch and no --changelog"
elif ! command -v curl >/dev/null 2>&1; then
  not_computed="curl is not installed; pass --changelog <file>"
else
  tmp_changelog="$(mktemp)"
  if curl -fsSL --max-time 60 "$CHANGELOG_URL" -o "$tmp_changelog" 2>/dev/null; then
    changelog="$tmp_changelog"
  else
    not_computed="fetch of $CHANGELOG_URL failed; pass --changelog <file> or retry"
  fi
fi

if [[ -n "$changelog" ]]; then
  first_heading="$(grep -m1 -E '^# ' "$changelog" | tr -d '\r')"
  if [[ "$first_heading" != "$CHANGELOG_HEADING" ]]; then
    not_computed="body is not the changelog page (first heading: ${first_heading:-none})"
    changelog=""
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

# --- Releases in range -----------------------------------------------------------
# One line per release in range: "<version>\t<core item count>", oldest first.
# mode "after": version > last (or every release when last is empty).
# mode "between": first <= version <= last_in_range.
if [[ -n "$range_first" ]]; then
  mode="between"
else
  mode="after"
fi
mapfile -t in_range < <(awk -v mode="$mode" -v last="$last" -v lo="$range_first" -v hi="$range_last" '
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
  /<Update label="/ {
    match($0, /label="[^"]+"/)
    v = substr($0, RSTART + 7, RLENGTH - 8)
    n = 0
    next
  }
  /^<\/Update>/ {
    if (v != "" && wanted(v)) print v "\t" n
    v = ""
    next
  }
  v != "" && /^[[:space:]]*\*/ && !/\[VSCode\]/ { n++ }
' "$changelog" | sort -t. -k1,1n -k2,2n -k3,3n)

# Newest published release, independent of the range, for the latest line and the
# installed-version warning.
latest="$(grep -oE '<Update label="'"$VERSION_RE"'"' "$changelog" | grep -oE "$VERSION_RE" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
printf 'latest: %s\n' "${latest:-unknown}"

# A body with the right heading but no release blocks is a parse failure (the page
# markup moved), never proof that nothing is pending.
if [[ -z "$latest" ]]; then
  printf 'range: not computed (no <Update label=...> release blocks parsed from the changelog body; the page markup may have changed)\n'
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

first="$(printf '%s\n' "${in_range[0]}" | cut -f1)"
last_in_range="$(printf '%s\n' "${in_range[rel_count - 1]}" | cut -f1)"
item_count="$(printf '%s\n' "${in_range[@]}" | awk -F'\t' '{ s += $2 } END { print s + 0 }')"
versions="$(printf '%s\n' "${in_range[@]}" | cut -f1 | tr '\n' ' ')"
versions="${versions% }"

printf 'range: %s..%s (%d releases, %d core items)\n' "$first" "$last_in_range" "$rel_count" "$item_count"

if ((rel_count > cap_releases || item_count > cap_items)); then
  if ((rel_count > cap_releases)); then
    printf 'releases: (%d releases, list omitted beyond the cap)\n' "$rel_count"
  else
    printf 'releases: %s\n' "$versions"
  fi
  printf 'cap: exceeded (%d releases / %d items)\n' "$cap_releases" "$cap_items"
  printf 'recommend: replay cost scales with items and the current docs carry the cumulative state. Run a docs-conformance recheck of the components, then set the marker in %s to %s and diff only from there\n' "$ledger" "$last_in_range"
else
  printf 'releases: %s\n' "$versions"
  printf 'cap: within budget (%d releases / %d items)\n' "$cap_releases" "$cap_items"
  if [[ -z "$last" ]]; then
    printf 'recommend: no read marker. After this range is applied, create %s with the marker line at %s\n' "$ledger" "$last_in_range"
  fi
fi

# The comparison is against the newest release IN THE RANGE, not the newest published:
# an explicit historical range is fully supported by an installed version that is
# older than the feed's newest release.
if [[ "$installed" != "unknown" && "$(vmax "$installed" "$last_in_range")" != "$installed" ]]; then
  printf 'warn: installed %s is older than the newest release in the range %s; update Claude Code before applying changes that reference it\n' "$installed" "$last_in_range"
fi
exit 0
