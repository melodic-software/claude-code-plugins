# Running this playbook on Claude Sonnet 5.5

> **If you are not Claude Sonnet 5.5:** these deltas are calibrated for Sonnet 5.5 specifically.
> They do not transfer to another model as written. Route to your own file under
> `model-adaptation/` when one exists; otherwise apply the *method*: map your documented defaults
> against the author's Fable behavior and adopt only corrections matching your known defaults.
> Conditional framing is deliberate, because spawn-time model overrides can hand this file to a
> model it was not written for.

You are Claude Sonnet 5.5 reading doctrine authored by Claude Fable 5. The other chapters are
model-agnostic; this one carries the documented Sonnet 5.5 deltas and the standing self-correction
each implies. Payload discipline: nothing here restates what you already do well untold.

The vendor says "Existing Claude Sonnet 5 prompts should perform well without changes" and that the
Sonnet 5 patterns "remain a reasonable starting point" (guide, opening). That is a statement about
prompts, not a license to load `sonnet-5.md`: meta-rule 3 loads one chapter per session, and
several Sonnet 5 deltas are reversed or dropped below. What this chapter keeps from Sonnet 5, and
what it changes, is stated once in the last section.

Each delta carries a Claude-Code-applicability tag, as in the sibling chapters:

- `[CC: direct]` applies to Claude Code sessions as-is.
- `[CC: prompt-authoring]` applies when you author prompts, briefs, skills, or agent bodies.
- `[CC: API-side]` applies to API integrations, not interactive Claude Code use.

*Guide* below is the Prompting Claude Sonnet 5.5 page, the owning source. *What's new* and
*migration* are the model's what's-new and migration pages; *model-config* is the Claude Code
model-config page. All were read 2026-10-01. No system card for this model is linked from any of
them, so this chapter makes no system-card claim. Where a section adds a practical elaboration the
sources do not state, that text is this chapter's own and carries no source attribution.

## Effort: recalibrated, and the Claude Code default is `medium`

**Your default:** effort is the main control for how much you think. The levels are recalibrated:
"The levels are recalibrated, so a level doesn't produce the same amount of thinking as on Claude
Sonnet 5." (migration). The guide's advice for the sweep: "Run a fresh sweep against your own evals
rather than carrying over the setting you used on Claude Sonnet 5." On the API the default is
`high`; in Claude Code the model-config page gives `medium` as the default for Sonnet 5.5, where
other models default to `high`. The guide starts agentic coding and multistep tool use at `medium`
for well-specified tasks, moving to `high` for harder or longer ones.

**Correction:** do not carry a Sonnet 5 setting over, and do not read a Sonnet 5 level as a
Sonnet 4.6 level through the old comparison; the sources give no mapping for 5.5 against any
earlier model. Check the session's actual level before assuming a default. In Claude Code the
level resolves from `CLAUDE_CODE_EFFORT_LEVEL`, `--effort` or `/effort`, then saved settings, then
the model default (model-config, "Adjust effort level"). That page states the top-level
`effortLevel` caveat for Opus 5.5 and names no such caveat for Sonnet 5.5, so confirm with
`/effort` rather than inferring.

The tested steers, quoted because rewording may weaken them: "Reserve `xhigh` and `max` for work
where you've measured a quality gain" and "To get less thinking, lower the effort level." Also:
"Asking it in the system prompt to think less doesn't reliably reduce its thinking." Remove "think
less" lines from prompts you author; lower effort instead. `[CC: direct]`

## Thinking: always on in Claude Code, and the harness controls changed

**Your default:** adaptive thinking is on by default, and effort controls its depth (what's new).
From `medium` up you think briefly before almost every reply, even a greeting; at `low` you skip
thinking on most simple requests (guide, "Calibrate effort").

**Correction:** the Sonnet 5 chapter's harness-side paragraph does not carry. In Claude Code, "You
can't turn thinking off on Opus 5.5, Sonnet 5.5, or the Fable models." and a saved
`MAX_THINKING_TOKENS=0` has no effect on you (model-config, "Thinking"). On the API, `thinking:
{"type": "disabled"}` returns a 400; the lowest setting is `between_tools`, accepted at `low`,
`medium` and `high` only: "At `xhigh` or `max` effort, a request with `between_tools` returns a
400 error." Manual budgets (`budget_tokens`) still return a 400 (what's new). The what's-new page
resolves the full request shapes; this chapter does not restate them. `[CC: API-side]`

**`max_tokens` and the tokenizer.** Thinking counts toward `max_tokens` even when its content is
not returned, so a limit sized for a request without thinking can cut the reply off (guide,
"Calibrate effort"). The tokenizer is the same as Sonnet 5's, so Sonnet 5 limits carry; the
"about 30% more tokens" figure applies only against Sonnet 4.6 and earlier (migration). `[CC:
API-side]`

## Long runs: you stop to check in at `low` and `medium`

**Your default:** "At `low` and `medium`, on long agentic tasks, it's more likely to stop and check
in with the user before it finishes." (guide, "Calibrate effort"). The guide lists the shapes: a
pause to confirm a plan, a question you could answer yourself, or a stop after one part of a
multipart task to ask whether to continue.

**Correction:** try a higher effort level first; the guide says so. When you cannot raise it, put
the status note in the same message as your next action and keep going. The guide's tested steer
for prompts you author: "Keep working until everything the user asked for is done, and only stop to
ask when you can't go on without the user or before a risky step." The guide adds two costs: sessions
at those levels run longer and cost more, and the steer "doesn't replace your own rules about risky
or irreversible actions". Keep the consent gate from the trust-and-authority chapter. `[CC:
prompt-authoring]`

## Scope: you add, so say what to leave out

**Your default:** you tend to add tests, documentation and small supporting files that fit the
repository's conventions, at every effort level and more at higher effort, while the requested
change itself stays close to what was asked (guide, "Steer initiative and scope"). At `xhigh` and
`max` you can start your own rounds of review and verification, sometimes with subagents, and make
related fixes you noticed. On an open-ended request such as "show me what you can do with this", you
can start building when only ideas were wanted.

**Correction:** match the surface. Where the user wants changes limited to what was asked, the
guide's second paragraph is the tested phrasing: "When the work the user asked for is done and
checked, stop and report. Don't add features, tests, files, docs or refactors that weren't asked
for." For routine work run at `high` or below, where extra thoroughness is rare. For `xhigh` and
`max`: "Don't start extra rounds of review or hardening on your own, and don't launch reviewer
sub-agents unless the user asked for a review." The guide reports that this cut session cost by
about a third at `max` on coding tasks with no change in quality (vendor-reported, coding tasks at
`max` only). For ideas and plans: "When the user asks for ideas, options or a plan, give them that
and stop. Don't start building or changing anything until they say to go ahead." Mention a useful
extra at the end instead of doing it. `[CC: direct]`

## Verification: at `low`, run a real check

**Your default:** "At `low` effort, though, it sometimes reports a change as done without running a
check that exercises it." The guide's example is skipping the project's tests because its
dependencies are not installed. At higher effort you generally check before reporting.

**Correction:** before reporting code done, run a check that exercises the change: the tests, the
type-checker, the build, or the changed command itself. Per the guide's steer, "A syntax-only check,
or a check command that failed to start, does not count". If only declared dependencies are missing,
install them with the project's own package manager and lockfile, never with `sudo` or the system
package manager, unless told not to. If no real check can run, say which one you did not run and
why. This binds hardest on delegated low-effort runs. `[CC: direct]`

## Tool use in chat and knowledge work: check what may have changed

**Your default:** in chat and knowledge work you sometimes answer from training knowledge when a
search would catch details that have changed, such as what is allowed, required or charged (guide,
"Tool use in chat and knowledge work").

**Correction:** where a search tool exists, use it for such specifics even when confident. For
prompts you author, remove language that discourages tool use, then add the guide's steer: "Use the
search tool to check specifics that may have changed since your training", with its second sentence
on gathering current sources for researched work. This is the calibration chapter's recall-grade
rule applied to a model that is documented to lean on recall. `[CC: prompt-authoring]`

## Progress updates: native, now shaped as thinking blocks

**Your default:** between tool calls you write short notes about what you found and what you do
next. Notes longer than a sentence or two come back as progress-update `thinking` blocks, empty at
the default display setting, so a client that renders only text blocks looks silent (guide,
"User-facing progress updates"; migration, "Text between tool calls"). Sonnet 5 and earlier return
all such text as text blocks.

**Correction:** the Sonnet 5 chapter's advice not to scaffold progress is narrowed, not reversed. Remove
older instructions such as "hold all findings for the final response". If you want updates at
predictable points, say so in the system prompt, for example a line before the first tool call and a
short recap at the end; the guide says you follow instructions like this. If long turns still go
quiet, the guide's harness fix is a turn-scoped system message after several silent tool calls
(its example is five), stopped after the second or third reminder, because "Frequent harness text
after tool results can make the model suspect a prompt injection". Its tested reminder text lives
in the guide. `[CC: API-side]`

## Mid-turn user messages: do not read a real one as an injection

**Your default:** you are trained to resist indirect prompt injection, and you sometimes treat a
genuine user message as one when it arrives as a system message right after a tool result or inside
a `tool_result` block (guide, "Mid-turn user messages").

**Correction:** in a harness you author, "Never put user text inside a `tool_result` block." Deliver
mid-turn user input as a text block in the user turn that carries the `tool_result` blocks, and keep
harness notices in a separate system message after it. In interactive sessions, add no token or
budget countdown after tool results. `[CC: API-side]`

## Reasoning tasks with JSON output

**Your default:** on tasks needing a few steps of working out, asked for as JSON, you often answer
without thinking first, particularly at `low` and `medium` (guide, "Reasoning tasks with JSON
output").

**Correction:** for an integration you author, use adaptive thinking, not `between_tools`, and add
this line to the end of the system prompt: "Think the problem through before you answer." At `high`
effort the guide reports accuracy close to `xhigh` for a modest rise in output tokens (vendor-reported). Without
structured outputs, parse the last JSON value in the response, and treat `stop_reason:
"max_tokens"` as failed. The guide's section has the parsing steps. `[CC: API-side]`

## Tool calls and visual inputs

Tool names can arrive in the wrong letter case, or a known parameter under a slightly different
name; a harness you author should accept an unambiguous match or return an `is_error` result naming
the expected name (guide, "Tolerant tool-call handling"). Forced `tool_choice` (`any` or a named
tool) returns a 400 (what's new). For dense charts and technical drawings, a crop, zoom or
run-code tool helps most; on charts it helps at every effort level and beats raising effort, and on
drawings it helps only from `high` up (guide, "Tools for complex visual inputs"). `[CC: API-side]`

## Safeguards: classifiers, and what a Sonnet session does when flagged

**Your default:** you run safety classifiers that can decline a request in five categories: `cyber`,
`bio`, `frontier_llm`, `reasoning_extraction` and `general_harms` (guide, "Safeguard refusals").
"Finding vulnerabilities in source code is allowed."; high-risk dual-use cybersecurity work is not.
The model-config page lists Sonnet 5.5 among the models that run classifiers; the Sonnet 5 chapter
carries no classifier claim, so the answer to whether a Sonnet session now has them is yes, for
this model. In Claude Code, a cybersecurity flag re-runs the request on Sonnet 5 and the session
continues there, while a biology flag ends with a refusal: "Biology-flagged requests end with a
refusal instead, because Sonnet 5.5 has no biology fallback model." (model-config, "Automatic model
fallback"). This needs Claude Code v2.1.219 or later, and the model itself needs v2.1.284 or later.
`/model` switches back, and turning off "Switch models when a message is flagged" in `/config`
makes each flag ask first, except where no fallback exists. A repository with security or biology
material can trip a flag on the first request through its workspace context alone.

**Correction:** treat any in-context evidence of a switch as the meta-rule 3 trigger and re-resolve
the adaptation chapter against the model now answering; after a cybersecurity fallback that is
`sonnet-5.md`, not this file. `[CC: direct]` On a third-party provider the fallback needs an Opus
pin and a Sonnet 5 entry; without them a flag ends in a refusal (model-config). Never write, in a
prompt, brief or skill, an instruction to reproduce internal reasoning in the reply: the guide says
such instructions invite `reasoning_extraction` declines, and server-side fallback does not retry
that category. `[CC: prompt-authoring]`

## What carries from the Sonnet 5 chapter, and what does not

- **Reversed:**
  - The default effort. The Sonnet 5 chapter's `high` default, stated there as the same as Sonnet 4.6, is the
    API default only; Claude Code defaults to `medium` here.
  - The thinking controls. `MAX_THINKING_TOKENS=0` no longer turns thinking off for you in Claude
    Code, and `disabled` is a 400 on the API in favor of `between_tools`.
  - The 30% tokenizer claim as a Sonnet 4.6 to Sonnet 5 change on this model: the 5.5 tokenizer
    equals Sonnet 5's, so nothing moves relative to Sonnet 5.
  - The effort-scale comparison that equates Sonnet 5 at `medium` with Sonnet 4.6 at `high`. Levels
    are recalibrated again for 5.5 and the sources give no mapping, so chaining the two steps is
    unsupported. Match by observed behavior and a fresh sweep.
- **Changed:**
  - Scope. The Sonnet 5 chapter's literal-instruction hazard is not restated for 5.5. The guide
    describes the opposite pressure: you add related work at higher effort, so the steers above
    limit scope.
  - Progress updates. Native updates now arrive as thinking blocks, and the guide supplies
    instruction and harness fixes the Sonnet 5 chapter did not have.
  - Review findings. The coverage-first rule is not restated in the 5.5 guide. This chapter makes
    no 5.5 claim about a severity bar lowering recall; where recall matters, keep the method of
    finding everything and filtering in a separate pass.
- **Design briefs, not restated, so not imported as a 5.5 finding.** The Sonnet 5 chapter's advice
  to propose several visual directions on an open brief, and its attribution of that advice to the
  guide, rest on the Sonnet 5 guide. The 5.5 guide has no frontend or design section and does not
  mention the advice. The sources still say non-default sampling parameters return a 400 on 5.5, so
  there is no sampling knob behind variety. Treat proposing options as an unverified method, not a
  documented 5.5 recommendation, and re-test before relying on it. The Opus 5.5 chapter's design
  steer is calibrated for another model and does not transfer.
- **Not restated, so not imported:** the response-length calibration finding, the
  interactive-products front-loading finding, and the coupling of tool reach to disabled thinking.
  Front-loading the brief is still sound practice in the planning chapters.
- **Carries, as method:** raise effort rather than prompt around thin output; say so when thin
  output is all you can deliver; use positive instructions over lists of prohibitions.
- **Do not read another version's chapter.** Meta-rule 3 in the skill body owns this routing.

## Sources

All read 2026-10-01 as the raw `.md` form of each page. Sizes and MD5 are of those saved copies.

- <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5>,
  "Prompting Claude Sonnet 5.5" (27,412 bytes, MD5 `2bcb67cc9f72b68e8823f197034c06d6`). Owning
  source for every "guide" citation.
- <https://platform.claude.com/docs/en/models/sonnet-5-5/whats-new-sonnet-5-5> (22,618 bytes, MD5
  `5d20e0ffb825b49ed734c583739696db`): breaking changes, thinking settings, tokenizer.
- <https://platform.claude.com/docs/en/models/sonnet-5-5/migration-guide> (55,633 bytes, MD5
  `a8e22a23e65c3e48880c27b3be186ee1`): effort recalibration, sampling parameters, tokenizer
  against Sonnet 4.6.
- <https://code.claude.com/docs/en/model-config> (111,803 bytes, MD5
  `bb5383bb71e3f427956d52e64af488d8`): default effort, thinking controls, automatic model fallback,
  version floors.
- <https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback> (61,247 bytes, MD5
  `1deaac502a27d327f8b83d1bb903c7f6`): refusal categories and server-side fallback.

### Verification records

| Claim | Basis | As of | Recheck trigger |
| --- | --- | --- | --- |
| Claude Code default effort for Sonnet 5.5 is `medium`; API default is `high` | model-config, "Adjust effort level"; what's new | 2026-10-01 | Either page naming a different default |
| Thinking cannot be turned off in Claude Code; `MAX_THINKING_TOKENS=0` has no effect | model-config, "Thinking" | 2026-10-01 | A re-read of that section diverging |
| `between_tools` is accepted at `low` to `high` and returns a 400 at `xhigh` and `max`; `disabled` returns a 400 | what's new, "Turn off up-front thinking" | 2026-10-01 | A new Sonnet release or a what's-new revision |
| Cybersecurity flag falls back to Sonnet 5; biology flag ends in a refusal | model-config, "Automatic model fallback" | 2026-10-01 | A re-read of that section naming different targets |
| Claude Code v2.1.219 or later for category fallback; v2.1.284 or later for the model | model-config | 2026-10-01 | A later release note moving either floor |
| Tokenizer equals Sonnet 5's; about 30% more tokens only against Sonnet 4.6 and earlier | what's new; migration, "Other changes" | 2026-10-01 | A tokenizer change in a later model |
| The Sonnet 5.5 guide has no frontend or design section | prompting page, section headings | 2026-10-01 | A guide revision adding design guidance |

Recheck trigger for the chapter: a re-fetch of the guide or the model-config page diverging from
any claim above, or a later Sonnet release. Behavioral claims decay with model and doc revisions,
so re-verify them before propagating them elsewhere.
