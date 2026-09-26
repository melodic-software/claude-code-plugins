#!/usr/bin/env bash
# Inventory every MCP server in the resolved Claude Code configuration for audit-posture.
#
# Static only: reads config files, never runs anything a config names, never touches the network.
# Output (stdout): a dated title line, a TSV header, one row per server sorted by scope then
# name, `# source <scope> <path> <found|absent>` lines, then `# not read:` and `# not evaluated:`
# footer lines. No env or headers value, and no argument other than the package spec, is emitted.
# Usage: inventory.sh [--claude-json F] [--project D] [--mcp-json F] [--managed-dir D]
#                     [--config F]... [--date YYYY-MM-DD] | --help
# Exit: 0 ok; 2 on a usage error, jq missing, unparsable JSON, or a non-object server map.
set -u
export LC_ALL=C

usage() {
  cat <<'EOF'
inventory.sh: list the MCP servers Claude Code would load, classified for supply-chain posture.

Usage:
  inventory.sh [--claude-json F] [--project D] [--mcp-json F] [--managed-dir D]
               [--config F]... [--date YYYY-MM-DD]
  inventory.sh --help

  --claude-json F   user and local scope (default $HOME/.claude.json)
  --project D       project whose local scope and .mcp.json are read
                    (default $CLAUDE_PROJECT_DIR, else $PWD)
  --mcp-json F      project scope (default <project>/.mcp.json)
  --managed-dir D   managed-mcp.json, managed-settings.json, managed-settings.d/*.json
                    (default per OS: /Library/Application Support/ClaudeCode,
                    /etc/claude-code, or C:/Program Files/ClaudeCode)
  --config F        extra file with an mcpServers object, scope "file" (repeatable)
  --date D          date for the title line (default today)

Reads files only. A missing file is reported as absent, not an error.
Exit: 0 ok; 2 on a usage error, jq missing, unparsable JSON, or a non-object server map.
EOF
}

CLAUDE_JSON=""
PROJECT=""
MCP_JSON=""
MANAGED_DIR=""
DATE=""
CONFIGS=()

need_value() {
  if [[ "$2" -lt 2 ]]; then
    echo "inventory.sh: $1 requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --claude-json | --project | --mcp-json | --managed-dir | --config | --date)
    need_value "$1" $#
    case "$1" in
    --claude-json) CLAUDE_JSON="$2" ;;
    --project) PROJECT="$2" ;;
    --mcp-json) MCP_JSON="$2" ;;
    --managed-dir) MANAGED_DIR="$2" ;;
    --config) CONFIGS+=("$2") ;;
    --date) DATE="$2" ;;
    *) ;;
    esac
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "inventory.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "inventory.sh: jq is required but was not found on PATH" >&2
  exit 2
fi

if [[ -n "$DATE" && ! "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "inventory.sh: --date must be YYYY-MM-DD" >&2
  exit 2
fi
[[ -z "$DATE" ]] && DATE="$(date +%F)"
[[ -z "$CLAUDE_JSON" ]] && CLAUDE_JSON="${HOME:-}/.claude.json"
[[ -z "$PROJECT" ]] && PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
[[ -z "$MCP_JSON" ]] && MCP_JSON="${PROJECT%/}/.mcp.json"
if [[ -z "$MANAGED_DIR" ]]; then
  case "$(uname -s 2>/dev/null)" in
  Darwin) MANAGED_DIR="/Library/Application Support/ClaudeCode" ;;
  MINGW* | MSYS* | CYGWIN*) MANAGED_DIR="C:/Program Files/ClaudeCode" ;;
  *) MANAGED_DIR="/etc/claude-code" ;;
  esac
fi

PROJECT_KEY="$PROJECT"
if command -v cygpath >/dev/null 2>&1; then
  converted="$(cygpath -m "$PROJECT" 2>/dev/null | tr -d '\r')"
  [[ -n "$converted" ]] && PROJECT_KEY="$converted"
fi

# Path normalization shared by the local-scope key match: backslash to slash, trailing
# slashes dropped, lowercased when the path starts with a drive letter.
JQ_NORM='def norm: gsub("\\\\"; "/") | sub("/+$"; "") | if test("^[A-Za-z]:") then ascii_downcase else . end;'

SOURCES=""
ROWS=""
MANAGED_PRESENT=false
META_LOCAL='{"matched": false, "disabled": [], "disabledJson": []}'

clean_text() {
  printf '%s' "${1//[[:cntrl:]]/}"
}

add_source() {
  SOURCES+="# source $1 $(clean_text "$2") $3"$'\n'
}

die_json() {
  echo "inventory.sh: $1: $(clean_text "$2")" >&2
  exit 2
}

# check_json <file>: exit 2 unless the file parses as JSON.
check_json() {
  jq empty <"$1" >/dev/null 2>&1 || die_json "unparsable JSON" "$1"
}

# add_rows <file> <scope> <filter>: append {scope,name,cfg} JSON lines for the server map
# the filter selects. A null map adds nothing; any other non-object exits 2.
add_rows() {
  local out
  out="$(jq -c --arg s "$2" --arg p "$PROJECT_KEY" "$JQ_NORM"'
    ('"$3"') as $m
    | if $m == null then empty
      elif ($m | type) != "object" then error("non-object server map")
      else $m | to_entries[] | {scope: $s, name: .key, cfg: .value} end' <"$1" 2>/dev/null)" ||
    die_json "non-object server map" "$1"
  [[ -n "$out" ]] && ROWS+="$(printf '%s' "$out" | tr -d '\r')"$'\n'
}

# shellcheck disable=SC2016
LOCAL_FILTER='[(.projects // {}) | to_entries[] | select((.key | norm) == ($p | norm))] | first | .value'

# User and local scope: ~/.claude.json.
if [[ -f "$CLAUDE_JSON" ]]; then
  check_json "$CLAUDE_JSON"
  add_source user "$CLAUDE_JSON" found
  add_rows "$CLAUDE_JSON" user '.mcpServers'
  META_LOCAL="$(jq -c --arg p "$PROJECT_KEY" "$JQ_NORM"'
    ('"$LOCAL_FILTER"') as $v
    | def names: if type == "array" then map(tostring) else [] end;
    {matched: ($v != null),
     disabled: ($v.disabledMcpServers // [] | names),
     disabledJson: ($v.disabledMcpjsonServers // [] | names)}' <"$CLAUDE_JSON" 2>/dev/null | tr -d '\r')" ||
    die_json "non-object projects map" "$CLAUDE_JSON"
  if [[ "$(printf '%s' "$META_LOCAL" | jq -r '.matched' | tr -d '\r')" == "true" ]]; then
    add_source local "$CLAUDE_JSON" found
    add_rows "$CLAUDE_JSON" local "($LOCAL_FILTER).mcpServers"
  else
    add_source local "$CLAUDE_JSON" absent
  fi
else
  add_source user "$CLAUDE_JSON" absent
  add_source local "$CLAUDE_JSON" absent
fi

# add_file_source <scope> <file> <filter>: read one file-backed source or report it absent.
add_file_source() {
  if [[ -f "$2" ]]; then
    check_json "$2"
    add_source "$1" "$2" found
    add_rows "$2" "$1" "$3"
    return 0
  fi
  add_source "$1" "$2" absent
  return 1
}

add_file_source project "$MCP_JSON" '.mcpServers'
add_file_source managed "$MANAGED_DIR/managed-mcp.json" '.mcpServers' && MANAGED_PRESENT=true

# managed-settings.json first, then drop-ins in name order; a later file wins per name.
add_file_source managed-settings "$MANAGED_DIR/managed-settings.json" '.managedMcpServers'
shopt -s nullglob
for dropin in "$MANAGED_DIR"/managed-settings.d/*.json; do
  add_file_source managed-settings "$dropin" '.managedMcpServers'
done
shopt -u nullglob

for config in ${CONFIGS[@]+"${CONFIGS[@]}"}; do
  add_file_source file "$config" '.mcpServers'
done

META="$(printf '%s' "$META_LOCAL" | jq -c --argjson managed "$MANAGED_PRESENT" '. + {managed: $managed}' | tr -d '\r')"

# Classification. Only the package spec (userinfo, query, and fragment stripped) and the
# command basename are ever emitted; every other argument and all env/headers are dropped.
# shellcheck disable=SC2016
CLASSIFY='
def clean: tostring | gsub("[[:cntrl:]]"; "");
def basename_of: gsub("\\\\"; "/") | (split("/") | last) // "";
def lc_base: basename_of | ascii_downcase | sub("\\.(cmd|exe)$"; "");
def ws_split: [splits("[ \t]+")] | map(select(length > 0));
def unwrap:
  if length == 0 then .
  else (.[0] | lc_base) as $b
  | if $b == "cmd" and length > 2 and ((.[1] | ascii_downcase) == "/c") then (.[2:] | join(" ") | ws_split | unwrap)
    elif ($b == "bash" or $b == "sh") and length > 2 and .[1] == "-c" then (.[2] | ws_split | unwrap)
    else . end
  end;
def scheme_re: "^[A-Za-z][A-Za-z0-9+.-]*://";
def strip_url:
  sub("^(?<s>[A-Za-z][A-Za-z0-9+.-]*://)[^/@?#]*@"; "\(.s)")
  | if test("#[0-9a-f]{40}$")
    then ((capture("^(?<a>[^?#]*)[^#]*(?<h>#[0-9a-f]{40})$") | .a + .h) // .)
    else sub("[?#].*$"; "") end;
def is_url: test(scheme_re);
def is_local_path: test("^(\\./|\\.\\./|/|~/|file:|[A-Za-z]:)");
def is_git: is_url or test("^(git\\+|git:|github:|gitlab:|bitbucket:|gist:)");
def git_pin: if test("#[0-9a-f]{40}$") then "git-commit" else "git-ref" end;
def url_host: (capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/?#:]*)") | .h) // "-";
def git_pub:
  if is_url then url_host
  elif test("^[a-z]+:") then ((capture("^(?<p>[a-z]+):(?<o>[^/]+)") | "\(.p):\(.o)") // "-")
  else "github:" + (split("/") | .[0]) end;
def npm_ver:
  if . == "" then "floating-unversioned"
  elif test("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$") then "exact"
  elif test("[\\^~*<>=| ]") or test("(^|\\.)[xX](\\.|$)") or test("^v?[0-9]+(\\.[0-9]+)?$") then "floating-range"
  else "floating-tag" end;
def npm_class:
  if is_local_path then {pin: "local-path", pub: "local"}
  elif is_git or test("^[^@][^@]*/") then {pin: git_pin, pub: git_pub}
  else
    (if startswith("@") then (capture("^(?<n>@[^/]+/[^@]*)(@(?<v>.*))?$") // {n: ., v: null})
     else (capture("^(?<n>[^@]*)(@(?<v>.*))?$") // {n: ., v: null}) end) as $c
    | ($c.v // "") as $v
    | if ($v | startswith("npm:")) then ($v[4:] | npm_class)
      else {pin: ($v | npm_ver), pub: (if startswith("@") then (split("/") | .[0]) else "unscoped" end)} end
  end;
def py_class:
  if is_local_path then {pin: "local-path", pub: "local"}
  elif is_git then {pin: git_pin, pub: git_pub}
  else gsub("\\[[^\\]]*\\]"; "") as $s
  | {pub: "pypi", pin:
      (if ($s | contains("@")) then
         ($s | sub("^[^@]*@ *"; "")) as $v
         | if $v == "latest" then "floating-tag"
           elif ($v | test("^[0-9][0-9A-Za-z.+!-]*$")) then "exact"
           else "floating-tag" end
       elif ($s | test("===?")) and ($s | test("[<>!~*,]") | not) then "exact"
       elif ($s | test("[<>!~=*,]")) then "floating-range"
       else "floating-unversioned" end)}
  end;
def img_class:
  (sub("@.*$"; "") | split("/")) as $p
  | {pub: (if ($p | length) <= 1 then "library" else ($p[:-1] | join("/")) end),
     pin: (if test("@sha256:") then "digest"
           elif ($p | last | contains(":")) then
             (if ($p | last | split(":") | .[1]) == "latest" then "floating-tag" else "mutable-tag" end)
           else "floating-unversioned" end)};
def npm_pkg:
  def go($p):
    if length == 0 then $p
    else .[0] as $t
    | if $t == "-p" or $t == "--package" then (.[1] as $v | .[2:] | go($v))
      elif ($t | startswith("--package=")) then (.[1:] | go($t[10:]))
      elif IN($t; "--registry", "--cache", "--userconfig", "-c", "--call") then (.[2:] | go($p))
      elif ($t | startswith("-")) then (.[1:] | go($p))
      else ($p // $t) end
    end;
  go(null);
def py_pkg:
  def go($f):
    if length == 0 then $f
    else .[0] as $t
    | if $t == "--from" then (.[1] as $v | .[2:] | go($v))
      elif ($t | startswith("--from=")) then (.[1:] | go($t[7:]))
      elif IN($t; "--with", "--python", "-p", "--index-url", "--extra-index-url", "--index",
              "--default-index", "--with-requirements", "--with-editable", "-w", "--find-links", "-f")
        then (.[2:] | go($f))
      elif ($t | startswith("-")) then (.[1:] | go($f))
      else ($f // $t) end
    end;
  go(null);
def pipx_pkg:
  def go($f):
    if length == 0 then $f
    else .[0] as $t
    | if $t == "--spec" then (.[1] as $v | .[2:] | go($v))
      elif ($t | startswith("--spec=")) then (.[1:] | go($t[7:]))
      elif IN($t; "--python", "--index-url", "--pip-args") then (.[2:] | go($f))
      elif ($t | startswith("-")) then (.[1:] | go($f))
      else ($f // $t) end
    end;
  go(null);
def img_of:
  if length == 0 then null
  else .[0] as $t
  | if IN($t; "-e", "--env", "--env-file", "-v", "--volume", "--mount", "--name", "--network", "-p",
          "--publish", "-w", "--workdir", "-u", "--user", "--entrypoint", "-l", "--label", "--platform",
          "--pull", "--add-host", "--device", "--cap-add", "--cap-drop")
      then (.[2:] | img_of)
    elif ($t | startswith("-")) then (.[1:] | img_of)
    else $t end
  end;
def pkgrow($l; $spec; $eco):
  if $spec == null or $spec == "" then {launcher: $l, package: "-", pin: "not-a-package", publisher: "-"}
  else ($spec | strip_url) as $s
  | ($s | if $eco == "npm" then npm_class elif $eco == "py" then py_class else img_class end) as $k
  | {launcher: $l, package: $s, pin: $k.pin, publisher: $k.pub}
  end;
def stdio_row:
  . as $t
  | (($t[0] // "") | lc_base) as $b
  | ($t[1] // "") as $a1
  | if $b == "npx" then pkgrow("npx"; $t[1:] | npm_pkg; "npm")
    elif $b == "npm" and ($a1 == "exec" or $a1 == "x") then pkgrow("npm-exec"; $t[2:] | npm_pkg; "npm")
    elif $b == "pnpm" and $a1 == "dlx" then pkgrow("pnpm-dlx"; $t[2:] | npm_pkg; "npm")
    elif $b == "yarn" and $a1 == "dlx" then pkgrow("yarn-dlx"; $t[2:] | npm_pkg; "npm")
    elif $b == "bunx" then pkgrow("bunx"; $t[1:] | npm_pkg; "npm")
    elif $b == "bun" and $a1 == "x" then pkgrow("bunx"; $t[2:] | npm_pkg; "npm")
    elif $b == "uvx" then pkgrow("uvx"; $t[1:] | py_pkg; "py")
    elif $b == "uv" and $a1 == "tool" and ($t[2] // "") == "run" then pkgrow("uv-tool-run"; $t[3:] | py_pkg; "py")
    elif $b == "pipx" and $a1 == "run" then pkgrow("pipx"; $t[2:] | pipx_pkg; "py")
    elif IN($b; "docker", "podman", "nerdctl") then
      pkgrow($b; ($t[1:] | (indices("run") | first) as $i | if $i == null then null else .[$i + 1:] | img_of end); "img")
    else {launcher: "local", package: ((($t[0] // "") | basename_of) as $n | if $n == "" then "-" else $n end),
          pin: "not-a-package", publisher: "local"}
    end;
def classify:
  (.cfg | if type == "object" then . else {} end) as $c
  | (if $c.type == "streamable-http" then "http"
     elif ($c.type | type) == "string" then $c.type
     elif ($c.url | type) == "string" then "http"
     else "stdio" end) as $transport
  | if $transport != "stdio" then
      ((($c.url // "") | tostring | capture("^(?<s>[A-Za-z][A-Za-z0-9+.-]*://)([^/@?#]*@)?(?<h>[^/?#]*)")) // null) as $m
      | {launcher: "remote",
         package: (if $m then $m.s + $m.h else "-" end),
         pin: "n/a",
         publisher: (if $m then ($m.h | sub(":[0-9]+$"; "")) else "-" end),
         sandboxed: "n/a"}
    else
      ([($c.command // "") | tostring] + ($c.args // [] | if type == "array" then map(tostring) else [] end))
      | unwrap | stdio_row | . + {sandboxed: "no"}
    end
  | . + {transport: $transport};
def rank: {local: 3, project: 2, user: 1}[.] // 0;
def overridable: IN(.; "user", "local", "project", "file");

(reduce .[] as $r ({}; .[$r.scope + "\u0000" + $r.name] = $r) | [.[]]) as $rows
| $rows[]
| . as $r
| ($r.scope | rank) as $rk
| ([$rows[] | select(.name == $r.name and (.scope | rank) > $rk)] | max_by(.scope | rank) | .scope) as $winner
| (if $meta.managed and ($r.scope | overridable) then "suppressed-by-managed"
   elif ($r.scope | overridable) and any($meta.disabled[]; . == $r.name) then "disabled"
   elif $r.scope == "project" and any($meta.disabledJson[]; . == $r.name) then "disabled"
   elif $rk > 0 and $winner != null then "shadowed-by:" + $winner
   else "yes" end) as $effective
| ($r | classify) as $k
| [$r.scope, $r.name, $effective, $k.transport, $k.launcher, $k.package, $k.pin, $k.publisher, $k.sandboxed]
| map(clean)
'

TABLE="$(printf '%s' "$ROWS" | jq -rs --argjson meta "$META" \
  "[$CLASSIFY] | sort_by(.[0], .[1]) | .[] | @tsv" | tr -d '\r')" || {
  echo "inventory.sh: classification failed" >&2
  exit 2
}

printf '# mcp-posture inventory %s\n' "$DATE"
printf 'scope\tname\teffective\ttransport\tlauncher\tpackage\tpin\tpublisher\tsandboxed\n'
[[ -n "$TABLE" ]] && printf '%s\n' "$TABLE"
printf '%s' "$SOURCES"
printf '%s\n' \
  '# not read: MDM/registry/plist policy' \
  '# not read: server-managed settings' \
  '# not read: claude.ai connectors' \
  '# not read: --mcp-config servers' \
  '# not read: plugin servers not passed as --config' \
  '# not evaluated: allowedMcpServers/deniedMcpServers, enableAllProjectMcpServers, enabledMcpjsonServers (see /claude-config:audit)'
exit 0
