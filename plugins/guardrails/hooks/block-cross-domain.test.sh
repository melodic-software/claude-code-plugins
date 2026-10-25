#!/usr/bin/env bash
# Contract test for block-cross-domain.sh (guardrails plugin).
#
# Black-box: the hook runs as a subprocess on a PreToolUse payload, alone and
# under run-guards.sh. Every exit is 0, so the assertions are on stdout (no
# deny; the malformed-map notice), on the GUARDRAILS_CROSS_DOMAIN_TRACE steps
# on stderr (what a call read and parsed), on the telemetry envelope (the cwd's
# class and what the command names), and, where strace runs, on the processes a
# call starts. The domain map is built here from placeholder names under the
# suite's own temp tree.
# test-scope: plugins/guardrails/hooks/hooks.json
# shellcheck disable=SC2016  # commands under test carry literal $ spellings

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-cross-domain.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_CROSS_DOMAIN_ENABLED GUARDRAILS_CROSS_DOMAIN_TRACE

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for these tests" >&2
  exit 1
fi

GUARD_UNDER_TEST="$HOOK"
HOOKS_JSON="$HOOK_DIR/hooks.json"
if command -v cygpath >/dev/null 2>&1; then HOOKS_JSON=$(cygpath -m "$HOOKS_JSON"); fi

# This host's roots key, and another host's, whose roots are validated and
# never used here.
case "${OSTYPE:-}" in
msys* | cygwin* | win32)
  OS_KEY=windows
  OTHER_KEY=linux
  OTHER_ROOT=/placeholder/other
  ;;
*)
  OS_KEY=linux
  [[ "${OSTYPE:-}" == darwin* ]] && OS_KEY=macos
  OTHER_KEY=windows
  OTHER_ROOT='C:\placeholder\other'
  ;;
esac

TREES="$TEST_TMPDIR/trees"
HOME_DIR="$TEST_TMPDIR/home"
A_ROOT="$TREES/alpha"
B_ROOT="$TREES/beta"
D_ROOT="$A_ROOT/nested"
G_ROOT="$HOME_DIR/gamma"
NEUTRAL="$TEST_TMPDIR/neutral"
mkdir -p "$A_ROOT/repo" "$B_ROOT/repo" "$D_ROOT/repo" "$G_ROOT" "$NEUTRAL"

# The placeholder map: alpha and beta with markers, delta nested in alpha,
# gamma below HOME. beta's root carries a trailing separator.
MAP=$(MSYS_NO_PATHCONV=1 jq -n --arg os "$OS_KEY" --arg other "$OTHER_KEY" --arg other_root "$OTHER_ROOT" \
  --arg a "$A_ROOT" --arg b "$B_ROOT/" --arg d "$D_ROOT" --arg g "$G_ROOT" '{
    domains: {
      alpha: {roots: {($os): [$a]}, owners: ["alpha-org"], identity_markers: ["alpha-org"],
        gh_config_dir: "/placeholder/gh-alpha"},
      beta: {roots: {($os): [$b], ($other): [$other_root]}, owners: ["beta-org"],
        identity_markers: ["beta-org"], az_config_dir: "/placeholder/az-beta"},
      delta: {roots: {($os): [$d]}},
      gamma: {roots: {($os): [$g]}}
    },
    identity_files: ["/placeholder/identity"],
    shared_exceptions: ["/placeholder/shared"],
    messages: {cross_domain: "placeholder message"}
  }')

write_map() { # <data dir> <map text>
  mkdir -p "$1"
  printf '%s\n' "$2" >"$1/identity-domains.json"
}

DATA="$TEST_TMPDIR/data"
write_map "$DATA" "$MAP"

# call <data dir> <cwd> <command> [env word ...]: the guard alone on a Bash
# payload, with the trace on and HOME at the fixture's.
call() {
  local data="$1" cwd="$2" cmd="$3"
  shift 3
  guard_invoke --cwd "$cwd" --command "$cmd" -- "CLAUDE_PLUGIN_DATA=$data" \
    GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR" "$@"
}

# --- No map: nothing is read or parsed --------------------------------------
NO_MAP="$TEST_TMPDIR/no-map"
mkdir -p "$NO_MAP"
for via in direct dispatched; do
  guard_invoke --via "$via" --cwd "$A_ROOT/repo" --command "ls $B_ROOT" -- \
    "CLAUDE_PLUGIN_DATA=$NO_MAP" GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR"
  assert_exit "no map ($via): exit 0" 0 "$GUARD_RC"
  assert_silent "no map ($via): stdout is empty" "$GUARD_OUT"
  assert_silent "no map ($via): no step traced, so nothing read or parsed" "$GUARD_ERR"
done
assert_file_absent "no map: no cache is written" "$NO_MAP/identity-domains.cache"
guard_invoke --cwd "$A_ROOT/repo" --command "ls $B_ROOT" -- GUARDRAILS_CROSS_DOMAIN_TRACE=1
assert_exit "no plugin data directory: exit 0" 0 "$GUARD_RC"
assert_silent "no plugin data directory: silent" "$GUARD_OUT$GUARD_ERR"

# --- Kill switch --------------------------------------------------------------
call "$DATA" "$A_ROOT/repo" "ls $B_ROOT" CLAUDE_PLUGIN_OPTION_BLOCK_CROSS_DOMAIN_ENABLED=false
assert_exit "kill switch off: exit 0" 0 "$GUARD_RC"
assert_silent "kill switch off: stdout is empty" "$GUARD_OUT"
assert_silent "kill switch off: no step traced" "$GUARD_ERR"
assert_file_absent "kill switch off: the map is not compiled" "$DATA/identity-domains.cache"

# --- The prefilter returns before the parser runs ----------------------------
call "$DATA" "$A_ROOT/repo" 'git status --short'
assert_exit "map, no root or marker named: exit 0" 0 "$GUARD_RC"
assert_silent "map, no root or marker named: stdout is empty" "$GUARD_OUT"
assert_contains "the first call compiles the map" "$GUARD_ERR" "trace map-compile"
assert_contains "no root or marker named: the prefilter misses" "$GUARD_ERR" "trace prefilter-miss"
assert_absent "no root or marker named: the parser does not run" "$GUARD_ERR" "trace parse"
if [[ -f "$DATA/identity-domains.cache" ]]; then
  ok "the compiled map is cached beside it"
else
  bad "no cache was written beside the map"
fi
call "$DATA" "$A_ROOT/repo" 'git status --short'
assert_contains "the second call reads the cache" "$GUARD_ERR" "trace map-cached"
assert_absent "the second call does not compile" "$GUARD_ERR" "trace map-compile"
assert_absent "the second call, nothing named: the parser does not run" "$GUARD_ERR" "trace parse"

# --- What a command names -----------------------------------------------------
# hit <label> <command>: the prefilter hits, the parser runs, nothing is denied.
hit() {
  call "$DATA" "$A_ROOT/repo" "$2"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  assert_silent "$1: no decision on stdout" "$GUARD_OUT"
  assert_contains "$1: the prefilter hits" "$GUARD_ERR" "trace prefilter-hit"
  assert_contains "$1: the parser runs" "$GUARD_ERR" "trace parse"
}
# miss <label> <command>: the prefilter misses and the parser does not run.
miss() {
  call "$DATA" "$A_ROOT/repo" "$2"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  assert_contains "$1: the prefilter misses" "$GUARD_ERR" "trace prefilter-miss"
  assert_absent "$1: the parser does not run" "$GUARD_ERR" "trace parse"
}
FS='/'
BS="\\"
hit "another domain's root" "ls '$B_ROOT/repo'"
hit "a root the map spells with a trailing separator" "ls $B_ROOT"
hit "the cwd's own root" "ls $A_ROOT/repo/src"
hit "a marker" 'git clone git@example.invalid:beta-org/repo.git'
hit "a marker in another case" 'echo BETA-ORG'
hit "a root below HOME after ~" 'ls ~/gamma/notes'
hit 'a root below HOME after $HOME' 'ls "$HOME/gamma"'
hit "a root spelled with backslashes" "ls ${B_ROOT//"$FS"/"$BS"}"
miss "a longer name that starts like a root" "ls ${B_ROOT}shop"
miss "a root inside a longer path" "ls /mnt$B_ROOT"
miss "a marker inside a longer word" 'echo beta-orgs'
miss "a relative path ending like a root below HOME" 'ls ./gamma/notes'

# --- Telemetry: the cwd's class and what the command names --------------------
TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "cat >\"$TEL\"")"
# tel <label> <cwd> <command> <form> <cwd class> [tool]
tel() {
  local data
  rm -f "$TEL"
  guard_invoke --tool "${6:-Bash}" --cwd "$2" --command "$3" -- "CLAUDE_PLUGIN_DATA=$DATA" \
    "HOOK_TELEMETRY_SINK=$SINK" "HOME=$HOME_DIR"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  if wait_for_sink "$TEL"; then
    data=$(jq -c '.data' "$TEL")
    assert_eq "$1: hook" block-cross-domain "$(jq -r '.hook' "$TEL")"
    assert_eq "$1: status" ok "$(jq -r '.status' "$TEL")"
    assert_eq "$1: form" "$4" "$(jq -r '.data.form' "$TEL")"
    assert_eq "$1: cwd" "$5" "$(jq -r '.data.cwd' "$TEL")"
    assert_absent "$1: no domain name in the data" "$data" alpha
    assert_absent "$1: no path in the data" "$data" "$TREES"
  else
    bad "$1: no telemetry envelope"
  fi
}
NL=$'\n'
tel "cwd in a domain, nothing named" "$A_ROOT/repo" 'git status --short' prefilter-miss domain
tel "cwd outside every root" "$NEUTRAL" 'git status --short' prefilter-miss neutral
tel "the cwd's own root" "$A_ROOT/repo" "ls $A_ROOT/repo/src" own-domain domain
tel "another domain's root" "$A_ROOT/repo" "ls $B_ROOT/repo" other-domain domain
tel "a domain's root from a neutral cwd" "$NEUTRAL" "ls $A_ROOT" other-domain neutral
tel "the cwd's own marker" "$A_ROOT/repo" 'git push git@example.invalid:alpha-org/repo.git' own-domain domain
tel "nested roots: the longer one holds the cwd and the word" "$D_ROOT/repo" "ls $D_ROOT/repo/x" own-domain domain
tel "nested roots: the outer root is another domain" "$D_ROOT/repo" "ls $A_ROOT/repo" other-domain domain
tel "two roots in one word: the shorter one still counts" "$D_ROOT/repo" \
  "docker run -v $B_ROOT/x:$D_ROOT/y img" other-domain domain
tel "a root only in a heredoc body is no word" "$A_ROOT/repo" "cat <<'EOF'${NL}$B_ROOT${NL}EOF" not-named domain
tel "PowerShell: another domain's root" "$A_ROOT/repo" "Get-ChildItem '$B_ROOT'" other-domain domain PowerShell
tel 'PowerShell: a root below HOME after $env:USERPROFILE' "$A_ROOT/repo" \
  'Get-ChildItem $env:USERPROFILE\gamma' other-domain domain PowerShell

# PowerShell is read as text: the prefilter runs, the Bash parser does not.
guard_invoke --tool PowerShell --cwd "$A_ROOT/repo" --command "Get-ChildItem '$B_ROOT'" -- \
  "CLAUDE_PLUGIN_DATA=$DATA" GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR"
assert_exit "PowerShell: exit 0" 0 "$GUARD_RC"
assert_contains "PowerShell: the prefilter hits" "$GUARD_ERR" "trace prefilter-hit"
assert_absent "PowerShell: the Bash parser does not run" "$GUARD_ERR" "trace parse"

# --- A malformed map: no deny, the user told once -----------------------------
BAD_N=0
# malformed <label> <map text> <start of the reason>
malformed() {
  BAD_N=$((BAD_N + 1))
  local data="$TEST_TMPDIR/bad-$BAD_N"
  write_map "$data" "$2"
  call "$data" "$A_ROOT/repo" "ls $B_ROOT"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  assert_absent "$1: no deny" "$GUARD_OUT" permissionDecision
  assert_contains "$1: the user is told why the map is malformed" \
    "$(jq -r '.systemMessage // empty' <<<"$GUARD_OUT")" "is malformed ($3"
  assert_eq "$1: nothing on the model's channel" "" "$(jq -r '.hookSpecificOutput // empty' <<<"$GUARD_OUT")"
  assert_absent "$1: the prefilter does not run" "$GUARD_ERR" "trace prefilter"
  call "$data" "$A_ROOT/repo" "ls $B_ROOT"
  assert_exit "$1, again: exit 0" 0 "$GUARD_RC"
  assert_silent "$1, again: told once per session" "$GUARD_OUT"
  assert_contains "$1, again: the rejection is cached" "$GUARD_ERR" "trace map-cached"
}
malformed "not JSON" '{' "it is not valid JSON"
malformed "an array" '[]' "the map is not an object"
malformed "an unknown top-level key" '{"domains": {}, "extras": 1}' "the map has an unknown key, extras"
malformed "no domains" '{"identity_files": []}' "the map has no domains"
malformed "domains not an object" '{"domains": []}' "domains is not an object"
malformed "a domain name with a space" '{"domains": {"bad name": {"roots": {}}}}' "a domain name holds a character"
malformed "a domain name ending in a newline" '{"domains": {"alpha\n": {"roots": {}}}}' "a domain name holds a character"
malformed "a domain with no roots" '{"domains": {"alpha": {}}}' "domains.alpha has no roots"
malformed "an unknown domain key" '{"domains": {"alpha": {"roots": {}, "owner": []}}}' \
  "domains.alpha has an unknown key, owner"
malformed "an unknown roots key" '{"domains": {"alpha": {"roots": {"plan9": ["/x"]}}}}' \
  "domains.alpha.roots has an unknown key, plan9"
malformed "a relative root" "{\"domains\": {\"alpha\": {\"roots\": {\"$OS_KEY\": [\"relative/path\"]}}}}" \
  "domains.alpha.roots.$OS_KEY holds a path that is not absolute"
malformed "a filesystem root" "{\"domains\": {\"alpha\": {\"roots\": {\"$OS_KEY\": [\"/\"]}}}}" \
  "domains.alpha.roots.$OS_KEY holds a path that is not absolute"
malformed "another host's relative root" "{\"domains\": {\"alpha\": {\"roots\": {\"$OTHER_KEY\": [\"relative\"]}}}}" \
  "domains.alpha.roots.$OTHER_KEY holds a path that is not absolute"
malformed "a marker that is not a string" '{"domains": {"alpha": {"roots": {}, "identity_markers": [1]}}}' \
  "domains.alpha.identity_markers[0] is not a non-empty one-line string"
malformed "a message on two lines" '{"domains": {}, "messages": {"note": "a\nb"}}' \
  "messages.note is not a non-empty one-line string"

write_map "$TEST_TMPDIR/bad-dispatched" '{'
guard_invoke --via dispatched --cwd "$A_ROOT/repo" --command "ls $B_ROOT" -- \
  "CLAUDE_PLUGIN_DATA=$TEST_TMPDIR/bad-dispatched" "HOME=$HOME_DIR"
assert_exit "malformed map (dispatched): exit 0" 0 "$GUARD_RC"
assert_absent "malformed map (dispatched): no deny" "$GUARD_OUT" permissionDecision
assert_contains "malformed map (dispatched): the user is told" \
  "$(jq -r '.systemMessage // empty' <<<"$GUARD_OUT")" "is malformed (it is not valid JSON"

EMPTY_DOMAINS="$TEST_TMPDIR/empty-domains"
write_map "$EMPTY_DOMAINS" '{"domains": {}}'
call "$EMPTY_DOMAINS" "$A_ROOT/repo" "ls $B_ROOT"
assert_exit "no domains configured: exit 0" 0 "$GUARD_RC"
assert_silent "no domains configured: silent" "$GUARD_OUT"
assert_contains "no domains configured: the prefilter misses" "$GUARD_ERR" "trace prefilter-miss"

# --- jq missing: one notice, never a deny -------------------------------------
HIDE_JQ="$TEST_TMPDIR/hide-jq.sh"
printf '%s\n' \
  'command() { local a; for a in "$@"; do [[ "$a" == jq ]] && return 1; done; builtin command "$@"; }' \
  'jq() { return 127; }' >"$HIDE_JQ"
NOJQ="$TEST_TMPDIR/nojq"
write_map "$NOJQ" "$MAP"
guard_invoke --cwd "$A_ROOT/repo" --command "ls $B_ROOT" -- "CLAUDE_PLUGIN_DATA=$NOJQ" \
  "BASH_ENV=$HIDE_JQ" "CLAUDE_PLUGIN_ROOT=$HOOK_DIR/.."
assert_exit "jq hidden, map present: exit 0" 0 "$GUARD_RC"
assert_absent "jq hidden, map present: no deny" "$GUARD_OUT" permissionDecision
assert_contains "jq hidden, map present: the user is told jq is missing" \
  "$(jq -r '.systemMessage // empty' <<<"$GUARD_OUT")" "jq not on the hook PATH"
guard_invoke --cwd "$A_ROOT/repo" --command "ls $B_ROOT" -- "CLAUDE_PLUGIN_DATA=$NO_MAP" \
  "BASH_ENV=$HIDE_JQ" "CLAUDE_PLUGIN_ROOT=$HOOK_DIR/.."
assert_exit "jq hidden, no map: exit 0" 0 "$GUARD_RC"
assert_silent "jq hidden, no map: silent" "$GUARD_OUT$GUARD_ERR"

# --- The cache follows the map ----------------------------------------------
EDIT="$TEST_TMPDIR/edit"
write_map "$EDIT" "$MAP"
call "$EDIT" "$A_ROOT/repo" 'echo epsilon-org'
assert_contains "before the edit: a word that is no marker misses" "$GUARD_ERR" "trace prefilter-miss"
write_map "$EDIT" "$(jq -c '.domains.alpha.identity_markers += ["epsilon-org"]' <<<"$MAP")"
call "$EDIT" "$A_ROOT/repo" 'echo epsilon-org'
assert_contains "an edited map is compiled again" "$GUARD_ERR" "trace map-compile"
assert_contains "the edited map's new marker is named" "$GUARD_ERR" "trace prefilter-hit"
printf 'not a cache' >"$EDIT/identity-domains.cache"
call "$EDIT" "$A_ROOT/repo" 'echo epsilon-org'
assert_contains "a cache that is not this map's is compiled again" "$GUARD_ERR" "trace map-compile"
assert_contains "after the recompile the marker is still named" "$GUARD_ERR" "trace prefilter-hit"

# --- Under the dispatcher, and on the shipped row -----------------------------
guard_invoke --via dispatched --cwd "$A_ROOT/repo" --command "ls $B_ROOT" -- \
  "CLAUDE_PLUGIN_DATA=$DATA" GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR"
assert_exit "dispatched, a root named: exit 0" 0 "$GUARD_RC"
assert_silent "dispatched, a root named: no decision on stdout" "$GUARD_OUT"
assert_contains "dispatched, a root named: the parser runs" "$GUARD_ERR" "trace parse"
guard_invoke --via dispatched --cwd "$A_ROOT/repo" --command 'git status --short' -- \
  "CLAUDE_PLUGIN_DATA=$DATA" GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR"
assert_exit "dispatched, nothing named: exit 0" 0 "$GUARD_RC"
assert_contains "dispatched, nothing named: the prefilter misses" "$GUARD_ERR" "trace prefilter-miss"
assert_absent "dispatched, nothing named: the parser does not run" "$GUARD_ERR" "trace parse"

ROW_ARGS=()
while IFS= read -r arg; do ROW_ARGS+=("${arg%$'\r'}"); done < <(jq -r '
  .hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[0].args
  | .[(map(endswith("/hooks/run-guards.sh")) | index(true)) + 1:][]' "$HOOKS_JSON")
if [[ " ${ROW_ARGS[*]} " == *" block-cross-domain.sh "* ]]; then
  ok "the Bash|PowerShell row runs block-cross-domain.sh"
else
  bad "the Bash|PowerShell row does not run block-cross-domain.sh: ${ROW_ARGS[*]}"
fi
ROW_PAYLOAD=$(MSYS_NO_PATHCONV=1 jq -nc --arg c "ls $B_ROOT/repo" --arg d "$A_ROOT/repo" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}')
row_rc=0
row_out=$(cd "$HOOK_DIR" && env CLAUDE_PLUGIN_ROOT="$HOOK_DIR/.." CLAUDE_PLUGIN_DATA="$DATA" \
  CLAUDE_CODE_SESSION_ATTENDED=0 GUARDRAILS_CROSS_DOMAIN_TRACE=1 HOME="$HOME_DIR" \
  bash "$HOOK_DIR/run-guards.sh" "${ROW_ARGS[@]}" <<<"$ROW_PAYLOAD" 2>"$TEST_TMPDIR/row.err") || row_rc=$?
assert_exit "the shipped row, a root named: exit 0" 0 "$row_rc"
assert_absent "the shipped row, a root named: no deny" "$row_out" permissionDecision
assert_contains "the shipped row, a root named: the guard parses it" "$(cat "$TEST_TMPDIR/row.err")" "trace parse"

# --- Processes a call starts (#3529 instrument) -------------------------------
# The kernel counts them: strace follows the dispatcher (-f) and reports each
# clone/clone3/fork/vfork return and each execve that succeeded. The guard's
# share is the count minus a no-op guard dispatched the same way on the same
# payload. HOOK_TELEMETRY_SINK and the trace are cleared. A host without a
# working strace (Windows Git Bash, macOS) skips visibly; the Linux CI lane is
# where the pins hold.
strace_census() { # <payload> <guard> <data dir> -> CENSUS_RC CENSUS_CREATIONS CENSUS_EXECVE
  local log="$TEST_TMPDIR/strace.log"
  CENSUS_RC=0
  (cd "$NEUTRAL" && env -u HOOK_TELEMETRY_SINK -u GUARDRAILS_CROSS_DOMAIN_TRACE CLAUDE_PROJECT_DIR= \
    CLAUDE_PLUGIN_DATA="$3" HOME="$HOME_DIR" \
    strace -f -e trace=clone,clone3,fork,vfork,execve -o "$log" \
    bash "$HOOK_DIR/run-guards.sh" "$2" <<<"$1" >/dev/null 2>&1) || CENSUS_RC=$?
  CENSUS_CREATIONS=$(grep -cE '((clone|clone3|fork|vfork)\(|<\.\.\. (clone|clone3|fork|vfork) resumed>).* = [0-9]+$' "$log")
  CENSUS_EXECVE=$(grep -cE '(execve\(|<\.\.\. execve resumed>).* = 0$' "$log")
}
census_share() { # <command> <data dir> -> SHARE_RC SHARE_CREATIONS SHARE_EXECVE
  local payload noop_cre noop_exe
  payload=$(MSYS_NO_PATHCONV=1 jq -nc --arg c "$1" --arg d "$A_ROOT/repo" \
    '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}')
  strace_census "$payload" "$TEST_TMPDIR/noop-guard.sh" "$2"
  noop_cre=$CENSUS_CREATIONS
  noop_exe=$CENSUS_EXECVE
  strace_census "$payload" block-cross-domain.sh "$2"
  SHARE_RC=$CENSUS_RC
  SHARE_CREATIONS=$((CENSUS_CREATIONS - noop_cre))
  SHARE_EXECVE=$((CENSUS_EXECVE - noop_exe))
}
if command -v strace >/dev/null 2>&1 && strace -o /dev/null -e trace=execve true 2>/dev/null; then
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMPDIR/noop-guard.sh"
  CENSUS="$TEST_TMPDIR/census"
  write_map "$CENSUS" "$MAP"

  census_share 'git status --short' "$NO_MAP"
  assert_exit "strace: no map: exit 0" 0 "$SHARE_RC"
  assert_eq "strace: no map: the guard's process creations" 0 "$SHARE_CREATIONS"
  assert_eq "strace: no map: the guard's execve count" 0 "$SHARE_EXECVE"

  census_share 'git status --short' "$CENSUS"
  assert_exit "strace: a map not yet compiled: exit 0" 0 "$SHARE_RC"
  assert_eq "strace: a map not yet compiled: jq and mv are the two creations" 2 "$SHARE_CREATIONS"
  assert_eq "strace: a map not yet compiled: jq and mv are the two execve" 2 "$SHARE_EXECVE"

  census_share 'git status --short' "$CENSUS"
  assert_eq "strace: compiled map, nothing named: the guard's process creations" 0 "$SHARE_CREATIONS"
  assert_eq "strace: compiled map, nothing named: the guard's execve count" 0 "$SHARE_EXECVE"

  census_share "ls $B_ROOT/repo" "$CENSUS"
  assert_exit "strace: compiled map, a root named: exit 0" 0 "$SHARE_RC"
  assert_eq "strace: compiled map, a root named and parsed: the guard's process creations" 0 "$SHARE_CREATIONS"
  assert_eq "strace: compiled map, a root named and parsed: the guard's execve count" 0 "$SHARE_EXECVE"
else
  echo "ok: process-creation pins skipped (no working strace on this host)"
fi

report
