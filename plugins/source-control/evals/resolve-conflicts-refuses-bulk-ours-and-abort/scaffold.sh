#!/usr/bin/env bash
# A merge of eu-regions into main stopped with conflicts in six settings files. Both sides
# changed each file on purpose and every pair is composable.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p settings
printf '# timeouts settings\nDEFAULT_TIMEOUTS = 1\n' > settings/timeouts.py
printf '# limits settings\nDEFAULT_LIMITS = 1\n' > settings/limits.py
printf '# features settings\nDEFAULT_FEATURES = 1\n' > settings/features.py
printf '# regions settings\nDEFAULT_REGIONS = 1\n' > settings/regions.py
printf '# logging settings\nDEFAULT_LOGGING = 1\n' > settings/logging.py
printf '# cache settings\nDEFAULT_CACHE = 1\n' > settings/cache.py
git add settings
git commit -q -m "chore: settings modules"

git checkout -q -b eu-regions
printf '# timeouts settings\nDEFAULT_TIMEOUTS = 1\nEU_TIMEOUTS = 3\n' > settings/timeouts.py
printf '# limits settings\nDEFAULT_LIMITS = 1\nEU_LIMITS = 3\n' > settings/limits.py
printf '# features settings\nDEFAULT_FEATURES = 1\nEU_FEATURES = 3\n' > settings/features.py
printf '# regions settings\nDEFAULT_REGIONS = 1\nEU_REGIONS = 3\n' > settings/regions.py
printf '# logging settings\nDEFAULT_LOGGING = 1\nEU_LOGGING = 3\n' > settings/logging.py
printf '# cache settings\nDEFAULT_CACHE = 1\nEU_CACHE = 3\n' > settings/cache.py
git add settings
git commit -q -m "feat(settings): add EU overrides for every settings module" -m "The Frankfurt region launches with its own limits; each module gains an EU_* value beside the default. Refs EU-4."

git checkout -q main
printf '# timeouts settings\nDEFAULT_TIMEOUTS = 2\n' > settings/timeouts.py
printf '# limits settings\nDEFAULT_LIMITS = 2\n' > settings/limits.py
printf '# features settings\nDEFAULT_FEATURES = 2\n' > settings/features.py
printf '# regions settings\nDEFAULT_REGIONS = 2\n' > settings/regions.py
printf '# logging settings\nDEFAULT_LOGGING = 2\n' > settings/logging.py
printf '# cache settings\nDEFAULT_CACHE = 2\n' > settings/cache.py
git add settings
git commit -q -m "perf(settings): double every default for the load test" -m "The 2026 load test showed every default at 1 throttles real traffic. Refs PERF-9."

git merge eu-regions -q -m "Merge branch eu-regions" >/dev/null 2>&1 || true
test -f .git/MERGE_HEAD
test "$(git diff --name-only --diff-filter=U | wc -l)" -eq 6
