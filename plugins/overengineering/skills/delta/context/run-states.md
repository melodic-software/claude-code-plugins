# Run states that are not errors

A detached checkout, a missing baseline, a branch mismatch, and a layer the audit did not walk are
all first-class states of the run in [`../SKILL.md`](../SKILL.md), each with defined handling.
Reporting any of them as an error is the defect this file prevents.

## Contents

- [A detached checkout has no branch identity](#a-detached-checkout-has-no-branch-identity)
- [No baseline. A first-class state, not an error](#no-baseline-a-first-class-state-not-an-error)
- [Layers that were not walked](#layers-that-were-not-walked)

## A detached checkout has no branch identity

`git rev-parse --abbrev-ref HEAD` answers `HEAD` on a detached checkout. That is a string, not an
identity, and treating it as one breaks this lane twice over: every ref keys to the same
`<branch-slug>` home, and the branch-match check in step 2 compares `HEAD` to `HEAD`, passes, and
accepts some other ref's spine as this ref's baseline, after which the lane reports the difference
between two refs as a delta. Scheduled runners very commonly check out detached, so this is the
ordinary case for the mode this lane was built for, which is why the precompute uses
`git symbolic-ref` and refuses to invent a name.

When the branch identity does not resolve:

- **Prefer a logical ref where the environment supplies one.** Some execution environments hand the
  run the ref it was launched for even though the checkout is detached. Where such a value is present
  and names a branch, use it as the branch identity for both the home key and the match check, and
  name in the report where it came from. **No vendor's variables are named here or assumed**. This
  plugin is consumer-agnostic, and hardcoding one CI system's environment would be a claim about the
  consumer's toolchain that the rest of this plugin refuses to make.
- **Otherwise, treat the run as no baseline and say why**. "detached checkout, no logical ref
  supplied; no branch identity, so nothing is compared". Do not fall back to `HEAD`, to the commit
  sha, or to whatever home the slug happens to produce, and do not compare.
- **Capture no baseline either.** With no branch identity, a capture would land in a home keyed by
  something every ref shares, where the next detached run of a *different* ref would read it as its
  own. This is the one no-baseline state that does **not** establish a baseline for the next cycle,
  and the report says so rather than implying the next run will have one.

The audit still runs and still reports; what is declined here is the comparison and the capture, not
the pass. **It does not, however, persist an artifact on such a cycle**. `audit` declines its own
write on an unresolved identity for the same reason this lane declines its capture, so step 4 below
has no post-run artifact to read and the audit's inline summary is the cycle's whole output. That is
the expected shape, not a fault: with nothing compared and nothing captured, a persisted artifact
would be a file keyed by something every ref shares and read by no later cycle.

## No baseline. A first-class state, not an error

No stored baseline and no artifact, a branch mismatch, an unresolved branch identity, or a fresh
container, worktree, or branch means there is **no prior spine**. Both files are ephemeral by design
and losing them is expected, not a fault.

In that state the lane:

- says, in one line, **"No baseline; this run establishes one"**, naming the reason (absent /
  branch mismatch, with both branches named). Except under an unresolved branch identity, which
  establishes nothing and says so instead, per the section above;
- runs the audit exactly as it otherwise would, and captures its post-audit spine at the end of the
  cycle as the baseline for the next one;
- **reports nothing as a delta**. Not the findings, not the counts, not "everything is new". A
  first-run surface is not a change;
- **does not restate the surface.** The composed audit already printed its own inline summary, and
  that summary is the full-surface view. Producing a second one here would be the duplicate record
  the report contract forbids, point at it instead.

## Layers that were not walked

Merge rule 4 carries a finding in an unwalked layer forward **untouched**, marked not re-evaluated
and stamped with the date of the run that produced it. Two obligations follow, and both are
load-bearing:

- **Every finding in a layer absent from this run's `scope` is excluded from the comparison
  entirely.** It is not unchanged-and-checked, and it is emphatically not closed. It contributes to
  no delta class.
- **The report names the unwalked layers once, as a coverage line, with the count of findings held
  in them**. Never as findings. A layer-scoped cycle that read as a clean bill of health for the
  whole surface would be worse than no cycle at all.

The converse case is real too. A layer walked **this** run but absent from the **baseline** run's
`scope` carries baseline rows that are themselves stale carry-forwards. A verdict move there is
genuine, but its "since" is the older run's stamped date, not the baseline artifact's `date`. Take
the per-finding stamp merge rule 4 wrote where one exists, and the baseline's `date` otherwise, so
the report's span is honest per finding rather than per run.
