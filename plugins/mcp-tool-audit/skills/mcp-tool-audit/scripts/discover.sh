#!/usr/bin/env bash
# Emit MCP tool manifest facts for the mcp-tool-audit skill.
#
# Discovery config: reference/server-discovery.md
# Output: Server count, then one block per tool (Server, Runtime, Tool file, Tool, Tool line).
# Scan root: the git repository root, or the directory given to --path.
# Exit: always 0.
set -u

SCAN_PATH=""

usage() {
  cat <<'EOF'
discover.sh — emit MCP tool manifest facts for the mcp-tool-audit skill.

Usage:
  discover.sh
  discover.sh --path <dir>
  discover.sh --help

Scans the project (git root, or --path) for MCP tool markers across
Python (FastMCP), TypeScript (@modelcontextprotocol/sdk), and .NET.

Exit: always 0.
EOF
}

# derive_server <relative-file-path> — best-effort server label from a tool file path.
# The nearest ancestor directory above a runtime/source folder, else the top dir.
derive_server() {
  local rel="$1" seg prev="" out=""
  local IFS='/'
  # shellcheck disable=SC2086
  set -- $rel
  for seg in "$@"; do
    case "$seg" in
      node | python | dotnet | src)
        out="$prev"
        break
        ;;
      *) ;;
    esac
    prev="$seg"
  done
  [[ -z "$out" ]] && out="${rel%%/*}"
  [[ -z "$out" || "$out" == "$rel" ]] && out="(root)"
  printf '%s' "$out"
}

# emit_tool <server> <runtime> <file> <tool_name> <line_num> — print one tool manifest record.
emit_tool() {
  printf 'Server: %s\n' "$1"
  printf 'Runtime: %s\n' "$2"
  printf 'Tool file: %s\n' "$3"
  printf 'Tool: %s\n' "$4"
  printf 'Tool line: %s\n' "$5"
  printf '%s\n' '---'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      if [[ $# -lt 2 ]]; then
        echo "discover.sh: --path requires a value" >&2
        exit 2
      fi
      SCAN_PATH="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "discover.sh: unknown arg '$1'" >&2
      exit 2
      ;;
  esac
done

root=""
if [[ -n "$SCAN_PATH" ]]; then
  root="$SCAN_PATH"
else
  root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -z "$root" ]] && root="."
fi

if [[ ! -d "$root" ]]; then
  echo "Server count: 0"
  echo "Error: scan path is not a directory: $root"
  exit 0
fi
cd "$root" || exit 0

records=""
servers_seen=""

add_record() {
  records+="$(emit_tool "$1" "$2" "$3" "$4" "$5")"$'\n'
  case " $servers_seen " in
    *" $1 "*) ;;
    *) servers_seen+="$1 " ;;
  esac
}

# TypeScript — @modelcontextprotocol/sdk
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  rel="${file#./}"
  server="$(derive_server "$rel")"
  while IFS= read -r line_num; do
    [[ -z "$line_num" ]] && continue
    tool_name="$(sed -n "${line_num},$((line_num + 6))p" "$file" 2>/dev/null \
      | grep -oE '"[a-zA-Z][a-zA-Z0-9_.-]*"' | head -1 | tr -d '"')"
    [[ -z "$tool_name" ]] && continue
    add_record "$server" typescript "$rel" "$tool_name" "$line_num"
  done < <(grep -nE 'server\.(register)?[tT]ool\(' "$file" 2>/dev/null | cut -d: -f1 | tr -d '\r' || true)
done < <(find . -type f -name '*.ts' \
  ! -path '*/node_modules/*' ! -path '*/build/*' ! -path '*/dist/*' \
  ! -name '*.test.ts' ! -name '*.spec.ts' 2>/dev/null | LC_ALL=C sort)

# Python — FastMCP
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  rel="${file#./}"
  server="$(derive_server "$rel")"
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    line_num="${hit%%:*}"
    func_line="$(sed -n "$((line_num + 1))p" "$file" 2>/dev/null)"
    tool_name="$(printf '%s' "$func_line" | sed -n 's/^[[:space:]]*def[[:space:]]\+\([a-zA-Z0-9_]*\).*/\1/p')"
    [[ -z "$tool_name" ]] && tool_name="$(printf '%s' "$func_line" | sed -n 's/^[[:space:]]*async[[:space:]]\+def[[:space:]]\+\([a-zA-Z0-9_]*\).*/\1/p')"
    [[ -z "$tool_name" ]] && continue
    add_record "$server" python "$rel" "$tool_name" "$line_num"
  done < <(grep -n '@mcp\.tool' "$file" 2>/dev/null | tr -d '\r' || true)
done < <(find . -type f -name '*.py' \
  ! -path '*/.venv/*' ! -path '*/__pycache__/*' \
  ! -name '*_test.py' ! -name 'test_*.py' 2>/dev/null | LC_ALL=C sort)

# .NET — ModelContextProtocol
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  rel="${file#./}"
  server="$(derive_server "$rel")"
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    line_num="${hit%%:*}"
    method_line="$(sed -n "$((line_num + 1))p" "$file" 2>/dev/null)"
    tool_name="$(printf '%s' "$method_line" | sed -n 's/^[[:space:]]*\(public\|private\|internal\|protected\).* \([A-Za-z0-9_]*\)(.*/\2/p')"
    [[ -z "$tool_name" ]] && continue
    add_record "$server" dotnet "$rel" "$tool_name" "$line_num"
  done < <(grep -n '\[McpServerTool\]' "$file" 2>/dev/null | tr -d '\r' || true)
done < <(find . -type f -name '*.cs' \
  ! -path '*/bin/*' ! -path '*/obj/*' ! -path '*Tests/*' 2>/dev/null | LC_ALL=C sort)

server_count=0
for _ in $servers_seen; do
  server_count=$((server_count + 1))
done

printf 'Server count: %s\n' "$server_count"
[[ -n "$records" ]] && printf '%s' "$records"

exit 0
