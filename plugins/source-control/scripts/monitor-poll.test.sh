#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/../skills/pull-request/scripts/monitor-poll.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# Children that call mktemp land inside the trapped root.
export TMPDIR="$TEST_TMPDIR"

BIN="$TEST_TMPDIR/bin"
mkdir -p "$BIN"

CHECKOUT="$TEST_TMPDIR/checkout"
git init -q "$CHECKOUT"
git -C "$CHECKOUT" remote add origin https://github.com/owner/repo.git
unset GH_REPO

PLUGIN="$TEST_TMPDIR/plugin"
mkdir -p "$PLUGIN/skills/pull-request/scripts" "$PLUGIN/scripts" "$PLUGIN/lib"
cp -p "$SRC" "$SCRIPT_DIR/../skills/pull-request/scripts/target-repo.sh" \
  "$SCRIPT_DIR/../skills/pull-request/scripts/pr-verify-run.jq" "$PLUGIN/skills/pull-request/scripts/"
export MP_FIXTURES="$SCRIPT_DIR/fixtures/monitor-poll"
cp -p "$SCRIPT_DIR/../lib/github-remote.sh" "$PLUGIN/lib/"
POLL="$PLUGIN/skills/pull-request/scripts/monitor-poll.sh"

cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh. $FX holds poll (the counter), checks.<n> (JSON, or FAIL) per poll,
# merged_at (the poll number at which the PR reports MERGED), and optionally
# statuses.<n> (JSON) and comment_at (the poll from which one issue comment exists).
# Each answer is logged to $FX/calls as "<poll> <status> <path>".
set -u
args="$*"
inm="" prev=""
for a in "$@"; do
  [[ "$prev" == -H && "$a" == "If-None-Match: "* ]] && inm=${a#If-None-Match: }
  prev=$a
done
# reply <json>: what `gh api -i` prints for <json>. The ETag is a hash of the body, so an
# unchanged body answers a request naming it with 304 Not Modified, as GitHub does; gh then
# prints the headers only, says "gh: HTTP 304" on stderr and exits 1.
reply() {
  local tag
  tag="\"$(printf '%s' "$1" | cksum | cut -d' ' -f1)\""
  if [[ "$inm" == "$tag" ]]; then
    echo "$(cat "$FX/poll") 304 ${args##* }" >>"$FX/calls"
    printf 'HTTP/2.0 304 Not Modified\r\nEtag: %s\r\n\r\n' "$tag"
    echo "gh: HTTP 304" >&2
    exit 1
  fi
  echo "$(cat "$FX/poll") 200 ${args##* }" >>"$FX/calls"
  printf 'HTTP/2.0 200 OK\r\nEtag: %s\r\n' "$tag"
  [[ -n "${2:-}" ]] && printf 'Link: <%s>; rel="next", <%s>; rel="last"\r\n' "$2" "$2"
  printf '\r\n%s\n' "$1"
  exit 0
}
case "$args" in
  "repo set-default --view"*) echo "No default remote repository has been set." >&2 ;;
  *"/pulls/7")
    n=$(($(cat "$FX/poll" 2>/dev/null || echo 0) + 1))
    echo "$n" >"$FX/poll"
    if [ "$n" -ge "$(cat "$FX/merged_at")" ]; then state=closed merged=true; else state=open merged=false; fi
    # head.<n>: the head SHA from that poll on (the newest such file at or below n); sha1 without one.
    sha=sha1
    for f in "$FX"/head.*; do [ -e "$f" ] && [ "${f##*.}" -le "$n" ] && sha=$(cat "$f"); done
    reply "{\"state\":\"$state\",\"merged\":$merged,\"head\":{\"sha\":\"$sha\",\"ref\":\"feature\"},\"base\":{\"ref\":\"main\",\"repo\":{\"default_branch\":\"main\",\"full_name\":\"owner/repo\"}}}" ;;
  *"/contents/.github/workflows/pr-verify.yml"*)
    # no-verify: the base branch has no pr-verify workflow.
    if [ -e "$FX/no-verify" ]; then
      echo "$(cat "$FX/poll") 404 ${args##* }" >>"$FX/calls"
      printf 'HTTP/2.0 404 Not Found\r\n\r\n{"message":"Not Found"}\n'
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    reply '{"path":".github/workflows/pr-verify.yml"}' ;;
  *"/actions/artifacts?name="*)
    # art/<name>: "<from poll> [<run id>]", the artifact by that exact name from that poll on,
    # shaped from the captured listing fixtures/monitor-poll/artifacts-pass-notes.json.
    name=${args##*name=} name=${name%%&*}
    live=0 run=5
    if [ -e "$FX/art/$name" ]; then
      read -r from run <"$FX/art/$name"
      run=${run:-5}
      [ "$(cat "$FX/poll")" -ge "$from" ] && live=1
    fi
    reply "$(jq -c --arg n "$name" --argjson r "$run" --argjson live "$live" \
      'if $live == 1 then .artifacts[0] |= (.name = $n | .workflow_run.id = $r) else .total_count = 0 | .artifacts = [] end' \
      "$MP_FIXTURES/artifacts-pass-notes.json")" ;;
  *"/actions/runs/"[0-9]*)
    # The captured pr-verify run fixtures/monitor-poll/run-pr-verify.json, moved to this repository;
    # run.<id>, when present, is a jq edit that forges one field.
    id=${args##*/}
    reply "$(jq -c --argjson id "$id" "(.id = \$id | .repository.full_name = \"owner/repo\" | .head_repository.full_name = \"owner/repo\") | $(cat "$FX/run.$id" 2>/dev/null || echo .)" \
      "$MP_FIXTURES/run-pr-verify.json")" ;;
  *"/actions/runs"*)
    n=$(cat "$FX/poll")
    [ "$(cat "$FX/fault.$n" 2>/dev/null)" = actions ] && { echo "boom: transient" >&2; exit 1; }
    reply '{"workflow_runs":[]}' ;;
  *"/check-runs"*)
    n=$(cat "$FX/poll")
    [ "$(cat "$FX/fault.$n" 2>/dev/null)" = ratelimit ] && { echo "API rate limit exceeded" >&2; exit 1; }
    if [ "$(cat "$FX/checks.$n")" = FAIL ]; then echo "boom: transient" >&2; exit 1; fi
    # checks.<n>.p2, when present, is a second page the first page's Link header names.
    case "$args" in
      *"&page=2") reply "$(cat "$FX/checks.$n.p2")" ;;
      *) [ -e "$FX/checks.$n.p2" ] && reply "$(cat "$FX/checks.$n")" "https://api.github.com/repos/owner/repo/commits/sha1/check-runs?per_page=100&page=2"
         reply "$(cat "$FX/checks.$n")" ;;
    esac ;;
  *"/status"*)
    n=$(cat "$FX/poll")
    [ "$(cat "$FX/fault.$n" 2>/dev/null)" = status ] && { echo "boom: transient" >&2; exit 1; }
    reply "$(cat "$FX/statuses.$n" 2>/dev/null || echo '{"statuses":[]}')" ;;
  *"/issues/7/comments"*)
    n=$(cat "$FX/poll")
    [ "$(cat "$FX/fault.$n" 2>/dev/null)" = comments-ratelimit ] && { echo "API rate limit exceeded" >&2; exit 1; }
    # A comment is stamped with the time it is first read, the way a comment posted between
    # two polls carries a time no later than the read that finds it.
    # comment_at: from that poll, page 1 holds "hello". comments.p1: page 1's older comments.
    # paged: page 1 names a page 2. comment2_at: from that poll, page 2 holds "page two".
    stamp() {
      [ -e "$FX/$1.json" ] ||
        printf '{"user":{"login":"bot"},"updated_at":"%s","body":"%s"}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" >"$FX/$1.json"
      cat "$FX/$1.json"
    }
    case "$args" in
      *"&page=2")
        [ "$(cat "$FX/fault.$n" 2>/dev/null)" = comments-p2 ] && { echo "boom: transient" >&2; exit 1; }
        if [ -e "$FX/comment2_at" ] && [ "$n" -ge "$(cat "$FX/comment2_at")" ]; then
          reply "[$(stamp comment2 "page two")]"
        fi
        reply '[]' ;;
      *)
        items=$(cat "$FX/comments.p1" 2>/dev/null)
        if [ -e "$FX/comment_at" ] && [ "$n" -ge "$(cat "$FX/comment_at")" ]; then
          items="${items:+$items,}$(stamp comment hello)"
        fi
        link=""
        [ -e "$FX/paged" ] && link="https://api.github.com/repos/owner/repo/issues/7/comments?per_page=100&page=2"
        reply "[$items]" "$link" ;;
    esac ;;
  "api "*) reply '[]' ;;
  *) ;;
esac
exit 0
STUB
cat >"$PLUGIN/scripts/source-control-review-threads" <<'STUB'
touch "$FX/threads-read"
echo "THREADS_OK unresolved=0"
STUB
chmod +x "$BIN/gh"

runs_json() {
  local out="" n
  for n in "$@"; do
    out+="${out:+,}{\"name\":\"$n\",\"check_suite\":{\"id\":1},\"started_at\":\"t\",\"status\":\"completed\",\"conclusion\":\"success\"}"
  done
  printf '{"check_runs":[%s]}' "$out"
}

POLL_TMP="$TEST_TMPDIR/poll-tmp"
mkdir -p "$POLL_TMP"
run_poll() {
  (cd "$TEST_TMPDIR" && FX="$1" TMPDIR="$POLL_TMP" PATH="$BIN:$PATH" \
    timeout 60 bash "$POLL" --pr 7 --interval 0 --checkout "$CHECKOUT" "${@:2}" 2>/dev/null)
}

FX1="$TEST_TMPDIR/fx1"
mkdir -p "$FX1"
echo FAIL >"$FX1/checks.1"
runs_json a b >"$FX1/checks.2"
runs_json a b c >"$FX1/checks.3"
echo 4 >"$FX1/merged_at"
out1="$(run_poll "$FX1")"
assert_not_contains "failed first read: check a not emitted" "$out1" "a: pass"
assert_not_contains "failed first read: check b not emitted" "$out1" "b: pass"
assert_eq "failed first read: only c is emitted, once" "1" "$(grep -c '^c: pass$' <<<"$out1")"
assert_contains "failed first read: watch completes" "$out1" "PR #7 MERGED — watch complete"

FX2="$TEST_TMPDIR/fx2"
mkdir -p "$FX2"
runs_json a >"$FX2/checks.1"
echo FAIL >"$FX2/checks.2"
runs_json a b >"$FX2/checks.3"
echo 4 >"$FX2/merged_at"
out2="$(run_poll "$FX2")"
assert_not_contains "failed middle read: baseline check a not emitted" "$out2" "a: pass"
assert_eq "failed middle read: b is emitted exactly once" "1" "$(grep -c '^b: pass$' <<<"$out2")"

FX3="$TEST_TMPDIR/fx3"
mkdir -p "$FX3"
runs_json a >"$FX3/checks.1"
runs_json a b >"$FX3/checks.2"
echo 3 >"$FX3/merged_at"
out3="$(run_poll "$FX3")"
assert_not_contains "clean polls: baseline check a not emitted" "$out3" "a: pass"
assert_eq "clean polls: b is emitted once" "1" "$(grep -c '^b: pass$' <<<"$out3")"

FX8="$TEST_TMPDIR/fx8"
mkdir -p "$FX8"
for n in 1 2 3 4; do runs_json a >"$FX8/checks.$n"; done
for n in 2 3 4; do echo '{"statuses":[{"context":"ci/x","state":"success"}]}' >"$FX8/statuses.$n"; done
echo 2 >"$FX8/comment_at"
echo 5 >"$FX8/merged_at"
out8="$(run_poll "$FX8")"
assert_eq "304 replay: a status finishing beside unchanged check runs is emitted once" "1" "$(grep -c '^ci/x: pass$' <<<"$out8")"
assert_not_contains "304 replay: the replayed baseline check a is not emitted" "$out8" "a: pass"
assert_eq "304 replay: the new comment is emitted once, not again from the replayed body" "1" \
  "$(grep -c '^COMMENT bot: hello$' <<<"$out8")"
assert_eq "304 replay: no read in the unchanged poll 3 got a full answer" "" "$(awk '$1 == 3 && $2 != 304' "$FX8/calls")"
assert_contains "304 replay: poll 3 reads were answered 304" "$(awk '$1 == 3 { print $2 }' "$FX8/calls")" "304"
assert_contains "304 replay: the watch completes" "$out8" "PR #7 MERGED — watch complete"

FX9="$TEST_TMPDIR/fx9"
mkdir -p "$FX9"
for n in 1 2 3; do runs_json a >"$FX9/checks.$n"; done
runs_json b | sed 's/"completed","conclusion":"success"/"in_progress","conclusion":null/' >"$FX9/checks.1.p2"
runs_json b >"$FX9/checks.2.p2"
runs_json b >"$FX9/checks.3.p2"
echo 4 >"$FX9/merged_at"
out9="$(run_poll "$FX9")"
assert_eq "paged checks: a check finishing on the second page is emitted once" "1" "$(grep -c '^b: pass$' <<<"$out9")"
assert_not_contains "paged checks: the first page's unchanged check is not emitted" "$out9" "a: pass"

FX10="$TEST_TMPDIR/fx10"
mkdir -p "$FX10"
for n in 1 2 3; do runs_json a >"$FX10/checks.$n"; done
seq 100 | awk '{ printf "%s{\"user\":{\"login\":\"old\"},\"updated_at\":\"2000-01-01T00:00:00Z\",\"body\":\"c%s\"}", (NR > 1 ? "," : ""), $1 }' >"$FX10/comments.p1"
echo 2 >"$FX10/comment2_at"
echo 4 >"$FX10/merged_at"
out10="$(run_poll "$FX10")"
assert_eq "list grows from 100 to 101 comments: the 101st, on a new page 2, is emitted once" "1" \
  "$(grep -c '^COMMENT bot: page two$' <<<"$out10")"
assert_not_contains "list grows from 100 to 101 comments: the older comments are not emitted" "$out10" "COMMENT old:"

FX11="$TEST_TMPDIR/fx11"
mkdir -p "$FX11"
for n in 1 2 3 4; do runs_json a >"$FX11/checks.$n"; done
touch "$FX11/paged"
echo 2 >"$FX11/comment_at"
echo comments-p2 >"$FX11/fault.2"
echo 5 >"$FX11/merged_at"
out11="$(run_poll "$FX11")"
assert_eq "page 2 fails in the poll page 1 changes: the new comment is emitted on a later poll, once" "1" \
  "$(grep -c '^COMMENT bot: hello$' <<<"$out11")"

FX7="$TEST_TMPDIR/fx7"
mkdir -p "$FX7"
runs_json a >"$FX7/checks.1"
runs_json a b >"$FX7/checks.2"
echo 9 >"$FX7/merged_at"
out7="$(run_poll "$FX7" --once)"
assert_exit "--once: exits 0 after the poll that printed" 0 "$?"
assert_eq "--once: b is emitted once" "1" "$(grep -c '^b: pass$' <<<"$out7")"
assert_not_contains "--once: the watch does not run on to the merge" "$out7" "watch complete"
assert_eq "--once: it stopped after poll 2" "2" "$(cat "$FX7/poll")"

for fault in actions status; do
  FXF="$TEST_TMPDIR/fx-$fault"
  mkdir -p "$FXF"
  runs_json a b >"$FXF/checks.1"
  echo "$fault" >"$FXF/fault.1"
  runs_json a b >"$FXF/checks.2"
  runs_json a b c >"$FXF/checks.3"
  echo 4 >"$FXF/merged_at"
  outf="$(run_poll "$FXF")"
  assert_not_contains "faulted $fault read: check a not emitted" "$outf" "a: pass"
  assert_eq "faulted $fault read: only c is emitted, once" "1" "$(grep -c '^c: pass$' <<<"$outf")"
  assert_contains "faulted $fault read: watch completes" "$outf" "PR #7 MERGED — watch complete"
done

FX4="$TEST_TMPDIR/fx4"
mkdir -p "$FX4"
runs_json a >"$FX4/checks.1"
echo ratelimit >"$FX4/fault.1"
echo 9 >"$FX4/merged_at"
out4="$(run_poll "$FX4")"
rc4=$?
assert_eq "rate limit: exit status" "2" "$rc4"
assert_contains "rate limit: RATE-LIMITED line" "$out4" "RATE-LIMITED"

FX6="$TEST_TMPDIR/fx6"
mkdir -p "$FX6"
runs_json a >"$FX6/checks.1"
echo comments-ratelimit >"$FX6/fault.1"
echo 9 >"$FX6/merged_at"
out6="$(run_poll "$FX6")"
rc6=$?
assert_eq "comment-read rate limit: exit status" "2" "$rc6"
assert_contains "comment-read rate limit: names the error" "$out6" "RATE-LIMITED — watch stopped: API rate limit exceeded"

H1=$(printf 'a%.0s' $(seq 40))
H2=$(printf 'b%.0s' $(seq 40))
DIGEST=$(printf '%s' feature | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-16)
verdict_fx() {
  local fx="$TEST_TMPDIR/$1" n
  mkdir -p "$fx/art"
  for n in 1 2 3 4 5; do runs_json a >"$fx/checks.$n"; done
  echo "$H1" >"$fx/head.1"
  echo 5 >"$fx/merged_at"
  printf '%s' "$fx"
}

FXV=$(verdict_fx fxv-pass)
echo 2 >"$FXV/art/pr-verify-7-$H1-pass"
outv="$(run_poll "$FXV")"
assert_eq "verdict at the head: the pass is printed once" "1" "$(grep -c "^PR-VERIFY pass $H1\$" <<<"$outv")"
assert_contains "verdict at the head: the watch completes" "$outv" "PR #7 MERGED — watch complete"

FXV=$(verdict_fx fxv-digest)
echo 2 >"$FXV/art/pr-verify-7-$H1-pass-notes-$DIGEST"
outv="$(run_poll "$FXV")"
assert_eq "verdict named with the head-ref digest: the pass-notes is printed once" "1" \
  "$(grep -c "^PR-VERIFY pass-notes $H1\$" <<<"$outv")"

FXV=$(verdict_fx fxv-fail)
echo 2 >"$FXV/art/pr-verify-index-pr-7"
echo 2 >"$FXV/art/pr-verify-index-sha-$H1"
outv="$(run_poll "$FXV")"
assert_eq "FAIL at the head: printed once, from its index artifacts" "1" "$(grep -c "^PR-VERIFY fail $H1 — " <<<"$outv")"
assert_contains "FAIL at the head: the line points at the label and the fail-note threads" "$outv" \
  "label pr-verify-failed; its notes are the review threads that open with <!-- pr-verify:fail-note -->"

FXV=$(verdict_fx fxv-fail-other-run)
echo "2 5" >"$FXV/art/pr-verify-index-pr-7"
echo "2 6" >"$FXV/art/pr-verify-index-sha-$H1"
outv="$(run_poll "$FXV")"
assert_not_contains "index artifacts from two different runs: no FAIL is printed" "$outv" "PR-VERIFY"

FXV=$(verdict_fx fxv-older-head)
echo "$H2" >"$FXV/head.2"
echo 2 >"$FXV/art/pr-verify-7-$H1-pass"
echo 2 >"$FXV/art/pr-verify-index-pr-7"
echo 2 >"$FXV/art/pr-verify-index-sha-$H1"
outv="$(run_poll "$FXV")"
assert_not_contains "verdicts at an older head: nothing is printed" "$outv" "PR-VERIFY"
assert_contains "verdicts at an older head: the watch completes" "$outv" "PR #7 MERGED — watch complete"

FXV=$(verdict_fx fxv-none)
outv="$(run_poll "$FXV")"
assert_not_contains "no verdict artifact: nothing is printed" "$outv" "PR-VERIFY"
assert_contains "no verdict artifact: verdict reads ran by exact name" "$(cat "$FXV/calls")" \
  "actions/artifacts?name=pr-verify-7-$H1-pass&per_page=100"

FXV=$(verdict_fx fxv-first-poll)
echo 1 >"$FXV/art/pr-verify-7-$H1-pass"
outv="$(run_poll "$FXV")"
assert_not_contains "a verdict already there at the first poll is recorded, not printed" "$outv" "PR-VERIFY"

FXV=$(verdict_fx fxv-off)
touch "$FXV/no-verify"
echo 2 >"$FXV/art/pr-verify-7-$H1-pass"
outv="$(run_poll "$FXV")"
assert_not_contains "base branch without the pr-verify workflow: no verdict is printed" "$outv" "PR-VERIFY"
assert_eq "base branch without the pr-verify workflow: its file is read once" "1" \
  "$(grep -c 'pr-verify.yml' "$FXV/calls")"
assert_not_contains "base branch without the pr-verify workflow: no artifact is read" "$(cat "$FXV/calls")" "actions/artifacts"

FXV=$(verdict_fx fxv-pending)
for n in 1 2; do runs_json a | sed 's/"completed","conclusion":"success"/"in_progress","conclusion":null/' >"$FXV/checks.$n"; done
echo 4 >"$FXV/art/pr-verify-7-$H1-pass"
outv="$(run_poll "$FXV")"
assert_contains "first poll: the record-only verdict read runs though a check run is pending" \
  "$(awk '$1 == 1' "$FXV/calls")" "actions/artifacts"
assert_eq "a check run still pending after the first poll: no verdict read" "" "$(awk '$1 == 2 && /actions\/artifacts/' "$FXV/calls")"
assert_contains "every check run finished: the verdict reads start" "$(awk '$1 == 3' "$FXV/calls")" "actions/artifacts"
assert_eq "every check run finished: a verdict landing later is printed once" "1" "$(grep -c "^PR-VERIFY pass $H1\$" <<<"$outv")"

FXV=$(verdict_fx fxv-pending-at-arming)
echo 6 >"$FXV/merged_at"
for n in 1 2 3; do runs_json a | sed 's/"completed","conclusion":"success"/"in_progress","conclusion":null/' >"$FXV/checks.$n"; done
echo 2 >"$FXV/art/pr-verify-7-$H1-pass"
outv="$(run_poll "$FXV")"
assert_eq "no baseline, a check run pending through poll 3, a verdict at poll 2: printed exactly once" "1" \
  "$(grep -c "^PR-VERIFY pass $H1\$" <<<"$outv")"

FXV=$(verdict_fx fxv-pass-then-fail)
echo 6 >"$FXV/merged_at"
echo 2 >"$FXV/art/pr-verify-7-$H1-pass"
echo 4 >"$FXV/art/pr-verify-index-pr-7"
echo 4 >"$FXV/art/pr-verify-index-sha-$H1"
outv="$(run_poll "$FXV")"
assert_contains "a pass recorded for the head: its reads go on" "$(awk '$1 == 3' "$FXV/calls")" "actions/artifacts"
assert_eq "a pass then a fail at one head: the pass is printed once" "1" "$(grep -c "^PR-VERIFY pass $H1\$" <<<"$outv")"
assert_eq "a pass then a fail at one head: the fail is printed once" "1" "$(grep -c "^PR-VERIFY fail $H1 — " <<<"$outv")"

FXV=$(verdict_fx fxv-new-head)
echo 2 >"$FXV/art/pr-verify-7-$H1-pass"
echo "$H2" >"$FXV/head.4"
outv="$(run_poll "$FXV")"
assert_contains "a new head: the verdict reads name it" "$(awk '$1 == 4' "$FXV/calls")" "pr-verify-7-$H2-pass"

for forge in '.status = "in_progress"' '.conclusion = "failure"' '.path = ".github/workflows/forged.yml"' \
  '.event = "pull_request"' '.repository.full_name = "fork/repo"' '.head_repository.full_name = "fork/repo"' \
  '.head_branch = "feature"'; do
  FXV=$(verdict_fx "fxv-forged-$(cksum <<<"$forge" | cut -d' ' -f1)")
  echo "2 9" >"$FXV/art/pr-verify-7-$H1-pass"
  echo "2 9" >"$FXV/art/pr-verify-index-pr-7"
  echo "2 9" >"$FXV/art/pr-verify-index-sha-$H1"
  echo "$forge" >"$FXV/run.9"
  outv="$(run_poll "$FXV")"
  assert_not_contains "artifacts from a run with $forge: nothing is printed" "$outv" "PR-VERIFY"
  assert_contains "artifacts from a run with $forge: the run was read" "$(cat "$FXV/calls")" "actions/runs/9"
done

FXV=$(verdict_fx fxv-fail-then-pass)
echo 6 >"$FXV/merged_at"
echo 2 >"$FXV/art/pr-verify-index-pr-7"
echo 2 >"$FXV/art/pr-verify-index-sha-$H1"
echo 4 >"$FXV/art/pr-verify-7-$H1-pass"
outv="$(run_poll "$FXV")"
assert_contains "a fail recorded for the head: its reads go on" "$(awk '$1 == 3' "$FXV/calls")" "actions/artifacts"
assert_eq "a fail then a pass at one head: the fail is printed once" "1" "$(grep -c "^PR-VERIFY fail $H1 — " <<<"$outv")"
assert_eq "a fail then a pass at one head: the pass is printed once" "1" "$(grep -c "^PR-VERIFY pass $H1\$" <<<"$outv")"

FXV=$(verdict_fx fxv-rearm)
echo 1 >"$FXV/art/pr-verify-7-$H1-pass"
run_poll "$FXV" --snapshot "$FXV/snap" >/dev/null
assert_contains "snapshot: holds the verdict at the head" "$(cat "$FXV/snap")" "PR-VERIFY pass $H1"
echo "$H2" >"$FXV/head.3"
echo 3 >"$FXV/art/pr-verify-index-pr-7"
echo 3 >"$FXV/art/pr-verify-index-sha-$H2"
outv="$(run_poll "$FXV" --baseline "$FXV/snap")"
assert_not_contains "re-armed from the snapshot: the verdict it holds is not printed again" "$outv" "PR-VERIFY pass"
assert_eq "re-armed from the snapshot: a verdict at a new head is printed once" "1" "$(grep -c "^PR-VERIFY fail $H2 — " <<<"$outv")"
assert_not_contains "re-armed from the snapshot: the verdict line is not taken for a check" "$outv" "BASELINE-UNREADABLE"

FXV=$(verdict_fx fxv-once)
echo 9 >"$FXV/merged_at"
echo 2 >"$FXV/art/pr-verify-7-$H1-pass"
outv="$(run_poll "$FXV" --once)"
assert_eq "--once: a new verdict ends the poll" "2" "$(cat "$FXV/poll")"

FXV=$(verdict_fx fxv-verdict-mode)
echo 1 >"$FXV/art/pr-verify-7-$H1-pass"
assert_eq "--verdict: prints the verdict at the head" "PR-VERIFY pass $H1" "$(run_poll "$FXV" --verdict)"
FXV=$(verdict_fx fxv-verdict-none)
assert_eq "--verdict: names no verdict at the head" "PR-VERIFY none $H1" "$(run_poll "$FXV" --verdict)"
FXV=$(verdict_fx fxv-verdict-off)
touch "$FXV/no-verify"
assert_contains "--verdict: says the base branch runs no pr-verify" "$(run_poll "$FXV" --verdict)" "PR-VERIFY off"

# --- the script runs no rm and makes no temp file: an auto-mode session's
# safety check denied a Monitor command that ran rm:
# https://github.com/melodic-software/claude-code-plugins/issues/16201
assert_eq "poll script runs no rm" "" "$(grep -nE '(^|[^[:alnum:]_-])rm([^[:alnum:]_-]|$)' "$SRC")"
assert_eq "poll script makes no temp file" "" "$(grep -n 'mktemp' "$SRC")"

FX5="$TEST_TMPDIR/fx5"
mkdir -p "$FX5"
runs_json a >"$FX5/checks.1"
echo 9 >"$FX5/merged_at"
FX="$FX5" TMPDIR="$POLL_TMP" PATH="$BIN:$PATH" bash "$POLL" --pr 7 --interval 30 --checkout "$CHECKOUT" >"$TEST_TMPDIR/out5" 2>&1 &
pid5=$!
for _ in $(seq 100); do
  [[ -e "$FX5/threads-read" ]] && break
  sleep 0.1
done
sleep 0.5
assert_eq "running watch: poll 1 reached its threads read" "yes" "$([[ -e "$FX5/threads-read" ]] && echo yes || echo no)"
assert_eq "running watch: poll 1 ran clean" "" "$(grep -v '^target repository: ' "$TEST_TMPDIR/out5")"
kill -TERM "$pid5" 2>/dev/null
pkill -TERM -P "$pid5" 2>/dev/null
for _ in $(seq 50); do
  kill -0 "$pid5" 2>/dev/null || break
  sleep 0.1
done
assert_eq "stopped watch: it exits within 5s of TERM" "gone" "$(kill -0 "$pid5" 2>/dev/null && echo running || echo gone)"
kill -0 "$pid5" 2>/dev/null && kill -KILL "$pid5" 2>/dev/null
wait "$pid5" 2>/dev/null

# --- the documented Monitor command. Both docs hand the script to bash by
# path with no poll body inline, so the shell the Monitor tool runs (zsh on
# some hosts) never parses the poll itself; and each command as written, its
# placeholders filled in, runs a watch to completion against the stub. The
# quotes are dropped before the split: the fixture paths hold no whitespace.
# https://github.com/melodic-software/claude-code-plugins/issues/16353
SKILL_DOC="$SCRIPT_DIR/../skills/pull-request/reference/monitor.md"
PROVIDER_DOC="$SCRIPT_DIR/../reference/providers/github/pull-request/monitor.md"
skill_cmd=$(sed -n 's/^[[:space:]]*command: //p' "$SKILL_DOC")
provider_cmd=$(awk '/^## Poll checks over REST$/ { s = 1; next } s && /^## / { exit } s && /^```bash$/ { f = 1; next } f && /^```$/ { exit } f { print }' "$PROVIDER_DOC")
doc_prefix='bash "<skill-dir>/scripts/monitor-poll.sh" '
for doc in skill provider; do
  if [[ "$doc" == skill ]]; then
    cmd=$skill_cmd docf=$SKILL_DOC
  else
    cmd=$provider_cmd docf=$PROVIDER_DOC
  fi
  assert_eq "$doc doc: one documented poll command" "1" "$(grep -c . <<<"$cmd")"
  assert_eq "$doc doc: the command runs the script with bash, by path" "$doc_prefix" "${cmd:0:${#doc_prefix}}"
  assert_eq "$doc doc: no inline poll body" "" "$(grep -nE 'read_into\(\)|while true; do' "$docf")"
  [[ "${cmd:0:${#doc_prefix}}" == "$doc_prefix" ]] || continue
  cmd=${cmd//<skill-dir>/$PLUGIN/skills/pull-request}
  cmd=${cmd//<checkout>/$CHECKOUT}
  cmd=${cmd//<N>/7}
  read -ra argv <<<"${cmd//\"/}"
  FXD="$TEST_TMPDIR/fx-doc-$doc"
  mkdir -p "$FXD"
  runs_json a >"$FXD/checks.1"
  runs_json a b >"$FXD/checks.2"
  echo 3 >"$FXD/merged_at"
  outd="$(cd "$TEST_TMPDIR" && FX="$FXD" TMPDIR="$POLL_TMP" PATH="$BIN:$PATH" \
    timeout 60 "${argv[@]}" --interval 0 2>/dev/null)"
  assert_eq "$doc doc: the documented watch emits b once" "1" "$(grep -c '^b: pass$' <<<"$outd")"
  assert_contains "$doc doc: the documented watch completes" "$outd" "PR #7 MERGED — watch complete"
done

assert_eq "poll script leaves no temp file behind" "" "$(find "$POLL_TMP" -mindepth 1)"

[[ $FAILED -eq 0 ]] || exit 1
