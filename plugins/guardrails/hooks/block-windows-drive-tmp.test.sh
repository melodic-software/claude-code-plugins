#!/usr/bin/env bash
# Contract test for block-windows-drive-tmp.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash/PowerShell
# JSON on stdin, asserts on exit code (2 = blocked, 0 = allowed). The Windows
# lane is forced via OSTYPE=msys so Linux CI exercises the same matcher the
# Git Bash host would. Self-contained — no host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-windows-drive-tmp.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Force the Windows host gate even on Linux CI.
run_win() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc out
  out=$(env OSTYPE=msys "$@" bash "$HOOK" <<<"$(command_json "$command")" 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
  if ((expected == 2)); then
    assert_contains "$label → message" "$out" "drive-root temp"
    assert_contains "$label → fix" "$out" "%TEMP%"
  fi
}

run_win_pwsh() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc out
  out=$(env OSTYPE=msys "$@" bash "$HOOK" <<<"$(pwsh_command_json "$command")" 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
  if ((expected == 2)); then
    assert_contains "$label → message" "$out" "drive-root temp"
  fi
}

# Non-Windows host: /tmp is legitimate POSIX temp — must never block.
run_posix_host() {
  local label="$1" command="$2"
  local rc
  env OSTYPE=linux-gnu bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" 0 "$rc"
}

# --- Host gate ---------------------------------------------------------------
run_posix_host "Linux host: >/tmp/x allowed" 'echo x > /tmp/x'
run_posix_host "Linux host: mkdir /tmp/x allowed" 'mkdir -p /tmp/x'

# --- Redirects to drive-root tmp (blocked) -----------------------------------
run_win "redirect >/tmp/x (blocked)" 'echo x > /tmp/x' 2
run_win "redirect >>/tmp/x (blocked)" 'echo x >> /tmp/x' 2
run_win "redirect glued >/tmp/x (blocked)" 'echo x>/tmp/x' 2
run_win "stderr redirect 2>/tmp/err (blocked)" 'echo x 2>/tmp/err' 2
run_win "both-streams &>/tmp/x (blocked)" 'echo x &>/tmp/x' 2
run_win "redirect >C:/tmp/x (blocked)" 'echo x > C:/tmp/x' 2
run_win "redirect >C:\\tmp\\x (blocked)" 'echo x > C:\tmp\x' 2
run_win "redirect >/c/tmp/x MSYS (blocked)" 'echo x > /c/tmp/x' 2
run_win "redirect >\\tmp\\x drive-root (blocked)" 'echo x > \tmp\x' 2
run_win "quoted redirect target >\"/tmp/x\" (blocked)" 'echo x > "/tmp/x"' 2

# --- Write utilities with drive-root tmp (blocked) ---------------------------
run_win "mkdir /tmp/x (blocked)" 'mkdir -p /tmp/x' 2
run_win "mktemp /tmp/tmp.XXXXXX (blocked)" 'mktemp /tmp/tmp.XXXXXX' 2
run_win "touch /tmp/x (blocked)" 'touch /tmp/x' 2
run_win "tee /tmp/x (blocked)" 'echo x | tee /tmp/x' 2
run_win "cp to /tmp/x (blocked)" 'cp ./a /tmp/x' 2
run_win "mv to /tmp/x (blocked)" 'mv ./a /tmp/x' 2
run_win "python open /tmp write (blocked)" "python3 -c \"open('/tmp/x','w').write('a')\"" 2

# --- PowerShell writers (blocked) --------------------------------------------
run_win_pwsh "PS: Set-Content C:\\tmp\\x (blocked)" 'Set-Content -Path C:\tmp\x -Value hi' 2
run_win_pwsh "PS: Out-File \\tmp\\x (blocked)" "'hi' | Out-File \tmp\x" 2
run_win_pwsh "PS: redirect >/tmp/x (blocked)" "'hi' > /tmp/x" 2
run_win_pwsh "PS: New-Item /c/tmp/x (blocked)" 'New-Item -Path /c/tmp/x -ItemType File' 2
run_win_pwsh "PS: Add-Content C:/tmp/x (blocked)" 'Add-Content -Path C:/tmp/x -Value hi' 2

# --- Legitimate platform temp / POSIX variants (allowed) ---------------------
# Literal $TEMP / $env:TEMP in fixture strings must not expand in this test process.
# shellcheck disable=SC2016
run_win "redirect >\$TEMP/x (allowed)" 'echo x > $TEMP/x' 0
# shellcheck disable=SC2016
run_win "redirect >\$TMP/x (allowed)" 'echo x > $TMP/x' 0
# shellcheck disable=SC2016
run_win "redirect >\$TMPDIR/x (allowed)" 'echo x > $TMPDIR/x' 0
run_win "redirect >%TEMP%/x literal (allowed)" 'echo x > %TEMP%/x' 0
run_win "redirect >/var/tmp/x (allowed)" 'echo x > /var/tmp/x' 0
run_win "mkdir /var/tmp/x (allowed)" 'mkdir -p /var/tmp/x' 0
# shellcheck disable=SC2016
run_win "mktemp under \$TEMP (allowed)" 'mktemp "$TEMP/tmp.XXXXXX"' 0
# shellcheck disable=SC2016
run_win_pwsh "PS: Set-Content \$env:TEMP (allowed)" 'Set-Content -Path $env:TEMP\x -Value hi' 0
# shellcheck disable=SC2016
run_win_pwsh "PS: Out-File \$env:TMP (allowed)" 'Out-File -FilePath $env:TMP\x -InputObject hi' 0

# --- Non-write mentions (allowed) --------------------------------------------
run_win "echo mentions /tmp (allowed)" 'echo do not use /tmp' 0
run_win "ls /tmp (read, allowed)" 'ls /tmp' 0
run_win "cat /tmp/x (read, allowed)" 'cat /tmp/x' 0
run_win "relative ./tmp (allowed)" 'echo x > ./tmp/x' 0
run_win "path component foo/tmp (allowed)" 'echo x > foo/tmp/x' 0
run_win "unrelated command (allowed)" 'git status' 0
# Redirect operator inside a quoted message must not fail closed (#2594 review).
run_win "quoted prose redirect (allowed)" 'git commit -m "Example: echo x > /tmp/x"' 0
run_win "single-quoted prose redirect (allowed)" "printf '%s' 'echo > /tmp/x'" 0
# Source-only /tmp with a writer elsewhere must stay allowed.
run_win "cp from /tmp (allowed)" 'cp /tmp/source ./dest' 0
run_win "compound mkdir then cat /tmp (allowed)" 'mkdir ./out && cat /tmp/source' 0

# --- PowerShell copy/move destinations (blocked) -----------------------------
run_win_pwsh "PS: Copy-Item to C:\\tmp (blocked)" 'Copy-Item .\a C:\tmp\a' 2
run_win_pwsh "PS: Move-Item to C:\\tmp (blocked)" 'Move-Item .\a C:\tmp\a' 2
run_win_pwsh "PS: copy alias to /tmp (blocked)" 'copy .\a /tmp/a' 2

# --- Kill switch -------------------------------------------------------------
run_win "kill switch disables guard" 'echo x > /tmp/x' 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_WINDOWS_DRIVE_TMP_ENABLED=false

# --- Telemetry (opt-in sink) -------------------------------------------------
TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK=$(make_sink "cat > \"$TEL\"")
out=$(env OSTYPE=msys HOOK_TELEMETRY_SINK="$SINK" bash "$HOOK" \
  <<<"$(command_json 'echo x > /tmp/x')" 2>&1) || true
wait_for_sink "$TEL" || true
if [[ -s "$TEL" ]]; then
  tel_body=$(cat "$TEL")
  assert_contains "telemetry hook id" "$tel_body" '"hook": "block-windows-drive-tmp"'
  assert_contains "telemetry blocked" "$tel_body" '"status": "blocked"'
  assert_contains "telemetry form" "$tel_body" '"form": "redirect"'
else
  # Telemetry is best-effort; an empty sink on a slow box is not a contract fail
  # when the block itself already asserted. Record as an explicit skip-visible.
  ok "telemetry sink empty (best-effort; block path already covered)"
fi
assert_contains "blocked stderr still present with sink" "$out" "drive-root temp"

report
