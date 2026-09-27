#!/usr/bin/env bash
# Self-contained tests for inventory.sh (no external test lib; ships with the plugin).
# Every location flag is passed explicitly and HOME points at a fixture directory,
# so no run reads the real ~/.claude.json or managed policy.
set -uo pipefail

unset CLAUDE_PROJECT_DIR CLAUDE_CONFIG_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INV="$SCRIPT_DIR/inventory.sh"

TEST_TMPDIR="$(mktemp -d 2>/dev/null)" || TEST_TMPDIR=""
if [[ -z "$TEST_TMPDIR" || ! -d "$TEST_TMPDIR" ]]; then
  echo "inventory.test.sh: mktemp -d failed; refusing to write fixtures" >&2
  exit 2
fi
trap 'rm -rf -- "${TEST_TMPDIR:?}"' EXIT

FAILED=0
CASE=0

pass() {
  CASE=$((CASE + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE=$((CASE + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1" "expected [$2], got [$3]"
  fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "must not contain: $3" ;;
  *) pass "$1" ;;
  esac
}

# Fixture root contains a space so every path flag is exercised with one.
FIX="$TEST_TMPDIR/fix dir"
mkdir -p "$FIX/home" "$FIX/proj" "$FIX/plugin dir" "$FIX/empty bin" \
  "$FIX/managed one/managed-settings.d" "$FIX/managed two"
export HOME="$FIX/home"

OUT=""
ERR=""
RC=0
ALL=""
# run_inv <args...>: run the script, capturing stdout, stderr, and exit code.
run_inv() {
  OUT="$(bash "$INV" "$@" 2>"$FIX/stderr.txt")"
  RC=$?
  ERR="$(<"$FIX/stderr.txt")"
  ALL+="$OUT$ERR"
}
# find_row <scope> <name>: set FIELDS to the tab-split fields of the first row matching scope
# and name (empty when none). Pure parameter expansion: no subshell or external process, which
# keeps the suite fast where process creation is slow (Git Bash on Windows).
FIELDS=()
find_row() {
  local rest="$OUT"$'\n' line
  FIELDS=()
  while [[ -n "$rest" ]]; do
    line="${rest%%$'\n'*}"
    rest="${rest#*$'\n'}"
    if [[ "$line" == "$1"$'\t'"$2"$'\t'* ]]; then
      line+=$'\t'
      while [[ -n "$line" ]]; do
        FIELDS+=("${line%%$'\t'*}")
        line="${line#*$'\t'}"
      done
      return 0
    fi
  done
}
# cell <scope> <name> <column>: one field of the first row matching scope and name.
cell() {
  find_row "$1" "$2"
  printf '%s' "${FIELDS[$(($3 - 1))]:-}"
}
# check_row <name> <launcher> <package> <pin> <publisher>: a file-scope row's classification.
check_row() {
  find_row file "$1"
  assert_eq "$1 launcher" "$2" "${FIELDS[4]:-}"
  assert_eq "$1 package" "$3" "${FIELDS[5]:-}"
  assert_eq "$1 pin" "$4" "${FIELDS[6]:-}"
  assert_eq "$1 publisher" "$5" "${FIELDS[7]:-}"
}

# --- Fixtures ---------------------------------------------------------------

cat >"$FIX/claude.json" <<'JSON'
{
  "mcpServers": {
    "shared": {"command": "npx", "args": ["-y", "shared-user@1.0.0"]},
    "pu": {"command": "npx", "args": ["pu-user@1.0.0"]},
    "useronly": {"command": "uvx", "args": ["useronly==1.0.0"]},
    "dis": {"command": "npx", "args": ["dis@1.0.0"]},
    "corp": {"command": "npx", "args": ["corp-user@1.0.0"]},
    "ghp_LEAKNAMEDIS1": {"command": "npx", "args": ["gh@1.0.0"]},
    "evil\tna\nme\u001b[31m": {"command": "npx", "args": ["ctl@1.0.0"]}
  },
  "projects": {
    "C:\u005cWork\u005cProj": {
      "mcpServers": {
        "shared": {"command": "npx", "args": ["shared-local@1.0.0"]},
        "localonly": {"command": "npx", "args": ["localonly@1.0.0"]}
      },
      "disabledMcpServers": ["dis", "projdis", "override", "ghp_LEAKNAMEDIS1"],
      "disabledMcpjsonServers": ["rejected"],
      "enabledMcpjsonServers": ["pu", "projdis"]
    },
    "D:\u005cAll": {"enableAllProjectMcpServers": true},
    "/other/project": {
      "mcpServers": {"otherproj": {"command": "npx", "args": ["other@1.0.0"]}}
    }
  }
}
JSON

cat >"$FIX/proj/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "shared": {"command": "npx", "args": ["shared-project@1.0.0"]},
    "pu": {"command": "npx", "args": ["pu-project@1.0.0"]},
    "projonly": {"command": "npx", "args": ["projonly@1.0.0"]},
    "rejected": {"command": "npx", "args": ["rejected@1.0.0"]},
    "projdis": {"command": "npx", "args": ["projdis@1.0.0"]}
  }
}
JSON

cat >"$FIX/servers a.json" <<'JSON'
{
  "mcpServers": {
    "npx-bare": {"command": "npx", "args": ["-y", "bare-mcp"]},
    "npx-latest": {"command": "npx", "args": ["-y", "tag-mcp@latest"]},
    "npx-next": {"command": "npx", "args": ["tag-mcp@next"]},
    "npx-caret": {"command": "npx", "args": ["r-mcp@^1.2.0"]},
    "npx-tilde": {"command": "npx", "args": ["r-mcp@~1.2.0"]},
    "npx-xrange": {"command": "npx", "args": ["r-mcp@1.x"]},
    "npx-partial": {"command": "npx", "args": ["r-mcp@1.2"]},
    "npx-exact": {"command": "npx", "args": ["--yes", "e-mcp@1.2.3"]},
    "npx-pre": {"command": "npx", "args": ["e-mcp@1.2.3-beta.1"]},
    "npx-scoped-exact": {"command": "npx", "args": ["-y", "@acme/mcp-server@2.0.0"]},
    "npx-scoped-bare": {"command": "npx", "args": ["@acme/mcp-server"]},
    "npx-package-eq": {"command": "npx", "args": ["--package=@acme/tool@1.0.0", "acme-bin"]},
    "npx-package-p": {"command": "npx", "args": ["-p", "p-mcp@3.0.0", "p-bin"]},
    "npx-secrets": {
      "command": "npx",
      "args": ["--registry=https://tok:SECRETREG1@reg.example.com/", "--registry", "https://SECRETREG2@reg.example.com/",
               "-y", "s-mcp@1.0.0", "--api-key", "SECRETAPIKEY1"],
      "env": {"API_TOKEN": "SECRETENV1"}
    },
    "npx-alias": {"command": "npx", "args": ["alias@npm:real-mcp@1.0.0"]},
    "npx-alias-scoped": {"command": "npx", "args": ["alias@npm:@acme/real@1.0.0"]},
    "npx-local": {"command": "npx", "args": ["./server-dir"]},
    "npx-file": {"command": "npx", "args": ["file:../pkg"]},
    "npx-github": {"command": "npx", "args": ["github:owner/repo"]},
    "npx-userrepo": {"command": "npx", "args": ["owner/repo"]},
    "npx-gitcommit": {"command": "npx", "args": ["git+https://github.com/o/r.git#0123456789abcdef0123456789abcdef01234567"]},
    "npx-tarball": {"command": "npx", "args": ["https://user:SECRETTGZ1@host.example.com/x.tgz?sig=SECRETQTGZ1#SECRETFRAG1"]},
    "cmd-wrap": {"command": "cmd", "args": ["/c", "npx", "-y", "w-mcp@1.0.0"]},
    "cmdexe-wrap": {"command": "C:\u005cWindows\u005cSystem32\u005cCMD.EXE", "args": ["/C", "npx", "w-mcp@latest"]},
    "npx-cmd": {"command": "npx.cmd", "args": ["-y", "c-mcp@1.0.0"]},
    "bash-wrap": {"command": "bash", "args": ["-c", "npx -y b-mcp@latest --api-key SECRETBASH1"]},
    "npm-exec": {"command": "npm", "args": ["exec", "--yes", "--", "ne-mcp@1.0.0"]},
    "pnpm-dlx": {"command": "pnpm", "args": ["dlx", "pd-mcp@^2.0.0"]},
    "pnpx-bare": {"command": "pnpx", "args": ["px-mcp"]},
    "pnpx-exact": {"command": "pnpx", "args": ["px-mcp@1.0.0"]},
    "yarn-dlx": {"command": "yarn", "args": ["dlx", "yd-mcp"]},
    "bunx": {"command": "bunx", "args": ["bx-mcp@1.0.0"]},
    "uvx-bare": {"command": "uvx", "args": ["mcp-server-fetch"]},
    "uvx-eq": {"command": "uvx", "args": ["mcp-server-fetch==1.2.3"]},
    "uvx-at": {"command": "uvx", "args": ["mcp-server-fetch@1.2.3"]},
    "uvx-latest": {"command": "uvx", "args": ["mcp-server-fetch@latest"]},
    "uvx-range": {"command": "uvx", "args": ["mcp-server-fetch>=1.0"]},
    "uvx-extras": {"command": "uvx", "args": ["mcp-x[cli]==1.0.0"]},
    "uvx-from": {"command": "uvx", "args": ["--from", "git+https://SECRETFROM1@git.example.com/x.git", "xcmd"]},
    "uvx-from-exact": {"command": "uvx", "args": ["--python", "3.12", "--from", "fx==2.0.0", "fx-cmd"]},
    "uvx-index": {"command": "uvx", "args": ["--index-url", "https://u:SECRETIDX1@pypi.example.com/simple", "ix==1.0.0"]},
    "uv-tool-run": {"command": "uv", "args": ["tool", "run", "ut==1.0.0"]},
    "pipx-spec": {"command": "pipx", "args": ["run", "--spec", "px==1.0.0", "px-cmd"]},
    "pipx-bare": {"command": "pipx", "args": ["run", "pxb"]},
    "docker-digest": {"command": "docker", "args": ["run", "-i", "--rm", "-e", "API_KEY=SECRETDOCKER1",
      "ghcr.io/acme/server@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"]},
    "docker-tagdigest": {"command": "docker", "args": ["run",
      "acme/server:1.0@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"]},
    "docker-latest": {"command": "docker", "args": ["run", "-i", "mcp/fetch:latest"]},
    "docker-untagged": {"command": "docker", "args": ["run", "--rm", "-i", "mcp/fetch"]},
    "docker-library": {"command": "docker", "args": ["run", "alpine"]},
    "docker-fixed": {"command": "docker", "args": ["run", "-i", "--rm", "-v", "/a:/b", "--name", "x", "--env=FOO=bar",
      "--network", "host", "localhost:5000/team/img:1.2"]},
    "docker-port-untagged": {"command": "docker", "args": ["run", "localhost:5000/img"]},
    "podman": {"command": "podman", "args": ["run", "-i", "quay.io/org/img:2"]},
    "nerdctl": {"command": "nerdctl", "args": ["run", "img:latest"]},
    "local": {"command": "/usr/local/bin/my-server", "args": ["--token", "SECRETLOCAL1"]},
    "remote-http": {"type": "http", "url": "https://user:SECRETURLPW1@mcp.example.com:8443/v1/mcp?token=SECRETQUERY1",
      "headers": {"Authorization": "Bearer SECRETHDR1"}},
    "remote-sse": {"type": "sse", "url": "https://sse.example.com/sse"},
    "remote-streamable": {"type": "streamable-http", "url": "https://st.example.com/mcp"},
    "remote-notype": {"url": "https://nt.example.com/mcp"},
    "remote-oauth": {"type": "http", "url": "https://o.example.com/mcp",
      "oauth": {"clientId": "cid", "clientSecret": "SECRETOAUTH1"},
      "headersHelper": "/bin/get-token --key SECRETHELPER1"}
  }
}
JSON

cat >"$FIX/plugin dir/plugin.json" <<'JSON'
{"name": "p", "mcpServers": {"plug": {"command": "npx", "args": ["plug-mcp@1.0.0"]}}}
JSON

cat >"$FIX/managed one/managed-settings.json" <<'JSON'
{"managedMcpServers": {
  "corp": {"type": "http", "url": "https://corp.example.com/mcp"},
  "override": {"type": "http", "url": "https://a.example.com/mcp"}
}}
JSON
cat >"$FIX/managed one/managed-settings.d/10-a.json" <<'JSON'
{"managedMcpServers": {"override": {"type": "http", "url": "https://b.example.com/mcp"}}}
JSON
cat >"$FIX/managed one/managed-settings.d/20-b.json" <<'JSON'
{"managedMcpServers": {"override": {"type": "http", "url": "https://c.example.com/mcp"}}}
JSON

cat >"$FIX/managed two/managed-mcp.json" <<'JSON'
{"mcpServers": {"corpstdio": {"command": "npx", "args": ["corp-mcp@1.0.0"]}}}
JSON

# Review probe: wrappers, URL versions, unknown value flags, non-string args, bidi.
cat >"$FIX/probe cases.json" <<'JSON'
{"mcpServers": {
  "a-bash-env": {"command": "bash", "args": ["-c", "API_KEY=LEAK1 npx -y p@1.0.0"]},
  "b-npx-authtok": {"command": "npx", "args": ["--_authToken", "LEAK2", "p@1.0.0"]},
  "c-npm-giturl": {"command": "npx", "args": ["-y", "p@git+https://tok:LEAK3@github.com/o/r.git"]},
  "d-npm-tgzurl": {"command": "npx", "args": ["-y", "p@https://u:LEAK4@host/x.tgz"]},
  "e-pep508": {"command": "uvx", "args": ["--from", "mcp-x @ git+https://tok:LEAK5@github.com/o/r", "mcp-x"]},
  "f-docker-logopt": {"command": "docker", "args": ["run", "--log-opt", "token=LEAK6", "img:1"]},
  "f2-docker-unknown": {"command": "docker", "args": ["run", "--frobnicate", "SECRETUNK1", "img:1"]},
  "g-uvx-i": {"command": "uvx", "args": ["-i", "https://pypi.example.com/simple", "pkg==1.0"]},
  "h-bash-lc": {"command": "bash", "args": ["-lc", "npx -y floaty@latest"]},
  "i-cmd-dsc": {"command": "cmd.exe", "args": ["/d", "/s", "/c", "npx -y floaty@latest"]},
  "j-env": {"command": "env", "args": ["X=1", "npx", "-y", "floaty"]},
  "k-docker-mem": {"command": "docker", "args": ["run", "--memory", "512m", "-i", "mcp/x"]},
  "l-bash-quoted": {"command": "bash", "args": ["-c", "npx -y 'q@1.0.0'"]},
  "m-args-obj": {"command": "npx", "args": [{"k": "LEAK7"}]},
  "n-bidi": {"command": "npx", "args": ["x\u202e@1.0.0"]},
  "o-pwsh": {"command": "powershell", "args": ["-NoProfile", "-Command", "npx -y floaty"]},
  "p-docker-sha-only": {"command": "docker", "args": ["run", "img@sha256:abc"]},
  "q-uvx-star": {"command": "uvx", "args": ["pkg==1.*"]},
  "r-npx-v": {"command": "npx", "args": ["pkg@v1.2.3"]},
  "s-py-eq3": {"command": "uvx", "args": ["pkg===1.0"]},
  "t-npx-ws": {"command": "npx", "args": ["-w", "LEAK8", "pkg@1.0.0"]},
  "u-bash-combined": {"command": "sh", "args": ["-ec", "npx -y u@1.0.0"]},
  "v-local-wrapped": {"command": "node", "args": ["run.js", "npx", "-y", "z"]},
  "w-npx-assign": {"command": "npx", "args": ["API_KEY=SECRETSHAPE1"]},
  "x-docker-assign": {"command": "docker", "args": ["run", "-i", "FOO=SECRETSHAPE2"]},
  "bidi\u202ename": {"command": "npx", "args": ["bidi@1.0.0"]}
}}
JSON

# --- Run 1: every source, no managed-mcp.json -------------------------------

run_inv --claude-json "$FIX/claude.json" --project "c:/work/proj" --mcp-json "$FIX/proj/.mcp.json" \
  --managed-dir "$FIX/managed one" --config "$FIX/servers a.json" --config "$FIX/plugin dir/plugin.json" \
  --config "$FIX/nope.json" --config "$FIX/probe cases.json" --date 2026-01-02

assert_eq "run 1 exits 0" 0 "$RC"
assert_eq "line 1 is the dated title" "# mcp-posture inventory 2026-01-02" "$(printf '%s\n' "$OUT" | sed -n 1p)"
assert_eq "line 2 is the TSV header" $'scope\tname\teffective\ttransport\tlauncher\tpackage\tpin\tpublisher\tsandboxed' \
  "$(printf '%s\n' "$OUT" | sed -n 2p)"

rows="$(printf '%s\n' "$OUT" | sed -n '3,$p' | grep -v '^#')"
assert_eq "rows sorted by scope then name" "$(printf '%s\n' "$rows" | cut -f1,2 | LC_ALL=C sort)" \
  "$(printf '%s\n' "$rows" | cut -f1,2)"
assert_eq "every row has nine fields and a known scope" "" \
  "$(printf '%s\n' "$rows" | awk -F'\t' 'NF != 9 || $1 !~ /^(managed|managed-settings|local|project|user|file)$/')"
assert_eq "no comment line between rows" "" \
  "$(printf '%s\n' "$OUT" | sed -n '3,$p' | awk '/^#/ { seen = 1; next } seen { print }')"

# Effective states.
assert_eq "local shared wins" "yes" "$(cell local shared 3)"
assert_eq "project shared shadowed by local" "shadowed-by:local" "$(cell project shared 3)"
assert_eq "user shared shadowed by local" "shadowed-by:local" "$(cell user shared 3)"
assert_eq "project pu wins over user" "yes" "$(cell project pu 3)"
assert_eq "user pu shadowed by project" "shadowed-by:project" "$(cell user pu 3)"
assert_eq "disabledMcpServers marks a user server disabled" "disabled" "$(cell user dis 3)"
assert_eq "disabledMcpjsonServers marks a project server disabled" "disabled" "$(cell project rejected 3)"
assert_eq "unapproved project server is approval-unknown" "approval-unknown" "$(cell project projonly 3)"
assert_eq "enabledMcpjsonServers approves a project server" "yes" "$(cell project pu 3)"
assert_eq "disabledMcpServers does not disable a project server" "yes" "$(cell project projdis 3)"
assert_eq "disabledMcpServers disables a managed-settings server" "disabled" "$(cell managed-settings override 3)"
assert_eq "user-only server effective" "yes" "$(cell user useronly 3)"
assert_eq "file server effective without managed-mcp.json" "yes" "$(cell file npx-bare 3)"
assert_eq "managed-settings server effective" "yes" "$(cell managed-settings corp 3)"
assert_eq "user row shadowed by a managed-settings row" "shadowed-by:managed-settings" "$(cell user corp 3)"
assert_eq "secret-shaped name redacted, still matched by disabledMcpServers" "disabled" \
  "$(cell user 'redacted-name(16)' 3)"

# Local-scope key matching: C:\Work\Proj key matches the lowercase forward-slash --project.
assert_eq "local key matched case-insensitively" "localonly@1.0.0" "$(cell local localonly 6)"
assert_not_contains "other project's local servers not read" "$OUT" "otherproj"
assert_contains "user source line" "$OUT" "# source user $FIX/claude.json found"
assert_contains "local source line" "$OUT" "# source local $FIX/claude.json found"
assert_contains "project source line" "$OUT" "# source project $FIX/proj/.mcp.json found"
assert_contains "managed-mcp.json absent reported" "$OUT" "# source managed $FIX/managed one/managed-mcp.json absent"
assert_contains "managed-settings.json source line" "$OUT" \
  "# source managed-settings $FIX/managed one/managed-settings.json found"
assert_contains "managed-settings.d drop-in source line" "$OUT" \
  "# source managed-settings $FIX/managed one/managed-settings.d/20-b.json found"
assert_contains "absent --config reported, not an error" "$OUT" "# source file $FIX/nope.json absent"
assert_eq "plugin.json inline mcpServers read" "plug-mcp@1.0.0" "$(cell file plug 6)"

# managed-settings.d: later file wins per name.
assert_eq "managed-settings.d later file wins" "https://c.example.com" "$(cell managed-settings override 6)"

# Footer.
assert_contains "not read: MDM" "$OUT" "# not read: MDM/registry/plist policy"
assert_contains "not read: server-managed settings" "$OUT" "# not read: server-managed settings"
assert_contains "not read: claude.ai connectors" "$OUT" "# not read: claude.ai connectors"
assert_contains "not read: --mcp-config" "$OUT" "# not read: --mcp-config"
assert_contains "not read: plugin servers" "$OUT" "# not read: plugin servers not passed as --config"
assert_contains "not evaluated line" "$OUT" \
  "# not evaluated: allowedMcpServers/deniedMcpServers (see /claude-config:audit)"
assert_contains "project approval not evaluated line" "$OUT" \
  "# not evaluated: project approval in settings files (enabledMcpjsonServers, enableAllProjectMcpServers); only the ~/.claude.json project entry is read, so an unapproved project row shows approval-unknown"
assert_contains "file-scope precedence not evaluated line" "$OUT" \
  "# not evaluated: file-scope rows are not checked for precedence against other scopes"
assert_contains "drop-in merge not evaluated line" "$OUT" \
  "# not evaluated: managed-settings.d drop-ins are merged by whole entry per name; key-level merging is not modeled"

# Review probe classifications.
check_row a-bash-env npx p@1.0.0 exact unscoped
check_row b-npx-authtok npx - unparsed -
check_row c-npm-giturl npx p@git+https://github.com/o/r.git git-ref github.com
check_row d-npm-tgzurl npx p@https://host/x.tgz tarball host
check_row e-pep508 uvx 'mcp-x @ git+https://github.com/o/r' git-ref github.com
check_row f-docker-logopt docker img:1 mutable-tag library
check_row f2-docker-unknown docker - unparsed -
check_row g-uvx-i uvx pkg==1.0 exact index:pypi.example.com
check_row h-bash-lc npx floaty@latest floating-tag unscoped
check_row i-cmd-dsc npx floaty@latest floating-tag unscoped
check_row j-env npx floaty floating-unversioned unscoped
check_row k-docker-mem docker mcp/x floating-unversioned mcp
check_row l-bash-quoted local - unparsed -
check_row m-args-obj npx - unparsed -
check_row n-bidi npx - unparsed -
check_row o-pwsh npx floaty floating-unversioned unscoped
check_row p-docker-sha-only docker - unparsed -
check_row q-uvx-star uvx 'pkg==1.*' floating-range pypi
check_row r-npx-v npx pkg@v1.2.3 exact unscoped
check_row s-py-eq3 uvx pkg===1.0 exact pypi
check_row t-npx-ws npx pkg@1.0.0 exact unscoped
check_row u-bash-combined npx u@1.0.0 exact unscoped
check_row v-local-wrapped local - wrapped local
check_row w-npx-assign npx - unparsed -
check_row x-docker-assign docker - unparsed -
assert_eq "format-char name redacted by raw length" "bidi@1.0.0" "$(cell file 'redacted-name(9)' 6)"
assert_not_contains "no RLO char in output" "$OUT" $'\xe2\x80\xae'
assert_contains "source with a server map is found" "$OUT" "# source file $FIX/probe cases.json found"

# Control characters in a server name are never printed; the name is redacted.
assert_not_contains "no ESC byte in output" "$OUT" $'\e'
assert_eq "control-char name redacted by raw length" "ctl@1.0.0" "$(cell user 'redacted-name(15)' 6)"

# Transport and sandboxed columns.
assert_eq "stdio transport" "stdio" "$(cell file npx-bare 4)"
assert_eq "stdio sandboxed no" "no" "$(cell file npx-bare 9)"
assert_eq "http transport" "http" "$(cell file remote-http 4)"
assert_eq "remote sandboxed n/a" "n/a" "$(cell file remote-http 9)"
assert_eq "sse transport" "sse" "$(cell file remote-sse 4)"
assert_eq "streamable-http maps to http" "http" "$(cell file remote-streamable 4)"
assert_eq "url without type is http" "http" "$(cell file remote-notype 4)"

# Pin rules and launchers.
check_row npx-bare npx bare-mcp floating-unversioned unscoped
check_row npx-latest npx tag-mcp@latest floating-tag unscoped
check_row npx-next npx tag-mcp@next floating-tag unscoped
check_row npx-caret npx 'r-mcp@^1.2.0' floating-range unscoped
check_row npx-tilde npx 'r-mcp@~1.2.0' floating-range unscoped
check_row npx-xrange npx r-mcp@1.x floating-range unscoped
check_row npx-partial npx r-mcp@1.2 floating-range unscoped
check_row npx-exact npx e-mcp@1.2.3 exact unscoped
check_row npx-pre npx e-mcp@1.2.3-beta.1 exact unscoped
check_row npx-scoped-exact npx @acme/mcp-server@2.0.0 exact @acme
check_row npx-scoped-bare npx @acme/mcp-server floating-unversioned @acme
check_row npx-package-eq npx @acme/tool@1.0.0 exact @acme
check_row npx-package-p npx p-mcp@3.0.0 exact unscoped
check_row npx-secrets npx s-mcp@1.0.0 exact unscoped
check_row npx-alias npx alias@npm:real-mcp@1.0.0 exact unscoped
check_row npx-alias-scoped npx alias@npm:@acme/real@1.0.0 exact @acme
check_row npx-local npx ./server-dir local-path local
check_row npx-file npx file:../pkg local-path local
check_row npx-github npx github:owner/repo git-ref github:owner
check_row npx-userrepo npx owner/repo git-ref github:owner
check_row npx-gitcommit npx git+https://github.com/o/r.git#0123456789abcdef0123456789abcdef01234567 git-commit github.com
check_row npx-tarball npx - unparsed -
check_row cmd-wrap npx w-mcp@1.0.0 exact unscoped
check_row cmdexe-wrap npx w-mcp@latest floating-tag unscoped
check_row npx-cmd npx c-mcp@1.0.0 exact unscoped
check_row bash-wrap npx b-mcp@latest floating-tag unscoped
check_row npm-exec npm-exec ne-mcp@1.0.0 exact unscoped
check_row pnpm-dlx pnpm-dlx 'pd-mcp@^2.0.0' floating-range unscoped
check_row pnpx-bare pnpx px-mcp floating-unversioned unscoped
check_row pnpx-exact pnpx px-mcp@1.0.0 exact unscoped
check_row yarn-dlx yarn-dlx yd-mcp floating-unversioned unscoped
check_row bunx bunx bx-mcp@1.0.0 exact unscoped
check_row uvx-bare uvx mcp-server-fetch floating-unversioned pypi
check_row uvx-eq uvx mcp-server-fetch==1.2.3 exact pypi
check_row uvx-at uvx mcp-server-fetch@1.2.3 exact pypi
check_row uvx-latest uvx mcp-server-fetch@latest floating-tag pypi
check_row uvx-range uvx 'mcp-server-fetch>=1.0' floating-range pypi
check_row uvx-extras uvx 'mcp-x[cli]==1.0.0' exact pypi
check_row uvx-from uvx git+https://git.example.com/x.git git-ref git.example.com
check_row uvx-from-exact uvx fx==2.0.0 exact pypi
check_row uvx-index uvx ix==1.0.0 exact index:pypi.example.com
check_row uv-tool-run uv-tool-run ut==1.0.0 exact pypi
check_row pipx-spec pipx px==1.0.0 exact pypi
check_row pipx-bare pipx pxb floating-unversioned pypi
check_row docker-digest docker \
  ghcr.io/acme/server@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef digest ghcr.io/acme
check_row docker-tagdigest docker \
  acme/server:1.0@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef digest acme
check_row docker-latest docker mcp/fetch:latest floating-tag mcp
check_row docker-untagged docker mcp/fetch floating-unversioned mcp
check_row docker-library docker alpine floating-unversioned library
check_row docker-fixed docker localhost:5000/team/img:1.2 mutable-tag localhost:5000/team
check_row docker-port-untagged docker localhost:5000/img floating-unversioned localhost:5000
check_row podman podman quay.io/org/img:2 mutable-tag quay.io/org
check_row nerdctl nerdctl img:latest floating-tag library
check_row local local my-server not-a-package local
check_row remote-http remote https://mcp.example.com:8443 n/a mcp.example.com
check_row remote-sse remote https://sse.example.com n/a sse.example.com
check_row remote-oauth remote https://o.example.com n/a o.example.com

# --- Run 2: managed-mcp.json present suppresses user/local/project/file ------

run_inv --claude-json "$FIX/claude.json" --project "c:/work/proj" --mcp-json "$FIX/proj/.mcp.json" \
  --managed-dir "$FIX/managed two" --config "$FIX/servers a.json" --date 2026-01-02

assert_eq "run 2 exits 0" 0 "$RC"
assert_eq "managed server effective" "yes" "$(cell managed corpstdio 3)"
assert_eq "user suppressed by managed" "suppressed-by-managed" "$(cell user useronly 3)"
assert_eq "local suppressed by managed" "suppressed-by-managed" "$(cell local localonly 3)"
assert_eq "project suppressed by managed" "suppressed-by-managed" "$(cell project projonly 3)"
assert_eq "file suppressed by managed" "suppressed-by-managed" "$(cell file npx-bare 3)"
assert_contains "managed-mcp.json found" "$OUT" "# source managed $FIX/managed two/managed-mcp.json found"
assert_contains "managed-settings.json absent" "$OUT" \
  "# source managed-settings $FIX/managed two/managed-settings.json absent"

# --- Run 2b: managedMcpServers rows still load beside managed-mcp.json ---------

mkdir -p "$FIX/managed three"
printf '%s\n' '{"managedMcpServers": {"corp": {"type": "http", "url": "https://corp.example.com/mcp"},
  "both": {"type": "http", "url": "https://both-settings.example.com/mcp"}}}' \
  >"$FIX/managed three/managed-settings.json"
printf '%s\n' '{"mcpServers": {"corpstdio": {"command": "npx", "args": ["corp-mcp@1.0.0"]},
  "both": {"command": "npx", "args": ["both-mcp@1.0.0"]}}}' >"$FIX/managed three/managed-mcp.json"
run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/managed three" --date 2026-01-02
assert_eq "managedMcpServers not suppressed by managed-mcp.json" "yes" "$(cell managed-settings corp 3)"
assert_eq "managed-settings row shadowed by a managed-mcp.json row" "shadowed-by:managed" \
  "$(cell managed-settings both 3)"
assert_eq "managed-mcp.json row wins over managed-settings" "yes" "$(cell managed both 3)"

# --- Run 2c: enableAllProjectMcpServers approves every project server ----------

run_inv --claude-json "$FIX/claude.json" --project "d:/all" --mcp-json "$FIX/proj/.mcp.json" \
  --managed-dir "$FIX/no managed" --date 2026-01-02
assert_eq "enableAllProjectMcpServers approves a project server" "yes" "$(cell project projonly 3)"

# --- Run 3: path-keyed local scope with a space and a trailing slash ---------

space_key="$FIX/my proj"
if command -v cygpath >/dev/null 2>&1; then
  space_key="$(cygpath -m "$space_key" | tr -d '\r')"
fi
jq -n --arg k "$space_key" '{projects: {($k): {mcpServers: {spaceproj: {command: "npx", args: ["sp@1.0.0"]}}}}}' \
  >"$FIX/claude space.json"

run_inv --claude-json "$FIX/claude space.json" --project "$FIX/my proj/" --mcp-json "$FIX/my proj/.mcp.json" \
  --managed-dir "$FIX/no managed" --date 2026-01-02
assert_eq "run 3 exits 0 with absent files" 0 "$RC"
assert_eq "path key with space and trailing slash matched" "yes" "$(cell local spaceproj 3)"
assert_contains "absent .mcp.json reported" "$OUT" "# source project $FIX/my proj/.mcp.json absent"

# --- Run 4: unmatched project key --------------------------------------------

run_inv --claude-json "$FIX/claude.json" --project "$FIX/unmatched" --mcp-json "$FIX/unmatched/.mcp.json" \
  --managed-dir "$FIX/no managed" --date 2026-01-02
assert_contains "unmatched project reports local absent" "$OUT" "# source local $FIX/claude.json absent"
assert_eq "unmatched project yields no local rows" "" "$(cell local shared 3)"

# --- Run 5: the same name in two --config files keeps both file rows -----------

printf '%s\n' '{"mcpServers": {"dup": {"command": "npx", "args": ["dup-a@1.0.0"]}}}' >"$FIX/dup a.json"
printf '%s\n' '{"mcpServers": {"dup": {"command": "npx", "args": ["dup-b@1.0.0"]}}}' >"$FIX/dup b.json"
run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/dup a.json" --config "$FIX/dup b.json" --date 2026-01-02
assert_eq "duplicate file-scope names both listed" 2 \
  "$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == "file" && $2 == "dup"' | wc -l | tr -d ' ')"

# --- Run 6: merge-gate adversarial fixture ------------------------------------

cat >"$FIX/gate adv.json" <<'JSON'
{"mcpServers": {
  "cmd-with-spaces": {"command": "npx -y evil-pkg --api-key LEAKCMD1"},
  "cmd-env-path": {"command": "/usr/bin/env API_KEY=LEAKCMD2 node", "args": ["server.js"]},
  "cmd-win-path": {"command": "C:\u005ctools\u005crun.exe --token LEAKCMD3"},
  "cmd-multiline": {"command": "node\nLEAKCMD4"},
  "url-at-in-pass": {"type": "http", "url": "https://tok:abc@LEAKURL1@host.example.com/mcp"},
  "url-slash-in-pass": {"type": "http", "url": "https://user:pa/LEAKURL2@host.example.com/mcp"},
  "url-hash-in-pass": {"type": "sse", "url": "https://user:p#LEAKURL3@host.example.com/mcp"},
  "url-query-in-pass": {"type": "http", "url": "https://user:p?LEAKURL4@host.example.com/mcp"},
  "git-at-in-pass": {"command": "npx", "args": ["git+https://u:x@LEAKGIT1@github.com/o/r.git"]},
  "uvx-from-at": {"command": "uvx", "args": ["--from", "git+https://u:p@LEAKGIT2@gh.com/o/r", "tool"]},
  "hdr": {"type": "http", "url": "https://h.example.com", "headers": {"Authorization": "Bearer LEAKHDR1"}},
  "env": {"command": "npx", "args": ["-y", "p@1.0.0"], "env": {"TOKEN": "LEAKENV1\nx", "K": "\u001b[31mLEAKENV2"}},
  "sk-LEAKNAME1abcdef": {"command": "npx", "args": ["p@1.0.0"]},
  "abcdefghijklmnopqrstuvwxyz0123456789": {"command": "npx", "args": ["long@1.0.0"]},
  "argsecret": {"command": "npx", "args": ["--api-key", "LEAKARG1", "pkg@1.0.0"]},
  "argsecret2": {"command": "npx", "args": ["-y", "--token=LEAKARG2", "pkg@1.0.0"]},
  "unicode": {"command": "npx", "args": ["\u202epkg@1.0.0"]},
  "pwsh": {"command": "pwsh", "args": ["-Command", "$env:K='LEAKPS1'; npx -y pkg@1.0.0"]},
  "pwsh-bare": {"command": "pwsh", "args": ["-Command", "$env:K=LEAKPS2; $env:J=\"LEAKPS3\"; npx -y pkg@1.0.0"]},
  "cmdc": {"command": "cmd", "args": ["/c", "set K=LEAKCMDC1&& npx -y pkg@1.0.0"]},
  "cmdc-space": {"command": "cmd", "args": ["/c", "set K=LEAKCMDC2 & npx -y pkg@1.0.0"]},
  "cmdc-quoted": {"command": "cmd", "args": ["/c", "set \"K=LEAKCMDC3\" && npx -y pkg@1.0.0"]},
  "wrapped-unsafe": {"command": "bash", "args": ["-c", "export K=LEAKEXP1; npx -y pkg@1.0.0"]},
  "latest": {"command": "npx", "args": ["-y", "@scope/pkg@latest"]},
  "scoped": {"command": "npx", "args": ["-y", "@scope/pkg"]},
  "scopedexact": {"command": "npx", "args": ["-y", "@scope/pkg@1.2.3"]},
  "tarball": {"command": "npx", "args": ["-y", "https://registry.npmjs.org/p/-/p-1.0.0.tgz"]},
  "tarball-other": {"command": "npx", "args": ["https://cdn.example.com/p-1.0.0.tgz"]},
  "tarball-targz": {"command": "uvx", "args": ["https://files.example.com/pkg-1.0.tar.gz"]},
  "gitsha": {"command": "npx", "args": ["github:o/r#0123456789abcdef0123456789abcdef01234567"]},
  "pnpx": {"command": "pnpx", "args": ["pkg"]},
  "bunx": {"command": "bunx", "args": ["pkg@1.0.0"]},
  "uvxfrom": {"command": "uvx", "args": ["--from", "pkg==1.0.0", "tool"]},
  "uvxlatest": {"command": "uvx", "args": ["pkg@latest"]},
  "dockerdigest": {"command": "docker", "args": ["run", "-i", "--rm", "-e", "K",
    "ghcr.io/o/i@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"]},
  "dockertag": {"command": "docker", "args": ["run", "-i", "--rm", "ghcr.io/o/i:1.0"]},
  "dockerlatest": {"command": "docker", "args": ["run", "img:latest"]},
  "dockerenvinline": {"command": "docker", "args": ["run", "-eK=LEAKDOCK1", "img:1"]},
  "npxcmdwin": {"command": "C:\u005cProgram Files\u005cnodejs\u005cnpx.cmd", "args": ["-y", "pkg"]},
  "npmexec": {"command": "npm", "args": ["exec", "--yes", "--", "pkg@2"]},
  "yarn": {"command": "yarn", "args": ["dlx", "pkg@1.0.0"]}
}}
JSON

run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/gate adv.json" --date 2026-01-02
assert_eq "run 6 exits 0" 0 "$RC"
check_row cmd-with-spaces local - unparsed -
check_row cmd-env-path local - unparsed -
check_row cmd-win-path local - unparsed -
check_row cmd-multiline local - unparsed -
check_row url-at-in-pass remote - unparsed -
check_row url-slash-in-pass remote - unparsed -
check_row url-hash-in-pass remote - unparsed -
check_row url-query-in-pass remote - unparsed -
check_row git-at-in-pass npx - unparsed -
check_row uvx-from-at uvx - unparsed -
check_row hdr remote https://h.example.com n/a h.example.com
check_row env npx p@1.0.0 exact unscoped
check_row 'redacted-name(18)' npx p@1.0.0 exact unscoped
check_row 'redacted-name(36)' npx long@1.0.0 exact unscoped
check_row argsecret npx - unparsed -
check_row argsecret2 npx pkg@1.0.0 exact unscoped
check_row unicode npx - unparsed -
check_row pwsh npx pkg@1.0.0 exact unscoped
check_row pwsh-bare local - unparsed -
check_row cmdc npx pkg@1.0.0 exact unscoped
check_row cmdc-space local - unparsed -
check_row cmdc-quoted local - unparsed -
check_row wrapped-unsafe local - unparsed -
check_row latest npx @scope/pkg@latest floating-tag @scope
check_row scoped npx @scope/pkg floating-unversioned @scope
check_row scopedexact npx @scope/pkg@1.2.3 exact @scope
check_row tarball npx https://registry.npmjs.org/.../p-1.0.0.tgz exact registry.npmjs.org
check_row tarball-other npx https://cdn.example.com/p-1.0.0.tgz tarball cdn.example.com
check_row tarball-targz uvx https://files.example.com/pkg-1.0.tar.gz tarball files.example.com
check_row gitsha npx github:o/r#0123456789abcdef0123456789abcdef01234567 git-commit github:o
check_row pnpx pnpx pkg floating-unversioned unscoped
check_row bunx bunx pkg@1.0.0 exact unscoped
check_row uvxfrom uvx pkg==1.0.0 exact pypi
check_row uvxlatest uvx pkg@latest floating-tag pypi
check_row dockerdigest docker \
  ghcr.io/o/i@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef digest ghcr.io/o
check_row dockertag docker ghcr.io/o/i:1.0 mutable-tag ghcr.io/o
check_row dockerlatest docker img:latest floating-tag library
check_row dockerenvinline docker img:1 mutable-tag library
check_row npxcmdwin npx pkg floating-unversioned unscoped
check_row npmexec npm-exec pkg@2 floating-range unscoped
check_row yarn yarn-dlx pkg@1.0.0 exact unscoped

# --- Run 7: re-attack fixture (every ZQX token must stay out of all output) ------
# One server per case; ZQX062 is a managed-settings.d drop-in.

mkdir -p "$FIX/managed five/managed-settings.d"
cat >"$FIX/managed five/managed-settings.d/50-x.json" <<'JSON'
{"managedMcpServers": {"s": {"type":"http","url":"https://u:ZQX062@h.example.com/mcp?k=ZQX062#ZQX062","headers":{"X":"ZQX062"},"oauth":{"clientSecret":"ZQX062"}}}}
JSON
cat >"$FIX/reattack cases.json" <<'JSON'
{"mcpServers": {
  "r001":{"type":"http","url":"https://user%40x:ZQX001@h.example.com/mcp"},
  "r002":{"type":"http","url":"https://u:ZQX002@[::1]:8443/mcp"},
  "r003":{"type":"http","url":"HTTPS://ZQX003:x@H.EXAMPLE.COM:444/m"},
  "r004":{"command":"npx","args":["-y","git+ssh://git:ZQX004@github.com/o/r.git"]},
  "r005":{"command":"npx","args":["-y","ssh://ZQX005@github.com/o/r"]},
  "r006":{"command":"npx","args":["-y","ZQX006@github.com:o/r"]},
  "r007":{"command":"npx","args":["-y","git+ssh:ZQX007@github.com:o/r"]},
  "r008":{"command":"npx","args":["-y","file://ZQX008:p@host/share/pkg.tgz"]},
  "r009":{"command":"npx","args":["-y","foo@npm:bar@https://u:ZQX009@h.example.com/x.tgz"]},
  "r010":{"command":"npx","args":["-y","https://h.example.com/p@ZQX010/x.tgz"]},
  "r011":{"type":"http","url":"https:\u005c\u005cu:ZQX011@h.example.com\u005cmcp"},
  "r071":{"type":"http","url":"https://h.example.com\u005cZQX071\u005cmcp"},
  "r012":{"type":"http","url":"https://h.example.com ?token=ZQX012"},
  "r072":{"type":"http","url":"https://h.example.com token=ZQX072"},
  "r013":{"command":"npx","args":["-y","git+https://github.com/o/r#ZQX013#0123456789abcdef0123456789abcdef01234567"]},
  "r014":{"command":"npx","args":["-y","git+https://github.com/o/r?t=ZQX014#0123456789abcdef0123456789abcdef01234567"]},
  "r015":{"type":"http","url":"u:ZQX015@h.example.com/mcp"},
  "r016":{"type":"http","url":"//u:ZQX016@h.example.com/mcp"},
  "r017":{"type":"http","url":"https://h.example.com;token=ZQX017/mcp"},
  "r018":{"command":"bash","args":["-c","env X=1 sh -c 'npx pkg --token ZQX018'"]},
  "r019":{"command":"cmd","args":["/v","/c","set T=ZQX019&& npx -y pkg"]},
  "r020":{"command":"powershell","args":["-EncodedCommand","ZQX020base64"]},
  "r021":{"command":"pwsh","args":["-c","& { $env:X='ZQX021'; npx pkg }"]},
  "r022":{"command":"cmd","args":["/c","set /p T=ZQX022 && npx pkg"]},
  "r023":{"command":"bash","args":["-c","export T=ZQX023; npx pkg"]},
  "r024":{"command":"T=ZQX024","args":["npx","pkg"]},
  "r073":{"command":"bash","args":["-c","T=ZQX073 npx pkg"]},
  "r025":{"command":"sudo","args":["-E","npx","pkg","--key","ZQX025"]},
  "r026":{"command":"npx","args":["--node-options=--x=ZQX026","pkg"]},
  "r027":{"command":"npm","args":["exec","--","pkg","--token","ZQX027"]},
  "r028":{"command":"yarn","args":["dlx","-p","pkg","bin","--token=ZQX028"]},
  "r029":{"command":"bash","args":["-c","API_KEY='abc ZQX029' ./server"]},
  "r030":{"command":"bash","args":["-c","npx -y pkg@1.0.0;curl${IFS}-H${IFS}Auth:ZQX030"]},
  "r031":{"command":"pwsh","args":["-c","npx pkg@1;$env:T='ZQX031'"]},
  "r032":{"command":"cmd","args":["/c","npx pkg@1&&set T=ZQX032"]},
  "r033":{"command":"bash","args":["-c","uvx mcp-x==1.0\u00a0--token\u00a0ZQX033"]},
  "r034":{"command":"docker","args":["run","--env=K=ZQX034","img"]},
  "r035":{"command":"docker","args":["run","-e=K=ZQX035","img"]},
  "r036":{"command":"docker","args":["run","--label","k=ZQX036","img"]},
  "r037":{"command":"docker","args":["run","--secret","id=ZQX037","img"]},
  "r038":{"command":"docker","args":["run","--build-arg","T=ZQX038","img"]},
  "r039":{"command":"docker","args":["run","-v","/ZQX039:/d","img"]},
  "r040":{"command":"docker","args":["run","--entrypoint","/bin/ZQX040","img","arg"]},
  "r041":{"command":"docker","args":["run","img","--token","ZQX041"]},
  "r042":{"command":"uvx","args":["--with","ZQX042pkg","mcp-x"]},
  "r043":{"command":"uvx","args":["--index-url","https://u:ZQX043@h.example.com/simple","mcp-x"]},
  "r044":{"command":"pipx","args":["run","--spec","https://u:ZQX044@h.example.com/x.whl?t=1","mcp-x"]},
  "r045":{"command":"uvx","args":["mcp-x==1.0 --api-key ZQX045"]},
  "r046":{"command":"uvx","args":["mcp-x==1.0\rZQX046"]},
  "r047":{"command":"npx","args":[123,null,{"t":"ZQX047"},["ZQX047b"],"pkg"]},
  "r048":{"command":"docker","args":["run","-p",8080,"-v","ZQX048:/data","img"]},
  "r049":{"command":{"x":"ZQX049"},"args":["ZQX049b"]},
  "\u0455k-ZQX050":{"type":"http","url":"https://h.example.com"},
  "Sk-ZQX051":{"type":"http","url":"https://h.example.com"},
  "ASIAZQX052ABCDEFGHIJ":{"type":"http","url":"https://h.example.com"},
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ.ZQX053sig":{"type":"http","url":"https://h.example.com"},
  "s\u00adk-ZQX054":{"type":"http","url":"https://h.example.com"},
  "r055":{"command":"npx","args":["pkg","--token","ZQX055AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"]},
  "r056":{"command":"\u001b]0;ZQX056\u0007server","args":[]},
  "r057":{"command":"bash","args":["-c","npx pkg\u2028ZQX057"]},
  "r058":{"command":"uvx","args":["mcp-x==1\u0000ZQX058"]},
  "r059":{"type":"stdio","url":"https://u:ZQX059@h.example.com/mcp"},
  "r060":{"type":"http","url":"https://h.example.com/mcp","command":"bash","args":["-c","ZQX060"]},
  "r061":{"type":"ZQX061","url":"https://h.example.com/mcp"},
  "r063":{"command":"npx","args":["pkg"],"env":{"K":"ZQX063"},"headers":{"A":"ZQX063"},"oauth":{"clientId":"ZQX063"},"headersHelper":"/bin/ZQX063"},
  "r065":{"command":"uvx","args":["mcp-x[ZQX065 secret]"]},
  "r066":{"command":"npx","args":["pkg@1.0.0 ZQX066"]},
  "r067":{"type":"http","url":"https://h.example.com/mcp?k=ZQX067#ZQX067"},
  "r068":{"command":"env","args":["-S","X=ZQX068 npx pkg"]},
  "r069":{"command":"env","args":["-S","X='a ZQX069' npx pkg"]},
  "r070":{"command":"cmd","args":["/c","set \"T=a ZQX070\" && npx pkg"]},
  "r074":{"command":"bash","args":["-c","X=\"a ZQX074\" npx -y pkg"]},
  "r075":{"command":"uvx","args":["mcp-x==1.0;ZQX075"]},
  "r076":{"command":"npx","args":["-y","pkg@1.0.0&&curl${IFS}ZQX076"]},
  "r077":{"command":"docker","args":["run","ZQX077@r:t"]},
  "r078":{"command":"bash","args":["-c","sudo -E npx pkg --token ZQX078"]},
  "r079":{"command":"npx","args":["-y","pkg@git+https://github.com/o/r?#ZQX079"]},
  "r080":{"type":"sse","url":"wss://ZQX080@h.example.com"},
  "r081":{"command":"uvx","args":["--from","mcp-x @ git+https://u:ZQX081@github.com/o/r","mcp-x"]},
  "r082":{"command":"npx","args":["-y","@scope/pkg@1.0.0\u200bZQX082"]},
  "r083":{"command":"C:\u005cProgram Files\u005cnode\u005cnpx.cmd","args":["-y","pkg@latest","--api-key=ZQX083"]},
  "r084":{"command":"npx","args":["-y","github:ZQX084@o/r"]}
}}
JSON

run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/managed five" --config "$FIX/reattack cases.json" --date 2026-01-02
assert_eq "run 7 exits 0" 0 "$RC"
assert_eq "run 7 prints one row per case" 83 \
  "$(printf '%s\n' "$OUT" | sed -n '3,$p' | grep -vc '^#')"
check_row r001 remote https://h.example.com n/a h.example.com
check_row r002 remote 'https://[::1]:8443' n/a '[::1]'
check_row r003 remote - unparsed -
check_row r004 npx git+ssh://github.com/o/r.git git-ref github.com
check_row r018 local - unparsed -
check_row r022 local - unparsed -
check_row r029 local - unparsed -
check_row r030 local - unparsed -
check_row r047 npx - unparsed -
check_row r061 - - unparsed -
check_row r074 local - unparsed -
check_row r081 uvx 'mcp-x @ git+https://github.com/o/r' git-ref github.com
assert_eq "unknown type prints transport unknown" "unknown" "$(cell file r061 4)"
assert_eq "valid drop-in managedMcpServers entry loads" "yes" "$(cell managed-settings s 3)"
assert_eq "drop-in remote url prints host only" "https://h.example.com" "$(cell managed-settings s 6)"
assert_eq "non-ASCII name redacted by raw length" "https://h.example.com" "$(cell file 'redacted-name(10)' 6)"

# --- Run 8: managed validity, conditional shadowing, names, transports ---------

mkdir -p "$FIX/managed four" "$FIX/seven"
cat >"$FIX/managed four/managed-settings.json" <<'JSON'
{"managedMcpServers": {
  "ok-entry": {"type": "http", "url": "https://ok.example.com/mcp"},
  "bad-cmd": {"type": "http", "url": "https://x.example.com/mcp", "command": "npx"},
  "bad-http": {"type": "http", "url": "http://x.example.com/mcp"},
  "bad-var": {"type": "http", "url": "https://x.example.com/${TOKEN}"},
  "bad.name": {"type": "http", "url": "https://x.example.com/mcp"},
  "bad-env": {"type": "http", "url": "https://x.example.com/mcp", "env": {"A": "b"}}
}}
JSON
cat >"$FIX/seven/claude.json" <<'JSON'
{"mcpServers": {
  "pua": {"command": "npx", "args": ["pua-user@1.0.0"]},
  "bad-cmd": {"command": "npx", "args": ["bc-user@1.0.0"]}
}}
JSON
cat >"$FIX/seven/.mcp.json" <<'JSON'
{"mcpServers": {"pua": {"command": "npx", "args": ["pua-project@1.0.0"]}}}
JSON
cat >"$FIX/seven/names.json" <<'JSON'
{"mcpServers": {
  "my server 1": {"command": "npx", "args": ["n1@1.0.0"]},
  "abcd abcd abcd abcd abcd abcd abcd abcd abcd abcd abcd abcd abcd ": {"command": "npx", "args": ["n65@1.0.0"]},
  "a.b.c": {"command": "npx", "args": ["dots@1.0.0"]},
  "has:colon1": {"command": "npx", "args": ["colon@1.0.0"]},
  "AIzaKey": {"command": "npx", "args": ["ai-key@1.0.0"]},
  "eyJx": {"command": "npx", "args": ["ej-x@1.0.0"]},
  "t-unknown": {"type": "websocket", "url": "https://x.example.com"},
  "t-sdk": {"type": "sdk"},
  "q-key": {"type": "http", "url": "https://h.example.com/mcp?api_key=ZQX901"},
  "q-userinfo": {"type": "http", "url": "https://u:p@h.example.com/mcp?x=ZQX902"}
}}
JSON

run_inv --claude-json "$FIX/seven/claude.json" --project "$FIX/seven" --mcp-json "$FIX/seven/.mcp.json" \
  --managed-dir "$FIX/managed four" --config "$FIX/seven/names.json" --date 2026-01-02
assert_eq "run 8 exits 0" 0 "$RC"
assert_eq "unapproved project row" "approval-unknown" "$(cell project pua 3)"
assert_eq "user row behind an unapproved project row" "shadowed-by:project-if-approved" "$(cell user pua 3)"
assert_eq "valid managedMcpServers entry" "yes" "$(cell managed-settings ok-entry 3)"
assert_eq "managedMcpServers entry with command rejected" "rejected-by-client" "$(cell managed-settings bad-cmd 3)"
assert_eq "managedMcpServers entry with http url rejected" "rejected-by-client" "$(cell managed-settings bad-http 3)"
assert_eq "managedMcpServers entry with a variable rejected" "rejected-by-client" "$(cell managed-settings bad-var 3)"
assert_eq "managedMcpServers entry with a dotted name rejected" "rejected-by-client" \
  "$(cell managed-settings bad.name 3)"
assert_eq "managedMcpServers entry with env rejected" "rejected-by-client" "$(cell managed-settings bad-env 3)"
assert_eq "rejected managed entry shadows nothing" "yes" "$(cell user bad-cmd 3)"
assert_eq "plain name with spaces printed" "n1@1.0.0" "$(cell file 'my server 1' 6)"
assert_eq "name over 64 characters redacted" "n65@1.0.0" "$(cell file 'redacted-name(65)' 6)"
assert_eq "dotted base64url name redacted" "dots@1.0.0" "$(cell file 'redacted-name(5)' 6)"
assert_eq "name outside the charset redacted" "colon@1.0.0" "$(cell file 'redacted-name(10)' 6)"
assert_eq "AIza name redacted" "ai-key@1.0.0" "$(cell file 'redacted-name(7)' 6)"
assert_eq "eyJ name redacted" "ej-x@1.0.0" "$(cell file 'redacted-name(4)' 6)"
assert_eq "unrecognized type prints transport unknown" "unknown" "$(cell file t-unknown 4)"
assert_eq "unrecognized type row is unparsed" "unparsed" "$(cell file t-unknown 7)"
assert_eq "sdk transport" "sdk" "$(cell file t-sdk 4)"
assert_eq "sdk launcher" "sdk" "$(cell file t-sdk 5)"
check_row q-key remote https://h.example.com n/a h.example.com
check_row q-userinfo remote https://h.example.com n/a h.example.com

# --- Run 9: second re-attack (value filter, env options, path elision) ---------
# Withheld cases carry ZQX; the .cfg extension keeps them out of the *.json grep, and the
# planted loop below collects them separately. Residual cases carry RSD instead: they are
# not secret-shaped under the value filter, so they still print (asserted below).

mkdir -p "$FIX/managed six/managed-settings.d"
cat >"$FIX/managed six/managed-settings.d/50-n.json" <<'JSON'
{"managedMcpServers": {"RSDsecret123": {"type": "http", "url": "https://h.example.com"}}}
JSON
cat >"$FIX/reattack2 cases.cfg" <<'JSON'
{"mcpServers": {
  "N01-npm-longtag":{"command":"npx","args":["-y","somepkg@ZQXghpAbcDef0123456789abcdef0123456789abcdef0123456789ABCDEF0123456789"]},
  "N02-npm-scope":{"command":"npx","args":["-y","@ZQXsecret0123456789abcdef0123456789/pkg@1.0.0"]},
  "N03-img-tag":{"command":"docker","args":["run","-i","--rm","ghcr.io/o/img:ZQXghp_AbcDef0123456789abcdef0123456789"]},
  "N04-img-registry":{"command":"docker","args":["run","ZQXtoken0123456789.registry.example.com:5000/o/img:1"]},
  "N05-git-path":{"command":"npx","args":["-y","git+https://github.com/o/ZQXghpAbcDef0123456789abcdef.git"]},
  "N06-tarball-path":{"command":"npx","args":["-y","https://h.example.com/api/ZQXtoken0123456789abcdef/pkg.tgz"]},
  "N07-alias-tarball":{"command":"npx","args":["-y","foo@https://h.example.com/ZQXsecret/x.tgz"]},
  "N08-py-url":{"command":"uvx","args":["--from","pkg @ git+https://u:pw@h.example.com/RSDsecret/r.git","pkg"]},
  "N09-local-path":{"command":"npx","args":["-y","./RSDsecret0123456789/pkg"]},
  "N10-file-path":{"command":"npx","args":["-y","file:RSDsecret0123456789"]},
  "N11-home-path":{"command":"uvx","args":["~/RSDsecret"]},
  "N12-gh-spec":{"command":"npx","args":["-y","ZQXowner/ZQXghpAbcDef0123456789"]},
  "N13-uvx-name":{"command":"uvx","args":["ZQXghp_AbcDef0123456789abcdef01234567"]},
  "N14-uvx-ver":{"command":"uvx","args":["pkg==RSDsecret0123456789"]},
  "N15-uvx-at":{"command":"uvx","args":["pkg@RSDsecret0123456789"]},
  "N16-basename":{"command":"ZQXsk-proj-AbcDef0123456789abcdef0123456789","args":[]},
  "N17-bash-c-basename":{"command":"bash","args":["-c","RSDsecret_token_0123456789abcdef --serve"]},
  "N18-env-P":{"command":"env","args":["-P","ZQXsecret","server"]},
  "N19-env-a":{"command":"env","args":["-a","ZQXsecret","server"]},
  "N20-remote-host":{"type":"http","url":"https://ZQXtoken0123456789abcdef.ngrok.io/mcp"},
  "N21-remote-port":{"type":"sse","url":"https://h.example.com:443/ZQXpath?k=ZQX"},
  "ZQXa1b2c3d4e5f6g7h8i9j0 k1l2m3n4o5p6q7r8s9t0u1v2w3x4":{"command":"node"},
  "ZQXabcdefghijklmnopqrstuvwx01.abcdefghijklmnopqrstuvwxyz0123":{"command":"node"},
  "prod RSDAKIAIOSFODNN7EXAMPLE":{"command":"node"},
  "ZQXabcdef0123456789abcdef012":{"command":"node"},
  "a\tZQXsecret":{"command":"node"},
  "RSD correct horse battery staple":{"command":"node"},
  "N28-type-garbage":{"type":"ZQXsecret","url":"https://h.example.com"},
  "N29-cmd-set":{"command":"cmd","args":["/c","set","TOKEN=ZQXsecret","&&","npx","-y","pkg@1.0.0"]},
  "N30-pwsh-env":{"command":"pwsh","args":["-Command","$env:TOKEN='ZQXsecret'; npx -y pkg@1.0.0"]},
  "N31-docker-env":{"command":"docker","args":["run","-eTOKEN=ZQXsecret","--env=X=ZQXsecret","-e","Y=ZQXsecret","img:1"]},
  "N32-docker-unknown-flag":{"command":"docker","args":["run","--newflag","ZQXsecret","img:1"]},
  "N33-npx-unknown-flag-eq":{"command":"npx","args":["--foo","ZQXsecret0123456789","pkg"]},
  "N34-npx-c":{"command":"npx","args":["-c","ZQXsecret cmd","pkg@1.0.0"]},
  "N35-npm-hex":{"command":"npx","args":["-y","ZQX0123456789abcdef0123456789abcdef01234567"]},
  "N36-uv-with":{"command":"uvx","args":["--with","ZQXsecret","--index-url","https://u:ZQX@h/simple","pkg==1.0"]},
  "N37-env-S":{"command":"env","args":["-S","TOKEN=ZQXsecret npx -y pkg@1.0.0"]},
  "N38-bash-c-assign":{"command":"bash","args":["-c","TOKEN=ZQXsecret npx -y pkg@1.0.0"]},
  "N39-nonstring-arg":{"command":"ZQXcmd","args":[1]},
  "N40-img-libname":{"command":"podman","args":["run","ZQXsecret0123456789abcdef"]},
  "N41-pipx-spec":{"command":"pipx","args":["run","--spec","RSDsecret==1.0","x"]},
  "N43-img-digest":{"command":"docker","args":["run","ZQX/img@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"]},
  "N44-gh-commit":{"command":"npx","args":["-y","github:RSDo/r#0123456789abcdef0123456789abcdef01234567"]},
  "N45-sdk":{"type":"sdk","name":"ZQX"},
  "env-unknown-flag":{"command":"env","args":["--frob","ZQXenvflag","npx","pkg"]},
  "env-unset-eq":{"command":"env","args":["--unset=ZQXunset","npx","pkg@1.0.0"]},
  "legit-npm":{"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem@2025.4.8"]},
  "legit-py":{"command":"uvx","args":["mcp-server-fetch==2025.4.7"]},
  "legit-img":{"command":"docker","args":["run","ghcr.io/github/github-mcp-server:0.4.0"]},
  "legit-digest":{"command":"docker","args":["run","docker.io/mcp/notes@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"]},
  "legit-git":{"command":"npx","args":["git+https://github.com/o/r.git#0123456789abcdef0123456789abcdef01234567"]},
  "N04-lower":{"command":"docker","args":["run","rsdtoken0123456789.registry.example.com:5000/o/img:1"]},
  "N43-lower":{"command":"docker","args":["run","rsdns/img@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"]}
}}
JSON

run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/managed six" --config "$FIX/reattack2 cases.cfg" --date 2026-01-02
assert_eq "run 9 exits 0" 0 "$RC"
assert_eq "run 9 prints one row per case" 54 "$(printf '%s\n' "$OUT" | sed -n '3,$p' | grep -vc '^#')"
check_row N01-npm-longtag npx - unparsed -
check_row N05-git-path npx - unparsed -
check_row N06-tarball-path npx https://h.example.com/.../pkg.tgz tarball h.example.com
check_row N07-alias-tarball npx foo@https://h.example.com/.../x.tgz tarball h.example.com
check_row N12-gh-spec npx - unparsed -
check_row N13-uvx-name uvx - unparsed -
check_row N16-basename local - unparsed -
check_row N18-env-P local server not-a-package local
check_row N19-env-a local server not-a-package local
check_row N20-remote-host remote - unparsed -
check_row env-unknown-flag local - unparsed -
check_row env-unset-eq npx pkg@1.0.0 exact unscoped
check_row legit-npm npx @modelcontextprotocol/server-filesystem@2025.4.8 exact @modelcontextprotocol
check_row legit-py uvx mcp-server-fetch==2025.4.7 exact pypi
check_row legit-img docker ghcr.io/github/github-mcp-server:0.4.0 mutable-tag ghcr.io/github
check_row legit-digest docker \
  docker.io/mcp/notes@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef digest docker.io/mcp
check_row legit-git npx git+https://github.com/o/r.git#0123456789abcdef0123456789abcdef01234567 git-commit github.com
assert_eq "secret-shaped name with spaces redacted" "node" "$(cell file 'redacted-name(52)' 6)"
assert_eq "digit-letter name redacted" "node" "$(cell file 'redacted-name(28)' 6)"
assert_eq "AKIA glued to a letter prints (accepted residual)" "node" \
  "$(cell file 'prod RSDAKIAIOSFODNN7EXAMPLE' 6)"
# Residuals: short values that are not secret-shaped under the value filter still print.
check_row N08-py-url uvx 'pkg @ git+https://h.example.com/RSDsecret/r.git' git-ref h.example.com
check_row N14-uvx-ver uvx pkg==RSDsecret0123456789 exact pypi
check_row N17-bash-c-basename local RSDsecret_token_0123456789abcdef not-a-package local
check_row N04-lower docker rsdtoken0123456789.registry.example.com:5000/o/img:1 mutable-tag \
  rsdtoken0123456789.registry.example.com:5000/o
check_row N43-lower docker \
  rsdns/img@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef digest rsdns
assert_eq "dictionary-word name prints (accepted residual)" "node" "$(cell file 'RSD correct horse battery staple' 6)"
assert_eq "short drop-in entry name prints (accepted residual)" "yes" "$(cell managed-settings RSDsecret123 3)"

# --- Run 10: availability limits and source paths ----------------------------

jq -n '{mcpServers: {big: {command: "bash", args: ["-c", ("npx \"" + ("a" * 1048576))]}}}' >"$FIX/big wrapper.json"
jq -n '{mcpServers: {many: {command: "npx", args: ([range(0; 257)] | map("pkg"))}}}' >"$FIX/many args.json"
started=$SECONDS
run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/big wrapper.json" --config "$FIX/many args.json" --date 2026-01-02
assert_eq "1 MB unbalanced wrapper finishes in under 60 s" "yes" "$([[ $((SECONDS - started)) -lt 60 ]] && echo yes)"
check_row big local - unparsed -
check_row many npx - unparsed -

# Secret prefixes match only at the start of a value or after a non-alphanumeric character.
cat >"$FIX/prefix cases.json" <<'JSON'
{"mcpServers": {
  "p-task": {"command": "npx", "args": ["task-runner@1.0.0"]},
  "p-disk": {"command": "npx", "args": ["disk-usage@1.0.0"]},
  "p-asian": {"command": "npx", "args": ["@acme/asian-food@1.0.0"]},
  "p-sk": {"command": "npx", "args": ["sk-proj-abc@1.0.0"]},
  "p-ghp": {"command": "npx", "args": ["x/ghp_abc"]},
  "prod AKIAabc": {"command": "npx", "args": ["plain@1.0.0"]},
  "u-npm-uuid": {"command": "npx", "args": ["pkg@5f3c9a2e-8b1d-4e7a-9c6f-2d8b0a1e4f7c"]},
  "u-img-hex": {"command": "docker", "args": ["run", "ghcr.io/o/img:0123456789abcdef0123456789abcdef01234567"]},
  "5f3c9a2e-8b1d-4e7a-9c6f-2d8b0a1e4f7c": {"command": "npx", "args": ["uuidname@1.0.0"]},
  "u-ok": {"command": "npx", "args": ["pkg@1.2.3"]},
  "pw-Env": {"command": "pwsh", "args": ["-Command", "$Env:K='LEAKPW1'; npx -y pkg@1.0.0"]},
  "pw-ENV": {"command": "pwsh", "args": ["-COMMAND", "$ENV:K=LEAKPW2; npx -y pkg@1.0.0"]},
  "pw-brace": {"command": "pwsh", "args": ["-command", "${env:K}='LEAKPW3'; npx -y pkg@1.0.0"]},
  "cmd-upper": {"command": "cmd", "args": ["/C", "SET K=LEAKPW4&& npx -y pkg@1.0.0"]}
}}
JSON
run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/prefix cases.json" --date 2026-01-02
check_row p-task npx task-runner@1.0.0 exact unscoped
check_row p-disk npx disk-usage@1.0.0 exact unscoped
check_row p-asian npx @acme/asian-food@1.0.0 exact @acme
check_row p-sk npx - unparsed -
check_row p-ghp npx - unparsed -
assert_eq "AKIA after a space redacts the name" "plain@1.0.0" "$(cell file 'redacted-name(12)' 6)"
# A UUID or a 32+ hex run is withheld; a git #<40 hex> commit and an @sha256 digest are not
# (both covered by npx-gitcommit and docker-digest in run 1).
check_row u-npm-uuid npx - unparsed -
check_row u-img-hex docker - unparsed -
assert_eq "UUID name redacted" "uuidname@1.0.0" "$(cell file 'redacted-name(36)' 6)"
check_row u-ok npx pkg@1.2.3 exact unscoped
# PowerShell env assignments, -Command, cmd /C and SET are matched case-insensitively.
check_row pw-Env npx pkg@1.0.0 exact unscoped
check_row pw-ENV npx pkg@1.0.0 exact unscoped
check_row pw-brace local - unparsed -
check_row cmd-upper npx pkg@1.0.0 exact unscoped

mkdir -p "$FIX/managed seven/managed-settings.d"
printf '%s\n' '{"managedMcpServers": {}}' >"$FIX/managed seven/managed-settings.d/ZQXdrop0123456789abcdefghij.json"
run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/managed seven" --date 2026-01-02
assert_contains "secret-shaped drop-in file name prints as redacted-file" "$OUT" \
  "# source managed-settings $FIX/managed seven/managed-settings.d/redacted-file found"
assert_not_contains "drop-in file name not echoed" "$OUT$ERR" "ZQXdrop"

run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/a"$'\n'"ZQXLINEPATH.json" --date 2026-01-02
assert_eq "control character in a source path exits 2" 2 "$RC"
assert_not_contains "control-character path not echoed" "$OUT$ERR" "ZQXLINEPATH"

# --- Run 11: re-gate fixtures (wrapper whitespace, URL backslash, custom index) -----
# Tokens are lower-case zqx; the planted loop collects them, plus the zq/xaNN halves of
# tokens split by a quote, space, or percent escape.

cat >"$FIX/gate3 adv3.json" <<'JSON'
{"mcpServers": {
 "b01": {"command":"bash","args":["-c","TOKEN=abc\u005c zqxb01 ./run"]},
 "b02": {"command":"bash","args":["-c","K=abc\u2028zqxb02 ./run"]},
 "b03": {"command":"bash","args":["-c","K=abc\u00a0zqxb03 ./run"]},
 "b04": {"command":"bash","args":["-c","K=abc\u000bzqxb04 ./run"]},
 "b05": {"command":"env","args":["-S","K=abc\u005c zqxb05 node"]},
 "b06": {"command":"bash","args":["-c","K=abc\u2029zqxb06 run"]},
 "b07": {"command":"bash","args":["-c","K=abc\u000czqxb07 run"]},
 "b08": {"command":"bash","args":["-c","K=abc\u0085zqxb08 run"]},
 "b09": {"command":"bash","args":["-c","K=abc\u3000zqxb09 run"]},
 "b10": {"command":"cmd","args":["/c","set K=abc\u00a0zqxb10&& run"]},
 "b11": {"command":"pwsh","args":["-Command","$env:K=abc\u2028zqxb11; run"]},
 "b12": {"command":"bash","args":["-c","K=\"abc\"\u005c zqxb12 run"]}
}}
JSON
cat >"$FIX/gate3 adv2.json" <<'JSON'
{"mcpServers": {
 "a01-env-str": {"command":"npx","args":["-y","pkg@1.0.0"],"env":{"K":"zqxa01"}},
 "a02-env-obj": {"command":"npx","args":["-y","pkg@1.0.0"],"env":{"K":{"v":"zqxa02"},"L":["zqxa02b"],"M":42}},
 "a03-hdr-multi": {"type":"http","url":"https://h.example.com/mcp","headers":{"X-Api-Key":"zqxa03","Cookie":"s=zqxa03b"}},
 "a04-hdr-nonstr": {"type":"sse","url":"https://h.example.com/","headers":["zqxa04"]},
 "a05-arg-after-pkg": {"command":"npx","args":["-y","pkg@1.0.0","--token","zqxa05"]},
 "a06-arg-before-pkg": {"command":"npx","args":["--token","zqxa06","pkg@1.0.0"]},
 "a07-arg-eq": {"command":"npx","args":["--token=zqxa07","-y","pkg@1.0.0"]},
 "a08-short-bundle": {"command":"npx","args":["-yt","zqxa08","pkg@1.0.0"]},
 "a09-unknownflag-dashval": {"command":"npx","args":["--key","-zqxa09","pkg@1.0.0"]},
 "a10-uvx-envfile": {"command":"uvx","args":["--env-file","zqxa10","tool==1.0"]},
 "a11-docker-bundle-e": {"command":"docker","args":["run","-ite","K=zqxa11","img:1"]},
 "a12-docker-env-eq": {"command":"docker","args":["run","--env=K=zqxa12","img:1"]},
 "a13-docker-unknown": {"command":"docker","args":["run","--sig-proxy","zqxa13","img:1"]},
 "a14-url-user-only": {"type":"http","url":"https://zqxa14@h.example.com/mcp"},
 "a15-url-pct40": {"type":"http","url":"https://u:zq%40xa15@h.example.com/mcp"},
 "a16-url-pct2f": {"type":"http","url":"https://u:zq%2Fxa16@h.example.com/mcp"},
 "a17-url-ipv6": {"type":"http","url":"https://u:zqxa17@[::1]:8443/mcp?t=zqxa17b#zqxa17c"},
 "a18-url-puny": {"type":"http","url":"https://u:zqxa18@xn--bcher-kva.example/mcp"},
 "a19-url-at-path": {"type":"http","url":"https://h.example.com/a@zqxa19/mcp"},
 "a20-url-backslash": {"type":"http","url":"https://zqxa20.evil\u005c@h.example.com/mcp"},
 "a21-url-query": {"type":"http","url":"https://h.example.com/mcp?api_key=zqxa21"},
 "a22-url-frag": {"type":"sse","url":"https://h.example.com/mcp#zqxa22"},
 "a23-file-url": {"command":"npx","args":["file:///x?zqxa23"]},
 "a24-ssh-url": {"command":"npx","args":["git+ssh://git:zqxa24@github.com/o/r.git"]},
 "a25-scp-git": {"command":"npx","args":["git@github.com:zqxa25/r.git"]},
 "a26-git-query": {"command":"npx","args":["git+https://github.com/o/r.git?token=zqxa26"]},
 "a27-git-frag": {"command":"npx","args":["github:o/r#zqxa27"]},
 "a28-tgz-query": {"command":"npx","args":["https://reg.example.com/p/-/p-1.0.0.tgz?sig=zqxa28"]},
 "a29-tgz-user": {"command":"npx","args":["https://u:zqxa29@reg.example.com/p/-/p-1.0.0.tgz"]},
 "a30-bash-quotes": {"command":"bash","args":["-c","TOKEN='zq xa30' npx -y pkg@1.0.0"]},
 "a31-bash-escape": {"command":"bash","args":["-c","TOKEN=zq\u005c xa31 npx -y pkg@1.0.0"]},
 "a32-bash-dq": {"command":"bash","args":["-c","npx -y pkg@1.0.0 --key \"zqxa32\""]},
 "a33-nbsp-cmd": {"command":"npx\u00a0--key\u00a0zqxa33\u00a0pkg","args":[]},
 "a34-u2028-wrap": {"command":"bash","args":["-c","K=zqxa34\u2028npx -y pkg@1.0.0"]},
 "a35-tab-arg": {"command":"npx","args":["-y","pkg@1.0.0\tzqxa35"]},
 "a36-cr-arg": {"command":"npx","args":["-y","pkg@1.0.0\rzqxa36"]},
 "a37-nl-arg": {"command":"npx","args":["-y","pkg@1.0.0\nzqxa37"]},
 "a38-nbsp-arg": {"command":"npx","args":["-y","pkg@1.0.0\u00a0zqxa38"]},
 "a39-pwsh-spaced": {"command":"pwsh","args":["-Command","$Env:K = \"zqxa39\" ; npx -y pkg@1.0.0"]},
 "a40-pwsh-brace": {"command":"powershell.exe","args":["-c","${env:K}='zqxa40'; npx -y pkg@1.0.0"]},
 "a41-pwsh-setitem": {"command":"pwsh","args":["-Command","Set-Item env:K zqxa41; npx -y pkg@1.0.0"]},
 "a42-pwsh-escq": {"command":"pwsh","args":["-Command","$env:K='zq''xa42'; npx -y pkg@1.0.0"]},
 "a43-cmd-caret": {"command":"cmd.exe","args":["/C","set K=zq^&xa43&& npx -y pkg@1.0.0"]},
 "a44-cmd-quoted": {"command":"cmd","args":["/s","/c","set \"K=zqxa44\" && npx -y pkg@1.0.0"]},
 "a45-cmd-noamp": {"command":"cmd","args":["/c","set K=zqxa45 npx -y pkg@1.0.0"]},
 "a46-cmd-setA": {"command":"cmd","args":["/c","set /a K=zqxa46&& npx -y pkg@1.0.0"]},
 "a47-json-u0040": {"type":"http","url":"https://u:zqxa47\u0040h.example.com/mcp"},
 "a48-dupkey": {"type":"http","url":"https://u:zqxa48@h.example.com/","url":"https://h2.example.com/"},
 "a49-long": {"command":"npx","args":["-y","pkg@1.0.0","--k","zqxa49aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]},
 "a50-env-S": {"command":"env","args":["-S","K=zqxa50 npx -y pkg@1.0.0 --t zqxa50b"]},
 "a51-env-u": {"command":"env","args":["-u","zqxa51","npx","pkg@1.0.0"]},
 "a52-py-at-url": {"command":"uvx","args":["--from","tool @ https://u:zqxa52@h.example.com/o/r/x.whl?t=zqxa52b","tool"]},
 "a53-uv-index": {"command":"uvx","args":["--index-url","https://u:zqxa53@pypi.example/simple","tool==1.0"]},
 "a54-npm-registry": {"command":"npx","args":["--registry=https://u:zqxa54@r.example/","-y","pkg@1.0.0"]},
 "a55-npx-p-url": {"command":"npx","args":["-p","https://u:zqxa55@r.example.com/a/b/p-1.0.0.tgz","bin"]},
 "a56-docker-H": {"command":"docker","args":["-H","tcp://u:zqxa56@h:2376","run","img:1"]},
 "a57-bash-lc-meta": {"command":"sh","args":["-lc","npx -y pkg@1.0.0 && echo zqxa57"]},
 "a58-cmd-quoted-prog": {"command":"\"C:\u005cProgram Files\u005cn\u005cnpx.cmd\" --key zqxa58 pkg","args":[]},
 "a59-url-tab": {"type":"http","url":"https://zqxa59.evil\t/@h.example.com/"},
 "a60-url-backslash2": {"type":"http","url":"https://evil.example\u005c@h.example.com/"},
 "a61-remote-no-type": {"url":"https://h.example.com/","headers":{"Authorization":"Bearer zqxa61"},"env":{"x":"zqxa61b"}},
 "a62-npm-alias-at": {"command":"npx","args":["x@npm:y@zqxa62:q"]},
 "a63-bun-x": {"command":"bun","args":["x","--api-key","zqxa63","pkg@1.0.0"]},
 "a64-pipx": {"command":"pipx","args":["run","--pip-args=--index-url=https://u:zqxa64@x/","tool==1.0"]},
 "a65-docker-e-last": {"command":"docker","args":["run","img:1","-e","K=zqxa65"]},
 "a66-bash-c-only-assign": {"command":"bash","args":["-c","K=zqxa66"]},
 "a67-env-only-assign": {"command":"env","args":["K=zqxa67"]},
 "a68-npx-dashdash": {"command":"npx","args":["--","pkg@1.0.0","zqxa68"]},
 "a69-uvx-with": {"command":"uvx","args":["--with","https://u:zqxa69@x.example/o/r","tool"]},
 "a70-yarn-dlx-flag": {"command":"yarn","args":["dlx","-p","pkg@1.0.0","--token","zqxa70","bin"]}
}}
JSON

run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/gate3 adv3.json" --config "$FIX/gate3 adv2.json" --date 2026-01-02
assert_eq "run 11 exits 0" 0 "$RC"
assert_eq "run 11 prints one row per case" 82 "$(printf '%s\n' "$OUT" | sed -n '3,$p' | grep -vc '^#')"
for wrapped in b01 b02 b03 b04 b05 b06 b07 b08 b09 b10 b11 b12; do
  check_row "$wrapped" local - unparsed -
done
check_row a31-bash-escape local - unparsed -
check_row a34-u2028-wrap local - unparsed -
check_row a20-url-backslash remote - unparsed -
check_row a60-url-backslash2 remote - unparsed -
check_row a53-uv-index uvx tool==1.0 exact index:pypi.example
check_row a64-pipx pipx tool==1.0 exact index:x
check_row a17-url-ipv6 remote 'https://[::1]:8443' n/a '[::1]'
check_row a21-url-query remote https://h.example.com n/a h.example.com

# --- Run 12: managed validity (type, invisible characters) and precedence -------

mkdir -p "$FIX/gate pm1" "$FIX/gate pm2x" "$FIX/gate proj"
cat >"$FIX/gate pm1/managed-settings.json" <<'JSON'
{"managedMcpServers": {
  "all": {"type": "http", "url": "https://ms-all.example.com/mcp"},
  "stdiotype": {"type": "stdio", "url": "https://ms-st.example.com/mcp"},
  "zw": {"type": "http", "url": "https://ms-zw.example.com/mcp", "headers": {"X-K": "a\u200bb"}},
  "plainhttp": {"type": "http", "url": "http://ms-ph.example.com/mcp"},
  "withenv": {"type": "http", "url": "https://ms-env.example.com/mcp", "env": {}}
}}
JSON
cp "$FIX/gate pm1/managed-settings.json" "$FIX/gate pm2x/managed-settings.json"
cat >"$FIX/gate pm2x/managed-mcp.json" <<'JSON'
{"mcpServers": {"all": {"type": "http", "url": "https://mm-all.example.com/mcp"}}}
JSON
cat >"$FIX/gate claude.json" <<'JSON'
{"mcpServers": {
  "all": {"command": "npx", "args": ["-y", "u-all@1.0.0"]},
  "up": {"command": "npx", "args": ["-y", "u-up@1.0.0"]},
  "stdiotype": {"command": "npx", "args": ["-y", "u-st@1.0.0"]},
  "zw": {"command": "npx", "args": ["-y", "u-zw@1.0.0"]}
 },
 "projects": {"F:\u005cGate": {
   "mcpServers": {"all": {"command": "npx", "args": ["-y", "l-all@1.0.0"]}, "lp": {"command": "npx", "args": ["-y", "l-lp@1.0.0"]}},
   "enabledMcpjsonServers": ["up"]
 }}}
JSON
cat >"$FIX/gate proj/.mcp.json" <<'JSON'
{"mcpServers": {
  "all": {"command": "npx", "args": ["-y", "p-all@1.0.0"]},
  "up": {"command": "npx", "args": ["-y", "p-up@1.0.0"]},
  "lp": {"command": "npx", "args": ["-y", "p-lp@1.0.0"]}
}}
JSON

run_inv --claude-json "$FIX/gate claude.json" --project "f:/gate" --mcp-json "$FIX/gate proj/.mcp.json" \
  --managed-dir "$FIX/gate pm1" --date 2026-01-02
assert_eq "run 12 exits 0" 0 "$RC"
assert_eq "valid managed-settings entry" "yes" "$(cell managed-settings all 3)"
assert_eq "managed-settings stdio type rejected" "rejected-by-client" "$(cell managed-settings stdiotype 3)"
assert_eq "managed-settings zero-width header rejected" "rejected-by-client" "$(cell managed-settings zw 3)"
assert_eq "managed-settings http url rejected" "rejected-by-client" "$(cell managed-settings plainhttp 3)"
assert_eq "managed-settings env member rejected" "rejected-by-client" "$(cell managed-settings withenv 3)"
assert_eq "user row behind managed-settings" "shadowed-by:managed-settings" "$(cell user all 3)"
assert_eq "local row behind managed-settings" "shadowed-by:managed-settings" "$(cell local all 3)"
assert_eq "project row behind managed-settings" "shadowed-by:managed-settings" "$(cell project all 3)"
assert_eq "rejected stdio-type entry shadows nothing" "yes" "$(cell user stdiotype 3)"
assert_eq "rejected zero-width entry shadows nothing" "yes" "$(cell user zw 3)"
assert_eq "user row behind approved project row" "shadowed-by:project" "$(cell user up 3)"
assert_eq "approved project row" "yes" "$(cell project up 3)"
assert_eq "local row" "yes" "$(cell local lp 3)"
assert_eq "project row behind local" "shadowed-by:local" "$(cell project lp 3)"

run_inv --claude-json "$FIX/gate claude.json" --project "f:/gate" --mcp-json "$FIX/gate proj/.mcp.json" \
  --managed-dir "$FIX/gate pm2x" --date 2026-01-02
assert_eq "managed-mcp.json row" "yes" "$(cell managed all 3)"
assert_eq "managed-settings row behind managed-mcp.json" "shadowed-by:managed" "$(cell managed-settings all 3)"
assert_eq "user row suppressed by managed-mcp.json" "suppressed-by-managed" "$(cell user all 3)"
assert_eq "project row suppressed by managed-mcp.json" "suppressed-by-managed" "$(cell project up 3)"

# --- Run 13: conservative wrapper parsing (fourth re-attack sample, zqyNNN tokens) --
# Every leaking case plus every eighth held case; c320 (a GitHub-token-shaped name) and
# c336 (a 5000-character padding case) are left out.

cat >"$FIX/reattack4 cases.json" <<'JSON'
{"mcpServers": {
  "c008":{"command":"env","args":["-S","TOKEN=ab\nzqy008 node s.js"]},
  "c016":{"command":"env","args":["-S","TOKEN=ab\u000bzqy016 node s.js"]},
  "c024":{"command":"env","args":["-S","TOKEN=ab\fzqy024 node s.js"]},
  "c032":{"command":"env","args":["-S","TOKEN=ab\rzqy032 node s.js"]},
  "c040":{"command":"pwsh","args":["-c","$env:TOKEN='ab zqy040'; node s.js"]},
  "c048":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u0085zqy048'; node s.js"]},
  "c056":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u00a0zqy056'; node s.js"]},
  "c064":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u1680zqy064'; node s.js"]},
  "c072":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2000zqy072'; node s.js"]},
  "c080":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2001zqy080'; node s.js"]},
  "c088":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2002zqy088'; node s.js"]},
  "c096":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2003zqy096'; node s.js"]},
  "c104":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2004zqy104'; node s.js"]},
  "c112":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2005zqy112'; node s.js"]},
  "c120":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2006zqy120'; node s.js"]},
  "c128":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2007zqy128'; node s.js"]},
  "c136":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2008zqy136'; node s.js"]},
  "c144":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2009zqy144'; node s.js"]},
  "c152":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u200azqy152'; node s.js"]},
  "c160":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2028zqy160'; node s.js"]},
  "c168":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u2029zqy168'; node s.js"]},
  "c176":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u202fzqy176'; node s.js"]},
  "c184":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u205fzqy184'; node s.js"]},
  "c192":{"command":"pwsh","args":["-c","$env:TOKEN='ab\u3000zqy192'; node s.js"]},
  "c200":{"command":"dash","args":["-ec","B=zqy200 node s.js"]},
  "c208":{"command":"bash","args":["-c","node s.js $'zqy208'"]},
  "c215":{"command":"bash","args":["-c","IFS=_; node_zqy215"]},
  "c216":{"command":"bash","args":["-c","node s.js <<zqy216"]},
  "c220":{"command":"bash","args":["-c","'X=1' zqy220"]},
  "c221":{"command":"bash","args":["-c","\"X\"=1 zqy221"]},
  "c224":{"command":"bash","args":["-c","X='zqy224 node s.js"]},
  "c232":{"command":"bash","args":["-c","V0=x V1=x V2=x V3=x V4=x V5=x V6=x V7=x V8=x V9=x V10=x V11=x V12=x V13=x V14=x V15=x V16=x V17=x V18=x V19=x V20=x V21=x V22=x V23=x V24=x V25=x V26=x V27=x V28=x V29=x K=zqy232 W0=y W1=y W2=y W3=y W4=y W5=y W6=y W7=y W8=y W9=y W10=y W11=y W12=y W13=y W14=y W15=y W16=y W17=y W18=y W19=y W20=y W21=y W22=y W23=y W24=y W25=y W26=y W27=y W28=y W29=y node s.js"]},
  "c240":{"command":"env","args":["-u","zqy240","node","s.js"]},
  "c248":{"command":"env","args":["-","TOKEN=zqy248","node"]},
  "c252":{"command":"env","args":["X=1","-S","zqy252"]},
  "c253":{"command":"env","args":["X=1","--","zqy253"]},
  "c254":{"command":"env","args":["X=1","-i","zqy254"]},
  "c255":{"command":"env","args":["X=1","-","zqy255"]},
  "c256":{"command":"env","args":["X=1","-u","Y","zqy256"]},
  "c262":{"command":"cmd","args":["/c","set \"TOKEN=ab\"zqy262"]},
  "c263":{"command":"cmd","args":["/c","set \"TOKEN=ab\" zqy263"]},
  "c264":{"command":"cmd","args":["/c","set TOKEN=ab^&zqy264"]},
  "c265":{"command":"cmd","args":["/c","set TOKEN=ab^&zqy265 node s.js"]},
  "c272":{"command":"cmd","args":["/c","no^de s.js zqy272"]},
  "c280":{"command":"pwsh","args":["-c","Set-Item env:TOKEN zqy280; node s.js"]},
  "c283":{"command":"pwsh","args":["-c","$env:TOKEN='ab''zqy283'''"]},
  "c284":{"command":"pwsh","args":["-c","$env:TOKEN='ab''zqy284' node s.js"]},
  "c285":{"command":"pwsh","args":["-c","$env:TOKEN=\"ab\"\"zqy285\"\"\""]},
  "c286":{"command":"pwsh","args":["-c","$env:TOKEN='ab'zqy286 node s.js"]},
  "c287":{"command":"pwsh","args":["-c","$env:TOKEN='ab' zqy287"]},
  "c288":{"command":"pwsh","args":["-c","$env:TOKEN=zqy288 node s.js"]},
  "c289":{"command":"pwsh","args":["-NoProfile","-File","run.ps1","-c","zqy289"]},
  "c290":{"command":"powershell.exe","args":["-File","run.ps1","-Command","zqy290","-Token","zqy291"]},
  "c296":{"command":"pwsh","args":["-c","node s.js `zqy297"]},
  "c297":{"command":"pwsh","args":["-c","'X=1' zqy298"]},
  "c303":{"command":"pwsh","args":["-c","bash -c \"'X=1' zqy304\""]},
  "c304":{"command":"sh","args":["-c","env -S 'X=zqy305 node s.js'"]},
  "c306":{"command":"bash","args":["-c","bash -c \"'X=1' zqy307\""]},
  "c307":{"command":"cmd","args":["/c","bash -c \"'X=1' zqy308\""]},
  "c312":{"command":"pwsh","args":["-c","npx -y pkg@1.0.0 --key zqy313"]},
  "c324":{"command":"bash","args":["-c","zqy326ab12-cd34ef56-gh78ij90-kl12mn34"]},
  "c328":{"command":"cmd","args":["/c","set A=1& zqy330Ab12Cd34Ef56Gh78xx"]},
  "c342":{"command":"TOKEN=abc","args":["zqy344","s.js"]}
}}
JSON

# Safe-but-wrong parses: a dropped assignment hiding shell syntax, or an odd program name.
cat >"$FIX/wrapper rules.json" <<'JSON'
{"mcpServers": {
  "sw-semi": {"command": "bash", "args": ["-c", "X=1; node s.js --t LEAKSW1"]},
  "sw-subst": {"command": "bash", "args": ["-c", "X=$(cat f) node s.js"]},
  "sw-pipe": {"command": "bash", "args": ["-c", "X=1 node s.js | tee LEAKSW2"]},
  "sw-and": {"command": "bash", "args": ["-c", "X=1 && node s.js"]},
  "sw-tick": {"command": "bash", "args": ["-c", "X=`id` node s.js"]},
  "sw-dash": {"command": "bash", "args": ["-c", "-x node"]},
  "sw-dashdash": {"command": "bash", "args": ["-c", "-- node"]},
  "sw-exec": {"command": "bash", "args": ["-c", "X=1 exec node s.js"]},
  "sw-eval": {"command": "bash", "args": ["-c", "eval node s.js"]},
  "sw-set": {"command": "bash", "args": ["-c", "set -e"]},
  "sw-quote": {"command": "bash", "args": ["-c", "npx -y 'q@1.0.0'"]},
  "sw-pwsh-file": {"command": "pwsh", "args": ["-File", "run.ps1"]},
  "sw-pwsh-enc": {"command": "powershell", "args": ["-EncodedCommand", "abc"]},
  "sw-cmd-v": {"command": "cmd", "args": ["/v:on", "/c", "npx -y pkg@1.0.0"]},
  "sw-env-after": {"command": "env", "args": ["X=1", "-i", "node"]},
  "sw-cmd-eq": {"command": "A=B", "args": ["node"]},
  "ok-pwsh-opts": {"command": "pwsh", "args": ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
    "-Command", "npx -y pkg@1.0.0"]},
  "ok-cmd-opts": {"command": "cmd", "args": ["/d", "/q", "/v:off", "/c", "npx -y pkg@1.0.0"]},
  "ok-env-chain": {"command": "env", "args": ["A=1", "B=2", "npx", "pkg@1.0.0"]},
  "ok-bash-assign": {"command": "bash", "args": ["-c", "A=1 B=x.y npx -y pkg@1.0.0"]}
}}
JSON

run_inv --claude-json "$FIX/nope.json" --project "$FIX/proj" --mcp-json "$FIX/nope.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/reattack4 cases.json" --config "$FIX/wrapper rules.json" \
  --date 2026-01-02
assert_eq "run 13 exits 0" 0 "$RC"
for wrapped in c220 c221 c252 c253 c254 c255 c256 c262 c263 c264 c265 c283 c284 c285 c286 c287 c289 c290 \
  c297 c303 c306 c307 c342 sw-semi sw-subst sw-pipe sw-and sw-tick sw-dash sw-dashdash sw-exec sw-eval \
  sw-set sw-quote sw-pwsh-file sw-pwsh-enc sw-cmd-v sw-env-after sw-cmd-eq; do
  check_row "$wrapped" local - unparsed -
done
check_row c324 local - unparsed -
check_row ok-pwsh-opts npx pkg@1.0.0 exact unscoped
check_row ok-cmd-opts npx pkg@1.0.0 exact unscoped
check_row ok-env-chain npx pkg@1.0.0 exact unscoped
check_row ok-bash-assign npx pkg@1.0.0 exact unscoped

# --- Exit 2 cases --------------------------------------------------------------

printf '%s\n' '{not json' >"$FIX/bad.json"
printf '%s\n' '{"mcpServers": "./x.json"}' >"$FIX/string-servers.json"
printf '%s\n' '{"mcpServers": ["./x.json"]}' >"$FIX/array-servers.json"
printf '%s\n' '{"name": "p"}' >"$FIX/no-servers.json"
printf '%s\n' '{"mcpServers": 5}' >"$FIX/number-servers.json"

run_inv --claude-json "$FIX/bad.json" --project "$FIX/proj" --mcp-json "$FIX/proj/.mcp.json" \
  --managed-dir "$FIX/no managed" --date 2026-01-02
assert_eq "invalid JSON exits 2" 2 "$RC"
assert_contains "invalid JSON names the file" "$ERR" "$FIX/bad.json"

run_inv --claude-json "$FIX/claude.json" --project "$FIX/proj" --mcp-json "$FIX/proj/.mcp.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/string-servers.json" --config "$FIX/array-servers.json" \
  --config "$FIX/no-servers.json" --date 2026-01-02
assert_eq "string or array mcpServers does not exit 2" 0 "$RC"
assert_contains "string mcpServers skipped" "$OUT" \
  "# source file $FIX/string-servers.json skipped (mcpServers is a path; pass that file as --config)"
assert_contains "array mcpServers skipped" "$OUT" \
  "# source file $FIX/array-servers.json skipped (mcpServers is a path; pass that file as --config)"
assert_contains "file without a server map is found-empty" "$OUT" "# source file $FIX/no-servers.json found-empty"

run_inv --claude-json "$FIX/claude.json" --project "$FIX/proj" --mcp-json "$FIX/proj/.mcp.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/number-servers.json" --date 2026-01-02
assert_eq "number mcpServers exits 2" 2 "$RC"
assert_contains "number mcpServers names the file" "$ERR" "$FIX/number-servers.json"

run_inv --bogus
assert_eq "unknown flag exits 2" 2 "$RC"

run_inv --date
assert_eq "flag without value exits 2" 2 "$RC"

run_inv --help
assert_eq "--help exits 0" 0 "$RC"
assert_contains "--help prints usage" "$OUT" "Usage:"

# jq missing: PATH holds only an empty directory, so no jq resolves.
OUT="$(PATH="$FIX/empty bin" "$BASH" "$INV" --claude-json "$FIX/claude.json" --project "$FIX/proj" \
  --mcp-json "$FIX/proj/.mcp.json" --managed-dir "$FIX/no managed" --date 2026-01-02 2>"$FIX/stderr.txt")"
RC=$?
ERR="$(<"$FIX/stderr.txt")"
ALL+="$OUT$ERR"
assert_eq "jq missing exits 2" 2 "$RC"
assert_contains "jq missing names jq" "$ERR" "jq"

# --- Planted secrets never reach stdout or stderr of any run -------------------
# Every LEAK*/SECRET* token and every ZQXnnn id planted in any fixture is checked
# against the combined stdout and stderr of every run above.

planted="$(grep -rhoE '(LEAK|SECRET)[A-Z0-9_]*|ZQX[0-9]{3}' --include='*.json' "$FIX" | LC_ALL=C sort -u)"
assert_eq "planted secret tokens were collected" "yes" "$([[ -n "$planted" ]] && echo yes)"
assert_eq "all 85 re-attack ids were collected" 85 "$(printf '%s\n' "$planted" | grep -c '^ZQX')"
second="$(grep -hoE 'ZQX[A-Za-z0-9]*' "$FIX/reattack2 cases.cfg" | LC_ALL=C sort -u)"
assert_eq "second re-attack tokens were collected" "yes" "$([[ -n "$second" ]] && echo yes)"
planted+=$'\n'"$second"
third="$(grep -rhoE 'zqx[a-z0-9]*|xa[0-9]{2}|zqy[0-9]{3}' --include='*.json' "$FIX" | LC_ALL=C sort -u)"
assert_eq "re-gate lower-case tokens were collected" "yes" "$([[ "$third" == *zqxb01* && "$third" == *xa31* && "$third" == *zqy220* ]] && echo yes)"
planted+=$'\n'"$third"
while IFS= read -r secret; do
  [[ -z "$secret" ]] && continue
  assert_not_contains "secret $secret never emitted" "$ALL" "$secret"
done <<<"$planted"

if [[ $FAILED -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE" >&2
exit 1
