#!/usr/bin/env bash
# The notify-service repository plus scripts/setup-sms.sh: the generate library above the STAGES
# marker, taken unchanged from the plugin's template.sh, and a two-stage Textwave wizard below it.
# Refuses to overwrite an existing script.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
tpl="$here/../../skills/generate/template.sh"
out=scripts/setup-sms.sh
[[ -f "$tpl" ]] || { echo "refusing: $tpl not found" >&2; exit 1; }
[[ ! -e "$out" ]] || { echo "refusing: $out already exists" >&2; exit 1; }
bash "$here/../fixtures/sms-repo.sh"
sed '/^run_wizard() {$/,$d' "$tpl" >"$out"
cat >>"$out" <<'SH'
run_wizard() {
  TOTAL_STAGES=2

  banner "Textwave SMS setup" \
    "Keep a browser beside this terminal; pages for each stage open there." \
    "Ctrl-C quits. Answers saved in $ENV_FILE are pre-filled on a later run."

  # shellcheck disable=SC2154  # ask/ask_secret assign the named variable via printf -v
  stage "Textwave: sender ID"
  open_url "https://console.textwave.example/messaging/sender-ids"
  step "Copy the sender ID shown as Approved."
  ask SMS_SENDER_ID "Sender ID:"
  write_env SMS_SENDER_ID "$SMS_SENDER_ID"
  set_var SMS_SENDER_ID "$SMS_SENDER_ID" # the deploy workflow reads vars.SMS_SENDER_ID

  stage "Textwave: gateway key"
  open_url "https://console.textwave.example/developers/keys"
  step "Choose Create key, tick only the send scope, and copy the new key."
  ask_secret SMS_GATEWAY_KEY "Gateway key:"
  write_env SMS_GATEWAY_KEY "$SMS_GATEWAY_KEY"
  set_secret SMS_GATEWAY_KEY "$SMS_GATEWAY_KEY" # the deploy workflow reads secrets.SMS_GATEWAY_KEY

  finish "Textwave SMS setup complete"
  exit
}

run_wizard "$@"
SH
