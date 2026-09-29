# changelog: native-surface drift after an apply

Phase 7 of `apply`. After the release is integrated, re-read what Claude Code itself ships, say
what moved since the last run, and file a work item for each drift that needs a human. Every name
comes from the extraction and the overlap store; this file names no surface.

## Run

`<ws>` is `<memory_dir>/claude-code-changelog/<range>/native-drift/` (the working set in
[decisions.md](decisions.md), "Persistence"). `<prev>` is
`<memory_dir>/claude-code-changelog/native-surface-summary.json`, the previous run's summary; it
sits outside any range because it describes the last extraction, not a release range. `<store>` is
the overlap store, default `docs/native-surfaces/records.json`. One command per Bash call; record
each exit code.

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py" --self-check
python3 "${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py" --binary-only --docs --out <ws>/inventory.json
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-native-overlap/scripts/overlap.py" detect --inventory <ws>/inventory.json --store <store> --out <ws>/detect.json
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-native-overlap/scripts/overlap.py" self-check --store <store>
python3 "${CLAUDE_PLUGIN_ROOT}/skills/changelog/scripts/native_drift.py" summarize --inventory <ws>/inventory.json --detect <ws>/detect.json --out <ws>/summary.json
python3 "${CLAUDE_PLUGIN_ROOT}/skills/changelog/scripts/native_drift.py" diff --current <ws>/summary.json --previous <prev> --store <store> --detect <ws>/detect.json --self-check-exit <inventory self-check exit> --out <ws>/drift.json
```

The self-check and `detect` exit `0` ok, `1` broken, `3` degraded; `3` is a passing run. When
`detect` exits `1` with no output file, run `summarize` without `--detect`. `native_drift.py` exits
`2` only on a missing or malformed input. After the report and the filing, copy
`<ws>/summary.json` over `<prev>`, unless the inventory self-check exited `1`: a broken extraction
never becomes the baseline. Its suite is `scripts/test_native_drift.py`, wrapped by
`scripts/native_drift.test.sh`.

## Report

From `<ws>/drift.json`, one section each, empty ones stated as "none":

- **Inventory**: the self-check verdict, `cli_version` against `validated_against`, and the
  overlap self-check's exit.
- **Surfaces**: `surface_changes` added, removed, renamed (with the alias or description match that
  paired them), reclassified. `baseline: true` means no previous summary: say that no surface diff
  exists yet and that the next run has one.
- **Invocability and markers**: `surface_changes.invocability` and `.markers`.
- **Docs cross-check**: `docs_changes`, the block's status and each name whose status moved.
- **Overlap**: `new_candidates`, and each `fired_triggers` row with its reasons.
  `rows_not_evaluable` counts store rows this extraction cannot judge (a live-roster or
  upstream-source observation, a name no lane holds, a broken lane).

## Items

`items` lists what to file, one per entry, each with a stable key
`native-drift:<kind>:<surface>:<component>`:

| Kind | Filed when | Title |
|---|---|---|
| `candidate` | A `detect` candidate new since `<prev>`, at or over its threshold, re-derivable, with no store row | `claude-ops/audit-native-overlap: rule on <surface> overlap with <component>` |
| `recheck` | A store row's trigger fired: its surface was removed or renamed since `<prev>`, its class changed, or its markers (hidden, gated, model-invocation-disabled) differ from the row | `claude-ops/audit-native-overlap: recheck <surface> row for <component>` |
| `revalidate` | The self-check is degraded only because the CLI moved past `VALIDATED_AGAINST`, every lane is ok, and no surface changed since `<prev>` | `claude-ops/inventory: revalidate the extraction against Claude Code <version>` |
| `inventory-degraded`, `inventory-broken` | Any other degraded or broken self-check, including a baseline run | `claude-ops/inventory: extraction <status> on Claude Code <version>` |

A `revalidate` body says the proposal plainly: re-run the inventory evals against the new build,
then bump `VALIDATED_AGAINST`; nothing is known to be wrong. Every body carries the item's `facts`,
a line `Drift key: <key>`, and a line `Filed by /claude-ops:changelog apply (native drift, <range>)`.
A candidate body also says that `/claude-ops:audit-native-overlap` rules on it and a human writes
the store row.

## Filing

File through `/work-items:track`, invoked with the Skill tool, when the `work-items` plugin is
installed and a tracker binding resolves; never call a provider CLI directly. Otherwise print
"filing skipped: <reason>; report-only" and stop at the report.

1. **Dedupe by key.** For each item, invoke `/work-items:track search` with the quoted key. A hit
   counts only when its body contains the key verbatim; confirm the search ran against the bound
   tracker before trusting an empty result. An open hit: skip, and report "already open #N". For a
   `candidate`, a hit closed as not planned is its **dismissal**: skip. Any other closed hit: file
   anew and link it.
2. **File** each remaining item through `/work-items:track add` with the title and body above. It
   applies the raw-intake floor `needs-triage` from the live label set; the filer never
   self-triages.
3. **Label** each item `native-drift` when that exact label is in the live set; ask `track add` for
   it as an extra label. Otherwise file without it and say so once. The label is a filter; the key
   is the dedupe, so a missing label never causes a duplicate.

**Who approves.** The run is interactive unless its caller declares it unattended (a loop, a
routine, or a lane directive that authorizes tracker filing). Interactive: print the count and the
list (kind, key, title), then file on one confirmation for the batch, which is `track add`'s
authorization gate for model-initiated filing. Unattended: print the count and file without
asking, with the AI disclaimer `track add` and the dogfood contract require.

## Recorded facts

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| `work-items` defines no filing-posture key, so the only filing gate is `track add`'s authorization gate (`filing_posture` belongs to the `bugs` plugin and governs `/bugs:scan` alone) | `git grep filing_posture` hits only `plugins/bugs/` and `.claude/bugs.md`; `plugins/work-items/skills/track/actions/add.md`, "Authorization gate" | 2026-09-29 | `work-items` gains a filing-posture or autonomy key; this step then reads it and never exceeds it |
| `track add` has no flag for an arbitrary meta label, so `native-drift` is requested in the invocation, not passed as a flag | `plugins/work-items/skills/track/actions/add.md`, "Flags" | 2026-09-29 | `track add` gains a label flag |
| `native-drift` is not in this repository's live label set; labels here are managed as code (`governance: managed`), so the label is added there, never created by a run | `gh label list` on melodic-software/claude-code-plugins | 2026-09-29 | The label appears in `gh label list`, or the label-as-code owner changes |
