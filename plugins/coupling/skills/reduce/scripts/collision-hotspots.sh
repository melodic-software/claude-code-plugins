#!/usr/bin/env bash
# Rank files by measured merge conflicts between pull requests that were open
# at the same time. Run from the root of a clone of the repository.
#
#   collision-hotspots.sh --prs <n> [--repo <owner>/<repo>] [--max-pairs <m>]
#                         [--exclude <glob>]... [--dry-run]
#
# Reads the last <n> PRs of every state through gh (number, open and close
# times, changed files), pairs PRs whose open intervals overlap and that share a
# file, fetches each paired PR head into refs/collision-hotspots/<run-id>/pr/<n>,
# and replays every pair with `git merge-tree --write-tree`. A file is ranked
# once at least 3 replayed pairs shared it. Output, path last on every line:
#
#   gap: ...                   a PR whose file list hit gh's limit, or a head
#                              that could not be fetched
#   known bump hotspots: ...   excluded files (changelogs, lockfiles, version
#                              manifests, each --exclude) touched by 2+ PRs
#   pairs: ...                 pairs found, replayed and skipped by the cap
#   would replay: #a #b ...    --dry-run only; nothing is fetched or written
#   ranked: ...                then one `conflicts<TAB>pairs<TAB>path` row per
#                              ranked file, most conflicts first
#
# The run's refs are deleted on exit, on failure too; fetched objects stay
# until git's own gc. PR file paths are data: they never reach a shell word.
#
# Exit 0 done, 2 usage error, missing gh, jq or `merge-tree --write-tree`, not
# a repository, a failed gh or git call, or a PR path with a control character.
set -uo pipefail

MIN_PAIRS=3
GH_FILE_LIMIT=100
BUMP_GLOBS=('CHANGELOG*' '*.lock' '*-lock.*' 'package.json' 'plugin.json')

die() {
  printf 'collision-hotspots: %s\n' "$1" >&2
  exit 2
}
usage() { die "$1 (usage: --prs <n> [--repo <owner>/<repo>] [--max-pairs <m>] [--exclude <glob>]... [--dry-run])"; }

prs="" repo="" max_pairs=200 dry_run=0
excludes=()
while (($#)); do
  case "$1" in
  --dry-run)
    dry_run=1
    shift
    continue
    ;;
  --prs | --repo | --max-pairs | --exclude) (($# >= 2)) || usage "$1 needs a value" ;;
  *) usage "unknown argument: $1" ;;
  esac
  case "$1" in
  --prs) prs="$2" ;;
  --repo) repo="$2" ;;
  --max-pairs) max_pairs="$2" ;;
  *) excludes+=("$2") ;;
  esac
  shift 2
done
[[ "$prs" =~ ^[1-9][0-9]*$ ]] || usage "--prs must be a positive integer"
[[ "$max_pairs" =~ ^[1-9][0-9]*$ ]] || usage "--max-pairs must be a positive integer"
if [[ -n "$repo" && ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  usage "--repo must be <owner>/<repo>"
fi

fallback="; rank co-change from version-control history instead"
for tool in gh jq git; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found$fallback"
done
git rev-parse --verify -q HEAD >/dev/null 2>&1 || die "run from a git repository with at least one commit"
git merge-tree --write-tree --name-only HEAD HEAD >/dev/null 2>&1 ||
  die "this git has no 'merge-tree --write-tree'$fallback"

repo_args=()
[[ -n "$repo" ]] && repo_args=(--repo "$repo")
listing="$(gh pr list --state all --limit "$prs" --json number,createdAt,closedAt,files "${repo_args[@]}")" ||
  die "gh pr list failed$fallback"

# Shape and safety checks before any path is used: integer PR numbers, and no
# control character in any path (a tab or newline would split a row).
bad="$(jq -r '
  if type != "array" then "the gh listing is not an array"
  else
    (map(select((.number | type) != "number" or .number != (.number | floor) or .number < 1)) | length) as $badnum
    | ([.[] | .number as $n | (.files // [])[] | select(.path | test("[[:cntrl:]]")) | $n] | unique) as $ctl
    | if $badnum > 0 then "a PR number is not a positive integer"
      elif ($ctl | length) > 0 then "a file path in PR #\($ctl[0]) contains a control character"
      else empty end
  end' <<<"$listing")" || die "could not parse the gh listing"
[[ -z "$bad" ]] || die "$bad"

jq -r --argjson limit "$GH_FILE_LIMIT" '.[] | select((.files // []) | length >= $limit)
  | "gap: PR #\(.number) lists \($limit) files, gh\u0027s limit; files past it are not counted"' <<<"$listing"

# Classify each distinct path once: excluded when its basename matches a
# default glob, or when an --exclude glob matches the basename (glob without a
# slash) or the whole path (glob with one).
excluded=""
while IFS= read -r path; do
  base="${path##*/}" hit=0
  for glob in "${BUMP_GLOBS[@]}"; do
    # shellcheck disable=SC2053 # the right side is a glob by design
    [[ "$base" == $glob ]] && hit=1
  done
  for glob in "${excludes[@]}"; do
    if [[ "$glob" == */* ]]; then
      # shellcheck disable=SC2053
      [[ "$path" == $glob ]] && hit=1
    else
      # shellcheck disable=SC2053
      [[ "$base" == $glob ]] && hit=1
    fi
  done
  ((hit)) && excluded+="$path"$'\n'
done < <(jq -r '[.[] | (.files // [])[].path] | unique | .[]' <<<"$listing")

bump="$(jq -r --arg excl "$excluded" '
  ($excl | split("\n") | map(select(length > 0))) as $ex
  | [.[] | [(.files // [])[].path] | unique | .[] | select(IN($ex[]))]
  | group_by(.) | map(select(length > 1) | {p: .[0], n: length})
  | sort_by(-.n, .p) | map("\(.p) (\(.n) PRs)") | join(", ")' <<<"$listing")"
printf 'known bump hotspots: changelogs, lockfiles and version manifests conflict on every version bump, not through design, so they are left out of the ranking: %s\n' "${bump:-none}"

# Pairs: open intervals overlap (an open PR runs to now) and at least one
# ranked file is shared. Most shared files first, then the newest PRs. Each
# shared path appears once as a `p<TAB>path` line in index order, and each pair
# as `r<TAB>a<TAB>b<TAB>index...`, so no PR path is ever an array subscript:
# with bash 5.1 compatibility an arithmetic subscript is expanded twice, which
# would run a `$(...)` inside a file name.
pairs="$(jq -r --arg excl "$excluded" '
  ($excl | split("\n") | map(select(length > 0)) | map({key: ., value: true}) | from_entries) as $ex
  | [.[] | {n: .number, s: (.createdAt | fromdateiso8601),
            e: (if .closedAt == null then now else (.closedAt | fromdateiso8601) end),
            f: ([(.files // [])[].path] | unique | map(select($ex[.] | not)))}
     | select(.f | length > 0) | .set = (.f | map({key: ., value: true}) | from_entries)] as $p
  | [range(0; $p | length) as $i | range($i + 1; $p | length) as $j
     | $p[$i] as $a | $p[$j] as $b
     | select($a.s < $b.e and $b.s < $a.e)
     | [$a.f[] | select($b.set[.])] as $sh
     | select($sh | length > 0)
     | {a: ([$a.n, $b.n] | min), b: ([$a.n, $b.n] | max), sh: $sh}]
  | sort_by(-(.sh | length), -.b, -.a) as $pairs
  | ([$pairs[].sh[]] | unique) as $all
  | ($all | to_entries | map({key: .value, value: .key}) | from_entries) as $ix
  | ($all[] | "p\t\(.)"),
    ($pairs[] | "r\t\(.a)\t\(.b)\t\(.sh | map($ix[.]) | join("\t"))")' <<<"$listing")" || die "could not pair the PRs"

paths=() pair_lines=()
while IFS= read -r line; do
  case "$line" in
  p$'\t'*) paths+=("${line#p$'\t'}") ;;
  r$'\t'*)
    line="${line#r$'\t'}"
    [[ "$line" =~ ^[0-9]+$'\t'[0-9]+($'\t'[0-9]+)+$ ]] || die "unexpected pair line"
    pair_lines+=("$line")
    ;;
  *) ;;
  esac
done <<<"$pairs"
total=${#pair_lines[@]}
replay=$((total < max_pairs ? total : max_pairs))
printf 'pairs: %d overlapping pairs share a ranked file; replaying %d (--max-pairs %d), skipped %d\n' \
  "$total" "$replay" "$max_pairs" $((total - replay))
pair_lines=("${pair_lines[@]:0:replay}")

if ((dry_run)); then
  for line in "${pair_lines[@]}"; do
    IFS=$'\t' read -r a b shared_rest <<<"$line"
    IFS=$'\t' read -r -a shared <<<"$shared_rest"
    printf 'would replay: #%s #%s (%d shared files)\n' "$a" "$b" "${#shared[@]}"
  done
  exit 0
fi

ns="refs/collision-hotspots/${EPOCHSECONDS:-0}-$$-$RANDOM"
cleanup() {
  git for-each-ref --format='delete %(refname)' "$ns/" | git update-ref --stdin >/dev/null 2>&1
}
trap cleanup EXIT
trap 'exit 2' INT TERM HUP

remote=origin
if [[ -n "$repo" ]]; then
  remote="$(gh repo view "$repo" --json url --jq .url)" || die "gh repo view failed for --repo"
  [[ -n "$remote" ]] || die "gh reported no URL for --repo"
fi

# PR numbers and path indexes are digits only (checked above), so the indexed
# arrays below never evaluate untrusted text.
wanted=()
for line in "${pair_lines[@]}"; do
  IFS=$'\t' read -r a b _ <<<"$line"
  wanted[a]=1 wanted[b]=1
done
numbers=("${!wanted[@]}")
for ((i = 0; i < ${#numbers[@]}; i += 50)); do
  specs=()
  for n in "${numbers[@]:i:50}"; do
    [[ "$n" =~ ^[0-9]+$ ]] || die "unexpected PR number"
    specs+=("+refs/pull/$n/head:$ns/pr/$n")
  done
  # An empty --refmap stops a configured remote.<name>.fetch from also writing
  # remote-tracking refs for these heads.
  if ! git fetch --quiet --no-tags --no-write-fetch-head --refmap= "$remote" "${specs[@]}" 2>/dev/null; then
    for spec in "${specs[@]}"; do
      git fetch --quiet --no-tags --no-write-fetch-head --refmap= "$remote" "$spec" 2>/dev/null || true
    done
  fi
done
fetched=()
for n in "${numbers[@]}"; do
  if git rev-parse --verify -q "$ns/pr/$n^{commit}" >/dev/null; then
    fetched[n]=1
  else
    printf 'gap: PR #%s head could not be fetched; its pairs are not replayed\n' "$n"
  fi
done

# Counts are indexed by path index; the names git reports as conflicted are
# compared as strings and never used as subscripts.
pair_count=() conflict_count=()
for line in "${pair_lines[@]}"; do
  IFS=$'\t' read -r a b shared_rest <<<"$line"
  [[ -n "${fetched[a]:-}" && -n "${fetched[b]:-}" ]] || continue
  IFS=$'\t' read -r -a shared <<<"$shared_rest"
  mapfile -d '' -t out < <(git merge-tree --write-tree --name-only --no-messages -z "$ns/pr/$a" "$ns/pr/$b")
  wait $!
  rc=$?
  ((rc <= 1)) || die "git merge-tree failed on PRs #$a and #$b (exit $rc)"
  for idx in "${shared[@]}"; do
    pair_count[idx]=$((${pair_count[idx]:-0} + 1))
    for name in "${out[@]:1}"; do
      if [[ "$name" == "${paths[idx]}" ]]; then
        conflict_count[idx]=$((${conflict_count[idx]:-0} + 1))
        break
      fi
    done
  done
done

rows=()
for idx in "${!pair_count[@]}"; do
  n=${pair_count[idx]}
  ((n >= MIN_PAIRS)) &&
    rows+=("$(printf '%d\t%d\t%s' "${conflict_count[idx]:-0}" "$n" "${paths[idx]}")")
done
if ((${#rows[@]} == 0)); then
  printf 'ranked: none; no file was shared by %d or more replayed pairs\n' "$MIN_PAIRS"
  exit 0
fi
printf 'ranked: %d files shared by %d or more replayed pairs (conflicts, pairs, path)\n' "${#rows[@]}" "$MIN_PAIRS"
printf '%s\n' "${rows[@]}" | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2nr -k3,3
