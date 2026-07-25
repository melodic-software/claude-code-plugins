# skill-dispatch-posture-sweep — completed evidence, promoted

**This directory is an input to a topic that has not started, not a record of one that finished.**
It holds the completed dispatch-posture audit of every non-`setup` skill in this marketplace — 138
skills, 11 batches, zero skipped — produced during the
[`discovery-subagent-dispatch`](../discovery-subagent-dispatch/PLAN.md) effort, which applied its
conclusions to the `discovery` plugin only.

## Why it is here rather than in a memory slice

The audit was written into `.work/discovery-subagent-dispatch/`, whose `.gitignore` is `*`. Every
file was therefore worktree-local: it survived a session, but not a worktree cleanup, and it was
invisible to any other clone or session that picked the sweep up. Filing a tracked issue pointing at
that path would have handed the next session a dangling reference to evidence it could not read.

Promotion is the fix, and it is deliberately promotion **without re-derivation** — the audit's
verdicts are unchanged from the run that produced them. Rewriting them here would make this a second
source of truth for work already done.

## What is in it

| Path | What it holds |
|---|---|
| [`LEDGER.md`](LEDGER.md) | The index — one row per skill, its verdict, and a pointer to the batch artifact carrying its evidence-cited rationale |
| `audit/B01.md` … `B11.md` | The eleven batch artifacts. Rationale lives here, cited against the skill's own text; the ledger does not copy it up |
| `decide/` | The decision rounds that set and later amended the audit criteria, including `D9-close-unverified.md` |
| `verify/` | The verification passes over the audit, plus reconciliation and renormalization records |

Verdict distribution at completion: **DISPATCH-DEFAULT 22, DISPATCH-OPTIONAL 44, INLINE-ONLY 39,
NO-CHANGE 33.**

## Known gaps, carried forward honestly

Two accounting weaknesses are recorded rather than smoothed over, because a consumer of this evidence
needs to know where it is thinner than the totals suggest:

- **32 of the original 57 INLINE-ONLY rows were upheld without an independent read**, inherited from
  batch rationale rather than re-verified against the skill's own text. A scripted predictor over
  those 32 returned three hits, all benign — so the estimated risk is low, but it is *estimated*, not
  measured.
- **10 INLINE-ONLY rows sit in no normalization bucket** (`decide/D9-close-unverified.md`). They
  applied the amended criteria independently, so the risk is low and the accounting is incomplete.

## What a consuming topic still owes

Applying these verdicts to the other plugins is the work; this directory is only its input. Anything
that touches a skill's text belongs to that topic, including a re-read of the 32 rows above before a
DISPATCH verdict is acted on.

One conflict surfaced during the sweep and remains unresolved: **`playbooks:fable-5`'s core doctrine
encodes a competing delegation rule** whose 5+-item fan-out floor is stricter than the signals this
sweep used to reach DISPATCH-DEFAULT. Two documents in the same marketplace currently answer "when
should this delegate?" differently, and a sweep that applies one while the other ships is how the
fleet ends up internally inconsistent.
