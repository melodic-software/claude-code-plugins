#!/usr/bin/env bash
# Exit codes:
#   0  written
#   1  the write failed (directory, staging or rename); the prior file, if any,
#      is left as it was
#   2  usage error or rejected argument; nothing is written
set -uo pipefail

CDPATH=

PROG="persist-report.sh"
FILENAME="last-audit.md"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STAGED_INPUT=""
STAGED_TARGET=""
cleanup() {
  if [[ -n "$STAGED_INPUT" ]]; then rm -f "$STAGED_INPUT"; fi
  if [[ -n "$STAGED_TARGET" ]]; then rm -f "$STAGED_TARGET"; fi
  return 0
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
persist-report.sh: write last-audit.md under <plugin-data>/<component>/<state-key>/.

  persist-report.sh --plugin-data <dir> --component <name> --report <file|->
                    [--root <path>]

--plugin-data  the substituted ${CLAUDE_PLUGIN_DATA} path (absolute, no '..')
--component    the skill's directory name, one plain path segment
--report       the report body, or `-` to read it from stdin
--root         derive the state key for that directory instead of the current one

Prints the final path. Exit: 0 written; 1 the write failed; 2 usage or a
rejected argument, with nothing written.
EOF
}

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

fail_write() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 1
}

# shellcheck source=opt-value.sh
opt_value_dir="${BASH_SOURCE[0]%/*}"
[[ "$opt_value_dir" != "${BASH_SOURCE[0]}" ]] || opt_value_dir=.
source "$opt_value_dir/opt-value.sh"
OPT_VALUE_STDIN=1

PLUGIN_DATA=""
COMPONENT=""
REPORT=""
ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --plugin-data)
    require_opt_value "$PROG" "$@"
    PLUGIN_DATA="$2"
    shift 2
    ;;
  --component)
    require_opt_value "$PROG" "$@"
    COMPONENT="$2"
    shift 2
    ;;
  --report)
    require_opt_value "$PROG" "$@"
    REPORT="$2"
    shift 2
    ;;
  --root)
    require_opt_value "$PROG" "$@"
    ROOT="$2"
    shift 2
    ;;
  *)
    usage >&2
    die "unknown argument: $1"
    ;;
  esac
done

if [[ -z "$PLUGIN_DATA" ]]; then
  die "--plugin-data is required: \${CLAUDE_PLUGIN_DATA} is not exported to the Bash tool, so pass the path substituted into the skill text"
fi
case "$PLUGIN_DATA" in
/* | ?:[\\/]*) : ;;
*) die "--plugin-data must be an absolute path: $PLUGIN_DATA" ;;
esac
case "$PLUGIN_DATA" in
*[/\\].. | *[/\\]..[/\\]*) die "--plugin-data must not contain a '..' path component: $PLUGIN_DATA" ;;
*) : ;;
esac

if [[ -z "$COMPONENT" ]]; then
  die "--component is required"
fi
if [[ ! "$COMPONENT" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
  die "--component must be a plain path segment matching [A-Za-z0-9][A-Za-z0-9_.-]*: $COMPONENT"
fi
case "$COMPONENT" in
*..*) die "--component must not contain '..': $COMPONENT" ;;
*) : ;;
esac

if [[ -z "$REPORT" ]]; then
  die "--report is required: a file path, or - for stdin"
fi
if [[ "$REPORT" != "-" ]] && { [[ ! -f "$REPORT" ]] || [[ ! -r "$REPORT" ]]; }; then
  die "--report is not a readable regular file: $REPORT"
fi
if [[ -n "$ROOT" ]] && [[ ! -d "$ROOT" ]]; then
  die "--root is not a directory: $ROOT"
fi

STATE_KEY_LIB="$LIB_DIR/state-key.sh"
if [[ ! -f "$STATE_KEY_LIB" ]]; then
  die "cannot find state-key.sh at: $STATE_KEY_LIB"
fi
if [[ -n "$ROOT" ]]; then
  STATE_KEY=$(bash "$STATE_KEY_LIB" --root "$ROOT") || die "state-key.sh failed for --root $ROOT"
else
  STATE_KEY=$(bash "$STATE_KEY_LIB") || die "state-key.sh failed"
fi
if [[ -z "$STATE_KEY" ]]; then
  die "state-key.sh produced no state key"
fi

STAGED_INPUT=$(mktemp "${TMPDIR:-/tmp}/persist-report.XXXXXX") || fail_write "cannot stage the report"
if [[ "$REPORT" == "-" ]]; then
  cat >"$STAGED_INPUT" || fail_write "cannot read the report from stdin"
else
  cat -- "$REPORT" >"$STAGED_INPUT" || fail_write "cannot read the report: $REPORT"
fi
if [[ ! -s "$STAGED_INPUT" ]]; then
  die "the report is empty"
fi

DIR="$PLUGIN_DATA/$COMPONENT/$STATE_KEY"
TARGET="$DIR/$FILENAME"
mkdir -p "$DIR" || fail_write "cannot create $DIR"
STAGED_TARGET=$(mktemp "$DIR/.$FILENAME.XXXXXX") || fail_write "cannot stage in $DIR"
cat "$STAGED_INPUT" >"$STAGED_TARGET" || fail_write "cannot write $STAGED_TARGET"
chmod "$(printf '%04o' $((0666 & ~0$(umask))))" "$STAGED_TARGET" || fail_write "cannot set the mode of $STAGED_TARGET"
mv -f "$STAGED_TARGET" "$TARGET" || fail_write "cannot replace $TARGET"
STAGED_TARGET=""

printf '%s\n' "$TARGET"
