# Claude Code mods: the deferred verdict and its evidence trail

The verdict is **Defer**, recorded in
[ADR 0035](../../adr/0035-defer-claude-code-mods-with-five-go-criteria.md) and as the mods row under
"Recorded gate runs" in [docs/plugin-philosophy.md](../../plugin-philosophy.md). This folder holds
the trail behind it.

## Reading order

1. [sources.md](sources.md) — the single cited index: every external link, what it establishes,
   when it was fetched, and which document uses it. Start here if the question is "what about
   mods?"; its first section says what to read and in what order.
2. [go-no-go.md](go-no-go.md) — the runbook. The five go criteria, each with an exact command and
   its 2026-09-19 output. Criteria 1 to 3 are the quick check for a Claude Code pin bump; the full
   run is on demand.
3. [experiments.md](experiments.md) — the full run's other half: experiments E1 to E6 as rerunnable
   procedures with their 2026-09-19 baselines, and the probes that stayed open. Criterion 3 cannot
   pass without E2.
4. [research-2026-09-19/](research-2026-09-19/) — a frozen snapshot of the verified research report
   (hub plus ten sidecars), with the versions it was verified against.
