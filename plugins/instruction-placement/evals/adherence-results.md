# Adherence measurement — result: no detectable effect

This plugin shipped with a claim it had not measured: that a convention delivered at the moment a
matching file is read is followed more reliably than the same convention buried in a large
always-loaded file. `adherence-experiment.sh` tested it. **The claim is not supported.**

## What was run

Two arms, identical in every respect except how the convention reaches the model:

| | Control | Treatment |
|---|---|---|
| Convention text | identical | identical |
| Delivery | one section of a large always-loaded `AGENTS.md` | a path-scoped rule on `**/*.cs` |
| Filler content | identical | identical |
| Task | identical | identical |

The convention: public classes are declared `sealed`; private fields take a leading underscore.
Neither is the model's default, and both are mechanically checkable. Compliance was defined before
any trial ran.

The task edits an **existing** `.cs` file, so the read that triggers a path-scoped rule actually
happens. A create-only task would instead be testing the documented write-trigger gap, which the
rubric already answers by refusing that destination.

Arms were interleaved so any drift in service conditions hit both alike.

## Results

| Bloat level | Control `AGENTS.md` | Arm | n | `sealed` | underscore | both |
|---|---|---|---|---|---|---|
| Realistic | 251 lines | control | 8 | 8 | 8 | 8 |
| Realistic | 251 lines | treatment | 8 | 8 | 8 | 8 |
| Extreme | 1,927 lines | control | 8 | 8 | 8 | 8 |
| Extreme | 1,927 lines | treatment | 8 | 8 | 8 | 8 |

32 trials. **100% compliance in every cell.** No difference between arms at either bloat level,
including one nearly ten times the 200-line guidance.

## What this does and does not establish

**Establishes:** a clear, unambiguous, non-conflicting convention is followed just as reliably from
line 900 of a 1,927-line always-loaded file as from a path-scoped rule that fires on read. For that
shape of instruction, moving it buys nothing in adherence.

**Does not establish** that adherence never degrades. The control arm scored 100%, so the experiment
had a ceiling and could not have detected a smaller effect. Specifically untested:

- A convention that **conflicts** with a strong model default, or with another instruction in the
  same file. The filler here was deliberately non-conflicting.
- Many competing conventions at once, where attention is genuinely rivalrous.
- Weaker or older models. The official guidance predates current models, and long-context
  instruction-following has moved; a result on today's model is not a result on last year's.
- Instruction shapes other than a crisp, checkable rule — a nuanced judgment call may behave
  differently from "declare it sealed".

## What changed because of it

The README's value case previously led with adherence. That bullet has been removed, not softened:
an unmeasured claim that measurement contradicts does not get to stay as a hedge.

The plugin's justification now rests on the three things that **are** demonstrable:

1. **Context economy** — always-loaded lines released are directly measurable, and the trade is
   stated per proposal rather than assumed.
2. **The promote lane** — conventions Claude currently loads *never* have no presence to lose, so
   any working destination is a strict improvement. No adherence claim is needed for this to hold.
3. **Reachability** — the generated index makes deferred surfaces reachable from subagents, which is
   a measured mechanic, not an inference.

Anyone weighing whether to run a migration should weigh it on context cost and on the promote lane,
not on an expectation that their instructions will be followed better.

## Re-running

```bash
plugins/instruction-placement/evals/adherence-experiment.sh --trials 8 --filler 120
```

Worth re-running when the model tier changes, or with a deliberately conflicting convention to probe
past the ceiling this run hit. A future result that *does* find an effect should replace this
document rather than be appended to it.
