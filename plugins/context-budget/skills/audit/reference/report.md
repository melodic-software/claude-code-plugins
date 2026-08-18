# Report contract

The audit's default deliverable: what the report must contain, in what order, and the framing
rules that keep it honest. The report is read-only and is the durable asset — the fix path, when
it exists, is a separate explicitly-invoked override.

## Framing: smart zone, not dollars

The report leads with **reclaimed reasoning space** — the share of the context window the fixed
payload occupies and what measured trims would return to the model's working room. Cost per
million tokens is never the lead and never a required line. When the `context-guard` plugin is
installed, its zone vocabulary (smart/acceptable/dumb bands) may frame the headline; absent it,
report the payload as a percentage of the measured window (`totalTokens` / `maxTokens` in sdk
mode; the displayed fraction in cli-parse mode).

## Section order

1. **Stamp.** Binary path and version, measurement mode and precision, `sessionKind: headless`,
   the session model, the working directory measured from, and the UTC timestamp. On a cloud or
   container surface, one added sentence: these numbers describe this container's binary and
   settings, not the operator's machine.
2. **Headline.** Fixed payload as tokens and as a share of the window; one sentence of smart-zone
   framing. The deferred pool is stated beside it as *recurring request weight outside the
   window* — the dual-ledger sentence, exactly once.
3. **Category totals.** The measured category table from the baseline snapshot, as measured —
   never reconciled to any external figure, never supplemented from memory.
4. **Ranked per-tool attribution.** From the attribution record: one row per measured tool —
   `savedTokens`, split into `prefixDelta` / `deferredDelta`, with the `comparable` flag. Rows
   the engine marked incomparable appear with their reason instead of their numbers. If the
   additivity check ran, state its verdict in one line. Unmeasured tools are listed as
   unmeasured, not omitted — silence reads as "measured zero".
5. **Lever findings.** One entry per applicable catalogue lever
   ([`levers.json`](levers.json)): current detected state, honesty category (with the condition's
   measured resolution where the row has one), the measured or measurable delta, the exact
   emitted config, and the official citation. Grouped by category, `removes-weight` first.
   Postures bind: `never-recommend` rows appear under a "priced, not recommended" heading;
   `report-only` vendor weight closes the group as the honest floor.
6. **Routes.** The catalogue's route-outs (`/doctor` for usage-based removal — operator-run;
   memory files, hooks, live occupancy to their owners), each in one line.
7. **Degradations and caveats.** Every `caveats[]` entry from the records used, plus anything the
   engine could not measure and why. An audit that hit rung 3 reports the structured error's
   remediation here and stops claiming numbers it does not have.

## Rules

- **Nothing appears that was not measured this audit** (or explicitly labeled as unmeasured /
  a route-out). No figure from documentation, training data, this plugin's own development
  history, or a previous audit enters the report body; previous audits live in the ledger
  section, labeled with their own stamps.
- **Zeros are findings.** A lever that measured zero is reported with its zero and the category
  that explains it.
- **Precision is carried, not dropped.** `display-rounded` numbers are presented as approximate
  (`~`); exact integers plain. Never mix the two in one comparison.
- **The report is persisted** to `<data-dir>/reports/<UTC-timestamp>-audit.md` — one file per
  run, never overwriting an earlier report — and the ledger's latest rows are summarized at the
  end when any exist (each with its own stamp).

## What the report never does

- Recommend a lever whose category is undetermined for this configuration.
- Present a deferral as a request-weight saving, or merge the two System tools buckets.
- Reconcile its numbers to any external source's arithmetic — a mismatch with someone else's
  table is reported as this machine's measurement, full stop.
- Apply anything. Emitted config is printed for the operator; the measure-toggle-remeasure loop
  verifies whatever they choose to apply.
