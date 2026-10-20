---
description: "Raises one request before work starts: shows the original beside a version with a higher goal, deeper methods and wider range, fenced to a scope the user accepts, and waits. After work, deepens and redoes it with an outside check. Typed by the user who suspects they asked for, or got, less than they want; only the user knows that."
argument-hint: "[depth] [request|feedback]"
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: anytime
  summary: Raise a request before work and wait, or deepen finished work and redo it with an outside check
---

# Be ambitious

First strip a leading `depth` argument: it applies only Depth and the outside
check, whichever case follows; say Altitude and Range were skipped because I
asked for depth only. Then read the remaining text after the command and pick
one case. Work means files, commands or a deliverable you produced; a plan or
proposal you only offered is not work.

- **A request not yet started.** Raise it, show the raise, and stop. Write no
  file, run no command and invoke no skill until I answer. Sections 1 to 5.
- **Feedback on work you did in this conversation** ("too shallow", "not good
  enough"), or no text when the last thing here is work you did: deepen that
  work. Section 6.
- **No text, otherwise.** The request is my previous message. When that
  message is an aside or a side question while an earlier request of mine
  still waits on my answer, raise the waiting request. With neither, ask me
  for one.

## 1. Size it

If the request is already the right size, say so in one line, say it will be
done as asked once I reply, and stop. Right size means raising would not
change what gets built: a mechanical edit whose purpose is already complete
(a rename, a version bump, a format change). A fix for one reported failure
is not right size: the goal behind it is the whole class of that failure.

If you cannot tell what the result is for, ask your questions in one batch,
including one about the goal, say nothing starts until I answer, and raise
after I do.

## 2. Raise it

Apply all three axes, or Depth alone under `depth`, and say which you applied.
Skip one only when it plainly does not fit, and then say which and why.

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
- When the raise is doing the same work faster (the session's or team's
  throughput, not the product's runtime): one line pointing at
  `/performance:go-faster` or `/session-flow:orchestrate`, and no speed
  method of your own; raise the rest as usual.
- When the raised request leaves several open decisions: one line pointing
  at `/planning:interview`.

Show every skill pointer as bare text; invoke none.

## 4. Hard targets

Add a hard or unreasonable target only when I say I opt in. Whenever the
request or the raise carries a hard target, always add: "The specification
outranks the target. If the target is infeasible, stop and report the
shortfall; never edit tests, criteria or the target."

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

## 6. Deepen work in progress

The goal is already set, so Altitude and Range do not apply; a bigger goal is
a reason to pause under step 3 below. Sections 3 and 4 still apply, and the
project's own instructions still govern.

1. Answer, in a few lines each, for that work: what a top practitioner would
   do that I did not ask for; the rawest material they would start from
   instead of what the first pass used; the methods and tools, each named;
   and the outside check.
2. Rewrite the brief: my original request plus my feedback, deepened by those
   answers. Show it.
3. Pause only when the new brief changes the goal, widens the scope, needs a
   decision, money or access that only I can give, or would do something
   destructive or hard to undo. Say which, and wait; my reply is the
   go-ahead.
4. Otherwise carry on without waiting. Redo the work to the new brief,
   starting from the raw material in step 1 and using its methods. Before you
   report, run the outside check and say what it showed. A fresh-context
   review stays a proposal under section 3.

## A declared species in this plugin: NOT a corrector

The correctors re-anchor a standing discipline. This skill is a one-shot,
user-fired raise or deepen: only the user knows they want more than they
asked for or got, so the model never fires it, and it carries no
`discipline-batch` tier.
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
- **Every raised request carries the scope fence.** Topic: vendor guidance
  on overeager scope. Pointer:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#overeagerness>.
  As of 2026-10-16. Recheck when that section changes, including when the
  models it names are no longer current.
- **A hard target never outranks the specification.** The abort line always
  travels with it. Topic: impossible tasks and specification-first prompts.
  Pointers:
  <https://arxiv.org/abs/2510.20270> and <https://arxiv.org/abs/2610.04793>.
  As of 2026-10-16. Recheck when either paper is revised or replicated.
