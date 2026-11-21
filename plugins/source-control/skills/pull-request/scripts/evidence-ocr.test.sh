# shellcheck shell=bash
# test-scope: plugins/source-control/skills/pull-request/scripts/evidence-ocr.py

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/evidence-ocr.py"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

PYTHON="$(command -v python3)" || skip_suite "python3 not installed"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
STUBS="$TEST_TMPDIR/stubs"
NO_TESSERACT="$TEST_TMPDIR/no-tesseract"
CAPTURES="$TEST_TMPDIR/captures"
mkdir -p "$STUBS" "$NO_TESSERACT" "$CAPTURES"
export OCR_STUB_CALLS="$TEST_TMPDIR/calls" OCR_STUB_TEXT="$TEST_TMPDIR/ocr-text"

printf '#!%s\n' "$BASH" | tee "$STUBS/ffmpeg" >"$STUBS/tesseract"
cat >>"$STUBS/ffmpeg" <<'STUB_EOF'
printf 'ffmpeg %s\n' "$*" >>"$OCR_STUB_CALLS"
out="${*: -1}"
case "$out" in
  *%06d.png) printf 'f' >"${out%/*}/frame-000001.png"; printf 'f' >"${out%/*}/frame-000002.png" ;;
  *) printf 'v' >"$out" ;;
esac
STUB_EOF
cat >>"$STUBS/tesseract" <<'STUB_EOF'
printf 'tesseract %s\n' "$*" >>"$OCR_STUB_CALLS"
printf '%s' "$(<"$OCR_STUB_TEXT")"
STUB_EOF
chmod +x "$STUBS/ffmpeg" "$STUBS/tesseract"
ln -s "$STUBS/ffmpeg" "$NO_TESSERACT/ffmpeg"

printf 'png' >"$CAPTURES/shot.png"
printf 'mp4' >"$CAPTURES/walkthrough.mp4"
SECRET="tok""en=Zq7Wm2Kx9Lp4Rt"
ERR="$TEST_TMPDIR/stderr"

ocr() { PATH="$STUBS" "$PYTHON" "$SCRIPT" "$@" 2>"$ERR"; }

printf 'Build passed on the settings page\n' >"$OCR_STUB_TEXT"
out=$(ocr "$CAPTURES/shot.png")
assert_exit "clean OCR text posts" 0 "$?"
assert_contains "a clean run states its cost" "$out" "1 captures, 1 images, 2 OCR passes in"
assert_contains "the image is read inverted as well" "$(cat "$OCR_STUB_CALLS")" "negate"
assert_contains "tesseract reads sparse screen text" "$(cat "$OCR_STUB_CALLS")" "--psm 11"

printf 'Signed in\n%s\n' "$SECRET" >"$OCR_STUB_TEXT"
ocr "$CAPTURES/shot.png" >/dev/null
assert_exit "a secret in an image's text is refused" 5 "$?"
assert_contains "the refusal names the capture and kind" "$(cat "$ERR")" "shot.png: secret assignment"
assert_not_contains "the refusal never prints the secret" "$(cat "$ERR")" "Zq7Wm2Kx9Lp4Rt"

printf 'Account owner\nAcme Ledger Ltd\n' >"$OCR_STUB_TEXT"
printf 'acme ledger\n' | ocr --mask-stdin "$CAPTURES/shot.png" >/dev/null
assert_exit "a mask value in the text, case and spacing aside, is refused" 5 "$?"
assert_contains "the mask refusal names its kind" "$(cat "$ERR")" "mask value"

: >"$OCR_STUB_TEXT"
ocr "$CAPTURES/shot.png" >/dev/null
assert_exit "OCR that reads no text is refused" 6 "$?"
assert_contains "the no-text refusal names the capture" "$(cat "$ERR")" "no-text: OCR read no text from shot.png"

printf 'Build passed\n' >"$OCR_STUB_TEXT"
PATH="$NO_TESSERACT" "$PYTHON" "$SCRIPT" "$CAPTURES/shot.png" >/dev/null 2>"$ERR"
assert_exit "a host without tesseract fails closed" 7 "$?"
assert_contains "the refusal names tesseract" "$(cat "$ERR")" "refused tesseract: tesseract is not installed"

: >"$OCR_STUB_CALLS"
out=$(ocr "$CAPTURES/walkthrough.mp4")
assert_exit "a clean video posts" 0 "$?"
assert_contains "every kept frame is read" "$out" "1 captures, 2 images, 4 OCR passes"
assert_contains "frames are sampled with mpdecimate at the default hi" "$(cat "$OCR_STUB_CALLS")" "mpdecimate=hi=256 -fps_mode vfr"

: >"$OCR_STUB_CALLS"
ocr --mpdecimate-hi 768 "$CAPTURES/walkthrough.mp4" >/dev/null
assert_contains "--mpdecimate-hi sets the threshold" "$(cat "$OCR_STUB_CALLS")" "mpdecimate=hi=768"

ocr --mpdecimate-hi 0 "$CAPTURES/walkthrough.mp4" >/dev/null
assert_exit "a threshold below 1 is a usage error" 2 "$?"
printf 'txt' >"$CAPTURES/notes.txt"
ocr "$CAPTURES/notes.txt" >/dev/null
assert_exit "a file that is not an image or video is a usage error" 2 "$?"

if ! command -v tesseract >/dev/null 2>&1 || ! command -v ffmpeg >/dev/null 2>&1; then
  skip_case "real OCR: tesseract or ffmpeg not installed"
else
  printf '%s' "$SECRET" >"$TEST_TMPDIR/planted.txt"
  for theme in white:black 0x1e1e1e:white; do
    shot="$CAPTURES/planted-${theme%%:*}.png"
    if ! ffmpeg -v error -y -f lavfi -i "color=c=${theme%%:*}:s=1000x120" \
      -vf "drawtext=textfile=$TEST_TMPDIR/planted.txt:fontcolor=${theme#*:}:fontsize=48:x=20:y=36" \
      -frames:v 1 -update 1 "$shot" 2>/dev/null; then
      skip_case "real OCR: this ffmpeg cannot draw text"
      continue
    fi
    "$PYTHON" "$SCRIPT" "$shot" >/dev/null 2>"$ERR"
    assert_exit "a secret drawn on ${theme%%:*} is read and refused" 5 "$?"
  done
fi

[[ $FAILED -eq 0 ]] || exit 1
