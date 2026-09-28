#!/usr/bin/env bash
# Exercises the unattended bash library. Does not launch the PowerShell template
# except for a parse check when pwsh is present.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$ROOT/template.sh"
fail=0
ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

bash -n "$TEMPLATE" && ok "bash -n" || bad "bash -n"

if command -v pwsh >/dev/null 2>&1; then
  if pwsh -NoProfile -NonInteractive -Command "\$e=\$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$ROOT/template.ps1', [ref]\$null, [ref]\$e); if (\$e) { \$e | ForEach-Object { \$_.ToString() }; exit 1 }"; then
    ok "pwsh parse"
  else
    bad "pwsh parse"
  fi
else
  printf 'SKIP: pwsh parse (pwsh absent)\n'
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=template.sh
RESULT_DIR="$TMP/r1"
RESULT_NAME=result
UNATTENDED_LIB_ONLY=1 source "$TEMPLATE"

require_user && ok "require_user when not root" || bad "require_user"
if require_root; then
  bad "require_root should fail unelevated"
else
  ok "require_root refuses unelevated"
fi

WSL_DISTRO_NAME=Ubuntu-26.04
if refuse_if_env WSL_DISTRO_NAME Ubuntu-26.04; then
  bad "refuse_if_env should fail"
else
  ok "refuse_if_env"
fi
unset WSL_DISTRO_NAME
refuse_if_env WSL_DISTRO_NAME Ubuntu-26.04 && ok "refuse_if_env allows other" || bad "refuse_if_env allows other"

export DEMO_SECRET='s3cret-value'
got="$(resolve_secret DEMO_SECRET)"
[[ "$got" == "s3cret-value" ]] && ok "secret from env" || bad "secret from env"
printf 'token=%s\n' 'file-secret' >"$TMP/secrets"
unset DEMO_SECRET
got="$(resolve_secret token "$TMP/secrets")"
[[ "$got" == "file-secret" ]] && ok "secret from file" || bad "secret from file"

if preflight_bin bash "install bash"; then
  ok "preflight present"
else
  bad "preflight present"
fi
if preflight_bin wizard-unattended-missing-bin "install wizard-unattended-missing-bin"; then
  bad "preflight missing should fail"
else
  ok "preflight missing names remedy"
fi

hold fleet
release fleet
[[ ${#HELD[@]} -eq 0 ]] && ok "release clears hold" || bad "release clears hold"
hold fleet
write_result
python3 - "$TMP/r1/result.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc["schema"] == "wizard-unattended/1"
assert doc["status"] == "failed"
assert "fleet" in doc["held"]
text = open(sys.argv[1]).read()
assert "s3cret-value" not in text and "file-secret" not in text
print("json shape ok")
PY
[[ $? -eq 0 ]] && ok "result json holds fleet and redacts secrets" || bad "result json"

# Idempotent re-entry: a prior ok step is skipped.
RESULT_DIR="$TMP/r2" RESULT_NAME=result
mkdir -p "$RESULT_DIR"
cat >"$RESULT_DIR/result-latest.json" <<'JSON'
{
  "steps": [
    {"id": "again", "status": "ok", "detail": "done"}
  ]
}
JSON
STEP_IDS=() STEP_STATUS=() STEP_DETAIL=()
OVERALL=ok
run_step again true
[[ "${STEP_STATUS[0]}" == "skipped" ]] && ok "idempotent skip" || bad "idempotent skip"

if command -v pwsh >/dev/null 2>&1; then
  if RESULT_DIR="$TMP/ps" RESULT_NAME=result WIZARD_UNATTENDED_LIB=1 pwsh -NoProfile -NonInteractive -Command "
    . '$ROOT/template.ps1'
    Refuse-Elevated
    if (\$script:Overall -ne 'ok') { exit 1 }
    Invoke-Step 'ps-step' { }
    if (\$script:Steps[-1].status -ne 'ok') { exit 1 }
  "; then
    ok "pwsh library runs unelevated"
  else
    bad "pwsh library runs unelevated"
  fi
fi

[[ "$fail" -eq 0 ]] && exit 0
printf '%s failed\n' "$fail" >&2
exit 1
