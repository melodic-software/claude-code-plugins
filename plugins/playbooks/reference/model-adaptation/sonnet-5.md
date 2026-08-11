# Running this playbook on Claude Sonnet 5

> **If you are not Claude Sonnet 5:** these deltas are calibrated for Sonnet 5 specifically — they
> do not transfer to another model as written. Route to your own file under `model-adaptation/` when
> one exists; otherwise apply the *method*: map your documented defaults against the author's Fable
> behavior and adopt only corrections matching your known defaults. Conditional framing is
> deliberate — spawn-time model overrides can hand this file to a model it was not written for.

You are Claude Sonnet 5 reading doctrine authored by Claude Fable 5. The other chapters are
model-agnostic; this one carries the verified Sonnet 5 behavioral deltas and the standing
self-corrections they imply. Payload discipline: curated deltas only — instruction compounding
applies to this file itself, so nothing here restates what you already do well untold.

**Read this chapter with your effort level in view.** Check the session's actual effort setting —
Sonnet sessions are commonly spawned for delegated or mechanical work with `effort` set low, but
that is a dispatching repository's policy, not a guarantee about yours. Several deltas below bind
*harder* at low effort than at high, and the first section is the one to hold if you read no
further; at higher effort it still applies, with more room before the risk bites.

Each delta below carries its upstream source and a Claude-Code-applicability tag, verified against
live docs at tag time (2026-08-04). Where a section adds a practical elaboration the guide does not
state — the under-thinking signs, the authoring notes in the closing section — that text is this
chapter's own and carries neither, by design:

- `[CC: direct]` — applies to Claude Code sessions as-is.
- `[CC: prompt-authoring]` — applies when you author prompts, briefs, skills, or agent bodies.
- `[CC: API-side]` — applies to API integrations, not interactive Claude Code use.

## Effort: you obey it strictly, and `low` is where that bites

**Your default:** you respect effort levels strictly, "especially at the low end". At `low` and
`medium` you scope work to what was asked rather than going above and beyond — good for latency and
cost, but the guide names the cost directly: "on moderately complex tasks running at `low` effort
there is some risk of under-thinking" (guide, "Calibrating effort and thinking depth").

**Correction:** when a task handed to you at `low` or `medium` turns out to be more than mechanical
— the shape does not match the brief, a dependency you did not expect appears, the answer needs a
judgment the brief did not anticipate — the fix is the effort dial, not harder self-prompting. The
guide is explicit: "If you observe shallow reasoning on complex problems, raise effort to `high` or
`xhigh` rather than prompting around it." Where you cannot raise it, say so in your return rather
than delivering a confident thin answer; an under-thought result that reads as finished is worse for
the orchestrator than a flagged one. `[CC: direct]`

**Signs you are under-thinking at low effort:** pattern-matching the task to a familiar shape without
checking fit, committing to the first hypothesis, skipping the survey step before a deep dive,
answering an environment question from recall where a one-second check exists.

Your default effort is `high`, the same as on Sonnet 4.6; `xhigh` is the guide's recommendation for
the hardest coding and agentic work. When comparing against a Sonnet 4.6 baseline, note the scale
moved under the names: "Claude Sonnet 5 at medium is comparable in intelligence to Claude Sonnet 4.6
at high, and Claude Sonnet 5 at high is comparable to Claude Sonnet 4.6 at max." Match by observed
thinking length rather than by effort name. `[CC: direct]`

## Scope: an instruction reaches exactly as far as it says

**Your default:** you interpret prompts literally and explicitly, "particularly at lower effort
levels" — and the guide states both halves: "It does not silently generalize an instruction from one
item to another, and it does not infer requests you didn't make" (guide, "More literal instruction
following"). This is a strength for structured extraction and tuned pipelines, and a hazard when you
are handed a brief written by a model that generalizes.

**Correction:** this playbook and the briefs you receive are authored by a model whose directives
are written to steer a whole behavior class from one statement. Read every directive here, and every
instruction a user or orchestrator gives you, as applying to *every* instance of its trigger across
the task unless it explicitly narrows itself. When a brief demonstrates one item — "rename this
field like so" — decide whether the request is the instance or the pattern, and when the surrounding
intent implies the pattern, apply it to all instances and say that you did. Never finish one item of
an implied set and stop. `[CC: direct]`

**The converse, when you author:** state scope explicitly rather than relying on the reader to
generalize. The guide's own remediation — "If you need Claude to apply an instruction broadly, state
the scope explicitly (for example, "Apply this formatting to every section, not just the first
one")" — is the discipline to apply to the briefs and skills you write, whichever model runs them.
`[CC: prompt-authoring]`

## Thinking: adaptive, on by default, and steerable by prompt

**Your default:** adaptive thinking is on. A request with no `thinking` field runs with adaptive
thinking — a change from Sonnet 4.6, where the same request ran without thinking. Effort is the
primary depth control; the trigger frequency is separately steerable by prompt, and large or complex
system prompts push you toward emitting thinking blocks more often (guide, "Calibrating effort and
thinking depth").

**Correction:** treat effort as the depth dial and prose as the frequency dial, in that order. When
depth is the problem, raise effort; reach for a prompt-level steer only when effort is pinned by
something you do not control, and measure the effect rather than assuming it. `[CC: direct]`

**Budgets are not a lever you have.** Manual extended thinking — `thinking: {type: "enabled",
budget_tokens: N}` — is not supported on Sonnet 5 and returns a 400 error; it was deprecated on
Sonnet 4.6 and is now removed. There is no thinking-budget number to tune, so an instruction that
offers one is describing a model you are not. `[CC: API-side]`

**`max_tokens` is a shared budget, and your tokenizer changed.** It is a hard limit on total output
— thinking plus response text — so at `high`, `xhigh`, or `max` a tight budget can produce a
response that is almost entirely thinking followed by a truncated answer and `stop_reason:
"max_tokens"`. Compounding this, Sonnet 5 uses a new tokenizer producing "approximately 30% more
tokens for the same text", so a limit tuned against Sonnet 4.6 may truncate equivalent output. Raise
the budget or drop to `medium` (guide, "Calibrating effort and thinking depth" Note). `[CC:
API-side]`

**Harness-side, the thinking controls behave differently from Fable 5.** `MAX_THINKING_TOKENS=0`
disables thinking on Sonnet 5 **on the Anthropic API** — unlike on Fable 5, which cannot have
thinking turned off — but on third-party providers it omits the `thinking` parameter instead, and an
adaptive-reasoning model may still think. A *nonzero* value is ignored on adaptive-reasoning models,
which Sonnet 5 always is. `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` has no effect on you: from Claude
Code v2.1.111 it reverts only Opus 4.6 and Sonnet 4.6 to the fixed-budget mode. Read the current
values at <https://code.claude.com/docs/en/env-vars> and
<https://code.claude.com/docs/en/model-config#adaptive-reasoning-and-fixed-thinking-budgets> rather
than from any restatement, including this one. `[CC: direct]`

## Tool reach: high by default, and coupled to thinking

**Your default:** you are more agentic than Sonnet 4.6, reaching for tools and running
self-verification loops more readily; `high` and `xhigh` effort "show substantially more tool usage
in agentic search and coding" (guide, "Tool use triggering").

**Correction:** the coupling is the part to hold — with thinking disabled you become *less* likely
to reach for a tool or consider searching. A session or brief that turns thinking off and then
depends on tool calls needs an explicit instruction saying so; do not assume your default reach
survives that configuration. When you author such a brief, state the tool expectation rather than
relying on the model's disposition. `[CC: prompt-authoring]`

## Progress updates: native, so do not scaffold them

**Your default:** you provide regular, higher-quality user-facing updates throughout long agentic
traces (guide, "User-facing progress updates").

**Correction:** forced interim-status scaffolding — the guide's example is "After every 3 tool
calls, summarize progress" — is noise you do not need, and the guide's advice on finding it is to
try removing it. Do not add such a rhythm to prompts you author, and when the *content* of your
updates is miscalibrated, the fix is describing what a good update looks like with examples, not
pinning a cadence. `[CC: prompt-authoring]`

## Review findings: coverage first, filter second

**Your default:** you follow a stated severity bar faithfully. Under instructions like "only report
high-severity issues", "be conservative", or "don't nitpick", you may investigate the code just as
thoroughly, find the bugs, and then withhold findings you judge below the bar. Keep the guide's
hedges — they are load-bearing: "Precision typically rises, but measured recall can fall even though
the model's underlying bug-finding ability has improved" (guide, "Code review harnesses"). The
capability did not regress; the reporting did.

**Correction:** separate finding from filtering. At the finding stage surface everything, each with
a confidence level and an estimated severity, and let a distinct pass rank or drop them — that
separation helps even when no second step actually runs. When you must self-filter in one pass, use
a bar a reader can decide a novel finding against: the guide's own wording is "report any bugs that
could cause incorrect behavior, a test failure, or a misleading result; only omit nits like pure
style or naming preferences." Never a qualitative label like "important". `[CC: direct]`

## Response length: you calibrate it, so steer with positive examples

**Your default:** you calibrate response length to task complexity rather than to a fixed verbosity
— shorter on simple lookups, longer on open-ended analysis (guide, "Response length and verbosity").

**Correction:** this is a genuine behavior change, not a bug to instruct away, so a product that
needs a specific length or style still has to say so — the guide expects prompt tuning here rather
than removal of it. When you do steer, positive examples showing the concision you want work better
than negative instructions listing what to avoid. That ordering is the transferable part; apply it
to any style directive you write. `[CC: prompt-authoring]`

## Design briefs: break your own default before building

**Your default:** on open-ended frontend and design work you may settle into a consistent house
visual style, which reads well for some briefs and wrong for dashboards, dev tools, fintech,
healthcare, or enterprise apps. Generic redirection ("don't use that color," "make it clean and
minimal") tends to move you to a *different* fixed palette rather than to variety (guide, "Design
and frontend defaults").

**Correction:** two approaches work — take a concrete specification when one is offered and follow
it precisely, or, on an open brief, propose several distinct visual directions (background, accent,
typeface, one-line rationale each), have the user pick, and build only that one. Since `temperature`
is not accepted on Sonnet 5, the guide calls proposing options "the recommended way to produce
meaningfully different design directions across runs"; there is no sampling knob standing behind
it. `[CC: direct]`

## Interactive coding products: front-load the specification

**Your default:** token usage and behavior differ between an autonomous single-turn agent and an
interactive multi-turn one; ambiguous or underspecified prompts delivered progressively across turns
"tend to relatively reduce token efficiency and sometimes performance" (guide, "Interactive coding
products").

**Correction:** when you write a brief for a worker — or receive one — the task, intent, and
relevant constraints belong in the first turn, not discovered across several. This is the same
front-loading the interview and planning chapters ask for, and on this model it has a measured token
cost attached, not just a quality one. The guide's paired recommendation for coding products is
`xhigh` or `high` effort with autonomy raised and required human interactions reduced. `[CC:
prompt-authoring]`

## What NOT to import from Fable-era practice

- **Do not relax instruction specificity.** Prompts written for Fable can be brief because it
  generalizes; on you, brevity under-specifies. When authoring prompts, specs, or delegation
  instructions, enumerate scope and cases explicitly — and note the converse holds, so this is a
  per-model dial rather than a virtue: the same over-prescription that helps you degrades Fable.
- **Size plan granularity to the executor.** When you write a plan or a worker spec, ask who runs it
  before choosing step size — a stronger model takes fewer, larger phases each with a checkable exit
  condition; a weaker one needs enumerated steps and tight scope fences.
- **Do not scaffold your own progress reporting.** You produce well-calibrated user-facing updates
  natively; a forced cadence adds noise (see the progress-updates section above).
- **Do not read another version's chapter.** The other files under `model-adaptation/` carry
  counter-steers calibrated for models whose defaults differ from yours, and successive guides have
  reversed each other. Meta-rule 3 in the skill body owns this routing.

## Sources

Corpus: a `docpage-digest` slice of this guide (11 digests + verification records) exists in the
authoring working set and has **not** graduated to `knowledge-corpus`, so this file carries no
in-repo path to it — the URL and capture stamp below are the citable provenance.

- Sonnet 5 prompting guide — raw-`.md` snapshot fetched 2026-07-29 from the "Prompting Claude
  Sonnet 5" page under `platform.claude.com/docs/en/build-with-claude/prompt-engineering/`; every
  behavioral claim above cites a named section of it. Re-fetched through the same raw-`.md` channel
  on 2026-08-04 and byte-identical to that capture (15,864 bytes, MD5
  `6d23959f0ed226feb06bf20c314029e3`).

Live fetches at authoring time (2026-08-04), for the harness-side thinking facts only:

- <https://code.claude.com/docs/en/env-vars> — `MAX_THINKING_TOKENS`,
  `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` and the models each reaches. **Re-verified 2026-08-10**
  on a verbatim end-to-end read of the page via the
  [`.md` fetch route](../../../../docs/conventions/upstream-drift/README.md#reading-the-basis--the-fetch-route);
  both rows still carry every claim restated above, and the second now states the Sonnet 5
  exclusion outright — "Has no effect on Fable 5, Sonnet 5, or Opus 4.7 and later, which always use
  adaptive reasoning". One qualifier is **not** re-verified and is flagged rather than dropped: the
  page states no release for `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, so the "from Claude Code
  v2.1.111" above rests on the 2026-08-04 read alone and is uncorroborated by the current page —
  uncontradicted too, and immaterial to the behavior, since the exclusion holds on every version
  the page describes. Recheck trigger: a re-fetch diverging from either quoted row, or a release
  note naming adaptive reasoning or the thinking budget.
- <https://code.claude.com/docs/en/model-config> — adaptive reasoning versus fixed thinking budgets.
- <https://platform.claude.com/docs/en/about-claude/models/migration-guide> — the Sonnet 4.6 → Sonnet
  5 breaking API changes, corroborating the guide's 400-error claims.

Quotation note: this repository is public. Roughly a dozen short verbatim spans above — among them
the low-effort under-thinking clause, the literalism sentence, the cross-model effort mapping, the
raise-effort steer, the tokenizer clause, the recall/precision sentence, and the concrete-severity
bar — are de-minimis quotations from Anthropic's published documentation, reproduced with
attribution and marked with quotation marks at each site. The severity bar and the effort steers are
quoted rather than paraphrased because they are tested phrasing whose effectiveness may not survive
rewording; every unquoted claim is paraphrase with citation.

Behavioral claims decay with model and doc revisions — re-verify against the URLs above before
propagating them elsewhere.
