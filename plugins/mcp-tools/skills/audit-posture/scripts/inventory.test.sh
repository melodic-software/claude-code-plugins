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
# cell <scope> <name> <column>: one field of the first row matching scope and name.
cell() {
  printf '%s\n' "$OUT" | awk -F'\t' -v s="$1" -v n="$2" -v c="$3" '$1 == s && $2 == n { print $c; exit }'
}
# check_row <name> <launcher> <package> <pin> <publisher>: a file-scope row's classification.
check_row() {
  assert_eq "$1 launcher" "$2" "$(cell file "$1" 5)"
  assert_eq "$1 package" "$3" "$(cell file "$1" 6)"
  assert_eq "$1 pin" "$4" "$(cell file "$1" 7)"
  assert_eq "$1 publisher" "$5" "$(cell file "$1" 8)"
}

# --- Fixtures ---------------------------------------------------------------

cat >"$FIX/claude.json" <<'JSON'
{
  "mcpServers": {
    "shared": {"command": "npx", "args": ["-y", "shared-user@1.0.0"]},
    "pu": {"command": "npx", "args": ["pu-user@1.0.0"]},
    "useronly": {"command": "uvx", "args": ["useronly==1.0.0"]},
    "dis": {"command": "npx", "args": ["dis@1.0.0"]},
    "evil\tna\nme\u001b[31m": {"command": "npx", "args": ["ctl@1.0.0"]}
  },
  "projects": {
    "C:\\Work\\Proj": {
      "mcpServers": {
        "shared": {"command": "npx", "args": ["shared-local@1.0.0"]},
        "localonly": {"command": "npx", "args": ["localonly@1.0.0"]}
      },
      "disabledMcpServers": ["dis"],
      "disabledMcpjsonServers": ["rejected"]
    },
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
    "rejected": {"command": "npx", "args": ["rejected@1.0.0"]}
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
    "cmdexe-wrap": {"command": "C:\\Windows\\System32\\CMD.EXE", "args": ["/C", "npx", "w-mcp@latest"]},
    "npx-cmd": {"command": "npx.cmd", "args": ["-y", "c-mcp@1.0.0"]},
    "bash-wrap": {"command": "bash", "args": ["-c", "npx -y b-mcp@latest --api-key SECRETBASH1"]},
    "npm-exec": {"command": "npm", "args": ["exec", "--yes", "--", "ne-mcp@1.0.0"]},
    "pnpm-dlx": {"command": "pnpm", "args": ["dlx", "pd-mcp@^2.0.0"]},
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

# --- Run 1: every source, no managed-mcp.json -------------------------------

run_inv --claude-json "$FIX/claude.json" --project "c:/work/proj" --mcp-json "$FIX/proj/.mcp.json" \
  --managed-dir "$FIX/managed one" --config "$FIX/servers a.json" --config "$FIX/plugin dir/plugin.json" \
  --config "$FIX/nope.json" --date 2026-01-02

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
assert_eq "project-only server effective" "yes" "$(cell project projonly 3)"
assert_eq "user-only server effective" "yes" "$(cell user useronly 3)"
assert_eq "file server effective without managed-mcp.json" "yes" "$(cell file npx-bare 3)"
assert_eq "managed-settings server effective" "yes" "$(cell managed-settings corp 3)"

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
  "# not evaluated: allowedMcpServers/deniedMcpServers, enableAllProjectMcpServers, enabledMcpjsonServers (see /claude-config:audit)"

# Control characters in a server name are neutralized.
assert_not_contains "no ESC byte in output" "$OUT" $'\e'
assert_eq "control chars stripped from name" "ctl@1.0.0" "$(cell user 'evilname[31m' 6)"

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
check_row npx-tarball npx https://host.example.com/x.tgz git-ref host.example.com
check_row cmd-wrap npx w-mcp@1.0.0 exact unscoped
check_row cmdexe-wrap npx w-mcp@latest floating-tag unscoped
check_row npx-cmd npx c-mcp@1.0.0 exact unscoped
check_row bash-wrap npx b-mcp@latest floating-tag unscoped
check_row npm-exec npm-exec ne-mcp@1.0.0 exact unscoped
check_row pnpm-dlx pnpm-dlx 'pd-mcp@^2.0.0' floating-range unscoped
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
check_row uvx-index uvx ix==1.0.0 exact pypi
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

# --- Planted secrets never reach stdout or stderr ----------------------------

for secret in SECRETENV1 SECRETHDR1 SECRETOAUTH1 SECRETHELPER1 SECRETAPIKEY1 SECRETREG1 SECRETREG2 \
  SECRETIDX1 SECRETFROM1 SECRETTGZ1 SECRETQTGZ1 SECRETFRAG1 SECRETURLPW1 SECRETQUERY1 SECRETDOCKER1 \
  SECRETLOCAL1 SECRETBASH1; do
  assert_not_contains "secret $secret never emitted" "$ALL" "$secret"
done

# --- Exit 2 cases --------------------------------------------------------------

printf '%s\n' '{not json' >"$FIX/bad.json"
printf '%s\n' '{"mcpServers": "./x.json"}' >"$FIX/string-servers.json"

run_inv --claude-json "$FIX/bad.json" --project "$FIX/proj" --mcp-json "$FIX/proj/.mcp.json" \
  --managed-dir "$FIX/no managed" --date 2026-01-02
assert_eq "invalid JSON exits 2" 2 "$RC"
assert_contains "invalid JSON names the file" "$ERR" "$FIX/bad.json"

run_inv --claude-json "$FIX/claude.json" --project "$FIX/proj" --mcp-json "$FIX/proj/.mcp.json" \
  --managed-dir "$FIX/no managed" --config "$FIX/string-servers.json" --date 2026-01-02
assert_eq "non-object mcpServers exits 2" 2 "$RC"
assert_contains "non-object mcpServers names the file" "$ERR" "$FIX/string-servers.json"

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
assert_eq "jq missing exits 2" 2 "$RC"
assert_contains "jq missing names jq" "$ERR" "jq"

if [[ $FAILED -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE" >&2
exit 1
