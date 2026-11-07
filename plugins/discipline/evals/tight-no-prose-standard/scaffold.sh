#!/usr/bin/env bash
# Seed a padded support doc and no prose-terseness standard.
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
cat >docs/support.md <<'MD'
# Support hours

It is worth noting that, basically, our support team is available from 08:00 to 18:00 UTC on
weekdays. As previously mentioned, in order to reach the on-call engineer outside those hours, you
should page through the incident tool, and you should only do so for a P1 incident.
MD
