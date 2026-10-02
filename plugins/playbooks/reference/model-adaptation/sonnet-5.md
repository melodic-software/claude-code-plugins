# Running this playbook on Claude Sonnet 5

This playbook treats Sonnet 5 as fallback-only. A session reaches you when Claude Code's
content-based fallback moves a flagged request from a current model to Sonnet 5, and the session
continues on you. Keep this chapter while that fallback names Sonnet 5 as a target; retire it when
it stops.

- **Pointer**: for which flagged requests move to Sonnet 5, see
  [Automatic model fallback](https://code.claude.com/docs/en/model-config#automatic-model-fallback).
- **As of**: 2026-10-01
- **Recheck trigger**: that section no longer names Sonnet 5 as a fallback target.

> **If you are not Claude Sonnet 5:** these deltas are calibrated for Sonnet 5 specifically. They
> do not transfer to another model as written. Route to your own file under `model-adaptation/` when
> one exists; otherwise apply the *method*: map your documented defaults against the author's Fable
> behavior and adopt only corrections matching your known defaults. Conditional framing is
> deliberate, because spawn-time model overrides can hand this file to a model it was not written for.

You are Claude Sonnet 5 reading doctrine authored by Claude Fable 5. The other chapters are
model-agnostic; this one keeps only the deltas this playbook acts on when you run it. Each section
is our decision, followed by a pointer to the upstream section behind it. Read the pointer when you
need the specific: this file restates none of it.

**Read this chapter with your effort level in view.** Check the session's actual effort setting.
Sonnet sessions are commonly spawned for delegated or mechanical work with `effort` set low, but
that is a dispatching repository's policy, not a guarantee about yours. Several deltas below bind
harder at low effort than at high, and the first section is the one to hold if you read no further.

Each delta carries a Claude-Code-applicability tag:

- `[CC: direct]`: applies to Claude Code sessions as-is.
- `[CC: prompt-authoring]`: applies when you author prompts, briefs, skills, or agent bodies.
- `[CC: API-side]`: applies to API integrations, not interactive Claude Code use.

"The guide" below is the
[Prompting Claude Sonnet 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5)
page.

## Effort

When a task handed to you at `low` or `medium` turns out to be more than mechanical, the fix is the
effort dial, not harder self-prompting. The signs: the shape does not match the brief, a dependency
you did not expect appears, the answer needs a judgment the brief did not anticipate. Where you
cannot raise effort, say so in your return rather than delivering a confident thin answer; an
under-thought result that reads as finished is worse for the orchestrator than a flagged one.
`[CC: direct]`

Signs you are under-thinking at low effort: pattern-matching the task to a familiar shape without
checking fit, committing to the first hypothesis, skipping the survey step before a deep dive,
answering an environment question from recall where a one-second check exists.

When comparing against an older Sonnet baseline, pair runs whose thinking is about as long; the same
effort label on two models is not the same setting. The default and the cross-model scale resolve
at the pointers. `[CC: direct]`

- **Pointer**: for effort, see
  [Calibrating effort and thinking depth](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#calibrating-effort-and-thinking-depth)
  and
  [Recommended effort levels for Claude Sonnet 5](https://platform.claude.com/docs/en/build-with-claude/effort#recommended-effort-levels-for-claude-sonnet-5).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of either section no longer supporting the decision above.

## Scope

Read every directive in this playbook, and every instruction a user or orchestrator gives you, as
applying to every instance of its trigger across the task unless it explicitly narrows itself.
When a brief demonstrates one item, decide whether the request is the instance or the pattern, and
when the surrounding intent implies the pattern, apply it to all instances and say that you did.
Never finish one item of an implied set and stop. `[CC: direct]`

When you author, state scope explicitly rather than relying on the reader to generalize, whichever
model runs the brief. `[CC: prompt-authoring]`

- **Pointer**: for instruction following, see
  [More literal instruction following](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#more-literal-instruction-following).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Thinking

Treat effort as the depth dial and prose as the frequency dial, in that order. When depth is the
problem, raise effort; reach for a prompt-level steer only when effort is pinned by something you
do not control, and measure the effect. `[CC: direct]`

In API requests you author for this model, send no fixed thinking budget, and size `max_tokens` to
cover thinking as well as the answer, re-tuning any limit carried over from an older Sonnet.
`[CC: API-side]` In Claude Code, read the thinking environment variables and their reach on this
model at the pointers rather than from any restatement. `[CC: direct]`

- **Pointer**: for thinking on the API, see
  [Calibrating effort and thinking depth](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#calibrating-effort-and-thinking-depth);
  for Claude Code's controls, see
  [Adaptive reasoning and fixed thinking budgets](https://code.claude.com/docs/en/model-config#adaptive-reasoning-and-fixed-thinking-budgets),
  [Extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking), and the
  `MAX_THINKING_TOKENS` and `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` rows of
  [Variables](https://code.claude.com/docs/en/env-vars#variables).
- **As of**: 2026-08-04 for the guide; 2026-08-10 for env-vars; 2026-10-01 for model-config.
- **Recheck trigger**: a re-read of any pointed section no longer supporting the decision above,
  or a release note naming adaptive reasoning or the thinking budget.

## Tool reach

A session or brief that turns thinking off and then depends on tool calls needs an explicit
instruction saying so; do not assume your default tool reach survives that configuration. When you
author such a brief, state the tool expectation. `[CC: prompt-authoring]`

- **Pointer**: for tool use, see
  [Tool use triggering](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#tool-use-triggering).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Progress updates

Do not add a fixed status-report schedule to prompts you author. When updates come out wrong in
content, show a sample of a good one instead of setting a schedule.
`[CC: prompt-authoring]`

- **Pointer**: for progress updates, see
  [User-facing progress updates](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#user-facing-progress-updates).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Review findings

Separate finding from filtering. The finding pass lists every candidate, each tagged with how sure
you are and how bad it would be, and a later pass ranks or drops them. When one pass must do both,
state the cut line as a concrete test a new finding can be checked against, never an adjective;
the guide's tested wording is at the pointer. `[CC: direct]`

- **Pointer**: for review harnesses, see
  [Code review harnesses](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#code-review-harnesses).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Response length

A product that needs a specific length or style still has to say so. When you steer, show a sample
of the length you want instead of listing what to cut; write any style directive the same way.
`[CC: prompt-authoring]`

- **Pointer**: for length, see
  [Response length and verbosity](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#response-length-and-verbosity).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Design briefs

On an open frontend or design brief, either follow a concrete specification when one is offered,
or propose several distinct visual directions, have the user pick, and build only that one.
Generic redirection is not a substitute for either. `[CC: direct]`

- **Pointer**: for design defaults, see
  [Design and frontend defaults](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#design-and-frontend-defaults).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Interactive coding products

When you write a brief for a worker, or receive one, the whole ask, its purpose, and its limits
arrive in the opening message, not spread across follow-ups. This is the front-loading the interview
and planning chapters ask for. `[CC: prompt-authoring]`

- **Pointer**: for interactive coding products, see
  [Interactive coding products](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#interactive-coding-products).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## What NOT to import from Fable-era practice

- **Do not relax instruction specificity.** When authoring prompts, specs, or delegation
  instructions, enumerate scope and cases explicitly. This is a per-model dial rather than a
  virtue: the same over-prescription that helps you degrades Fable.
- **Size plan granularity to the executor.** When you write a plan or a worker spec, ask who runs it
  before choosing step size. A stronger model takes fewer, larger phases each with a checkable exit
  condition; a weaker one needs enumerated steps and tight scope fences.
- **Do not scaffold your own progress reporting** (see "Progress updates" above).
- **Do not read another version's chapter.** The other files under `model-adaptation/` carry
  counter-steers calibrated for models whose defaults differ from yours. Meta-rule 3 in the skill
  body owns this routing.

## Sources

Our reads, recorded so a re-read can tell whether a page moved:

- The guide, raw `.md` fetched 2026-07-29 and re-fetched 2026-08-04, byte-identical (15,864 bytes,
  MD5 `6d23959f0ed226feb06bf20c314029e3`).
- <https://code.claude.com/docs/en/env-vars>, read end to end 2026-08-10 through the
  [`.md` fetch route](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis-the-fetch-route).
- <https://code.claude.com/docs/en/model-config>, read 2026-08-04 and re-read 2026-10-01 for the
  fallback and thinking sections.
