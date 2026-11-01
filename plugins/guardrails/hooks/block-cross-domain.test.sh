#!/usr/bin/env bash
# Contract test for block-cross-domain.sh (guardrails plugin).
#
# Black-box: the hook runs as a subprocess on a PreToolUse payload, alone and
# under run-guards.sh. Every exit is 0, so the assertions are on stdout (the
# deny document; the malformed-map notice), on the GUARDRAILS_CROSS_DOMAIN_TRACE
# steps on stderr (what a call read and parsed), on the telemetry envelope (the
# cwd's class, what the command names, and whether it was denied), and, where
# strace runs, on the processes a call starts. The domain map is built here from
# placeholder names under the suite's own temp tree.
# test-scope: plugins/guardrails/hooks/hooks.json
# shellcheck disable=SC2016  # commands under test carry literal $ spellings
# test-scope: plugins/guardrails/.claude-plugin/plugin.json plugins/guardrails/prerequisites.json

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-cross-domain.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_CROSS_DOMAIN_ENABLED GUARDRAILS_CROSS_DOMAIN_TRACE GH_CONFIG_DIR AZURE_CONFIG_DIR

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

# The placeholder map: alpha and beta with owners and markers (shared-org in
# both), delta nested in alpha, gamma below HOME, and epsilon and zeta on drive
# Q, spelled as a Windows drive path for Windows and as its WSL mount elsewhere.
# beta's root carries a trailing separator. No root of epsilon or zeta exists on
# disk: only the text is read. alpha has a gh config directory below HOME and
# beta an az one, so for gh beta uses the default, and for az alpha does.
# epsilon's shared directory is open to zeta.
GH_A="$HOME_DIR/.config/gh-alpha"
if [[ "$OS_KEY" == windows ]]; then
  Q_HOST='Q:\placeholder'
  Q_SEP="\\"
else
  Q_HOST=/mnt/q/placeholder
  Q_SEP=/
fi
E_CWD="$Q_HOST${Q_SEP}epsilon${Q_SEP}repo"
Z_CWD="$Q_HOST${Q_SEP}zeta${Q_SEP}repo"
# shared_map <entry JSON>: the placeholder map with that one shared_exceptions
# entry; a path below drive Q's placeholder directory is given as `@/<rest>`.
shared_map() {
  MSYS_NO_PATHCONV=1 jq -c --arg q "$Q_HOST" --arg sep "$Q_SEP" --argjson e "$1" '
    def q: if startswith("@/") then $q + $sep + (.[2:] | gsub("/"; $sep)) else . end;
    .shared_exceptions = [$e | if type == "string" then q else .path |= q end]' <<<"$MAP"
}
MAP=$(MSYS_NO_PATHCONV=1 jq -n --arg os "$OS_KEY" --arg other "$OTHER_KEY" --arg other_root "$OTHER_ROOT" \
  --arg a "$A_ROOT" --arg b "$B_ROOT/" --arg d "$D_ROOT" --arg g "$G_ROOT" --arg gha "$GH_A" \
  --arg es "$Q_HOST${Q_SEP}epsilon${Q_SEP}shared" '{
    domains: {
      alpha: {roots: {($os): [$a]}, owners: ["alpha-org"], identity_markers: ["alpha-org", "shared-org"],
        gh_config_dir: $gha},
      beta: {roots: {($os): [$b], ($other): [$other_root]}, owners: ["beta-org"],
        identity_markers: ["beta-org", "dev@beta.example", "gh-beta", "az-beta", "shared-org"],
        az_config_dir: "/placeholder/az-beta"},
      delta: {roots: {($os): [$d]}},
      gamma: {roots: {($os): [$g]}},
      epsilon: {roots: {windows: ["Q:\\placeholder\\epsilon"], linux: ["/mnt/q/placeholder/epsilon"],
        macos: ["/mnt/q/placeholder/epsilon"]}},
      zeta: {roots: {windows: ["Q:\\placeholder\\zeta"], linux: ["/mnt/q/placeholder/zeta"],
        macos: ["/mnt/q/placeholder/zeta"]}}
    },
    identity_files: ["/placeholder/identity"],
    shared_exceptions: [{path: $es, from: ["zeta"], to: "epsilon"}],
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

# --- No map: no domain, and a command that writes no identity is not parsed ---
NO_MAP="$TEST_TMPDIR/no-map"
mkdir -p "$NO_MAP"
for via in direct dispatched; do
  guard_invoke --via "$via" --cwd "$A_ROOT/repo" --command "ls $B_ROOT" -- \
    "CLAUDE_PLUGIN_DATA=$NO_MAP" GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR"
  assert_exit "no map ($via): exit 0" 0 "$GUARD_RC"
  assert_silent "no map ($via): stdout is empty" "$GUARD_OUT"
  assert_silent "no map ($via): no step traced, so no map read and nothing parsed" "$GUARD_ERR"
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

# --- What a command names, and what it denies ---------------------------------
# verdict <label> <deny|allow>: what the last call decided. A deny is one
# PreToolUse document on stdout, and the exit stays 0.
verdict() {
  local reason
  if [[ "$2" == allow ]]; then
    assert_silent "$1: allowed, nothing on stdout" "$GUARD_OUT"
    assert_absent "$1: allowed, no deny traced" "$GUARD_ERR" "trace deny"
    return 0
  fi
  assert_eq "$1: denied" deny "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
  reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")
  assert_contains "$1: the reason says which guard denied it" "$reason" "block-cross-domain: denied"
  assert_contains "$1: the reason names the way off" "$reason" "block_cross_domain_enabled"
}
# hit <label> <command> [deny|allow]: the prefilter hits, the parser runs, and
# the call from alpha's tree is denied or allowed.
hit() {
  call "$DATA" "$A_ROOT/repo" "$2"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  assert_contains "$1: the prefilter hits" "$GUARD_ERR" "trace prefilter-hit"
  assert_contains "$1: the parser runs" "$GUARD_ERR" "trace parse"
  [[ -z "${3-}" ]] || verdict "$1" "$3"
}
# miss <label> <command>: the prefilter misses, the parser does not run, and the
# call is allowed.
miss() {
  call "$DATA" "$A_ROOT/repo" "$2"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  assert_contains "$1: the prefilter misses" "$GUARD_ERR" "trace prefilter-miss"
  assert_absent "$1: the parser does not run" "$GUARD_ERR" "trace parse"
  verdict "$1" allow
}
FS='/'
BS="\\"
hit "another domain's root" "ls '$B_ROOT/repo'" deny
hit "a root the map spells with a trailing separator" "ls $B_ROOT" deny
hit "another domain's root as a redirection target" "echo x >'$B_ROOT/notes'" deny
hit "another domain's root after cd" "cd $B_ROOT/repo && git status" deny
hit "another domain's root inside bash -c" "bash -c 'cat $B_ROOT/repo/README.md'" deny
hit "the cwd's own root" "ls $A_ROOT/repo/src" allow
hit "a marker" 'git clone git@example.invalid:beta-org/repo.git' allow
hit "a marker in another case" 'echo BETA-ORG' allow
hit "a root below HOME after ~" 'ls ~/gamma/notes' deny
hit 'a root below HOME after $HOME' 'ls "$HOME/gamma"' deny
hit 'a root below HOME after a quoted $HOME' 'ls "$HOME"/gamma' deny
# Unquoted, bash drops each backslash, so the word the parser hands over names
# no root: the prefilter hits on the raw text and the parse settles it.
hit "a root spelled with unquoted backslashes" "ls ${B_ROOT//"$FS"/"$BS"}" allow
hit "a root spelled with quoted backslashes" "ls '${B_ROOT//"$FS"/"$BS"}'" deny
miss "a longer name that starts like a root" "ls ${B_ROOT}shop"
miss "a root inside a longer path" "ls /mnt$B_ROOT"
miss "a marker inside a longer word" 'echo beta-orgs'
miss "a relative path ending like a root below HOME" 'ls ./gamma/notes'
miss "a neutral path" "ls $NEUTRAL/x"

# Every spelling of a root on drive Q, from whichever form the host's map holds.
E_WIN="Q:${BS}placeholder${BS}epsilon"
hit "a drive path with backslashes" "ls '$E_WIN${BS}x'" deny
hit "a drive path with escaped backslashes" "ls '${E_WIN//"$BS"/"$BS$BS"}'" deny
hit "a drive path with forward slashes" 'ls Q:/placeholder/epsilon/x' deny
hit "a drive path in another case" 'ls q:/PLACEHOLDER/Epsilon' deny
hit "an MSYS drive path" 'ls /q/placeholder/epsilon/x' deny
hit "a Cygwin drive path" 'ls /cygdrive/q/placeholder/epsilon' deny
hit "a WSL drive path" 'ls /mnt/q/placeholder/epsilon/x' deny
hit "a WSL drive path in another case" 'ls /MNT/Q/Placeholder/EPSILON' deny
miss "a drive path that only starts like a root" 'ls /q/placeholder/epsilons'
miss "a drive path on another drive" 'ls R:/placeholder/epsilon'

# An owner's directory below ~/src/github.com or ~/worktrees/github.com is that
# owner's domain's path.
hit "another domain's owner below ~/src" 'ls ~/src/github.com/beta-org/repo' deny
hit "another domain's owner below ~/worktrees" 'git -C ~/worktrees/github.com/beta-org/repo/wt status' deny
hit 'another domain'"'"'s owner after $HOME' 'cat "$HOME/src/github.com/beta-org/repo/README.md"' deny
hit "another domain's owner by the literal home path" "ls $HOME_DIR/src/github.com/beta-org" deny
hit "another domain's owner in another case" 'ls ~/src/github.com/Beta-Org/repo' deny
hit "the cwd's own owner" 'ls ~/src/github.com/alpha-org/repo' allow
hit "another domain's owner below another host, a marker only" 'ls ~/src/gitlab.com/beta-org/repo' allow
miss "an owner that only starts like another domain's" 'ls ~/src/github.com/beta-orgs/repo'
miss "an owner no domain lists" 'ls ~/src/github.com/unlisted-org/repo'

# Where the cwd is decides: from beta's tree alpha's paths are the other
# domain's, and from a neutral cwd nothing is denied.
call "$DATA" "$B_ROOT/repo" "ls $A_ROOT/repo ~/src/github.com/alpha-org"
verdict "from beta's tree, alpha's root and owner" deny
REASON=$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")
assert_contains "from beta's tree: the reason names the cwd's domain" "$REASON" "identity domain 'beta'"
assert_contains "from beta's tree: the reason names alpha once" "$REASON" "another domain ('alpha')"
call "$DATA" "$A_ROOT/repo" "ls $B_ROOT/repo ~/gamma"
assert_contains "two other domains: the reason names both, in the order named" \
  "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")" "another domain ('beta', 'gamma')"
call "$DATA" "$NEUTRAL" "ls $A_ROOT $B_ROOT/repo ~/src/github.com/beta-org"
assert_contains "from a neutral cwd: the parser runs" "$GUARD_ERR" "trace parse"
verdict "from a neutral cwd, two domains' paths" allow
call "$DATA" "$A_ROOT/repo" "ls $B_ROOT" CLAUDE_CODE_SESSION_ATTENDED=1
verdict "an attended session" deny

# An owner's directory classifies the cwd as a root does: inside beta-org's
# clone the session is beta's.
OWNED="$HOME_DIR/src/github.com/beta-org/repo"
call "$DATA" "$OWNED" "ls $A_ROOT/repo"
verdict "from beta-org's clone, alpha's root" deny
assert_contains "from beta-org's clone: the reason names beta as the cwd's domain" \
  "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")" "identity domain 'beta'"
call "$DATA" "$OWNED" "ls ~/worktrees/github.com/beta-org/repo/wt $B_ROOT/repo"
assert_contains "from beta-org's clone, beta's own paths: the parser runs" "$GUARD_ERR" "trace parse"
verdict "from beta-org's clone, beta's own paths" allow

# --- A shared exception opens one directory one way ---------------------------
# sp <form> <path below drive Q's placeholder directory>: one spelling of it,
# the Windows one quoted so the parse keeps its backslashes.
sp() {
  case "$1" in
  windows) printf "'Q:%splaceholder%s%s'" "$BS" "$BS" "${2//"$FS"/"$BS"}" ;;
  msys) printf '/q/placeholder/%s' "$2" ;;
  *) printf '/mnt/q/placeholder/%s' "$2" ;;
  esac
}
# shared <label> <deny|allow> <data dir> <cwd> <command, each drive Q path as
# `{<path below the placeholder directory>}`>: the call in the Windows, MSYS and
# WSL spellings of every drive Q path. A group holding a comma is shell brace
# syntax, never a path, and is sent as written.
shared() {
  local form cmd rest
  for form in windows msys wsl; do
    cmd="" rest=$5
    while [[ "$rest" =~ ^([^{]*)\{([^},]*)\}(.*)$ ]]; do
      cmd+=${BASH_REMATCH[1]}$(sp "$form" "${BASH_REMATCH[2]}")
      rest=${BASH_REMATCH[3]}
    done
    call "$3" "$4" "$cmd$rest"
    assert_exit "$1 ($form): exit 0" 0 "$GUARD_RC"
    verdict "$1 ($form)" "$2"
  done
}
shared "from a from domain, inside the exception" allow "$DATA" "$Z_CWD" 'ls {epsilon/shared/x}'
shared "from a from domain, the exception itself" allow "$DATA" "$Z_CWD" 'ls {epsilon/shared}'
shared "from a from domain, a write inside the exception" allow "$DATA" "$Z_CWD" \
  'cp {epsilon/shared/a} {epsilon/shared/b} && echo x >{epsilon/shared/c}'
shared "from a from domain, the exception beside its own path" allow "$DATA" "$Z_CWD" \
  'cp {zeta/repo/a} {epsilon/shared/b}'
shared "from the to domain, a from domain's path" deny "$DATA" "$E_CWD" 'ls {zeta/repo/x}'
shared "from an unlisted domain, the exception" deny "$DATA" "$A_ROOT/repo" 'ls {epsilon/shared/x}'
shared "from a from domain, the exception with .." deny "$DATA" "$Z_CWD" 'ls {epsilon/shared/../x}'
shared "from a from domain, a .. elsewhere in the command" deny "$DATA" "$Z_CWD" 'ls {epsilon/shared/x} ../y'
shared "from a from domain, one foreign path outside the exception" deny "$DATA" "$Z_CWD" \
  'cp {epsilon/shared/a} {epsilon/private/b}'
shared "from a from domain, a name that only starts like the exception" deny "$DATA" "$Z_CWD" \
  'ls {epsilon/shared-not/x}'
shared "from a from domain, the exception beside a sibling that starts like it" deny "$DATA" "$Z_CWD" \
  'cp {epsilon/shared/a} {epsilon/shared-private/b}'
shared "from a from domain, a sibling whose name continues with +" deny "$DATA" "$Z_CWD" 'cat {epsilon/shared+x/f}'
shared "from a from domain, a sibling whose name continues with ~" deny "$DATA" "$Z_CWD" 'cat {epsilon/shared~x/f}'
shared "from a from domain, an operator right after the exception" allow "$DATA" "$Z_CWD" 'ls {epsilon/shared}|cat'
shared "from a from domain, a glob right after the exception" deny "$DATA" "$Z_CWD" 'cat {epsilon/shared}*/x'
shared "from a from domain, a brace right after the exception" deny "$DATA" "$Z_CWD" 'ls {epsilon/shared}{,-private}'
shared "from a from domain, an expansion right after the exception" deny "$DATA" "$Z_CWD" 'ls {epsilon/shared}$X'
shared "from a from domain, a glob below the exception" allow "$DATA" "$Z_CWD" 'ls {epsilon/shared/x}*'
call "$DATA" "$Z_CWD" "ls $(sp msys epsilon/private/x)"
assert_contains "a path the exception does not hold: the reason names its to domain" \
  "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")" "another domain ('epsilon')"

# An entry that grants nothing leaves the map well formed and the user is told
# once: a path that is not a path of its to domain, and a plain string.
SHARED_N=0
# no_grant <label> <entry JSON> <what the notice says>
no_grant() {
  SHARED_N=$((SHARED_N + 1))
  local data="$TEST_TMPDIR/shared-$SHARED_N"
  write_map "$data" "$(shared_map "$2")"
  call "$data" "$Z_CWD" "ls $(sp msys epsilon/shared/x)"
  verdict "$1" deny
  assert_absent "$1: the map is not malformed" "$GUARD_OUT" "is malformed"
  assert_contains "$1: the user is told which entry grants nothing" \
    "$(jq -r '.systemMessage // empty' <<<"$GUARD_OUT")" "shared_exceptions[0] $3"
  assert_contains "$1: the notice says to re-run setup" "$(jq -r '.systemMessage // empty' <<<"$GUARD_OUT")" \
    "/guardrails:setup apply identity-domains"
  shared "$1, again" deny "$data" "$Z_CWD" 'ls {epsilon/shared/x}'
  assert_absent "$1, again: told once per session" "$GUARD_OUT" systemMessage
  call "$data" "$A_ROOT/repo" "ls $A_ROOT/repo"
  verdict "$1, the guard still checks" allow
  call "$data" "$Z_CWD" "ls $(sp wsl epsilon/x)"
  verdict "$1, the guard still denies another domain's path" deny
}
no_grant "an exception whose path is not in its to domain" '{"path": "@/epsilon/shared", "from": ["zeta"], "to": "delta"}' \
  "grants nothing: its path is not a path of its to domain, 'delta'"
no_grant "a string entry" '"@/epsilon/shared"' "grants nothing: it is a plain path"
call "$TEST_TMPDIR/shared-$SHARED_N" "$NEUTRAL" "ls $A_ROOT"
assert_silent "a string entry, from a neutral cwd after the notice: silent" "$GUARD_OUT"
# A path below a domain nested in `to` is that domain's, so `to` cannot open it.
NESTED_DATA="$TEST_TMPDIR/shared-nested"
write_map "$NESTED_DATA" "$(shared_map "$(MSYS_NO_PATHCONV=1 jq -nc --arg p "$D_ROOT/x" '{path: $p, from: ["beta"], to: "alpha"}')")"
call "$NESTED_DATA" "$B_ROOT/repo" "ls $D_ROOT/x/f"
verdict "an exception below a domain nested in its to" deny
assert_contains "an exception below a domain nested in its to: the user is told" \
  "$(jq -r '.systemMessage // empty' <<<"$GUARD_OUT")" "shared_exceptions[0] grants nothing: its path is not a path of its to domain, 'alpha'"
assert_contains "an exception below a domain nested in its to: the reason names the nested domain" \
  "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")" "another domain ('delta')"

# --- Telemetry: the cwd's class, what the command names, and the decision -----
TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "cat >\"$TEL\"")"
# tel <label> <cwd> <command> <form> <cwd class> <status> [tool]
tel() {
  local data
  rm -f "$TEL"
  guard_invoke --tool "${7:-Bash}" --cwd "$2" --command "$3" -- "CLAUDE_PLUGIN_DATA=$DATA" \
    "HOOK_TELEMETRY_SINK=$SINK" "HOME=$HOME_DIR"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  if wait_for_sink "$TEL"; then
    data=$(jq -c '.data' "$TEL")
    assert_eq "$1: hook" block-cross-domain "$(jq -r '.hook' "$TEL")"
    assert_eq "$1: status" "$6" "$(jq -r '.status' "$TEL")"
    assert_eq "$1: form" "$4" "$(jq -r '.data.form' "$TEL")"
    assert_eq "$1: cwd" "$5" "$(jq -r '.data.cwd' "$TEL")"
    assert_absent "$1: no domain name in the data" "$data" alpha
    assert_absent "$1: no path in the data" "$data" "$TREES"
  else
    bad "$1: no telemetry envelope"
  fi
}
NL=$'\n'
tel "cwd in a domain, nothing named" "$A_ROOT/repo" 'git status --short' prefilter-miss domain ok
tel "cwd outside every root" "$NEUTRAL" 'git status --short' prefilter-miss neutral ok
tel "the cwd's own root" "$A_ROOT/repo" "ls $A_ROOT/repo/src" own-domain domain ok
tel "another domain's root" "$A_ROOT/repo" "ls $B_ROOT/repo" other-domain domain blocked
tel "a domain's root from a neutral cwd" "$NEUTRAL" "ls $A_ROOT" other-domain neutral ok
tel "the cwd's own marker" "$A_ROOT/repo" 'git push git@example.invalid:alpha-org/repo.git' own-domain domain ok
tel "another domain's marker" "$A_ROOT/repo" 'git push git@example.invalid:beta-org/repo.git' other-domain domain ok
tel "another domain's owner" "$A_ROOT/repo" 'ls ~/src/github.com/beta-org/repo' other-domain domain blocked
tel "nested roots: the longer one holds the cwd and the word" "$D_ROOT/repo" "ls $D_ROOT/repo/x" own-domain domain ok
tel "nested roots: the outer root is another domain" "$D_ROOT/repo" "ls $A_ROOT/repo" other-domain domain blocked
tel "two roots in one word: the shorter one still counts" "$D_ROOT/repo" \
  "docker run -v $B_ROOT/x:$D_ROOT/y img" other-domain domain blocked
tel "a root only in a heredoc body is no word" "$A_ROOT/repo" "cat <<'EOF'${NL}$B_ROOT${NL}EOF" not-named domain ok
tel "PowerShell: another domain's root" "$A_ROOT/repo" "Get-ChildItem '$B_ROOT'" other-domain domain blocked PowerShell
tel 'PowerShell: a root below HOME after $env:USERPROFILE' "$A_ROOT/repo" \
  'Get-ChildItem $env:USERPROFILE\gamma' other-domain domain blocked PowerShell
tel "PowerShell: another domain's owner" "$A_ROOT/repo" \
  "Get-ChildItem \$env:USERPROFILE${BS}src${BS}github.com${BS}beta-org${BS}repo" other-domain domain blocked PowerShell
tel "PowerShell: a drive path" "$A_ROOT/repo" 'Get-ChildItem Q:\placeholder\epsilon\x' \
  other-domain domain blocked PowerShell
tel "PowerShell: a marker only" "$A_ROOT/repo" 'Write-Output beta-org' other-domain domain ok PowerShell

# PowerShell is read as text: the prefilter runs, the Bash parser does not.
guard_invoke --tool PowerShell --cwd "$A_ROOT/repo" --command "Get-ChildItem '$B_ROOT'" -- \
  "CLAUDE_PLUGIN_DATA=$DATA" GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR"
assert_exit "PowerShell: exit 0" 0 "$GUARD_RC"
assert_contains "PowerShell: the prefilter hits" "$GUARD_ERR" "trace prefilter-hit"
assert_absent "PowerShell: the Bash parser does not run" "$GUARD_ERR" "trace parse"
verdict "PowerShell: another domain's root" deny

# --- Identity positions (rule 4) ----------------------------------------------
# deny <label> <command> [tool]: from alpha's tree, the call is denied.
deny() {
  guard_invoke --tool "${3:-Bash}" --cwd "$A_ROOT/repo" --command "$2" -- \
    "CLAUDE_PLUGIN_DATA=$DATA" "HOME=$HOME_DIR"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  assert_eq "$1: denied" deny "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
}
# allow <label> <command> [cwd] [tool]: the call is not denied.
allow() {
  guard_invoke --tool "${4:-Bash}" --cwd "${3:-$A_ROOT/repo}" --command "$2" -- \
    "CLAUDE_PLUGIN_DATA=$DATA" "HOME=$HOME_DIR"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  assert_absent "$1: not denied" "$GUARD_OUT" permissionDecision
}
URL='git@example.invalid:beta-org/repo.git'
deny "git remote add to another domain's org" "git remote add origin $URL"
assert_contains "the deny reason names the position" \
  "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$GUARD_OUT")" "git remote add"
deny "git remote set-url to another domain's org" 'git remote set-url origin https://example.invalid/beta-org/repo'
deny "git remote set-url --push" "git remote set-url --push origin $URL"
deny "git -C <dir> remote add" "git -C sub remote add upstream $URL"
deny "git remote add in a later segment" "cd sub && git remote add origin $URL"
deny "git config remote.<name>.url" "git config remote.origin.url $URL"
deny "git config user.email" 'git config user.email dev@beta.example'
deny "git config --local user.email" 'git config --local user.email dev@beta.example'
deny "git config set user.email" 'git config set user.email dev@beta.example'
deny "git -c user.email=" 'git -c user.email=dev@beta.example commit -m wip'
deny "git commit --author=" 'git commit --author="Dev <dev@beta.example>" -m wip'
deny "git commit --author <v>" 'git commit -m wip --author "Dev <dev@beta.example>"'
deny "GIT_AUTHOR_EMAIL= before git" 'GIT_AUTHOR_EMAIL=dev@beta.example git commit -m wip'
deny "export GH_CONFIG_DIR=" 'export GH_CONFIG_DIR=/placeholder/gh-beta'
deny "GH_CONFIG_DIR= before gh" 'GH_CONFIG_DIR=~/.config/gh-beta gh pr list'
deny "env AZURE_CONFIG_DIR=" 'env AZURE_CONFIG_DIR=/placeholder/az-beta az account show'
deny 'PowerShell: $env:GH_CONFIG_DIR = <v>' '$env:GH_CONFIG_DIR = "C:\placeholder\gh-beta"' PowerShell
deny 'PowerShell: $env:AZURE_CONFIG_DIR=<v>' "\$env:AZURE_CONFIG_DIR='C:\\placeholder\\az-beta'" PowerShell
deny "PowerShell: git remote add" "git remote add origin $URL" PowerShell
deny 'PowerShell: $env:name= <v>, any case' '$env:gh_config_dir= "C:\placeholder\gh-beta"' PowerShell
deny "an assignment after then" 'if true; then export GH_CONFIG_DIR=/placeholder/gh-beta; fi'
allow "a lowercase Bash variable is not GH_CONFIG_DIR" 'gh_config_dir=/placeholder/gh-beta true'
allow "git remote set-url --delete" "git remote set-url --delete origin $URL"
allow "the marker in a commit message" "git commit -m \"git remote add origin $URL\""
allow "user.email= in a commit message" 'git commit -m "user.email=dev@beta.example"'
allow "an echo of an assignment" 'echo GH_CONFIG_DIR=/placeholder/gh-beta'
allow "an echo of an address" 'echo dev@beta.example'
allow "git log --author filters, it sets nothing" 'git log --author=dev@beta.example'
allow "git config --get with a value pattern" 'git config --get user.email dev@beta.example'
allow "git clone of another domain's org" "git clone $URL"
allow "the cwd's own marker" 'git remote add origin git@example.invalid:alpha-org/repo.git'
allow "a marker the cwd's domain also lists" 'git remote add origin git@example.invalid:shared-org/repo.git'
allow "from a neutral cwd" "git remote add origin $URL" "$NEUTRAL"
allow "PowerShell: an assignment in a string" 'Write-Output "GH_CONFIG_DIR=C:\placeholder\gh-beta"' "" PowerShell
guard_invoke --via dispatched --cwd "$A_ROOT/repo" --command "git remote add origin $URL" -- \
  "CLAUDE_PLUGIN_DATA=$DATA" "HOME=$HOME_DIR"
assert_exit "dispatched, an identity position: exit 0" 0 "$GUARD_RC"
assert_contains "dispatched, an identity position: denied" "$GUARD_OUT" '"permissionDecision":"deny"'
rm -f "$TEL"
guard_invoke --cwd "$A_ROOT/repo" --command "git remote add origin $URL" -- "CLAUDE_PLUGIN_DATA=$DATA" \
  "HOOK_TELEMETRY_SINK=$SINK" "HOME=$HOME_DIR"
if wait_for_sink "$TEL"; then
  assert_eq "identity deny telemetry: status" blocked "$(jq -r '.status' "$TEL")"
  assert_eq "identity deny telemetry: form" identity-deny "$(jq -r '.data.form' "$TEL")"
  assert_absent "identity deny telemetry: no marker in the data" "$(jq -c '.data' "$TEL")" beta-org
else
  bad "identity deny telemetry: no telemetry envelope"
fi

# --- Config directories (rule 5) ----------------------------------------------
A_CWD="$A_ROOT/repo"
B_CWD="$B_ROOT/repo"
CONF_TOOL=Bash
# conf <label> <deny|allow> <cwd> <command> [env word ...]: the call on
# CONF_TOOL, denied or not. CONF_REASON is the deny's reason.
conf() {
  local label=$1 want=$2 cwd=$3 cmd=$4
  shift 4
  guard_invoke --tool "$CONF_TOOL" --cwd "$cwd" --command "$cmd" -- "CLAUDE_PLUGIN_DATA=$DATA" \
    GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR" "$@"
  assert_exit "$label: exit 0" 0 "$GUARD_RC"
  CONF_REASON=$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")
  if [[ "$want" == allow ]]; then
    assert_absent "$label: not denied" "$GUARD_OUT" permissionDecision
  else
    assert_eq "$label: denied" deny "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
    assert_contains "$label: the reason names the way off" "$CONF_REASON" block_cross_domain_enabled
  fi
}
conf "gh without the domain's directory" deny "$A_CWD" 'gh pr list'
assert_contains "gh without the domain's directory: the reason names it" "$CONF_REASON" \
  "runs gh without the domain's GH_CONFIG_DIR ($GH_A)"
assert_contains "gh from a domain: the config prefilter hits" "$GUARD_ERR" "trace config-hit"
assert_absent "gh from a domain, no path named: the path prefilter does not hit" "$GUARD_ERR" "trace prefilter-hit"
conf "gh with it in the command" allow "$A_CWD" "GH_CONFIG_DIR=$GH_A gh pr list"
conf "gh with it only in the hook environment" allow "$A_CWD" 'gh pr list' "GH_CONFIG_DIR=$GH_A"
conf "gh with it after ~" allow "$A_CWD" 'GH_CONFIG_DIR=~/.config/gh-alpha gh pr list'
conf 'gh with it after $HOME, in another case, with a trailing separator' allow "$A_CWD" \
  'GH_CONFIG_DIR="$HOME/.Config/gh-alpha/" gh pr list'
conf "gh with it exported earlier" allow "$A_CWD" "export GH_CONFIG_DIR=$GH_A && gh pr list"
conf "gh with it after env" allow "$A_CWD" "env GH_CONFIG_DIR=$GH_A gh auth status"
conf "gh --version" allow "$A_CWD" 'gh --version'
conf "a gh word that is no command" allow "$A_CWD" 'echo gh pr list'
conf "gh by its path" deny "$A_CWD" '/usr/bin/gh pr list'
conf "gh in a later segment" deny "$A_CWD" 'git status && gh pr list'
conf "gh with another directory" deny "$A_CWD" 'GH_CONFIG_DIR=/placeholder/other gh pr list'
conf "gh with it before an earlier command only" deny "$A_CWD" "GH_CONFIG_DIR=$GH_A true && gh pr list"
conf "gh after a bare assignment of an unexported name" deny "$A_CWD" "GH_CONFIG_DIR=$GH_A; gh pr list"
conf "gh after a bare assignment of an exported name" allow "$A_CWD" "GH_CONFIG_DIR=$GH_A; gh pr list" \
  GH_CONFIG_DIR=/placeholder/other
conf "gh after unset" deny "$A_CWD" 'unset GH_CONFIG_DIR; gh pr list' "GH_CONFIG_DIR=$GH_A"
conf "gh after env -u" deny "$A_CWD" 'env -u GH_CONFIG_DIR gh pr list' "GH_CONFIG_DIR=$GH_A"
conf "gh after env -i" deny "$A_CWD" 'env -i gh pr list' "GH_CONFIG_DIR=$GH_A"
conf "gh after env -" deny "$A_CWD" 'env - gh pr list' "GH_CONFIG_DIR=$GH_A"
conf "gh after env -C <dir>" deny "$A_CWD" 'env -C /placeholder gh pr list'
conf "gh after time -p" deny "$A_CWD" 'time -p gh pr list'
conf "command -v gh looks gh up" allow "$A_CWD" 'command -v gh'
conf "an assignment before command -v holds for it only" deny "$A_CWD" \
  "GH_CONFIG_DIR=$GH_A command -v gh && gh pr list" GH_CONFIG_DIR=/placeholder/other
conf "az from a domain that uses the default" allow "$A_CWD" 'az account show'
conf "az with another domain's directory, from a domain that uses the default" deny "$A_CWD" \
  'az account show' AZURE_CONFIG_DIR=/placeholder/az-beta
assert_contains "the default-domain reason names the other domain" "$CONF_REASON" \
  "runs az with domain 'beta''s AZURE_CONFIG_DIR, where this domain uses the default"
conf "from beta, gh with alpha's directory in the command" deny "$B_CWD" "GH_CONFIG_DIR=$GH_A gh pr list"
conf "from beta, gh with alpha's directory in the hook environment" deny "$B_CWD" 'gh pr list' \
  "GH_CONFIG_DIR=$GH_A"
conf "from beta, gh with the default" allow "$B_CWD" 'gh pr list'
conf "from beta, az without the domain's directory" deny "$B_CWD" 'az account show'
conf "from beta, az with it" allow "$B_CWD" 'AZURE_CONFIG_DIR=/placeholder/az-beta az account show'
conf "from beta, az --version" allow "$B_CWD" 'az --version'
conf "from a neutral cwd, gh without a directory" allow "$NEUTRAL" 'gh pr list'
assert_contains "from a neutral cwd, gh: the prefilter misses" "$GUARD_ERR" "trace prefilter-miss"
CONF_TOOL=PowerShell
conf "PowerShell: gh without the domain's directory" deny "$A_CWD" 'gh pr list'
conf 'PowerShell: gh after $env:GH_CONFIG_DIR' allow "$A_CWD" '$env:GH_CONFIG_DIR = "~\.config\gh-alpha"; gh pr list'
conf "PowerShell: gh.exe" deny "$A_CWD" 'gh.exe pr list'
CONF_TOOL=Bash
guard_invoke --via dispatched --cwd "$A_CWD" --command 'gh pr list' -- "CLAUDE_PLUGIN_DATA=$DATA" "HOME=$HOME_DIR"
assert_exit "dispatched, gh without the domain's directory: exit 0" 0 "$GUARD_RC"
assert_contains "dispatched, gh without the domain's directory: denied" "$GUARD_OUT" '"permissionDecision":"deny"'
rm -f "$TEL"
guard_invoke --cwd "$A_CWD" --command 'gh pr list' -- "CLAUDE_PLUGIN_DATA=$DATA" \
  "HOOK_TELEMETRY_SINK=$SINK" "HOME=$HOME_DIR"
if wait_for_sink "$TEL"; then
  assert_eq "config deny telemetry: status" blocked "$(jq -r '.status' "$TEL")"
  assert_eq "config deny telemetry: form" config-deny "$(jq -r '.data.form' "$TEL")"
  assert_absent "config deny telemetry: no domain name in the data" "$(jq -c '.data' "$TEL")" alpha
else
  bad "config deny telemetry: no telemetry envelope"
fi

# --- Git identity writes (rule 6) ---------------------------------------------
# idw <label> <deny|allow> <cwd> <command> [data dir] [tool]: the call, denied
# as an identity write or not denied at all.
idw() {
  guard_invoke --tool "${6:-Bash}" --cwd "$3" --command "$4" -- "CLAUDE_PLUGIN_DATA=${5:-$DATA}" \
    GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR"
  assert_exit "$1: exit 0" 0 "$GUARD_RC"
  if [[ "$2" == allow ]]; then
    assert_absent "$1: not denied" "$GUARD_OUT" permissionDecision
    return 0
  fi
  assert_eq "$1: denied" deny "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
  IDW_REASON=$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")
  assert_contains "$1: the reason names an identity write" "$IDW_REASON" "writes this machine's git identity"
  assert_contains "$1: the reason names the way off" "$IDW_REASON" block_cross_domain_enabled
}
# Each cwd: a neutral one and one in a domain, both with the map, and a neutral
# one on a host with no map.
IDW_WHERE=("neutral cwd|$NEUTRAL|$DATA" "domain cwd|$A_ROOT/repo|$DATA" "no map|$NEUTRAL|$NO_MAP")
idw_each() { # <deny|allow> <label> <command> [tool]
  local where label cwd data
  for where in "${IDW_WHERE[@]}"; do
    IFS='|' read -r label cwd data <<<"$where"
    idw "$2, $label" "$1" "$cwd" "$3" "$data" "${4:-Bash}"
  done
}
for key in user.email user.signingkey credential.helper core.sshCommand core.hooksPath user.useConfigOnly \
  'includeIf.gitdir:~/work/.path'; do
  for form in "--global $key v" "--system $key v" "--file ~/.gitconfig-work $key v" "-f ~/work.gitconfig $key v" \
    "set --global $key v" "--global --unset $key" "--global --add $key v" "unset --global $key"; do
    idw_each deny "git config $form" "git config $form"
  done
done
idw_each deny "credential.<url>.helper" 'git config --global credential.https://example.invalid.helper store'
idw_each deny "a key in another case" 'git config --global USER.EMAIL dev@example.invalid'
idw_each deny "git -C <dir> config --global" 'git -C sub config --global user.email dev@example.invalid'
idw_each deny "git config --global in a later segment" 'cd sub && git config --global core.hooksPath .hooks'
idw_each deny "git config --global --remove-section user" 'git config --global --remove-section user'
idw_each deny "git config rename-section includeIf" \
  'git config rename-section --global includeIf.gitdir:~/a/ includeIf.gitdir:~/b/'
idw_each deny "git config --global --edit" 'git config --global --edit'
idw_each deny "an append redirection to ~/.gitconfig" 'echo "[user]" >> ~/.gitconfig'
idw_each deny 'a redirection to $HOME/.gitconfig-work' 'printf x > "$HOME/.gitconfig-work"'
idw_each deny "a redirection to a *.gitconfig file" 'cat <<<x >/placeholder/work.gitconfig'
idw_each deny "tee -a ~/.gitconfig" 'printf x | tee -a ~/.gitconfig'
idw_each deny "touch a *.gitconfig file" 'touch ~/identities/work.gitconfig'
idw_each deny "cp to ~/.gitconfig" 'cp /placeholder/template ~/.gitconfig'
idw_each deny "cp -t naming a *.gitconfig destination" 'cp -t ~/.gitconfig.d/x.gitconfig /placeholder/template'
idw_each deny "ln -sf onto ~/.gitconfig" 'ln -sf /placeholder/dotfiles/gitconfig ~/.gitconfig'
idw_each deny "cp -T is --no-target-directory, the last operand is the destination" 'cp -T /placeholder/template ~/.gitconfig'
idw_each deny "ln -T onto ~/.gitconfig" 'ln -T /placeholder/dotfiles/gitconfig ~/.gitconfig'
idw_each deny "mv ~/.gitconfig away" 'mv ~/.gitconfig ~/.gitconfig.bak'
idw_each deny "rm ~/.gitconfig" 'rm -f ~/.gitconfig'
idw_each deny "sed -i on ~/.gitconfig" "sed -i 's/a/b/' ~/.gitconfig" # portability-ok: command text the guard reads, never run
idw_each deny "perl -pi -e on a *.gitconfig file" "perl -pi -e 's/a/b/' /placeholder/work.gitconfig"
idw_each deny "dd of=~/.gitconfig" 'dd if=/placeholder/template of=~/.gitconfig'
idw_each deny "sudo tee" 'sudo tee ~/.gitconfig'
idw_each deny "an &> redirection, which the parse splits" 'echo x &> ~/.gitconfig'
idw_each deny "an &>> redirection" 'echo x &>>~/.gitconfig'
idw_each deny "a >| redirection" 'echo x >| ~/.gitconfig'
idw_each deny "perl -pi.bak" "perl -pi.bak -e 's/a/b/' ~/.gitconfig"
idw_each deny "sed -Ei.bak" "sed -Ei.bak 's/a/b/' ~/.gitconfig" # portability-ok: command text the guard reads, never run
idw_each deny "rsync -t is --times, the last operand is the destination" 'rsync -t /placeholder/template ~/.gitconfig'
idw_each deny "PowerShell: Copy-Item -Dest" 'Copy-Item C:\placeholder\template -Dest ~\.gitconfig' PowerShell
idw_each deny "PowerShell: Copy-Item -Destination:<path>" 'Copy-Item C:\placeholder\template -Destination:~\.gitconfig' PowerShell
idw_each deny "PowerShell: Set-Content to ~/.gitconfig" 'Set-Content -Path $env:USERPROFILE\.gitconfig -Value x' PowerShell
idw_each deny "PowerShell: git config --global" 'git config --global user.email dev@example.invalid' PowerShell
idw_each deny "PowerShell: Copy-Item -Destination ~/.gitconfig" \
  'Copy-Item -Path C:\placeholder\template -Destination ~\.gitconfig' PowerShell
for form in "--global --get user.email" "--global user.email" "--global --list" "-l --global" "get --global user.email" \
  "list --global" "--global --get-regexp includeIf" "--global --get-all credential.helper" \
  "--global --get-urlmatch credential.helper https://example.invalid" "--file ~/.gitconfig --get user.email"; do
  idw_each allow "git config $form reads" "git config $form"
done
idw_each allow "git config --local user.email" 'git config --local user.email dev@example.invalid'
idw_each allow "git config user.email, the repository's own" 'git config user.email dev@example.invalid'
idw_each allow "git config --global user.name, no identity key" 'git config --global user.name Dev'
idw_each allow "git config --file <a file that is no identity file>" 'git config --file .gitmodules user.email x'
idw_each allow "git -c user.email= sets no file" 'git -c user.email=dev@example.invalid commit -m wip'
idw_each allow "the write in a commit message" 'git commit -m "git config --global user.email dev@example.invalid"'
idw_each allow "cat ~/.gitconfig" 'cat ~/.gitconfig'
idw_each allow "cp from ~/.gitconfig" 'cp ~/.gitconfig /placeholder/backup'
idw_each allow "cp -T from ~/.gitconfig" 'cp -T ~/.gitconfig /placeholder/backup'
idw_each allow "Copy-Item from ~/.gitconfig" 'Copy-Item -Path ~\.gitconfig -Destination C:\placeholder\kept' PowerShell
idw_each allow "an echo of ~/.gitconfig" 'echo ~/.gitconfig'
idw_each allow "sed without -i on ~/.gitconfig" "sed -n '1p' ~/.gitconfig" # portability-ok: command text the guard reads, never run
idw_each allow "a .gitconfig file below a directory other than HOME's" 'touch /placeholder/.gitconfig-x'
idw_each allow "a bare .gitconfig outside HOME" 'touch /placeholder/repo/.gitconfig'
idw_each allow "perl -M and -n read" "perl -Mstrict -ne 'print' ~/.gitconfig"
idw_each allow "rsync -t from ~/.gitconfig" 'rsync -t ~/.gitconfig /placeholder/kept'
idw_each allow "scp to another host's ~/.gitconfig" 'scp ~/.gitconfig host.example.invalid:~/.gitconfig'
idw_each allow "a redirection from ~/.gitconfig" 'grep email < ~/.gitconfig'
# The map's identity_files: a path in the list, or below it, is an identity
# file only where there is a map.
idw "touch below a listed identity file, neutral cwd" deny "$NEUTRAL" 'touch /placeholder/identity/work'
idw "touch below a listed identity file, domain cwd" deny "$A_ROOT/repo" 'touch /placeholder/identity/work'
assert_contains "a listed identity file's name hits the prefilter" "$GUARD_ERR" "trace write-hit"
idw "git config --file <a listed identity file>" deny "$NEUTRAL" \
  'git config --file /placeholder/identity user.email dev@example.invalid'
idw "touch below a listed identity file, no map" allow "$NEUTRAL" 'touch /placeholder/identity/work' "$NO_MAP"
idw "a listed identity file's longer name" allow "$NEUTRAL" 'touch /placeholder/identityx'
# The trace and the dispatcher.
idw "no map, an identity write" deny "$NEUTRAL" 'git config --global user.email dev@example.invalid' "$NO_MAP"
assert_contains "no map, an identity write: the write prefilter hits" "$GUARD_ERR" "trace write-hit"
assert_contains "no map, an identity write: the parser runs" "$GUARD_ERR" "trace parse"
assert_absent "no map, an identity write: no map is compiled" "$GUARD_ERR" "trace map-"
assert_contains "the reason names the write" "$IDW_REASON" "git config --global user.email"
for data in "$DATA" "$NO_MAP"; do
  guard_invoke --via dispatched --cwd "$NEUTRAL" --command 'git config --global user.email dev@example.invalid' -- \
    "CLAUDE_PLUGIN_DATA=$data" "HOME=$HOME_DIR"
  assert_exit "dispatched, an identity write ($data): exit 0" 0 "$GUARD_RC"
  assert_contains "dispatched, an identity write ($data): denied" "$GUARD_OUT" '"permissionDecision":"deny"'
done
tel "an identity write from a neutral cwd" "$NEUTRAL" 'git config --global user.email dev@example.invalid' \
  identity-write-deny neutral blocked
tel "an identity write from a domain cwd" "$A_ROOT/repo" 'echo x >> ~/.gitconfig' identity-write-deny domain blocked
tel "an identity read" "$NEUTRAL" 'git config --global --get user.email' not-named neutral ok

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
ONE='"domains": {"alpha": {"roots": {}}, "beta": {"roots": {}}}'
malformed "shared exceptions not an array" "{$ONE, \"shared_exceptions\": {}}" "shared_exceptions is not an array"
malformed "a shared exception with no to" "{$ONE, \"shared_exceptions\": [{\"path\": \"/x\", \"from\": [\"alpha\"]}]}" \
  "shared_exceptions[0] needs path, from and to"
malformed "a shared exception with an unknown key" \
  "{$ONE, \"shared_exceptions\": [{\"path\": \"/x\", \"from\": [\"alpha\"], \"to\": \"beta\", \"both\": true}]}" \
  "shared_exceptions[0] has an unknown key, both"
malformed "a shared exception to no domain" "{$ONE, \"shared_exceptions\": [{\"path\": \"/x\", \"from\": [\"alpha\"], \"to\": \"nope\"}]}" \
  "shared_exceptions[0].to names no domain of the map"
malformed "a shared exception from no domain" "{$ONE, \"shared_exceptions\": [{\"path\": \"/x\", \"from\": [\"nope\"], \"to\": \"beta\"}]}" \
  "shared_exceptions[0].from names no domain of the map"
malformed "a shared exception from nothing" "{$ONE, \"shared_exceptions\": [{\"path\": \"/x\", \"from\": [], \"to\": \"beta\"}]}" \
  "shared_exceptions[0].from is empty"
malformed "a shared exception from its own to" "{$ONE, \"shared_exceptions\": [{\"path\": \"/x\", \"from\": [\"beta\"], \"to\": \"beta\"}]}" \
  "shared_exceptions[0].from holds its to"
malformed "a shared exception string on two lines" "{$ONE, \"shared_exceptions\": [\"a\\nb\"]}" \
  "shared_exceptions[0] is not a non-empty one-line string"

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
guard_invoke --cwd "$NEUTRAL" --command 'git config --global user.email dev@example.invalid' -- \
  "CLAUDE_PLUGIN_DATA=$NO_MAP" "BASH_ENV=$HIDE_JQ" "CLAUDE_PLUGIN_ROOT=$HOOK_DIR/.."
assert_exit "jq hidden, no map, an identity write: exit 0" 0 "$GUARD_RC"
assert_absent "jq hidden, no map, an identity write: no deny" "$GUARD_OUT" permissionDecision
assert_contains "jq hidden, no map, an identity write: the user is told jq is missing" \
  "$(jq -r '.systemMessage // empty' <<<"$GUARD_OUT")" "jq not on the hook PATH"

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
# The owner directories sit below HOME, so the same map under another HOME is
# compiled again, and the owner below the new HOME is the one denied.
OTHER_HOME="$TEST_TMPDIR/other-home"
call "$EDIT" "$A_ROOT/repo" "ls $OTHER_HOME/src/github.com/beta-org/repo" "HOME=$OTHER_HOME"
assert_contains "the same map under another HOME is compiled again" "$GUARD_ERR" "trace map-compile"
verdict "another domain's owner below the new HOME" deny

# --- Under the dispatcher, and on the shipped row -----------------------------
guard_invoke --via dispatched --cwd "$A_ROOT/repo" --command "ls $B_ROOT" -- \
  "CLAUDE_PLUGIN_DATA=$DATA" GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR"
assert_exit "dispatched, another domain's root: exit 0" 0 "$GUARD_RC"
assert_contains "dispatched, another domain's root: the parser runs" "$GUARD_ERR" "trace parse"
verdict "dispatched, another domain's root" deny
guard_invoke --via dispatched --cwd "$A_ROOT/repo" --command "ls $A_ROOT/repo/src" -- \
  "CLAUDE_PLUGIN_DATA=$DATA" GUARDRAILS_CROSS_DOMAIN_TRACE=1 "HOME=$HOME_DIR"
assert_exit "dispatched, the cwd's own root: exit 0" 0 "$GUARD_RC"
verdict "dispatched, the cwd's own root" allow
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
assert_exit "the shipped row, another domain's root: exit 0" 0 "$row_rc"
assert_eq "the shipped row, another domain's root: one document on stdout" 1 "$(jq -s 'length' <<<"$row_out")"
assert_eq "the shipped row, another domain's root: denied" deny \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$row_out")"
assert_contains "the shipped row, another domain's root: the guard parses it" "$(cat "$TEST_TMPDIR/row.err")" "trace parse"

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
  assert_exit "strace: compiled map, another domain's root: exit 0" 0 "$SHARE_RC"
  assert_eq "strace: compiled map, another domain's root parsed and denied: the guard's process creations" 0 "$SHARE_CREATIONS"
  assert_eq "strace: compiled map, another domain's root parsed and denied: the guard's execve count" 0 "$SHARE_EXECVE"

  census_share "git remote add origin git@example.invalid:beta-org/repo.git" "$CENSUS"
  assert_exit "strace: compiled map, an identity position denied: exit 0" 0 "$SHARE_RC"
  assert_eq "strace: compiled map, an identity position denied: the guard's process creations" 0 "$SHARE_CREATIONS"
  assert_eq "strace: compiled map, an identity position denied: the guard's execve count" 0 "$SHARE_EXECVE"

  census_share "gh pr list" "$CENSUS"
  assert_exit "strace: compiled map, gh without its directory denied: exit 0" 0 "$SHARE_RC"
  assert_eq "strace: compiled map, gh without its directory denied: the guard's process creations" 0 "$SHARE_CREATIONS"
  assert_eq "strace: compiled map, gh without its directory denied: the guard's execve count" 0 "$SHARE_EXECVE"

  for data in "$NO_MAP" "$CENSUS"; do
    census_share "git config --global user.email dev@example.invalid" "$data"
    assert_exit "strace: an identity write denied ($data): exit 0" 0 "$SHARE_RC"
    assert_eq "strace: an identity write denied ($data): the guard's process creations" 0 "$SHARE_CREATIONS"
    assert_eq "strace: an identity write denied ($data): the guard's execve count" 0 "$SHARE_EXECVE"
  done
else
  echo "ok: process-creation pins skipped (no working strace on this host)"
fi

report
