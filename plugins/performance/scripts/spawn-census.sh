#!/usr/bin/env bash
# Count the process spawns a subject command performs.
#
# A spawn count is the drift-immune counter this plugin puts ahead of any
# duration: it does not move when the machine is loaded, so it stays the honest
# before/after metric on a box whose wall-clock timings swing several-fold
# within an hour. A counter that fails to move is also an unambiguous signal,
# where a duration that fails to move is ambiguous.
#
# Method: prepend a shim directory to the subject's PATH. Each shim logs its own
# name and then execs the real tool. Builtins never reach a shim, which is
# precisely the distinction being measured.
#
# What this refuses to do, and why (reference/harness-integrity.md):
#
#   * Invent a shim directory. The directory goes on PATH, so under rule 1 it
#     must be fixed across runs. The source harness used `mktemp -d`, changed
#     PATH every run, forced a permanent cache miss in a subject that cached
#     keyed on PATH, and reported "no improvement" while measuring its own
#     randomization. --shim-dir is required, a temporary root is rejected, and
#     a ledger keyed on the label catches a directory that moved between runs.
#   * Skip a tool it cannot resolve. The source harness did (`|| continue`),
#     which undercounts silently. Rule 2: fail, never degrade.
#   * Accept a Windows drive-letter path without being told to. Rule 6.
#
# Usage:
#   spawn-census.sh --shim-dir <dir> --label <label> [options] -- <command> [args...]
#
#   --shim-dir <dir>        REQUIRED. Stable directory prepended to PATH.
#   --label <label>         REQUIRED. Report label, and the default ledger key.
#   --tool <name>           Shim this tool. Repeatable. Replaces the default set.
#   --ledger-key <key>      Ledger key, when the label varies but the arm does not.
#   --ledger-reset          Forget this key's recorded PATH entry, once.
#   --no-ledger             Skip the recorded-PATH-entry check entirely.
#   --stdin <text>          Feed <text> to the subject on stdin.
#   --stdin-file <path>     Feed <path> to the subject on stdin.
#   --allow-windows-paths   Permit drive-letter paths in the subject command.
#
# Output, one line:
#   <label> spawns=<n> rc=<subject exit> [<tool counts>]
#
# Exit: 0 the census ran; 2 a precondition failed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"

# Ordinary external tools a shell-driven subject reaches for, plus the
# interpreter, so the one unavoidable interpreter spawn is counted and any EXTRA
# probe spawn shows up as a second entry.
DEFAULT_TOOLS=(sed dirname mv rm mkdir chmod cat basename expr tr python3)

usage() {
  cat <<'USAGE'
spawn-census.sh --shim-dir <dir> --label <label> [options] -- <command> [args...]

  --shim-dir <dir>        REQUIRED. Stable directory prepended to PATH.
  --label <label>         REQUIRED. Report label, and the default ledger key.
  --tool <name>           Shim this tool. Repeatable. Replaces the default set.
  --ledger-key <key>      Ledger key, when the label varies but the arm does not.
  --ledger-reset          Forget this key's recorded PATH entry, once.
  --no-ledger             Skip the recorded-PATH-entry check entirely.
  --stdin <text>          Feed <text> to the subject on stdin.
  --stdin-file <path>     Feed <path> to the subject on stdin.
  --allow-windows-paths   Permit drive-letter paths in the subject command.

Prints: <label> spawns=<n> rc=<subject exit> [<tool counts>]
Exit:   0 the census ran; 2 a precondition failed.
USAGE
}

SHIM_DIR=""
LABEL=""
LEDGER_KEY=""
USE_LEDGER=1
LEDGER_RESET=0
ALLOW_WINDOWS_PATHS=0
STDIN_FILE=""
STDIN_TEXT=""
HAVE_STDIN=0
TOOLS=()
SUBJECT=()

while (($# > 0)); do
  case "$1" in
  --shim-dir)
    SHIM_DIR="${2:-}"
    shift 2
    ;;
  --label)
    LABEL="${2:-}"
    shift 2
    ;;
  --tool)
    TOOLS+=("${2:-}")
    shift 2
    ;;
  --ledger-key)
    LEDGER_KEY="${2:-}"
    shift 2
    ;;
  --ledger-reset)
    LEDGER_RESET=1
    shift
    ;;
  --no-ledger)
    USE_LEDGER=0
    shift
    ;;
  --stdin)
    STDIN_TEXT="${2:-}"
    HAVE_STDIN=1
    shift 2
    ;;
  --stdin-file)
    STDIN_FILE="${2:-}"
    HAVE_STDIN=1
    shift 2
    ;;
  --allow-windows-paths)
    ALLOW_WINDOWS_PATHS=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    SUBJECT=("$@")
    break
    ;;
  *)
    harness_die "unknown argument: $1 (see --help)"
    ;;
  esac
done

[[ -n "$LABEL" ]] || harness_die "--label is required; it names the arm in the report and keys the injected-PATH ledger."
((${#SUBJECT[@]} > 0)) || harness_die "no subject command. Pass it after --, for example: --shim-dir /d/work/.shim --label before -- bash /d/repo/hook.sh"

if ((ALLOW_WINDOWS_PATHS == 0)); then
  for arg in "${SUBJECT[@]}"; do
    harness_require_posix_path "the subject command" "$arg"
  done
fi

if ((HAVE_STDIN == 1)) && [[ -n "$STDIN_FILE" && ! -f "$STDIN_FILE" ]]; then
  harness_die "--stdin-file does not exist: $STDIN_FILE"
fi

harness_resolve_shim_dir "$SHIM_DIR"
mkdir -p "$HARNESS_SHIM_DIR" || harness_die "cannot create the shim directory: $HARNESS_SHIM_DIR"

if ((${#TOOLS[@]} == 0)); then
  TOOLS=("${DEFAULT_TOOLS[@]}")
fi

# Strip any prior injection so a nested invocation does not shim its own shims,
# which would double every count and read as a regression.
REAL_PATH=":$PATH:"
REAL_PATH="${REAL_PATH//:${HARNESS_SHIM_DIR}:/:}"
REAL_PATH="${REAL_PATH#:}"
REAL_PATH="${REAL_PATH%:}"

LOG="$HARNESS_SHIM_DIR/spawns.log"

resolve_tool() {
  # `type -P` searches PATH only, so a builtin name never resolves to itself.
  # `command -v pwd` returns the bare word "pwd", and a shim exec'ing that would
  # find itself first on PATH and spin forever.
  (
    PATH="$REAL_PATH"
    type -P -- "$1" || true
  ) 2>/dev/null
}

refreshed=0
for tool in "${TOOLS[@]}"; do
  real="$(resolve_tool "$tool")"
  if [[ -z "$real" || "$real" != /* ]]; then
    harness_die "requested tool '$tool' does not resolve to an executable on PATH (got '${real:-<nothing>}'). The source harness skipped an unresolvable tool silently, which undercounts every run and reports a confident wrong number; harness-integrity.md rule 2 requires a failure instead. Drop it from --tool, or install it."
  fi
  desired="$(printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q >>%q\nexec %q "$@"\n' "$tool" "$LOG" "$real")"
  shim="$HARNESS_SHIM_DIR/$tool"
  if [[ -x "$shim" && "$(<"$shim")" == "$desired" ]]; then
    continue
  fi
  printf '%s\n' "$desired" >"$shim"
  chmod +x "$shim"
  refreshed=1
done

if ((USE_LEDGER == 1)); then
  key="${LEDGER_KEY:-$LABEL}"
  if ((LEDGER_RESET == 1)); then
    harness_ledger_reset "$key"
  fi
  harness_ledger_check "$key" "$HARNESS_SHIM_DIR"
elif ((LEDGER_RESET == 1)); then
  harness_die "--ledger-reset and --no-ledger contradict each other."
fi

if ((refreshed == 1)); then
  harness_warn "shim directory refreshed at $HARNESS_SHIM_DIR. The shims' modification times moved, so a subject that invalidates a cache on a newer interpreter will report COLD counts on this run. Treat this run as cold and re-run for the warm number."
fi

# Stdin is materialized to a FILE and redirected, never piped. A
# `printf ... | subject` pipeline under `pipefail` reports 141 whenever the
# subject exits without draining stdin, because printf takes EPIPE and is then
# the only non-zero element: the census would fabricate an exit code the subject
# never returned, intermittently, on a pipe-buffer race. It also costs a
# subshell fork per run, which is a spawn this census would then be counting
# against itself.
INPUT="/dev/null"
if ((HAVE_STDIN == 1)); then
  if [[ -n "$STDIN_FILE" ]]; then
    INPUT="$STDIN_FILE"
  else
    INPUT="$HARNESS_SHIM_DIR/stdin.payload"
    printf '%s' "$STDIN_TEXT" >"$INPUT"
  fi
fi

: >"$LOG"

set +e
PATH="$HARNESS_SHIM_DIR:$REAL_PATH" "${SUBJECT[@]}" <"$INPUT" >/dev/null 2>&1
subject_rc=$?
set -e

# 126 as well as 127. 127 is "not found" and 126 is "found but not executable",
# a directory, or a permission refusal. Both mean the subject NEVER RAN, and both
# produce a tidy `spawns=0` line that reads as a clean result. Guarding only the
# more famous of the two leaves the same false green reachable by the other.
if ((subject_rc == 127 || subject_rc == 126)); then
  harness_die "the subject command exited $subject_rc, which means the shell never ran it ($( ((subject_rc == 127)) && printf 'not found' || printf 'found but not executable, a directory, or refused by permissions')). A census of a command that never ran counts zero spawns and reads as a clean result, which is how source failures 3 and 4 reported a confident wrong verdict. Subject was: ${SUBJECT[*]}"
fi

count="$(grep -c . "$LOG" || true)"
breakdown="$(sort "$LOG" | uniq -c | tr '\n' ' ' | tr -s ' ')"

printf '%s spawns=%s rc=%s [%s]\n' "$LABEL" "$count" "$subject_rc" "${breakdown# }"
