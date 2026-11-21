# shellcheck shell=bash
# Tests for read-evidence-layout.sh, run through bash (no #! line, no executable bit). Expected
# outputs follow the evidence_inline_max_captures and evidence_record_fields contract in
# reference/evidence.md and reference/config-resolution.md: the repository value at the default
# branch wins over the default (4 and false), and an invalid value falls back to the default with a
# notice.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/read-evidence-layout.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

REPO_LEVEL='repository (docs/conventions/source-control.yaml at main)'
ERR="$TEST_TMPDIR/stderr"
read_doc() { printf '%s' "$1" | bash "$SCRIPT" "${@:2}" --base main --default-branch main - 2>"$ERR"; }
lines() {
  printf 'evidence_inline_max_captures\t%s\t%s\nevidence_record_fields\t%s\t%s\nevidence_ocr_mpdecimate_hi\t%s\t%s' \
    "$1" "$2" "$3" "$4" "${5:-256}" "${6:-default}"
}

assert_eq "no repository level gives every default, hi 256 included" "$(lines 4 default false default 256 default)" "$(bash "$SCRIPT" 2>"$ERR")"
assert_eq "no repository level prints no notice" "" "$(cat "$ERR")"

out=$(read_doc $'evidence_inline_max_captures: 6\nevidence_record_fields: true\n')
assert_eq "the repository values win" "$(lines 6 "$REPO_LEVEL" true "$REPO_LEVEL")" "$out"
assert_eq "valid repository values print no notice" "" "$(cat "$ERR")"

out=$(read_doc $'evidence_inline_max_captures: 0\n')
assert_eq "0 is a valid threshold and the other key keeps its default" \
  "$(lines 0 "$REPO_LEVEL" false default)" "$out"

out=$(read_doc $'evidence_record_fields: false\n')
assert_eq "an explicit false reports the repository level" "$(lines 4 default false "$REPO_LEVEL")" "$out"

out=$(read_doc $'pr_open_state: ready\n')
assert_eq "a file without either key gives both defaults" "$(lines 4 default false default)" "$out"

for bad in -1 2.5 four 1000 04; do
  out=$(read_doc "evidence_inline_max_captures: $bad"$'\n')
  assert_eq "threshold $bad falls back to 4" \
    "$(lines 4 "invalid value at $REPO_LEVEL (fell back to 4)" false default)" "$out"
  assert_contains "threshold $bad prints a notice" "$(cat "$ERR")" "evidence_inline_max_captures"
done

for bad in yes True 1; do
  out=$(read_doc "evidence_record_fields: $bad"$'\n')
  assert_eq "record switch $bad falls back to false" \
    "$(lines 4 default false "invalid value at $REPO_LEVEL (fell back to false)")" "$out"
  assert_contains "record switch $bad prints a notice" "$(cat "$ERR")" "evidence_record_fields"
done

out=$(read_doc $'evidence_ocr_mpdecimate_hi: 768\n')
assert_eq "the repository's mpdecimate threshold wins over 256" \
  "$(lines 4 default false default 768 "$REPO_LEVEL")" "$out"

for bad in 0 10000 2.5 high; do
  out=$(read_doc "evidence_ocr_mpdecimate_hi: $bad"$'\n')
  assert_eq "mpdecimate threshold $bad falls back to 256" \
    "$(lines 4 default false default 256 "invalid value at $REPO_LEVEL (fell back to 256)")" "$out"
  assert_contains "mpdecimate threshold $bad prints a notice" "$(cat "$ERR")" "evidence_ocr_mpdecimate_hi"
done

out=$(read_doc $'evidence_inline_max_captures:\n  - 4\n')
assert_eq "a list is not a threshold" \
  "$(lines 4 "invalid value at $REPO_LEVEL (fell back to 4)" false default)" "$out"

# A repository level that cannot be read or trusted is skipped with a notice.
out=$(printf 'evidence_record_fields: true\n' | bash "$SCRIPT" --base stack/layer-2 --default-branch main - 2>"$ERR")
assert_eq "a base other than the default branch leaves the repository level unread" \
  "$(lines 4 default false default)" "$out"
assert_contains "the unread base is named" "$(cat "$ERR")" "base stack/layer-2 is not the default branch main"

out=$(read_doc $'evidence_record_fields: true\n\tbad: x\n')
assert_eq "a file the parser rejects leaves the repository level unread" "$(lines 4 default false default)" "$out"
assert_contains "the parse failure is named" "$(cat "$ERR")" "does not parse"

out=$(printf 'evidence_record_fields: t\000rue\n' | bash "$SCRIPT" --base main --default-branch main - 2>"$ERR")
assert_eq "a NUL byte leaves the repository level unread" "$(lines 4 default false default)" "$out"

# --http-response reads a `gh api -i` response: the status line decides.
read_response() { printf '%s' "$1" | bash "$SCRIPT" --base main --default-branch main --http-response 2>"$ERR"; }
out=$(read_response $'HTTP/2.0 200 OK\r\nContent-Type: application/vnd.github.raw\r\n\r\nevidence_inline_max_captures: 2\n')
assert_eq "a 200 response is read as the document" "$(lines 2 "$REPO_LEVEL" false default)" "$out"
out=$(read_response $'HTTP/2.0 404 Not Found\r\n\r\n{"message":"Not Found"}')
assert_eq "a 404 response gives both defaults" "$(lines 4 default false default)" "$out"
assert_eq "a 404 response prints no notice" "" "$(cat "$ERR")"
out=$(read_response $'HTTP/2.0 502 Bad Gateway\r\n\r\n')
assert_eq "a 5xx response leaves the repository level unread" "$(lines 4 default false default)" "$out"
assert_contains "the failed read is named" "$(cat "$ERR")" "502"

printf '' | bash "$SCRIPT" - >/dev/null 2>&1
assert_exit "a file read without --base and --default-branch is a usage error" 2 "$?"
bash "$SCRIPT" --base main >/dev/null 2>&1
assert_exit "--base without a file read is a usage error" 2 "$?"
bash "$SCRIPT" "$TEST_TMPDIR/source-control.yaml" >/dev/null 2>&1
assert_exit "a working-tree path is refused" 2 "$?"
out=$(bash "$SCRIPT" --help 2>"$ERR")
assert_exit "--help exits 0" 0 "$?"
assert_contains "--help names the mpdecimate threshold" "$out" "evidence_ocr_mpdecimate_hi"

[[ $FAILED -eq 0 ]] || exit 1
