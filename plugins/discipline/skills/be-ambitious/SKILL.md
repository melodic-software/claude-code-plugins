---
description: "Raises one request before work starts: shows the original beside a version with a higher goal, deeper methods and wider range, fenced to a scope the user accepts, and waits. Typed by the user who suspects they asked for less than they want; only the user knows that."
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: anytime
  summary: Raise one request's goal, depth and range, fenced and checkable, then wait for the user to accept
---

# Be ambitious

The request is the text after the command. With none, it is my previous
message; with neither, ask me for one. Raise it, show the raise, and stop.
Write no file, run no command and invoke no skill until I answer.

## 1. Size it

If the request is already the right size, say so in one line, say it will be
done as asked once I reply, and stop. Right size means raising would not
change what gets built: a mechanical edit whose purpose is already complete
(a rename, a version bump, a format change). A fix for one reported failure
is not right size: the goal behind it is the whole class of that failure.

If you cannot tell what the result is for, ask your questions in one batch,
including one about the goal, and raise after I answer.

## 2. Raise it

Apply each axis that fits and say which ones you applied.

**Altitude.** State the goal behind the goal, then one purpose line: "This is
for ...". Screen the fit: creative or taste work is a weaker fit (say so, do
not refuse), and an unbounded goal needs a bound. Ask whether a precedent
shows the bigger goal is reachable.

**Depth.** Run the deeper-version pass: what a top expert in this domain
would add that the first version skips; the rawest material to work from
(primary data, the source, real users); the methods and tools, each named
concretely; and the outside check below.

**Outside check, always.** Whatever axes apply, name one check outside the
model that shows the result is right: something executable first (a test,
benchmark, validator, measurement, browser run), then a fresh-context
reviewer, which `/discipline:scrutinize-dont-coast` runs.

**Range.** Show a nouns-to-verbs step: turn the thing asked for into what it
must do ("a website" becomes "lets an old friend recognize me and write
back"). Bring in at least one field beyond the request's own. Rewrite any "act
as X" into "do what X does: <the work>". Add this line verbatim: "What tool
from another field would change what's possible here?"

## 3. Proposals, never actions

- A crew of specialists: propose it as a hand-off to `/planning:plan`.
- A red team: propose it only for irreversible, shared-infrastructure or
  security work, for me to decide, and scope it to gaps that affect
  correctness or the stated requirements.
- Missing tools or data: one environment line naming what is missing and a
  reduced version that works without it. Never refuse for lack of them.
- When the raise is the same thing, faster: one line pointing at
  `/performance:go-faster` or `/session-flow:orchestrate`, and no speed
  method of your own; raise the rest as usual.
- When the raised request leaves several open decisions: one line pointing
  at `/planning:interview`.

Show every skill pointer as bare text; invoke none.

## 4. Hard targets: opt-in only

Add a hard or unreasonable target only when I say I opt in. Then always add:
"The specification outranks the target. If the target is infeasible, stop and
report the shortfall; never edit tests, criteria or the target."

## 5. Output

```text
Original: <the request as given>
Raised:   <the raised request>
Axes applied: <Altitude | Depth | Range>
Check: <the outside check>

Deliver what was accepted, at that scope. The project's own instructions still govern.

Reply "accept", edit the raised version, or keep the original.
```

My reply is the go-ahead; ask for no second confirmation. Once I answer, this
skill ends and the session works the accepted request normally.

## A declared species in this plugin: NOT a corrector

The correctors re-anchor a standing discipline. This skill is a one-shot,
user-fired request raise: only the user knows they want more than they asked,
so the model never fires it, and it carries no `discipline-batch` tier.
Nearest siblings, for routing: `/planning:brainstorm` when the user wants
options rather than one raised request, and `/discipline:scrutinize-dont-coast`
when the question is whether finished work is sound.

## Next

`/planning:interview`, when the raised request leaves several open decisions; it locks them into a brief.

## Gotchas

- **Keep the outside check even when the request already says "don't
  cheat".** We rely on a structural check, not on wording. Topic: reward
  hacking under anti-cheating prompts. Pointers:
  <https://arxiv.org/abs/2510.20270> (impossible-task results by prompt
  variant) and
  <https://code.claude.com/docs/en/best-practices#give-claude-a-way-to-verify-its-work>.
  As of 2026-10-16. Recheck when that docs section or the paper is revised.
- **Scope any red team to correctness and the stated requirements.** Topic:
  padded adversarial findings. Pointer:
  <https://code.claude.com/docs/en/best-practices#add-an-adversarial-review-step>.
  As of 2026-10-16. Recheck when that section drops or changes its scoping
  callout.
- **Ask for a specialist's work, never a persona.** Topic: expert-persona
  prompting and accuracy. Pointers: <https://arxiv.org/abs/2512.05858> and
  <https://arxiv.org/abs/2508.19764>. As of 2026-10-16. Recheck when either paper
  is revised or a study of persona prompts in coding agents appears.
- **End every raised request with the scope fence.** Topic: vendor guidance
  on overeager scope. Pointer:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#overeagerness>.
  As of 2026-10-16. Recheck when that section changes, including when the
  models it names are no longer current.
- **A hard target never outranks the specification.** The abort line always
  travels with it. Topic: impossible tasks and specification-first prompts.
  Pointers:
  <https://arxiv.org/abs/2510.20270> and <https://arxiv.org/abs/2610.04793>.
  As of 2026-10-16. Recheck when either paper is revised or replicated.
