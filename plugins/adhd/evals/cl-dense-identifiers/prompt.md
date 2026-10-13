---
description: "Explicit clarify of a dense three-decision message with Q-numbers keeps every operative term verbatim, back-links each original id, numbers the table rows itself, names what it left out, and closes with the lens line"
tags: [adhd, clarify, outcome, fidelity]
max_turns: 6
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A decision table (or numbered list) with rows 1-3 mapping to Q3, Q4, Q5; operative terms copied verbatim (patch bump, 2.4.1, --force, scripts/migrate_v2.sh, config/retry.yaml, 48-hour, 800 ms); each Basis carried (CHANGELOG.md:41, judgment, #212); a Left out note naming the docs freeze; a closing line telling the reader to validate against the original."
---

/adhd:clarify Round 3 decisions from the release sync; all three need an answer today.

Q3: Ship the cache-invalidation fix as a patch bump to 2.4.1 rather than a minor (2.5.0), because nothing in the public API changed. Basis: CHANGELOG.md:41 lists no new exports.
Q4: Run scripts/migrate_v2.sh with `--force` on the staging cluster only; production waits until the 48-hour soak finishes clean. The alternative was a dry run first without `--force`. Basis: judgment.
Q5: Raise the retry ceiling in config/retry.yaml from 3 to 7, unless p99 latency goes over the 800 ms budget, in which case keep 3. Basis: load test run #212.

Side note: the docs freeze starts Friday, which blocks the Q3 release notes but needs no decision from you.
