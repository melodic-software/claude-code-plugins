# shellcheck shell=bash
# Tests for read-review-venue.sh, run through bash (no #! line, no executable bit). Expected outputs follow the review_venue
# contract in reference/review-venue.md and reference/config-resolution.md: the
# repository value wins over userConfig, which wins over the default auto, and
# an unknown value falls back to auto with a notice.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/read-review-venue.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

REPO_LEVEL='repository (docs/conventions/source-control.yaml at main)'
ERR="$TEST_TMPDIR/stderr"
read_doc() { printf '%s' "$1" | bash "$SCRIPT" "${@:2}" --base main --default-branch main - 2>"$ERR"; }
line() { printf 'review_venue\t%s\t%s' "$1" "$2"; }

for v in auto local ci both; do
  out=$(read_doc "review_venue: $v"$'\n')
  assert_eq "the repository value $v is the venue" "$(line "$v" "$REPO_LEVEL")" "$out"
  assert_eq "the repository value $v prints no notice" "" "$(cat "$ERR")"
done

out=$(read_doc $'review_venue: everywhere\n')
assert_eq "an unknown repository value falls back to auto" \
  "$(line auto "invalid value at $REPO_LEVEL (fell back to auto)")" "$out"
assert_contains "an unknown repository value prints a notice" "$(cat "$ERR")" "review_venue 'everywhere' at repository"

out=$(read_doc $'review_venue: everywhere\n' --user ci)
assert_eq "an unknown repository value falls back to auto, not to userConfig" \
  "$(line auto "invalid value at $REPO_LEVEL (fell back to auto)")" "$out"

out=$(read_doc $'review_venue:\n  - ci\n')
assert_eq "a list is not a value and falls back to auto" \
  "$(line auto "invalid value at $REPO_LEVEL (fell back to auto)")" "$out"

out=$(read_doc $'review_venue: local\n' --user ci)
assert_eq "the repository value wins over userConfig" "$(line local "$REPO_LEVEL")" "$out"

out=$(read_doc $'pr_open_state: ready\n' --user both)
assert_eq "a file without the key leaves the userConfig value" "$(line both userConfig)" "$out"

# The userConfig level alone: no file read.
user_only() { bash "$SCRIPT" "$@" 2>"$ERR"; }
for v in local ci both; do
  assert_eq "the userConfig value $v is the venue" "$(line "$v" userConfig)" "$(user_only --user "$v")"
done
assert_eq "a substituted auto reports the default" "$(line auto default)" "$(user_only --user auto)"
assert_eq "no value at any level is auto" "$(line auto default)" "$(user_only)"
# shellcheck disable=SC2016 # the literal, unsubstituted placeholder
assert_eq "an unsubstituted placeholder is unset" "$(line auto default)" "$(user_only --user '${user_config.review_venue}')"
out=$(user_only --user Local)
assert_eq "an unknown userConfig value falls back to auto" \
  "$(line auto 'invalid value at userConfig (fell back to auto)')" "$out"
assert_contains "an unknown userConfig value prints a notice" "$(cat "$ERR")" "review_venue 'Local' at userConfig"

# A repository level that cannot be read or trusted is skipped with a notice.
out=$(printf 'review_venue: ci\n' | bash "$SCRIPT" --user local --base stack/layer-2 --default-branch main - 2>"$ERR")
assert_eq "a base other than the default branch leaves the repository level unread" "$(line local userConfig)" "$out"
assert_contains "the unread base is named" "$(cat "$ERR")" "base stack/layer-2 is not the default branch main"

out=$(read_doc $'review_venue: ci\n\tbad: x\n')
assert_eq "a file the parser rejects leaves the repository level unread" "$(line auto default)" "$out"
assert_contains "the parse failure is named" "$(cat "$ERR")" "does not parse"

out=$(printf 'review_venue: c\000i\n' | bash "$SCRIPT" --base main --default-branch main - 2>"$ERR")
assert_eq "a NUL byte leaves the repository level unread" "$(line auto default)" "$out"

# --http-response reads a `gh api -i` response: the status line decides.
read_response() { printf '%s' "$1" | bash "$SCRIPT" "${@:2}" --base main --default-branch main --http-response 2>"$ERR"; }
out=$(read_response $'HTTP/2.0 200 OK\r\nContent-Type: application/vnd.github.raw\r\n\r\nreview_venue: ci\n')
assert_eq "a 200 response is read as the document" "$(line ci "$REPO_LEVEL")" "$out"
out=$(read_response $'HTTP/2.0 404 Not Found\r\n\r\n{"message":"Not Found"}' --user both)
assert_eq "a 404 response leaves the userConfig value" "$(line both userConfig)" "$out"
assert_eq "a 404 response prints no notice" "" "$(cat "$ERR")"
out=$(read_response $'HTTP/2.0 502 Bad Gateway\r\n\r\n')
assert_eq "a 5xx response leaves the repository level unread" "$(line auto default)" "$out"
assert_contains "the failed read is named" "$(cat "$ERR")" "502"

printf '' | bash "$SCRIPT" - >/dev/null 2>&1
assert_exit "a file read without --base and --default-branch is a usage error" 2 "$?"
bash "$SCRIPT" --base main >/dev/null 2>&1
assert_exit "--base without a file read is a usage error" 2 "$?"
bash "$SCRIPT" --user >/dev/null 2>&1
assert_exit "--user without a value is a usage error" 2 "$?"
bash "$SCRIPT" "$TEST_TMPDIR/source-control.yaml" >/dev/null 2>&1
assert_exit "a working-tree path is refused" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
