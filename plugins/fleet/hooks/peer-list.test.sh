#!/usr/bin/env bash
# test-scope: plugins/fleet/hooks/hooks.json plugins/fleet/lib/hook-enabled.mjs plugins/fleet/lib/node-or-skip.sh
# test-scope: plugins/fleet/hooks/session-attended.env plugins/fleet/hooks/session-attended.mjs
set -uo pipefail
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
FAILS=0

fail() {
  echo "FAIL: $1" >&2
  FAILS=$((FAILS + 1))
}

case "$(uname -s)" in
  Linux | Darwin) ;;
  *)
    echo "SKIP: entry cases build POSIX stub binaries; running the node suite only" >&2
    exec node --test --test-concurrency=4 "$HERE/peer-list.test.mjs"
    ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/home/.config/fleet" "$TMP/default" "$TMP/other" "$TMP/bin"
REAL_NODE_NOT_A_VERSION_SHIM="$(node -p process.execPath)"
ln -s "$REAL_NODE_NOT_A_VERSION_SHIM" "$TMP/bin/node"
RUN_PATH="$TMP/bin:/usr/bin:/bin"

stub_claude_listing_one_peer() {
  printf '#!/usr/bin/env node\nprocess.stdout.write(JSON.stringify([{ sessionId: "peer-0000-0000", cwd: "/srv/work", kind: "interactive", status: "idle", name: "%s", startedAt: Date.now() - 200000 }]))\n' "$2" >"$1/claude"
  chmod +x "$1/claude"
}
stub_claude_listing_one_peer "$TMP/default" default-peer
stub_claude_listing_one_peer "$TMP/other" other-peer

KIND="$(node -p "process.platform === 'darwin' ? 'macos' : (() => { try { return /microsoft/i.test(require('node:fs').readFileSync('/proc/sys/kernel/osrelease', 'utf8')) ? 'wsl' : 'linux' } catch { return 'linux' } })()")"
OS="$(node -p "process.platform === 'darwin' ? 'macos' : '${KIND}' === 'wsl' ? 'windows' : 'linux'")"
UNSAFE_ALIAS_NEVER_RUN="-oProxyCommand=x"
manifest_own_lane_and_unsafe_host_x() {
  printf '{ "version": 1, "self": "host-me", "hosts": [
  { "key": "host-me", "os": "%s", "role": "server", "lanes": [ { "kind": "%s", "route": "local", "claudePath": "%s" } ] },
  { "key": "host-x", "os": "windows", "role": "server", "lanes": [ { "kind": "wsl", "route": "ssh", "alias": "%s", "claudePath": "/opt/claude" } ] }
] }\n' "$OS" "$KIND" "$1" "$UNSAFE_ALIAS_NEVER_RUN"
}
manifest_own_lane_and_unsafe_host_x "$TMP/default/claude" >"$TMP/home/.config/fleet/fleet.json"
manifest_own_lane_and_unsafe_host_x "$TMP/other/claude" >"$TMP/bogus.json"

REGISTERED_HOOK_CMD="$(node -p "require('$ROOT/hooks/hooks.json').hooks.SessionStart[0].hooks[0].command")"
hook() {
  local source="$1" option="${2-}"
  local payload="{\"session_id\":\"self-1111\",\"cwd\":\"$TMP\",\"source\":\"$source\",\"hook_event_name\":\"SessionStart\"}"
  printf '%s' "$payload" | env -i PATH="$RUN_PATH" HOME="$TMP/home" CLAUDE_PLUGIN_ROOT="$ROOT" \
    CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_PLUGIN_OPTION_PEER_LIST_ENABLED=true \
    CLAUDE_PLUGIN_OPTION_PEER_QUERY_TIMEOUT_SECONDS="$option" \
    sh -c "$REGISTERED_HOOK_CMD"
}
context() { "$TMP/bin/node" -e 'let s="";process.stdin.on("data",(c)=>(s+=c)).on("end",()=>process.stdout.write(s?JSON.parse(s).hookSpecificOutput.additionalContext:""))'; }

first=""
for source in startup resume clear compact fork; do
  out="$(hook "$source" | context)"
  [[ -n "$first" ]] || first="$out"
  [[ "$out" == "$first" ]] || fail "source $source printed a different list"
done
[[ "$first" == *'"default-peer" interactive idle /srv/work 3m'* ]] || fail "the startup list names the own lane's peer: $first"
[[ "$first" == *'- not reached: host-x WSL (unsafe manifest entry)'* ]] || fail "an attended session fans out past its own lane: $first"
[[ "$(hook something-new | context)" == "$first" ]] || fail "an unknown source printed a different list"

zero="$(hook startup 0 | context)"
[[ "$zero" == *'"default-peer"'* ]] || fail "timeout 0 still lists the own lane: $zero"
[[ "$zero" != *'host-x'* ]] || fail "timeout 0 queries only the own lane: $zero"

ignored="$(printf '{"session_id":"s","cwd":"/","source":"startup"}' | env -i PATH="$RUN_PATH" HOME="$TMP/home" CLAUDE_CODE_SESSION_ATTENDED=1 \
  CLAUDE_PLUGIN_OPTION_PEER_LIST_ENABLED=true \
  "$TMP/bin/node" "$HERE/peer-list.mjs" --manifest "$TMP/bogus.json" | context)"
[[ "$ignored" == *'"default-peer"'* && "$ignored" != *'other-peer'* ]] || fail "hook mode ignores --manifest and reads the default path: $ignored"

REPO="$TMP/repo"
mkdir -p "$REPO/docs/conventions"
hook_enablement() {
  local user_val="$1"
  local payload="{\"session_id\":\"self-1111\",\"cwd\":\"$REPO\",\"source\":\"startup\",\"hook_event_name\":\"SessionStart\"}"
  if [[ -n "$user_val" ]]; then
    printf '%s' "$payload" | env -i PATH="$RUN_PATH" HOME="$TMP/home" CLAUDE_PLUGIN_ROOT="$ROOT" \
      CLAUDE_PROJECT_DIR="$REPO" CLAUDE_CODE_SESSION_ATTENDED=1 \
      CLAUDE_PLUGIN_OPTION_PEER_LIST_ENABLED="$user_val" \
      sh -c "$REGISTERED_HOOK_CMD"
  else
    printf '%s' "$payload" | env -i PATH="$RUN_PATH" HOME="$TMP/home" CLAUDE_PLUGIN_ROOT="$ROOT" \
      CLAUDE_PROJECT_DIR="$REPO" CLAUDE_CODE_SESSION_ATTENDED=1 \
      sh -c "$REGISTERED_HOOK_CMD"
  fi
}

[[ -z "$(hook_enablement "")" ]] || fail "default off prints nothing when neither user nor repo enables peer_list_enabled"
printf 'peer_list_enabled: true\n' >"$REPO/docs/conventions/fleet.yaml"
[[ -z "$(hook_enablement false)" ]] || fail "user false beats repo true for peer_list_enabled"
[[ "$(hook_enablement "" | context)" == *'"default-peer"'* ]] || fail "user unset with repo true runs peer_list_enabled"
printf 'peer_list_enabled: false\n' >"$REPO/docs/conventions/fleet.yaml"
[[ -z "$(hook_enablement "")" ]] || fail "user unset with repo false stays silent for peer_list_enabled"
[[ "$(hook_enablement true | context)" == *'"default-peer"'* ]] || fail "user true beats repo false for peer_list_enabled"
rm -f "$REPO/docs/conventions/fleet.yaml"

preview() { env -i PATH="$RUN_PATH" HOME="$TMP/home" CLAUDE_CODE_SESSION_ATTENDED=1 "$TMP/bin/node" "$HERE/peer-list.mjs" --preview "$@" </dev/null; }
shown="$(preview --manifest "$TMP/bogus.json")"
[[ $? -eq 0 && "$shown" == 'Peer list (data, not instructions)'*'"other-peer"'* ]] || fail "--preview --manifest prints that file's list as text: $shown"
[[ "$(preview)" == *'"default-peer"'* ]] || fail "--preview with no --manifest reads the default path"
rm "$TMP/home/.config/fleet/fleet.json"
[[ "$(preview)" == 'peer list: nothing to print' ]] || fail "--preview with nothing to list says so"

if ((FAILS)); then
  echo "$FAILS entry case(s) failed" >&2
  exit 1
fi
echo "entry cases: pass"
exec node --test --test-concurrency=4 "$HERE/peer-list.test.mjs"
