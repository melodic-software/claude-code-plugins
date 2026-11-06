#!/usr/bin/env bash
# The first process in pr-verify-capture.yml's sibling sandbox, run from the
# root-owned copy at /opt/ccd/sibling-init.sh with the workspace as $1.
# Before any pull request code exists it records what code here can reach:
# the reach probe (capture-probe.mjs, with the sentinel's name added), the
# driver engine's doctor, the bridge to the key proxy, whether the internet
# answers, the process count and the sandbox's first environment. The
# workflow's "Check the sibling sandbox" step reads those files and fails the
# job on anything unexpected. Then it starts the launch broker, the only
# process given the dummy key, on its stdin.
set -uo pipefail

ws=$1
rt=${CCD_RUNTIME_DIR:?}
probe=$rt/probe
driver=/opt/ccd/control-claude-code/driver
port=47100

# The broker's roots must exist when it starts; the head checkout fills head later.
mkdir -p "$ws/head" "$ws/capture-run"

# The sandbox has no network: a loopback port carries the driven session's
# requests to the key proxy's unix socket outside.
socat "TCP-LISTEN:$port,bind=127.0.0.1,fork,reuseaddr" UNIX-CONNECT:/run/ccd-proxy/proxy.sock </dev/null >>"$rt/log/socat.log" 2>&1 &

# The probe runs before the broker, so no process here holds even the dummy key.
(cd "$ws" && CAPTURE_PROBE_EXTRA_NAMES=CCD_SENTINEL_CREDENTIAL node /opt/ccd/capture-probe.mjs "$probe/capture-probe.json" >"$probe/capture-probe.out" 2>&1)

node "$driver/driver.mjs" doctor --deps-dir /opt/ccd/deps >"$probe/doctor.out" 2>&1
doctor_rc=$?
engine=false
if grep -qx 'engine: loads' "$probe/doctor.out" && grep -qx 'signatures: verified at install' "$probe/doctor.out"; then
  engine=true
fi

status=none
for _ in $(seq 20); do
  status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$port/v1/models") && [[ $status != 000 ]] && break
  sleep 0.25
done
if curl -s -o /dev/null --max-time 3 https://api.anthropic.com/; then
  egress=open
else
  egress=refused
fi
pids=(/proc/[0-9]*)
pid1_env=$(tr '\0' '\n' </proc/1/environ | cut -d= -f1 | jq -R . | jq -s -c sort)
jq -n --argjson pids "${#pids[@]}" --arg ps "$status" --arg eg "$egress" --argjson dr "$doctor_rc" --argjson engine "$engine" --argjson env "$pid1_env" \
  '{pids: $pids, proxy_status: $ps, egress: $eg, doctor_rc: $dr, engine: $engine, pid1_env: $env}' >"$probe/facts.json"

# The driven session's home is this sandbox's tmpfs: onboarding done, the
# dummy key approved by its last 20 characters as Claude Code records it, and
# the empty working directory trusted. The key stays in an unexported variable
# and reaches jq and the broker on stdin only.
key="ccd-dummy-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
printf '%s' "${key: -20}" | jq -R --arg w "$HOME/w" \
  '{hasCompletedOnboarding: true, customApiKeyResponses: {approved: [.], rejected: []}, projects: {($w): {hasTrustDialogAccepted: true}}}' >"$HOME/.claude.json"

touch "$probe/done"
printf '%s' "$key" | exec node "$driver/broker.mjs" --socket "$rt/broker/broker.sock" --driver "$driver/driver.mjs" \
  --root "$ws/head" --root "$ws/capture-run" --deps-dir /opt/ccd/deps >>"$rt/log/broker.log" 2>&1
