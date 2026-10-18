#!/usr/bin/env bash
# Tests for wsl-profile.sh: WSL detection, derived paths, print-only behavior,
# and the lint that rejects Write(path) and single-slash path rules.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wsl-profile.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

mkdir -p "$T/mnt/x/Users/Public" "$T/mnt/x/Users/someone" "$T/home/me"
echo "Linux version 5.15 Microsoft standard WSL2" >"$T/procv-wsl"
echo "Linux version 6.1 generic" >"$T/procv-plain"

run() { env -u WSL_DISTRO_NAME HOME="$T/home/me" TMPDIR="$T/session-tmp" WSL_PROFILE_TMPDIR="$T/tmp" WSL_PROFILE_MNT_ROOT="$T/mnt" "$@"; }

# --- Detection ---------------------------------------------------------------
rc=0
run WSL_DISTRO_NAME=Distro WSL_PROFILE_PROC_VERSION="$T/procv-plain" bash "$SCRIPT" detect || rc=$?
assert_eq "WSL_DISTRO_NAME marks a WSL host" "0" "$rc"
rc=0
run WSL_PROFILE_PROC_VERSION="$T/procv-wsl" bash "$SCRIPT" detect || rc=$?
assert_eq "/proc/version naming Microsoft marks a WSL host" "0" "$rc"
rc=0
run WSL_PROFILE_PROC_VERSION="$T/procv-plain" bash "$SCRIPT" detect || rc=$?
assert_eq "a plain Linux host is not WSL" "1" "$rc"
rc=0
out="$(run WSL_PROFILE_PROC_VERSION="$T/procv-plain" bash "$SCRIPT" print 2>&1)" || rc=$?
assert_eq "print on a non-WSL host exits 1" "1" "$rc"
case "$out" in *"does not apply"*) pass "non-WSL print says the profile does not apply" ;; *) fail "non-WSL message" "$out" ;; esac

# --- The printed profile -----------------------------------------------------
run WSL_PROFILE_PROC_VERSION="$T/procv-wsl" bash "$SCRIPT" print >"$T/profile.json" 2>/dev/null
assert_eq "print emits valid JSON" "0" "$(jq empty "$T/profile.json" >/dev/null 2>&1 && echo 0 || echo 1)"
assert_eq "TMPDIR is pinned from the environment" "$T/tmp" "$(jq -r '.env.TMPDIR' "$T/profile.json")"
assert_eq "a Linux secret store is a // Read deny" "true" \
  "$(jq --arg r "Read(/$T/home/me/.ssh/id_*)" '.permissions.deny | index($r) != null' "$T/profile.json")"
assert_eq "the Windows host config is a // Edit deny, Public skipped" "true" \
  "$(jq --arg r "Edit(/$T/mnt/x/Users/someone/.claude/**)" '.permissions.deny | index($r) != null' "$T/profile.json")"
assert_eq "no rule names the Public profile" "0" "$(jq '[.permissions.deny[] | select(test("Public"))] | length' "$T/profile.json")"
assert_eq "the shipped profile has no Write rule" "0" "$(jq '[.permissions.deny[] | select(startswith("Write("))] | length' "$T/profile.json")"
rc=0
bash "$SCRIPT" lint "$T/profile.json" >/dev/null || rc=$?
assert_eq "lint passes on the printed profile" "0" "$rc"

# --- Print writes nothing ----------------------------------------------------
before="$(find "$T/home" "$T/mnt" | sort | md5sum)"
run WSL_PROFILE_PROC_VERSION="$T/procv-wsl" bash "$SCRIPT" print >/dev/null 2>&1
assert_eq "print leaves the filesystem unchanged" "$before" "$(find "$T/home" "$T/mnt" | sort | md5sum)"

# --- No Windows user directory: placeholders ---------------------------------
out="$(run WSL_PROFILE_MNT_ROOT="$T/empty" WSL_PROFILE_PROC_VERSION="$T/procv-wsl" bash "$SCRIPT" print 2>/dev/null)"
case "$out" in *"<windows-user>"*) pass "missing Windows home falls back to placeholders" ;; *) fail "placeholder fallback" "$out" ;; esac

# --- Lint rejects bad rules --------------------------------------------------
printf '%s' '{"permissions":{"deny":["Write(//a/b/**)"]}}' >"$T/bad-write.json"
printf '%s' '{"permissions":{"deny":["Edit(/a/b/**)"]}}' >"$T/bad-slash.json"
printf '%s' '{"permissions":{"deny":["Read(~/.ssh/id_*)"]}}' >"$T/bad-tilde.json"
printf '%s' '{"permissions":{"deny":["Read(//a/b/**)","Edit(//a/c)"]}}' >"$T/good.json"
for f in bad-write bad-slash bad-tilde; do
  rc=0
  bash "$SCRIPT" lint "$T/$f.json" >/dev/null 2>&1 || rc=$?
  assert_eq "lint fails on $f" "1" "$rc"
done
rc=0
bash "$SCRIPT" lint "$T/good.json" >/dev/null || rc=$?
assert_eq "lint passes on // Read and Edit rules" "0" "$rc"

if ((FAILED > 0)); then
  printf '%d failure(s)\n' "$FAILED" >&2
  exit 1
fi
echo "all passed"
