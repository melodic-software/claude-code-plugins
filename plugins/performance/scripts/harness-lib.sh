#!/usr/bin/env bash

harness_die() {
  printf 'HARNESS FAIL: %s\n' "$*" >&2
  exit 2
}

harness_warn() {
  printf 'HARNESS WARNING: %s\n' "$*" >&2
}

harness_posix_form() {
  local value="$1"
  value="${value//\\//}"
  if [[ "$value" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    local drive rest
    drive="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]:-/}"
    printf '/%s%s\n' "${drive,,}" "$rest"
    return 0
  fi
  printf '%s\n' "$value"
}

harness_require_posix_path() {
  local what="$1" value="$2"
  local drive_letter_re='(^|[^A-Za-z0-9])[A-Za-z]:[/\]'
  if [[ "$value" =~ $drive_letter_re ]]; then
    harness_die "$what carries a Windows drive-letter path: '$value'. Drive-letter paths are a harness hazard on a mixed MSYS host. The backslash form collapses when it is interpolated unquoted into a command string, so the command exits 127 in both arms of a check and the harness reports a confident wrong verdict for a check that never ran. A drive-letter PATH entry separately breaks bash's colon-separated parsing (harness-integrity.md rule 6, source failures 3 and 4). Use the POSIX spelling: /d/... rather than D:/... . Pass --allow-windows-paths only if the subject is a native Windows program that genuinely needs the native form."
  fi
}

harness_real_dir() {
  local posix
  posix="$(harness_posix_form "$1")"
  (cd "$posix" 2>/dev/null && pwd -P) || printf '%s\n' "$posix"
}

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

harness_ledger_path() {
  local key="$1" dir base
  dir="${PERF_HARNESS_LEDGER_DIR:-}"
  if [[ -z "$dir" ]]; then
    base="${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}"
    if [[ -z "$base" ]]; then
      harness_die "none of PERF_HARNESS_LEDGER_DIR, XDG_CACHE_HOME or HOME is set, so the harness cannot record the PATH entry it injects and cannot prove that entry stayed fixed. Set PERF_HARNESS_LEDGER_DIR, or pass --no-ledger and prove stability another way."
    fi
    dir="$base/performance-harness/ledger"
  fi
  mkdir -p "$dir" || harness_die "cannot create the ledger directory: $dir"
  key="${key//[^A-Za-z0-9._-]/-}"
  HARNESS_LEDGER_FILE="$dir/$key.path"
}

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

harness_ledger_reset() {
  harness_ledger_path "$1"
  rm -f "$HARNESS_LEDGER_FILE"
}

harness_require_python() {
  local candidate resolved
  for candidate in python3 python; do
    resolved="$(type -P "$candidate" 2>/dev/null)" || continue
    if "$resolved" -c 'import sys' </dev/null >/dev/null 2>&1; then
      # shellcheck disable=SC2034  # this is the function's OUTPUT, read by every sourcing script
      HARNESS_PYTHON="$resolved"
      return 0
    fi
    harness_warn "$candidate resolves to $resolved, which did not run 'import sys'; skipping it."
  done
  harness_die "no python3 or python on PATH runs. The percentile and ratio refusals live in the Python summarizers, so a run without them would report numbers no gate had checked."
}
