#!/usr/bin/env bash
# The notify-service repository: a deploy workflow reading vars.SMS_SENDER_ID and secrets.SMS_GATEWAY_KEY, an env template, a live .env.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/sms-repo.sh"
