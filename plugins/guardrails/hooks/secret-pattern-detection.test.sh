#!/usr/bin/env bash
# Contract test for secret-pattern-detection.sh (guardrails plugin).
#
# Black-box subprocess invocation. The hook reads file_path as a string only —
# fixtures need not exist on disk.
#
# Token construction discipline: every real-shape token is assembled at runtime
# from concatenated parts, so the literal joined string never appears in this
# file's source bytes — no secret scanner (gitleaks etc.) sees a committed key.
# test-scope: plugins/guardrails/hooks/hooks.json

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/secret-pattern-detection.sh"
TEST_TMPDIR="$(mktemp -d)"
D1_LINKDIR=""
D1_SEAMDIR=""
d1_cleanup() {
  if [[ -n "$D1_SEAMDIR" ]]; then
    rmdir "$D1_SEAMDIR/lowtemp" "$D1_SEAMDIR/CapTemp" 2>/dev/null
    rmdir "$D1_SEAMDIR" 2>/dev/null
  fi
  [[ -n "$D1_LINKDIR" ]] || return 0
  if [[ -L "$D1_LINKDIR/ToHooks" ]]; then
    if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
      MSYS_NO_PATHCONV=1 cmd /c rmdir "$(cygpath -w "$D1_LINKDIR/ToHooks")" >/dev/null 2>&1
    else
      rm -f "$D1_LINKDIR/ToHooks"
    fi
  fi
  rm -f "$D1_LINKDIR/hl-src.txt" "$D1_LINKDIR/hl.txt" "$D1_LINKDIR/plain.txt"
  rmdir "$D1_LINKDIR/sub" 2>/dev/null
  rmdir "$D1_LINKDIR" 2>/dev/null
  return 0
}
trap 'd1_cleanup; rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free

unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ALLOWED_ROOTS \
  CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_SKIP_GITIGNORED

AWS_PREFIX='AKIA'
AWS_TOKEN="${AWS_PREFIX}IOSFODNN7EXAMPLE"
GH_PREFIX='ghp_'
GH_PAT="${GH_PREFIX}$(printf 'a%.0s' {1..36})"
GHS_PREFIX='ghs_'
GH_APP_TOKEN="${GHS_PREFIX}$(printf 'b%.0s' {1..36})"
GH_APP_TOKEN_JWT="${GHS_PREFIX}1234567_eyJFAKE.FAKEpayload$(printf 'A%.0s' {1..450}).FAKEsignatureNOTreal"
SLACK_PREFIX='xoxb-'
SLACK_TOKEN="${SLACK_PREFIX}1234567890123-9876543210987"
STRIPE_PREFIX='sk_live_'
STRIPE_TOKEN="${STRIPE_PREFIX}abcdefghij1234567890"
OPENAI_PREFIX='sk-'
OPENAI_BARE_KEY="${OPENAI_PREFIX}$(printf 'A%.0s' {1..25})"
PEM_HEADER='-----BEGIN '"PRIVATE KEY-----"

# Force the Windows case-fold path even on Linux CI: OSTYPE must be set BEFORE
# the hook is sourced (bash resets it to the build value at startup).
run_hook_windows() {
  bash -c 'OSTYPE=msys; source "$1"' _ "$HOOK" <<<"$1"
}

FIXTURE="$TEST_TMPDIR/fixture.txt"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "AWS Access Key → exit 2" 2 "$RC"
assert_contains "AWS → message" "$OUT" "AWS Access Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "token = '$GH_PAT'")" 2>&1)
RC=$?
assert_exit "GitHub PAT → exit 2" 2 "$RC"
assert_contains "GH PAT → message" "$OUT" "GitHub PAT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "token = '$GH_APP_TOKEN'")" 2>&1)
RC=$?
assert_exit "GitHub App token, 36-char form → exit 2" 2 "$RC"
assert_contains "GH App token, 36-char form → message" "$OUT" "GitHub App Token"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "token = '$GH_APP_TOKEN_JWT'")" 2>&1)
RC=$?
assert_exit "GitHub App token, ghs_<APPID>_<JWT> form → exit 2" 2 "$RC"
assert_contains "GH App token, ghs_<APPID>_<JWT> form → message" "$OUT" "GitHub App Token"

b64url() { printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_'; }
JWT_TAIL=".$(b64url '{"sub":"FAKE-not-a-real-token","iat":0}').$(b64url "$(printf 'FAKE signature, not a real token?>%.0s' {1..10})")"
for header in "$(b64url '{"alg":"RS256","typ":"JWT"}')" "$(b64url '{"kid":"k?~>","alg":"RS256","typ":"JWT"}')"; do
  for tok in "${GHS_PREFIX}$header$JWT_TAIL" "${GHS_PREFIX}123456_$header$JWT_TAIL"; do
    OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "token = '$tok'")" 2>&1)
    RC=$?
    assert_exit "stateless GitHub App token ${tok:0:20}... → exit 2" 2 "$RC"
    assert_contains "stateless GitHub App token ${tok:0:20}... → message" "$OUT" "GitHub App Token"
    OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "{\"log\": \"line\\n$tok\"}")" 2>&1)
    RC=$?
    assert_exit "GitHub App token ${tok:0:20}... after a literal \\n → exit 2" 2 "$RC"
  done
done

SLOW_SHAPES=(
  "${GHS_PREFIX}1_-:50000" "${GHS_PREFIX}1_eyJ:30000" "${GHS_PREFIX}1_eyJa.:30000" "${GHS_PREFIX}1_eyJ-:30000"
)
for shape in "${SLOW_SHAPES[@]}"; do
  unit="${shape%:*}" count="${shape##*:}"
  printf -v content '%*s' "$count" ''
  printf '%s' "${content// /$unit}" >"$TEST_TMPDIR/slow.txt"
  rc=0
  # shellcheck disable=SC2016  # expanded by the inner bash
  LC_ALL=C.UTF-8 timeout 10 bash -c 'source "$1"; secrets::scan_text "$(<"$2")" >/dev/null || :' \
    _ "$HOOK_DIR/../lib/secret-detection/secret-patterns.sh" "$TEST_TMPDIR/slow.txt" || rc=$?
  assert_exit "scan of '${unit}' x${count} finishes" 0 "$rc"
done

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "SLACK='$SLACK_TOKEN'")" 2>&1)
RC=$?
assert_exit "Slack Bot Token → exit 2" 2 "$RC"
assert_contains "Slack → message" "$OUT" "Slack Bot Token"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "STRIPE_KEY='$STRIPE_TOKEN'")" 2>&1)
RC=$?
assert_exit "Stripe Key → exit 2" 2 "$RC"
assert_contains "Stripe → message" "$OUT" "Stripe Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "OPENAI_KEY='$OPENAI_BARE_KEY'")" 2>&1)
RC=$?
assert_exit "OpenAI bare sk- key → exit 2" 2 "$RC"
assert_contains "OpenAI bare sk- → message" "$OUT" "OpenAI API Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "$PEM_HEADER")" 2>&1)
RC=$?
assert_exit "PEM private key → exit 2" 2 "$RC"
assert_contains "PEM → message" "$OUT" "Private Key (PEM)"

OUT=$(bash "$HOOK" <<<"$(edit_json "$FIXTURE" "old to '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "Edit new_string → exit 2" 2 "$RC"

OUT=$(bash "$HOOK" <<<"$(notebook_json "$FIXTURE" "secret = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "NotebookEdit new_source → exit 2" 2 "$RC"

NUL_PAYLOAD=$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$FIXTURE" --arg tok "$AWS_TOKEN" \
  '{tool_name:"Write",tool_input:{file_path:$fp,content:("harmless first line" + ([0] | implode) + "config = " + $tok)}}')
OUT=$(bash "$HOOK" <<<"$NUL_PAYLOAD" 2>&1)
RC=$?
assert_exit "secret AFTER a NUL byte in content → exit 2" 2 "$RC"
assert_contains "secret after NUL → NUL refusal message" "$OUT" "NUL byte"

SCOPE_REPO="$TEST_TMPDIR/scoperepo"
mkdir -p "$SCOPE_REPO"
git -C "$SCOPE_REPO" init -q

OUT=$(CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "in-project secret with PROJECT_DIR set → exit 2" 2 "$RC"
assert_contains "in-project secret → message" "$OUT" "AWS Access Key"

OUT=$(CLAUDE_PROJECT_DIR="$SCOPE_REPO/" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "trailing-slash PROJECT_DIR still scans in-project file → exit 2" 2 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="${SCOPE_REPO//\//\\}" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "backslash-spelled repo root still scans in-project file → exit 2" 2 "$RC"

nb_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg np "$1" --arg s "$2" --arg m "${3:-}" --arg fp "${4:-}" \
    '{tool_name:"NotebookEdit",tool_input:({notebook_path:$np,new_source:$s}
      + (if $m == "" then {} else {edit_mode:$m} end)
      + (if $fp == "" then {} else {file_path:$fp} end))}'
}
GUARD_UNDER_TEST="$HOOK"
NB_ALSO=(--also "$HOOK_DIR/hardcoded-path-check.sh" --also "$HOOK_DIR/block-windows-drive-tmp.sh")
nb_both() {
  local label="$1" expected="$2" needle="$3" payload="$4" via
  shift 4
  for via in direct dispatched; do
    expect "$label ($via)" "$expected" --via "$via" --merge-stderr --payload "$payload" "${NB_ALSO[@]}" -- "$@"
    [[ -z "$needle" ]] || assert_contains "$label ($via) names '$needle'" "$GUARD_OUT" "$needle"
  done
}
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then NB_BASE="C:/spd-nb-root"; else NB_BASE="/spd-nb-root"; fi
NB_FILE="$NB_BASE/nb/x.ipynb"

for NB_VIA in direct dispatched; do
  guard_invoke --via "$NB_VIA" --merge-stderr --payload "$(nb_json "$NB_FILE" "secret = '$AWS_TOKEN'")" "${NB_ALSO[@]}"
  assert_exit "NotebookEdit real shape, no root ($NB_VIA) → exit 2" 2 "$GUARD_RC"
  assert_contains "NotebookEdit real shape ($NB_VIA) → names the pattern" "$GUARD_OUT" "AWS Access Key"
  assert_contains "NotebookEdit real shape ($NB_VIA) → names the notebook path" "$GUARD_OUT" "$NB_FILE"
done
nb_both "NotebookEdit edit_mode insert with a secret → exit 2" 2 "GitHub PAT" \
  "$(nb_json "$NB_FILE" "token = '$GH_PAT'" insert)"
nb_both "NotebookEdit clean new_source → exit 0" 0 "" "$(nb_json "$NB_FILE" "print('hello')")"
nb_both "NotebookEdit edit_mode delete, empty new_source → exit 0" 0 "" "$(nb_json "$NB_FILE" "" delete)"
nb_both "NotebookEdit to an allowlisted path → exit 0" 0 "" \
  "$(nb_json "$NB_BASE/tests/fixtures/x.ipynb" "secret = '$AWS_TOKEN'")"

NB_REPO="$TEST_TMPDIR/nbrepo"
mkdir -p "$NB_REPO"
git -C "$NB_REPO" init -q
[[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]] && NB_REPO=$(cygpath -l -m "$NB_REPO")
nb_both "NotebookEdit in a honored root → exit 2" 2 "AWS Access Key" \
  "$(nb_json "$NB_REPO/nb/x.ipynb" "secret = '$AWS_TOKEN'")" CLAUDE_PROJECT_DIR="$NB_REPO"
nb_both "NotebookEdit outside a honored root → exit 0" 0 "" \
  "$(nb_json "$NB_FILE" "secret = '$AWS_TOKEN'")" CLAUDE_PROJECT_DIR="$NB_REPO"
nb_both "NotebookEdit in-root notebook_path, out-of-root file_path → exit 2" 2 "AWS Access Key" \
  "$(nb_json "$NB_REPO/nb/x.ipynb" "secret = '$AWS_TOKEN'" "" "$NB_FILE")" CLAUDE_PROJECT_DIR="$NB_REPO"
nb_both "NotebookEdit out-of-root notebook_path, in-root file_path → exit 0" 0 "" \
  "$(nb_json "$NB_FILE" "secret = '$AWS_TOKEN'" "" "$NB_REPO/nb/x.ipynb")" CLAUDE_PROJECT_DIR="$NB_REPO"

NB_NUL=$(MSYS_NO_PATHCONV=1 jq -nc --arg np "$NB_FILE" --arg tok "$AWS_TOKEN" \
  '{tool_name:"NotebookEdit",tool_input:{notebook_path:($np + ([0] | implode) + ".ipynb"),new_source:("x = " + $tok)}}')
nb_both "NotebookEdit NUL inside notebook_path → exit 2" 2 "NUL byte" "$NB_NUL"

OUTSIDE_FILE="$TEST_TMPDIR/elsewhere/src/config.env"
NONREPO="$TEST_TMPDIR/nonrepo"
mkdir -p "$NONREPO"
OUT=$(CLAUDE_PROJECT_DIR="$NONREPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "non-repo root: outside write still scanned → exit 2" 2 "$RC"
assert_contains "non-repo root: outside write names the pattern" "$OUT" "AWS Access Key"

HOME_REPO="$TEST_TMPDIR/homerepo"
mkdir -p "$HOME_REPO/user"
git -C "$HOME_REPO" init -q
OUT=$(env HOME="$HOME_REPO" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "root is a repo AND home: outside write scanned → exit 2" 2 "$RC"
OUT=$(env HOME="$HOME_REPO/" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "root is home with a trailing slash on HOME → exit 2" 2 "$RC"
OUT=$(env HOME="$HOME_REPO/user" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "root is a repo that is an ancestor of home → exit 2" 2 "$RC"
OUT=$(env -u HOME USERPROFILE="$HOME_REPO" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "HOME unset, USERPROFILE is the repo root → exit 2" 2 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "real repo root: outside write → exit 0" 0 "$RC"
assert_silent "real repo root: outside write → no stderr" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="${SCOPE_REPO//\//\\}" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "backslash-spelled real repo root: outside write → exit 0" 0 "$RC"
assert_silent "backslash-spelled real repo root: outside write → no stderr" "$OUT"

H="$HOME_REPO"
mkdir -p "$H/~"
for SPELLED in "$H/." "${H%/*}//${H##*/}" "$H/../${H##*/}" "$H/user/.." "$H/~/.."; do
  OUT=$(env HOME="$H" CLAUDE_PROJECT_DIR="$SPELLED" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "unnormalized root '$SPELLED': outside write scanned → exit 2" 2 "$RC"
done

SPELL_HOME="$TEST_TMPDIR/spell-home"
mkdir -p "$SPELL_HOME" "$SCOPE_REPO/src" "${SCOPE_REPO%/*}/x"
for SPELLED in "${SCOPE_REPO%/*}/./${SCOPE_REPO##*/}" "$SCOPE_REPO/src/.." \
  "$SCOPE_REPO/." "${SCOPE_REPO%/*}/x/../${SCOPE_REPO##*/}"; do
  OUT=$(env HOME="$SPELL_HOME" USERPROFILE="" CLAUDE_PROJECT_DIR="$SPELLED" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "dot-spelled root '$SPELLED', HOME elsewhere: in-project write scanned → exit 2" 2 "$RC"
done

TILDE_REPO="$TEST_TMPDIR/tilde~repo"
mkdir -p "$TILDE_REPO"
git -C "$TILDE_REPO" init -q
OUT=$(CLAUDE_PROJECT_DIR="$TILDE_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "repo root containing '~': outside write scanned → exit 2" 2 "$RC"

for SPELLED in "$SCOPE_REPO//" "${SCOPE_REPO//\//\\}\\\\"; do
  OUT=$(CLAUDE_PROJECT_DIR="$SPELLED" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "root '$SPELLED': in-project write scanned → exit 2" 2 "$RC"
  OUT=$(CLAUDE_PROJECT_DIR="$SPELLED" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "root '$SPELLED': outside write scanned → exit 2" 2 "$RC"
done

OUT=$(cd "$SCOPE_REPO" && CLAUDE_PROJECT_DIR=. bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "relative root '.' inside a repo: outside write scanned → exit 2" 2 "$RC"

# A directory link to home names home under another path. Linux CI makes a
# symlink; a Windows host makes a junction (a plain `ln -s` there copies).
make_dir_link() { # <target> <link> -> 0 when <link> is a real directory link
  if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    command -v cmd >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1 || return 1
    MSYS_NO_PATHCONV=1 cmd /c mklink /J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null 2>&1
  else
    ln -s "$1" "$2" 2>/dev/null
  fi
  [[ -L "$2" ]]
}
if make_dir_link "$HOME_REPO" "$TEST_TMPDIR/home-link"; then
  OUT=$(env HOME="$HOME_REPO" CLAUDE_PROJECT_DIR="$TEST_TMPDIR/home-link" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "root is a link to home: outside write scanned → exit 2" 2 "$RC"
else
  echo "skip: root is a link to home (no directory link could be made on this host)"
fi

ELSEWHERE_HOME="$TEST_TMPDIR/elsewhere-home"
mkdir -p "$ELSEWHERE_HOME"
OUT=$(env HOME="$ELSEWHERE_HOME" USERPROFILE="$HOME_REPO" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "root is USERPROFILE while HOME is elsewhere: outside write scanned → exit 2" 2 "$RC"
OUT=$(env -u HOME USERPROFILE="$ELSEWHERE_HOME" CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "HOME unset, USERPROFILE elsewhere: real repo root keeps scope → exit 0" 0 "$RC"

OUT=$(cd "$TEST_TMPDIR" && env HOME="" USERPROFILE="" CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "empty HOME and USERPROFILE: outside write scanned → exit 2" 2 "$RC"

FAKE_FILE="$TEST_TMPDIR/fake-gitfile"
mkdir -p "$FAKE_FILE"
: >"$FAKE_FILE/.git"
OUT=$(CLAUDE_PROJECT_DIR="$FAKE_FILE" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "empty .git file: outside write scanned → exit 2" 2 "$RC"
FAKE_DIR="$TEST_TMPDIR/fake-gitdir"
mkdir -p "$FAKE_DIR/.git"
OUT=$(CLAUDE_PROJECT_DIR="$FAKE_DIR" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "empty .git directory (no HEAD): outside write scanned → exit 2" 2 "$RC"
WT_MAIN="$TEST_TMPDIR/wt-main"
WT_LINK="$TEST_TMPDIR/wt-link"
mkdir -p "$WT_MAIN"
git -C "$WT_MAIN" init -q
git -C "$WT_MAIN" -c user.email=t@t.test -c user.name=t commit -q --allow-empty -m seed
git -C "$WT_MAIN" worktree add -q "$WT_LINK" >/dev/null 2>&1
if [[ -f "$WT_LINK/.git" ]]; then
  OUT=$(CLAUDE_PROJECT_DIR="$WT_LINK" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "linked worktree root (.git gitdir: file): outside write → exit 0" 0 "$RC"
else
  bad "linked worktree root: git worktree add produced no .git file"
fi

if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]] && command -v cygpath >/dev/null 2>&1; then
  HOME_REPO_M=$(git -C "$HOME_REPO" rev-parse --show-toplevel)
  HOME_REPO_U="/${HOME_REPO_M:0:1}${HOME_REPO_M:2}"
  OUT=$(env HOME="$SCOPE_REPO" CLAUDE_PROJECT_DIR="$HOME_REPO_M" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "msys: the C:/ root alone is honored when HOME is elsewhere → exit 0" 0 "$RC"
  OUT=$(env HOME="${HOME_REPO_U,,}" CLAUDE_PROJECT_DIR="$HOME_REPO_M" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "msys: C:/ root vs lower-cased /c/ HOME is home → exit 2" 2 "$RC"
  OUT=$(env HOME="${HOME_REPO_U^^}/" CLAUDE_PROJECT_DIR="$HOME_REPO_M/" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "msys: upper-cased /C/ HOME and trailing slashes still match → exit 2" 2 "$RC"
fi

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'just some normal code here')" 2>&1)
RC=$?
assert_exit "clean content → exit 0" 0 "$RC"
assert_silent "clean content → no stderr" "$OUT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'api_key=mySecretValue123')" 2>&1)
RC=$?
assert_exit "low-confidence generic pattern → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'token = ghs_job; lane = ghs_lane; sha = 3e7fef0587433cfb07332dbeabf0d79fc0baadf3')" 2>&1)
RC=$?
assert_exit "token placeholders and a commit sha → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'label = highs_and_lows_of_the_market_over_the_year; mood = laughs_out_loud_at_the_whole_long_meeting_today')" 2>&1)
RC=$?
assert_exit "a long identifier ending in ghs_ → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(other_tool_json "Read" "$FIXTURE")" 2>&1)
RC=$?
assert_exit "Read tool → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.env.example" "API_KEY='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".env.example allowlist → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/tests/fixtures/secrets.txt" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "tests/fixtures/ allowlist → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.claude/hooks/foo.sh" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".claude/hooks/ self-exemption → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/settings.local.json" "{\"k\":\"$AWS_TOKEN\"}")" 2>&1)
RC=$?
assert_exit "settings.local.json allowlist → exit 0" 0 "$RC"

OUT=$(run_hook_windows "$(write_json "C:/repo/CLAUDE.local.md" "token='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "CLAUDE.local.md allowlist (case-sensitive) → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "/other-repo/fixtures/bad/leak.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "file outside project root → exit 0" 0 "$RC"
assert_silent "outside project root → no stderr" "$OUT"

OUT=$(CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED=false bash "$HOOK" <<<"$(write_json "$FIXTURE" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "kill switch off → exit 0" 0 "$RC"
assert_silent "kill switch off → no stderr" "$OUT"

# --- jq fail-open visibility (finding P4) -----------------------------------
# Runtime jq-removal is not portably simulable — an isolated bin dir without jq
# cannot host bash + coreutils (their DLLs / PATH) across Git Bash and Linux.
# Assert the fail-open guard is present in the hook source via the shared
# hook::require jq helper (docs/contracts/hook-observability/) — it composes
# the once per session and agent notice_once gate with the dual-channel
# (systemMessage + additionalContext) visibility notice; hook::require's own behavior is covered
# by lib/hook-utils.test.sh, not re-asserted here.
HOOK_SRC=$(cat "$HOOK")
assert_contains "jq guard: uses hook::require jq" "$HOOK_SRC" 'hook::require jq'

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/src/node_modules/pkg/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "node_modules real segment → exit 0 (exempt)" 0 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/evil_node_modules/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "evil_node_modules substring → exit 2 (scanned)" 2 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.venv/lib/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".venv real segment → exit 0 (exempt)" 0 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.venv-backup/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".venv-backup impostor → exit 2 (scanned)" 2 "$RC"

TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$SCOPE_REPO" \
  bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "secret-pattern-detection"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: violation label" "$(jq -r '.data.violations[]' "$TEL")" "AWS Access Key"
  assert_absent "telemetry: no raw token in envelope" "$(cat "$TEL")" "$AWS_TOKEN"
else
  bad "telemetry: no envelope written on block"
fi

H="ho""me"
ABS_FILE="/${H}/alice/secretproj/config.env"
TELR="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKR="$(make_sink "cat >\"$TELR\"")"
env HOOK_TELEMETRY_SINK="$SINKR" bash "$HOOK" \
  <<<"$(write_json "$ABS_FILE" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TELR"; then
  df=$(jq -r '.data.file' "$TELR")
  assert_contains "redaction: data.file is the basename" "$df" "config.env"
  assert_absent "redaction: data.file has no path separator" "$df" "/"
  assert_absent "redaction: envelope drops the username dir" "$(cat "$TELR")" "alice"
else
  bad "redaction: no envelope written"
fi

assert_contains "path helper: uses hook::repo_relative_path_to" "$HOOK_SRC" 'hook::repo_relative_path_to'
assert_absent "path helper: no hand-rolled prefix strip" "$HOOK_SRC" '_fwd#'

PATHREPO="$TEST_TMPDIR/pathrepo"
mkdir -p "$PATHREPO/src"
git -C "$PATHREPO" init -q
PATHREPO_TL="$(git -C "$PATHREPO" rev-parse --show-toplevel)"

telemetry_file() {
  local tel sink
  tel="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
  sink="$(make_sink "cat >\"$tel\"")"
  env HOOK_TELEMETRY_SINK="$sink" bash "$HOOK" \
    <<<"$(write_json "$1" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
  if wait_for_sink "$tel"; then jq -r '.data.file' "$tel"; else printf '<no-envelope>'; fi
}

UNC_HOST='srv'
# shellcheck disable=SC1003  # BS is a literal single backslash, not a quote escape
BS='\'
UNC_FILE="${BS}${BS}${UNC_HOST}${BS}share${BS}secrets.env"
df=$(telemetry_file "$UNC_FILE")
assert_eq "UNC/no-project: data.file is exactly the basename" "secrets.env" "$df"
assert_absent "UNC/no-project: data.file keeps no backslash" "$df" "$BS"
assert_absent "UNC/no-project: data.file drops the share host" "$df" "$UNC_HOST"

df=$(telemetry_file "$PATHREPO_TL/src/config.env")
assert_contains "in-repo/no-project: data.file is repo-relative" "$df" "src/config.env"
assert_absent "in-repo/no-project: data.file is not absolute" "$df" "$PATHREPO_TL"

GIT_SHIM_DIR="$TEST_TMPDIR/git-shim"
mkdir -p "$GIT_SHIM_DIR"
GIT_C_LOG="$TEST_TMPDIR/git-c-args"
REAL_GIT="$(command -v git)"
{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016  # the shim's own expansions are literal source text
  printf 'a=("$@"); for ((i = 0; i < $# - 1; i++)); do [[ "${a[i]}" == "-C" ]] && printf "%%s\\n" "${a[i + 1]}" >>"%s"; done\n' "$GIT_C_LOG"
  printf 'exec "%s" "$@"\n' "$REAL_GIT"
} >"$GIT_SHIM_DIR/git"
chmod +x "$GIT_SHIM_DIR/git"
: >"$GIT_C_LOG"
ROOT_TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
ROOT_SINK="$(make_sink "cat >\"$ROOT_TEL\"")"
env PATH="$GIT_SHIM_DIR:$PATH" HOOK_TELEMETRY_SINK="$ROOT_SINK" bash "$HOOK" \
  <<<"$(write_json "/secrets.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1
assert_exit "root-level/no-project: still blocks" 2 "$?"
if wait_for_sink "$ROOT_TEL"; then
  assert_eq "root-level/no-project: data.file is exactly the basename" \
    "secrets.env" "$(jq -r '.data.file' "$ROOT_TEL")"
else
  bad "root-level/no-project: no envelope written"
fi
assert_eq "root-level/no-project: repo root is anchored on / (dirname semantics)" \
  "/" "$(cat "$GIT_C_LOG")"

LINKREPO="$TEST_TMPDIR/linkrepo"
ln -s "$PATHREPO_TL" "$LINKREPO"
df=$(telemetry_file "$PATHREPO_TL/src/config.env")
assert_contains "symlinked repo, physical spelling: repo-relative" "$df" "src/config.env"
df=$(telemetry_file "$LINKREPO/src/config.env")
assert_contains "symlinked repo, symlink spelling: basename" "$df" "config.env"
assert_absent "symlinked repo, symlink spelling: no path separator" "$df" "/"

TELTS="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKTS="$(make_sink "cat >\"$TELTS\"")"
env HOOK_TELEMETRY_SINK="$SINKTS" CLAUDE_PROJECT_DIR="$PATHREPO_TL/" bash "$HOOK" \
  <<<"$(write_json "$PATHREPO_TL/src/config.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TELTS"; then
  assert_eq "trailing-slash project dir: data.file stays repo-relative" \
    "src/config.env" "$(jq -r '.data.file' "$TELTS")"
else
  bad "trailing-slash project dir: no envelope written"
fi

TELNR="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKNR="$(make_sink "cat >\"$TELNR\"")"
env HOOK_TELEMETRY_SINK="$SINKNR" CLAUDE_PROJECT_DIR="$NONREPO" bash "$HOOK" \
  <<<"$(write_json "$PATHREPO_TL/src/config.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TELNR"; then
  assert_eq "non-repo root: data.file is relative to the file's own checkout" \
    "src/config.env" "$(jq -r '.data.file' "$TELNR")"
else
  bad "non-repo root: no envelope written"
fi


run_bounded() {
  local rc=0
  printf '%s' "$1" | timeout 150 bash "$HOOK" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

for SZ in 65535 65536 65600 65663 65664; do
  assert_bounded_exit "boundary: clean ${SZ}-byte payload → exit 0" \
    0 "$(run_bounded "$(sized_write_json "$SZ")")"
done

for SZ in 65536 65600; do
  assert_bounded_exit "boundary: AWS key in ${SZ}-byte payload → exit 2" \
    2 "$(run_bounded "$(sized_write_json "$SZ" "$AWS_TOKEN")")"
done

BOUND_ERR=$(printf '%s' "$(sized_write_json 65600 "$AWS_TOKEN")" | timeout 150 bash "$HOOK" 2>&1 >/dev/null)
assert_contains "boundary: in-window block still reports the label" "$BOUND_ERR" "AWS Access Key"
assert_absent "boundary: no SIGPIPE noise on stderr" "$BOUND_ERR" "Broken pipe"

RC=0
printf '%s' "$(sized_write_json 0)" | timeout 30 bash "$HOOK" >/dev/null 2>&1 || RC=$?
assert_exit "boundary: empty content → exit 0" 0 "$RC"


RC=0
bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "import os")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP create_or_update_file: clean content → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'")" 2>&1)
RC=$?
assert_exit "MCP create_or_update_file: secret → exit 2" 2 "$RC"
assert_contains "MCP create_or_update_file: names the pattern" "$OUT" "GitHub PAT"
assert_contains "MCP create_or_update_file: names the repo path" "$OUT" "src/app.py"
assert_contains "MCP create_or_update_file: names the GitHub destination" "$OUT" "content bound for GitHub"

RC=0
bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "y = 2")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: all clean → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "k = '$AWS_TOKEN'" "b.py" "y = 2")" 2>&1)
RC=$?
assert_exit "MCP push_files: secret in the FIRST file → exit 2" 2 "$RC"
assert_contains "MCP push_files: first-file block names its path" "$OUT" "a.py"

OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "k = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "MCP push_files: secret in the LAST file → exit 2" 2 "$RC"
assert_contains "MCP push_files: last-file block names its path" "$OUT" "b.py"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__push_files","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m","files":[]}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: empty files array → exit 0" 0 "$RC"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__push_files","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m"}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: absent files array → exit 0" 0 "$RC"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__delete_file","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m","path":"src/app.py"}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP delete_file: no content to scan → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'" | scoped create_or_update_file)" 2>&1)
RC=$?
assert_exit "MCP scoped create_or_update_file: secret → exit 2" 2 "$RC"
assert_contains "MCP scoped create_or_update_file: names the repo path" "$OUT" "src/app.py"
OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "k = '$AWS_TOKEN'" | scoped push_files)" 2>&1)
RC=$?
assert_exit "MCP scoped push_files: secret in the LAST file → exit 2" 2 "$RC"
assert_contains "MCP scoped push_files: names the last file" "$OUT" "b.py"
RC=0
bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" | scoped push_files)" >/dev/null 2>&1 || RC=$?
assert_exit "MCP scoped push_files: clean → exit 0" 0 "$RC"

MATCHER=$(jq -r '.hooks.PreToolUse[] | select(.hooks[] | (.command + " " + ((.args // []) | map(tostring) | join(" "))) | contains("secret-pattern-detection.sh")) | .matcher | select(test("github"))' "$HOOK_DIR/hooks.json")
for name in mcp__github__push_files mcp__github__create_or_update_file \
  mcp__plugin_github_github__push_files mcp__plugin_my-plugin_github__create_or_update_file; do
  RC=0
  jq -en --arg m "$MATCHER" --arg n "$name" '$n | test($m)' >/dev/null || RC=$?
  assert_exit "hooks.json GitHub row matches $name" 0 "$RC"
done
for name in mcp__github__delete_file mcp__plugin_github_github__delete_file mcp__gitlab__push_files; do
  RC=0
  jq -en --arg m "$MATCHER" --arg n "$name" '$n | test($m)' >/dev/null || RC=$?
  assert_exit "hooks.json GitHub row does not match $name" 1 "$RC"
done

RC=0
bash "$HOOK" <<<"$(mcp_single_json "docs/.env.example" "token = '$GH_PAT'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: allowlisted .env.example is exempt" 0 "$RC"
RC=0
bash "$HOOK" <<<"$(mcp_push_json "tests/fixtures/keys.py" "k = '$AWS_TOKEN'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: allowlisted test fixture is exempt" 0 "$RC"
RC=0
bash "$HOOK" <<<"$(mcp_push_json "evil_node_modules/x.py" "k = '$AWS_TOKEN'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: a name-prefix sibling of an allowlisted dir still blocks" 2 "$RC"

RC=0
CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" \
  <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: a set CLAUDE_PROJECT_DIR does not skip the remote write" 2 "$RC"

RC=0
CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED=false bash "$HOOK" \
  <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: disabled guard allows the write" 0 "$RC"

D1_WIN=0
[[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]] && D1_WIN=1
if ((D1_WIN)); then
  D1_TEMP=$(cygpath -l -m "${TEMP:-${TMP:-/tmp}}")
  D1_ROOT="C:/spd-d1-nonrepo-root"
  D1_HOME="C:/spd-d1-home"
else
  D1_TEMP=/tmp
  D1_ROOT="/spd-d1-nonrepo-root"
  D1_HOME="/spd-d1-home"
fi
D1_TARGET="$D1_TEMP/spd-d1-$$/sub/f.txt"

d1_rc() {
  local root="$1" target="$2" rc=0
  shift 2
  if [[ -n "$root" ]]; then
    env "$@" CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<<"$(write_json "$target" "token = '$GH_PAT'")" >/dev/null 2>&1 || rc=$?
  else
    env "$@" bash "$HOOK" <<<"$(write_json "$target" "token = '$GH_PAT'")" >/dev/null 2>&1 || rc=$?
  fi
  printf '%s' "$rc"
}

assert_exit "D1 non-temp non-git root, temp target → exit 0" 0 "$(d1_rc "$D1_ROOT" "$D1_TARGET")"
assert_exit "D1 root is HOME, temp target → exit 0" 0 \
  "$(d1_rc "$D1_HOME" "$D1_TARGET" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
assert_exit "D1 root unset, temp target → exit 2" 2 "$(d1_rc "" "$D1_TARGET")"
assert_exit "D1 root under temp → exit 2" 2 "$(d1_rc "$D1_TEMP/spd-d1-$$" "$D1_TARGET")"
assert_exit "D1 root is the temp root → exit 2" 2 "$(d1_rc "$D1_TEMP" "$D1_TARGET")"

for D1_T in "$D1_TEMP/spd-d1-$$/../../spd-d1-out/f.txt" "${D1_TEMP}Evil/spd-d1/f.txt" \
  "$D1_TEMP/spd~1/f.txt" "/$D1_TARGET" "$D1_TEMP//spd-d1/f.txt" "tmp/spd-d1/f.txt" \
  "$D1_TEMP/spd-a\$b/f.txt" "$D1_TEMP/spd-a[1]/f.txt" "$D1_TEMP/spd-a\`b/f.txt" \
  "$D1_TEMP/spd a/f.txt" "$D1_TEMP/spd;a/f.txt" "$D1_TEMP/spd\"a/f.txt" "$D1_TEMP/spd'a/f.txt" \
  "$D1_TEMP/spd(a)/f.txt" "$D1_TEMP/spd#a/f.txt" "$D1_TEMP/spd&a/f.txt"; do
  assert_exit "D1 target '$D1_T' → exit 2" 2 "$(d1_rc "$D1_ROOT" "$D1_T")"
done
for D1_R in "$D1_ROOT\$x" "${D1_ROOT}*" "${D1_ROOT}~1" "spd-d1-rel-root" "/"; do
  assert_exit "D1 root '$D1_R' → exit 2" 2 "$(d1_rc "$D1_R" "$D1_TARGET")"
done

D1_LINKDIR=$(mktemp -d) || D1_LINKDIR=""
if [[ -n "$D1_LINKDIR" ]]; then
  D1_LINKBASE="$D1_LINKDIR"
  ((D1_WIN)) && D1_LINKBASE=$(cygpath -l -m "$D1_LINKDIR")
  if make_dir_link "$HOOK_DIR" "$D1_LINKDIR/ToHooks"; then
    assert_exit "D1 target through a temp link to a non-temp dir → exit 2" 2 \
      "$(d1_rc "$D1_ROOT" "$D1_LINKBASE/ToHooks/spd-d1-absent/f.txt")"
    assert_exit "D1 genuine sibling in the same temp dir → exit 0" 0 \
      "$(d1_rc "$D1_ROOT" "$D1_LINKBASE/genuine/f.txt")"
  else
    echo "SKIP: D1 temp link cases (no directory link could be made on this host)"
  fi
  : >"$D1_LINKDIR/hl-src.txt"
  : >"$D1_LINKDIR/plain.txt"
  if ln "$D1_LINKDIR/hl-src.txt" "$D1_LINKDIR/hl.txt" 2>/dev/null; then
    assert_exit "D1 hard-linked temp file → exit 2" 2 "$(d1_rc "$D1_ROOT" "$D1_LINKBASE/hl.txt")"
    assert_exit "D1 plain temp file beside it → exit 0" 0 "$(d1_rc "$D1_ROOT" "$D1_LINKBASE/plain.txt")"
  else
    echo "SKIP: D1 hard link cases (ln could not make a hard link on this host)"
  fi
  mkdir "$D1_LINKDIR/sub"
  # shellcheck disable=SC2016  # the child shell's expansions are literal source text
  D1_PROBE=$(CLAUDE_PROJECT_DIR="$D1_ROOT" bash -c 'exit() { printf "MARK|%s\n" "${_HOOK_PHYS_KEYS[*]-}"; builtin exit "$@"; }; source "$1"' _ "$HOOK" <<<"$(write_json "$D1_LINKBASE/sub/f.txt" "token = '$GH_PAT'")" 2>/dev/null)
  D1_PROBE_RC=$?
  assert_exit "D1 probe: sourced guard declines" 0 "$D1_PROBE_RC"
  D1_KEYS="${D1_PROBE#*MARK|}"
  if [[ "$D1_PROBE" == *"MARK|"* && -n "$D1_KEYS" ]]; then ok "D1 probe: resolve stage ran"; else bad "D1 probe: no cache keys ($D1_PROBE)"; fi
  assert_absent "D1 probe: the resolved target directory is not cached" "$D1_KEYS" "$D1_LINKBASE/sub"
else
  echo "SKIP: D1 temp-file cases (mktemp -d failed)"
fi

# Width on POSIX: the target's lowercased spelling must also fall under a temp
# candidate, which keeps its case, so a capitalized temp root never declines.
# Lifted seam: the spd functions run with OSTYPE forced to POSIX and the
# candidate set replaced by one test-owned directory, capitalized or not.
# shellcheck disable=SC2016  # the sed addresses are literal hook source text
D1_SEAM=$(sed -n '/^spd_win=0$/,/^spd_temp_declines "\$FILE" && exit 0$/p' "$HOOK" | sed '$d')
d1_seam_rc() {
  # shellcheck disable=SC2016  # the child shell's expansions are literal source text
  CLAUDE_PROJECT_DIR=/spd-d1-nonrepo-root bash -c 'OSTYPE=linux-gnu; source "$1/hook-utils.sh"; eval "$2"
    d1_cand="$3"
    hook::_temp_root_candidates() { _HOOK_TEMP_CANDS=("$d1_cand"); }
    spd_temp_declines "$3/spd-d1-absent/f.txt"; printf %s "$?"' _ "$HOOK_DIR" "$D1_SEAM" "$1"
}
# mktemp names carry capitals, so the seam dirs sit under a lowercase name of
# their own, removed by name in the EXIT trap. The precondition asks the seam's
# own resolver: under a forced Linux OSTYPE the library resolves with `cd -P`,
# which on Git Bash follows the /tmp mount to a capitalized Windows path, so the
# cases only run where that resolver spells each seam dir as given.
d1_seam_self() { # <dir> -> 0 when the Linux resolver spells <dir> as given; answer left in D1_SEAM_GOT
  # shellcheck disable=SC2016  # the child shell's expansions are literal source text
  D1_SEAM_GOT=$(bash -c 'OSTYPE=linux-gnu; source "$1/hook-utils.sh"; hook::physical_path_to p "$2" && printf %s "$p"' _ "$HOOK_DIR" "$1" 2>/dev/null)
  [[ "$D1_SEAM_GOT" == "$1" ]]
}
D1_SEAM_TRY="/tmp/spd-d1-seam-$$"
D1_SEAM_STEP="mkdir $D1_SEAM_TRY"
if mkdir "$D1_SEAM_TRY" 2>/dev/null && D1_SEAMDIR="$D1_SEAM_TRY" &&
  D1_SEAM_STEP="mkdir lowtemp and CapTemp under it" &&
  mkdir "$D1_SEAMDIR/lowtemp" "$D1_SEAMDIR/CapTemp" 2>/dev/null &&
  D1_SEAM_STEP="resolve $D1_SEAMDIR/lowtemp" && d1_seam_self "$D1_SEAMDIR/lowtemp" &&
  D1_SEAM_STEP="resolve $D1_SEAMDIR/CapTemp" && d1_seam_self "$D1_SEAMDIR/CapTemp"; then
  assert_eq "D1 seam: posix, lowercase temp root declines" 0 "$(d1_seam_rc "$D1_SEAMDIR/lowtemp")"
  assert_eq "D1 seam: posix, capitalized temp root scans" 1 "$(d1_seam_rc "$D1_SEAMDIR/CapTemp")"
elif [[ "${OSTYPE:-}" == linux* ]]; then
  [[ "$D1_SEAM_STEP" == resolve* ]] && D1_SEAM_STEP+=" under the library's Linux resolver gave '$D1_SEAM_GOT'"
  bad "D1 seam: precondition failed: $D1_SEAM_STEP"
else
  echo "SKIP: D1 seam width cases (under a forced Linux OSTYPE the library resolver does not spell the /tmp seam dirs as given on this host, or the seam dirs could not be made)"
fi

if ((D1_WIN)); then
  assert_exit "D1 windows: drive root '${D1_ROOT%%/*}/' → exit 2" 2 "$(d1_rc "${D1_ROOT%%/*}/" "$D1_TARGET")"
  assert_exit "D1 windows: Z:/ root, temp target, terminates → exit 0" 0 \
    "$(
      D1_RC=0
      timeout 150 env CLAUDE_PROJECT_DIR="Z:/spd-d1-root" bash "$HOOK" <<<"$(write_json "$D1_TARGET" "token = '$GH_PAT'")" >/dev/null 2>&1 || D1_RC=$?
      printf '%s' "$D1_RC"
    )"
  assert_exit "D1 windows: backslash long spelling, HOME root → exit 0" 0 \
    "$(d1_rc "$D1_HOME" "${D1_TARGET//\//\\}" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
  assert_exit "D1 windows: /c/ spelling → exit 2" 2 \
    "$(d1_rc "$D1_HOME" "/${D1_TARGET:0:1}${D1_TARGET:2}" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
  assert_exit "D1 windows: /tmp/ spelling → exit 2" 2 \
    "$(d1_rc "$D1_HOME" "/tmp/spd-d1-$$/f.txt" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
  D1_SHORT="$(cygpath -s -m "$D1_TEMP")/spd-d1-$$/sub/f.txt"
  if [[ "$D1_SHORT" != "$D1_TARGET" ]]; then
    assert_exit "D1 windows: 8.3 short spelling → exit 0" 0 \
      "$(d1_rc "$D1_HOME" "$D1_SHORT" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
    assert_exit "D1 windows: 8.3 spelling with a nonexistent name~9 component → exit 2" 2 \
      "$(d1_rc "$D1_HOME" "$(cygpath -s -m "$D1_TEMP")/spd-nope~9/f.txt" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
  else
    echo "SKIP: D1 windows 8.3 case (the temp path has no short spelling on this volume)"
  fi
else
  echo "SKIP: D1 Windows spelling cases (not a Windows Git Bash host)"
  assert_exit "D1 posix: target carrying a backslash → exit 2" 2 \
    "$(d1_rc "$D1_ROOT" "/tmp/spd-d1-$$\\x/f.txt")"
fi

D1_SHIM="$TEST_TMPDIR/d1-shim"
D1_LOG="$TEST_TMPDIR/d1-shim.log"
mkdir -p "$D1_SHIM"
for D1_BIN in realpath readlink cygpath; do
  D1_REAL=$(command -v "$D1_BIN") || continue
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" %s >>"%s"\n' "$D1_BIN" "$D1_LOG"
    printf 'exec "%s" "$@"\n' "$D1_REAL"
  } >"$D1_SHIM/$D1_BIN"
  chmod +x "$D1_SHIM/$D1_BIN"
done
: >"$D1_LOG"
d1_rc "$D1_ROOT" "$D1_ROOT/src/f.txt" PATH="$D1_SHIM:$PATH" HOOK_TELEMETRY_SINK= >/dev/null
assert_eq "D1 non-temp target spawns no resolver" "" "$(cat "$D1_LOG")"
: >"$D1_LOG"
d1_rc "$D1_ROOT" "$D1_TARGET" PATH="$D1_SHIM:$PATH" HOOK_TELEMETRY_SINK= >/dev/null
if [[ "${OSTYPE:-}" == linux* ]]; then
  "$D1_SHIM/realpath" / >/dev/null
  if [[ -s "$D1_LOG" ]]; then ok "D1 shim logs a resolver spawn"; else bad "D1 shim logged no resolver spawn"; fi
elif [[ -s "$D1_LOG" ]]; then ok "D1 temp target spawns a resolver"; else bad "D1 temp target spawned no resolver"; fi

D1_83="/tmp/spd-d1-83-$$"
d1_83_rc() {
  # shellcheck disable=SC2016  # the child shell's expansions are literal source text
  (cd "$D1_83" && PATH="${2:-$PATH}" CLAUDE_PROJECT_DIR=C:/spd-d1-root bash -c 'OSTYPE=cygwin; source "$1/hook-utils.sh"; eval "$2"
    hook::_temp_root_candidates() { _HOOK_TEMP_CANDS=("c:/longna~1"); }
    spd_temp_declines "$3"; printf %s "$?"' _ "$HOOK_DIR" "$D1_SEAM" "$1")
}
rm -rf "$D1_83"
if [[ -d /usr ]] && mkdir -p "$D1_83/c:/longname/claude" &&
  ln -s "$D1_83/c:/longname" "$D1_83/c:/longna~1" 2>/dev/null && test -L "$D1_83/c:/longna~1" &&
  ln -s /usr "$D1_83/c:/longna~1/tousr~1" 2>/dev/null; then
  assert_eq "D1 8.3 sim: short spelling under temp declines" 0 "$(d1_83_rc "c:/longna~1/claude/x/f.txt")"
  assert_eq "D1 8.3 sim: nonexistent name~9 component scans" 1 "$(d1_83_rc "c:/longna~1/nope~9/f.txt")"
  assert_eq "D1 8.3 sim: a~b component scans" 1 "$(d1_83_rc "c:/longna~1/a~b/f.txt")"
  assert_eq "D1 8.3 sim: x~ component scans" 1 "$(d1_83_rc "c:/longna~1/x~/f.txt")"
  assert_eq "D1 8.3 sim: short alias linking out of temp scans" 1 "$(d1_83_rc "c:/longna~1/tousr~1/f.txt")"
  : >"$D1_LOG"
  assert_eq "D1 8.3 sim: short spelling outside every temp candidate scans" 1 \
    "$(d1_83_rc "c:/progra~1/f.txt" "$D1_SHIM:$PATH")"
  assert_eq "D1 8.3 sim: that miss spawned no resolver" "" "$(cat "$D1_LOG")"
else
  echo "SKIP: D1 8.3 simulation (no symlink could be made on this host; no coverage here, not a pass)"
fi
rm -f "$D1_83/c:/longname/tousr~1" "$D1_83/c:/longna~1"
rm -rf "$D1_83"
if ((!D1_WIN)); then
  assert_exit "D1 posix: short-name spelling under temp still scans" 2 \
    "$(d1_rc "$D1_ROOT" "/tmp/spd~1/spd-d1-$$/f.txt")"
fi

D1_DISPATCH_RC=0
CLAUDE_PROJECT_DIR="$D1_ROOT" bash "$HOOK_DIR/run-guards.sh" secret-pattern-detection.sh hardcoded-path-check.sh block-windows-drive-tmp.sh \
  <<<"$(write_json "$D1_TARGET" "token = '$GH_PAT'")" >/dev/null 2>&1 || D1_DISPATCH_RC=$?
assert_exit "D1 dispatcher: non-temp root, temp target → exit 0" 0 "$D1_DISPATCH_RC"
D1_DISPATCH_RC=0
bash "$HOOK_DIR/run-guards.sh" secret-pattern-detection.sh hardcoded-path-check.sh block-windows-drive-tmp.sh \
  <<<"$(write_json "$D1_TARGET" "token = '$GH_PAT'")" >/dev/null 2>&1 || D1_DISPATCH_RC=$?
assert_exit "D1 dispatcher: root unset → exit 2" 2 "$D1_DISPATCH_RC"

if ((!D1_WIN)); then
  CR_DIR="$TEST_TMPDIR/custom-root"
  mkdir -p "$CR_DIR/bin"
  # shellcheck disable=SC2016 # the stub's own expressions
  printf '%s\n' '#!/bin/sh' 'echo "$*" >>"$CR_LOG"' 'for a in "$@"; do case "$a" in -*) ;; *) echo "$a" ;; esac; done' \
    >"$CR_DIR/bin/cygpath"
  chmod +x "$CR_DIR/bin/cygpath"
  cr_calls() {
    : >"$CR_DIR/log"
    # shellcheck disable=SC2016 # $1 is the child's own positional parameter
    env TMPDIR="$1" TMP="" TEMP="" CR_LOG="$CR_DIR/log" PATH="$CR_DIR/bin:$PATH" CLAUDE_PROJECT_DIR="D:/cr-root" \
      bash -c 'OSTYPE=msys; source "$1"' _ "$HOOK" <<<"$(write_json "C:/cr-out/f.txt" "token = '$GH_PAT'")" >/dev/null 2>&1
    wc -l <"$CR_DIR/log" | tr -d ' '
  }
  assert_eq "D1 target outside a default temp root spawns no cygpath" "0" "$(cr_calls /tmp)"
  [[ "$(cr_calls /usr)" -ge 1 ]] && CR_CUSTOM=yes || CR_CUSTOM=no
  assert_eq "D1 custom temp root without a tmp component asks for drive spellings" "yes" "$CR_CUSTOM"
fi

nb_both "D1 NotebookEdit: non-temp non-git root, temp target → exit 0" 0 "" \
  "$(nb_json "$D1_TARGET" "token = '$GH_PAT'")" CLAUDE_PROJECT_DIR="$D1_ROOT"
nb_both "D1 NotebookEdit: root unset, temp target → exit 2" 2 "GitHub PAT" \
  "$(nb_json "$D1_TARGET" "token = '$GH_PAT'")"

SPE="$TEST_TMPDIR/spe"
mkdir -p "$SPE/D/inner" "$SPE/D-sib" "$SPE/outside" "$SPE/home"
SPE_B="$SPE"
((D1_WIN)) && SPE_B=$(cygpath -l -m "$SPE")
SPE_D="$SPE_B/D"
SPE_AR=CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ALLOWED_ROOTS
SPE_GI=CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_SKIP_GITIGNORED

spe_rc() {
  local target="$1" rc=0 out
  shift
  out=$(cd "$SPE" && env HOME="$SPE/home" USERPROFILE= HOOK_TELEMETRY_SINK= "$@" bash "$HOOK" \
    <<<"$(write_json "$target" "token = '$GH_PAT'")" 2>&1) || rc=$?
  [[ "$rc" == 0 && -n "$out" ]] && rc="0+output"
  printf '%s' "$rc"
}

assert_exit "allowed roots unset: token under D → exit 2" 2 "$(spe_rc "$SPE_D/sub/x.md")"
assert_exit "allowed roots: token under D, directory not made yet → exit 0" 0 \
  "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_D")"
: >"$SPE/D/plain.md"
assert_exit "allowed roots: existing file in D → exit 0" 0 "$(spe_rc "$SPE_D/plain.md" "$SPE_AR=$SPE_D")"
assert_exit "allowed roots: entry with a trailing slash → exit 0" 0 \
  "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_D/")"
assert_exit "allowed roots: bad entries ahead of D leave the list in force → exit 0" 0 \
  "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=spe-rel/D, ,$SPE_B/D-missing,$SPE_D")"
for SPE_T in "$SPE_B/D-sib/x.md" "$SPE_D" "$SPE_B/outside/../D/sub/x.md" "$SPE_D/../D/sub/x.md" \
  "$SPE_D/./sub/x.md" "$SPE_D//sub/x.md" "$SPE_B/outside/x.md"; do
  assert_exit "allowed roots: target '$SPE_T' → exit 2" 2 "$(spe_rc "$SPE_T" "$SPE_AR=$SPE_D")"
done
for SPE_E in " " "," "$SPE_B/outside/../D" "$SPE_D"$'\n' "/"; do
  assert_exit "allowed roots: entry '$SPE_E' grants nothing → exit 2" 2 \
    "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_E")"
done
mkdir -p "$SPE/glob[D]"
assert_exit "allowed roots: entry holding a glob bracket grants nothing → exit 2" 2 \
  "$(spe_rc "$SPE_B/glob[D]/x.md" "$SPE_AR=$SPE_B/glob[D]")"
assert_exit "allowed roots: entry that is not an existing directory grants nothing → exit 2" 2 \
  "$(spe_rc "$SPE_B/D-missing/x.md" "$SPE_AR=$SPE_B/D-missing")"
assert_exit "allowed roots: relative entry naming D from the working directory grants nothing → exit 2" 2 \
  "$(cd "$SPE" && spe_rc "$SPE_D/sub/x.md" "$SPE_AR=D")"
if ((!D1_WIN)); then
  mkdir -p "$SPE/star*"
  assert_exit "allowed roots: entry holding a glob star grants nothing → exit 2" 2 \
    "$(spe_rc "$SPE_B/star*/x.md" "$SPE_AR=$SPE_B/star*")"
  assert_exit "allowed roots: UNC-spelled entry grants nothing → exit 2" 2 \
    "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=/$SPE_D")"
else
  echo "SKIP: allowed roots glob-star and UNC-spelling cases (Windows refuses a '*' name and reads '//' as a share)"
fi
assert_exit "allowed roots: root is HOME → exit 2" 2 "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_D" HOME="$SPE/D")"
assert_exit "allowed roots: root holds HOME → exit 2" 2 \
  "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_D" HOME="$SPE/D/inner")"
assert_exit "allowed roots: root holds USERPROFILE → exit 2" 2 \
  "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_D" USERPROFILE="$SPE/D/inner")"
assert_exit "allowed roots: HOME empty → exit 2" 2 "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_D" HOME=)"
assert_exit "allowed roots: HOME relative → exit 2" 2 "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_D" HOME=spe-rel)"
assert_exit "allowed roots: HOME missing → exit 2" 2 \
  "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_D" HOME="$SPE/home-missing")"
if make_dir_link "$SPE/outside" "$SPE/D/out-link" && make_dir_link "$SPE/D" "$SPE/to-d"; then
  assert_exit "allowed roots: through a link under D to outside → exit 2" 2 \
    "$(spe_rc "$SPE_D/out-link/x.md" "$SPE_AR=$SPE_D")"
  assert_exit "allowed roots: through a link outside D that lands under D → exit 0" 0 \
    "$(spe_rc "$SPE_B/to-d/sub/x.md" "$SPE_AR=$SPE_D")"
  assert_exit "allowed roots: entry spelled through a link to D → exit 0" 0 \
    "$(spe_rc "$SPE_D/sub/x.md" "$SPE_AR=$SPE_B/to-d")"
else
  echo "SKIP: allowed roots directory-link cases (no directory link could be made on this host)"
fi
SPE_W="$TEST_TMPDIR/spe-win"
if ((!D1_WIN)); then
  mkdir -p "$SPE_W/c:/long/D" "$SPE_W/c:/long/outside" "$SPE_W/c:/long/home"
  ln -s "$SPE_W/c:/long" "$SPE_W/mnt" 2>/dev/null
fi
# shellcheck disable=SC2016  # sed and grep patterns, not expansions
SPE_SEAM=$(sed -n '/^spd_win=0$/,/^spd_temp_declines "\$FILE" && exit 0$/p;/^spd_et=""$/,/^spd_opt_roots=/p' "$HOOK" |
  grep -v '^spd_temp_declines "\$FILE" && exit 0$\|^spd_opt_roots=')
spe_win_rc() {
  # shellcheck disable=SC2016  # the child shell's expansions are literal source text
  (cd "$SPE_W" && HOME="$SPE_W/c:/long/home" USERPROFILE='' bash -c 'OSTYPE=msys; source "$1/hook-utils.sh"; eval "$2"
    M="$PWD/mnt"
    hook::_physical_prime() { :; }
    hook::physical_path_to() {
      case "$2" in
      c:/long/to-d) printf -v "$1" %s "$M/D" ;;
      c:/long/D/out-link) printf -v "$1" %s "$M/outside" ;;
      c:/long/broken) return 1 ;;
      *) printf -v "$1" %s "$2" ;;
      esac
    }
    cygpath() {
      local p="${!#}"
      [[ "$p" == "$M"/* ]] || { printf "%s\n" "$p"; return 0; }
      if [[ -e "c:/long${p#"$M"}" ]]; then printf "%s\n" "c:/long${p#"$M"}"; else printf "%s\n" "c:/runner~1${p#"$M"}"; fi
    }
    spd_opt_roots=c:/long/D
    spd_exempt_target "$3" || { printf %s target-refused; exit; }
    spd_under_allowed_root; printf %s "$?"' _ "$HOOK_DIR" "$SPE_SEAM" "$1")
}
if ((!D1_WIN)) && [[ -L "$SPE_W/mnt" ]] && ln -s "$SPE_W/mnt/D" "$SPE_W/c:/long/to-d" 2>/dev/null &&
  ln -s "$SPE_W/mnt/outside" "$SPE_W/c:/long/D/out-link" 2>/dev/null && mkdir -p "$SPE_W/c:/long/broken"; then
  assert_eq "allowed roots win sim: junction outside D into D, mount-spelled answer → granted" 0 \
    "$(spe_win_rc c:/long/to-d/sub/x.md)"
  assert_eq "allowed roots win sim: junction under D to outside → not granted" 1 \
    "$(spe_win_rc c:/long/D/out-link/sub/x.md)"
  assert_eq "allowed roots win sim: unresolvable ancestor → not granted" 1 \
    "$(spe_win_rc c:/long/broken/x.md)"
else
  echo "SKIP: allowed roots Windows mount-spelling simulation (a Windows host, or no symlink could be made)"
fi
: >"$SPE/outside/target.md"
if ln -s "$SPE/outside/target.md" "$SPE/D/file-link.md" 2>/dev/null && [[ -L "$SPE/D/file-link.md" ]]; then
  assert_exit "allowed roots: a file symlink under D to outside → exit 2" 2 \
    "$(spe_rc "$SPE_D/file-link.md" "$SPE_AR=$SPE_D")"
else
  echo "SKIP: allowed roots file-symlink case (no symlink could be made on this host)"
fi
: >"$SPE/outside/hl-src.md"
if ln "$SPE/outside/hl-src.md" "$SPE/D/hl.md" 2>/dev/null; then
  assert_exit "allowed roots: a hard link under D → exit 2" 2 "$(spe_rc "$SPE_D/hl.md" "$SPE_AR=$SPE_D")"
else
  echo "SKIP: allowed roots hard-link case (ln could not make a hard link on this host)"
fi
nb_both "allowed roots: NotebookEdit under D → exit 0" 0 "" \
  "$(nb_json "$SPE_D/nb/x.ipynb" "token = '$GH_PAT'")" HOME="$SPE/home" USERPROFILE= "$SPE_AR=$SPE_D"
SPE_REPO="$SPE/repo"
mkdir -p "$SPE_REPO/notes"
git -C "$SPE_REPO" init -q
SPE_REPO_B="$SPE_B/repo"
assert_exit "allowed roots, repo-rooted: token under the root's notes → exit 0" 0 \
  "$(spe_rc "$SPE_REPO_B/notes/x.md" CLAUDE_PROJECT_DIR="$SPE_REPO_B" "$SPE_AR=$SPE_REPO_B/notes")"
assert_exit "allowed roots, repo-rooted: token elsewhere in the repo → exit 2" 2 \
  "$(spe_rc "$SPE_REPO_B/src/x.md" CLAUDE_PROJECT_DIR="$SPE_REPO_B" "$SPE_AR=$SPE_REPO_B/notes")"
mkdir -p "$SPE/home/.claude/references"
assert_exit "home-rooted, no option: token in a notes dir under home → exit 2" 2 \
  "$(spe_rc "$SPE_B/home/.claude/references/x.md" CLAUDE_PROJECT_DIR="$SPE_B/home")"
assert_exit "allowed roots, home-rooted: token in a listed notes dir under home → exit 0" 0 \
  "$(spe_rc "$SPE_B/home/.claude/references/x.md" CLAUDE_PROJECT_DIR="$SPE_B/home" \
    "$SPE_AR=$SPE_B/home/.claude/references")"
SPE_RC=0
env HOME="$SPE/home" USERPROFILE= "$SPE_AR=$SPE_D" bash "$HOOK_DIR/run-guards.sh" secret-pattern-detection.sh \
  hardcoded-path-check.sh block-windows-drive-tmp.sh <<<"$(write_json "$SPE_D/sub/x.md" "token = '$GH_PAT'")" \
  >/dev/null 2>&1 || SPE_RC=$?
assert_exit "allowed roots: dispatcher, token under D → exit 0" 0 "$SPE_RC"

SPE_G="$SPE/grepo"
mkdir -p "$SPE_G/.work" "$SPE_G/src"
git -C "$SPE_G" init -q
printf '.work/\n' >"$SPE_G/.gitignore"
printf 'x\n' >"$SPE_G/README.md"
printf 'x\n' >"$SPE_G/.work/tracked.md"
git -C "$SPE_G" add .gitignore README.md
git -C "$SPE_G" add -f .work/tracked.md
SPE_GB="$SPE_B/grepo"
assert_exit "skip gitignored unset: token in an ignored file → exit 2" 2 "$(spe_rc "$SPE_GB/.work/x.md")"
assert_exit "skip gitignored: token in an ignored file → exit 0" 0 "$(spe_rc "$SPE_GB/.work/x.md" "$SPE_GI=true")"
assert_exit "skip gitignored: ignored, directory not made yet → exit 0" 0 \
  "$(spe_rc "$SPE_GB/.work/new/deeper/x.md" "$SPE_GI=true")"
for SPE_T in "$SPE_GB/src/x.md" "$SPE_GB/README.md" "$SPE_GB/.work/tracked.md" "$SPE_B/outside/x.md" \
  "$SPE_GB/src/../.work/x.md"; do
  assert_exit "skip gitignored: target '$SPE_T' → exit 2" 2 "$(spe_rc "$SPE_T" "$SPE_GI=true")"
done
assert_exit "skip gitignored: a value other than true → exit 2" 2 "$(spe_rc "$SPE_GB/.work/x.md" "$SPE_GI=TRUE")"
if ln -s "$SPE_G/README.md" "$SPE_G/.work/link.md" 2>/dev/null && [[ -L "$SPE_G/.work/link.md" ]]; then
  assert_exit "skip gitignored: an ignored symlink to a tracked file → exit 2" 2 \
    "$(spe_rc "$SPE_GB/.work/link.md" "$SPE_GI=true")"
else
  echo "SKIP: skip gitignored symlink case (no symlink could be made on this host)"
fi
: >"$SPE_G/src/real.md"
if ln "$SPE_G/src/real.md" "$SPE_G/.work/hl.md" 2>/dev/null; then
  assert_exit "skip gitignored: an ignored hard link to a tracked-tree file → exit 2" 2 \
    "$(spe_rc "$SPE_GB/.work/hl.md" "$SPE_GI=true")"
else
  echo "SKIP: skip gitignored hard-link case (ln could not make a hard link on this host)"
fi
assert_exit "skip gitignored, repo-rooted: ignored file → exit 0" 0 \
  "$(spe_rc "$SPE_GB/.work/x.md" CLAUDE_PROJECT_DIR="$SPE_GB" "$SPE_GI=true")"
assert_exit "skip gitignored, repo-rooted: not ignored → exit 2" 2 \
  "$(spe_rc "$SPE_GB/src/x.md" CLAUDE_PROJECT_DIR="$SPE_GB" "$SPE_GI=true")"
assert_exit "skip gitignored, home-rooted: ignored file → exit 0" 0 \
  "$(spe_rc "$SPE_GB/.work/x.md" HOME="$SPE_G" CLAUDE_PROJECT_DIR="$SPE_GB" "$SPE_GI=true")"
assert_exit "skip gitignored, home-rooted: not ignored → exit 2" 2 \
  "$(spe_rc "$SPE_GB/src/x.md" HOME="$SPE_G" CLAUDE_PROJECT_DIR="$SPE_GB" "$SPE_GI=true")"
nb_both "skip gitignored: NotebookEdit to an ignored notebook → exit 0" 0 "" \
  "$(nb_json "$SPE_GB/.work/x.ipynb" "token = '$GH_PAT'")" "$SPE_GI=true"
printf '#!/bin/sh\ntouch "%s"\n' "$SPE/fsm-ran" >"$SPE/fsm.sh"
chmod +x "$SPE/fsm.sh"
git -C "$SPE_G" config core.fsmonitor "$SPE/fsm.sh"
assert_exit "skip gitignored, planted core.fsmonitor: ignored file → exit 0" 0 \
  "$(spe_rc "$SPE_GB/.work/x.md" "$SPE_GI=true")"
assert_file_absent "skip gitignored: a planted core.fsmonitor never runs" "$SPE/fsm-ran"
git -C "$SPE_G" check-ignore -q -- .work/x.md >/dev/null 2>&1
if [[ -e "$SPE/fsm-ran" ]]; then ok "fixture: plain git check-ignore runs the planted fsmonitor"; else bad "fixture: the planted fsmonitor never fires, so the check above proves nothing"; fi
git -C "$SPE_G" config --unset core.fsmonitor

for SPE_P in "$SPE_D/x.md" ".work/x.md" "notes/x.md"; do
  SPE_RC=0
  env HOME="$SPE/home" USERPROFILE= "$SPE_AR=$SPE_D,$SPE_B/repo/notes" "$SPE_GI=true" bash "$HOOK" \
    <<<"$(mcp_single_json "$SPE_P" "token = '$GH_PAT'")" >/dev/null 2>&1 || SPE_RC=$?
  assert_exit "MCP create_or_update_file '$SPE_P' with both options set → exit 2" 2 "$SPE_RC"
  SPE_RC=0
  env HOME="$SPE/home" USERPROFILE= "$SPE_AR=$SPE_D,$SPE_B/repo/notes" "$SPE_GI=true" bash "$HOOK" \
    <<<"$(mcp_push_json "$SPE_P" "k = '$AWS_TOKEN'")" >/dev/null 2>&1 || SPE_RC=$?
  assert_exit "MCP push_files '$SPE_P' with both options set → exit 2" 2 "$SPE_RC"
done

SPE_SHIM="$TEST_TMPDIR/spe-shim"
SPE_LOG="$TEST_TMPDIR/spe-shim.log"
mkdir -p "$SPE_SHIM"
for SPE_BIN in realpath readlink cygpath git stat; do
  SPE_REAL=$(command -v "$SPE_BIN") || continue
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" %s >>"%s"\n' "$SPE_BIN" "$SPE_LOG"
    printf 'exec "%s" "$@"\n' "$SPE_REAL"
  } >"$SPE_SHIM/$SPE_BIN"
  chmod +x "$SPE_SHIM/$SPE_BIN"
done
SPE_NT="$HOOK"
((D1_WIN)) && SPE_NT=$(cygpath -l -m "$HOOK")
: >"$SPE_LOG"
assert_exit "options unset: shimmed blocked Write → exit 2" 2 "$(spe_rc "$SPE_NT" PATH="$SPE_SHIM:$PATH")"
assert_eq "options unset: a blocked Write spawns no resolver, git or stat" "" "$(cat "$SPE_LOG")"
: >"$SPE_LOG"
assert_exit "skip gitignored set: shimmed Write to a tracked file → exit 2" 2 \
  "$(spe_rc "$SPE_NT" PATH="$SPE_SHIM:$PATH" "$SPE_GI=true")"
assert_contains "skip gitignored set: the shimmed Write ran git" "$(cat "$SPE_LOG")" "git"

report
