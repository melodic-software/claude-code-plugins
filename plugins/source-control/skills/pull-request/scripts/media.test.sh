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
record_edit() { bash "$(dirname "$0")/record-edit" "$S" "$1"; }
case "$1 $2" in
  "api graphql")
    # GraphQL viewer names an App or Actions token `name[bot]`; its edits' editor is `name`.
    jq -n --slurpfile edits "$S/edits.jsonl" \
      --arg viewer "$( [[ -f "$S/viewer" ]] && cat "$S/viewer" || echo media-bot)" \
      '{data: {viewer: {login: $viewer}, repository: {pullRequest:
        {userContentEdits: {nodes: ($edits | reverse | .[0:20])}}}}}'
    ;;
  "api user")
    echo media-bot
    ;;
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
      w=$(($(cat "$S/writes") + 1))
      echo "$w" >"$S/writes"
      # A person's edit landing while this call uploads, before gh writes the body.
      [[ ! -f "$S/write-hook-$w" ]] || bash "$S/write-hook-$w"
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
      record_edit media-bot
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
    # What gh prints for media.py's --jq: one {login, type, body} object per comment.
    for f in "$S"/comments/*; do
      [[ -f "$f" ]] || continue
      who="$S/authors/$(basename "$f")"
      jq -cn --rawfile body "$f" --arg login "$( [[ -f "$who" ]] && cut -d' ' -f1 "$who" || echo media-bot)" \
        --arg type "$( [[ -f "$who" ]] && cut -d' ' -f2 "$who" || echo User)" \
        '{login: $login, type: $type, body: $body}'
    done
    ;;
  *)
    echo "gh-stub: unrouted $*" >&2
    exit 1
    ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

# record-edit <state> <login>: the body's edit history gains the current body as
# an edit by <login>, as GitHub's userContentEdits holds each revision in `diff`.
cat >"$STUB_DIR/record-edit" <<'STUB_EOF'
n=$(($(wc -l <"$1/edits.jsonl") + 1))
jq -cn --rawfile body "$1/body" --arg who "$2" --arg id "E$n" \
  --arg at "$(printf '2026-01-01T00:%02d:%02dZ' $((n / 60)) $((n % 60)))" \
  '{id: $id, editedAt: $at, editor: {login: $who}, diff: $body}' >>"$1/edits.jsonl"
STUB_EOF

# person-edit <state> <line>: a person appends a line to the PR body.
cat >"$STUB_DIR/person-edit" <<'STUB_EOF'
printf '%s\n' "$2" >>"$1/body"
bash "$(dirname "$0")/record-edit" "$1" a-person
STUB_EOF

# reset <body-file> <head>: a fresh pull request #7 holding that body.
reset() {
  rm -rf "$S"
  mkdir -p "$S/comments" "$S/authors"
  cp "$1" "$S/body"
  : >"$S/edits.jsonl"
  bash "$STUB_DIR/record-edit" "$S" a-person
  echo 0 >"$S/writes"
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
  jq -n --arg head "$2" --arg title "${3:-The fix}" \
    --arg vsum "$(sha "$1/video.mp4")" --arg ssum "$(sha "$1/sheet-1.png")" '{
    head_sha: $head, storyboard_sha256: "0",
    video: {path: "video.mp4", bytes: 1, duration_s: 90, captions: "burned", sha256: $vsum},
    chapters: [{title: "Intro", start_s: 0}, {title: $title, start_s: 65}],
    contact_sheet: [{path: "sheet-1.png", bytes: 1, sha256: $ssum}], screenshots: [],
    voice: {backend: "edge-tts", voice: "en-US-AndrewNeural"},
    scan: {status: "pass", floor_rules: 1}, encode: {profile: "reviewer-stills", steps: []}}' >"$1/manifest.json"
}

sums() { for f in "$@"; do cksum <"$f"; done; }

# sha <file>: the file's lowercase hex SHA-256, from the system tool.
sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# shot_entry <dir> <image> <sidecar>: a screenshot manifest entry binding both files.
shot_entry() {
  jq -cn --arg p "$2" --arg s "$3" --arg ps "$(sha "$1/$2")" --arg ss "$(sha "$1/$3")" \
    '{path: $p, sha256: $ps, sidecar: $s, sidecar_sha256: $ss}'
}

# block_of <body-file>: the lines from the start marker through the end marker.
block_of() { sed -n "/^${START}\$/,/^${END}\$/p" "$1"; }

# outside_of <body-file>: every line outside the marked block.
outside_of() { sed "/^${START}\$/,/^${END}\$/d" "$1"; }

body_edits() { grep -c -- '^pr edit .*--body-file' "$S/calls" || true; }

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

reset "$PLAIN" "$HEAD1"
printf '<!-- reviewer-media:failed %s -->\n' "$HEAD1" >"$S/comments/0"
media claim 7 --run-id run-1
assert_exit "a claim on a head that already has its failure comment aborts with exit 3" 3 "$RC"
assert_contains "the refusal names the failed head" "$OUT" "refused failed"
assert_eq "a refused claim on a failed head edits nothing" "0" "$(body_edits)"
assert_contains "a refused claim on a failed head keeps the request label" "$(cat "$S/labels")" "$REQUESTED"

reset "$PLAIN" "$HEAD2"
printf '<!-- reviewer-media:failed %s -->\n' "$HEAD1" >"$S/comments/0"
media claim 7 --run-id run-1
assert_exit "a failure comment on an older head does not stop a claim on the new one" 0 "$RC"

reset "$PLAIN" "$HEAD1"
printf '<!-- reviewer-media:failed %s -->\n' "$HEAD1" >"$S/comments/0"
echo "someone User" >"$S/authors/0"
media claim 7 --run-id run-1
assert_exit "a failure marker planted by another person does not stop a claim" 0 "$RC"

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

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
printf 'echo %s >"%s/head"\n' "$HEAD2" "$S" >"$S/view-hook-2"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "post when the head moves before the write still posts" 0 "$RC"
assert_contains "a head that moved before the write gets the stale line" "$(block_of "$S/body")" \
  "Out of date: shows commit $HEAD1"

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
printf 'echo %s >"%s/head"\n' "$HEAD2" "$S" >"$S/write-hook-1"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "post when the head moves during the upload still posts" 0 "$RC"
assert_contains "a head that moved during the upload gets the stale line" "$(block_of "$S/body")" \
  "Out of date: shows commit $HEAD1"
assert_not_contains "a head that moved during the upload leaves no posted line" "$(block_of "$S/body")" \
  "<!-- reviewer-media:posted"
assert_contains "the stale section keeps the uploaded video" "$(block_of "$S/body")" \
  "https://github.com/user-attachments/assets/video.mp4"

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
printf 'shot-two-bytes' >"$M5/shot-2.png"
mkdir -p "$M5/frames"
printf 'Settings page, Save button' >"$M5/frames/shot.txt"
printf 'Profile page' >"$M5/frames/shot-2.txt"
# shots <entries-json>: M5's manifest with those screenshot entries.
shots() { jq --argjson s "$1" '.screenshots = $s' "$M5/base.json" >"$M5/manifest.json"; }
cp "$M5/manifest.json" "$M5/base.json"

shots '["shot.png"]'
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M5/manifest.json" --run-id run-1
assert_exit "a bare-string screenshot entry names no sidecar and exits 6" 6 "$RC"
assert_silent "a bare-string screenshot uploads nothing" "$(cat "$S/attached")"

shots "[$(jq -c 'del(.sidecar, .sidecar_sha256)' <<<"$(shot_entry "$M5" shot.png frames/shot.txt)")]"
media post 7 --manifest "$M5/manifest.json" --run-id run-1
assert_exit "a screenshot with no frame-text sidecar exits 6" 6 "$RC"
assert_silent "a screenshot with no sidecar uploads nothing" "$(cat "$S/attached")"
cmp -s "$S/body" "$TEST_TMPDIR/claimed.md"
assert_exit "a screenshot with no sidecar posts nothing" 0 "$?"

shots "[$(shot_entry "$M5" shot.png frames/shot.txt), $(shot_entry "$M5" shot-2.png frames/shot.txt)]"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M5/manifest.json" --run-id run-1
assert_exit "two screenshots sharing one sidecar exit 6" 6 "$RC"
assert_silent "a shared sidecar uploads nothing" "$(cat "$S/attached")"

# A secret beside the image under the old <image>.txt name is not the sidecar the entry names.
printf 'api key %s' "$TOKEN" >"$M5/shot.png.txt"
shots "[$(shot_entry "$M5" shot.png frames/shot.txt)]"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M5/manifest.json" --run-id run-1
assert_exit "a screenshot with a clean named sidecar posts" 0 "$RC"
assert_eq "the screenshot is attached after the video and sheet" \
  "$(sums "$M5/video.mp4" "$M5/sheet-1.png" "$M5/shot.png")" "$(cat "$S/attached")"
assert_contains "the screenshot is shown in the section" "$(block_of "$S/body")" \
  "![Screenshot 1](https://github.com/user-attachments/assets/screenshot-1.png)"

printf 'api key %s' "$TOKEN" >"$M5/frames/secret.txt"
shots "[$(shot_entry "$M5" shot.png frames/secret.txt)]"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M5/manifest.json" --run-id run-1
assert_exit "a secret in a screenshot's sidecar exits 5" 5 "$RC"
assert_silent "a secret in a sidecar uploads nothing" "$(cat "$S/attached")"

shots "[$(shot_entry "$M5" shot.png frames/shot.txt)]"
printf 'Settings page, Save button, and %s' "$TOKEN" >"$M5/frames/shot.txt"
media post 7 --manifest "$M5/manifest.json" --run-id run-1
assert_exit "a sidecar changed after its digest was taken exits 5" 5 "$RC"
assert_contains "the refusal names it unbound" "$OUT" "unbound"
assert_not_contains "the unbound refusal never prints the sidecar text" "$OUT" "$TOKEN"
assert_silent "an unbound sidecar uploads nothing" "$(cat "$S/attached")"
printf 'Settings page, Save button' >"$M5/frames/shot.txt"

# --- every uploaded file is bound to its manifest digest --------------------------
M7="$TEST_TMPDIR/m7"
media_dir "$M7" "$HEAD1"
cp "$M7/manifest.json" "$M7/base.json"
jq 'del(.video.sha256)' "$M7/base.json" >"$M7/manifest.json"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M7/manifest.json" --run-id run-1
assert_exit "a video with no digest exits 5" 5 "$RC"
assert_contains "a missing digest is refused as unbound" "$OUT" "unbound"
assert_silent "a video with no digest uploads nothing" "$(cat "$S/attached")"
assert_eq "a video with no digest makes no body edit" "0" "$(body_edits)"

cp "$M7/base.json" "$M7/manifest.json"
printf 'swapped-after-the-scan' >"$M7/video.mp4"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M7/manifest.json" --run-id run-1
assert_exit "a video whose bytes no longer match its digest exits 5" 5 "$RC"
assert_contains "a mismatched video is refused as unbound" "$OUT" "unbound"
assert_silent "a mismatched video uploads nothing" "$(cat "$S/attached")"

media_dir "$M7" "$HEAD1"
printf 'other-sheet' >"$M7/sheet-1.png"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M7/manifest.json" --run-id run-1
assert_exit "a contact sheet whose bytes no longer match its digest exits 5" 5 "$RC"
assert_silent "a mismatched contact sheet uploads nothing" "$(cat "$S/attached")"

media_dir "$M7" "$HEAD1"
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media post 7 --manifest "$M7/manifest.json" --run-id run-1 --no-attach \
  --artifact-url https://github.com/acme/app/actions/runs/99 --artifact-name 'x) [click](https://evil.example'
assert_exit "an artifact name outside letters, digits, dots, underscores and hyphens is a usage error" 2 "$RC"
assert_eq "a bad artifact name makes no body edit" "0" "$(body_edits)"

# --- a person's edit during the upload is kept ------------------------------------
reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
printf 'bash "%s/person-edit" "%s" "Hold: waiting on the owner."\n' "$STUB_DIR" "$S" >"$S/write-hook-1"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "a person's edit during the upload still posts" 0 "$RC"
assert_contains "the person's edit made during the upload survives" "$(cat "$S/body")" "Hold: waiting on the owner."
assert_contains "the section is posted beside the person's edit" "$(block_of "$S/body")" \
  "https://github.com/user-attachments/assets/video.mp4"
assert_eq "the files are uploaded once" "$(sums "$M1/video.mp4" "$M1/sheet-1.png")" "$(cat "$S/attached")"
printf '%s\n' "$(outside_of "$TEST_TMPDIR/claimed.md")" "Hold: waiting on the owner." >"$TEST_TMPDIR/expected"
assert_eq "outside the markers the body is the person's version" "$(cat "$TEST_TMPDIR/expected")" "$(outside_of "$S/body")"

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
printf 'bash "%s/person-edit" "%s" "First late edit."\n' "$STUB_DIR" "$S" >"$S/write-hook-1"
printf 'bash "%s/person-edit" "%s" "Second late edit."\n' "$STUB_DIR" "$S" >"$S/write-hook-2"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "a person editing again during the repair write aborts with exit 3" 3 "$RC"
assert_contains "the second refusal names the change" "$OUT" "changed"

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
echo 'media-bot[bot]' >"$S/viewer"
printf 'bash "%s/person-edit" "%s" "Hold: waiting on the owner."\n' "$STUB_DIR" "$S" >"$S/write-hook-1"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "a bot token's edit during the upload still posts" 0 "$RC"
assert_contains "a bot viewer keeps the person's edit made during the upload" "$(cat "$S/body")" "Hold: waiting on the owner."

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
echo 'media-bot[bot]' >"$S/viewer"
printf 'bash "%s/person-edit" "%s" "First late edit."\n' "$STUB_DIR" "$S" >"$S/write-hook-1"
printf 'bash "%s/person-edit" "%s" "Second late edit."\n' "$STUB_DIR" "$S" >"$S/write-hook-2"
media post 7 --manifest "$M1/manifest.json" --run-id run-1
assert_exit "a bot viewer still aborts with exit 3 on a second edit during the repair" 3 "$RC"
assert_contains "a bot viewer's second refusal names the change" "$OUT" "changed"

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
assert_contains "stale keeps the media" "$(block_of "$S/body")" "https://example.com/user-attachments/assets/video.mp4"

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

reset "$PLAIN" "$HEAD1"
printf '<!-- reviewer-media:failed %s -->\nPlanted by someone else.\n' "$HEAD1" >"$S/comments/0"
echo "someone User" >"$S/authors/0"
media fail 7 --run-id run-1 --reason build-failed
assert_eq "a marker comment by another person does not stop the failure comment" "2" \
  "$(find "$S/comments" -type f | wc -l | tr -d ' ')"

reset "$PLAIN" "$HEAD1"
printf '<!-- reviewer-media:failed %s -->\n' "$HEAD1" >"$S/comments/0"
echo "media-lane[bot] Bot" >"$S/authors/0"
media fail 7 --run-id run-1 --reason build-failed
assert_eq "a marker comment by a bot account counts as the failure comment" "1" \
  "$(find "$S/comments" -type f | wc -l | tr -d ' ')"

printf '%s\n' 'Closes #12' '' "$START" "<!-- reviewer-media:claimed $HEAD1 run-1 -->" '' '## Summary' '' 'x' >"$TEST_TMPDIR/broken-claim.md"
reset "$TEST_TMPDIR/broken-claim.md" "$HEAD1"
media fail 7 --run-id run-1 --reason build-failed
assert_exit "fail on a body with broken markers exits 3" 3 "$RC"
assert_eq "fail on broken markers makes no body edit" "0" "$(body_edits)"
assert_contains "fail on broken markers still adds the failure label" "$(cat "$S/labels")" "$FAILED_LABEL"
assert_eq "fail on broken markers still posts the failure comment" "1" \
  "$(find "$S/comments" -type f | wc -l | tr -d ' ')"

# An installation token or GITHUB_TOKEN gets 403 from GET /user.
NO_USER_DIR="$TEST_TMPDIR/stubs-no-user"
mkdir -p "$NO_USER_DIR"
cat >"$NO_USER_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
[[ "$1 $2" != "api user" ]] || { echo "HTTP 403" >&2; exit 1; }
[[ ! -f "$MEDIA_GH_STATE/no-viewer" || "$1 $2" != "api graphql" ]] || { echo "HTTP 403" >&2; exit 1; }
exec "$(dirname "$0")/../stubs/gh" "$@"
STUB_EOF
chmod +x "$NO_USER_DIR/gh"
media_no_user() {
  OUT=$(MEDIA_GH_STATE="$S" PATH="$NO_USER_DIR:$STUB_DIR:$PATH" python3 -B "$SCRIPT" "$@" 2>&1)
  RC=$?
}

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
media_no_user fail 7 --run-id run-1 --reason build-failed
assert_exit "fail with a token that cannot read /user exits 0" 0 "$RC"
assert_eq "fail with a token that cannot read /user still posts the failure comment" "1" \
  "$(find "$S/comments" -type f | wc -l | tr -d ' ')"
media_no_user fail 7 --run-id run-1 --reason build-failed
assert_eq "its own earlier failure comment still counts without /user" "1" \
  "$(find "$S/comments" -type f | wc -l | tr -d ' ')"

reset "$TEST_TMPDIR/claimed.md" "$HEAD1"
: >"$S/no-viewer"
printf '<!-- reviewer-media:failed %s -->\n' "$HEAD1" >"$S/comments/0"
echo "media-bot User" >"$S/authors/0"
media_no_user fail 7 --run-id run-1 --reason build-failed
assert_exit "fail with no identity lookup at all exits 0" 0 "$RC"
assert_eq "with no identity, a person-type marker comment does not count" "2" \
  "$(find "$S/comments" -type f | wc -l | tr -d ' ')"
cmp -s "$S/body" "$PLAIN"
assert_exit "with no identity, fail still releases its claim" 0 "$?"

reset "$PLAIN" "$HEAD1"
: >"$S/no-viewer"
printf '<!-- reviewer-media:failed %s -->\n' "$HEAD1" >"$S/comments/0"
echo "media-lane[bot] Bot" >"$S/authors/0"
media_no_user fail 7 --run-id run-1 --reason build-failed
assert_eq "with no identity, a bot marker comment still counts" "1" \
  "$(find "$S/comments" -type f | wc -l | tr -d ' ')"

# A run whose claim another run took over records nothing against that run's head.
reset "$TEST_TMPDIR/other-claim.md" "$HEAD2"
cp "$S/labels" "$TEST_TMPDIR/labels-before"
media fail 7 --run-id run-1 --reason build-failed
assert_exit "fail when another run holds the claim exits 3" 3 "$RC"
assert_contains "the refusal names the claim" "$OUT" "claim"
cmp -s "$S/body" "$TEST_TMPDIR/other-claim.md"
assert_exit "fail under another run's claim leaves the body as it was" 0 "$?"
assert_eq "fail under another run's claim changes no label" "$(cat "$TEST_TMPDIR/labels-before")" "$(cat "$S/labels")"
assert_eq "fail under another run's claim posts no comment" "0" \
  "$(find "$S/comments" -type f | wc -l | tr -d ' ')"
assert_not_contains "fail under another run's claim makes no edit call" "$(cat "$S/calls")" "pr edit"

# --- markers --------------------------------------------------------------------
printf '%s\n' 'Closes #12' '' "$START" 'orphan' '' '## Summary' '' 'x' >"$TEST_TMPDIR/broken.md"
reset "$TEST_TMPDIR/broken.md" "$HEAD1"
media claim 7 --run-id run-1
assert_exit "a start marker with no end marker aborts with exit 3" 3 "$RC"
assert_eq "broken markers are never edited" "0" "$(body_edits)"

[[ $FAILED -eq 0 ]] || exit 1
