#!/usr/bin/env bash
# verify-load.sh — prove a migrated instruction surface actually loads.
#
# WHY. Every other check in this plugin is static: the glob parses, it matches
# tracked files, the index is in sync. None of them observes Claude Code
# actually loading anything. That gap is where this plugin's own bugs lived —
# a rule can pass every static gate and still never enter context, because
# discovery missed it, because nothing imports the file, or because the trigger
# is a read and nothing read a matching file.
#
# This closes the loop empirically. It runs the real CLI against the real
# repository with an InstructionsLoaded hook attached, touches a file the
# surface claims to cover, and reports which instruction files Claude Code
# actually loaded and why.
#
# HOW IT STAYS SAFE. The probe never mutates the repository under test:
#   * the hook is installed into a TEMPORARY settings file passed with
#     --settings, never into the repository's own .claude/settings.json;
#   * the probe prompt is read-only and the run is confined to --allowedTools Read;
#   * the hook only appends to a log outside the repository.
#
# HOW IT STAYS HONEST. If the CLI is absent, unauthenticated, or times out, this
# reports UNKNOWN and exits 3. It never reports a surface as verified because
# the probe failed to run — an unverifiable result is not a passing one.
#
# Usage:
#   verify-load.sh --trigger <path> [--expect <file>]... [options]
#
#   --trigger <path>   repo-relative file to read, which should fire the surface
#   --expect <file>    an instruction file that MUST load (repeatable)
#   --root <dir>       repository root (default: cwd)
#   --claude <path>    CLI to use (default: `claude` on PATH)
#   --timeout <secs>   probe timeout (default: 240)
#
# Output (TSV):
#   LOADED    file  load_reason  trigger  globs
#   EXPECTED  file  MET|MISSING
#   VERDICT   PASS|FAIL|UNKNOWN  reason
#
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
LOG="$WORK/loaded.log"
SETTINGS="$WORK/settings.json"

# The hook writes OUTSIDE the repository under test, so a probe never leaves a
# trace in the tree it is measuring.
cat >"$SETTINGS" <<JSON
{
  "hooks": {
    "InstructionsLoaded": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -c 'del(.session_id,.transcript_path,.cwd,.prompt_id)' >> '$LOG'"
          }
        ]
      }
    ]
  }
}
JSON

PROMPT="Use the Read tool on ${TRIGGER}. Then reply with exactly the word DONE and nothing else."

if ! timeout "$PROBE_TIMEOUT" "$CLAUDE_BIN" -p "$PROMPT" \
  --settings "$SETTINGS" --allowedTools Read >"$WORK/out.txt" 2>"$WORK/err.txt"; then
  rc=$?
  if ((rc == 124)); then
    unknown "the probe timed out after ${PROBE_TIMEOUT}s"
  fi
  unknown "the CLI exited $rc: $(head -c 200 "$WORK/err.txt" | tr '\n' ' ')"
fi

[[ -s "$LOG" ]] ||
  unknown "the InstructionsLoaded hook produced no records; the CLI may not support it here"

# Emit what actually loaded.
jq -r '[
    (.file_path // "?"),
    (.load_reason // "?"),
    (.trigger_file_path // "-"),
    ((.globs // ["-"]) | join(","))
  ] | @tsv' "$LOG" 2>/dev/null | LC_ALL=C sort -u | sed 's|^|LOADED\t|'

MISSING=0
if ((${#EXPECT[@]} > 0)); then
  loaded_files="$(jq -r '.file_path // empty' "$LOG" 2>/dev/null)"
  for want in "${EXPECT[@]}"; do
    # Match the WHOLE path or a complete path-component suffix — never a bare
    # substring. A plain `grep -F` marks `rules/rule.md` as MET when the only
    # loaded path is `/repo/old-rules/rule.md`, which lets a verification tool
    # report PASS for a surface that never loaded. For a tool whose entire job is
    # not lying about what loaded, that is the worst possible defect.
    want_norm="${want#./}"
    matched=0
    while IFS= read -r loaded; do
      [[ -n "$loaded" ]] || continue
      if [[ "$loaded" == "$want_norm" || "$loaded" == */"$want_norm" ]]; then
        matched=1
        break
      fi
    done <<<"$loaded_files"
    if ((matched == 1)); then
      printf 'EXPECTED\t%s\tMET\n' "$want"
    else
      printf 'EXPECTED\t%s\tMISSING\n' "$want"
      MISSING=$((MISSING + 1))
    fi
  done
fi

if ((MISSING > 0)); then
  printf 'VERDICT\tFAIL\t%d expected surface(s) did not load on reading %s\n' "$MISSING" "$TRIGGER"
  exit 1
fi

printf 'VERDICT\tPASS\tevery expected surface loaded on reading %s\n' "$TRIGGER"
exit 0
