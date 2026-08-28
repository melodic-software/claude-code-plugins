#!/usr/bin/env bash
# Black-box contract test for sync-prep.sh.
#
# sync-prep.sh is a print-only step: it opens the sync window by TELLING the
# operator which elevated command to run and by handing off to sync-finalize.sh.
# It must never disable a firewall rule itself and must never delete anything.
# Every case below therefore asserts on two things at once, what the script
# printed and what it did not do, because a regression that started running
# those commands inline would still print plausible output.
#
# Isolation. Each case copies the real script into a throwaway mktemp sandbox so
# its SCRIPT_DIR resolves there, writes the status.sh sibling it probes as a
# stub, and runs it under a PATH whose first entry shadows rm, pwsh,
# powershell.exe, netsh and icacls with recorders that perform nothing. Nothing
# outside the sandbox is read or written, no call can reach a real firewall, and
# an attempted delete is recorded rather than performed.
#
# Assertion helpers are duplicated per plugin on purpose:
# docs/conventions/shell-test-helpers/README.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/sync-prep.sh"
FIREWALL_PS1="${SCRIPT_DIR}/firewall.ps1"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

assert_rc() {
  local label="$1" want="$2" got="$3"
  if [[ "${got}" -eq "${want}" ]]; then
    pass "${label}"
  else
    fail "${label} (want rc ${want}, got ${got})"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qF -- "${needle}" <<<"${haystack}"; then
    pass "${label}"
  else
    fail "${label} (output does not contain: ${needle})"
  fi
}

assert_lacks() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qF -- "${needle}" <<<"${haystack}"; then
    fail "${label} (output unexpectedly contains: ${needle})"
  else
    pass "${label}"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# A tree the script has no business reaching at all. Checked once at the end:
# the sandbox snapshots below only prove nothing vanished inside the sandbox.
OUTSIDE="${TMP}/outside"
mkdir -p "${OUTSIDE}"
printf 'nothing here is sync-prep business\n' >"${OUTSIDE}/keep.txt"
OUTSIDE_BEFORE="$(cat "${OUTSIDE}/keep.txt")"

CALL_LOG="${TMP}/external-calls.log"
export CALL_LOG
: >"${CALL_LOG}"

# PATH shims: every command this script must never invoke is shadowed by a
# recorder that does nothing, so "it did not touch the machine" is an assertion
# over a file instead of a hope.
SHIM_DIR="${TMP}/bin"
mkdir -p "${SHIM_DIR}"
for shim_cmd in rm pwsh powershell.exe netsh icacls; do
  cat >"${SHIM_DIR}/${shim_cmd}" <<'SHIM'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"${CALL_LOG}"
exit 0
SHIM
  chmod +x "${SHIM_DIR}/${shim_cmd}"
done

# $1 selects the status.sh sibling flavor: present (executable), nonexec,
# absent, or failing (executable, exits 1). Prints the sandbox path.
make_sandbox() {
  local flavor="$1" sbx
  sbx="$(mktemp -d "${TMP}/sandbox.XXXXXX")"
  cp "${SUT}" "${sbx}/sync-prep.sh"
  mkdir -p "${sbx}/canary"
  printf 'sync-prep must never delete this\n' >"${sbx}/canary/keep.txt"
  if [[ "${flavor}" != "absent" ]]; then
    {
      echo '#!/usr/bin/env bash'
      echo 'echo STATUS_STUB_RAN'
      if [[ "${flavor}" == "failing" ]]; then
        echo 'echo "status probe failed" >&2'
        echo 'exit 1'
      fi
    } >"${sbx}/status.sh"
    if [[ "${flavor}" == "nonexec" ]]; then
      chmod 644 "${sbx}/status.sh"
    else
      chmod 755 "${sbx}/status.sh"
    fi
  fi
  printf '%s\n' "${sbx}"
}

snapshot() { find "$1" -mindepth 1 | LC_ALL=C sort; }

# The shim directory is prepended as a command-scoped assignment rather than by
# exporting PATH, so this suite's own rm (the EXIT trap) is never the shim.
run_sut() {
  local sbx="$1"
  shift
  : >"${CALL_LOG}"
  PATH="${SHIM_DIR}:${PATH}" bash "${sbx}/sync-prep.sh" "$@" 2>&1
}

assert_touched_nothing() {
  local label="$1" sbx="$2" before="$3"
  local calls
  calls="$(cat "${CALL_LOG}")"
  if [[ -n "${calls}" ]]; then
    fail "${label}: ran shadowed external command(s): ${calls}"
  else
    pass "${label}: invoked no rm/pwsh/powershell/netsh/icacls"
  fi
  if [[ "$(snapshot "${sbx}")" == "${before}" ]]; then
    pass "${label}: left the sandbox tree unchanged"
  else
    fail "${label}: sandbox tree changed"
  fi
  if [[ "$(cat "${sbx}/canary/keep.txt")" == "sync-prep must never delete this" ]]; then
    pass "${label}: left the canary file intact"
  else
    fail "${label}: canary file was modified"
  fi
}

# The rule name the script prints has to be the one firewall.ps1 acts on, or the
# operator is told to disable a rule that does not exist. Read from the real
# script, never restated here, so a rename in either file fails this suite.
RULE_NAME="$(grep "RuleName = '" "${FIREWALL_PS1}" | head -1 | cut -d"'" -f2)"
if [[ -z "${RULE_NAME}" ]]; then
  fail "could not read \$RuleName out of firewall.ps1 (cross-script check cannot run)"
fi

# --- A. --dry-run plans the work and performs none of it ---

sbx="$(make_sandbox present)"
before="$(snapshot "${sbx}")"
out="$(run_sut "${sbx}" --dry-run)"
rc=$?

assert_rc "dry-run exits 0" 0 "${rc}"
assert_contains "dry-run announces the script" "${out}" "=== kindle-dedrm: sync prep ==="
assert_contains "dry-run prints the plan" "${out}" "[DRY-RUN] Would do:"
assert_contains "dry-run names the firewall step" "${out}" "Disable firewall rule"
assert_contains "dry-run names the cached-installer delete" "${out}" "Delete cached installer"
assert_contains "dry-run names the sync-finalize handoff" "${out}" "sync-finalize.sh"
# The discriminator for an always-true --dry-run guard turning into an
# always-false one: the live walkthrough must not print in dry-run mode.
assert_lacks "dry-run withholds the live user steps" "${out}" "USER STEPS"
assert_lacks "dry-run withholds the elevated command" "${out}" "Disable-NetFirewallRule"
if [[ -n "${RULE_NAME}" ]]; then
  assert_contains "dry-run names firewall.ps1's own rule" "${out}" "${RULE_NAME}"
fi
assert_contains "dry-run still runs the status pre-flight" "${out}" "[sync-prep] current state:"
assert_contains "dry-run shows the status output" "${out}" "STATUS_STUB_RAN"
assert_touched_nothing "dry-run" "${sbx}" "${before}"

# --- B. the live path prints the walkthrough and still performs nothing ---

sbx="$(make_sandbox present)"
before="$(snapshot "${sbx}")"
out="$(run_sut "${sbx}")"
rc=$?

assert_rc "live run exits 0" 0 "${rc}"
assert_contains "live run opens the walkthrough" "${out}" "=== USER STEPS (do not skip) ==="
assert_contains "live run closes the walkthrough" "${out}" "=== END USER STEPS ==="
# Mirror of the dry-run discriminator: an always-true guard would print the plan
# instead of the walkthrough, and both halves have to be checked to catch it.
assert_lacks "live run is not the dry-run plan" "${out}" "[DRY-RUN]"
assert_contains "live run prints the elevated disable command" "${out}" "Disable-NetFirewallRule -DisplayName"
assert_contains "live run points at its own firewall.ps1" "${out}" "${sbx}/firewall.ps1"
assert_contains "live run asks for the disable action" "${out}" "-Action disable"
assert_contains "live run points at its own sync-finalize.sh" "${out}" "${sbx}/sync-finalize.sh"
if [[ -n "${RULE_NAME}" ]]; then
  assert_contains "live run names firewall.ps1's own rule" "${out}" "${RULE_NAME}"
fi
# The upgrade refusal is the safety instruction the whole workflow rests on: an
# accepted 2.9.x upgrade breaks key extraction and costs a re-download.
assert_contains "live run keeps the upgrade refusal" "${out}" "if Kindle prompts to upgrade, REFUSE"
assert_contains "live run keeps the quit-Kindle step" "${out}" "Quit Kindle entirely"
assert_touched_nothing "live run" "${sbx}" "${before}"

# --- C. absent status.sh degrades, it does not abort ---

sbx="$(make_sandbox absent)"
before="$(snapshot "${sbx}")"
out="$(run_sut "${sbx}")"
rc=$?

assert_rc "missing status.sh still exits 0" 0 "${rc}"
assert_lacks "missing status.sh prints no state header" "${out}" "[sync-prep] current state:"
assert_contains "missing status.sh still opens the sync window" "${out}" "=== USER STEPS (do not skip) ==="
assert_touched_nothing "missing status.sh" "${sbx}" "${before}"

# --- D. present but non-executable status.sh is treated as absent ---

sbx="$(make_sandbox nonexec)"
if [[ -x "${sbx}/status.sh" ]]; then
  # Not scored as a pass: this filesystem cannot express the state under test.
  echo "SKIP: filesystem keeps the execute bit after chmod 644, so the non-executable status.sh case cannot be set up"
else
  before="$(snapshot "${sbx}")"
  out="$(run_sut "${sbx}")"
  rc=$?
  assert_rc "non-executable status.sh still exits 0" 0 "${rc}"
  assert_lacks "non-executable status.sh is not run" "${out}" "STATUS_STUB_RAN"
  assert_lacks "non-executable status.sh prints no state header" "${out}" "[sync-prep] current state:"
  assert_contains "non-executable status.sh still opens the sync window" "${out}" "=== USER STEPS (do not skip) ==="
  assert_touched_nothing "non-executable status.sh" "${sbx}" "${before}"
fi

# --- E. a failing status probe must not close the sync window ---

sbx="$(make_sandbox failing)"
before="$(snapshot "${sbx}")"
out="$(run_sut "${sbx}")"
rc=$?

assert_rc "failing status.sh still exits 0" 0 "${rc}"
assert_contains "failing status.sh is still attempted" "${out}" "STATUS_STUB_RAN"
assert_contains "failing status.sh surfaces its error" "${out}" "status probe failed"
assert_contains "failing status.sh still opens the sync window" "${out}" "=== USER STEPS (do not skip) ==="
assert_touched_nothing "failing status.sh" "${sbx}" "${before}"

# --- F. argument handling matches the documented `sync-prep.sh [--dry-run]` ---

# Only the first argument selects dry-run. Pinned because the failure direction
# matters: a misplaced flag falls through to the live walkthrough, and an
# operator who believes they asked for a plan gets the real one.
sbx="$(make_sandbox present)"
before="$(snapshot "${sbx}")"
out="$(run_sut "${sbx}" unexpected --dry-run)"
rc=$?

assert_rc "--dry-run after another argument still exits 0" 0 "${rc}"
assert_lacks "--dry-run is honored in first position only" "${out}" "[DRY-RUN]"
assert_contains "a non-first --dry-run takes the live path" "${out}" "=== USER STEPS (do not skip) ==="
assert_touched_nothing "non-first --dry-run" "${sbx}" "${before}"

# An unknown argument is accepted and takes the live path. This script has no
# argument validation, unlike the sibling cleanup.sh, which exits 1 on an
# unknown argument. Pinned so that adding validation here is a deliberate
# change with a visible test update, not an accident.
sbx="$(make_sandbox present)"
before="$(snapshot "${sbx}")"
out="$(run_sut "${sbx}" --dryrun)"
rc=$?

assert_rc "an unknown argument exits 0" 0 "${rc}"
assert_lacks "a misspelled --dryrun does not enable dry-run" "${out}" "[DRY-RUN]"
assert_contains "a misspelled --dryrun takes the live path" "${out}" "=== USER STEPS (do not skip) ==="
assert_touched_nothing "unknown argument" "${sbx}" "${before}"

# --- G. no dependency on the Windows environment variables ---

# Unlike its siblings, sync-prep.sh expands no LOCALAPPDATA/APPDATA/USERPROFILE,
# so it runs before provisioning. Under `set -u` a newly added expansion of an
# unset one would abort mid-walkthrough, which this case catches.
sbx="$(make_sandbox present)"
before="$(snapshot "${sbx}")"
out="$(
  unset LOCALAPPDATA APPDATA USERPROFILE
  : >"${CALL_LOG}"
  PATH="${SHIM_DIR}:${PATH}" bash "${sbx}/sync-prep.sh" 2>&1
)"
rc=$?

assert_rc "runs with the Windows env vars unset" 0 "${rc}"
assert_contains "unset env vars still yield the full walkthrough" "${out}" "=== END USER STEPS ==="
assert_lacks "unset env vars raise no unbound-variable error" "${out}" "unbound variable"
assert_touched_nothing "unset Windows env vars" "${sbx}" "${before}"

# --- H. the handoff paths survive a relative-path invocation ---

# SCRIPT_DIR is `cd ... && pwd`, not a bare dirname, and the difference only
# shows when the script is invoked by a relative path: the printed
# sync-finalize.sh handoff has to stay absolute, since the operator pastes it
# into a shell whose working directory is their own.
sbx="$(make_sandbox present)"
before="$(snapshot "${sbx}")"
out="$(
  cd "$(dirname "${sbx}")" || exit 1
  : >"${CALL_LOG}"
  PATH="${SHIM_DIR}:${PATH}" bash "$(basename "${sbx}")/sync-prep.sh" 2>&1
)"
rc=$?

assert_rc "relative-path invocation exits 0" 0 "${rc}"
assert_contains "relative-path invocation still prints an absolute handoff path" "${out}" "${sbx}/sync-finalize.sh"
assert_contains "relative-path invocation still prints an absolute wrapper path" "${out}" "${sbx}/firewall.ps1"
assert_touched_nothing "relative-path invocation" "${sbx}" "${before}"

# --- I. nothing outside the sandboxes was reached ---

if [[ "$(cat "${OUTSIDE}/keep.txt")" == "${OUTSIDE_BEFORE}" ]]; then
  pass "left the out-of-sandbox tree untouched"
else
  fail "the out-of-sandbox tree was modified"
fi

if [[ "${fails}" -gt 0 ]]; then
  printf '\n%d case(s) failed\n' "${fails}" >&2
  exit 1
fi

printf '\nAll sync-prep.sh cases passed.\n'
