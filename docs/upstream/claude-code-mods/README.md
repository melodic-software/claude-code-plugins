# Claude Code mods: the verdict and its evidence trail

The verdict is **Adopt, scoped**, recorded in
[ADR 0046](../../adr/0046-adopt-claude-code-mods-within-five-scope-rules.md) and as the mods row
under "Recorded gate runs" in [docs/plugin-philosophy.md](../../plugin-philosophy.md). ADR 0046
superseded the 2026-09-19 Defer in
[ADR 0035](../../adr/0035-defer-claude-code-mods-with-five-go-criteria.md). This folder holds the
trail behind both.

## Reading order

1. [sources.md](sources.md): the single cited index: every external link, what it establishes,
   when it was fetched, and which document uses it. Start here if the question is "what about
   mods?"; its first section says what to read and in what order.
2. [go-no-go.md](go-no-go.md): the runbook. The five criteria, each with an exact command, the
   2026-09-19 baseline, and the 2026-10-02 run record. Criteria 1 to 3 and the replaced criterion 5
   are the quick check for a Claude Code pin bump; the full run is on demand.
3. [experiments.md](experiments.md): the full run's other half: experiments E1 to E6 with their
   2026-09-19 baselines, E7 and E8 from 2026-10-02, and the probes that stayed open. Criterion 3
   cannot pass without E2 or E8.
4. [research-2026-09-19/](research-2026-09-19/): a frozen snapshot of the verified research report
   (hub plus ten sidecars), with the versions it was verified against.
