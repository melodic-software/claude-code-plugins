#!/usr/bin/env bash
# Collect a C4 system-context record from one repository's committed config.
#
# WHY. A system context diagram is a fact only when every external system
# traces to a config key in a named file, and only the shape of that
# connection is kept. This script matches configuration. It does not execute
# it, and it does not read people out of the repository.
#
# Usage:
#   collect-context.sh [--repo <path>] [--out <file>] [--focal <name>]
#       [--actors <file>] [--generated-on <date>]
#   collect-context.sh --help
#
# Tracked files only (`git ls-files`). A gitignored or untracked file is not a
# source, so a local secret file cannot become a node. Configuration is matched
# as text and never executed.
#
# Output: context.json, schema_version 1, on stdout or in --out.
# The physical shape readers accept is fixed:
#
#   {
#     "schema_version": 1,
#     "generated_on": "YYYY-MM-DD",
#     "subject": "<github.com origin repository name, else directory basename>",
#     "focal": {"name":"...","origin":"derived"},
#     "actors": [ one {"name":...} object per line, or [] ],
#     "externals": [ one {"host":...} object per line, or [] ]
#   }
#
#   focal.origin is always "derived" (the repository being charted).
#   actors.origin is always "operator". Rows exist only when --actors is
#   passed. The file is operator-stated lines of "name<TAB>description".
#   This script never invents an actor from CODEOWNERS, git history, or prose.
#   externals.origin is always "derived". Each row is host, kind, port, file,
#   and key. The value that produced the row is not stored.
#
# Kinds: http, sql, storage, broker, authority, cache, mail.
#
# Redaction is plugins/architecture/lib/redact-connection.awk. A credential,
# token, account key, or URL userinfo cannot become a field.
#
# Portability: bash plus POSIX awk/sed. No jq, no python.
#
# Exit: 0 = a record was written; 1 = the path is not a readable directory;
# 2 = usage.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT_AWK="$SCRIPT_DIR/../../../lib/redact-connection.awk"
ASSIGN_AWK="$SCRIPT_DIR/config-assignments.awk"

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'collect-context.sh: %s\n' "$1" >&2
  exit "$2"
}

JSON_ESC=""
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  JSON_ESC="$s"
}

# Same github.com origin rule as portfolio-facts.sh (#4554). Prints the
# repository segment and returns 0, or returns 1 when the remote is not a
# github.com owner/repo URL.
github_repo_name() {
  local url="$1" scheme=0 host rest host_l repo
  [[ -n "$url" && "$url" != "unknown" ]] || return 1
  url="${url%/}"
  url="${url%.git}"
  [[ "$url" == *://* ]] && scheme=1 && url="${url#*://}"
  [[ "${url%%/*}" == *@* ]] && url="${url#*@}"
  host="${url%%[:/]*}"
  rest="${url#"$host"}"
  if [[ $scheme -eq 1 ]]; then
    [[ "$rest" =~ ^:[0-9]*/ ]] && rest="${rest#:*/}"
    if [[ "$rest" == :* ]]; then
      return 1
    fi
    rest="${rest#/}"
  else
    [[ "$rest" == :* ]] || return 1
    rest="${rest#:}"
    rest="${rest#/}"
  fi
  [[ -n "$rest" ]] || return 1
  host_l="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  [[ "$host_l" == "github.com" || "$host_l" == "www.github.com" ]] || return 1
  repo="${rest#*/}"
  repo="${repo%%/*}"
  [[ -n "$repo" && "$repo" != "$rest" ]] || return 1
  printf '%s' "$repo"
}

actor_line_is_secret() {
  local line="$1"
  case "$line" in
  *[Pp]assword=* | *[Aa]ccount[Kk]ey=* | *'?'sig=* | *'&'sig=* | *'://'*':'*'@'*)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

repo=""
out_file=""
focal=""
actors_file=""
generated_on=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --repo)
    [[ $# -ge 2 ]] || die "--repo needs a path" 2
    repo="$2"
    shift 2
    ;;
  --repo=*)
    repo="${1#--repo=}"
    shift
    ;;
  --out)
    [[ $# -ge 2 ]] || die "--out needs a path" 2
    out_file="$2"
    shift 2
    ;;
  --out=*)
    out_file="${1#--out=}"
    shift
    ;;
  --focal)
    [[ $# -ge 2 ]] || die "--focal needs a name" 2
    focal="$2"
    shift 2
    ;;
  --focal=*)
    focal="${1#--focal=}"
    shift
    ;;
  --actors)
    [[ $# -ge 2 ]] || die "--actors needs a file" 2
    actors_file="$2"
    shift 2
    ;;
  --actors=*)
    actors_file="${1#--actors=}"
    shift
    ;;
  --generated-on)
    [[ $# -ge 2 ]] || die "--generated-on needs a date" 2
    generated_on="$2"
    shift 2
    ;;
  --generated-on=*)
    generated_on="${1#--generated-on=}"
    shift
    ;;
  *)
    die "unknown argument: $1" 2
    ;;
  esac
done

if [[ -z "$repo" ]]; then
  repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$repo" ]] || repo="$(pwd)"
fi
if [[ ! -d "$repo" ]]; then
  die "not a directory: $repo" 1
fi
root="$(cd -P "$repo" 2>/dev/null && pwd)" || die "unreadable: $repo" 1
[[ -n "$generated_on" ]] || generated_on="$(date -u +%Y-%m-%d)"

subject="$(basename "$root")"
origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
if [[ -n "$origin" ]]; then
  if resolved="$(github_repo_name "$origin")"; then
    subject="$resolved"
  fi
fi
[[ -n "$focal" ]] || focal="$subject"

actors_abs=""
if [[ -n "$actors_file" ]]; then
  [[ -r "$actors_file" ]] || die "cannot read actors file: $actors_file" 1
  actors_abs="$(cd -P "$(dirname "$actors_file")" 2>/dev/null && pwd)/$(basename "$actors_file")"
fi

hits="$(mktemp)"
actor_body="$(mktemp)"
trap 'rm -f "$hits" "$actor_body"' EXIT

if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "not a git repository: $root" 1
fi

while IFS= read -r -d '' rel; do
  [[ -n "$rel" ]] || continue
  abs="$root/$rel"
  [[ -f "$abs" ]] || continue
  [[ -n "$actors_abs" && "$abs" == "$actors_abs" ]] && continue
  base="$(basename "$rel")"
  case "$base" in
  context.json | context.md | context.dsl | landscape.json | landscape.md | landscape.dsl | portfolio.md | dependency-graph.json | dependencies.md | package.json | package-lock.json | npm-shrinkwrap.json)
    continue
    ;;
  *) ;;
  esac
  bytes="$(wc -c <"$abs" | tr -d ' ')"
  [[ "$bytes" -le 524288 ]] || continue
  mode=""
  if [[ "$base" == *.json ]]; then
    mode=json
  elif [[ "$base" == *.yml || "$base" == *.yaml ]]; then
    mode=yaml
  elif [[ "$base" == *".env" || "$base" != "${base#.env}" ]]; then
    mode="env"
  elif [[ "$base" == *.xml || "$base" == *.config ]]; then
    mode=xml
  elif [[ "$base" == *.tf || "$base" == *.tfvars || "$base" == *.bicep || "$base" == *.toml ]]; then
    mode=hcl
  elif [[ "$base" == *.properties || "$base" == *.ini || "$base" == *.conf ]]; then
    mode=ini
  else
    continue
  fi
  # awk -F tab keeps an empty port. bash read would collapse it, because
  # tab is IFS whitespace, and the config key would slide into the port.
  ASSIGN_MODE="$mode" awk -f "$REDACT_AWK" -f "$ASSIGN_AWK" "$abs" |
    awk -F'\t' -v rel="$rel" '
      $1 != "" && $2 != "" && $4 != "" {
        kind = $1
        host = $2
        port = $3
        key = $4
        if (kind !~ /^(http|sql|storage|broker|authority|cache|mail)$/) next
        if (host ~ /[^a-z0-9.-]/ || index(host, ".") == 0 || index(host, "..") > 0) next
        if (port != "" && port !~ /^[0-9]+$/) next
        printf "%s\034%s\034%s\034%s\034%s\n", kind, host, port, rel, key
      }
    ' >>"$hits"
done < <(git -C "$root" ls-files -z --cached)

if [[ -s "$hits" ]]; then
  sort_hits="$(mktemp)"
  LC_ALL=C sort -u "$hits" >"$sort_hits"
  mv "$sort_hits" "$hits"
fi

if [[ -n "$actors_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -n "$line" ]] || continue
    case "$line" in
    \#*) continue ;;
    *) ;;
    esac
    if actor_line_is_secret "$line"; then
      printf 'collect-context.sh: skipped an actor line that contained connection material\n' >&2
      continue
    fi
    name="${line%%$'\t'*}"
    if [[ "$line" == *$'\t'* ]]; then
      desc="${line#*$'\t'}"
    else
      desc=""
    fi
    [[ -n "$name" ]] || continue
    json_escape "$name"
    obj="{\"name\":\"$JSON_ESC\""
    json_escape "$desc"
    obj="$obj,\"description\":\"$JSON_ESC\",\"origin\":\"operator\"}"
    printf '%s\n' "$obj" >>"$actor_body"
  done <"$actors_file"
  if [[ -s "$actor_body" ]]; then
    sort_actors="$(mktemp)"
    LC_ALL=C sort -u "$actor_body" >"$sort_actors"
    mv "$sort_actors" "$actor_body"
  fi
fi

emit_lines() {
  local key="$1" file="$2" comma="$3"
  if [[ ! -s "$file" ]]; then
    printf '  "%s": []%s\n' "$key" "$comma"
    return
  fi
  printf '  "%s": [\n' "$key"
  awk '
    NF { lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) printf "    %s%s\n", lines[i], (i < n ? "," : "")
    }
  ' "$file"
  printf '  ]%s\n' "$comma"
}

ext_body="$(mktemp)"
if [[ -s "$hits" ]]; then
  while IFS=$'\034' read -r kind host port file cfgkey; do
    [[ -n "$host" ]] || continue
    json_escape "$host"
    obj="{\"host\":\"$JSON_ESC\""
    json_escape "$kind"
    obj="$obj,\"kind\":\"$JSON_ESC\""
    json_escape "$port"
    obj="$obj,\"port\":\"$JSON_ESC\""
    json_escape "$file"
    obj="$obj,\"file\":\"$JSON_ESC\""
    json_escape "$cfgkey"
    obj="$obj,\"key\":\"$JSON_ESC\",\"origin\":\"derived\"}"
    printf '%s\n' "$obj"
  done <"$hits" >"$ext_body"
fi

record_body="$(
  json_escape "$generated_on"
  printf '{\n  "schema_version": 1,\n  "generated_on": "%s",\n' "$JSON_ESC"
  json_escape "$subject"
  printf '  "subject": "%s",\n' "$JSON_ESC"
  json_escape "$focal"
  printf '  "focal": {"name":"%s","origin":"derived"},\n' "$JSON_ESC"
  emit_lines actors "$actor_body" ","
  emit_lines externals "$ext_body" ""
  printf '}\n'
)"

rm -f "$ext_body"

if [[ -n "$out_file" ]]; then
  printf '%s\n' "$record_body" >"$out_file"
else
  printf '%s\n' "$record_body"
fi

exit 0
