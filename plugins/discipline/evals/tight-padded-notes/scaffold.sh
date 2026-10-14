#!/usr/bin/env bash
# Seed padded deploy notes (with three rules that must survive) and a verbose helper.
set -euo pipefail

mkdir -p docs src
cat >docs/deploy-notes.md <<'MD'
# Deploy notes

It is worth noting that, basically, in order to deploy the service safely, you should run the
database migrations only after the nightly backup completes, and you should never run them on
Fridays. As previously mentioned above, the cluster must always keep at least 3 replicas running
during the rollout, because dropping below that number can cause request failures for customers.

In order to roll back, it is important to note that you basically just need to redeploy the
previous image tag, which is something that can be done with the deploy command.
MD
cat >src/util.py <<'PY'
def normalize_names(names, legacy_mode=False):
    """Return the names stripped and lower-cased, skipping blanks."""
    if not isinstance(names, list):
        raise TypeError("names must be a list")
    result = []
    for name in names:
        cleaned = name.strip().lower()
        if cleaned != "":
            result.append(cleaned)
        else:
            pass
    return result
PY
