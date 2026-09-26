#!/usr/bin/env bash
# Inventory every MCP server in the resolved Claude Code configuration for audit-posture.
#
# Static only: reads config files, never runs anything a config names, never touches the network.
# Output (stdout): a dated title line, a TSV header, one row per server sorted by scope then
# name, `# source <scope> <path> <status>` lines (found, found-empty, skipped (...), absent),
# then `# not read:` and `# not evaluated:` footer lines. Output is allowlisted: a config value
# reaches stdout only when the raw value fully matches a strict package, image, URL, path, or
# name grammar; anything else prints as "-" (pin "unparsed") or redacted-name(<length>).
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
META_LOCAL='{"matched": false, "disabled": [], "disabledJson": [], "enabledJson": [], "enableAll": false}'
SKIPPED_TEXT="skipped (mcpServers is a path; pass that file as --config)"

# Value filter applied to every emitted package, publisher, name, and drop-in file name:
# split on / @ : = # . _ - [ ] and space; reject a value over 100 characters, a segment over
# 40, a known secret prefix at the start or after a non-alphanumeric character, or a segment
# of 20+ characters holding at least three digits and three letters. A segment that is
# exactly a 64-hex digest or 40-hex commit passes. AWS key prefixes (AKIA, ASIA) match only
# in upper case, since AWS key ids are upper case and lower-case "asia" is an ordinary word.
# A UUID anywhere, or a run of 32+ hex digits other than a trailing #<40 hex> git commit or
# @sha256:<64 hex> digest, is also rejected.
# shellcheck disable=SC2016
JQ_VF='def vf:
  (length <= 100)
  and (test("(^|[^A-Za-z0-9])(sk-|sk_|ghp_|gho_|ghs_|ghu_|github_pat_|xox[abprs]-|aiza|eyj|glpat-)"; "i") | not)
  and (test("(^|[^A-Za-z0-9])(AKIA|ASIA)") | not)
  and (test("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}") | not)
  and (sub("#[0-9a-f]{40}$"; "") | sub("@sha256:[0-9a-f]{64}$"; "") | test("[0-9a-fA-F]{32,}") | not)
  and ([splits("[/@:=#._\\[\\] -]")]
       | all(.[]; test("^([0-9a-f]{64}|[0-9a-f]{40})$")
                  or (length <= 40
                      and (length < 20 or ([scan("[0-9]")] | length) < 3 or ([scan("[A-Za-z]")] | length) < 3))));'

add_source() {
  SOURCES+="# source $1 $2 $3"$'\n'
}

die_json() {
  echo "inventory.sh: $1: $2" >&2
  exit 2
}

# check_json <file> <shown>: exit 2 unless the file parses as JSON.
check_json() {
  jq empty <"$1" >/dev/null 2>&1 || die_json "unparsable JSON" "$2"
}

# dropin_shown <path>: the path to print for a managed-settings.d drop-in; a file name that
# fails the value filter prints as redacted-file.
dropin_shown() {
  if jq -en --arg f "${1##*/}" "$JQ_VF"' $f | vf' >/dev/null 2>&1; then
    printf '%s' "$1"
  else
    printf '%s/redacted-file' "${1%/*}"
  fi
}

# add_rows <file> <scope> <filter> <shown>: append {scope,name,cfg} JSON lines for the server
# map the filter selects and set STATUS: found, found-empty (no map), or the skipped text
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
    die_json "non-object server map" "$4"
  STATUS="${out%%$'\n'*}"
  [[ "$STATUS" == "skipped" ]] && STATUS="$SKIPPED_TEXT"
  if [[ "$out" == *$'\n'* ]]; then
    ROWS+="${out#*$'\n'}"$'\n'
  fi
}

# shellcheck disable=SC2016
LOCAL_FILTER='[(.projects // {}) | to_entries[] | select((.key | norm) == ($p | norm))] | first | .value'

# add_file_source <scope> <file> <filter> [shown]: read one file-backed source or report it
# absent. A path holding a control character exits 2 without echoing it.
add_file_source() {
  local shown="${4:-$2}"
  if [[ "$2" == *[[:cntrl:]]* ]]; then
    echo "inventory.sh: a $1 source path contains a control character" >&2
    exit 2
  fi
  if [[ -f "$2" ]]; then
    check_json "$2" "$shown"
    add_rows "$2" "$1" "$3" "$shown"
    add_source "$1" "$shown" "$STATUS"
    return 0
  fi
  add_source "$1" "$shown" absent
  return 1
}

# User and local scope: ~/.claude.json.
if add_file_source user "$CLAUDE_JSON" '.mcpServers'; then
  META_LOCAL="$(jq -c --arg p "$PROJECT_KEY" "$JQ_NORM"'
    ('"$LOCAL_FILTER"') as $v
    | def names: if type == "array" then map(tostring) else [] end;
    {matched: ($v != null),
     disabled: ($v.disabledMcpServers // [] | names),
     disabledJson: ($v.disabledMcpjsonServers // [] | names),
     enabledJson: ($v.enabledMcpjsonServers // [] | names),
     enableAll: ($v.enableAllProjectMcpServers == true)}' <"$CLAUDE_JSON" 2>/dev/null | tr -d '\r')" ||
    die_json "non-object projects map" "$CLAUDE_JSON"
  if [[ "$META_LOCAL" == '{"matched":true'* ]]; then
    add_rows "$CLAUDE_JSON" local "($LOCAL_FILTER).mcpServers" "$CLAUDE_JSON"
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
  add_file_source managed-settings "$dropin" '.managedMcpServers' "$(dropin_shown "$dropin")"
done
shopt -u nullglob

for config in ${CONFIGS[@]+"${CONFIGS[@]}"}; do
  add_file_source file "$config" '.mcpServers'
done

# Classification. Output is allowlisted: a package, image, URL, path, or host reaches stdout
# only when the raw value fully matches one of the grammars below, with nothing stripped
# first except URL userinfo. Anything else prints package "-", pin "unparsed", publisher "-".
# Wrapper strings (bash -c, cmd /c, pwsh -Command, env -S) are split with a quote-aware
# tokenizer after known assignment prefixes are dropped; a remaining shell metacharacter or
# an unbalanced quote makes the row unparsed.
# shellcheck disable=SC2016
CLASSIFY='
def clean: tostring | gsub("[[:cntrl:]]"; "");
def SQ: [39] | implode;
def DQ: "\"";
def unparsed_mark: "\u0000unparsed";
def runners: ["npx", "npm", "pnpm", "pnpx", "yarn", "bunx", "bun", "uvx", "uv", "pipx", "docker", "podman", "nerdctl"];
def basename_of: gsub("\\\\"; "/") | (split("/") | last) // "";
def lc_base: basename_of | ascii_downcase | sub("\\.(cmd|exe)$"; "");
def is_assign: test("^[A-Za-z_][A-Za-z0-9_]*=([^=]|$)");
def drop_assign: until(length == 0 or (.[0] | is_assign | not); .[1:]);
def shell_split: [splits("[ \t\r\n]+")] | map(select(length > 0));
def metachar: test("[;&|$`(){}<>\\\\\n\r]");
def quoted_re: SQ + "[^" + SQ + "]*" + SQ + "|" + DQ + "[^" + DQ + "]*" + DQ;
def qsplit:
  if (gsub(quoted_re; "") | test("[" + SQ + DQ + "]")) then null
  else [scan("(?:[^[:space:]" + SQ + DQ + "]+|" + quoted_re + ")+")] end;
def unquote:
  gsub(SQ + "(?<a>[^" + SQ + "]*)" + SQ; "\(.a)") | gsub(DQ + "(?<a>[^" + DQ + "]*)" + DQ; "\(.a)");
def wrap_tokens:
  if length > 4096 or test("[\n\r]") then [unparsed_mark]
  else qsplit as $raw
  | if $raw == null then [unparsed_mark]
    else ($raw | drop_assign) as $rest
    | if any($rest[]; metachar) then [unparsed_mark] else ($rest | map(unquote)) end
    end
  end;
# PowerShell drive and variable names are case-insensitive: $env:X, $Env:X, ${env:X}.
def drop_pwsh_env:
  sub("^[[:space:]]*\\$(env:[A-Za-z_][A-Za-z0-9_]*|\\{env:[A-Za-z_][A-Za-z0-9_]*\\})[[:space:]]*=[[:space:]]*(" + quoted_re + "|[^;]*);?"; ""; "i") as $n
  | if $n == . then . else ($n | drop_pwsh_env) end;
def drop_cmd_set:
  sub("^[[:space:]]*set[[:space:]]+(\"[A-Za-z_][A-Za-z0-9_]*=[^\"]*\"|[A-Za-z_][A-Za-z0-9_]*=[^&]*)[[:space:]]*(&&?)?"; ""; "i") as $n
  | if $n == . then . else ($n | drop_cmd_set) end;
def shell_c_string:
  if length == 0 then null
  elif (.[0] | test("^-[A-Za-z]*c$")) then (.[1] // null)
  elif (.[0] | startswith("-")) then (.[1:] | shell_c_string)
  else null end;
def env_rest:
  if length == 0 then .
  elif (.[0] | is_assign) then (.[1:] | env_rest)
  elif IN(.[0]; "-u", "--unset", "-C", "--chdir", "-P", "-a", "--argv0") then (.[2:] | env_rest)
  elif (.[0] | test("^--(unset|chdir|argv0)=")) then (.[1:] | env_rest)
  elif IN(.[0]; "-S", "--split-string") then (((.[1] // "") | wrap_tokens) + .[2:])
  elif (.[0] | startswith("--split-string=")) then ((.[0] | sub("^--split-string="; "") | wrap_tokens) + .[1:])
  elif IN(.[0]; "-i", "--ignore-environment", "-0", "--null", "-v", "--debug", "-", "--") then (.[1:] | env_rest)
  elif (.[0] | startswith("-")) then [unparsed_mark]
  else . end;
def rest_after($opts):
  ([to_entries[] | select(.value | ascii_downcase | IN(.; $opts[])) | .key] | first) as $i
  | if $i == null then null else .[$i + 1:] end;
def unwrap:
  drop_assign
  | if length == 0 or .[0] == unparsed_mark then .
    else (.[0] | lc_base) as $b
    | .[1:] as $a
    | if IN($b; "cmd", "pwsh", "powershell") then
        (($a | rest_after(if $b == "cmd" then ["/c", "/k"] else ["-command", "-c", "-commandwithargs", "-cwa"] end)) as $r
         | if $r == null then .
           else ($r | join(" ") | if $b == "cmd" then drop_cmd_set else drop_pwsh_env end | wrap_tokens | unwrap) end)
      elif IN($b; "bash", "sh", "zsh", "dash", "ash", "ksh") then
        (($a | shell_c_string) as $s | if $s == null then . else ($s | wrap_tokens | unwrap) end)
      elif $b == "env" then ($a | env_rest | unwrap)
      else . end
    end;
# $tail is what may follow the path: a 40-hex commit for package specs, or any query or
# fragment for remote rows, which print only scheme://host[:port].
def url_parts($prefix; $schemes; $tail):
  (capture("^(?<s>" + $prefix + "(" + $schemes + ")://)([^/?#@]*@)?(?<h>[A-Za-z0-9.-]+|\\[[0-9A-Fa-f:.]+\\])(?<p>:[0-9]+)?(?<path>/[A-Za-z0-9._~/+-]*)?(?<c>" + $tail + ")?$")
   | {scheme: .s, host: .h, port: (.p // ""), path: (.path // ""), commit: (.c // "")}) // null;
# A git spec prints only its first two path segments (owner/repo); a tarball prints only its
# file name, with "/..." standing in for any directories before it.
def url_spec:
  url_parts("(git\\+)?"; "https?|ssh|git"; "#[0-9a-f]{40}") as $m
  | if $m == null then null
    else ($m.path | split("/") | map(select(length > 0))) as $segs
    | ($m.scheme + $m.host + $m.port) as $origin
    | if ($m.scheme | test("^https?://$")) and ($m.path | test("\\.(tgz|tar\\.gz)$")) then
        {package: ($origin + (if ($segs | length) > 1 then "/.../" else "/" end) + ($segs | last)), pub: $m.host,
         pin: (if $m.host == "registry.npmjs.org" and ($m.path | test("-[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?\\.tgz$"))
               then "exact" else "tarball" end)}
      else {package: ($origin + ($segs[:2] | map("/" + .) | join("")) + $m.commit), pub: $m.host,
            pin: (if $m.commit != "" then "git-commit" else "git-ref" end)} end
    end;
def path_spec:
  if test("^(\\./|\\.\\./|~/|/|file:(\\./|\\.\\./|/)?)[A-Za-z0-9._~/+-]*$")
  then {package: ., pin: "local-path", pub: "local"} else null end;
def gh_spec:
  ((capture("^(github:)?(?<o>[A-Za-z0-9._-]+)/[A-Za-z0-9._-]+(?<c>#[0-9a-f]{40})?$")) // null) as $m
  | if $m == null then null
    else {package: ., pin: (if $m.c != null then "git-commit" else "git-ref" end), pub: ("github:" + $m.o)} end;
def ref_spec: path_spec // url_spec // gh_spec;
def NPM_NAME: "(@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*";
def NPM_VER: "[A-Za-z0-9._+~^*<>=|-]*";
def npm_ver:
  if . == "" then "floating-unversioned"
  elif test("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$") then "exact"
  elif test("[\\^~*<>=| ]") or test("(^|\\.)[xX](\\.|$)") or test("^v?[0-9]+(\\.[0-9]+)?$") then "floating-range"
  else "floating-tag" end;
def npm_plain:
  capture("^(?<n>" + NPM_NAME + ")(@(?<v>.*))?$") as $c
  | {pin: (($c.v // "") | npm_ver), pub: (if startswith("@") then (split("/") | .[0]) else "unscoped" end)};
def npm_spec:
  . as $s
  | if test("^" + NPM_NAME + "(@" + NPM_VER + ")?$") then {package: $s} + npm_plain
    elif test("^" + NPM_NAME + "@npm:" + NPM_NAME + "(@" + NPM_VER + ")?$") then
      {package: $s} + (sub("^" + NPM_NAME + "@npm:"; "") | npm_plain)
    elif ref_spec != null then ref_spec
    else
      ((capture("^(?<n>" + NPM_NAME + ")@(?<u>.+)$")) // null) as $c
      | if $c == null then null
        else ($c.u | url_spec) as $k | if $k == null then null else $k + {package: ($c.n + "@" + $k.package)} end end
    end;
def PY_NAME: "[A-Za-z0-9._-]+(\\[[A-Za-z0-9._,-]+\\])?";
def py_pin:
  gsub("\\[[^\\]]*\\]"; "") as $s
  | if ($s | contains("@")) then
      (($s | sub("^[^@]*@"; "")) | if test("^[0-9][0-9A-Za-z.+!-]*$") then "exact" else "floating-tag" end)
    elif ($s | test("===?")) and ($s | test("[<>!~*,]") | not) then "exact"
    elif ($s | test("[<>!~=*,]")) then "floating-range"
    else "floating-unversioned" end;
def py_spec:
  . as $s
  | if test("^" + PY_NAME + "((==|===|>=|<=|~=|!=|<|>|@)[A-Za-z0-9.*+!_-]+(,(==|>=|<=|~=|!=|<|>)[A-Za-z0-9.*+!_-]+)*)?$")
    then {package: $s, pin: py_pin, pub: "pypi"}
    elif ref_spec != null then ref_spec
    else
      ((capture("^(?<n>" + PY_NAME + ") *@ *(?<u>.+)$")) // null) as $c
      | if $c == null then null
        else ($c.u | url_spec) as $k | if $k == null then null else $k + {package: ($c.n + " @ " + $k.package)} end end
    end;
def img_spec:
  if test("^([a-z0-9.-]+(:[0-9]+)?/)?[a-z0-9._-]+(/[a-z0-9._-]+)*(:[A-Za-z0-9._-]{1,128})?(@sha256:[0-9a-f]{64})?$") then
    (sub("@.*$"; "") | split("/")) as $p
    | {package: .,
       pub: (if ($p | length) <= 1 then "library" else ($p[:-1] | join("/")) end),
       pin: (if test("@sha256:") then "digest"
             elif ($p | last | contains(":")) then
               (if ($p | last | split(":") | .[1]) == "latest" then "floating-tag" else "mutable-tag" end)
             else "floating-unversioned" end)}
  else null end;
def parse_args($pkgflags; $vals; $bools):
  def go($p):
    if length == 0 then $p
    else .[0] as $t
    | if IN($t; $pkgflags[]) then (.[1] as $v | .[2:] | go($v))
      elif any($pkgflags[]; . as $f | $t | startswith($f + "=")) then (($t | sub("^[^=]*="; "")) as $v | .[1:] | go($v))
      elif IN($t; $vals[]) then (.[2:] | go($p))
      elif $t == "--" or IN($t; $bools[]) then (.[1:] | go($p))
      elif ($t | test("^-[A-Za-z].")) and any($vals[]; test("^-[A-Za-z]$") and (. as $v | $t | startswith($v)))
        then (.[1:] | go($p))
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
# pkgrow: allow maps the raw spec to {package, pin, pub} when it fits a grammar, else null.
def pkgrow($l; $spec; allow):
  if $spec == null or $spec == "" then {launcher: $l, package: "-", pin: "not-a-package", publisher: "-"}
  elif ($spec | length) > 4096 then {launcher: $l, package: "-", pin: "unparsed", publisher: "-"}
  else ($spec | allow) as $k
  | if $k == null then {launcher: $l, package: "-", pin: "unparsed", publisher: "-"}
    else {launcher: $l, package: $k.package, pin: $k.pin, publisher: $k.pub} end
  end;
def stdio_row:
  . as $t
  | (($t[0] // "") | lc_base) as $b
  | ($t[1] // "") as $a1
  | if ($t[0] // "") == unparsed_mark then {launcher: "local", package: "-", pin: "unparsed", publisher: "-"}
    elif $b == "npx" then pkgrow("npx"; $t[1:] | npm_pkg; npm_spec)
    elif $b == "npm" and ($a1 == "exec" or $a1 == "x") then pkgrow("npm-exec"; $t[2:] | npm_pkg; npm_spec)
    elif $b == "pnpm" and $a1 == "dlx" then pkgrow("pnpm-dlx"; $t[2:] | npm_pkg; npm_spec)
    elif $b == "pnpx" then pkgrow("pnpx"; $t[1:] | npm_pkg; npm_spec)
    elif $b == "yarn" and $a1 == "dlx" then pkgrow("yarn-dlx"; $t[2:] | npm_pkg; npm_spec)
    elif $b == "bunx" then pkgrow("bunx"; $t[1:] | npm_pkg; npm_spec)
    elif $b == "bun" and $a1 == "x" then pkgrow("bunx"; $t[2:] | npm_pkg; npm_spec)
    elif $b == "uvx" then pkgrow("uvx"; $t[1:] | py_pkg; py_spec)
    elif $b == "uv" and $a1 == "tool" and ($t[2] // "") == "run" then pkgrow("uv-tool-run"; $t[3:] | py_pkg; py_spec)
    elif $b == "pipx" and $a1 == "run" then pkgrow("pipx"; $t[2:] | pipx_pkg; py_spec)
    elif IN($b; "docker", "podman", "nerdctl") then
      pkgrow($b; ($t[1:] | (indices("run") | first) as $i | if $i == null then null else .[$i + 1:] | img_of end);
        img_spec)
    else
      ($t[1:] | map(shell_split[] | lc_base) | any(.[]; IN(.; runners[]))) as $wrapped
      | (($t[0] // "") | basename_of) as $n
      | if $n == "" then {launcher: "local", package: "-", pin: "not-a-package", publisher: "local"}
        elif ($n | test("^[A-Za-z0-9._+-]+$") | not) then {launcher: "local", package: "-", pin: "unparsed", publisher: "-"}
        elif $wrapped then {launcher: "local", package: "-", pin: "wrapped", publisher: "local"}
        else {launcher: "local", package: $n, pin: "not-a-package", publisher: "local"} end
    end;
def classify:
  (.cfg | if type == "object" then . else {} end) as $c
  | (if $c.type == null then (if ($c.url | type) == "string" then "http" else "stdio" end)
     elif $c.type == "streamable-http" then "http"
     elif IN($c.type; "stdio", "http", "sse", "sdk") then $c.type
     else "unknown" end) as $transport
  | if $transport == "unknown" then
      {launcher: "-", package: "-", pin: "unparsed", publisher: "-", sandboxed: "n/a"}
    elif $transport == "sdk" then
      {launcher: "sdk", package: "-", pin: "n/a", publisher: "-", sandboxed: "n/a"}
    elif $transport != "stdio" then
      ((if ($c.url | type) == "string" then $c.url else "" end) | url_parts(""; "https?"; "[?#].*")) as $m
      | if $m == null then {launcher: "remote", package: "-", pin: "unparsed", publisher: "-", sandboxed: "n/a"}
        else {launcher: "remote", package: ($m.scheme + $m.host + $m.port), pin: "n/a",
              publisher: $m.host, sandboxed: "n/a"} end
    else
      # A command whose final path segment holds whitespace or any control character is a
      # command line, not a program path; a non-string command or argument cannot be read.
      ($c.command // "") as $cmd0
      | ($c.args // []) as $args
      | ($cmd0 | if type == "string" then sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "") else "" end) as $cmd
      | if ($cmd | test("[[:cntrl:]]")) or ($cmd | basename_of | test("[[:space:]]")) then
          {launcher: "local", package: "-", pin: "unparsed", publisher: "-", sandboxed: "no"}
        elif ($cmd0 | type) != "string" or ($args | type) != "array" or ($args | length) > 256
          or any($args[]; type != "string") then
          {launcher: ([$cmd] | stdio_row | .launcher), package: "-", pin: "unparsed", publisher: "-", sandboxed: "no"}
        else ([$cmd] + $args) | unwrap | stdio_row | . + {sandboxed: "no"}
        end
    end
  | . + {transport: $transport};
def rank: {managed: 5, "managed-settings": 4, local: 3, project: 2, user: 1}[.] // 0;
def overridable: IN(.; "user", "local", "project", "file");
def opt_out: IN(.; "user", "local", "file", "managed-settings");
def secret_name:
  test("^(sk-|sk_|ghp_|gho_|ghs_|ghu_|github_pat_|xox[abprs]-|akia|asia|aiza|glpat-|eyj)"; "i")
  or test("[A-Za-z0-9_-]{32,}")
  or test("^[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+){2,}$");
def shown_name:
  if test("^[A-Za-z0-9._ -]{1,64}$") and (secret_name | not) and vf then . else "redacted-name(\(length))" end;
# withhold: a package or publisher that fails the value filter withholds the whole value.
def withhold:
  if (.package != "-" and (.package | vf | not))
     or ((.publisher | IN("-", "local", "unscoped", "pypi", "library") | not) and (.publisher | vf | not))
  then . + {package: "-", pin: "unparsed", publisher: "-"} else . end;
def ms_valid:
  if (.cfg | type) != "object" then false
  else (.name | test("^[A-Za-z0-9_-]+$"))
    and ((.cfg.url | type) == "string")
    and ((.cfg.url // "") | tostring | startswith("https://"))
    and (any(.cfg | keys[]; IN(.; "command", "args", "env", "headersHelper")) | not)
    and (any(.cfg | .. | strings; contains("${")) | not)
  end;
def approved: . as $n | $meta.enableAll or any($meta.enabledJson[]; . == $n);

([.[] | select(.scope != "managed-settings")]
 + (reduce (.[] | select(.scope == "managed-settings")) as $r ({}; .[$r.name] = $r) | [.[]]))
| map(. + {rejected: (.scope == "managed-settings" and (ms_valid | not))}) as $rows
| $rows[]
| . as $r
| ($r.scope | rank) as $rk
| ([$rows[] | select((.rejected | not) and .name == $r.name and (.scope | rank) > $rk)] | max_by(.scope | rank)) as $w
| (if $r.rejected then "rejected-by-client"
   elif $managed and ($r.scope | overridable) then "suppressed-by-managed"
   elif ($r.scope | opt_out) and any($meta.disabled[]; . == $r.name) then "disabled"
   elif $r.scope == "project" and any($meta.disabledJson[]; . == $r.name) then "disabled"
   elif $w != null then
     (if $w.scope == "project" and ($w.name | approved | not) and (any($meta.disabledJson[]; . == $w.name) | not)
      then "shadowed-by:project-if-approved" else "shadowed-by:" + $w.scope end)
   elif $r.scope == "project" and ($r.name | approved | not) then "approval-unknown"
   else "yes" end) as $effective
| ($r | classify | withhold) as $k
| [$r.scope, ($r.name | shown_name), $effective, $k.transport, $k.launcher, $k.package, $k.pin, $k.publisher, $k.sandboxed]
| map(clean)
'

TABLE="$(printf '%s' "$ROWS" | jq -rs --argjson meta "$META_LOCAL" --argjson managed "$MANAGED_PRESENT" \
  "$JQ_VF [$CLASSIFY] | sort_by(.[0], .[1]) | .[] | @tsv" 2>/dev/null | tr -d '\r')" || {
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
  '# not evaluated: allowedMcpServers/deniedMcpServers (see /claude-config:audit)' \
  '# not evaluated: project approval in settings files (enabledMcpjsonServers, enableAllProjectMcpServers); only the ~/.claude.json project entry is read, so an unapproved project row shows approval-unknown' \
  '# not evaluated: file-scope rows are not checked for precedence against other scopes' \
  '# not evaluated: managed-settings.d drop-ins are merged by whole entry per name; key-level merging is not modeled'
exit 0
