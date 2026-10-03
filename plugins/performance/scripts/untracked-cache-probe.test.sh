#!/usr/bin/env bash
# Tests for untracked-cache-probe.sh.
#
# The probe's promise is that it measures in a scratch repository it creates
# and removes, and never in the caller's: the cases assert the caller's index
# and status are unchanged, that no scratch dir survives any exit path, and that
# a scratch root on another volume is refused before anything is created. The
# supported or unsupported answer is the file system's to give, so the cases
# assert that the exit code and the result line agree, not which one it is.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROBE="$SCRIPT_DIR/untracked-cache-probe.sh"
readonly PROBE

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
ROOT="$WORK/probe-root"
mkdir -p "$REPO" "$ROOT"
git -C "$REPO" init -q
printf 'tracked\n' >"$REPO/a.txt"
git -C "$REPO" -c core.autocrlf=false add a.txt

# from <dir> <command...>: run a command from a directory. capture runs it in a
# subshell, so the cd never leaks into the suite.
from() {
  cd "$1" || return 2
  shift
  "$@"
}

# probe <cwd> [args...]: run the probe from a directory, as the sweeper does.
probe() {
  local dir="$1"
  shift
  capture from "$dir" bash "$PROBE" "$@"
}

# left_in <dir>: probe scratch dirs still under a root.
left_in() { find "$1" -maxdepth 1 -name 'untracked-cache-probe.*' | wc -l | tr -d ' '; }

line() { sed -n "s/^$1=//p" <<<"$RUN_OUT"; }

# A df that reports a fixed volume per path, so volume decisions are testable on one disk.
SHIM="$WORK/shim"
mkdir -p "$SHIM"
cat >"$SHIM/df" <<'DF'
#!/usr/bin/env bash
path="${!#}"
[[ -n "${FAKE_DF_FAIL:-}" ]] && exit 1
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
case "$path" in
  *probe-root*) printf '%s 1 1 1 1%% /x\n' "${FAKE_ROOT_VOLUME:-VOLA}" ;;
  *) printf 'VOLA 1 1 1 1%% /x\n' ;;
esac
DF
chmod +x "$SHIM/df"

index_hash() { sha256sum "$(git -C "$1" rev-parse --path-format=absolute --git-path index)" | cut -d' ' -f1; }

# --- 1. a run on the repository's own volume measures, in a scratch repo it removes ---
status_before="$(git -C "$REPO" status --porcelain --untracked-files=all)"
index_before="$(index_hash "$REPO")"
assert_eq "the repository has an index to compare" "64" "${#index_before}"
probe "$REPO" --scratch-root "$ROOT"
case "$RUN_RC:$(line result)" in
  0:supported | 1:unsupported) pass "the exit code and the result line agree ($RUN_RC)" ;;
  *) fail "the exit code and the result line agree" "0:supported or 1:unsupported" "$RUN_RC:$(line result)" ;;
esac
assert_contains "git's own message is passed through" "Testing mtime in" "$(line detail)"
assert_contains "git tested the scratch dir, not the repository" "untracked-cache-probe." "$(line detail)"
assert_eq "the volume tested is named" "yes" "$([[ -n "$(line volume)" && "$(line volume)" != unknown ]] && echo yes || echo no)"
assert_eq "the scratch root is on the repository's volume" "$(line volume)" "$(line scratch_volume)"
assert_eq "the scratch dir is removed after a measurement" "0" "$(left_in "$ROOT")"
assert_eq "the repository's status is unchanged" "$status_before" "$(git -C "$REPO" status --porcelain --untracked-files=all)"
assert_eq "the repository's index is unchanged" "$index_before" "$(index_hash "$REPO")"

# --- 2. an inherited GIT_DIR never redirects the scratch commands at a real repository ---
OTHER="$WORK/other"
mkdir -p "$OTHER"
git -C "$OTHER" init -q
printf 'x\n' >"$OTHER/b.txt"
git -C "$OTHER" -c core.autocrlf=false add b.txt
other_index="$(index_hash "$OTHER")"
assert_eq "the inherited repository has an index to compare" "64" "${#other_index}"
other_files="$(find "$OTHER/.git" -type f | sort)"
capture from "$REPO" env GIT_DIR="$OTHER/.git" GIT_WORK_TREE="$OTHER" bash "$PROBE" --scratch-root "$ROOT"
assert_not_contains "the inherited repository is not the one tested" "not-checked" "$(line result)"
assert_contains "git tested the scratch dir despite GIT_DIR" "untracked-cache-probe." "$(line detail)"
assert_eq "the inherited repository's index is unchanged" "$other_index" "$(index_hash "$OTHER")"
assert_eq "no file is added to the inherited repository" "$other_files" "$(find "$OTHER/.git" -type f | sort)"
assert_eq "the scratch dir is removed with an inherited GIT_DIR" "0" "$(left_in "$ROOT")"

# --- 3. a scratch root on another volume is refused before anything is created ---
capture from "$REPO" env PATH="$SHIM:$PATH" FAKE_ROOT_VOLUME=VOLB bash "$PROBE" --scratch-root "$ROOT"
assert_eq "another volume is not checked" "2" "$RUN_RC"
assert_eq "the result says not-checked" "not-checked" "$(line result)"
assert_eq "the reason code is no-data" "no-data" "$(line reason_code)"
assert_eq "the repository volume is named" "VOLA" "$(line volume)"
assert_eq "the scratch volume is named" "VOLB" "$(line scratch_volume)"
assert_contains "the reason names both volumes" "scratch root is on VOLB, the repository on VOLA" "$(line reason)"
assert_eq "nothing is created on another volume" "0" "$(left_in "$ROOT")"
assert_not_contains "git never ran" "detail=" "$RUN_OUT"

# --- 4. an unreadable volume is not guessed ---
capture from "$REPO" env PATH="$SHIM:$PATH" FAKE_DF_FAIL=1 bash "$PROBE" --scratch-root "$ROOT"
assert_eq "an unreadable volume is not checked" "2|no-data" "$RUN_RC|$(line reason_code)"
assert_eq "the unknown volume is shown as unknown" "unknown" "$(line volume)"

# --- 5. outside a repository there is nothing to test ---
mkdir -p "$WORK/plain"
probe "$WORK/plain" --scratch-root "$ROOT"
assert_eq "outside a repository is not checked" "2|no-data" "$RUN_RC|$(line reason_code)"
assert_contains "the reason says why" "not inside a git working tree" "$(line reason)"
assert_eq "nothing is created outside a repository" "0" "$(left_in "$ROOT")"

# --- 6. a root that is /, a drive root or not a directory is refused ---
probe "$REPO" --scratch-root /
assert_eq "/ is refused as a scratch root" "2|no-data" "$RUN_RC|$(line reason_code)"
probe "$REPO" --scratch-root C:/
assert_eq "a drive root is refused as a scratch root" "2|no-data" "$RUN_RC|$(line reason_code)"
probe "$REPO" --scratch-root /c
assert_eq "a mounted drive root is refused as a scratch root" "2|no-data" "$RUN_RC|$(line reason_code)"
probe "$REPO" --scratch-root "$WORK/missing"
assert_eq "a missing root is refused" "2|no-data" "$RUN_RC|$(line reason_code)"
assert_eq "a missing root is not created" "absent" "$([[ -e "$WORK/missing" ]] && echo present || echo absent)"

# --- 7. TMPDIR is the default root ---
capture from "$REPO" env TMPDIR="$ROOT" bash "$PROBE"
assert_contains "the default root is TMPDIR" "$(basename "$ROOT")/untracked-cache-probe." "$(line detail)"
assert_eq "the scratch dir under TMPDIR is removed" "0" "$(left_in "$ROOT")"

# --- 8. an unknown argument is a usage error ---
probe "$REPO" --nope
assert_eq "an unknown argument exits 2" "2" "$RUN_RC"
assert_contains "the usage is printed" "--scratch-root <dir>" "$RUN_OUT"

# --- 9. a scratch dir that cannot be created is refused, and the reason names the user's step ---
MKSHIM="$WORK/shim-mktemp"
mkdir -p "$MKSHIM"
cat >"$MKSHIM/mktemp" <<'MK'
#!/usr/bin/env bash
printf 'mktemp: refused\n' >&2
exit 1
MK
chmod +x "$MKSHIM/mktemp"
capture from "$REPO" env PATH="$MKSHIM:$PATH" bash "$PROBE" --scratch-root "$ROOT"
assert_eq "a scratch dir that cannot be created is not checked" "2|refused-by-guard" "$RUN_RC|$(line reason_code)"
assert_contains "the reason says what failed" "could not create a scratch dir under" "$(line reason)"
assert_contains "the reason names git's own test as a separate tool" "git update-index --test-untracked-cache" "$(line reason)"
assert_eq "git never ran when the scratch dir could not be created" "0" "$(grep -c '^detail=' <<<"$RUN_OUT")"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
