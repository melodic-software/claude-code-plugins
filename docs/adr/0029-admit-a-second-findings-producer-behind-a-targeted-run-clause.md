# Admit a second findings producer behind a targeted-run clause

- Status: accepted
- Date: 2026-09-05

## Decision

The `overengineering` findings artifact moves to `schema: 2` so that a second producer can write into
the same file, and the same suppression record, without damaging what the first one wrote. Decided
while adding `/overengineering:justify` (#3776), a pointed lane that judges non-enforcement artifacts
against the plugin's existing evidence-earned-keep method.

The artifact was written for one producer. `overengineering:audit` walks the whole enforcement
surface, so its merge rules could assume that a layer absent from a run had been examined and found
clean. Rule 3 closes a prior finding whose layer was walked and whose id is absent. A pointed run
examines one target, so under those rules it would close every finding in that target's layer as a
side effect of not having looked at them.

Five things carry the change:

- **A targeted-run clause placed AHEAD of the numbered merge rules and governing them.** It reaches
  rules 1 to 4 and rule 6, carries everything not covered forward untouched under rule 4, and stops
  a targeted run rewriting the run-level `Evidence availability`,
  `Suppressed`, and `Closed since last run` sections or re-disposing suppression entries it never
  examined. **The quantifier splits by what the rule does**: closing a finding (rule 3) takes every
  site in `targets`, because partial coverage must never retire something the run did not fully
  examine; refreshing a verdict or a suppression disposition (rules 1 and 2) takes any one site,
  because a lane that points at one target at a time would otherwise freeze every finding binding
  two artifacts. Ordering is the mechanism: a clause placed after the rules reads as an exception to them,
  and an exception is what a careless producer skips.

  **The membership test is defined on derived sites, not on a matching string**, and that is the part
  the first draft got wrong. `targets` and `sites` are different value spaces: a target may be a
  `path#heading`, whose site carries the file as its `surface` and the heading's ancestry in its
  `anchor/v1`. Comparing a site's `surface` against a target entry fails in both directions. A
  heading target matches no site at all, so a pointed run cannot write even its own finding; a file
  or directory target matches every site beneath it, so rule 3 closes findings the run never opened,
  which is the single loss the clause exists to prevent. A site is therefore in `targets` when this
  run derived that site from a `targets` entry.

  **The clause's two quantifiers differ on purpose.** Rules 1 and 2 apply to a finding **any** of
  whose sites is in `targets`; rule 3 applies only to one **every** of whose sites is. Rule 3 closes
  a finding, so it must be conservative, since closing on partial coverage retires something the run
  never fully examined. Rules 1 and 2 only refresh one, so they must be permissive: this lane takes
  one target per run, so a finding binding two sites can never have every site in a one-entry
  `targets`, and a restrictive reading would stamp it not re-evaluated on every later run that
  demonstrably did re-evaluate it, with no walk able to rescue it. Unifying them in either direction
  breaks one half.
- **Re-read before write, as a producer obligation on every writer.** Admitting a second producer is
  what makes it load-bearing: a producer merging against a copy loaded earlier in its run drops the
  other's rows, and drops them with no record, because a closure row is written only for a layer the
  run walked and the two producers walk disjoint layers. It belongs in the shared contract rather
  than in either lane's own binding, since neither lane can honour it alone. For the same reason the
  walking lane's `all` layer scope means the ten enforcement layers explicitly: resolved against the
  full fifteen it would record five layers it never walked, and close every pointed finding as a
  deleted artifact.
- **`mode` and `targets` frontmatter**, so a reader can tell a walk from a point without inferring it
  from which findings happen to be present.
- **Five layer values for non-enforcement artifacts** (`decision-records`, `documents`,
  `components`, `dependencies`, `source`), appended rather than inserted, because the enum order is
  the artifact's sort key.
- **`Basis`**, a non-spine field recording whether a verdict is `measured`, `class-inferred`, or
  `unexamined`. Required only on rows a schema-2 run writes, so rows carried forward from schema 1
  stay legal and display as not recorded rather than being backfilled with a guess.

**Consumers were taught the new schema rather than left to infer it.** `realign` presents a
`justify`-producer row with its evidence, its verdict and its owner, and offers no rollback rung: its
ladder is enforcement-shaped, and its rung-1 fallback would leave deletion as the only remaining act
for a lane it has no ladder for. `delta` reports these layers as not walkable rather than not walked,
since no cycle at any scope will compare them. `audit` writes `schema: 2` with `mode: walk`, and both
lanes accept either schema on read.

Alternatives weighed:

- **A second artifact file per producer, rejected.** The suppression record is the reason. Two files
  means two suppression records, and a mechanism suppressed in one is live in the other, so an
  operator's decision to stop hearing about something would depend on which lane asked.
- **Version the whole artifact and migrate schema-1 files, rejected.** Migration would have to invent
  a `Basis` for every carried row, and the honest value for a row written before the field existed is
  "not recorded", which is what carrying it forward already says. A migration that fabricates
  evidence grades is worse than a file with two vintages in it.
- **Let the pointed lane skip the merge rules entirely, rejected.** It would then be unable to close
  its own prior findings, and a lane that can only add rows accretes.

## Consequences

**Discovery mode ships, as an offer, on measured evidence that is poor.** ADR 0003 requires measured
precision before a verification guard earns default-on. The no-target discovery rung emits candidates
over a corpus, so it was measured once on this repository before shipping:

| Measure | Count |
|---|---|
| Distinct paths ever added that still exist | 2692 |
| Ranked candidates, first seen on or before 2026-07-31, two commits or fewer since | 638 |
| After excluding evals, fixtures, tests, schemas, examples | 285 |
| Markdown documents in that filtered set | 146 |
| Reported as cited nowhere outside their own directory | 3 |
| Real, after independent re-derivation | **1** |

The one is `docs/hook-migration-audit.md`, which no file in the repository references under any form.
Both rejections are more instructive than the survivor. `docs/adr/0006-...` is cited twice, but under
the `ADR 0006` form rather than the filename form, caught by this lane's own query-form-variation
rule. `docs/ai-briefing-design.md` is cited by `docs/MIGRATION-PLAYBOOK.md`, and was missed because
the measurement filtered to paths "cited nowhere outside their own directory" while both files sit in
`docs/`. Two of three apparent orphans were citation-search artifacts, in two different ways.

That is why discovery mode ships as an operator-chosen offer and not as an emitter: 1 in 638 does not
clear ADR 0003's bar for anything default-on, and the mode is offered, waited on, never run unasked,
and produces a candidate list rather than findings. It is also why the offer now corroborates before
it presents, checking each ranked path for inbound references repository-wide and dropping the ones
that have any. The measurement is not a footnote to that decision; a 2-in-3 false-positive rate on
the only sample that exists is the decision's whole evidentiary basis, and it is recorded here rather
than in the task's plan because the plan is pruned at merge and this number outlives it.

Age plus low churn has poor precision here for a reason worth keeping: most of the ranked set is
fixtures, evals, and tests, whose low churn is their designed steady state, so their inactivity
returns no information. That is the category error the method's protected classes already name.

**The lane's own limits are recorded where the lane is, not here.**
`plugins/overengineering/context/justification-lane.md`, section 12, carries them, including the one
this measurement produced: a citation search scoped by location misses citations the same way one
scoped by name does.
