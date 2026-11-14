#!/usr/bin/env bash
# Tests for media.py, black-box with a stubbed `gh` on PATH that keeps one pull
# request's body, head, labels and comments in files.
#
# Expected text comes from the reviewer-section contract in ../reference/media.md
# (markers, heading, first line, stale line, placement before `## Summary`) and
# from `gh pr edit --attach` as gh documents it: a body reference to an attached
# image has its path swapped for the asset URL, a video reference alone in a
# paragraph becomes the bare URL, and a failed upload leaves the body unwritten.
# test-scope: plugins/source-control/skills/pull-request/scripts/media.py plugins/source-control/tools/reviewer-media/lib/* plugins/source-control/skills/pull-request/scripts/fixtures/body-with-reviewer-media.md plugins/source-control/tools/reviewer-media/vendor/gitleaks/*

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/media.py"
FIXTURE="$SCRIPT_DIR/fixtures/body-with-reviewer-media.md"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"
command -v python3 >/dev/null 2>&1 || skip_suite "python3 not installed"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
S="$TEST_TMPDIR/state"
STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"

HEAD1=1111111111111111111111111111111111111111
HEAD2=2222222222222222222222222222222222222222
START='<!-- reviewer-media:start -->'
END='<!-- reviewer-media:end -->'
REQUESTED='reviewer-media: requested'
POSTED='reviewer-media: posted'
FAILED_LABEL='reviewer-media: failed'

cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
S="$MEDIA_GH_STATE"
printf '%s\n' "$*" >>"$S/calls"
case "$1 $2" in
  "pr view")
    n=$(($(cat "$S/views") + 1))
    echo "$n" >"$S/views"
    [[ ! -f "$S/view-hook-$n" ]] || bash "$S/view-hook-$n"
    jq -n --rawfile body "$S/body" --arg head "$(cat "$S/head")" --rawfile labels "$S/labels" \
      '{number: 7, url: "https://github.com/acme/app/pull/7", headRefOid: $head, body: $body,
        labels: ($labels | split("\n") | map(select(. != "") | {name: .}))}'
    ;;
  "pr edit")
    if [[ " $* " == *" --help "* ]]; then
      cat "$S/help"
      exit 0
    fi
    shift 2
    body="" attach=() add=() remove=()
    while (($#)); do
      case "$1" in
        --body-file) body="$2"; shift 2 ;;
        --attach) attach+=("$2"); shift 2 ;;
        --add-label) add+=("$2"); shift 2 ;;
        --remove-label) remove+=("$2"); shift 2 ;;
        -R) shift 2 ;;
        *) shift ;;
      esac
    done
    if ((${#attach[@]})) && [[ -f "$S/attach-fail" ]]; then
      echo "gh-stub: upload refused" >&2
      exit 1
    fi
    if [[ -n "$body" ]]; then
      cp "$body" "$S/body.new"
      for a in ${attach[@]+"${attach[@]}"}; do
        [[ -f "$a" && "$(dirname "$a")" == "$(dirname "$body")" ]] || {
          echo "gh-stub: $a is not a file beside the body file" >&2
          exit 1
        }
        name=$(basename "$a")
        cksum <"$a" >>"$S/attached"
        case "$name" in
          *.mp4) sed -E "s|^!\[[^]]*\]\(\./${name}\)\$|https://github.com/user-attachments/assets/${name}|" "$S/body.new" >"$S/body.tmp" ;;
          *) sed -E "s|\]\(\./${name}\)|](https://github.com/user-attachments/assets/${name})|" "$S/body.new" >"$S/body.tmp" ;;
        esac
        mv "$S/body.tmp" "$S/body.new"
      done
      mv "$S/body.new" "$S/body"
    fi
    for l in ${add[@]+"${add[@]}"}; do
      grep -qxF "$l" "$S/known-labels" || {
        echo "gh-stub: '$l' not found" >&2
        exit 1
      }
      grep -qxF "$l" "$S/labels" || echo "$l" >>"$S/labels"
    done
    for l in ${remove[@]+"${remove[@]}"}; do
      grep -vxF "$l" "$S/labels" >"$S/labels.new"
      mv "$S/labels.new" "$S/labels"
    done
    ;;
  "pr comment")
    while (($#)); do
      [[ "$1" != --body-file ]] || cp "$2" "$S/comments/$(find "$S/comments" -type f | wc -l)"
      shift
    done
    ;;
  "api --paginate")
    for f in "$S"/comments/*; do
      [[ ! -f "$f" ]] || cat "$f"
    done
    ;;
  *)
    echo "gh-stub: unrouted $*" >&2
    exit 1
    ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

# reset <body-file> <head>: a fresh pull request #7 holding that body.
reset() {
  rm -rf "$S"
  mkdir -p "$S/comments"
  cp "$1" "$S/body"
  echo "$2" >"$S/head"
  printf '%s\n' "$REQUESTED" bug >"$S/labels"
  printf '%s\n' "$REQUESTED" "$POSTED" "$FAILED_LABEL" bug >"$S/known-labels"
  echo 0 >"$S/views"
  printf 'FLAGS\n      --attach file   Attach an image or video file\n' >"$S/help"
  : >"$S/calls"
  : >"$S/attached"
}

OUT=""
RC=0
media() {
  OUT=$(MEDIA_GH_STATE="$S" PATH="$STUB_DIR:$PATH" python3 -B "$SCRIPT" "$@" 2>&1)
  RC=$?
}

# media_dir <dir> <head> [chapter-title]: a producer output directory with a
# video, one contact sheet, an unlisted file and manifest.json.
media_dir() {
  mkdir -p "$1"
  printf 'video-bytes-%s' "$2" >"$1/video.mp4"
  printf 'sheet-bytes-%s' "$2" >"$1/sheet-1.png"
  printf 'private notes' >"$1/notes.png"
  jq -n --arg head "$2" --arg title "${3:-The fix}" '{
    head_sha: $head, storyboard_sha256: "0",
    video: {path: "video.mp4", bytes: 1, duration_s: 90, captions: "burned"},
    chapters: [{title: "Intro", start_s: 0}, {title: $title, start_s: 65}],
    contact_sheet: [{path: "sheet-1.png", bytes: 1}], screenshots: [],
    voice: {backend: "edge-tts", voice: "en-US-AndrewNeural"},
    scan: {status: "pass", floor_rules: 1}, encode: {profile: "reviewer-stills", steps: []}}' >"$1/manifest.json"
}

sums() { for f in "$@"; do cksum <"$f"; done; }

# block_of <body-file>: the lines from the start marker through the end marker.
block_of() { sed -n "/^${START}\$/,/^${END}\$/p" "$1"; }

# outside_of <body-file>: every line outside the marked block.
outside_of() { sed "/^${START}\$/,/^${END}\$/d" "$1"; }

body_edits() { grep -c -- '--body-file' "$S/calls" || true; }

PLAIN="$TEST_TMPDIR/plain.md"
printf '%s\n' 'Closes #12' '' '## Summary' '' 'Adds a retry.' '' '## Fix' '' 'Retries once.' \
  '' '## Verification' '' '- ran it' '' '## Related' '' '- None.' >"$PLAIN"

# --- claim -------------------------------------------------------------------
reset "$PLAIN" "$HEAD1"
media claim 7 --run-id run-1
assert_exit "claim on a body with no section exits 0" 0 "$RC"
printf '%s\n' 'Closes #12' '' "$START" "<!-- reviewer-media:claimed $HEAD1 run-1 -->" "$END" '' \
  '## Summary' '' 'Adds a retry.' '' '## Fix' '' 'Retries once.' \
  '' '## Verification' '' '- ran it' '' '## Related' '' '- None.' >"$TEST_TMPDIR/expected"
cmp -s "$S/body" "$TEST_TMPDIR/expected"
assert_exit "the claim block sits after the linkage line and before ## Summary, every other byte kept" 0 "$?"
assert_not_contains "claim removes the request label" "$(cat "$S/labels")" "$REQUESTED"
assert_contains "claim leaves other labels" "$(cat "$S/labels")" "bug"
cp "$S/body" "$TEST_TMPDIR/claimed.md"

printf 'Closes #12\r\n\r\n## Summary\r\n\r\nText' >"$TEST_TMPDIR/crlf.md"
reset "$TEST_TMPDIR/crlf.md" "$HEAD1"
media claim 7 --run-id run-1
printf 'Closes #12\r\n\r\n%s\r\n%s\r\n%s\r\n\r\n## Summary\r\n\r\nText' \
  "$START" "<!-- reviewer-media:claimed $HEAD1 run-1 -->" "$END" >"$TEST_TMPDIR/expected"
cmp -s "$S/body" "$TEST_TMPDIR/expected"
assert_exit "a CRLF body with no final newline keeps its bytes and line endings" 0 "$?"

sed "s/run-1/run-other/" "$TEST_TMPDIR/claimed.md" >"$TEST_TMPDIR/other-claim.md"
reset "$TEST_TMPDIR/other-claim.md" "$HEAD1"
media claim 7 --run-id run-1
assert_exit "a claim held by another run on the same head aborts with exit 3" 3 "$RC"
cmp -s "$S/body" "$TEST_TMPDIR/other-claim.md"
assert_exit "an aborted claim leaves the body as it was" 0 "$?"
assert_eq "an aborted claim edits nothing" "0" "$(body_edits)"

reset "$TEST_TMPDIR/other-claim.md" "$HEAD2"
media claim 7 --run-id run-1
assert_exit "a claim left on an older head is taken over" 0 "$RC"
assert_contains "the takeover names the new head and run" "$(cat "$S/body")" \
  "<!-- reviewer-media:claimed $HEAD2 run-1 -->"
assert_not_contains "the takeover drops the old claim" "$(cat "$S/body")" "run-other"

# --- post, attaching ----------------------------------------------------------
M1="$TEST_TMPDIR/m1"
media_dir "$M1" "$HEAD1"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "post with a held claim exits 0" 0 "$RC"
assert_eq "bytes outside the markers are unchanged by post" \
  "$(outside_of "$TEST_TMPDIR/claimed.md")" "$(outside_of "$S/body")"
printf '%s\n' "$START" '## Reviewer media' '' \
  'For reviewers: a narrated walkthrough of this change. Watch it before the diff.' '' \
  "<!-- reviewer-media:posted $HEAD1 -->" '' \
  'https://github.com/user-attachments/assets/video.mp4' '' \
  '<details>' '<summary>Contact sheet</summary>' '' \
  '![Contact sheet 1](https://github.com/user-attachments/assets/sheet-1.png)' '' '</details>' '' \
  '<details>' '<summary>Chapters</summary>' '' '- 0:00 Intro' '- 1:05 The fix' '' '</details>' "$END" >"$TEST_TMPDIR/expected"
assert_eq "the section holds the heading, first line, video on top, then sheet and chapters in details" \
  "$(cat "$TEST_TMPDIR/expected")" "$(block_of "$S/body")"
assert_eq "the section sits between the linkage line and ## Summary" \
  "Closes #12||$START" "$(sed -n '1,3p' "$S/body" | paste -sd'|')"
assert_eq "only the manifest's video and contact sheet are attached" \
  "$(sums "$M1/video.mp4" "$M1/sheet-1.png")" "$(cat "$S/attached")"
assert_contains "post adds the posted label" "$(cat "$S/labels")" "$POSTED"
assert_not_contains "post leaves no request label" "$(cat "$S/labels")" "$REQUESTED"
bash "$SCRIPT_DIR/check-body-sections.sh" Summary Fix Verification Related <"$S/body" >/dev/null 2>&1
assert_exit "the posted body still passes the required-sections check" 0 "$?"

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M1/manifest.json" --run-id run-1 --label-posted false --label-requested false
assert_exit "post with labels turned off exits 0" 0 "$RC"
assert_not_contains "labels set to false make no label call" "$(cat "$S/calls")" "-label"

# --- a second run replaces only the marked block --------------------------------
reset "$FIXTURE" "$HEAD2"
media claim 7 --run-id run-2
assert_exit "claim on a body that already shows media exits 0" 0 "$RC"
M2="$TEST_TMPDIR/m2"
media_dir "$M2" "$HEAD2" "Second pass"
media post 7 --manifest "$M2/manifest.json" --run-id run-2
assert_exit "a second run posts" 0 "$RC"
assert_eq "a second run leaves every line outside the markers as the fixture has it" \
  "$(outside_of "$FIXTURE")" "$(outside_of "$S/body")"
assert_contains "the block now shows the new head" "$(block_of "$S/body")" "<!-- reviewer-media:posted $HEAD2 -->"
assert_contains "the block now lists the new chapters" "$(block_of "$S/body")" "- 1:05 Second pass"
assert_not_contains "the old head is gone from the body" "$(cat "$S/body")" "$HEAD1"
assert_not_contains "the old chapters are gone from the body" "$(cat "$S/body")" "The retry path"
assert_eq "the body holds one start and one end marker" "1 1" \
  "$(grep -c -- "^${START}\$" "$S/body") $(grep -c -- "^${END}\$" "$S/body")"

# --- claims and concurrent edits ----------------------------------------------
reset "$TEST_TMPDIR/other-claim.md" "$HEAD1"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "post under a claim held by another run aborts with exit 3" 3 "$RC"
assert_silent "post under another run's claim attaches nothing" "$(cat "$S/attached")"
cmp -s "$S/body" "$TEST_TMPDIR/other-claim.md"
assert_exit "post under another run's claim leaves the body as it was" 0 "$?"

reset "$PLAIN" "$HEAD1"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "post with no claim aborts with exit 3" 3 "$RC"

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
printf 'printf "%%s\\n" "A late edit by a person." >>"%s/body"\n' "$S" >"$S/view-hook-2"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "text outside the markers changing before the edit aborts with exit 3" 3 "$RC"
assert_contains "the person's edit survives" "$(cat "$S/body")" "A late edit by a person."
assert_not_contains "the aborted post wrote no section" "$(cat "$S/body")" "## Reviewer media"
assert_silent "the aborted post attaches nothing" "$(cat "$S/attached")"

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
printf 'sed "s/run-1/run-other/" "%s/body" >"%s/body.tmp" && mv "%s/body.tmp" "%s/body"\n' "$S" "$S" "$S" "$S" >"$S/view-hook-2"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "the claim changing before the edit aborts with exit 3" 3 "$RC"
assert_silent "a lost claim attaches nothing" "$(cat "$S/attached")"

reset "$TEST_TMPDIR/claimed.md" "$HEAD2"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "post after the head moved still posts" 0 "$RC"
assert_contains "media built for an older head carry the stale line" "$(block_of "$S/body")" \
  "Out of date: shows commit $HEAD1"

# --- hosting -------------------------------------------------------------------
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
printf 'FLAGS\n  -b, --body string   Set the new body.\n' >"$S/help"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "no attach and no artifact URL exits 4" 4 "$RC"
assert_contains "the refusal names its reason" "$OUT" "no-host"
cmp -s "$S/body" "$TEST_TMPDIR/claimed.md"
assert_exit "no attach and no artifact URL posts nothing" 0 "$?"
assert_eq "no attach and no artifact URL makes no body edit" "0" "$(body_edits)"
assert_not_contains "nothing posted adds no posted label" "$(cat "$S/labels")" "$POSTED"

media post 7 --manifest "$M1/manifest.json" --run-id run-1 \
  --artifact-url https://github.com/acme/app/actions/runs/99/artifacts/5 --retention-days 30
assert_exit "an artifact URL with no attach posts" 0 "$RC"
assert_contains "the section links the artifact" "$(block_of "$S/body")" \
  "(https://github.com/acme/app/actions/runs/99/artifacts/5)"
assert_contains "the section says how long the artifact is kept" "$(block_of "$S/body")" "kept 30 days"
assert_contains "the section still lists the chapters" "$(block_of "$S/body")" "- 1:05 The fix"
assert_not_contains "an artifact-only post attaches nothing" "$(cat "$S/calls")" "--attach"
assert_silent "an artifact-only post uploads no file" "$(cat "$S/attached")"

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
: >"$S/attach-fail"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "a refused upload with no artifact URL exits 4" 4 "$RC"
cmp -s "$S/body" "$TEST_TMPDIR/claimed.md"
assert_exit "a refused upload with no artifact URL leaves the body as it was" 0 "$?"

media post 7 --manifest "$M1/manifest.json" --run-id run-1 \
  --artifact-url 'https://example.com/x) [click](https://evil.example'
assert_exit "an artifact URL off github.com is a usage error" 2 "$RC"

# --- leak scan and allow-list ---------------------------------------------------
TOKEN="ghp_$(printf 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8')"
M3="$TEST_TMPDIR/m3"
media_dir "$M3" "$HEAD1" "Uses $TOKEN"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M3/manifest.json" --run-id run-1
assert_exit "a secret in the section exits 5" 5 "$RC"
assert_not_contains "the refusal never prints the matched text" "$OUT" "$TOKEN"
cmp -s "$S/body" "$TEST_TMPDIR/claimed.md"
assert_exit "a scan hit posts nothing" 0 "$?"
assert_silent "a scan hit uploads nothing" "$(cat "$S/attached")"
assert_eq "a scan hit makes no body edit" "0" "$(body_edits)"

HOME_PATH="/$(printf 'home')/octo/repo/x.py"
M4="$TEST_TMPDIR/m4"
media_dir "$M4" "$HEAD1" "Edits $HOME_PATH"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M4/manifest.json" --run-id run-1
assert_exit "a home path in the section exits 5" 5 "$RC"
assert_contains "the refusal names the kind" "$OUT" "home-path"
assert_silent "a home path uploads nothing" "$(cat "$S/attached")"

M5="$TEST_TMPDIR/m5"
media_dir "$M5" "$HEAD1"
printf 'shot-bytes' >"$M5/shot.png"
jq '.screenshots = ["shot.png"]' "$M1/manifest.json" >"$M5/manifest.json"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M5/manifest.json" --run-id run-1
assert_exit "a screenshot with no frame-text sidecar exits 6" 6 "$RC"
assert_silent "a screenshot with no sidecar uploads nothing" "$(cat "$S/attached")"
cmp -s "$S/body" "$TEST_TMPDIR/claimed.md"
assert_exit "a screenshot with no sidecar posts nothing" 0 "$?"

printf 'Settings page, Save button' >"$M5/shot.png.txt"
media post 7 --manifest "$M5/manifest.json" --run-id run-1
assert_exit "a screenshot with a clean sidecar posts" 0 "$RC"
assert_eq "the screenshot is attached after the video and sheet" \
  "$(sums "$M5/video.mp4" "$M5/sheet-1.png" "$M5/shot.png")" "$(cat "$S/attached")"
assert_contains "the screenshot is shown in the section" "$(block_of "$S/body")" \
  "![Screenshot 1](https://github.com/user-attachments/assets/screenshot-1.png)"

printf 'api key %s' "$TOKEN" >"$M5/shot.png.txt"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M5/manifest.json" --run-id run-1
assert_exit "a secret in a screenshot's sidecar exits 5" 5 "$RC"
assert_silent "a secret in a sidecar uploads nothing" "$(cat "$S/attached")"

M6="$TEST_TMPDIR/m6"
media_dir "$M6" "$HEAD1"
printf 'outside' >"$TEST_TMPDIR/outside.png"
jq '.contact_sheet = [{path: "../outside.png", bytes: 1}]' "$M1/manifest.json" >"$M6/manifest.json"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M6/manifest.json" --run-id run-1
assert_exit "a manifest path outside its directory exits 2" 2 "$RC"
assert_silent "a path outside the manifest directory uploads nothing" "$(cat "$S/attached")"

jq '.scan.status = "fail"' "$M1/manifest.json" >"$M6/manifest.json"
media post 7 --manifest "$M6/manifest.json" --run-id run-1
assert_exit "a manifest whose own scan did not pass exits 5" 5 "$RC"
assert_silent "a manifest whose scan did not pass uploads nothing" "$(cat "$S/attached")"

# --- stale ----------------------------------------------------------------------
reset "$FIXTURE" "$HEAD2"
media stale 7 --head "$HEAD2"
assert_exit "stale on a section for an older head exits 0" 0 "$RC"
assert_eq "the posted line becomes the stale line" "Out of date: shows commit $HEAD1" \
  "$(grep -- "$HEAD1" "$S/body")"
assert_eq "stale leaves every line outside the markers" "$(outside_of "$FIXTURE")" "$(outside_of "$S/body")"
assert_contains "stale keeps the media" "$(block_of "$S/body")" "https://github.com/user-attachments/assets/video.mp4"

reset "$FIXTURE" "$HEAD1"
media stale 7 --head "$HEAD1"
assert_exit "stale on a section for the current head exits 0" 0 "$RC"
assert_eq "a section for the current head is not edited" "0" "$(body_edits)"

reset "$PLAIN" "$HEAD2"
media stale 7 --head "$HEAD2"
assert_exit "stale on a body with no section exits 0" 0 "$RC"
assert_eq "a body with no section is not edited" "0" "$(body_edits)"

# --- fail -----------------------------------------------------------------------
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
grep -vxF "$REQUESTED" "$S/labels" >"$S/labels.new" && mv "$S/labels.new" "$S/labels"
media fail 7 --run-id run-1 --reason build-failed --run-url https://github.com/acme/app/actions/runs/99
assert_exit "fail exits 0" 0 "$RC"
cmp -s "$S/body" "$PLAIN"
assert_exit "fail removes a claim-only block and restores the body byte for byte" 0 "$?"
assert_contains "fail adds the failure label" "$(cat "$S/labels")" "$FAILED_LABEL"
assert_eq "fail posts one comment" "1" "$(find "$S/comments" -type f | wc -l | tr -d ' ')"
comment=$(cat "$S/comments/0")
assert_contains "the comment names the reason code" "$comment" "build-failed"
assert_contains "the comment links the run" "$comment" "https://github.com/acme/app/actions/runs/99"
assert_contains "the comment names the head" "$comment" "$HEAD1"

media fail 7 --run-id run-1 --reason build-failed --run-url https://github.com/acme/app/actions/runs/100
assert_exit "a second fail on the same head exits 0" 0 "$RC"
assert_eq "the same head never gets a second failure comment" "1" "$(find "$S/comments" -type f | wc -l | tr -d ' ')"

echo "$HEAD2" >"$S/head"
media fail 7 --run-id run-1 --reason build-failed
assert_eq "a new head gets its own failure comment" "2" "$(find "$S/comments" -type f | wc -l | tr -d ' ')"

reset "$FIXTURE" "$HEAD2"
media claim 7 --run-id run-2
media fail 7 --run-id run-2 --reason no-voice --label-failed false
assert_exit "fail over a section that already shows media exits 0" 0 "$RC"
assert_eq "fail drops only the claim line and keeps the earlier media" "$(cat "$FIXTURE")" "$(cat "$S/body")"
assert_not_contains "a failure label set to false is not added" "$(cat "$S/calls")" "--add-label"

media fail 7 --run-id run-2 --reason 'Bad Reason!'
assert_exit "a reason that is not a code is a usage error" 2 "$RC"

# --- markers --------------------------------------------------------------------
printf '%s\n' 'Closes #12' '' "$START" 'orphan' '' '## Summary' '' 'x' >"$TEST_TMPDIR/broken.md"
reset "$TEST_TMPDIR/broken.md" "$HEAD1"
media claim 7 --run-id run-1
assert_exit "a start marker with no end marker aborts with exit 3" 3 "$RC"
assert_eq "broken markers are never edited" "0" "$(body_edits)"

[[ $FAILED -eq 0 ]] || exit 1
