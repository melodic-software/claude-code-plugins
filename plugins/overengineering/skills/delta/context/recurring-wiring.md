# Recurring wiring — how a consumer schedules this lane

`overengineering:delta` is a **single-pass mechanic**. It runs once, compares once, reports once, and
exits. Recurrence is entirely the consumer's, and this plugin **adopts no cadence and ships no
schedule file**: a plugin that scheduled itself on install would be an unratified standing commitment
in somebody else's repository, which is precisely the class of thing this plugin exists to find and
retire.

This document describes four wiring shapes and the trade each makes. Pick one; none is a default.

## Before any of them: what a scheduled run must pass

Every shape below invokes the same line, and the two arguments are not optional decorations:

```text
/overengineering:delta [<layer> ...] unattended
```

- **`unattended` is mandatory for anything unwatched.** It selects the audit's unattended
  disposition for low-confidence intent (`context/scrutiny-method.md` §4): record `OPEN-INTENT`, ask
  nothing, guess nothing. The harness gives a prose skill no reliable probe for whether a human is
  watching, so the caller owns the flag — and a scheduled run that omits it will sit waiting on a
  checkpoint question nobody will answer.
- **Layer scope is how a large surface fits.** A mature surface runs past a hundred items and does
  not fit one context window. A rotation — one or two layers per cycle, covering the ten-value
  vocabulary over several cycles — composes correctly, because a re-run merges into the same
  artifact by stable finding id. What it costs is stated in the skill body: findings in the layers a
  cycle did not walk contribute to no delta class, and the cycle's report names them as coverage.
  **Rotate deliberately, and read the coverage line.**

## Shape 1 — a fixed-interval loop (interactive, the simplest)

```text
/loop 1w /overengineering:delta unattended
```

`/loop` is a bundled skill and needs no install. Supplying an interval converts it to a cron
expression and fires on that fixed schedule, subject to the scheduler's jitter.

**A fixed interval is the right shape here, and the reason is specific.** The self-paced shape — an
omitted interval, with the model choosing each delay — earns its keep for a *drain* loop, where what
the last cycle observed should govern when the next one fires and where the loop needs to be able to
end itself. This lane drains nothing and never ends: an enforcement surface has no terminal state,
and the interval chosen once *is* the whole cadence policy, so there is no per-cycle signal for a
self-paced schedule to consume.

**Pick the interval from how fast the surface actually changes**, not from how often a report would
be nice. A surface whose last four cycles were quiet is telling you the interval is too short. Weekly
or fortnightly suits an actively developed repository; monthly or quarterly suits a stable one.

**Known constraint.** A loop launched this way expires after seven days and must be relaunched;
on some providers an omitted interval silently becomes a fixed ten-minute schedule instead of a
self-paced one, which is one more reason to name the interval explicitly.

## Shape 2 — a scheduled task (headless)

Where the harness offers a headless scheduled-task surface, register the same one-line prompt there.
This is shape 1 without a session to keep open, and it makes the same trade.

Two things to get right:

- **The run needs a checkout on the branch it is auditing.** The findings artifact is branch-keyed,
  and this lane treats an artifact whose `branch:` does not match as no baseline at all. A scheduler
  that lands on a different branch than the last cycle will report "no baseline" every time.
- **Ephemeral runners have no baseline, ever.** A fresh container each cycle loses the memory-tier
  artifact, so every cycle is a first run and every report says so. Either persist the memory root
  across runs, or use shape 4 instead, where the durable record is a tracker item rather than a file.

## Shape 3 — a CI schedule

A scheduled CI job can run the lane, and the trade is the sharpest of the four.

**What it buys:** a cadence nobody has to remember, and a queue route that reaches a human through
the forge.

**What it costs:** a scheduled CI lane *is itself an enforcement-surface item* — one this plugin's
own audit will later walk, judge on carry cost, and quite possibly recommend retiring. Wire it
knowing that, and give it the evidence it will be judged on: record what each cycle found, so the
lane can prove its own keep rather than becoming the UNPROVEN row it exists to find. A recurring
report lane nobody reads is exactly the clutter the audit is pointed at.

**And the ephemerality problem is worst here.** CI checkouts are fresh containers and are often
shallow. A fresh container has no baseline, so the lane has nothing to compare; a shallow clone makes
the version-control evidence tier *unavailable*, which the audit reports honestly and which changes
what UNPROVEN means for every row. If you take this shape, persist the memory-tier home between runs
and fetch enough history for the evidence tiers to be readable — otherwise the lane reports a first
run, forever, over a thin evidence base.

## Shape 4 — a recurring work item (the lowest-commitment shape)

Register a recurring item in the consumer's own tracker — "run `/overengineering:delta unattended`
and record what moved" — on whatever cadence that tracker already understands, and let the operator's
existing work-selection routine pick it up when it comes due.

**This is the shape to prefer when in doubt**, and it is the one this plugin's own repository is
expected to consider first. Three reasons:

- **It ratifies the cadence in a reviewable place.** A row in a tracked schedule is a decision
  somebody made and can see; a cron line in a harness config is a commitment nobody reviews.
- **It adds no new enforcement-surface item**, so it does not enlarge the surface the audit walks.
  Shapes 1–3 all do, in their own small way.
- **It degrades honestly.** A due item that nobody picks up is visibly overdue. A scheduled lane that
  stopped firing looks exactly like a quiet surface.

Its cost is real and should be stated: it fires only when somebody works the queue, so the cadence is
a target rather than a guarantee.

## What no shape may do

- **No shape reaches `overengineering:realign`.** Recurrence changes nothing about the read-only
  contract, and there is no scheduled remediation path in this plugin at any cadence.
- **No shape may drop `unattended`.** An unwatched attended run stalls at the first intent
  checkpoint.
- **No shape substitutes for the operator's judgment about the cadence.** If a lane's last several
  cycles were all quiet, the correct response is to lengthen the interval or retire the lane — not to
  keep it and stop reading it.
