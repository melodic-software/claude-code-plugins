# The baseline model

What the delta in [`../SKILL.md`](../SKILL.md) is computed against, how a home with an artifact but
no baseline is bootstrapped, and what the baseline file itself carries. Both failure modes below
are silent, so do not infer this model from the run steps in the hub.

## Contents

- [The load-bearing mechanic: the baseline is the PREVIOUS cycle's post-audit spine](#the-load-bearing-mechanic-the-baseline-is-the-previous-cycles-post-audit-spine)
- [The bootstrap cycle. The one pre-audit capture](#the-bootstrap-cycle-the-one-pre-audit-capture)
- [The spine baseline](#the-spine-baseline)

## The load-bearing mechanic: the baseline is the PREVIOUS cycle's post-audit spine

Two independent things have to be right here, and each fails silently on its own.

**First: a spine must be persisted, because the artifact is rewritten in place on every re-run.** A
re-audit merges into the existing file by stable finding id rather than depositing a timestamped
sibling (`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, "Where it lives" and "Re-run merge
semantics"), and the audit writes **per layer as it walks**, so the prior content begins disappearing
at the first layer, not at the end of the run. There is therefore **no previous artifact left to diff
against after the audit has run**, and this lane can never be "run the audit, then diff the file". A
separately persisted spine is mandatory. That reason is unchanged and still load-bearing.

**Second: the persisted spine has to be captured at the *end* of a cycle, not the start.** A cycle
that captures its baseline from the artifact as it stands at the start of the run captures a file a
human may already have edited. `Status` is exactly that field: realign writes it, a human runs
realign **between** cycles, and the audit only ever writes `OPEN` on a newly-seen id and carries every
other status forward untouched. So a start-of-cycle capture already contains the new status, the
audit carries that same status through, and baseline and post-audit spine agree on `Status` for every
pre-existing finding, the status-change class is dead by construction, in precisely the case it
exists to catch.

The mechanic is therefore:

1. Resolve the home and the branch identity.
2. **Read the stored `spine-baseline.md`, the *previous* cycle's post-audit spine.** That, and
   nothing captured this cycle, is what the comparison measures from.
3. Invoke `overengineering:audit`.
4. Compare **this run's post-audit spine** against the stored baseline.
5. **Capture this run's post-audit spine over the stored baseline**, for the next cycle to compare
   against.

The pre-audit capture survives in exactly one place: **the bootstrap cycle** below, where no stored
baseline exists yet and a pre-audit capture is the only baseline obtainable.

**A maintainer who breaks either half does not get an error, they get a silently useless lane.**
Collapse step 5 into step 2 and the comparison never sees a status change, while every other class
still reports plausibly, so the loss is invisible. Drop the persistence entirely and every cycle
reports "no baseline, this run establishes one" forever and every cycle looks like a first run. Both
failures are invisible from the report, which is why the mechanic is stated here as a contract rather
than left as an implementation detail.

## The bootstrap cycle. The one pre-audit capture

A home can hold a findings artifact and no `spine-baseline.md`: audits were run manually here before
this lane ever ran. That first delta cycle **captures the artifact's spine pre-audit** so it has
something to compare against, and it says so in the report.

**A bootstrap cycle cannot detect a status change, and it says that too.** Its baseline is the
artifact as it stands *after* whatever realign runs already happened, and the audit carries those same
statuses forward, so both sides of the comparison hold the identical `Status` for every pre-existing
finding. The class is not suppressed; it is unobservable this once. **The next cycle can see one**,
because its baseline is this cycle's post-audit spine, taken before any later realign ran.

Every other delta class works normally on a bootstrap cycle: a verdict really can move between the
artifact's stored judgment and this run's fresh one.

## The spine baseline

`spine-baseline.md`, beside the findings artifact in the same resolved home. Its frontmatter, what
its body may and may not carry, its deliberately-not-`overengineering-findings` type, and why it is a
snapshot rather than a second record are owned by
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md` under "The spine-capture obligation". **This
skill does not restate them.** Two rules bind the run directly:

**A capture never replaces a baseline this cycle did not consume.** The end-of-cycle capture is
earned by having completed the comparison, and nothing else earns it. If the cycle stopped short
for any of these reasons, the stored baseline stays exactly as it is and this run writes none:
the audit was never invoked, the audit failed, the schema was unrecognized, the homes disagreed,
or the branch identity was unresolved.
Overwriting it would move the comparison's origin silently forward past a cycle nobody ever compared,
and whatever moved in between would then be reported by no cycle at all.

**A baseline older than one cycle widens the span rather than being discarded.** When the stored
baseline's `source-date` predates the immediately preceding cycle, an interrupted cycle left it
unconsumed, or a cycle consumed it and died before capturing its own, compare against it anyway and
say so: the report's span then covers more than one cycle and names the `source-date` it is measuring
from.
