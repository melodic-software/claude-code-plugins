# disconnected: built-but-unwired capability scan (Tier 0, evidence rung 3)

Run this scan on every invocation, before proposing any net-new build, whether or not the prompt
asks about existing code. A capability that is already built but never wired up is often the
cheapest candidate in the target: the work left is wiring, not building.

Every probe runs against the target root (SKILL.md "Repo as parameter") and inside the target
scope, when one was named. On a whole-repo scan, grep the symbols of the highest-churn files
(hotspots.md) and the stores and flags the code names, and record a `gap:` line for the rest.

## The three shapes

| Shape | How to find it | Disconnected when |
|---|---|---|
| Defined but unreferenced code | When `code-tidying:audit-dead-code` ran as a scan input (SKILL.md "Lane delegation as scan input"), take its dead and uncertain candidates. Otherwise list exported or imported symbols (`export`, `module.exports`, `import`, `require`, `def`, `pub fn`, `public`) and grep each name across the scope | The symbol is imported but never called, or exported and never imported, outside its own file. A symbol whose only callers are tests is disconnected; say so in the citation |
| Written but unread store | List the stores the code writes: tables (`INSERT INTO`, `UPDATE`), files, cache or queue keys, metrics, events. Grep each name for a read (`SELECT ... FROM`, `JOIN`, a reader call, a consumer) | Writes exist and no read does |
| Dark feature flag | Read the flag config (`flags.json`, settings files, `.env.example`) for flags that are off or default to off, then grep each flag name for the code it gates. In other `.env*` files, grep for the flag key only and never quote a value | The flag is off and is the only way to reach a route, job or UI the code already holds |

Entry points are referenced from outside the scope, so mark them uncertain rather than
disconnected: a package's `main` or `exports`, a framework-registered handler, a public library
API. Generated files count as neither callers nor candidates. A target that itself sits under a
`test` or `fixtures` path is scanned as ordinary code.

## Citation shape

Put the name and its state on one line, so the reader sees both together:

- `formatInvoicePdf` (`src/billing/routes.ts:2`): imported, never called, so `src/billing/pdf.ts` is unused (rung 3)
- `audit_log` table (`db/schema.sql:12`): written by `src/jobs/sync.js:40`, never read: no `SELECT` or join names it (rung 3)
- `newCheckout` flag (`config/flags.json:4`): `false`, gates `POST /checkout/v2` (rung 3)

A grep finds no reader only within what it searched, so the confidence is the rung 3 label from
ranking.md. Name the paths you searched, and record a `gap:` line when part of the target could
not be searched, such as a dynamic dispatch table or a reader in another repository.

## Ranking

Group shapes that belong to one capability (an unused exporter, the flag that hides its route,
the audit table that route writes) into one candidate: "wire up the existing <capability>". When
another candidate, a plan or the prompt proposes building the same capability new, rank the
wiring candidate ahead of it: the value is the same and the job is smaller. State that comparison
in the value-to-effort rationale. This ordering holds between those two candidates only; the
instrument-first rule (ranking.md) still takes rank 1 when it applies. Each disconnected shape
that matches no capability is its own candidate: wire it up or delete it, with the choice left to
the interview.
