#!/usr/bin/env bash
# Seed two wordy docs that both state the same refund policy.
set -euo pipefail
set -o noclobber

# Write only inside the run's temporary home, never the real one.
here="$(pwd -P)"
real="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6 || true)"
home="$(cd "${HOME:-/}" && pwd -P)"
if [[ -z "${real}" || "${home}" == "$(cd "${real}" 2>/dev/null && pwd -P)" ]]; then
  echo "refusing to scaffold under HOME=${HOME:-unset}: it is the real home or the real home is unknown" >&2
  exit 3
fi
case "${here}/" in
"${home}/" | /) echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
"${home}/"*) ;;
*) echo "refusing to scaffold in ${here}: outside HOME=${home}" >&2 && exit 3 ;;
esac

mkdir -p docs
cat >docs/refunds.md <<'MD'
# Refunds

It is worth noting that, basically, refunds are issued within 14 days of purchase, and in order to
keep things simple they always go back to the original payment method. As previously mentioned,
refunds are never issued as store credit.
MD
cat >docs/faq.md <<'MD'
# FAQ

## Can I get a refund?

In order to answer this, it is important to note that refunds are basically issued within 14 days of
purchase, to the original payment method, and never as store credit.
MD
