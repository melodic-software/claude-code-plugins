# Research snapshot, 2026-09-19

A frozen copy of the verified research report on Claude Code mods: the hub
[`research.md`](research.md) and its ten sidecars. Nothing here is updated in place. A later run
writes a new dated folder beside this one.

## What it was verified against

- Claude Code **2.1.278**.
- `anthropics/claude-code` `mods/` at commit **`92ec78f2`**.
- Synthesis faithfulness: **141 of 149 claims faithful**, 8 corrected (7 graded
  stronger-than-evidence, 1 wrong). No confidence a verifier lowered was raised.

Every claim carries its basis label: `OBSERVED`, `SOURCE`, `BINARY`, `STAFF`, `COMMUNITY`,
`INFERRED`. Read the label before reusing a claim.

## What is not here

The raw per-lane research directories (`repo-primary/`, `official-docs-changelog/`, `x-threads/`,
`community-falsification/`, `surfaces-desktop/`, `plugins-repo-explore/`, `architecture-pdf/`) and
the three decision-input documents beside the hub (`DEVILS-ADVOCATE.md`, `BLINDSPOTS.md`,
`VERIFICATION.md`) were machine-local and are not in this repository. Links to them would not
resolve, so the hub's references to them were rewritten to plain text naming the lane or the file.
The external sources those lanes cite are indexed in [sources.md](../sources.md).

Links between the hub and its sidecars resolve inside this folder.

Two deviations from a byte-exact copy, both mechanical: the hub's non-resolving links were flattened
to plain text as described above, and three sidecars carry a leading
`<!-- markdownlint-disable MD049 -->` because verbatim staff quotes inside them use underscore
emphasis. No claim text was changed.
