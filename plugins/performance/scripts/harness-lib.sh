#!/usr/bin/env bash
# Shared preconditions for the performance measurement harnesses.
#
# Sourced, never executed. Every function here fails LOUD rather than degrading
# into a weaker check that passes, because a harness that silently works around
# a broken precondition reports a confident wrong number, and a confident wrong
# number is worse than no number. See reference/harness-integrity.md rules 1, 2
# and 6, and the five source-run failures the plugin README tabulates.
#
# Path handling here is not defensive tidiness. Three of those five failures
# were a `D:/...` path handed to bash under MSYS, which resolves nowhere: both
# arms exited 127, the grep found nothing in either, and the harness reported a
# clean verdict for a check that never ran.

# harness_die <message...>
#
# Terminate the CALLING script. Exit status 2 is reserved across this directory
# for "the harness could not run", kept distinct from a subject's own failure so
# a caller can tell "the thing under test is broken" from "the instrument is".
#
# Never call this from inside $( ), where `exit` would leave only the
# substitution's subshell and the caller would sail on with an empty string.
harness_die() {
  printf 'HARNESS FAIL: %s\n' "$*" >&2
  exit 2
}

# harness_warn <message...>
harness_warn() {
  printf 'HARNESS WARNING: %s\n' "$*" >&2
}

# harness_posix_form <path>
#
# Print the MSYS spelling of a path: backslashes folded to forward slashes and a
# drive letter rewritten as a root segment, so `D:\a\b` and `D:/a/b` both become
# `/d/a/b`. Pure string work, no filesystem access, so it is safe to call on a
# path that does not exist (a Windows TEMP value bash cannot cd into, say).
harness_posix_form() {
  local value="$1"
  value="${value//\\//}"
  if [[ "$value" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    local drive rest
    drive="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
    [[ -n "$rest" ]] || rest="/"
    printf '/%s%s\n' "${drive,,}" "$rest"
    return 0
  fi
  printf '%s\n' "$value"
}

# harness_require_posix_path <what> <value>
#
# Refuse a Windows drive-letter path anywhere in <value>. Matching is not
# anchored, so an embedded one inside a `bash -c` command string is caught too:
# that is the shape the source-run harnesses actually shipped.
harness_require_posix_path() {
  local what="$1" value="$2"
  local drive_letter_re='(^|[^A-Za-z0-9])[A-Za-z]:[/\]'
  if [[ "$value" =~ $drive_letter_re ]]; then
    harness_die "$what carries a Windows drive-letter path: '$value'. Under MSYS a D:/... path handed to bash resolves nowhere, so both arms of a check fail identically and the harness reports a confident wrong verdict (harness-integrity.md rule 6, source failures 3 and 4). Use the POSIX spelling: /d/... rather than D:/... . Pass --allow-windows-paths only if the subject is a native Windows program that genuinely needs the native form."
  fi
}

# harness_real_dir <path>
#
# Print the PHYSICAL path of <path> when it exists, and its POSIX spelling
# otherwise. Resolving through the filesystem rather than comparing strings is
# load-bearing on Windows: TEMP is often the 8.3 short form
# `C:\Users\<SHORT~1>\AppData\Local\Temp`, while the same directory reached
# through `/tmp` reports `/c/Users/<longname>/AppData/Local/Temp`. A string
# prefix test between those two spellings finds nothing, and a temp-rooted shim
# directory would sail straight through the check meant to catch it.
harness_real_dir() {
  local posix
  posix="$(harness_posix_form "$1")"
  (cd "$posix" 2>/dev/null && pwd -P) || printf '%s\n' "$posix"
}

# harness_resolve_shim_dir <dir>
#
# Sets the global HARNESS_SHIM_DIR to a resolved, stability-checked shim
# directory. Call it directly, never inside $( ), so harness_die can terminate.
#
# The shim directory goes on PATH for the subject, so under rule 1 it must be
# FIXED across runs. The canonical defect this refuses is `mktemp -d`: a fresh
# directory each run changed PATH each run, the subject cached keyed on PATH,
# every run was a forced cache miss, and the census reported "no improvement"
# while measuring nothing but its own randomization.
harness_resolve_shim_dir() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    harness_die "a shim directory is required and deliberately has no default. It is prepended to the subject's PATH, so under harness-integrity.md rule 1 it must be the SAME directory on every run. Pass --shim-dir with a path that persists."
  fi
  harness_require_posix_path "the shim directory" "$dir"

  local parent base resolved_parent
  parent="$(dirname "$dir")"
  base="$(basename "$dir")"
  [[ -d "$parent" ]] || harness_die "the shim directory's parent does not exist: $parent"
  resolved_parent="$(cd "$parent" && pwd -P)" || harness_die "cannot resolve the shim directory's parent: $parent"
  local resolved="$resolved_parent/$base"

  # Reject the system temporary roots by RESOLVED PREFIX, not by substring: a
  # legitimate directory whose name merely contains "tmp" must not misfire.
  local normalized root normalized_root
  normalized="$(harness_real_dir "$resolved_parent")/$base"
  normalized="${normalized,,}"
  for root in "${TMPDIR:-}" "${TMP:-}" "${TEMP:-}" /tmp /var/tmp; do
    [[ -n "$root" ]] || continue
    normalized_root="$(harness_real_dir "$root")"
    normalized_root="${normalized_root,,}"
    normalized_root="${normalized_root%/}"
    [[ -n "$normalized_root" ]] || continue
    if [[ "$normalized" == "$normalized_root" || "$normalized" == "$normalized_root"/* ]]; then
      harness_die "the shim directory '$dir' resolves under the temporary root '$root'. A per-run temporary directory is the exact defect this check exists to stop: it changes PATH every run, and a subject that caches keyed on PATH then reports a permanent cache miss as 'no improvement' (harness-integrity.md rule 1, source failure 1). Choose a directory that persists across runs."
    fi
  done

  # shellcheck disable=SC2034  # this is the function's OUTPUT, read by every sourcing script
  HARNESS_SHIM_DIR="$resolved"
}

# harness_ledger_path <key>
#
# Sets HARNESS_LEDGER_FILE for <key>. The ledger deliberately does NOT live
# inside the shim directory: a ledger keyed on the thing whose stability it is
# proving is reset by the very change it must detect.
harness_ledger_path() {
  local key="$1" dir base
  dir="${PERF_HARNESS_LEDGER_DIR:-}"
  if [[ -z "$dir" ]]; then
    base="${XDG_CACHE_HOME:-}"
    if [[ -z "$base" ]]; then
      if [[ -z "${HOME:-}" ]]; then
        harness_die "none of PERF_HARNESS_LEDGER_DIR, XDG_CACHE_HOME or HOME is set, so the harness cannot record the PATH entry it injects and cannot prove that entry stayed fixed. Set PERF_HARNESS_LEDGER_DIR, or pass --no-ledger and prove stability another way."
      fi
      base="$HOME/.cache"
    fi
    dir="$base/performance-harness/ledger"
  fi
  mkdir -p "$dir" || harness_die "cannot create the ledger directory: $dir"
  key="${key//[^A-Za-z0-9._-]/-}"
  HARNESS_LEDGER_FILE="$dir/$key.path"
}

# harness_ledger_check <key> <injected-value>
#
# Rule 1, enforced by the standalone script rather than only by its driver. A
# census is invoked on its own far more often than through a before/after
# driver, so the driver's two-runs-agree proof cannot be the only enforcement.
# The first run for a key records and passes; a later run whose injected PATH
# entry differs fails and names both values.
harness_ledger_check() {
  local key="$1" value="$2" previous
  harness_ledger_path "$key"
  if [[ -f "$HARNESS_LEDGER_FILE" ]]; then
    previous="$(<"$HARNESS_LEDGER_FILE")"
    if [[ "$previous" != "$value" ]]; then
      harness_die "the PATH entry this harness injects CHANGED since the previous run recorded under ledger key '$key'. previously: '$previous'; now: '$value'. harness-integrity.md rule 1 requires the injected entry to be fixed across runs, because a subject that caches keyed on PATH sees every run as a cache miss and the census then measures the harness rather than the subject. Re-use the previous directory, or pass --ledger-reset once if you moved it deliberately."
    fi
  fi
  printf '%s\n' "$value" >"$HARNESS_LEDGER_FILE"
}

# harness_ledger_reset <key>
harness_ledger_reset() {
  harness_ledger_path "$1"
  rm -f "$HARNESS_LEDGER_FILE"
}

# harness_require_python
#
# Sets HARNESS_PYTHON. Fails rather than skipping: the summarizers are where the
# refusal rules live, so a run without them is not a weaker run, it is no run.
harness_require_python() {
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      # shellcheck disable=SC2034  # this is the function's OUTPUT, read by every sourcing script
      HARNESS_PYTHON="$candidate"
      return 0
    fi
  done
  harness_die "neither python3 nor python is on PATH. The percentile and ratio refusals live in the Python summarizers, so a run without them would report numbers no gate had checked."
}
