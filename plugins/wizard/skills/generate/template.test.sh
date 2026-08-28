#!/usr/bin/env bash
# Behavioral tests for template.sh, the wizard that /wizard:generate stamps out
# for a human to run.
#
# Self-contained: no external test lib, fixtures built inline in a mktemp dir,
# nothing outside that dir is written. The assertion primitives are duplicated
# per plugin on purpose, see docs/conventions/shell-test-helpers/README.md.
#
# HOW THE TEMPLATE IS EXERCISED. template.sh is a runnable wizard, not a library:
# sourcing it whole would execute its example stage and block on prompts, and it
# refuses to start at all without a controlling terminal. So each case extracts
# the LIBRARY half, everything above the STAGES marker, into a temp file and
# rewrites its single `exec 3</dev/tty` to read a fixture file instead. That one
# rewrite is the entire seam: every function under test then runs verbatim,
# prompts included. Case group 1 pins that the shipped file still carries exactly
# one `exec 3</dev/tty` and one STAGES marker, so the seam cannot drift into
# exercising a path the shipped file no longer takes, and group 2 proves the
# fail-closed guard itself on the unmodified file.
#
# shellcheck disable=SC2016  # single-quoted `$` here is literal by design: the sed replacement, the case-script prelude and the invalid-key fixtures are all bytes handed to another shell, never expansions in this one
set -uo pipefail

# Fixture git isolation. An inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# send the gitignore-warning fixture's `git init` and `git config` into the
# CALLER's repository instead of the throwaway one.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/template.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
SKIPPED_N=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present in: $2" ;;
  *) pass "$1" ;;
  esac
}
# skip_case <reason>. Skip one optional case without exiting. Named to match the
# house helper so scripts/check-discriminating-test-skips.sh can see the branch.
# Only ever used where another case already carries the discriminating proof.
skip_case() {
  SKIPPED_N=$((SKIPPED_N + 1))
  printf 'SKIP: %s\n' "$1" >&2
}

if [[ ! -f "$TEMPLATE" ]]; then
  printf 'FAIL: template.sh not found at %s\n' "$TEMPLATE" >&2
  exit 1
fi

# --- The library extraction and its fd-3 seam -------------------------------

LIB="$TEST_TMPDIR/wizard-lib.sh"
awk '/^# STAGES/ { exit } { print }' "$TEMPLATE" |
  sed 's|exec 3</dev/tty|exec 3<"$WIZARD_TEST_TTY"|' >"$LIB"

STUB_BIN="$TEST_TMPDIR/bin"
mkdir -p "$STUB_BIN"
export STUB_BIN

# gh stub. Records every invocation's argv and, for a write, its stdin, so a case
# can prove a secret value travelled over stdin and never over the command line.
cat >"$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_CAPTURE/argv"
case "${1:-}" in
auth)
  exit "${GH_STUB_AUTH_RC:-0}"
  ;;
repo)
  if [[ "${GH_STUB_REPO_RC:-0}" -ne 0 ]]; then
    printf 'stub: no repo here\n' >&2
    exit "${GH_STUB_REPO_RC}"
  fi
  printf '%s\n' "${GH_STUB_REPO:-acme/widgets}"
  ;;
secret | variable)
  cat >>"$GH_CAPTURE/stdin"
  if [[ "${GH_STUB_SET_RC:-0}" -ne 0 ]]; then
    printf 'stub: gh %s set refused\n' "$1" >&2
    exit "${GH_STUB_SET_RC}"
  fi
  ;;
*)
  exit 127
  ;;
esac
STUB
chmod +x "$STUB_BIN/gh"

# Browser-opener stub. open_url tries wslview first, so stubbing that name makes
# the dispatch deterministic on any host, and the capture file records exactly
# what was handed to it (nothing, for a refused URL).
cat >"$STUB_BIN/wslview" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$OPEN_CAPTURE"
STUB
chmod +x "$STUB_BIN/wslview"

# case_build [strict]. Read a case body from stdin, prepend the library, and
# print the path of the runnable case script. `strict` keeps the library's
# `set -e` in force; the default relaxes it so a case can inspect a return code.
case_build() {
  local mode="${1:-relaxed}" script
  script="$(mktemp "$TEST_TMPDIR/case.XXXXXX")"
  {
    printf 'source %q\n' "$LIB"
    if [[ "$mode" != strict ]]; then printf 'set +e\n'; fi
    cat
  } >"$script"
  printf '%s' "$script"
}

# case_exec <script> <tty-fixture>. Run a case script in a fresh working
# directory with fd 3 bound to <tty-fixture>. Merged output on stdout; the
# case script's exit status is the function's.
case_exec() {
  local script="$1" tty="$2" dir
  dir="$(mktemp -d "$TEST_TMPDIR/dir.XXXXXX")"
  (cd "$dir" && CASE_DIR="$dir" WIZARD_TEST_TTY="$tty" bash "$script" 2>&1)
}

# case_run <tty-fixture> [strict]. Build and run a one-off case from stdin.
case_run() {
  local tty="$1" mode="${2:-relaxed}" script
  script="$(case_build "$mode")"
  case_exec "$script" "$tty"
}

# fd-3 fixtures. /dev/null is EOF, the fail-closed input.
TTY_EOF=/dev/null
tty_fixture() {
  local name="$1"
  shift
  local path="$TEST_TMPDIR/tty-$name"
  printf '%s\n' "$@" >"$path"
  printf '%s' "$path"
}
TTY_Y="$(tty_fixture y y)"
TTY_N="$(tty_fixture n n)"
TTY_VALUE="$(tty_fixture value typed-value)"
TTY_BLANK="$(tty_fixture blank '')"
TTY_SECRET="$(tty_fixture secret 'sp3cial s3cret')"
TTY_PASTE="$(tty_fixture paste pasted-value y)"

# --- 1. Shipped-file contract -----------------------------------------------

if bash -n "$TEMPLATE" 2>/dev/null; then
  pass "template.sh parses (bash -n)"
else
  fail "template.sh parses (bash -n)" "exit 0" "parse error"
fi

assert_eq "template.sh declares set -euo pipefail" 1 \
  "$(grep -c '^set -euo pipefail$' "$TEMPLATE")"

assert_eq "STAGES marker appears exactly once (the authoring boundary)" 1 \
  "$(grep -c '^# STAGES' "$TEMPLATE")"

assert_eq "fd 3 is opened from /dev/tty exactly once (the seam this suite rewrites)" 1 \
  "$(grep -c 'exec 3</dev/tty' "$TEMPLATE")"

# The extraction must have cut above the example stage, or every library case
# below would be running the wizard's demo content too.
assert_not_contains "extracted library stops above the example stage" \
  "$(cat "$LIB")" "STRIPE_SECRET_KEY"

missing_fns=""
for fn in fatal banner stage say step note warn open_url pause confirm ask \
  ask_secret write_env set_secret set_var finish; do
  grep -qE "^${fn}\(\)" "$LIB" || missing_fns="$missing_fns $fn"
done
assert_eq "library defines the full helper API a generated wizard calls" "" "$missing_fns"

# The shipped example must stay self-consistent: TOTAL_STAGES is the denominator
# every `stage` line prints, so a drifted count ships a wizard that lies about
# its own length.
STAGES_SECTION="$TEST_TMPDIR/stages.sh"
awk 'found { print } /^# STAGES/ { found = 1 }' "$TEMPLATE" >"$STAGES_SECTION"
assert_eq "example TOTAL_STAGES matches the stage() calls below the marker" \
  "$(grep -E '^TOTAL_STAGES=' "$STAGES_SECTION" | tail -n1 | cut -d= -f2)" \
  "$(grep -cE '^stage "' "$STAGES_SECTION")"

# --- 2. Fail-closed without a terminal --------------------------------------

# On the unmodified shipped file, with the controlling terminal taken away.
if setsid --wait true >/dev/null 2>&1; then
  out="$(setsid --wait bash "$TEMPLATE" </dev/null 2>&1)"
  rc=$?
  assert_exit "shipped template refuses to start with no controlling TTY" 1 "$rc"
  assert_contains "... and names the reason" "$out" "no interactive terminal"
elif ! (exec 3</dev/tty) 2>/dev/null; then
  out="$(bash "$TEMPLATE" </dev/null 2>&1)"
  rc=$?
  assert_exit "shipped template refuses to start with no controlling TTY" 1 "$rc"
  assert_contains "... and names the reason" "$out" "no interactive terminal"
else
  # Not discriminating: the next case proves the same guard through the seam.
  skip_case "no setsid --wait and this host has a controlling TTY, cannot force the no-TTY path on the shipped file"
fi

# Same guard through the seam, with an unopenable fd-3 source. Deterministic
# everywhere, so the fail-closed contract is never left unproven.
out="$(
  case_run "$TEST_TMPDIR/no-such-tty" <<'BODY'
echo "reached-body"
BODY
)"
rc=$?
assert_exit "library aborts when its terminal source cannot be opened" 1 "$rc"
assert_not_contains "... before running any stage" "$out" "reached-body"

# --- 3. Key-name validation -------------------------------------------------

out="$(
  case_run "$TTY_EOF" <<'BODY'
for k in GOOD _under A1 x_9 A; do
  if (_valid_key "$k") >/dev/null 2>&1; then printf 'accept:%s\n' "$k"; else printf 'reject:%s\n' "$k"; fi
done
for k in 'bad-key' '1leading' 'has space' 'K=V' '' 'K;rm -rf /' 'K$(id)' 'K.V'; do
  if (_valid_key "$k") >/dev/null 2>&1; then printf 'accept:%s\n' "$k"; else printf 'reject:%s\n' "$k"; fi
done
BODY
)"
for k in GOOD _under A1 x_9 A; do
  assert_contains "_valid_key accepts '$k'" "$out" "accept:$k"
done
for k in 'bad-key' '1leading' 'has space' 'K=V' 'K;rm -rf /' 'K$(id)' 'K.V'; do
  assert_contains "_valid_key rejects '$k'" "$out" "reject:$k"
done
# Counted, not just spot-checked: this is what covers the empty-name fixture,
# whose reject line has nothing after the colon to match on.
assert_eq "_valid_key rejects all 8 invalid names, the empty one included" 8 \
  "$(printf '%s\n' "$out" | grep -c '^reject:')"
assert_eq "_valid_key accepts all 5 valid names and nothing else" 5 \
  "$(printf '%s\n' "$out" | grep -c '^accept:')"

out="$(
  case_run "$TTY_EOF" <<'BODY'
(write_env 'bad-key' value)
printf 'rc=%s\n' "$?"
if [[ -e .env ]]; then echo "env:CREATED"; else echo "env:ABSENT"; fi
BODY
)"
assert_contains "write_env fails on an invalid key" "$out" "rc=1"
assert_contains "... with a diagnosable message" "$out" "invalid key name: 'bad-key'"
assert_contains "... before the env file is created" "$out" "env:ABSENT"

# --- 4. write_env and _existing --------------------------------------------

# The fixture starts from a world-readable hand-written env file, which is the
# state a wizard actually walks into. The assertion is on the END state, which is
# the property that matters to a human whose secrets land there. Two mechanisms
# feed it, mktemp's own 0600 default on the staged rewrite and write_env's
# explicit chmods, so this case does not by itself pin either one.
out="$(
  case_run "$TTY_EOF" <<'BODY'
printf 'PRE=already here\n' >.env
chmod 644 .env
write_env API_KEY 'a value with spaces'
printf 'mode=[%s]\n' "$(ls -l .env | cut -c1-10)"
printf 'file=[%s]\n' "$(cat .env)"
BODY
)"
assert_contains "write_env stores the value single-quoted" "$out" "API_KEY='a value with spaces'"
assert_contains "write_env tightens a world-readable env file to owner-only" "$out" "mode=[-rw-------]"
assert_contains "write_env adopts a hand-written env file instead of clobbering it" "$out" "PRE=already here"
assert_contains "write_env reports the key it wrote" "$out" "wrote"

# The confirmation line is the only thing a human sees; a value must never be in it.
out="$(
  case_run "$TTY_EOF" <<'BODY'
write_env API_KEY 'hunter2-never-echo'
BODY
)"
assert_contains "write_env confirmation names the key" "$out" "API_KEY"
assert_not_contains "write_env never echoes the value it stored" "$out" "hunter2-never-echo"

out="$(
  case_run "$TTY_EOF" <<'BODY'
write_env K one >/dev/null
write_env OTHER keep >/dev/null
write_env K two >/dev/null
write_env K three >/dev/null
printf 'k_lines=%s\n' "$(grep -c '^K=' .env)"
printf 'k=[%s]\n' "$(_existing K)"
printf 'other=[%s]\n' "$(_existing OTHER)"
shopt -s nullglob
leftovers=(.env.*)
printf 'leftovers=%s\n' "${#leftovers[@]}"
BODY
)"
assert_contains "write_env upserts rather than appending" "$out" "k_lines=1"
assert_contains "... keeping the newest value" "$out" "k=[three]"
assert_contains "... and leaving other keys alone" "$out" "other=[keep]"
assert_contains "write_env leaves no staging temp file behind" "$out" "leftovers=0"

# The escaping contract: what write_env stores must read back byte-identical
# through _existing AND through a plain dotenv-style shell read.
out="$(
  case_run "$TTY_EOF" <<'BODY'
val="it's got 'quotes', \"doubles\" and a \$dollar"
write_env TRICKY "$val" >/dev/null
if [[ "$(_existing TRICKY)" == "$val" ]]; then echo "existing:OK"; else echo "existing:BAD [$(_existing TRICKY)]"; fi
sourced="$(bash -c 'set -a; . ./.env; printf "%s" "$TRICKY"')"
if [[ "$sourced" == "$val" ]]; then echo "sourced:OK"; else echo "sourced:BAD [$sourced]"; fi
BODY
)"
assert_contains "_existing round-trips an embedded single quote" "$out" "existing:OK"
assert_contains "a shell read of the env file returns the value verbatim" "$out" "sourced:OK"

out="$(
  case_run "$TTY_EOF" <<'BODY'
printf 'UNQUOTED=plain value\nDQ="double quoted"\nDUP=first\nDUP=second\nEMPTY=\n' >.env
printf 'unquoted=[%s]\n' "$(_existing UNQUOTED)"
printf 'dq=[%s]\n' "$(_existing DQ)"
printf 'dup=[%s]\n' "$(_existing DUP)"
_existing MISSING >/dev/null
printf 'missing_rc=%s\n' "$?"
ENV_FILE=absent.env
_existing UNQUOTED >/dev/null
printf 'nofile_rc=%s\n' "$?"
BODY
)"
assert_contains "_existing returns a hand-written unquoted value verbatim" "$out" "unquoted=[plain value]"
assert_contains "_existing strips one matched pair of double quotes" "$out" "dq=[double quoted]"
assert_contains "_existing takes the last duplicate line" "$out" "dup=[second]"
assert_contains "_existing fails when the key is absent" "$out" "missing_rc=1"
assert_contains "_existing fails when the env file does not exist" "$out" "nofile_rc=1"

# --- 5. The gitignore pre-flight -------------------------------------------

out="$(
  case_run "$TTY_EOF" <<'BODY'
git init -q . >/dev/null 2>&1
git config user.email fixture@example.com
git config user.name fixture
write_env A 1
write_env B 2
finish
BODY
)"
assert_contains "an ungitignored env file is called out in a git repo" "$out" "NOT gitignored"
assert_eq "... exactly once, however many values are written" 1 \
  "$(printf '%s\n' "$out" | grep -c 'NOT gitignored')"
assert_contains "... and lands in the closing summary" "$out" "add it to .gitignore"

out="$(
  case_run "$TTY_EOF" <<'BODY'
git init -q . >/dev/null 2>&1
git config user.email fixture@example.com
git config user.name fixture
printf '.env\n' >.gitignore
write_env A 1
finish
BODY
)"
assert_not_contains "a gitignored env file draws no warning" "$out" "NOT gitignored"

# --- 6. open_url ------------------------------------------------------------

out="$(
  case_run "$TTY_EOF" <<'BODY'
export PATH="$STUB_BIN:$PATH"
export OPEN_CAPTURE="$CASE_DIR/opened"
: >"$OPEN_CAPTURE"
open_url "https://dashboard.example.com/keys?tab=api"
printf 'rc=%s\n' "$?"
printf 'opened=[%s]\n' "$(cat "$OPEN_CAPTURE")"
BODY
)"
assert_contains "open_url prints the URL before dispatching it" "$out" "opening"
assert_contains "... including the full URL" "$out" "https://dashboard.example.com/keys?tab=api"
assert_contains "open_url dispatches an https URL to the opener" "$out" "opened=[https://dashboard.example.com/keys?tab=api]"
assert_contains "open_url returns success on the happy path" "$out" "rc=0"

out="$(
  case_run "$TTY_EOF" <<'BODY'
export PATH="$STUB_BIN:$PATH"
export OPEN_CAPTURE="$CASE_DIR/opened"
: >"$OPEN_CAPTURE"
for u in 'http://example.com' 'file:///etc/passwd' '//attacker/share/x' 'javascript:alert(1)' 'HTTPS://example.com'; do
  open_url "$u"
  printf 'rc=%s\n' "$?"
done
printf 'opened=[%s]\n' "$(cat "$OPEN_CAPTURE")"
BODY
)"
for u in 'http://example.com' 'file:///etc/passwd' '//attacker/share/x' 'javascript:alert(1)' 'HTTPS://example.com'; do
  assert_contains "open_url refuses '$u'" "$out" "refusing to open non-https URL: $u"
done
assert_contains "open_url never dispatches a refused URL" "$out" "opened=[]"
assert_not_contains "... and prints no opening line for one" "$out" "opening"
assert_not_contains "a refused URL is not fatal to the wizard" "$out" "rc=1"

# --- 7. Prompt gates over fd 3 ---------------------------------------------

# confirm's own drain is neutralized here so a scripted answer survives to the
# read; the drain has its own dedicated cases below.
confirm_case="$(
  case_build <<'BODY'
_drain_tty() { :; }
if confirm "proceed?"; then echo "answer:YES"; else echo "answer:NO"; fi
BODY
)"
for spec in 'y=YES' 'Y=YES' 'yes=YES' 'Yeah=YES' 'n=NO' 'N=NO' '=NO' 'maybe=NO' 'q=NO' '1=NO'; do
  answer="${spec%%=*}"
  want="${spec#*=}"
  fixture="$(tty_fixture confirm "$answer")"
  out="$(case_exec "$confirm_case" "$fixture")"
  assert_contains "confirm reads '$answer' as $want" "$out" "answer:$want"
done

out="$(
  case_run "$TTY_EOF" <<'BODY'
(confirm "proceed?")
printf 'rc=%s\n' "$?"
BODY
)"
assert_contains "confirm aborts rather than falling through at EOF" "$out" "terminal closed at a confirmation gate"
assert_contains "... with a failing status" "$out" "rc=1"

out="$(
  case_run "$TTY_EOF" <<'BODY'
(pause "Ready?")
printf 'rc=%s\n' "$?"
BODY
)"
assert_contains "pause aborts rather than falling through at EOF" "$out" "terminal closed at a pause gate"
assert_contains "... with a failing status" "$out" "rc=1"

# The paste bypass this library exists to close: a multi-line paste answered an
# earlier prompt AND left the next gate's answer buffered.
out="$(
  case_run "$TTY_PASTE" <<'BODY'
ask PASTED "Paste a value:"
printf 'asked=[%s]\n' "${PASTED-}"
if confirm "Really write it?"; then echo "gate:PASSED"; else echo "gate:REFUSED"; fi
BODY
)"
rc=$?
assert_contains "a pasted line still answers the prompt it was pasted into" "$out" "asked=[pasted-value]"
assert_not_contains "a buffered paste can never answer the NEXT confirmation gate" "$out" "gate:PASSED"
assert_contains "... the gate aborts instead" "$out" "terminal closed at a confirmation gate"
assert_exit "... and the wizard exits nonzero" 1 "$rc"

# Control for the case above: the same fixture DOES carry a working bypass
# payload, so the assertion there is the drain doing its job, not an empty file.
out="$(
  case_run "$TTY_PASTE" <<'BODY'
_drain_tty() { :; }
ask PASTED "Paste a value:"
if confirm "Really write it?"; then echo "gate:PASSED"; else echo "gate:REFUSED"; fi
BODY
)"
assert_contains "the paste fixture would pass the gate without the drain" "$out" "gate:PASSED"

out="$(
  case_run "$TTY_VALUE" <<'BODY'
ask MY_KEY "Value:"
printf 'value=[%s]\n' "${MY_KEY-}"
BODY
)"
assert_contains "ask assigns the typed line to the named variable" "$out" "value=[typed-value]"

out="$(
  case_run "$TTY_BLANK" <<'BODY'
write_env MY_KEY 'stored value' >/dev/null
ask MY_KEY "Value:"
printf 'value=[%s]\n' "${MY_KEY-}"
BODY
)"
assert_contains "an empty answer keeps the value already in the env file" "$out" "value=[stored value]"
assert_contains "... and the prompt says so" "$out" "Enter keeps current"

out="$(
  case_run "$TTY_VALUE" <<'BODY'
write_env MY_KEY 'stored value' >/dev/null
ask MY_KEY "Value:"
printf 'value=[%s]\n' "${MY_KEY-}"
BODY
)"
assert_contains "a typed answer overrides the stored value" "$out" "value=[typed-value]"

out="$(
  case_run "$TTY_VALUE" <<'BODY'
ask MY_KEY "Value:"
printf 'value=[%s]\n' "${MY_KEY-}"
BODY
)"
assert_not_contains "ask offers no default when nothing is stored" "$out" "Enter keeps current"

out="$(
  case_run "$TTY_SECRET" <<'BODY'
ask_secret TOKEN "Paste the secret:"
printf 'len=%s\n' "${#TOKEN}"
if [[ "$TOKEN" == 'sp3cial s3cret' ]]; then echo "assigned:OK"; else echo "assigned:BAD"; fi
BODY
)"
assert_contains "ask_secret assigns the typed secret" "$out" "assigned:OK"
assert_contains "... preserving it byte for byte" "$out" "len=14"
assert_contains "... and prints its prompt" "$out" "Paste the secret:"
assert_not_contains "... and prints its own newline so the next output is not glued on" \
  "$out" "Paste the secret: len="

# Echo suppression is a terminal-driver property, so a file-backed fd 3 cannot
# observe it: with or without -s nothing is echoed here. The flags are therefore
# pinned at the source, which is where the regression would actually land.
ask_secret_read="$(awk '/^ask_secret\(\)/ { inside = 1 } inside && /read / { print; exit }' "$LIB")"
assert_contains "ask_secret reads hidden and without readline, which would echo it back" \
  "$ask_secret_read" "read -rs -u 3 input"
ask_read="$(awk '/^ask\(\)/ { inside = 1 } inside && /read / { print; exit }' "$LIB")"
assert_contains "ask keeps readline editing on the non-secret prompt" "$ask_read" "-e"

out="$(
  case_run "$TTY_EOF" <<'BODY'
(ask MY_KEY "Value:")
printf 'ask_rc=%s\n' "$?"
(ask_secret TOKEN "Secret:")
printf 'secret_rc=%s\n' "$?"
BODY
)"
assert_contains "ask aborts at EOF instead of assigning empty" "$out" "terminal closed while reading MY_KEY"
assert_contains "... nonzero" "$out" "ask_rc=1"
assert_contains "ask_secret aborts at EOF too" "$out" "terminal closed while reading secret TOKEN"
assert_contains "... nonzero" "$out" "secret_rc=1"

# --- 8. GitHub Actions helpers ---------------------------------------------

GH_PRELUDE='export PATH="$STUB_BIN:$PATH"
export GH_CAPTURE="$CASE_DIR/gh"
mkdir -p "$GH_CAPTURE"
: >"$GH_CAPTURE/argv"
: >"$GH_CAPTURE/stdin"
'

out="$(
  case_run "$TTY_EOF" <<BODY
$GH_PRELUDE
set_secret TOKEN ""
printf 'secret_rc=%s\n' "\$?"
set_var REGION ""
printf 'var_rc=%s\n' "\$?"
printf 'ghcalls=%s\n' "\$(wc -l <"\$GH_CAPTURE/argv" | tr -d ' ')"
printf 'skipped=[%s]\n' "\${SKIPPED[*]-}"
BODY
)"
assert_contains "an empty secret is refused without calling gh" "$out" "ghcalls=0"
assert_contains "... reported as a skip" "$out" "empty value"
assert_contains "... non-fatally (secret)" "$out" "secret_rc=0"
assert_contains "... non-fatally (variable)" "$out" "var_rc=0"

out="$(
  case_run "$TTY_EOF" <<BODY
$GH_PRELUDE
export GH_STUB_AUTH_RC=1
set_secret TOKEN a-real-value
printf 'rc=%s\n' "\$?"
printf 'setcalls=%s\n' "\$(grep -c 'secret set' "\$GH_CAPTURE/argv")"
printf 'skipped=[%s]\n' "\${SKIPPED[*]-}"
BODY
)"
assert_contains "an unusable gh degrades to a skip, it does not fail the wizard" "$out" "rc=0"
assert_contains "... with no write attempted" "$out" "setcalls=0"
assert_contains "... and a hand-runnable remediation" "$out" "gh secret set TOKEN --repo <owner/repo>"

out="$(
  case_run "$TTY_Y" <<BODY
$GH_PRELUDE
_drain_tty() { :; }
set_secret DEPLOY_TOKEN 'top-secret-value'
printf 'rc=%s\n' "\$?"
printf 'written=[%s]\n' "\${WRITTEN_SECRET[*]-}"
printf 'stdin=[%s]\n' "\$(cat "\$GH_CAPTURE/stdin")"
printf 'argv=[%s]\n' "\$(tr '\\n' ' ' <"\$GH_CAPTURE/argv")"
BODY
)"
assert_contains "set_secret records the name it wrote" "$out" "written=[DEPLOY_TOKEN]"
assert_contains "set_secret sends the value over stdin" "$out" "stdin=[top-secret-value]"
assert_contains "set_secret pins the confirmed repo with --repo" "$out" "secret set DEPLOY_TOKEN --repo acme/widgets"
assert_not_contains "set_secret never puts the value on the command line" \
  "$(printf '%s\n' "$out" | grep '^argv=')" "top-secret-value"
assert_contains "set_secret succeeds" "$out" "rc=0"

out="$(
  case_run "$TTY_Y" <<BODY
$GH_PRELUDE
_drain_tty() { :; }
set_var REGION 'us-east-1'
printf 'written=[%s]\n' "\${WRITTEN_VAR[*]-}"
printf 'stdin=[%s]\n' "\$(cat "\$GH_CAPTURE/stdin")"
printf 'argv=[%s]\n' "\$(tr '\\n' ' ' <"\$GH_CAPTURE/argv")"
BODY
)"
assert_contains "set_var records the name it wrote" "$out" "written=[REGION]"
assert_contains "set_var sends the value over stdin" "$out" "stdin=[us-east-1]"
assert_contains "set_var pins the confirmed repo with --repo" "$out" "variable set REGION --repo acme/widgets"
assert_not_contains "set_var never puts the value on the command line" \
  "$(printf '%s\n' "$out" | grep '^argv=')" "us-east-1"

# The fixture holds exactly ONE `y`. A second confirmation prompt would read EOF
# and abort, so a green run here IS the proof that the repo is resolved once.
out="$(
  case_run "$TTY_Y" <<BODY
$GH_PRELUDE
_drain_tty() { :; }
set_secret FIRST one >/dev/null
set_var SECOND two >/dev/null
set_secret THIRD three >/dev/null
printf 'rc=%s\n' "\$?"
printf 'repoviews=%s\n' "\$(grep -c 'repo view' "\$GH_CAPTURE/argv")"
printf 'secrets=[%s]\n' "\${WRITTEN_SECRET[*]-}"
printf 'vars=[%s]\n' "\${WRITTEN_VAR[*]-}"
BODY
)"
assert_contains "the target repo is resolved and confirmed exactly once" "$out" "repoviews=1"
assert_contains "... and every later write reuses it (secrets)" "$out" "secrets=[FIRST THIRD]"
assert_contains "... and every later write reuses it (variables)" "$out" "vars=[SECOND]"
assert_contains "... with no second confirmation prompt" "$out" "rc=0"

out="$(
  case_run "$TTY_N" <<BODY
$GH_PRELUDE
_drain_tty() { :; }
set_secret TOKEN a-real-value
printf 'rc=%s\n' "\$?"
printf 'setcalls=%s\n' "\$(grep -c 'secret set' "\$GH_CAPTURE/argv")"
printf 'skipped=[%s]\n' "\${SKIPPED[*]-}"
BODY
)"
assert_contains "declining the repo confirmation writes nothing" "$out" "setcalls=0"
assert_contains "... and names the repo it declined" "$out" "declined for acme/widgets"
assert_contains "... and the secret is listed as still to do" "$out" "no confirmed target repo"
assert_contains "... without failing the wizard" "$out" "rc=0"

out="$(
  case_run "$TTY_EOF" <<BODY
$GH_PRELUDE
export GH_STUB_REPO_RC=1
set_secret TOKEN a-real-value
printf 'rc=%s\n' "\$?"
printf 'setcalls=%s\n' "\$(grep -c 'secret set' "\$GH_CAPTURE/argv")"
printf 'skipped=[%s]\n' "\${SKIPPED[*]-}"
BODY
)"
assert_contains "an unresolvable repo skips the write" "$out" "setcalls=0"
assert_contains "... surfacing the gh error text" "$out" "gh repo view failed: stub: no repo here"
assert_contains "... without failing the wizard" "$out" "rc=0"

out="$(
  case_run "$TTY_Y" <<BODY
$GH_PRELUDE
_drain_tty() { :; }
export GH_STUB_SET_RC=1
set_secret TOKEN a-real-value
printf 'rc=%s\n' "\$?"
printf 'written=[%s]\n' "\${WRITTEN_SECRET[*]-}"
printf 'skipped=[%s]\n' "\${SKIPPED[*]-}"
BODY
)"
assert_contains "a failing gh write surfaces its stderr in the summary" "$out" "gh error: stub: gh secret set refused"
assert_contains "... is not counted as written" "$out" "written=[]"
assert_contains "... and does not abort the wizard" "$out" "rc=0"

# --- 9. Stage framing and the closing summary -------------------------------

out="$(
  case_run "$TTY_EOF" <<'BODY'
TOTAL_STAGES=3
stage "First thing"
say "an instruction"
step "a browser action"
note "an aside"
warn "a caution"
stage "Second thing"
BODY
)"
assert_contains "stage numbers itself against TOTAL_STAGES" "$out" "Stage 1/3"
assert_contains "stage increments across calls" "$out" "Stage 2/3"
assert_contains "stage prints its title" "$out" "First thing"
assert_contains "say/step/note/warn all reach the human" "$out" "an instruction"
assert_contains "... including the caution" "$out" "a caution"
case "$out" in
*$'\033'*) fail "no ANSI escapes when stdout is not a terminal" "no ESC bytes" "escapes present" ;;
*) pass "no ANSI escapes when stdout is not a terminal" ;;
esac

out="$(
  case_run "$TTY_Y" <<BODY
$GH_PRELUDE
_drain_tty() { :; }
write_env API_KEY 'env-value-secret' >/dev/null
set_secret DEPLOY_TOKEN 'ci-value-secret' >/dev/null
set_var REGION 'us-east-1' >/dev/null
SKIPPED+=("rotate the old key by hand")
finish
BODY
)"
assert_contains "finish announces completion" "$out" "Setup complete"
assert_contains "finish names the env keys written" "$out" "API_KEY"
assert_contains "finish names the secrets set" "$out" "DEPLOY_TOKEN"
assert_contains "finish names the variables set" "$out" "REGION"
assert_contains "finish names the target repo" "$out" "acme/widgets"
assert_contains "finish lists the leftover manual work" "$out" "still to do by hand"
assert_contains "... itemized" "$out" "rotate the old key by hand"
assert_not_contains "finish never prints an env value" "$out" "env-value-secret"
assert_not_contains "finish never prints a secret value" "$out" "ci-value-secret"

out="$(
  case_run "$TTY_EOF" <<'BODY'
finish
BODY
)"
rc=$?
assert_exit "finish on a wizard that wrote nothing still exits clean" 0 "$rc"
assert_not_contains "... and claims no leftover work" "$out" "still to do by hand"

# --- 10. The EXIT trap must not turn a clean run into a failure -------------

# Run with the library's own `set -e` left in force. _cleanup's if-form exists
# precisely so a false condition does not hand the EXIT trap a nonzero status;
# the `[[ ... ]] && rm` form this replaced exits 1 from a wizard that did
# everything right.
out="$(
  case_run "$TTY_EOF" strict <<'BODY'
write_env A 1 >/dev/null
echo "reached-end"
BODY
)"
rc=$?
assert_exit "a successful wizard exits 0 under set -e (EXIT trap keeps its status)" 0 "$rc"
assert_contains "... having run to completion" "$out" "reached-end"

# --- Tally ------------------------------------------------------------------

printf '\n%d case(s), %d failure(s), %d skip(s)\n' "$CASE_NUM" "$FAILED" "$SKIPPED_N"
[[ $FAILED -eq 0 ]] || exit 1
