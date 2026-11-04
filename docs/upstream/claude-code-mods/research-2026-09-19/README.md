# Research snapshot, 2026-09-19

A dated snapshot of the verified research report on Claude Code mods: the hub
[`research.md`](research.md) and its ten sidecars. Its claims are not updated in place: a later run
writes a new dated folder beside this one. The only edits since capture are the deviations
listed at the end.

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

Three deviations from a byte-exact copy: the hub's non-resolving links were flattened to plain
text as described above; em dashes in the snapshot's own prose were replaced with other
punctuation so the folder could join `scripts/em-dash-purged-paths.txt`; and every quote of staff,
community or upstream text (the `mods/` README and declarations, binary strings, CLI and debug
output, docs pages, issue comments and posts) was rewritten in our own words to meet
[what a row may describe](../../../contracts/upstream-drift/README.md#what-a-row-may-describe).
Each restatement keeps its speaker, date, comment id, basis label and confidence; read the wording
at the cited source. Short fragments the analysis turns on, of four words or fewer, stay quoted.
Two code blocks stay because they hold only names: the one-line `plugin.json` skeleton in
`research-api-surface.md` and the plugin directory layout in `research-authoring-and-testing.md`.
Quotes of this repository's own text and of the research lanes' wording are kept as written.
