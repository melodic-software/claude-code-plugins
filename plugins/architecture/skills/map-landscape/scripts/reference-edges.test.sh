#!/usr/bin/env bash
# Self-contained tests for reference-edges.sh (skill-script shape, per
# docs/conventions/shell-test-helpers/README.md: per-plugin assertion
# primitives are duplicated on purpose, never shared across plugins).
#
# Every fixture is built in a mktemp directory and torn down on exit; nothing
# here reads or writes a real repository.
set -uo pipefail

# Isolate the fixture repositories from any ambient git environment, for the
# reason the sibling suite documents: `git -C` changes directory but does not
# override discovery, so an exported GIT_DIR would land these throwaway
# identities in the CALLER's .git/config.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/reference-edges.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3
  actual: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3
  actual: $2" ;;
  *) pass "$1" ;;
  esac
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

make_repo() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir"
  git -C "$dir" init --quiet 2>/dev/null
  git -C "$dir" config user.email "fixture@example.invalid"
  git -C "$dir" config user.name "Fixture"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.autocrlf false
  git -C "$dir" remote add origin "https://github.com/fixture-owner/$1.git"
  printf '%s' "$dir"
}

commit_repo() {
  git -C "$1" add -A 2>/dev/null
  git -C "$1" commit --quiet --no-verify -m "fixture" 2>/dev/null
}

# The record for one (to, type) pair, or the empty string.
edge() {
  printf '%s\n' "$1" | grep -F "\"to\":\"$2\"" | grep -F "\"type\":\"$3\"" | head -1
}

# One scalar out of an edge record.
field() {
  printf '%s' "$1" | awk -v key="$2" '
    {
      pat = "\"" key "\":"
      i = index($0, pat)
      if (i == 0) { print ""; exit }
      rest = substr($0, i + length(pat))
      if (substr(rest, 1, 1) == "\"") {
        rest = substr(rest, 2)
        print substr(rest, 1, index(rest, "\"") - 1)
      } else {
        j = 1
        while (j <= length(rest) && substr(rest, j, 1) ~ /[0-9]/) j++
        print substr(rest, 1, j - 1)
      }
    }
  '
}

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed" >&2
  exit 0
fi

# --- Case group 1: uses-workflow --------------------------------------------
wf_repo="$(make_repo runner)"
mkdir -p "$wf_repo/.github/workflows"
cat >"$wf_repo/.github/workflows/ci.yml" <<'YML'
jobs:
  build:
    uses: fixture-owner/ci-workflows/.github/workflows/build.yml@v2
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
      - uses: ./.github/actions/local-thing
      - uses: docker://alpine:3.20
  test:
    uses: fixture-owner/ci-workflows/.github/workflows/test.yml@v2
YML
commit_repo "$wf_repo"
out="$(bash "$SCRIPT" "$wf_repo")"
e="$(edge "$out" fixture-owner/ci-workflows uses-workflow)"
assert_equals "uses: the reusable workflow is an edge" "$(field "$e" to)" "fixture-owner/ci-workflows"
assert_equals "uses: both references are counted" "$(field "$e" count)" "2"
assert_equals "uses: a same-owner target is internal" "$(field "$e" relation)" "internal"
assert_contains "uses: the workflow file is cited" "$e" '.github/workflows/ci.yml'
e="$(edge "$out" actions/checkout uses-workflow)"
assert_equals "uses: the pinned ref is stripped from the repository name" "$(field "$e" to)" "actions/checkout"
assert_equals "uses: a third-party action is external" "$(field "$e" relation)" "external"
assert_not_contains "uses: a local action path is not a repository" "$out" '"to":"."'
assert_not_contains "uses: a docker image is not a repository" "$out" 'alpine'

# --- Case group 2: installs-plugin ------------------------------------------
mk_repo="$(make_repo marketplace)"
mkdir -p "$mk_repo/.claude-plugin"
cat >"$mk_repo/.claude-plugin/marketplace.json" <<'JSON'
{
  "plugins": [
    { "name": "local-one", "source": "./plugins/local-one" },
    { "name": "remote-one", "source": "vendor-org/their-plugins" }
  ]
}
JSON
commit_repo "$mk_repo"
out="$(bash "$SCRIPT" "$mk_repo")"
assert_contains "install: a remote source is an edge" "$out" '"to":"vendor-org/their-plugins"'
assert_contains "install: it is typed as installs-plugin" "$out" '"type":"installs-plugin"'
assert_not_contains "install: a local source is this repository's own component" "$out" '"to":"./plugins'
assert_not_contains "install: no edge is invented from the local path" "$out" 'local-one'

# --- Case group 3: depends-on -----------------------------------------------
go_repo="$(make_repo service)"
cat >"$go_repo/go.mod" <<'GOMOD'
module github.com/fixture-owner/service

go 1.23

require github.com/spf13/cobra v1.8.1
GOMOD
commit_repo "$go_repo"
out="$(bash "$SCRIPT" "$go_repo")"
e="$(edge "$out" spf13/cobra depends-on)"
assert_equals "go: the required module is a depends-on edge" "$(field "$e" to)" "spf13/cobra"
assert_not_contains "go: the module's own path is not a self-edge" "$out" '"to":"fixture-owner/service"'

# --- Case group 4: cites, and what is NOT cited -----------------------------
docs_repo="$(make_repo handbook)"
mkdir -p "$docs_repo/docs"
cat >"$docs_repo/docs/notes.md" <<'MD'
Our conventions live in fixture-owner/standards and we mirror
fixture-owner/standards again here.

See <https://github.com/anthropics/claude-code> for the CLI, and
<https://docs.github.com/en/rest/quickstart> for the API.

Sponsor us at <https://github.com/sponsors/fixture-owner>.

A usage example: `git clone https://github.com/owner/repo.git`.

An unrelated third party's bare token, other-org/their-thing, is not a link.
MD
commit_repo "$docs_repo"
out="$(bash "$SCRIPT" "$docs_repo")"
e="$(edge "$out" fixture-owner/standards cites)"
assert_equals "cites: a bare same-owner token is an edge" "$(field "$e" to)" "fixture-owner/standards"
assert_equals "cites: repeated references are counted, not de-duplicated per file" "$(field "$e" count)" "2"
assert_contains "cites: a github.com URL is an edge" "$out" '"to":"anthropics/claude-code"'
assert_not_contains "cites: a docs.github.com path is not an owner" "$out" '"to":"en/'
assert_not_contains "cites: a sponsors URL is not a repository" "$out" '"to":"sponsors/'
assert_not_contains "cites: a documentation placeholder is not a repository" "$out" '"to":"owner/repo"'
assert_not_contains "cites: a bare token from another owner is not trusted" "$out" 'other-org/their-thing'

# --- Case group 5: fixtures and self-references -----------------------------
noise_repo="$(make_repo charted)"
mkdir -p "$noise_repo/plugins/thing/evals" "$noise_repo/docs"
cat >"$noise_repo/plugins/thing/audit.test.sh" <<'SH'
# fixture data: acme-tools/api and Gone/Away and fixture-owner/ghost
SH
cat >"$noise_repo/plugins/thing/evals/evals.json" <<'JSON'
{ "note": "see fixture-owner/eval-only for the shape" }
JSON
cat >"$noise_repo/docs/real.md" <<'MD'
We depend on fixture-owner/ci-workflows.
This repository is Fixture-Owner/Charted, and also fixture-owner/charted.
MD
commit_repo "$noise_repo"
out="$(bash "$SCRIPT" "$noise_repo")"
assert_contains "noise: a real doc reference is still charted" "$out" '"to":"fixture-owner/ci-workflows"'
assert_not_contains "noise: a .test.sh fixture name is not a system" "$out" 'Gone/Away'
assert_not_contains "noise: a test-file same-owner token is not a system" "$out" 'fixture-owner/ghost'
assert_not_contains "noise: an evals fixture is not a system" "$out" 'fixture-owner/eval-only'
assert_not_contains "noise: the repository does not cite itself" "$out" '"to":"fixture-owner/charted"'

# This skill's own committed output names every repository it charted. Reading
# it back would raise every count on each run and cite the record as its own
# evidence, so a drift gate could never report clean.
mkdir -p "$noise_repo/docs/architecture"
cat >"$noise_repo/docs/architecture/landscape.json" <<'JSON'
{"repositories":[],"edges":[{"to":"fixture-owner/from-the-record"}]}
JSON
printf 'System(x, "fixture-owner/also-from-the-record")\n' \
  >"$noise_repo/docs/architecture/landscape.md"
printf '| fixture-owner/portfolio-row | owner |\n' \
  >"$noise_repo/docs/architecture/portfolio.md"
commit_repo "$noise_repo"
out="$(bash "$SCRIPT" "$noise_repo")"
assert_not_contains "artifact: the record is not evidence for its own edges" "$out" 'from-the-record'
assert_not_contains "artifact: nor is the rendered diagram" "$out" 'also-from-the-record'
assert_not_contains "artifact: nor the portfolio table" "$out" 'portfolio-row'
assert_contains "artifact: a real doc reference still survives alongside them" "$out" '"to":"fixture-owner/ci-workflows"'
assert_not_contains "noise: nor in another case" "$out" '"to":"Fixture-Owner/Charted"'

# --- Case group 6: the .git suffix ------------------------------------------
clone_repo="$(make_repo cloner)"
mkdir -p "$clone_repo/docs"
cat >"$clone_repo/docs/setup.md" <<'MD'
Clone <https://github.com/vendor-org/toolkit.git> to get started.
MD
commit_repo "$clone_repo"
out="$(bash "$SCRIPT" "$clone_repo")"
assert_contains "clone: the .git suffix is not part of the repository name" "$out" '"to":"vendor-org/toolkit"'
assert_not_contains "clone: and the suffixed form is not emitted" "$out" 'toolkit.git'

# --- Case group 7: --owner overrides the remote -----------------------------
out="$(bash "$SCRIPT" "$docs_repo" --owner other-org)"
assert_contains "owner: the override trusts that owner's bare tokens" "$out" '"to":"other-org/their-thing"'
assert_contains "owner: and marks them internal" "$out" '"relation":"internal"'
out="$(bash "$SCRIPT" "$docs_repo" --owner=other-org)"
assert_contains "owner: the = spelling works too" "$out" '"to":"other-org/their-thing"'

# --- Case group 8: a repository with nothing to say -------------------------
quiet_repo="$(make_repo quiet)"
printf 'Nothing references anything here.\n' >"$quiet_repo/README.md"
commit_repo "$quiet_repo"
out="$(bash "$SCRIPT" "$quiet_repo")"
rc=$?
assert_equals "quiet: no edges is exit 0, not an error" "$rc" "0"
assert_equals "quiet: and emits nothing" "$out" ""

# --- Case group 9: quoted YAML scalars --------------------------------------
#
# `uses:` takes an ordinary YAML scalar, which may be quoted either way. The
# quote belongs to the syntax, and an owner segment still carrying one fails the
# character check and drops the edge without saying so.
quoted_repo="$(make_repo quoted)"
mkdir -p "$quoted_repo/.github/workflows"
{
  printf 'jobs:\n  build:\n'
  printf '    uses: "fixture-owner/ci-workflows/.github/workflows/build.yml@v1"\n'
  printf '    steps:\n'
  printf "      - uses: 'actions/checkout@v4'\n"
  printf '      - uses: actions/setup-node@v4\n'
} >"$quoted_repo/.github/workflows/ci.yml"
commit_repo "$quoted_repo"
quoted_out="$(bash "$SCRIPT" "$quoted_repo")"
# By TYPE, not just by target. A same-owner bare token is also a `cites` hit, so
# asserting the target alone would pass on the citation while the workflow edge
# this case exists for stayed missing.
uses_line() { printf '%s\n' "$quoted_out" | grep -F '"type":"uses-workflow"' | grep -F "\"to\":\"$1\""; }
assert_contains "quoted: a double-quoted reusable workflow is still a workflow edge" \
  "$(uses_line fixture-owner/ci-workflows)" '"type":"uses-workflow"'
assert_contains "quoted: a single-quoted action is too" \
  "$(uses_line actions/checkout)" '"type":"uses-workflow"'
assert_contains "quoted: the unquoted form is unaffected" \
  "$(uses_line actions/setup-node)" '"type":"uses-workflow"'
assert_not_contains "quoted: no quote survives into a repository name" \
  "$quoted_out" '"to":"\"'

# --- Case group 10: --print-owner -------------------------------------------
#
# The record has to name the organisation the graph was drawn from, and a second
# implementation of that resolution would eventually disagree with this one.
owner_out="$(bash "$SCRIPT" "$quoted_repo" --print-owner)"
assert_equals "print-owner: the origin owner, and no edges" "$owner_out" "fixture-owner"
override_out="$(bash "$SCRIPT" "$quoted_repo" --owner other-co --print-owner)"
assert_equals "print-owner: the override wins" "$override_out" "other-co"
noremote_repo="$TEST_TMPDIR/no-remote"
mkdir -p "$noremote_repo"
git -C "$noremote_repo" init --quiet 2>/dev/null
git -C "$noremote_repo" config user.email "fixture@example.invalid"
git -C "$noremote_repo" config user.name "Fixture"
git -C "$noremote_repo" config commit.gpgsign false
printf 'no origin here\n' >"$noremote_repo/README.md"
commit_repo "$noremote_repo"
assert_equals "print-owner: no resolvable owner reads unknown" \
  "$(bash "$SCRIPT" "$noremote_repo" --print-owner)" "unknown"

# --- Case group 11: usage and bad paths --------------------------------------
bash "$SCRIPT" >/dev/null 2>&1
assert_equals "usage: no arguments exits 2" "$?" "2"

bash "$SCRIPT" "$TEST_TMPDIR/does-not-exist" >/dev/null 2>&1
assert_equals "usage: a missing path exits 1" "$?" "1"

plain_dir="$TEST_TMPDIR/not-a-repo"
mkdir -p "$plain_dir"
bad_out="$(bash "$SCRIPT" "$plain_dir" 2>&1)"
assert_equals "usage: a non-git directory exits 1" "$?" "1"
assert_contains "usage: and says why" "$bad_out" "not a git repository"

bash "$SCRIPT" "$quiet_repo" --owner >/dev/null 2>&1
assert_equals "usage: --owner without a value exits 2" "$?" "2"

bash "$SCRIPT" "$quiet_repo" "$docs_repo" >/dev/null 2>&1
assert_equals "usage: two repository paths exit 2" "$?" "2"

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
exit 0
