#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/repin-ci-workflows.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=test-git-helpers.sh
. "$SCRIPT_DIR/test-git-helpers.sh" || exit 2

OLD=1111111111111111111111111111111111111111
NEW=2222222222222222222222222222222222222222
OTHER=b8bdd7fa2319b2457cbbef32c5348c394b9bc3f6
CHECKOUT=3d3c42e5aac5ba805825da76410c181273ba90b1
A=melodic-software/ci-workflows/.github/actions

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

mkdir -p "$scratch/bin"
cat >"$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
[[ "${1:-}" == api ]] || { echo "stub gh: unsupported ${1:-}" >&2; exit 64; }
shift
path='' jq='.'
while (($#)); do
  case "$1" in
    --jq) jq="$2"; shift 2 ;;
    -*) shift ;;
    *) [[ -n "$path" ]] || path="$1"; shift ;;
  esac
done
case "$path" in
  */releases) json="${STUB_RELEASES:?}" ;;
  */git/ref/tags/*) json="${STUB_REF:?}" ;;
  */git/tags/*) json="${STUB_TAG:?}" ;;
  */compare/*) [[ "${STUB_COMPARE:-}" == fail ]] && { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }; json="${STUB_COMPARE:?}" ;;
  *) echo "stub gh: unexpected route $path" >&2; exit 64 ;;
esac
jq -r "$jq" <<<"$json"
STUB
chmod +x "$scratch/bin/gh"

mk_repo() {
  local dir="$1" second="${2:-$OLD}"
  mkdir -p "$dir/.github/workflows" "$dir/docs/conventions/pr-pipeline" "$dir/tests"
  cat >"$dir/.github/workflows/lane.yml" <<EOF
jobs:
  run:
    uses: melodic-software/ci-workflows/.github/workflows/intake-triage.yml@main
  act:
    steps:
      - uses: actions/checkout@${CHECKOUT} # v7.0.1
        with:
          repository: melodic-software/ci-workflows
          ref: ${OLD} # v0.74.0
      - uses: ${A}/run-claude-cli@${OLD} # v0.74.0
      - uses: ${A}/select-model-credential@${second} # v0.74.0
EOF
  cat >"$dir/.github/workflows/pr-check-managed-files-hosted.yml" <<EOF
      - uses: ${A}/check-managed-files@${OLD} # v0.74.0
EOF
  echo "[run-claude-cli](https://github.com/melodic-software/ci-workflows/blob/${OLD}/README.md)" \
    >"$dir/docs/conventions/pr-pipeline/pr-run-activity.md"
  echo "fixture ${OTHER}" >"$dir/tests/fixture.txt"
  echo readme >"$dir/README.md"
  git_init_test_repo "$dir"
  git_test_config "$dir" add -A
  git_test_config "$dir" commit -qm init
}

run() {
  local want="$1" name="$2" got
  shift 2
  LAST_OUTPUT="$(env -u GITHUB_OUTPUT PATH="$scratch/bin:$PATH" bash "$SUT" "$@" 2>&1)"
  got=$?
  if [[ "$got" == "$want" ]]; then ok "$name"; else bad "$name" "exit $got, want $want: $LAST_OUTPUT"; fi
}

contains() {
  if [[ "$LAST_OUTPUT" == *"$2"* ]]; then ok "$1"; else bad "$1" "no '$2' in: $LAST_OUTPUT"; fi
}

export STUB_RELEASES='[
  {"tag_name":"v0.9.0","draft":false,"prerelease":false},
  {"tag_name":"v0.75.0","draft":false,"prerelease":false},
  {"tag_name":"v0.80.0","draft":false,"prerelease":true},
  {"tag_name":"v0.90.0","draft":true,"prerelease":false},
  {"tag_name":"v1.0","draft":false,"prerelease":false}]'
export STUB_REF="{\"object\":{\"type\":\"tag\",\"sha\":\"$OTHER\"}}"
export STUB_TAG="{\"object\":{\"sha\":\"$NEW\"}}"
run 0 'resolve succeeds' resolve
contains 'resolve picks the highest full-SemVer published release' 'tag=v0.75.0'
contains 'resolve dereferences an annotated tag to its commit' "sha=$NEW"
STUB_REF="{\"object\":{\"type\":\"commit\",\"sha\":\"$NEW\"}}" run 0 'resolve reads a lightweight tag' resolve
contains 'a lightweight tag names its commit' "sha=$NEW"
STUB_RELEASES='[{"tag_name":"v1.0","draft":false,"prerelease":false}]' run 1 'resolve fails with no vX.Y.Z release' resolve

mk_repo "$scratch/cur"
run 0 'current reads the pin' current --root "$scratch/cur"
contains 'current names the sha' "sha=$OLD"
contains 'current names the tag' 'tag=v0.74.0'

export STUB_COMPARE='{"status":"ahead"}'
mk_repo "$scratch/move"
run 0 'apply moves to a newer release' apply "$OLD" v0.74.0 "$NEW" v0.75.0 --root "$scratch/move"
contains 'apply reports a change' 'changed=true'
LAST_OUTPUT="$(cat "$scratch/move/.github/workflows/lane.yml")"
contains 'the run-claude-cli pin moves' "run-claude-cli@${NEW} # v0.75.0"
contains 'the select-model-credential pin moves' "select-model-credential@${NEW} # v0.75.0"
contains 'the checkout ref moves' "ref: ${NEW} # v0.75.0"
contains 'another action pin stays' "checkout@${CHECKOUT} # v7.0.1"
contains 'an @main reusable workflow stays' 'intake-triage.yml@main'
LAST_OUTPUT="$(cat "$scratch/move/docs/conventions/pr-pipeline/pr-run-activity.md")"
contains 'the docs link moves' "blob/${NEW}/README.md"
LAST_OUTPUT="$(git_test_config "$scratch/move" status --porcelain)"
if [[ "$(sort <<<"$LAST_OUTPUT")" == " M .github/workflows/lane.yml"$'\n'" M docs/conventions/pr-pipeline/pr-run-activity.md" ]]; then
  ok 'only the workflow and the doc change; the managed file and fixtures do not'
else
  bad 'only the workflow and the doc change; the managed file and fixtures do not' "$LAST_OUTPUT"
fi

mk_repo "$scratch/same"
run 0 'apply to the current pin is a no-op' apply "$OLD" v0.74.0 "$OLD" v0.74.0 --root "$scratch/same"
contains 'a no-op reports no change' 'changed=false'

mk_repo "$scratch/two" "$OTHER"
run 1 'apply fails on two current SHAs' apply "$OLD" v0.74.0 "$NEW" v0.75.0 --root "$scratch/two"
contains 'the failure names both SHAs' "$OTHER"

mk_repo "$scratch/stale"
run 1 'apply fails when old-sha is not the current pin' apply "$NEW" v0.74.0 "$OTHER" v0.75.0 --root "$scratch/stale"

mk_repo "$scratch/older"
run 1 'apply refuses an older release' apply "$OLD" v0.74.0 "$NEW" v0.73.9 --root "$scratch/older"
run 1 'apply refuses an equal tag at another commit' apply "$OLD" v0.74.0 "$NEW" v0.74.0 --root "$scratch/older"
STUB_COMPARE='{"status":"behind"}' run 1 'apply refuses a release behind the pin' apply "$OLD" v0.74.0 "$NEW" v0.75.0 --root "$scratch/older"
STUB_COMPARE='{"status":"diverged"}' run 1 'apply refuses a release diverged from the pin' apply "$OLD" v0.74.0 "$NEW" v0.75.0 --root "$scratch/older"
contains 'the refusal names the compare status' "diverged"
STUB_COMPARE=fail run 1 'apply fails when the compare fails' apply "$OLD" v0.74.0 "$NEW" v0.75.0 --root "$scratch/older"
LAST_OUTPUT="$(git_test_config "$scratch/older" status --porcelain)"
if [[ -z "$LAST_OUTPUT" ]]; then ok 'a refusal changes nothing'; else bad 'a refusal changes nothing' "$LAST_OUTPUT"; fi

mk_repo "$scratch/dirty"
echo changed >>"$scratch/dirty/README.md"
run 1 'apply fails when a path outside the set changed' apply "$OLD" v0.74.0 "$NEW" v0.75.0 --root "$scratch/dirty"
contains 'the failure names the path' 'README.md'

mk_repo "$scratch/left"
echo "pinned at ${OLD}" >"$scratch/left/tests/notes.md"
git_test_config "$scratch/left" add tests/notes.md
git_test_config "$scratch/left" commit -qm notes
run 1 'apply fails when the old SHA remains outside the set' apply "$OLD" v0.74.0 "$NEW" v0.75.0 --root "$scratch/left"
contains 'the failure names the file' 'still appears after the rewrite in: tests/notes.md'

test_harness::report
