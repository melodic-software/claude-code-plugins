#!/usr/bin/env bash
# Seed a finished but shallow incident write-up. The digest it was written from hides the cause;
# only the raw log shows one tenant failing after one config change.
set -euo pipefail

mkdir -p logs notes scripts

tenants=(acme-us globex initech acme-eu)
{
  for minute in $(seq 0 119); do
    hh=$((13 + (minute + 30) / 60))
    mm=$(((minute + 30) % 60))
    ts=$(printf '2026-10-18T%02d:%02d' "$hh" "$mm")
    if [ "$minute" -eq 35 ]; then
      echo "${ts}:00Z level=info msg=deploy release=4.18.2 tenants=acme-eu change=\"PAYMENTS_TIMEOUT_MS 3000->800\""
    fi
    for t in "${tenants[@]}"; do
      release=4.18.1
      if [ "$t" = acme-eu ] && [ "$minute" -ge 35 ]; then release=4.18.2; fi
      if [ "$release" = 4.18.2 ] && [ $((minute % 4)) -ne 0 ]; then
        echo "${ts}:12Z level=error tenant=$t route=/checkout status=502 upstream=payments-gateway upstream_ms=801 release=$release"
      elif [ $((minute % 40)) -eq 7 ] && [ "$t" = globex ]; then
        echo "${ts}:12Z level=error tenant=$t route=/checkout status=502 upstream=payments-gateway upstream_ms=2950 release=$release"
      else
        echo "${ts}:12Z level=info tenant=$t route=/checkout status=200 upstream=payments-gateway upstream_ms=$((400 + (minute * 7) % 900)) release=$release"
      fi
    done
  done
} >logs/checkout.log

errors=$(grep -c 'status=502' logs/checkout.log)
total=$(grep -c 'route=/checkout' logs/checkout.log)
cat >logs/summary.txt <<TXT
Daily checkout digest, 2026-10-18 (13:30-15:29 UTC)
Requests: $total
Errors: $errors (all HTTP 502, upstream payments-gateway)
Error rate: $((errors * 100 / total))%
Previous day error rate: 0%
TXT

cat >scripts/errors_by.sh <<'SH'
#!/usr/bin/env bash
# Count checkout errors in logs/checkout.log grouped by one field, for example tenant or release.
set -euo pipefail
field=${1:?usage: scripts/errors_by.sh FIELD}
grep 'status=5' logs/checkout.log | grep -o "${field}=[^ ]*" | sort | uniq -c | sort -rn
SH
chmod +x scripts/errors_by.sh

cat >notes/incident.md <<'MD'
# Checkout error spike, 2026-10-18

Checkout errors rose sharply on 2026-10-18 between 13:30 and 15:30 UTC. Every error was an HTTP 502
from payments-gateway, and the previous day had none.

Likely cause: an outage at the payments provider.

Next step: open a ticket with the payments provider and ask for their incident report.

Source: logs/summary.txt
MD
