# coupling

A Claude Code plugin for iteratively reducing coupling — in any repository, at any altitude.
One skill, one standing question: which dependency here transmits the most unnecessary
change, and what is the smallest mechanism that stops the transmission? Each run takes one
verified, budgeted bite and records the rest, so coupling goes down monotonically across
runs instead of one heroic rewrite.

| Skill | What it does |
|---|---|
| `/coupling:reduce` | Scan for change-transmitting coupling, verify findings, apply a safe budgeted batch, route structural candidates, and resume from a durable ledger |

## The model

Findings are typed, not vibes-based: every one is a directed edge
(`A --(kind, via mechanism)--> B`) classified on the structured-design strength ladder
(content, common, external, control, stamp, data, message) and the connascence axes
(strength × degree × locality), then weighted by volatility — coupling to something that
never changes costs nothing, so co-change evidence from version-control history outranks
static impressions. The same model covers four altitudes: documents (duplicated facts, deep
references), code modules (internals reaching, dependency direction), applications (shared
databases, implicit contracts, temporal coupling), and repositories (copied content,
depending on another repo's internals instead of its releases).

Two lanes keep the skill honest:

- **Apply lane** — mechanical, contained, behavior-preserving reductions, applied under a
  scope budget and verified against the project's own build and tests.
- **Route lane** — cross-file and architectural findings are surfaced and routed to humans
  and design tooling, never auto-applied.

The remediation catalog carries an explicit counterweight per mechanism: decoupling's own
failure mode is speculative abstraction — an interface with one implementation, an event bus
for a one-to-one call — and the skill is built to refuse it.

```shell
/coupling:reduce                 # full pass over an inferred scope
/coupling:reduce src/billing     # narrowed to a path
/coupling:reduce dry-run docs    # findings and ledger only, no edits
/coupling:reduce status          # what is open, applied, routed, and recommended next
```

## Consumer conventions

- **Your standards win.** At orientation the skill discovers the consuming repo's own
  review criteria and engineering conventions (a review-criteria file, a conventions or
  standards directory, CLAUDE.md rules) and aligns finding vocabulary and severity with
  them; the bundled model is the fallback, never an override.
- **Ledger placement** follows the marketplace topic-docs convention — memory tier, default
  `.work/<topic-slug>/coupling-ledger.md`, never committed. Deltas in
  [`reference/topic-docs.md`](reference/topic-docs.md).
- **Optional collaborators** (`architecture`, `work-items`, `toolchain`, `source-control`,
  `docs-hygiene`) are presence-gated with documented fallbacks; the skill works alone.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install coupling@melodic-software
```

## License

MIT
