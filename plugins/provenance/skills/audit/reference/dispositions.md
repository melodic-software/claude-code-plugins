# Dispositions: what `fix` is allowed to do, and what guards each edit

Read this only inside `fix` or `sweep`. The default `audit` action never edits, so it never
needs this file.

Only `fingerprint-confirmed` findings are fix-eligible. Everything else — a judged-similar
passage, a suspected paraphrase, a `not-found` outcome, a split judge panel, a vetoed finding —
reaches the human report and stops there. A finding that is not fix-eligible is not "a fix
awaiting approval"; it is a report.

## The five dispositions

Three edit. Two do not.

| Disposition | What it does | When it is right |
|---|---|---|
| `convert-to-pointer` | Replaces the restatement with a link to the source | The reader can follow the link at the moment they need the fact |
| `trim-to-citation` | Keeps a short quoted excerpt, attributed, and drops the rest | A specific span is worth quoting verbatim and the surrounding restatement is not |
| `condense-to-stamped-record` | Condenses to a four-part record: claim, basis URL, as-of date, recheck trigger | The surface must state the fact to function even when the source is unreachable |
| `leave-with-reason` | Records why the passage stays | A carve-out applies, or a review veto fired, or the human decided |
| `neutral-not-found` | Records that no source was identified | Budgets were exhausted; every searched surface is named |

## Choosing between the three edits

The question is not "how similar is this to the source" — the fingerprint already answered that.
The question is **what a reader loses if the local text goes away**.

Ask them in this order:

1. **Does the surface have to work when the source is unreachable?** If yes, it condenses to a
   stamped record. It never takes a bare `convert-to-pointer`, whatever the containment score.
   This is the offline-load-bearing constraint and it is absolute — a pointer in a surface that
   must function offline is a regression dressed as a fix. Surfaces that qualify: anything a
   subagent reads mid-dispatch, anything that runs in a sandbox without network, anything whose
   whole purpose is to answer without a fetch.
2. **Is a specific span worth quoting verbatim?** An exact error string, a precise limit, a term
   of art whose wording is the fact. Then `trim-to-citation`: keep that span quoted and
   attributed, drop the restatement around it.
3. **Otherwise, `convert-to-pointer`.** Cite the source and let the reader fetch it. This is the
   preferred end state and the one that removes the drift risk rather than dating it.

**Read frequency and fetch cost weigh here, and only here.** A passage read on every run of a
hot path is a stronger candidate for condensing than for pointing, because the fetch cost is
paid repeatedly. That is a disposition argument. It is never an allowance argument: "this is
read often" does not make a copy acceptable, it makes a stamped record the right repair.

## The four-part record, when condensing

A stamped record carries all four parts or it is not one:

1. **The claim** — what exactly is being asserted, narrow enough to check.
2. **The basis** — the specific URL, with anchor where one exists. "Verified" with no stated
   basis is not re-checkable.
3. **The as-of date** — when the derivation happened.
4. **The recheck trigger** — the observable event that obliges re-deriving it.

A date alone is not a trigger. "Recheck periodically" is not a trigger. A trigger names an event
someone could notice: a major version bump, a named page changing, a deprecation landing. If you
cannot name one, that is a signal the passage wanted `convert-to-pointer` instead — a claim
nobody can say when to re-check is a claim nobody will re-check.

Write the record so `check-stamps.sh` can parse it: an ISO 8601 date (`YYYY-MM-DD`) within a
short span of a stamp keyword. A month-name or bare-year date is honest prose but the checker
declines it, and a stamp the checker cannot read is a stamp that never expires.

## Guards, all of which must pass before an edit is kept

Per file, in this order. Any guard that fails reverts that file's edits and routes the finding
to the human with the guard's own reason.

1. **Pointer liveness, at edit time.** Every URL the edit introduces or leaves behind is fetched
   and identity-checked (see `reference/source-fetch.md`). A pointer to a dead or aliased target
   is worse than the copy it replaced: the copy was at least readable. A target that fails the
   check does not get pointed at.
2. **The semantic-diff guard, fresh-context and blind.** A separate agent reads the before and
   after **without the rewrite rationale** and reports what a reader can no longer learn from
   the after. Withholding the rationale is the whole mechanism: an agent told why the edit was
   made will reliably find that the edit achieved it. It flags semantic loss, new ambiguity, and
   quote damage. Any flag routes to the human rather than being argued down.
3. **The edit stays inside the finding's span.** `fingerprint-confirmed` findings carry the
   module's exact matched span, which is what makes this checkable. An edit reaching outside it
   is out of scope for this finding, however good the idea.
4. **Carve-outs re-checked at edit time.** A passage inside a quotation context, a conforming
   stamped record, or a vendored tree is not edited, even if a finding reached this point.

## The demotion path when a pointer later dies

A pointer that was live at edit time can die later. That is a foreseen state with a defined
repair, not a defect in the disposition.

- A dead target demotes to a **stamped record**, if the fact is still knowable and still needed:
  claim, the now-dead basis URL marked as such, the original as-of date, and a trigger naming
  the recovery of a live basis.
- Where an archived snapshot of the original page exists, demote instead to an
  **archived-snapshot citation**, pointing at the archive and saying it is an archive.
- Never silently re-expand the pointer back into a copy. The copy is what the fix removed, and
  restoring it discards the record of why.

Wiring a repository's link-check lane to notice dead pointers is consuming-repo integration, not
plugin machinery. This file owns the repair; the consuming repo owns the trigger.

## Sweep closure

Under `sweep`, one tracked file at a time: apply the verdicts, run every guard, close the file,
move on. **A file is closed when every finding in it carries a disposition or an explicit
neutral outcome** — never when the interesting ones are done. Record each closure in the sweep
ledger with its dispositions and guard outcomes, so an interrupted sweep resumes without
re-deciding files it already closed, and so the closure count is a fact rather than a memory.
