#!/usr/bin/env bash
# Emit MCP tool manifest facts for the mcp-tool-audit skill.
#
# Discovery config: reference/server-discovery.md
# Output: Server count, then one block per tool (Server, Runtime, Tool file, Tool, Tool line).
# Scan root: the git repository root, or the directory given to --path.
# --path is bounded to ${CLAUDE_PROJECT_DIR} (or the git root when that is unset);
# a path resolving outside it is refused (exit 3). The scan is depth-capped.
# Exit: 0 normally, 2 on argument error, 3 on an out-of-bounds --path.
set -u

MAX_SCAN_DEPTH=12

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
--path is bounded to the project directory (${CLAUDE_PROJECT_DIR}, or the
git root when unset); a path outside it is refused. The scan is depth-capped.

Exit: 0 normally, 2 on argument error, 3 on an out-of-bounds --path.
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
project_root=""
scan_prefix=""
if [[ -n "$SCAN_PATH" ]]; then
  if [[ ! -d "$SCAN_PATH" ]]; then
    echo "Server count: 0"
    echo "Error: scan path is not a directory: $SCAN_PATH"
    exit 0
  fi
  # Canonicalize the scan path and the project boundary the same way (cd + pwd -P,
  # portable — no realpath/readlink dependency) so the prefix comparison is valid
  # regardless of symlinks, '..', or Git-Bash path form. Refuse a path that
  # resolves outside the boundary.
  scan_canon="$(cd "$SCAN_PATH" 2>/dev/null && pwd -P)"
  boundary="${CLAUDE_PROJECT_DIR:-}"
  [[ -z "$boundary" ]] && boundary="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  boundary_canon=""
  [[ -n "$boundary" ]] && boundary_canon="$(cd "$boundary" 2>/dev/null && pwd -P)"
  if [[ -n "$boundary_canon" && "$scan_canon" != "$boundary_canon" && "$scan_canon" != "$boundary_canon"/* ]]; then
    echo "discover.sh: --path '$SCAN_PATH' resolves outside the project directory ($boundary_canon); refusing to scan" >&2
    exit 3
  fi
  root="$scan_canon"
  project_root="$boundary_canon"
  [[ -z "$project_root" ]] && project_root="$root"
else
  project_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -z "$project_root" ]] && project_root="."
  root="$project_root"
fi

if [[ "$root" == "$project_root" ]]; then
  scan_prefix=""
else
  scan_prefix="${root#"$project_root"/}"
fi

if [[ ! -d "$root" ]]; then
  echo "Server count: 0"
  echo "Error: scan path is not a directory: $root"
  exit 0
fi
cd "$root" || exit 0

# to_project_rel <path-relative-to-scan-root> — emit a path relative to project_root.
to_project_rel() {
  local f="${1#./}"
  if [[ -n "$scan_prefix" ]]; then
    printf '%s/%s' "$scan_prefix" "$f"
  else
    printf '%s' "$f"
  fi
}

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
  rel="$(to_project_rel "$file")"
  server="$(derive_server "$rel")"
  while IFS= read -r line_num; do
    [[ -z "$line_num" ]] && continue
    tool_name="$(sed -n "${line_num},$((line_num + 6))p" "$file" 2>/dev/null \
      | grep -oE "['\"][a-zA-Z][a-zA-Z0-9_.-]*['\"]" | head -1 | tr -d "'\"")
    [[ -z "$tool_name" ]] && continue
    add_record "$server" typescript "$rel" "$tool_name" "$line_num"
  done < <(grep -nE 'server\.(register)?[tT]ool\(' "$file" 2>/dev/null | cut -d: -f1 | tr -d '\r' || true)
done < <(find . -maxdepth "$MAX_SCAN_DEPTH" -type f -name '*.ts' \
  ! -path '*/node_modules/*' ! -path '*/build/*' ! -path '*/dist/*' \
  ! -name '*.test.ts' ! -name '*.spec.ts' 2>/dev/null | LC_ALL=C sort)

# Python — FastMCP
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  rel="$(to_project_rel "$file")"
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
done < <(find . -maxdepth "$MAX_SCAN_DEPTH" -type f -name '*.py' \
  ! -path '*/.venv/*' ! -path '*/__pycache__/*' \
  ! -name '*_test.py' ! -name 'test_*.py' 2>/dev/null | LC_ALL=C sort)

# .NET — ModelContextProtocol
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  rel="$(to_project_rel "$file")"
  server="$(derive_server "$rel")"
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    line_num="${hit%%:*}"
    method_line=""
    offset=1
    while [[ $offset -le 12 ]]; do
      candidate="$(sed -n "$((line_num + offset))p" "$file" 2>/dev/null)"
      [[ -z "$candidate" ]] && break
      if printf '%s' "$candidate" | grep -qE '^[[:space:]]*(public|private|internal|protected).*[[:alnum:]_][[:alnum:]_]*[[:space:]]*\('; then
        method_line="$candidate"
        break
      fi
      offset=$((offset + 1))
    done
    [[ -z "$method_line" ]] && continue
    tool_name="$(printf '%s' "$method_line" | sed -n 's/^[[:space:]]*\(public\|private\|internal\|protected\).*[[:space:]]\+\([A-Za-z0-9_]*\)[[:space:]]*(.*/\2/p')"
    [[ -z "$tool_name" ]] && continue
    add_record "$server" dotnet "$rel" "$tool_name" "$line_num"
  done < <(grep -nE "\[McpServerTool\]" "$file" 2>/dev/null | tr -d '\r' || true)
done < <(find . -maxdepth "$MAX_SCAN_DEPTH" -type f -name '*.cs' \
  ! -path '*/bin/*' ! -path '*/obj/*' ! -path '*Tests/*' 2>/dev/null | LC_ALL=C sort)

server_count=0
for _ in $servers_seen; do
  server_count=$((server_count + 1))
done

printf 'Scan root: %s\n' "${scan_prefix:-.}"
printf 'Server count: %s\n' "$server_count"
[[ -n "$records" ]] && printf '%s' "$records"

exit 0
