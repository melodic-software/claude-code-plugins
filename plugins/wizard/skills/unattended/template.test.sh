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
  outside="$(cd "$dir" && find . -type f -not -path './results/*' | sort | tr '\n' ' ')"
  leftovers="$(ls "$dir"/marker* 2>/dev/null | tr '\n' ' ')"
  if [[ "$code" == 0 ]] \
    && [[ "$summary" == "mode=$mode status=ok steps=5 resources=1 irreversible=1 $DRY_DELTA" ]] \
    && [[ -z "$leftovers" ]] \
    && [[ "$outside" == './copy.ps1 ./err ./out ' ]] \
    && [[ ! -e "$dir/results/result-latest.json" ]] \
    && ! grep -Fq 'NonInteractive' "$dir/err"; then
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
if [[ "$code" != 0 && "$summary" == mode=run\ status=failed* ]] \
  && [[ -f "$dir/marker" && -f "$dir/marker.take" && -f "$dir/marker.prove" && -f "$dir/marker.release" && ! -e "$dir/marker.done" ]] \
  && grep -Fq 'timed out waiting for gone' "$dir/err" \
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
if [[ "$code" != 0 && "$summary" == 'mode=test status=failed steps=0 resources=0 irreversible=0 delta=dep held=' && ! -e "$dir/marker" ]] \
  && grep -Fq 'preflight failed: dep. Fix: install it' "$dir/err"; then
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
if [[ "$code" != 0 && "$(summarize "$dir/results/result-dry-latest.json" 2>&1)" == mode=whatif\ status=failed* ]] \
  && grep -Fq 'irreversible step other was not declared' "$dir/err" && ! grep -Fq 'NonInteractive' "$dir/err"; then
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

if [[ "$FAILED" -eq 0 ]]; then
  printf 'OK\n'
  exit 0
fi
printf '%s failed\n' "$FAILED" >&2
exit 1
