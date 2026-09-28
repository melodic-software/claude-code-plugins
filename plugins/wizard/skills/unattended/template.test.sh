#!/usr/bin/env bash
# Behavioral tests for the unattended PowerShell library.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/template.ps1"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2
}

if ! command -v pwsh >/dev/null 2>&1; then
  printf 'FAIL: pwsh is required\n' >&2
  exit 1
fi

run_pwsh() {
  local name="$1" body="$2" out err code
  out="$TEST_TMPDIR/$name.out"
  err="$TEST_TMPDIR/$name.err"
  WIZARD_UNATTENDED_LIBRARY_ONLY=1 pwsh -NoProfile -NonInteractive -Command "
    . '$TEMPLATE'
    $body
  " >"$out" 2>"$err"
  code=$?
  printf '%s' "$code"
}

code="$(run_pwsh marker "
  \$env:WIZARD_INSIDE_MARKER = 'Ubuntu-26.04'
  try { Assert-NotInside -Name 'Ubuntu-26.04'; 'ran' } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/marker.out")"
if [[ "$msg" == *'refusing to run inside Ubuntu-26.04'* ]]; then
  pass "not-inside guard refuses the named distro"
else
  fail "not-inside guard refuses the named distro" "$msg"
fi

code="$(run_pwsh elev "
  try { Assert-Elevation -Mode Required; 'ran' } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/elev.out")"
if [[ "$msg" == *'refusing to run unelevated'* ]]; then
  pass "required elevation refuses an unelevated process"
else
  fail "required elevation refuses an unelevated process" "$msg"
fi

code="$(run_pwsh elevok "
  Assert-Elevation -Mode Forbidden
  'allowed'
")"
msg="$(cat "$TEST_TMPDIR/elevok.out")"
if [[ "$msg" == *allowed* ]]; then
  pass "forbidden elevation allows an unelevated process"
else
  fail "forbidden elevation allows an unelevated process" "$msg"
fi

SECRET='super-secret-value'
code="$(WIZARD_TEST_SECRET="$SECRET" run_pwsh redact "
  \$dir = '$TEST_TMPDIR/redact'
  Initialize-UnattendedResult -ResultDirectory \$dir
  \$value = Resolve-UnattendedSecret -Name 'WIZARD_TEST_SECRET'
  Write-Host \$value
  Complete-UnattendedResult -Status ok
  Get-Content -Raw (Join-Path \$dir 'result-latest.json')
")"
msg="$(cat "$TEST_TMPDIR/redact.out")"
transcript="$(find "$TEST_TMPDIR/redact" -name 'transcript-*.log' | head -1)"
if [[ "$msg" == *'"schema": "cutover.result/1"'* || "$msg" == *'"schema":  "cutover.result/1"'* ]] \
  && [[ -f "$TEST_TMPDIR/redact/result-latest.json" ]] \
  && ! grep -Fq "$SECRET" "$transcript" \
  && grep -Fq '***' "$transcript"; then
  pass "result envelope is written and the transcript redacts the secret"
else
  fail "result envelope is written and the transcript redacts the secret" "json=$msg transcript=$(head -c 400 "$transcript" 2>/dev/null)"
fi

code="$(run_pwsh idem "
  \$dir = '$TEST_TMPDIR/idem'
  \$marker = Join-Path \$dir 'done'
  New-Item -ItemType Directory -Force -Path \$dir | Out-Null
  Initialize-UnattendedResult -ResultDirectory \$dir
  Invoke-IdempotentStep -Name 'rename' -Done { Test-Path -LiteralPath \$marker } -Action { Set-Content -LiteralPath \$marker -Value ok }
  Invoke-IdempotentStep -Name 'rename' -Done { Test-Path -LiteralPath \$marker } -Action { throw 'should not run' }
  Complete-UnattendedResult -Status ok
  (Get-Content -Raw (Join-Path \$dir 'result-latest.json'))
")"
msg="$(cat "$TEST_TMPDIR/idem.out")"
if [[ "$msg" == *'"status": "skipped"'* || "$msg" == *'"status":  "skipped"'* ]]; then
  pass "idempotent step skips when already done"
else
  fail "idempotent step skips when already done" "$msg"
fi

code="$(run_pwsh prior "
  \$dir = '$TEST_TMPDIR/prior'
  New-Item -ItemType Directory -Force -Path \$dir | Out-Null
  \$bad = Join-Path \$dir 'bad.json'
  Set-Content -LiteralPath \$bad -Value '{\"schema\":\"cutover.result/1\",\"status\":\"failed\"}'
  try { Assert-PriorResult -Path \$bad; 'ran' } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/prior.out")"
if [[ "$msg" == *'prior result is failed'* ]]; then
  pass "prior result must be ok"
else
  fail "prior result must be ok" "$msg"
fi

code="$(run_pwsh pre "
  \$dir = '$TEST_TMPDIR/pre'
  Initialize-UnattendedResult -ResultDirectory \$dir
  \$later = \$false
  try {
    Add-Preflight -Name 'dep' -Test { \$false } -Fix 'git pull'
    \$later = \$true
  } catch { }
  Complete-UnattendedResult -Status failed
  if (\$later) { 'later-ran' } else { 'stopped' }
")"
msg="$(cat "$TEST_TMPDIR/pre.out")"
if [[ "$msg" == *stopped* ]]; then
  pass "preflight stops before later steps"
else
  fail "preflight stops before later steps" "$msg"
fi

code="$(run_pwsh hold "
  \$dir = '$TEST_TMPDIR/hold'
  \$flag = Join-Path \$dir 'out'
  New-Item -ItemType Directory -Force -Path \$dir | Out-Null
  Initialize-UnattendedResult -ResultDirectory \$dir
  try {
    Use-GuardedResource -Name 'fleet' -Take { Set-Content -LiteralPath '$TEST_TMPDIR/hold-flag' -Value out } -Prove { throw 'proof failed' } -Release { Remove-Item -LiteralPath '$TEST_TMPDIR/hold-flag' }
  } catch { }
  Complete-UnattendedResult -Status failed
  Get-Content -Raw (Join-Path \$dir 'result-latest.json')
")"
msg="$(cat "$TEST_TMPDIR/hold.out")"
if [[ "$msg" == *fleet* ]] && [[ -f "$TEST_TMPDIR/hold-flag" ]]; then
  pass "failed proof keeps the shared resource and reports it"
else
  fail "failed proof keeps the shared resource and reports it" "$msg"
fi

code="$(run_pwsh take "
  \$dir = '$TEST_TMPDIR/take'
  Initialize-UnattendedResult -ResultDirectory \$dir
  try {
    Use-GuardedResource -Name 'fleet' -Take { throw 'drained, then failed' } -Prove { } -Release { }
  } catch { }
  Complete-UnattendedResult -Status failed
  (Get-Content -Raw (Join-Path \$dir 'result-latest.json') | ConvertFrom-Json).held_resources -join ','
")"
msg="$(cat "$TEST_TMPDIR/take.out")"
if [[ "$msg" == *fleet* ]]; then
  pass "a take that fails partway still reports the resource held"
else
  fail "a take that fails partway still reports the resource held" "$msg"
fi

code="$(run_pwsh native "
  \$dir = '$TEST_TMPDIR/native'
  Initialize-UnattendedResult -ResultDirectory \$dir
  try {
    Invoke-IdempotentStep -Name 'tool' -Done { \$false } -Action { & pwsh -NoProfile -Command 'exit 7' }
    'recorded-ok'
  } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/native.out")"
if [[ "$msg" == *'exited 7'* && "$msg" != *recorded-ok* ]]; then
  pass "a native command's nonzero exit fails the step"
else
  fail "a native command's nonzero exit fails the step" "$msg"
fi

code="$(WIZARD_TEST_SECRET="$SECRET" run_pwsh jsonredact "
  \$dir = '$TEST_TMPDIR/jsonredact'
  Initialize-UnattendedResult -ResultDirectory \$dir
  \$value = Resolve-UnattendedSecret -Name 'WIZARD_TEST_SECRET'
  try { Add-Preflight -Name 'db' -Test { \$false } -Fix \"retry with \$value\" } catch { }
  Complete-UnattendedResult -Status failed
")"
if ! grep -Fq "$SECRET" "$TEST_TMPDIR/jsonredact/result-latest.json" \
  && grep -Fq 'retry with ***' "$TEST_TMPDIR/jsonredact/result-latest.json"; then
  pass "the result JSON redacts a secret carried in a step detail"
else
  fail "the result JSON redacts a secret carried in a step detail" "$(cat "$TEST_TMPDIR/jsonredact/result-latest.json" 2>/dev/null)"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf 'OK\n'
  exit 0
fi
printf '%s failed\n' "$FAILED" >&2
exit 1
