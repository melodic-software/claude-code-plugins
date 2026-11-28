#!/usr/bin/env bash
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

view_args=()
[[ -n "$repo" ]] && view_args=("$repo")
view="$(gh repo view "${view_args[@]}" --json nameWithOwner,url,sshUrl)" || die "gh repo view failed$fallback"
repo="$(jq -r '.nameWithOwner // empty' <<<"$view")"
gh_url="$(jq -r '.url // empty' <<<"$view")" gh_ssh="$(jq -r '.sshUrl // empty' <<<"$view")"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "gh reported no repository name"
[[ -n "$gh_url" ]] || die "gh reported no URL for $repo"
list_repo="$repo"
if [[ "$gh_url" =~ ^https?://([^/@]+@)?([^/:]+) && "${BASH_REMATCH[2],,}" != github.com ]]; then
  list_repo="${BASH_REMATCH[2]}/$repo"
fi
listing="$(gh pr list --state all --limit "$prs" --json number,createdAt,closedAt,files --repo "$list_repo")" ||
  die "gh pr list failed$fallback"

origin_url="$(git config --get remote.origin.url 2>/dev/null)" || origin_url=""
origin_path="" origin_ssh=0
if [[ "$origin_url" =~ ^(https?|git|ssh|git\+ssh)://([^/@]+@)?[^/]+/(.+)$ ]]; then
  origin_path="${BASH_REMATCH[3]}"
  [[ "${BASH_REMATCH[1]}" == *ssh* ]] && origin_ssh=1
elif [[ "$origin_url" =~ ^([^/@]+@)?[^/:]+:([^/].*)$ ]]; then
  origin_path="${BASH_REMATCH[2]}" origin_ssh=1
fi
origin_path="${origin_path%/}"
origin_path="${origin_path%.git}"
if [[ -n "$origin_path" && "${origin_path,,}" == "${repo,,}" ]]; then
  remote=origin
elif ((origin_ssh)) && [[ -n "$gh_ssh" ]]; then
  remote="$gh_ssh"
else
  remote="$gh_url"
fi
export GIT_TERMINAL_PROMPT=0

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

excluded=""
while IFS= read -r path; do
  base="${path##*/}" hit=0
  for glob in "${BUMP_GLOBS[@]}"; do
    # shellcheck disable=SC2053 # the right side is a glob by design
    [[ "$base" == $glob ]] && hit=1
  done
  for glob in "${excludes[@]}"; do
    target="$base"
    [[ "$glob" == */* ]] && target="$path"
    # shellcheck disable=SC2053 # the right side is a glob by design
    [[ "$target" == $glob ]] && hit=1
  done
  ((hit)) && excluded+="$path"$'\n'
done < <(jq -r '[.[] | (.files // [])[].path] | unique | .[]' <<<"$listing")

bump="$(jq -r --arg excl "$excluded" '
  ($excl | split("\n") | map(select(length > 0))) as $ex
  | [.[] | [(.files // [])[].path] | unique | .[] | select(IN($ex[]))]
  | group_by(.) | map(select(length > 1) | {p: .[0], n: length})
  | sort_by(-.n, .p) | map("\(.p) (\(.n) PRs)") | join(", ")' <<<"$listing")"
printf 'known bump hotspots: changelogs, lockfiles and version manifests conflict on every version bump, not through design, so they are left out of the ranking: %s\n' "${bump:-none}"

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

wanted=() fetch_err=()
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
  # An empty --refmap makes git ignore remote.<name>.fetch; only the command-line refspecs apply.
  # https://git-scm.com/docs/git-fetch
  if ! git fetch --quiet --no-tags --no-write-fetch-head --refmap= "$remote" "${specs[@]}" >/dev/null 2>&1; then
    for spec in "${specs[@]}"; do
      if ! err="$(git fetch --quiet --no-tags --no-write-fetch-head --refmap= "$remote" "$spec" 2>&1 >/dev/null)"; then
        n="${spec#+refs/pull/}"
        err="${err%%$'\n'*}"
        fetch_err[${n%%/*}]="${err//[[:cntrl:]]/ }"
      fi
    done
  fi
done
fetched=()
for n in "${numbers[@]}"; do
  if git rev-parse --verify -q "$ns/pr/$n^{commit}" >/dev/null; then
    fetched[n]=1
  else
    printf 'gap: PR #%s head could not be fetched from %s: %s; its pairs are not replayed\n' \
      "$n" "$remote" "${fetch_err[n]:-no error reported}"
  fi
done

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
