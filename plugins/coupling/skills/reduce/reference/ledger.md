# The coupling ledger

The durable artifact that makes runs iterative. Location resolves through this plugin's
topic-docs binding (`../../../reference/topic-docs.md`): memory tier, default
`.work/<topic-slug>/coupling-ledger.md`, never committed. One file per topic slice, updated
in place — statuses inside it, not filenames, carry run-to-run history.

## File shape

```markdown
# Coupling ledger — <scope description>

- updated: <ISO-8601 UTC of the last write>
- scope: <the resolved scope of the most recent scan>

## <finding title — short, edge-first>

- status: proposed | applied | deferred | routed | rejected
- altitude: docs | code | app | repo
- edge: <A> --(<kind>, via <mechanism>)--> <B>
- strength: <ladder rung or connascence form>
- degree: <how many sites participate>
- locality: <same file | same module | cross-module | cross-app | cross-repo>
- volatility: <evidence that the depended-on side changes — commits, co-change pairs>
- evidence: <the concrete reproducible observation, file paths included>
- evidence-verified: <true only once phase C reproduced this observation>
- lane: apply | route
- remediation: <catalog entry name from remediations.md>
- outcome: <commit/PR/tracker/handoff reference once status leaves proposed>
- rejected-reason: <only when status is rejected and the reason is load-bearing>
```

`evidence` is the observation (what was seen, where); the narrative interpretation lives in
the title and remediation fields. `evidence-verified` records that phase C actually
reproduced *this* observation, so no downstream consumer ever reads a raw scan claim as a
verified one.

## Status lifecycle

- `proposed` — verified finding awaiting capacity. The next run's apply lane draws from
  these first, before scanning for new ones.
- `applied` — reduction landed and the batch verification passed; `outcome` names the
  commit or PR.
- `deferred` — apply lane but over this run's budget, or blocked by a soft exclusion;
  carries what unblocks it.
- `routed` — route lane, handed off; `outcome` names the design session, tracker item, or
  `/architecture:improve` candidate it became.
- `rejected` — deliberately not pursued (not-a-finding on closer look, counterweight won,
  consumer standards sanction the coupling). Keep these: they stop the next run from
  re-proposing the same edge.

## Re-run semantics

- **Same slug + existing file = resume.** Read the ledger before scanning; `proposed` and
  `deferred` entries are the starting backlog.
- **A re-scan writes what it currently finds; it never replays.** Re-check each open
  entry's evidence against the present tree: still reproducible → keep and re-rank; gone
  (fixed by other work, artifact deleted) → close it with a one-line outcome. Never re-emit
  an entry from memory of a previous run.
- **New findings merge by edge.** Two findings with the same edge and mechanism are the
  same entry — update it rather than appending a near-duplicate.
- **`rejected` is sticky.** Do not re-propose a rejected edge unless its evidence has
  materially changed; note the change when reopening.
