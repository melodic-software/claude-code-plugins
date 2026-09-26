#!/usr/bin/env bash
# Inventory every MCP server in the resolved Claude Code configuration for audit-posture.
#
# Static only: reads config files, never runs anything a config names, never touches the network.
# Output (stdout): a dated title line, a TSV header, one row per server sorted by scope then
# name, `# source <scope> <path> <status>` lines (found, found-empty, skipped (...), absent),
# then `# not read:` and `# not evaluated:` footer lines. No env or headers value is emitted,
# and the only argument ever emitted is a token shaped like a package spec, image ref, or path.
# Usage: inventory.sh [--claude-json F] [--project D] [--mcp-json F] [--managed-dir D]
#                     [--config F]... [--date YYYY-MM-DD] | --help
# Exit: 0 ok; 2 on a usage error, jq missing, unparsable JSON, or a number/boolean server map.
set -uo pipefail
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

Reads files only. A missing file is reported as absent, not an error; a server map that
is a string or array (a plugin.json path reference) is reported as skipped.
Exit: 0 ok; 2 on a usage error, jq missing, unparsable JSON, or a number/boolean server map.
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
STATUS=""
MANAGED_PRESENT=false
META_LOCAL='{"matched": false, "disabled": [], "disabledJson": []}'
SKIPPED_TEXT="skipped (mcpServers is a path; pass that file as --config)"

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
# the filter selects and set STATUS: found, found-empty (no map), or the skipped text
# (a string or array map). A number or boolean map exits 2.
add_rows() {
  local out
  out="$(jq -rc --arg s "$2" --arg p "$PROJECT_KEY" "$JQ_NORM"'
    ('"$3"') as $m
    | ($m | type) as $t
    | if $t == "null" then "found-empty"
      elif $t == "object" then ("found", ($m | to_entries[] | {scope: $s, name: .key, cfg: .value}))
      elif $t == "string" or $t == "array" then "skipped"
      else error("non-object server map") end' <"$1" 2>/dev/null | tr -d '\r')" ||
    die_json "non-object server map" "$1"
  STATUS="${out%%$'\n'*}"
  [[ "$STATUS" == "skipped" ]] && STATUS="$SKIPPED_TEXT"
  if [[ "$out" == *$'\n'* ]]; then
    ROWS+="${out#*$'\n'}"$'\n'
  fi
}

# shellcheck disable=SC2016
LOCAL_FILTER='[(.projects // {}) | to_entries[] | select((.key | norm) == ($p | norm))] | first | .value'

# add_file_source <scope> <file> <filter>: read one file-backed source or report it absent.
add_file_source() {
  if [[ -f "$2" ]]; then
    check_json "$2"
    add_rows "$2" "$1" "$3"
    add_source "$1" "$2" "$STATUS"
    return 0
  fi
  add_source "$1" "$2" absent
  return 1
}

# User and local scope: ~/.claude.json.
if add_file_source user "$CLAUDE_JSON" '.mcpServers'; then
  META_LOCAL="$(jq -c --arg p "$PROJECT_KEY" "$JQ_NORM"'
    ('"$LOCAL_FILTER"') as $v
    | def names: if type == "array" then map(tostring) else [] end;
    {matched: ($v != null),
     disabled: ($v.disabledMcpServers // [] | names),
     disabledJson: ($v.disabledMcpjsonServers // [] | names)}' <"$CLAUDE_JSON" 2>/dev/null | tr -d '\r')" ||
    die_json "non-object projects map" "$CLAUDE_JSON"
  if [[ "$META_LOCAL" == '{"matched":true'* ]]; then
    add_rows "$CLAUDE_JSON" local "($LOCAL_FILTER).mcpServers"
    add_source local "$CLAUDE_JSON" "$STATUS"
  else
    add_source local "$CLAUDE_JSON" absent
  fi
else
  add_source local "$CLAUDE_JSON" absent
fi

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


# Classification. The only argument ever emitted is one token that passes a package, image,
# URL, or path shape check (userinfo, query, and fragment stripped); every other argument and
# all env/headers are dropped. An unknown flag followed by a value-like token makes the package
# unknowable, so the row reports package "-" and pin "unparsed" instead of guessing.
# shellcheck disable=SC2016
CLASSIFY='
def clean: tostring | gsub("[[:cntrl:]\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]"; "");
def strip_fmt: gsub("[\u0001-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]"; "");
# A NUL-led marker fails every shape check, so pkgrow reports it as unparsed.
def unparsed_mark: "\u0000unparsed";
def runners: ["npx", "npm", "pnpm", "pnpx", "yarn", "bunx", "bun", "uvx", "uv", "pipx", "docker", "podman", "nerdctl"];
def basename_of: gsub("\\\\"; "/") | (split("/") | last) // "";
def lc_base: basename_of | ascii_downcase | sub("\\.(cmd|exe)$"; "");
def is_assign: test("^[A-Za-z_][A-Za-z0-9_]*=([^=]|$)");
def shell_split: [splits("[ \t\r\n]+")] | map(gsub("[\"\u0027\u0060]"; "")) | map(select(length > 0));
def drop_assign: until(length == 0 or (.[0] | is_assign | not); .[1:]);
def shell_c_string:
  if length == 0 then null
  elif (.[0] | test("^-[A-Za-z]*c$")) then (.[1] // null)
  elif (.[0] | startswith("-")) then (.[1:] | shell_c_string)
  else null end;
def env_rest:
  if length == 0 then .
  elif (.[0] | is_assign) then (.[1:] | env_rest)
  elif IN(.[0]; "-u", "--unset", "-C", "--chdir") then (.[2:] | env_rest)
  elif IN(.[0]; "-S", "--split-string") then (((.[1] // "") | shell_split) + .[2:])
  elif (.[0] | startswith("-")) then (.[1:] | env_rest)
  else . end;
def rest_after($opts):
  ([to_entries[] | select(.value | ascii_downcase | IN(.; $opts[])) | .key] | first) as $i
  | if $i == null then null else .[$i + 1:] end;
def unwrap:
  drop_assign
  | if length == 0 then .
    else (.[0] | lc_base) as $b
    | .[1:] as $a
    | if IN($b; "cmd", "pwsh", "powershell") then
        (($a | rest_after(if $b == "cmd" then ["/c", "/k"] else ["-command", "-c", "-commandwithargs", "-cwa"] end)) as $r
         | if $r == null then . else ($r | join(" ") | shell_split | unwrap) end)
      elif IN($b; "bash", "sh", "zsh", "dash", "ash", "ksh") then
        (($a | shell_c_string) as $s | if $s == null then . else ($s | shell_split | unwrap) end)
      elif $b == "env" then ($a | env_rest | unwrap)
      else . end
    end;
def strip_url:
  gsub("://[^/@?#[:space:]]*@"; "://")
  | if test("#[0-9a-f]{40}$")
    then ((capture("^(?<a>[^?#]*)[^#]*(?<h>#[0-9a-f]{40})$") | .a + .h) // .)
    else sub("[?#].*$"; "") end;
def is_url: test("^[A-Za-z][A-Za-z0-9+.-]*://");
def is_local_path: test("^(\\./|\\.\\./|/|~/|file:|[A-Za-z]:)");
def is_git: is_url or test("^(git\\+|git:|github:|gitlab:|bitbucket:|gist:)");
def is_ref: is_local_path or is_git;
def git_pin: if test("#[0-9a-f]{40}$") then "git-commit" else "git-ref" end;
def url_host: (capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/?#:]*)") | .h) // "-";
def git_pub:
  if is_url then url_host
  elif test("^[a-z]+:") then ((capture("^(?<p>[a-z]+):(?<o>[^/]+)") | "\(.p):\(.o)") // "-")
  else "github:" + (split("/") | .[0]) end;
def ref_class: if is_local_path then {pin: "local-path", pub: "local"} else {pin: git_pin, pub: git_pub} end;
def npm_shape:
  (test("[[:space:]]") | not) and (is_assign | not)
  and (is_ref or test("^[A-Za-z0-9._~-]+/[^[:space:]@=]+$") or test("^(@[A-Za-z0-9._~-]+/)?[A-Za-z0-9._~-]+(@.*)?$"));
def py_shape:
  (is_assign | not)
  and (is_ref or test("^[A-Za-z0-9][A-Za-z0-9._-]*(\\[[^\\]]*\\])?( *(===?|>=|<=|~=|!=|<|>|@) *[^ ].*)?$"));
def img_shape: (is_assign | not) and test("^[A-Za-z0-9][A-Za-z0-9._/:-]*(@[A-Za-z0-9]+:[A-Za-z0-9]+)?$");
def npm_ver:
  if . == "" then "floating-unversioned"
  elif test("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$") then "exact"
  elif test("[\\^~*<>=| ]") or test("(^|\\.)[xX](\\.|$)") or test("^v?[0-9]+(\\.[0-9]+)?$") then "floating-range"
  else "floating-tag" end;
def npm_class:
  if is_ref or test("^[^@][^@]*/") then ref_class
  else
    (if startswith("@") then (capture("^(?<n>@[^/]+/[^@]*)(@(?<v>.*))?$") // {n: ., v: null})
     else (capture("^(?<n>[^@]*)(@(?<v>.*))?$") // {n: ., v: null}) end) as $c
    | ($c.v // "") as $v
    | if ($v | startswith("npm:")) then ($v[4:] | npm_class)
      elif ($v | is_ref) then ($v | ref_class)
      else {pin: ($v | npm_ver), pub: (if startswith("@") then (split("/") | .[0]) else "unscoped" end)} end
  end;
def py_class:
  if is_ref then ref_class
  else gsub("\\[[^\\]]*\\]"; "") as $s
  | if ($s | contains("@")) then
      ($s | sub("^[^@]*@ *"; "")) as $v
      | if ($v | is_ref) then ($v | ref_class)
        else {pub: "pypi", pin: (if ($v | test("^[0-9][0-9A-Za-z.+!-]*$")) then "exact" else "floating-tag" end)} end
    else {pub: "pypi", pin:
      (if ($s | test("===?")) and ($s | test("[<>!~*,]") | not) then "exact"
       elif ($s | test("[<>!~=*,]")) then "floating-range"
       else "floating-unversioned" end)}
    end
  end;
def img_class:
  (sub("@.*$"; "") | split("/")) as $p
  | {pub: (if ($p | length) <= 1 then "library" else ($p[:-1] | join("/")) end),
     pin: (if test("@sha256:[0-9a-f]{64}$") then "digest"
           elif contains("@") then "mutable-tag"
           elif ($p | last | contains(":")) then
             (if ($p | last | split(":") | .[1]) == "latest" then "floating-tag" else "mutable-tag" end)
           else "floating-unversioned" end)};
def parse_args($pkgflags; $vals; $bools):
  def go($p):
    if length == 0 then $p
    else .[0] as $t
    | if IN($t; $pkgflags[]) then (.[1] as $v | .[2:] | go($v))
      elif any($pkgflags[]; . as $f | $t | startswith($f + "=")) then (($t | sub("^[^=]*="; "")) as $v | .[1:] | go($v))
      elif IN($t; $vals[]) then (.[2:] | go($p))
      elif $t == "--" or IN($t; $bools[]) then (.[1:] | go($p))
      elif ($t | startswith("-")) then
        (if ($t | test("^--[^=]+=")) or ((.[1] // "-") | startswith("-")) then (.[1:] | go($p))
         elif $p != null then $p
         else unparsed_mark end)
      else ($p // $t) end
    end;
  go(null);
def npm_pkg:
  parse_args(["-p", "--package"];
    ["--registry", "--cache", "--userconfig", "-c", "--call", "-w", "--workspace", "--node-options", "--script-shell"];
    ["-y", "--yes", "-q", "--quiet", "--no-install", "--prefer-offline", "--prefer-online", "--ignore-existing",
     "--silent", "--no", "--offline", "--workspaces", "--include-workspace-root"]);
def py_pkg:
  parse_args(["--from"];
    ["--with", "--python", "-p", "--index-url", "-i", "--extra-index-url", "--index", "--default-index",
     "--with-requirements", "--with-editable", "-w", "--find-links", "-f", "--constraints", "-c", "--overrides",
     "--cache-dir", "--directory", "--project", "--config-file", "--prerelease", "--resolution"];
    ["--isolated", "--offline", "--no-cache", "-n", "-q", "--quiet", "-v", "--verbose", "--refresh",
     "--no-progress", "--native-tls", "--no-config", "--no-python-downloads", "--managed-python",
     "--no-managed-python"]);
def pipx_pkg:
  parse_args(["--spec"];
    ["--python", "--index-url", "--pip-args", "--suffix"];
    ["--verbose", "--quiet", "--no-cache", "--include-deps", "--system-site-packages", "-v", "-q"]);
def img_of:
  parse_args([];
    ["-e", "--env", "--env-file", "-v", "--volume", "--mount", "--name", "--network", "-p", "--publish",
     "-w", "--workdir", "-u", "--user", "--entrypoint", "-l", "--label", "--label-file", "--platform", "--pull",
     "--add-host", "--device", "--cap-add", "--cap-drop", "--log-opt", "--log-driver", "--memory", "-m",
     "--memory-swap", "--memory-reservation", "--cpus", "--cpu-shares", "-c", "--cpuset-cpus", "--tmpfs",
     "--security-opt", "--ulimit", "--restart", "--hostname", "-h", "--ipc", "--pid", "--gpus", "--runtime",
     "--shm-size", "--dns", "--expose", "--health-cmd", "--group-add", "--stop-signal", "--stop-timeout",
     "--network-alias", "--cidfile", "--userns", "--uts", "--cgroupns", "--mac-address", "--ip", "--ip6",
     "--link", "--volumes-from", "--isolation", "--storage-opt", "--sysctl", "--attach", "-a",
     "--detach-keys", "--pids-limit", "--oom-score-adj", "--blkio-weight"];
    ["-i", "-t", "-d", "-it", "-ti", "-itd", "-dit", "--rm", "--init", "--privileged", "--read-only",
     "--interactive", "--tty", "--detach", "-P", "--publish-all", "--no-healthcheck", "--oom-kill-disable",
     "-q", "--quiet"]);
def pkgrow($l; $spec; shape; cls):
  if $spec == null or $spec == "" then {launcher: $l, package: "-", pin: "not-a-package", publisher: "-"}
  else ($spec | strip_url) as $s
  | if ($s | shape | not) then {launcher: $l, package: "-", pin: "unparsed", publisher: "-"}
    else ($s | cls) as $k | {launcher: $l, package: $s, pin: $k.pin, publisher: $k.pub}
    end
  end;
def stdio_row:
  . as $t
  | (($t[0] // "") | lc_base) as $b
  | ($t[1] // "") as $a1
  | if $b == "npx" then pkgrow("npx"; $t[1:] | npm_pkg; npm_shape; npm_class)
    elif $b == "npm" and ($a1 == "exec" or $a1 == "x") then pkgrow("npm-exec"; $t[2:] | npm_pkg; npm_shape; npm_class)
    elif $b == "pnpm" and $a1 == "dlx" then pkgrow("pnpm-dlx"; $t[2:] | npm_pkg; npm_shape; npm_class)
    elif $b == "yarn" and $a1 == "dlx" then pkgrow("yarn-dlx"; $t[2:] | npm_pkg; npm_shape; npm_class)
    elif $b == "bunx" then pkgrow("bunx"; $t[1:] | npm_pkg; npm_shape; npm_class)
    elif $b == "bun" and $a1 == "x" then pkgrow("bunx"; $t[2:] | npm_pkg; npm_shape; npm_class)
    elif $b == "uvx" then pkgrow("uvx"; $t[1:] | py_pkg; py_shape; py_class)
    elif $b == "uv" and $a1 == "tool" and ($t[2] // "") == "run" then
      pkgrow("uv-tool-run"; $t[3:] | py_pkg; py_shape; py_class)
    elif $b == "pipx" and $a1 == "run" then pkgrow("pipx"; $t[2:] | pipx_pkg; py_shape; py_class)
    elif IN($b; "docker", "podman", "nerdctl") then
      pkgrow($b; ($t[1:] | (indices("run") | first) as $i | if $i == null then null else .[$i + 1:] | img_of end);
        img_shape; img_class)
    else
      ($t[1:] | map(shell_split[] | lc_base) | any(.[]; IN(.; runners[]))) as $wrapped
      | {launcher: "local", package: ((($t[0] // "") | basename_of) as $n | if $n == "" then "-" else $n end),
         pin: (if $wrapped then "wrapped" else "not-a-package" end), publisher: "local"}
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
      ([$c.command // "" | if type == "string" then . else "" end]
       + ($c.args // [] | if type == "array" then map(select(type == "string")) else [] end))
      | map(strip_fmt) | unwrap | stdio_row | . + {sandboxed: "no"}
    end
  | . + {transport: $transport};
def rank: {local: 3, project: 2, user: 1}[.] // 0;
def overridable: IN(.; "user", "local", "project", "file");

([.[] | select(.scope != "managed-settings")]
 + (reduce (.[] | select(.scope == "managed-settings")) as $r ({}; .[$r.name] = $r) | [.[]])) as $rows
| $rows[]
| . as $r
| ($r.scope | rank) as $rk
| ([$rows[] | select(.name == $r.name and (.scope | rank) > $rk)] | max_by(.scope | rank) | .scope) as $winner
| (if $managed and ($r.scope | overridable) then "suppressed-by-managed"
   elif ($r.scope | overridable) and any($meta.disabled[]; . == $r.name) then "disabled"
   elif $r.scope == "project" and any($meta.disabledJson[]; . == $r.name) then "disabled"
   elif $rk > 0 and $winner != null then "shadowed-by:" + $winner
   else "yes" end) as $effective
| ($r | classify) as $k
| [$r.scope, $r.name, $effective, $k.transport, $k.launcher, $k.package, $k.pin, $k.publisher, $k.sandboxed]
| map(clean)
'

TABLE="$(printf '%s' "$ROWS" | jq -rs --argjson meta "$META_LOCAL" --argjson managed "$MANAGED_PRESENT" \
  "[$CLASSIFY] | sort_by(.[0], .[1]) | .[] | @tsv" 2>/dev/null | tr -d '\r')" || {
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
  '# not evaluated: allowedMcpServers/deniedMcpServers, enableAllProjectMcpServers, enabledMcpjsonServers (see /claude-config:audit)' \
  '# not evaluated: file-scope rows are not checked for precedence against other scopes'
exit 0
