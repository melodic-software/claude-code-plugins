#!/usr/bin/env bash
# Exit: 0 every --expect met; 1 an expectation missing; 2 usage error;
#       3 could not measure (no CLI, probe failed, timeout).

set -uo pipefail

usage() {
  cat <<'EOF'
verify-load.sh — prove a migrated instruction surface actually loads.

Usage:
  verify-load.sh --trigger <path> [--expect <file>]... [--root <dir>]
                 [--claude <path>] [--timeout <secs>]

Runs the real Claude Code CLI with an InstructionsLoaded hook attached, reads
<trigger>, and reports which instruction files actually loaded and why.

The repository under test is never modified: the hook lives in a temporary
--settings file, the probe is read-only, and the log is written outside the repo.

Output (TSV):
  LOADED    file  load_reason  trigger  globs
  EXPECTED  file  MET|MISSING
  VERDICT   PASS|FAIL|UNKNOWN  reason

Exit: 0 all expectations met; 1 an expectation missing; 2 usage error;
      3 could not measure — never a pass.
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

ROOT="$PWD"
TRIGGER=""
CLAUDE_BIN="claude"
PROBE_TIMEOUT=240
declare -a EXPECT=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    [[ $# -lt 2 ]] && die "--root needs a path"
    ROOT="$2"
    shift 2
    ;;
  --trigger)
    [[ $# -lt 2 ]] && die "--trigger needs a path"
    TRIGGER="$2"
    shift 2
    ;;
  --expect)
    [[ $# -lt 2 ]] && die "--expect needs a path"
    EXPECT+=("$2")
    shift 2
    ;;
  --claude)
    [[ $# -lt 2 ]] && die "--claude needs a path"
    CLAUDE_BIN="$2"
    shift 2
    ;;
  --timeout)
    [[ $# -lt 2 ]] && die "--timeout needs a number"
    [[ "$2" =~ ^[0-9]+$ ]] || die "--timeout must be an integer"
    PROBE_TIMEOUT="$2"
    shift 2
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"
[[ -n "$TRIGGER" ]] || die "--trigger is required"
cd "$ROOT" || die "cannot enter --root: $ROOT"
[[ -f "$TRIGGER" ]] || die "--trigger is not a readable file: $TRIGGER"

unknown() {
  printf 'VERDICT\tUNKNOWN\t%s\n' "$1"
  exit 3
}

command -v "$CLAUDE_BIN" >/dev/null 2>&1 ||
  unknown "the Claude Code CLI is not available as '$CLAUDE_BIN'; pass --claude <path>"
command -v jq >/dev/null 2>&1 ||
  unknown "jq is required to read the hook payloads"

WORK="$(mktemp -d)" || unknown "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT
RECORDS="$WORK/records"
mkdir -p "$RECORDS" || unknown "cannot create the record directory"
LOG="$WORK/loaded.log"
SETTINGS="$WORK/settings.json"

cat >"$SETTINGS" <<JSON
{
  "hooks": {
    "InstructionsLoaded": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -c 'del(.session_id,.transcript_path,.cwd,.prompt_id)' >> '$RECORDS/rec-'\$\$'.json'"
          }
        ]
      }
    ]
  }
}
JSON

PROMPT="Call the Read tool on the file ${TRIGGER}. This is a measurement probe: the Read call itself is the whole point, so make it yourself before you reply, do not delegate it, and do not answer from memory. After the Read returns, reply with exactly the word DONE and nothing else."

if ! timeout "$PROBE_TIMEOUT" "$CLAUDE_BIN" -p "$PROMPT" \
  --settings "$SETTINGS" --allowedTools Read --disallowedTools Agent >"$WORK/out.txt" 2>"$WORK/err.txt"; then
  rc=$?
  if ((rc == 124)); then
    unknown "the probe timed out after ${PROBE_TIMEOUT}s"
  fi
  unknown "the CLI exited $rc: $(head -c 200 "$WORK/err.txt" | tr '\n' ' ')"
fi

cat "$RECORDS"/rec-*.json >"$LOG" 2>/dev/null

[[ -s "$LOG" ]] ||
  unknown "the InstructionsLoaded hook produced no records; the CLI may not support it here"

jq -r '[
    (.file_path // "?"),
    (.load_reason // "?"),
    (.trigger_file_path // "-"),
    ((.globs // ["-"]) | join(","))
  ] | @tsv' "$LOG" 2>/dev/null | tr -d '\r' | LC_ALL=C sort -u | sed 's|^|LOADED\t|'

MISSING=0
if ((${#EXPECT[@]} > 0)); then
  loaded_files="$(jq -r '.file_path // empty' "$LOG" 2>/dev/null | tr -d '\r')"
  for want in "${EXPECT[@]}"; do
    want_norm="${want#./}"
    want_norm="${want_norm//\\//}"
    state=MISSING
    while IFS= read -r loaded; do
      [[ -n "$loaded" ]] || continue
      loaded="${loaded//\\//}"
      if [[ "$loaded" == "$want_norm" || "$loaded" == */"$want_norm" ]]; then
        state=MET
        break
      fi
    done <<<"$loaded_files"
    printf 'EXPECTED\t%s\t%s\n' "$want" "$state"
    [[ "$state" == MET ]] || MISSING=$((MISSING + 1))
  done
fi

if ((MISSING > 0)); then
  printf 'VERDICT\tFAIL\t%d expected surface(s) did not load on reading %s\n' "$MISSING" "$TRIGGER"
  exit 1
fi

printf 'VERDICT\tPASS\tevery expected surface loaded on reading %s\n' "$TRIGGER"
exit 0
