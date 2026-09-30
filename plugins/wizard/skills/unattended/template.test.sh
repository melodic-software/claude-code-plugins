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

code="$(run_pwsh wsl-env "
  Remove-Item Env:WIZARD_INSIDE_MARKER -ErrorAction SilentlyContinue
  \$env:WSL_DISTRO_NAME = 'Ubuntu-26.04'
  try { Assert-NotInside -Name 'Ubuntu-26.04'; 'ran' } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/wsl-env.out")"
if [[ "$msg" == *'refusing to run inside Ubuntu-26.04'* ]]; then
  pass "not-inside guard reads WSL_DISTRO_NAME when no marker is set"
else
  fail "not-inside guard reads WSL_DISTRO_NAME when no marker is set" "$msg"
fi

code="$(run_pwsh not-wsl "
  Remove-Item Env:WIZARD_INSIDE_MARKER -ErrorAction SilentlyContinue
  Remove-Item Env:WSL_DISTRO_NAME -ErrorAction SilentlyContinue
  try { Assert-NotInside -Name 'build-agent-service'; 'ran' } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/not-wsl.out")"
if [[ "$msg" == ran ]]; then
  pass "not-inside guard does not detect a service, only a WSL distro"
else
  fail "not-inside guard does not detect a service, only a WSL distro" "$msg"
fi

SKILL_MD="$SCRIPT_DIR/SKILL.md"
README_MD="$SCRIPT_DIR/../../README.md"
SKILL_FLAT="$(tr '\n' ' ' <"$SKILL_MD" | tr -s ' ')"
# shellcheck disable=SC2016 # backticks quote literal SKILL.md text
if [[ "$SKILL_FLAT" == *'Assert-NotInside -Name <wsl-distro>'* && "$SKILL_FLAT" != *'<distro-or-service>'* \
  && "$SKILL_FLAT" == *'compares `Name` with `WSL_DISTRO_NAME` only'* && "$SKILL_FLAT" == *'a service, container or process is not detected'* ]]; then
  pass "SKILL.md scopes Assert-NotInside to a WSL distro"
else
  fail "SKILL.md scopes Assert-NotInside to a WSL distro" "wording missing or still says distro-or-service"
fi

if [[ "$SKILL_FLAT" == *'WIZARD_INSIDE_MARKER'* && "$SKILL_FLAT" == *'the test seam'* ]] \
  && grep -Fq 'the test seam for template.test.sh' "$TEMPLATE"; then
  pass "WIZARD_INSIDE_MARKER is named as the test seam in the template and SKILL.md"
else
  fail "WIZARD_INSIDE_MARKER is named as the test seam in the template and SKILL.md" "seam not named"
fi

# shellcheck disable=SC2016 # backticks quote literal SKILL.md text
if head -n 1 "$TEMPLATE" | grep -Fxq '#requires -Version 7.0' \
  && [[ "$SKILL_FLAT" == *'requires PowerShell 7 (`pwsh`)'* && "$SKILL_FLAT" == *'`pwsh -File <script>` (Windows PowerShell 5.1 fails at `#requires`)'* ]] \
  && grep -Fq 'winget install --id Microsoft.PowerShell' "$README_MD" \
  && grep -Fq 'Needs PowerShell 7' "$README_MD"; then
  pass "the PowerShell 7 requirement and its Windows install path are stated"
else
  fail "the PowerShell 7 requirement and its Windows install path are stated" "requirement or install path missing"
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

code="$(run_pwsh nativeprove "
  \$dir = '$TEST_TMPDIR/nativeprove'
  Initialize-UnattendedResult -ResultDirectory \$dir
  try {
    Use-GuardedResource -Name 'fleet' -Take { } -Prove { & pwsh -NoProfile -Command 'exit 3' } -Release { 'released' }
  } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/nativeprove.out")"
if [[ "$msg" == *'prove fleet failed'* && "$msg" != *released* ]]; then
  pass "a native proof's nonzero exit keeps the resource unreleased"
else
  fail "a native proof's nonzero exit keeps the resource unreleased" "$msg"
fi

# Prove must be a real proof: name|prove block|expected outcome.
# shellcheck disable=SC2016 # PowerShell expressions are literal data, not shell expansions
for case in 'provefalse|$false|held' 'provenone||held' 'provetrue|$true|released' 'provecmp|1 -eq 1|released'; do
  IFS='|' read -r name prove outcome <<<"$case"
  code="$(run_pwsh "$name" "
    \$dir = '$TEST_TMPDIR/$name'
    Initialize-UnattendedResult -ResultDirectory \$dir
    try {
      Use-GuardedResource -Name 'fleet' -Take { } -Prove { $prove } -Release { 'released' }
    } catch { \$_.Exception.Message }
    Complete-UnattendedResult -Status ok
    'held=' + ((Get-Content -Raw (Join-Path \$dir 'result-latest.json') | ConvertFrom-Json).held_resources -join ',')
  ")"
  msg="$(cat "$TEST_TMPDIR/$name.out")"
  if [[ "$outcome" == held && "$msg" == *'prove fleet failed: proof failed'* && "$msg" != *released* && "$msg" == *'held=fleet'* ]] \
    || [[ "$outcome" == released && "$msg" == *released* && "$msg" != *failed* && "$msg" == *'held='* && "$msg" != *'held=fleet'* ]]; then
    pass "proof '$prove' leaves the resource $outcome"
  else
    fail "proof '$prove' leaves the resource $outcome" "$msg"
  fi
done

code="$(run_pwsh waitok "
  \$dir = '$TEST_TMPDIR/waitok'
  \$counter = '$TEST_TMPDIR/waitok-count'
  Set-Content -LiteralPath \$counter -Value 0
  Initialize-UnattendedResult -ResultDirectory \$dir
  Wait-ForState -Name 'drain' -TimeoutSeconds 10 -IntervalSeconds 0.05 -Predicate {
    \$n = [int](Get-Content -LiteralPath \$counter) + 1
    Set-Content -LiteralPath \$counter -Value \$n
    \$n -ge 3
  }
  Complete-UnattendedResult -Status ok
  'polls=' + (Get-Content -LiteralPath \$counter)
  \$step = (Get-Content -Raw (Join-Path \$dir 'result-latest.json') | ConvertFrom-Json).steps | Where-Object name -eq 'wait drain'
  'step=' + \$step.status + ':' + \$step.detail
")"
msg="$(cat "$TEST_TMPDIR/waitok.out")"
if [[ "$msg" == *'polls=3'* && "$msg" == *'step=ok:reached after '* && "$msg" == *'attempt 2'* ]]; then
  pass "Wait-ForState returns after the predicate turns truthy and records a step"
else
  fail "Wait-ForState returns after the predicate turns truthy and records a step" "$msg"
fi

code="$(run_pwsh waittimeout "
  Initialize-UnattendedResult -ResultDirectory '$TEST_TMPDIR/waittimeout'
  try {
    Wait-ForState -Name 'drain' -TimeoutSeconds 1 -IntervalSeconds 0.05 -Predicate { \$false }
    'reached'
  } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/waittimeout.out")"
if [[ "$msg" == *'timed out waiting for drain after 1s'* && "$msg" == *'value False'* && "$msg" != *reached* ]]; then
  pass "Wait-ForState times out with the last observed value"
else
  fail "Wait-ForState times out with the last observed value" "$msg"
fi

code="$(run_pwsh waitthrow "
  \$counter = '$TEST_TMPDIR/waitthrow-count'
  Set-Content -LiteralPath \$counter -Value 0
  Initialize-UnattendedResult -ResultDirectory '$TEST_TMPDIR/waitthrow'
  Wait-ForState -Name 'pool' -TimeoutSeconds 10 -IntervalSeconds 0.05 -Predicate {
    \$n = [int](Get-Content -LiteralPath \$counter) + 1
    Set-Content -LiteralPath \$counter -Value \$n
    if (\$n -lt 3) { throw 'target not there yet' }
    \$true
  }
  'polls=' + (Get-Content -LiteralPath \$counter)
")"
msg="$(cat "$TEST_TMPDIR/waitthrow.out")"
if [[ "$msg" == *'polls=3'* ]]; then
  pass "Wait-ForState treats a throwing predicate as not yet"
else
  fail "Wait-ForState treats a throwing predicate as not yet" "$msg"
fi

code="$(run_pwsh waitthrowfinal "
  Initialize-UnattendedResult -ResultDirectory '$TEST_TMPDIR/waitthrowfinal'
  try {
    Wait-ForState -Name 'pool' -TimeoutSeconds 1 -IntervalSeconds 0.05 -Predicate { throw 'no such pool' }
  } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/waitthrowfinal.out")"
if [[ "$msg" == *'timed out waiting for pool after 1s'* && "$msg" == *'no such pool'* ]]; then
  pass "Wait-ForState timeout carries the last predicate error"
else
  fail "Wait-ForState timeout carries the last predicate error" "$msg"
fi

code="$(run_pwsh tolerate "
  \$dir = '$TEST_TMPDIR/tolerate'
  Initialize-UnattendedResult -ResultDirectory \$dir
  try {
    Use-GuardedResource -Name 'fleet' -TolerateTakeExit -Take { & pwsh -NoProfile -Command 'exit 5' } -Prove { Wait-ForState -Name 'drain' -TimeoutSeconds 5 -IntervalSeconds 0.05 -Predicate { \$true } } -Release { 'released' }
  } catch { \$_.Exception.Message }
  Complete-UnattendedResult -Status ok
  \$json = Get-Content -Raw (Join-Path \$dir 'result-latest.json') | ConvertFrom-Json
  'held=' + (\$json.held_resources -join ',')
  'warnings=' + (\$json.warnings -join '|')
")"
msg="$(cat "$TEST_TMPDIR/tolerate.out")"
if [[ "$msg" == *released* && "$msg" == *'held='* && "$msg" != *'held=fleet'* && "$msg" == *'warnings=take fleet exited 5; state is proven by the next step'* ]]; then
  pass "TolerateTakeExit defers a nonzero take exit to the proof and warns"
else
  fail "TolerateTakeExit defers a nonzero take exit to the proof and warns" "$msg"
fi

code="$(run_pwsh tolerateprove "
  \$dir = '$TEST_TMPDIR/tolerateprove'
  Initialize-UnattendedResult -ResultDirectory \$dir
  try {
    Use-GuardedResource -Name 'fleet' -TolerateTakeExit -Take { & pwsh -NoProfile -Command 'exit 5' } -Prove { Wait-ForState -Name 'drain' -TimeoutSeconds 1 -IntervalSeconds 0.05 -Predicate { \$false } } -Release { 'released' }
  } catch { \$_.Exception.Message }
  Complete-UnattendedResult -Status failed
  'held=' + ((Get-Content -Raw (Join-Path \$dir 'result-latest.json') | ConvertFrom-Json).held_resources -join ',')
")"
msg="$(cat "$TEST_TMPDIR/tolerateprove.out")"
if [[ "$msg" == *'timed out waiting for drain'* && "$msg" != *released* && "$msg" == *'held=fleet'* ]]; then
  pass "TolerateTakeExit keeps the resource held when the proof never arrives"
else
  fail "TolerateTakeExit keeps the resource held when the proof never arrives" "$msg"
fi

code="$(run_pwsh tolerateoff "
  \$dir = '$TEST_TMPDIR/tolerateoff'
  Initialize-UnattendedResult -ResultDirectory \$dir
  try {
    Use-GuardedResource -Name 'fleet' -Take { & pwsh -NoProfile -Command 'exit 5' } -Prove { \$true } -Release { 'released' }
  } catch { \$_.Exception.Message }
  Complete-UnattendedResult -Status failed
  'held=' + ((Get-Content -Raw (Join-Path \$dir 'result-latest.json') | ConvertFrom-Json).held_resources -join ',')
")"
msg="$(cat "$TEST_TMPDIR/tolerateoff.out")"
if [[ "$msg" == *'take fleet failed: native command exited 5'* && "$msg" != *released* && "$msg" == *'held=fleet'* ]]; then
  pass "without TolerateTakeExit a nonzero take exit throws and stays held"
else
  fail "without TolerateTakeExit a nonzero take exit throws and stays held" "$msg"
fi

code="$(run_pwsh toleratethrow "
  \$dir = '$TEST_TMPDIR/toleratethrow'
  Initialize-UnattendedResult -ResultDirectory \$dir
  try {
    Use-GuardedResource -Name 'fleet' -TolerateTakeExit -Take { throw 'take blew up' } -Prove { \$true } -Release { 'released' }
  } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/toleratethrow.out")"
if [[ "$msg" == *'take blew up'* && "$msg" != *released* ]]; then
  pass "TolerateTakeExit still fails on a thrown take exception"
else
  fail "TolerateTakeExit still fails on a thrown take exception" "$msg"
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

code="$(run_pwsh irrlist "
  Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/irrlist' -Irreversible 'wsl --unregister Ubuntu-26.04', 'git push --force' -Stages { 'stage' }
  \$json = Get-Content -Raw '$TEST_TMPDIR/irrlist/result-latest.json' | ConvertFrom-Json
  'schema=' + \$json.schema
  'declared=' + (\$json.irreversible_actions -join '|')
")"
msg="$(cat "$TEST_TMPDIR/irrlist.out")"
transcript="$(find "$TEST_TMPDIR/irrlist" -name 'transcript-*.log' | head -1)"
if grep -Fq 'irreversible actions: wsl --unregister Ubuntu-26.04; git push --force' "$transcript" \
  && [[ "$msg" == *'schema=cutover.result/1'* && "$msg" == *'declared=wsl --unregister Ubuntu-26.04|git push --force'* ]]; then
  pass "the declared irreversible list is in the transcript and the result JSON"
else
  fail "the declared irreversible list is in the transcript and the result JSON" "$msg $(head -c 400 "$transcript" 2>/dev/null)"
fi

code="$(run_pwsh irrnone "
  Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/irrnone' -Stages { 'stage' }
  \$json = Get-Content -Raw '$TEST_TMPDIR/irrnone/result-latest.json' | ConvertFrom-Json
  'present=' + (\$json.PSObject.Properties.Name -contains 'irreversible_actions')
  'count=' + @(\$json.irreversible_actions).Count
")"
msg="$(cat "$TEST_TMPDIR/irrnone.out")"
transcript="$(find "$TEST_TMPDIR/irrnone" -name 'transcript-*.log' | head -1)"
if grep -Fq 'irreversible actions: none' "$transcript" && [[ "$msg" == *'present=True'* && "$msg" == *'count=0'* ]]; then
  pass "a run that declares nothing says none and emits an empty list"
else
  fail "a run that declares nothing says none and emits an empty list" "$msg"
fi

code="$(run_pwsh irrundeclared "
  try {
    Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/irrundeclared' -Irreversible 'wipe' -Stages { Confirm-Irreversible -Name 'other' }
  } catch { \$_.Exception.Message }
  \$json = Get-Content -Raw '$TEST_TMPDIR/irrundeclared/result-latest.json' | ConvertFrom-Json
  'status=' + \$json.status
  'declared=' + (\$json.irreversible_actions -join '|')
")"
msg="$(cat "$TEST_TMPDIR/irrundeclared.out")"
if [[ "$msg" == *'irreversible step other was not declared'* && "$msg" == *'status=failed'* && "$msg" == *'declared=wipe'* ]]; then
  pass "Confirm-Irreversible refuses an undeclared step before prompting"
else
  fail "Confirm-Irreversible refuses an undeclared step before prompting" "$msg"
fi

code="$(run_pwsh irrheld "
  try {
    Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/irrheld' -Irreversible 'wipe' -Stages {
      try { Use-GuardedResource -Name 'fleet' -Take { } -Prove { \$false } -Release { } } catch { }
      Confirm-Irreversible -Name 'wipe'
    }
  } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/irrheld.out")"
if [[ "$msg" == *'refusing irreversible step wipe while resources are held: fleet'* ]]; then
  pass "Confirm-Irreversible refuses while a guarded resource is held"
else
  fail "Confirm-Irreversible refuses while a guarded resource is held" "$msg"
fi

code="$(run_pwsh irrok "
  function Read-Host { 'wipe' }
  Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/irrok' -Irreversible 'wipe' -Stages {
    Use-GuardedResource -Name 'fleet' -Take { } -Prove { \$true } -Release { }
    Confirm-Irreversible -Name 'wipe'
  }
  \$step = (Get-Content -Raw '$TEST_TMPDIR/irrok/result-latest.json' | ConvertFrom-Json).steps | Where-Object name -eq 'irreversible wipe'
  'step=' + \$step.status + ':' + \$step.detail
")"
msg="$(cat "$TEST_TMPDIR/irrok.out")"
if [[ "$msg" == *'step=ok:confirmed'* ]]; then
  pass "a declared irreversible step with nothing held is confirmed and recorded"
else
  fail "a declared irreversible step with nothing held is confirmed and recorded" "$msg $(cat "$TEST_TMPDIR/irrok.err")"
fi

code="$(run_pwsh irrdecline "
  function Read-Host { 'no' }
  try {
    Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/irrdecline' -Irreversible 'wipe' -Stages { Confirm-Irreversible -Name 'wipe' }
  } catch { \$_.Exception.Message }
")"
msg="$(cat "$TEST_TMPDIR/irrdecline.out")"
if [[ "$msg" == *'confirmation declined for wipe'* ]]; then
  pass "a wrong confirmation answer aborts the run"
else
  fail "a wrong confirmation answer aborts the run" "$msg"
fi

# Assert-ParsedState: name|value expression|expected (throws, or the item count).
# shellcheck disable=SC2016 # PowerShell expressions are literal data, not shell expansions
for case in 'parsednull|$null|throws' 'parsedarray|@()|throws' "parsedblank|'   '|throws" "parsedblanks|@('', ' ')|throws" \
  "parsedone|'Ubuntu-26.04'|1" "parsedtwo|@('a', 'b')|2" 'parsedlines|("a" + [Environment]::NewLine + "b")|2'; do
  IFS='|' read -r name value expected <<<"$case"
  code="$(run_pwsh "$name" "
    try { Assert-ParsedState -Name 'listing' -Value $value; 'passed' } catch { \$_.Exception.Message }
  ")"
  msg="$(cat "$TEST_TMPDIR/$name.out")"
  if [[ "$expected" == throws && "$msg" == *"could not read listing: parsed listing is empty. Unknown state is a stop, not 'already absent'"* && "$msg" != *passed* ]] \
    || [[ "$expected" != throws && "$msg" == *"read listing: $expected item(s)"* && "$msg" == *passed* ]]; then
    pass "Assert-ParsedState on '$value' gives $expected"
  else
    fail "Assert-ParsedState on '$value' gives $expected" "$msg"
  fi
done

code="$(run_pwsh utf8 "
  \$env:WSL_UTF8 = \$null
  [Console]::OutputEncoding = [Text.Encoding]::Latin1
  \$inside = @(Invoke-NativeUtf8 { & pwsh -NoProfile -Command '\$env:WSL_UTF8'; & pwsh -NoProfile -Command '[Console]::Out.Write([char]0xE9)' })
  'variable=' + \$inside[0]
  'decoded=' + \$inside[1].Length
  'after=' + \$(if (Test-Path Env:WSL_UTF8) { \$env:WSL_UTF8 } else { 'unset' })
  'encoding=' + [Console]::OutputEncoding.WebName
")"
msg="$(cat "$TEST_TMPDIR/utf8.out")"
if [[ "$msg" == *'variable=1'* && "$msg" == *'decoded=1'* && "$msg" == *'after=unset'* && "$msg" == *'encoding=iso-8859-1'* ]]; then
  pass "Invoke-NativeUtf8 pins WSL_UTF8 and UTF-8 decoding inside the block and restores both"
else
  fail "Invoke-NativeUtf8 pins WSL_UTF8 and UTF-8 decoding inside the block and restores both" "$msg"
fi

code="$(run_pwsh utf8throw "
  \$env:WSL_UTF8 = 'keep'
  [Console]::OutputEncoding = [Text.Encoding]::Latin1
  try { Invoke-NativeUtf8 { throw 'boom' } } catch { 'caught=' + \$_.Exception.Message }
  'after=' + \$env:WSL_UTF8
  'encoding=' + [Console]::OutputEncoding.WebName
")"
msg="$(cat "$TEST_TMPDIR/utf8throw.out")"
if [[ "$msg" == *'caught=boom'* && "$msg" == *'after=keep'* && "$msg" == *'encoding=iso-8859-1'* ]]; then
  pass "Invoke-NativeUtf8 restores the prior variable and encoding when the block throws"
else
  fail "Invoke-NativeUtf8 restores the prior variable and encoding when the block throws" "$msg"
fi

code="$(run_pwsh moderun "
  \$dir = '$TEST_TMPDIR/moderun'
  Initialize-UnattendedResult -ResultDirectory \$dir
  Complete-UnattendedResult -Status ok
  \$json = Get-Content -Raw (Join-Path \$dir 'result-latest.json') | ConvertFrom-Json
  'mode=' + \$json.mode
  'planned=' + (\$json.PSObject.Properties.Name -contains 'planned')
  'delta=' + (\$json.PSObject.Properties.Name -contains 'delta')
")"
msg="$(cat "$TEST_TMPDIR/moderun.out")"
if [[ "$msg" == *'mode=run'* && "$msg" == *'planned=False'* && "$msg" == *'delta=False'* ]]; then
  pass "a real run records mode run and no dry-run fields"
else
  fail "a real run records mode run and no dry-run fields" "$msg"
fi

# Dry runs launch a copy of the template with a small stages block, as the operator would.
# Every mutating block writes under DRY_MARKER, so a leftover file proves a block ran.
DRY_STAGES="$(
  cat <<'PS'
# STAGES
Invoke-UnattendedRun -ResultDirectory (Join-Path $env:DRY_DIR 'results') -Irreversible 'wipe' -Stages {
    Assert-Elevation -Mode Forbidden
    Add-Preflight -Name 'dep' -Test { $true } -Fix 'none'
    Invoke-IdempotentStep -Name 'make marker' -Done { Test-Path -LiteralPath $env:DRY_MARKER } -Action { Set-Content -LiteralPath $env:DRY_MARKER -Value ran }
    Invoke-IdempotentStep -Name 'already there' -Done { $true } -Action { Set-Content -LiteralPath "$env:DRY_MARKER.done" -Value ran }
    Use-GuardedResource -Name 'fleet' -Take { Set-Content -LiteralPath "$env:DRY_MARKER.take" -Value took } -Prove { Set-Content -LiteralPath "$env:DRY_MARKER.prove" -Value proved; $true } -Release { Set-Content -LiteralPath "$env:DRY_MARKER.release" -Value released }
    $null = Wait-ForState -Name 'gone' -TimeoutSeconds ([int] $env:DRY_WAIT) -Predicate { $false }
    $null = Resolve-UnattendedSecret -Name 'DRY_SET_SECRET'
    $null = Resolve-UnattendedSecret -Name 'DRY_UNSET_SECRET'
    Confirm-Irreversible -Name 'wipe'
}
PS
)"

# run_launch <name> <stages> [script flags...]: prints the exit code; output lands in $TEST_TMPDIR/<name>/{out,err}.
# -NonInteractive makes a reached Read-Host throw, so a prompt shows up as a failure.
run_launch() {
  local name="$1" stages="$2" dir
  shift 2
  dir="$TEST_TMPDIR/$name"
  mkdir -p "$dir"
  { sed '/^# STAGES$/,$d' "$TEMPLATE"; printf '%s\n' "$stages"; } >"$dir/copy.ps1"
  (
    cd "$dir" || exit 99
    DRY_DIR="$dir" DRY_MARKER="$dir/marker" DRY_WAIT="${DRY_WAIT:-20}" DRY_SET_SECRET=sekret \
      pwsh -NoProfile -NonInteractive -File copy.ps1 "$@" >out 2>err
  )
  printf '%s' "$?"
}

# summarize <result json>: one line of the fields the tests compare.
summarize() {
  pwsh -NoProfile -Command "
    \$json = Get-Content -Raw '$1' | ConvertFrom-Json
    'mode=' + \$json.mode + ' status=' + \$json.status + ' steps=' + \$json.planned.steps + ' resources=' + \$json.planned.resources + ' irreversible=' + \$json.planned.irreversible + ' delta=' + ((\$json.delta | ForEach-Object name) -join '|') + ' held=' + (\$json.held_resources -join ',')
  "
}

DRY_DELTA='delta=make marker|guard fleet|wait gone|secret DRY_UNSET_SECRET|irreversible wipe held='
for mode in whatif test; do
  flag="-WhatIf"
  [[ "$mode" == test ]] && flag="-Test"
  dir="$TEST_TMPDIR/dry-$mode"
  code="$(run_launch "dry-$mode" "$DRY_STAGES" "$flag")"
  summary="$(summarize "$dir/results/result-dry-latest.json" 2>&1)"
  # portability-ok: false positive, plain sort with no -V option
  outside="$(cd "$dir" && find . -type f -not -path './results/*' | sort | tr '\n' ' ')"
  leftovers="$(find "$dir" -maxdepth 1 -name 'marker*' | tr '\n' ' ')"
  prompted=0
  # portability-ok: false positive, fixed-string grep with no -P option
  grep -Fq 'NonInteractive' "$dir/err" && prompted=1
  if [[ "$code" == 0 ]] \
    && [[ "$summary" == "mode=$mode status=ok steps=5 resources=1 irreversible=1 $DRY_DELTA" ]] \
    && [[ -z "$leftovers" ]] \
    && [[ "$outside" == './copy.ps1 ./err ./out ' ]] \
    && [[ ! -e "$dir/results/result-latest.json" ]] \
    && [[ "$prompted" == 0 ]]; then
    pass "$flag runs no block, prompts nothing, reports the plan and writes only the dry result"
  else
    fail "$flag runs no block, prompts nothing, reports the plan and writes only the dry result" "code=$code summary=$summary leftovers=$leftovers outside=$outside err=$(head -c 300 "$dir/err")"
  fi
done

out="$(cat "$TEST_TMPDIR/dry-whatif/out")"
if [[ "$out" == *'What if: dep [ok] preflight'* && "$out" == *'What if: make marker [would-run]'* && "$out" == *'What if: already there [skipped] already done'* \
  && "$out" == *'What if: blast radius: 5 step(s) would run, 1 resource(s) would be taken out of service, 1 declared irreversible action(s)'* ]]; then
  pass "-WhatIf narrates every step, done ones included, and ends with the blast radius counts"
else
  fail "-WhatIf narrates every step, done ones included, and ends with the blast radius counts" "$out"
fi

out="$(cat "$TEST_TMPDIR/dry-test/out")"
# portability-ok: false positive, grep -c counts lines and no -P/-V option is used
if [[ "$(printf '%s\n' "$out" | grep -c .)" == 1 && "$out" == 'Test: 5 step(s) would run, 1 resource(s) would be taken out of service, 1 declared irreversible action(s). Delta: '* ]]; then
  pass "-Test prints one final line and no narration"
else
  fail "-Test prints one final line and no narration" "$out"
fi

code="$(run_launch dry-both "$DRY_STAGES" -Test -WhatIf)"
if [[ "$code" == 0 && "$(summarize "$TEST_TMPDIR/dry-both/results/result-dry-latest.json")" == mode=test* && "$(cat "$TEST_TMPDIR/dry-both/out")" != *'What if:'* ]]; then
  pass "-Test wins over -WhatIf"
else
  fail "-Test wins over -WhatIf" "code=$code $(cat "$TEST_TMPDIR/dry-both/out")"
fi

# The same stages without a flag do the work; the wait times out after 1s, which stops the run.
code="$(DRY_WAIT=1 run_launch real "$DRY_STAGES")"
dir="$TEST_TMPDIR/real"
summary="$(summarize "$dir/results/result-latest.json" 2>&1)"
timed_out=0
# portability-ok: false positive, fixed-string grep with no -P option
grep -Fq 'timed out waiting for gone' "$dir/err" && timed_out=1
if [[ "$code" != 0 && "$summary" == mode=run\ status=failed* ]] \
  && [[ -f "$dir/marker" && -f "$dir/marker.take" && -f "$dir/marker.prove" && -f "$dir/marker.release" && ! -e "$dir/marker.done" ]] \
  && [[ "$timed_out" == 1 ]] \
  && [[ ! -e "$dir/results/result-dry-latest.json" ]]; then
  pass "a run without flags executes the blocks and writes result-latest.json"
else
  fail "a run without flags executes the blocks and writes result-latest.json" "code=$code summary=$summary err=$(head -c 300 "$dir/err")"
fi

BARE_STAGES="$(
  cat <<'PS'
# STAGES
Invoke-UnattendedRun -ResultDirectory (Join-Path $env:DRY_DIR 'results') -Stages {
    Set-Content -LiteralPath $env:DRY_MARKER -Value bare
}
PS
)"
for flag in -WhatIf -Test ''; do
  code="$(run_launch "bare$flag" "$BARE_STAGES" $flag)"
  dir="$TEST_TMPDIR/bare$flag"
  if [[ "$flag" == '' && -f "$dir/marker" ]] || [[ "$flag" != '' && "$code" == 0 && ! -e "$dir/marker" ]]; then
    pass "a cmdlet outside a helper honors dry mode with '${flag:-no flag}'"
  else
    fail "a cmdlet outside a helper honors dry mode with '${flag:-no flag}'" "code=$code $(head -c 300 "$dir/err")"
  fi
done

FAILING_STAGES="$(
  cat <<'PS'
# STAGES
Invoke-UnattendedRun -ResultDirectory (Join-Path $env:DRY_DIR 'results') -Stages {
    Add-Preflight -Name 'dep' -Test { $false } -Fix 'install it'
    Invoke-IdempotentStep -Name 'make marker' -Done { $false } -Action { Set-Content -LiteralPath $env:DRY_MARKER -Value ran }
}
PS
)"
code="$(run_launch dry-preflight "$FAILING_STAGES" -Test)"
dir="$TEST_TMPDIR/dry-preflight"
summary="$(summarize "$dir/results/result-dry-latest.json" 2>&1)"
preflight_failed=0
# portability-ok: false positive, fixed-string grep with no -P option
grep -Fq 'preflight failed: dep. Fix: install it' "$dir/err" && preflight_failed=1
if [[ "$code" != 0 && "$summary" == 'mode=test status=failed steps=0 resources=0 irreversible=0 delta=dep held=' && ! -e "$dir/marker" ]] \
  && [[ "$preflight_failed" == 1 ]]; then
  pass "-Test lists a failed preflight in the delta and stops before later steps"
else
  fail "-Test lists a failed preflight in the delta and stops before later steps" "code=$code summary=$summary err=$(head -c 300 "$dir/err")"
fi

UNDECLARED_STAGES="$(
  cat <<'PS'
# STAGES
Invoke-UnattendedRun -ResultDirectory (Join-Path $env:DRY_DIR 'results') -Irreversible 'wipe' -Stages {
    Confirm-Irreversible -Name 'other'
}
PS
)"
code="$(run_launch dry-undeclared "$UNDECLARED_STAGES" -WhatIf)"
dir="$TEST_TMPDIR/dry-undeclared"
undeclared_refused=0
# portability-ok: false positive, fixed-string grep with no -P option
grep -Fq 'irreversible step other was not declared' "$dir/err" && ! grep -Fq 'NonInteractive' "$dir/err" && undeclared_refused=1
if [[ "$code" != 0 && "$(summarize "$dir/results/result-dry-latest.json" 2>&1)" == mode=whatif\ status=failed* ]] \
  && [[ "$undeclared_refused" == 1 ]]; then
  pass "a dry run still refuses an undeclared irreversible step, before any prompt"
else
  fail "a dry run still refuses an undeclared irreversible step, before any prompt" "code=$code $(head -c 300 "$dir/err")"
fi

ELEVATED_STAGES="$(
  cat <<'PS'
# STAGES
Invoke-UnattendedRun -ResultDirectory (Join-Path $env:DRY_DIR 'results') -Stages {
    Assert-Elevation -Mode Required
    Invoke-IdempotentStep -Name 'make marker' -Done { $false } -Action { Set-Content -LiteralPath $env:DRY_MARKER -Value ran }
}
PS
)"
code="$(run_launch dry-elevation "$ELEVATED_STAGES" -Test)"
dir="$TEST_TMPDIR/dry-elevation"
if [[ "$code" != 0 && "$(summarize "$dir/results/result-dry-latest.json" 2>&1)" == mode=test\ status=failed* && ! -e "$dir/marker" ]] \
  && grep -Fq 'refusing to run unelevated' "$dir/err"; then
  pass "a dry run still enforces the elevation guard"
else
  fail "a dry run still enforces the elevation guard" "code=$code $(head -c 300 "$dir/err")"
fi

# Declared secrets: the mocks below stand in for the prompt (Read-Host) and the credential store (Get-Secret).
# A function outranks a cmdlet in PowerShell command resolution, so the library's own calls reach the mocks.
# Read-Host records 'prompt:<Prompt>' in $global:Log and answers 'typed-<Name>'.
# An empty PSModulePath keeps a real SecretManagement install from answering when no store mock is defined.
SECRET_MOCKS="$(
  cat <<'PS'
$global:Log = [System.Collections.Generic.List[string]]::new()
function Read-Host {
    param([string] $Prompt, [switch] $AsSecureString)
    $global:Log.Add("prompt:$Prompt")
    ConvertTo-SecureString ('typed-' + ($Prompt -replace '^Secret ', '')) -AsPlainText -Force
}
$env:PSModulePath = ''
PS
)"
STORE_MOCK="$(
  cat <<'PS'
function Get-Secret {
    [CmdletBinding()]
    param([string] $Name, [switch] $AsPlainText)
    if ($Name -like 'STORE_*') { "store-$Name" }
}
PS
)"

code="$(run_pwsh store-present "
  $SECRET_MOCKS
  $STORE_MOCK
  Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/store-present' -Secrets @(@{ Name = 'STORE_A' }) -Stages {
    \$global:Log.Add('got:' + (Resolve-UnattendedSecret -Name 'STORE_A'))
  }
  \$global:Log -join '|'
")"
msg="$(tail -n 1 "$TEST_TMPDIR/store-present.out")"
if [[ "$code" == 0 && "$msg" == 'got:store-STORE_A' ]]; then
  pass "a declared secret resolves from the credential store when the store has it"
else
  fail "a declared secret resolves from the credential store when the store has it" "code=$code msg=$msg err=$(head -c 300 "$TEST_TMPDIR/store-present.err")"
fi

code="$(run_pwsh store-absent "
  $SECRET_MOCKS
  \$direct = Get-UnattendedStoreSecret -Name 'STORE_A'
  \$ladder = Find-UnattendedSecret -Name 'STORE_A'
  'command=' + [bool] (Get-Command Get-Secret -ErrorAction SilentlyContinue)
  'direct=' + (\$null -eq \$direct)
  'ladder=' + (\$null -eq \$ladder)
")"
if [[ "$code" == 0 && "$(cat "$TEST_TMPDIR/store-absent.out")" == $'command=False\ndirect=True\nladder=True' && ! -s "$TEST_TMPDIR/store-absent.err" ]]; then
  pass "without a credential store the rung is skipped silently"
else
  fail "without a credential store the rung is skipped silently" "code=$code out=$(cat "$TEST_TMPDIR/store-absent.out") err=$(head -c 300 "$TEST_TMPDIR/store-absent.err")"
fi

printf 'file-loses' >"$TEST_TMPDIR/prec-file-vs-env"
printf 'file-beats-store' >"$TEST_TMPDIR/prec-file-vs-store"
code="$(PREC_ENV=env-value run_pwsh precedence "
  $SECRET_MOCKS
  $STORE_MOCK
  Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/precedence' -Secrets @(
    @{ Name = 'PREC_ENV'; FilePath = '$TEST_TMPDIR/prec-file-vs-env' },
    @{ Name = 'STORE_FILE'; FilePath = '$TEST_TMPDIR/prec-file-vs-store' },
    @{ Name = 'STORE_ONLY'; FilePath = '$TEST_TMPDIR/prec-missing' },
    @{ Name = 'PROMPT_ONLY'; FilePath = '$TEST_TMPDIR/prec-missing' }
  ) -Stages {
    foreach (\$name in 'PREC_ENV', 'STORE_FILE', 'STORE_ONLY', 'PROMPT_ONLY') {
      \$global:Log.Add(\$name + '=' + (Resolve-UnattendedSecret -Name \$name))
    }
  }
  \$global:Log -join '|'
")"
msg="$(tail -n 1 "$TEST_TMPDIR/precedence.out")"
if [[ "$code" == 0 && "$msg" == 'prompt:Secret PROMPT_ONLY|PREC_ENV=env-value|STORE_FILE=file-beats-store|STORE_ONLY=store-STORE_ONLY|PROMPT_ONLY=typed-PROMPT_ONLY' ]]; then
  pass "a declared secret resolves environment over file over store over prompt"
else
  fail "a declared secret resolves environment over file over store over prompt" "code=$code msg=$msg err=$(head -c 300 "$TEST_TMPDIR/precedence.err")"
fi

code="$(run_pwsh before-stage "
  $SECRET_MOCKS
  Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/before-stage' -Secrets @(@{ Name = 'ORDER_A' }) -Stages {
    \$global:Log.Add('stage')
    \$global:Log.Add('got:' + (Resolve-UnattendedSecret -Name 'ORDER_A'))
    \$global:Log.Add('got:' + (Resolve-UnattendedSecret -Name 'ORDER_A'))
  }
  \$global:Log -join '|'
")"
msg="$(tail -n 1 "$TEST_TMPDIR/before-stage.out")"
if [[ "$code" == 0 && "$msg" == 'prompt:Secret ORDER_A|stage|got:typed-ORDER_A|got:typed-ORDER_A' ]]; then
  pass "a declared secret is prompted before the first stage and a stage never prompts for it again"
else
  fail "a declared secret is prompted before the first stage and a stage never prompts for it again" "code=$code msg=$msg err=$(head -c 300 "$TEST_TMPDIR/before-stage.err")"
fi

code="$(run_pwsh two-prompts "
  $SECRET_MOCKS
  Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/two-prompts' -Secrets @(@{ Name = 'TWO_A' }, @{ Name = 'TWO_B' }) -Stages {
    \$global:Log.Add('stage')
  }
  \$global:Log -join '|'
")"
msg="$(tail -n 1 "$TEST_TMPDIR/two-prompts.out")"
if [[ "$code" == 0 && "$msg" == 'prompt:Secret TWO_A|prompt:Secret TWO_B|stage' ]]; then
  pass "every unresolved declared secret is prompted before any stage"
else
  fail "every unresolved declared secret is prompted before any stage" "code=$code msg=$msg err=$(head -c 300 "$TEST_TMPDIR/two-prompts.err")"
fi

code="$(DECL_ENV=declared-env run_pwsh undeclared "
  $SECRET_MOCKS
  Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/undeclared' -Secrets @(@{ Name = 'DECL_ENV' }) -Stages {
    \$global:Log.Add('stage')
    \$global:Log.Add('got:' + (Resolve-UnattendedSecret -Name 'UNDECL_A'))
  }
  \$global:Log -join '|'
")"
msg="$(tail -n 1 "$TEST_TMPDIR/undeclared.out")"
if [[ "$code" == 0 && "$msg" == 'stage|prompt:Secret UNDECL_A|got:typed-UNDECL_A' ]]; then
  pass "an undeclared secret still resolves and prompts at first use"
else
  fail "an undeclared secret still resolves and prompts at first use" "code=$code msg=$msg err=$(head -c 300 "$TEST_TMPDIR/undeclared.err")"
fi

printf 'file-secret-value' >"$TEST_TMPDIR/leak-file"
code="$(LEAK_ENV=env-secret-value run_pwsh leak "
  $SECRET_MOCKS
  $STORE_MOCK
  Invoke-UnattendedRun -ResultDirectory '$TEST_TMPDIR/leak' -Secrets @(
    @{ Name = 'LEAK_ENV' },
    @{ Name = 'LEAK_FILE'; FilePath = '$TEST_TMPDIR/leak-file' },
    @{ Name = 'STORE_LEAK' },
    @{ Name = 'LEAK_PROMPT' }
  ) -Stages {
    foreach (\$name in 'LEAK_ENV', 'LEAK_FILE', 'STORE_LEAK', 'LEAK_PROMPT') {
      Write-Host ('value ' + (Resolve-UnattendedSecret -Name \$name))
    }
  }
  \$json = Get-Content -Raw '$TEST_TMPDIR/leak/result-latest.json' | ConvertFrom-Json
  'names=' + (\$json.secrets -join '|')
")"
transcript="$(find "$TEST_TMPDIR/leak" -name 'transcript-*.log' | head -1)"
leaked=0
for value in env-secret-value file-secret-value store-STORE_LEAK typed-LEAK_PROMPT; do
  grep -Fq "$value" "$transcript" "$TEST_TMPDIR/leak/result-latest.json" && leaked=1
done
if [[ "$code" == 0 && "$leaked" == 0 && "$(grep -Fc '***' "$transcript")" -ge 4 ]] \
  && [[ "$(tail -n 1 "$TEST_TMPDIR/leak.out")" == 'names=LEAK_ENV|LEAK_FILE|STORE_LEAK|LEAK_PROMPT' ]]; then
  pass "declared secret values stay out of the transcript and the result JSON, which lists names only"
else
  fail "declared secret values stay out of the transcript and the result JSON, which lists names only" "code=$code leaked=$leaked out=$(tail -n 1 "$TEST_TMPDIR/leak.out") err=$(head -c 300 "$TEST_TMPDIR/leak.err")"
fi

DECLARED_STAGES="$(
  cat <<'PS'
# STAGES
Invoke-UnattendedRun -ResultDirectory (Join-Path $env:DRY_DIR 'results') -Secrets @(@{ Name = 'DRY_SET_SECRET' }, @{ Name = 'DRY_DECL_UNSET' }) -Stages {
    Invoke-IdempotentStep -Name 'make marker' -Done { $false } -Action { Set-Content -LiteralPath $env:DRY_MARKER -Value ran }
    $null = Resolve-UnattendedSecret -Name 'DRY_DECL_UNSET'
}
PS
)"
for mode in whatif test; do
  flag="-WhatIf"
  [[ "$mode" == test ]] && flag="-Test"
  dir="$TEST_TMPDIR/dry-declared-$mode"
  code="$(run_launch "dry-declared-$mode" "$DECLARED_STAGES" "$flag")"
  summary="$(summarize "$dir/results/result-dry-latest.json" 2>&1)"
  prompted=0
  # portability-ok: false positive, fixed-string grep with no -P option
  grep -Fq 'NonInteractive' "$dir/err" && prompted=1
  if [[ "$code" == 0 && "$prompted" == 0 && ! -e "$dir/marker" ]] \
    && [[ "$summary" == "mode=$mode status=ok steps=2 resources=0 irreversible=0 delta=secret DRY_DECL_UNSET|make marker held=" ]] \
    && grep -Fq '"DRY_DECL_UNSET"' "$dir/results/result-dry-latest.json"; then
    pass "$flag reports a declared unresolved secret as a would-run delta entry and prompts nothing"
  else
    fail "$flag reports a declared unresolved secret as a would-run delta entry and prompts nothing" "code=$code summary=$summary err=$(head -c 300 "$dir/err")"
  fi
done

if [[ "$FAILED" -eq 0 ]]; then
  printf 'OK\n'
  exit 0
fi
printf '%s failed\n' "$FAILED" >&2
exit 1
