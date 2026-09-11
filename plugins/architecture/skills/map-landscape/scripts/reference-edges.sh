#!/usr/bin/env bash
# Extract typed reference edges from ONE repository's tracked files, as JSON.
#
# WHY. A landscape drawn only from repositories that happen to be checked out
# locally shows one node and no edges, because the related systems are named by
# REFERENCE, not by adjacency on disk. This script reads what a repository says
# about other repositories and types each reference by the surface that carries
# it, so an edge means something specific instead of "these names co-occur".
#
# Extraction is per source type on purpose. A single `owner/repo` regex over all
# tracked text is what makes a landscape untrustworthy: on a docs-heavy
# repository it matches `sponsors/...` out of a funding URL, `en/...` out of a
# documentation path, and every `acme/billing` in a fixture. Each rule below
# either anchors on a syntax that only ever names a repository (`uses:`, a
# module path, a marketplace source) or requires the owner to match this
# repository's own.
#
# Usage:
#   reference-edges.sh <repo-path> [--owner <owner>]
#   reference-edges.sh --help
#
# --owner overrides the owner segment taken from the `origin` remote. It decides
# which references are `internal` (same owner) and which are `external`, and it
# is the only way a bare `owner/repo` token is trusted at all.
#
# Output: JSON Lines on stdout, one object per (target, type) pair, sorted:
#
#   {"from":…,"to":…,"type":…,"relation":…,"count":N,"files":[…]}
#
#   from      this repository's directory basename
#   to        `owner/repo`
#   type      uses-workflow | installs-plugin | depends-on | cites
#   relation  internal (owner matches this repository's) | external
#   count     how many references of this type name that target
#   files     up to FILE_CAP repo-relative files carrying them, sorted
#
# Edge types, and the syntax each one trusts:
#
#   uses-workflow   a `uses:` step in a workflow or composite action. Names a
#                   reusable workflow or action this repository RUNS.
#   installs-plugin a marketplace `source`, or a `/plugin marketplace add`
#                   line. Names a repository this one INSTALLS FROM.
#   depends-on      a Go module path, or a git dependency URL in a package
#                   manifest. Names code this repository BUILDS AGAINST.
#   cites           a github.com URL, or a bare `owner/repo` whose owner is this
#                   repository's own, anywhere else in tracked text. The weakest
#                   type: it means "mentioned", nothing more.
#
# Nothing here fetches, and nothing is inferred from a name's resemblance to
# another. A repository referenced only by a name that looks like a sibling
# produces no edge.
#
# Portability: bash plus POSIX awk/grep/sed, and git for the tracked-file scope.
# No jq, no `grep -P`, no python.
#
# Exit: 0 = edges emitted (possibly none); 1 = the path is not a readable git
# repository; 2 = usage.
set -uo pipefail

FILE_CAP=5

usage() {
  # Print the header comment block only, selected by comment marker so --help
  # stays correct as the block grows.
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

repo_arg=""
owner_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --owner)
    shift
    [[ $# -gt 0 ]] || {
      printf 'reference-edges.sh: --owner needs a value\n' >&2
      exit 2
    }
    owner_override="$1"
    ;;
  --owner=*) owner_override="${1#--owner=}" ;;
  -*)
    printf 'reference-edges.sh: unknown option: %s\n' "$1" >&2
    exit 2
    ;;
  *)
    [[ -z "$repo_arg" ]] || {
      printf 'reference-edges.sh: one repository path only\n' >&2
      exit 2
    }
    repo_arg="$1"
    ;;
  esac
  shift
done

if [[ -z "$repo_arg" ]]; then
  printf 'usage: reference-edges.sh <repo-path> [--owner <owner>]\n' >&2
  exit 2
fi

if [[ ! -d "$repo_arg" ]]; then
  printf 'reference-edges.sh: not a directory: %s\n' "$repo_arg" >&2
  exit 1
fi

repo="$(cd "$repo_arg" 2>/dev/null && pwd)" || {
  printf 'reference-edges.sh: unreadable: %s\n' "$repo_arg" >&2
  exit 1
}
name="$(basename "$repo")"

if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'reference-edges.sh: not a git repository, no tracked files to read: %s\n' "$repo" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Owner
# ---------------------------------------------------------------------------

# The owner segment of a github.com remote. Only github.com is read here: this
# owner decides which BARE `owner/repo` tokens are trusted, and trusting a bare
# token on a host whose path shape we have not verified is how fixture names
# become systems.
remote_owner_segment() {
  local url
  url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 1
  url="${url%.git}"
  case "$url" in
  *github.com[:/]*)
    url="${url#*github.com}"
    url="${url#:}"
    url="${url#/}"
    case "$url" in
    */*) printf '%s' "${url%%/*}" ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

owner="$owner_override"
[[ -n "$owner" ]] || owner="$(remote_owner_segment)" || owner=""

# ---------------------------------------------------------------------------
# Reserved GitHub path prefixes
# ---------------------------------------------------------------------------
#
# `github.com/<first>/<second>` is only an owner/repo pair when <first> is an
# account. These first segments are GitHub's own product surfaces, so a funding
# link (`github.com/sponsors/acme`) or a marketplace page is not a repository.
is_reserved_owner() {
  case "$1" in
  sponsors | features | orgs | settings | apps | marketplace | topics | \
    collections | about | pricing | security | login | join | new | notifications | \
    explore | trending | events | site | contact | readme | pulls | issues | \
    codespaces | enterprise | customer-stories | organizations)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# A segment that can actually be a GitHub owner or repository name. This is the
# backstop for every extractor: a regex tuned to one surface still catches
# neighbouring punctuation and documentation templates, so `<source>`,
# ``acme-tools` ``, and `claude-code-plugins`;` are rejected here rather than by
# making each pattern progressively more baroque.
is_valid_segment() {
  case "$1" in
  "" | . | ..) return 1 ;;
  *[!A-Za-z0-9_.-]*) return 1 ;;
  *) return 0 ;;
  esac
}

# Documentation placeholders. `github.com/owner/repo` in a usage example names
# the SHAPE of a reference, not a repository, and charting it invents a system
# called `owner/repo` that every docs-heavy repository would appear to depend
# on. `example` and `acme` are the conventional stand-in names.
is_placeholder_owner() {
  case "$1" in
  owner | org | user | username | your-org | your-owner | myorg | my-org | \
    example | example-org | acme | acme-corp | foo | bar | OWNER | ORG | USER)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Emission
# ---------------------------------------------------------------------------

# A test, fixture, or eval file names repositories that do not exist: `acme/api`
# and `Owner/Repo` are scaffolding for an assertion, not systems this repository
# relates to. Charting them fills the landscape with invented nodes, so the
# whole file is out of scope for every extractor.
is_fixture_file() {
  case "$1" in
  *.test.sh | *.test.ts | *.test.js | *.spec.ts | *.spec.js) return 0 ;;
  test_*.py | */test_*.py | *_test.py | *_test.go) return 0 ;;
  */tests/* | tests/*) return 0 ;;
  */evals/* | evals/*) return 0 ;;
  */fixtures/* | fixtures/*) return 0 ;;
  */testdata/* | testdata/*) return 0 ;;
  *) is_own_artifact "$1" ;;
  esac
}

# This skill's own committed output names every repository it charted, so once
# those artifacts are tracked the extractor would read them back as fresh
# evidence: each run would raise every count by one and cite the record as its
# own source, and a drift gate could never report clean again. The artifact
# names are fixed by this skill's contract while only their directory varies,
# so matching the basename is enough to keep derived output out of the input.
is_own_artifact() {
  case "${1##*/}" in
  landscape.json | landscape.md | landscape.dsl | landscape-notes.md | portfolio.md)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# GitHub treats an owner and a repository name case-insensitively, so
# `Melodic-Software/Claude-Code-Plugins` and `melodic-software/claude-code-plugins`
# are one target, and one of them is this repository referring to itself. Folded
# with `nocasematch` rather than a `tr` subshell: this runs once per hit, and a
# fork per hit is the cost that dominated the sibling collector. The prior
# setting is restored so the shopt never leaks into the extractors' own globs.
is_self_reference() {
  local result=1 had_nocase=0
  [[ -n "$owner" ]] || return 1
  shopt -q nocasematch && had_nocase=1
  shopt -s nocasematch
  [[ "$1" == "$owner/$name" ]] && result=0
  [[ $had_nocase -eq 1 ]] || shopt -u nocasematch
  return "$result"
}

# Raw hits accumulate here as `type<TAB>owner/repo<TAB>file`, one per line, and
# are aggregated once at the end. Collecting first and counting later keeps each
# extractor a plain producer with no shared counter to get wrong.
HITS=""
add_hit() {
  # $1 type, $2 owner/repo, $3 file
  local target="$2" file="$3" o r
  is_fixture_file "$file" && return 0
  # A bare token with no slash names no repository. Without this guard the
  # expansions below both return the whole token and it emits as `X/X`.
  case "$target" in
  */*) ;;
  *) return 0 ;;
  esac
  o="${target%%/*}"
  r="${target#*/}"
  r="${r%%/*}"
  # A `uses:` pin carries its ref; the repository is not named `checkout@<sha>`.
  r="${r%%@*}"
  # A clone URL carries the suffix; the repository is not named `repo.git`.
  r="${r%.git}"
  # Prose ends sentences. A dot is legal INSIDE a repository name (`docs.rs`)
  # and never terminates one, so `owner/repo.` in running text is `owner/repo`
  # plus the full stop that followed it.
  while [[ "$r" == *. ]]; do r="${r%.}"; done
  is_valid_segment "$o" || return 0
  is_valid_segment "$r" || return 0
  is_reserved_owner "$o" && return 0
  is_placeholder_owner "$o" && return 0
  # A reference to this repository itself is not an edge.
  is_self_reference "$o/$r" && return 0
  HITS="$HITS$1	$o/$r	$file"$'\n'
}

# ---------------------------------------------------------------------------
# Extractors
# ---------------------------------------------------------------------------

# `git grep -I` skips binary files; `-o` prints each match on its own line
# prefixed by the file, which is where the per-edge `files` list comes from.
grep_tracked() {
  local pattern="$1"
  shift
  git -C "$repo" grep -I -o -E -e "$pattern" -- "$@" 2>/dev/null
}

# 1. uses-workflow. A `uses:` step names a reusable workflow or action. Local
#    (`./path`) and container (`docker://`) forms name no repository.
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  match="${line#*:}"
  ref="${match#*uses:}"
  ref="${ref#"${ref%%[![:space:]]*}"}"
  case "$ref" in
  ./* | docker://*) continue ;;
  *) ;;
  esac
  add_hit uses-workflow "$ref" "$file"
done < <(grep_tracked '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[^[:space:]]+' \
  '.github/workflows' '.github/actions' '*.yml' '*.yaml')

# 2. installs-plugin. A marketplace source, or the documented install line. A
#    LOCAL source (`./plugins/foo`) is this repository's own component, not
#    another repository: a monorepo marketplace declares one per plugin, so
#    reading them as references invents an edge per directory.
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  match="${line#*:}"
  ref="${match##*[ \"]}"
  case "$ref" in
  ./* | ../* | /* | "") continue ;;
  *) ;;
  esac
  add_hit installs-plugin "$ref" "$file"
done < <(grep_tracked '(plugin marketplace add[[:space:]]+|"source"[[:space:]]*:[[:space:]]*")[A-Za-z0-9_./-]+' \
  '*.json' '*.md')

# 3. depends-on. A Go module path names its repository directly.
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  match="${line#*:}"
  ref="${match#*github.com/}"
  add_hit depends-on "$ref" "$file"
done < <(grep_tracked '(^|[^A-Za-z0-9.-])github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' 'go.mod' '*/go.mod')

# 4. cites, from a github.com URL. Any owner; the reserved-prefix filter in
#    add_hit drops GitHub's own product pages.
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  match="${line#*:}"
  case "$file" in
  go.mod | */go.mod) continue ;;
  *) ;;
  esac
  ref="${match#*github.com/}"
  add_hit cites "$ref" "$file"
done < <(grep_tracked '(^|[^A-Za-z0-9.-])github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+')

# 5. cites, from a BARE `owner/repo` token, and only when the owner is this
#    repository's own. This is the rule that finds a sibling named in prose or
#    in a rule file without a URL, and the owner requirement is what keeps
#    `acme/billing` in a fixture from becoming a system.
if [[ -n "$owner" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    file="${line%%:*}"
    match="${line#*:}"
    ref="${match#*"$owner/"}"
    add_hit cites "$owner/$ref" "$file"
  done < <(grep_tracked "(^|[^A-Za-z0-9_./-])${owner}/[A-Za-z0-9_.-]+")
fi

# ---------------------------------------------------------------------------
# Aggregate and emit
# ---------------------------------------------------------------------------
#
# One record per (target, type). A target reached by two surfaces earns two
# records, because "runs its CI" and "is mentioned in a doc" are different
# claims and collapsing them loses the stronger one.

[[ -n "$HITS" ]] || exit 0

printf '%s' "$HITS" | LC_ALL=C sort | awk -F'\t' \
  -v from="$name" -v owner="$owner" -v cap="$FILE_CAP" '
  function esc(s) {
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
    return s
  }
  function flush(  i, rel, out) {
    if (key == "") return
    rel = (owner != "" && curowner == owner) ? "internal" : "external"
    out = "{\"from\":\"" esc(from) "\",\"to\":\"" esc(curto) "\","
    out = out "\"type\":\"" esc(curtype) "\",\"relation\":\"" rel "\","
    out = out "\"count\":" count ",\"files\":["
    for (i = 1; i <= nfiles && i <= cap; i++) {
      if (i > 1) out = out ","
      out = out "\"" esc(files[i]) "\""
    }
    out = out "]}"
    print out
  }
  {
    k = $2 SUBSEP $1
    if (k != key) {
      flush()
      key = k; curtype = $1; curto = $2
      split(curto, parts, "/"); curowner = parts[1]
      count = 0; nfiles = 0; delete files; delete seen
    }
    count++
    if (!($3 in seen)) { seen[$3] = 1; files[++nfiles] = $3 }
  }
  END { flush() }
'
