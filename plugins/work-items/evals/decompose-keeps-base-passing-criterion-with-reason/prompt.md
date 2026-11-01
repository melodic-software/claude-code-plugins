---
description: "A criterion that already passes at the base commit and is kept at Step 3 is written into the item's Done when with its one-line reason"
tags: [decompose, acceptance-criteria]
runs: 3
max_turns: 20
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Writes the Done when section with AC1 as a plain check and AC2 on its own line ending with a note that it passes at base and is kept, with the user's reason that the change must not break the help output"
---

Load /work-items:decompose and write the `## Done when` section of the one item it would publish
for this breakdown. Show only that section. Publish nothing.

The item carries two criteria:

- AC1: `refunds export --month 2026-09` writes only September refunds.
- AC2: `refunds export --help` exits 0.

The base-commit check flagged AC2: `refunds export --help` already exits 0 at the base commit. At
Step 3 the user chose to keep AC2, with this reason: the new flag must not break the help output.
