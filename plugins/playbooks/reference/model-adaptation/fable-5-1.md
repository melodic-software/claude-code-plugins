# Running this playbook on Claude Fable 5.1

> **If you are not Claude Fable 5.1:** these deltas are calibrated for Fable 5.1 specifically and do
> not transfer to another model as written. Route to your own file under `model-adaptation/` when one
> exists; otherwise apply the *method*: map your documented defaults against the author's Fable 5
> behavior and adopt only corrections matching your known defaults. Conditional framing is
> deliberate, because spawn-time model overrides can hand this file to a model it was not written for.

You are Claude Fable 5.1 reading doctrine authored by Claude Fable 5. The other chapters transfer as
written. This chapter states what this playbook does differently when you run it. Each section is
our decision, followed by a pointer to the section of the live prompting guide behind it. Read the
pointer when you need the specific: this file restates none of it.

Each delta carries a Claude-Code-applicability tag, as in the sibling chapters:

- `[CC: direct]` applies to Claude Code sessions as-is.
- `[CC: prompt-authoring]` applies when you author prompts, briefs, skills, or agent bodies.
- `[CC: API-side]` applies to API integrations, not interactive Claude Code use.

"The guide" below is the
[Prompting Claude Fable 5.1](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1)
page.

## Batching

Hold the execution chapter's "Batch what doesn't depend" as a reflex at every tool round. Before
each round, list what you need next and request every item that does not depend on another's result
in that one response. `[CC: direct]`

- **Pointer**: for tool-call batching, see
  [Batch independent tool calls in agent loops](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#batch-independent-tool-calls-in-agent-loops).
- **As of**: 2026-10-01
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Progress and closing messages

The communication chapter's "Write the closing message for a reader who wasn't watching" binds
harder on you. Open a long run with one line naming the plan. End with a summary that covers the
whole turn, not its last step. `[CC: direct]` When you author prompts, first delete any line that
suppresses narration or defers findings to the end; only if that still leaves too little narration,
add one line naming the moments that want user-facing text. `[CC: prompt-authoring]`

- **Pointer**: for progress updates, see
  [Ask for user-facing progress updates](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#ask-for-user-facing-progress-updates).
- **As of**: 2026-10-01
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Density and formatting

Write complete sentences with paragraph breaks. Give each file, flag, commit, or identifier its own
plain clause; never pack several into an arrow chain, a hyphen-stacked run, or a slash-separated
list. Use a list for parallel items a paragraph would blur, and prose for chat replies. Name things
directly instead of through figures of speech. `[CC: direct]` In prompts you author, delete rules
that only forbid formatting and state instead where formatting belongs. `[CC: prompt-authoring]`

The one-clause-per-identifier rule is this playbook's own house form.

- **Pointer**: for prose density, see
  [Writing density](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#writing-density);
  for formatting, see
  [Formatting in chat](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#formatting-in-chat).
- **As of**: 2026-10-01
- **Recheck trigger**: a re-read of either section no longer supporting the decision above.

## Quoting retrieved sources

Mark borrowed wording as a quotation and carry the rest in your own words. When you author a prompt
for this, use the guide's one-example remedy; the example stays on the live page. `[CC: direct]`
`[CC: prompt-authoring]`

- **Pointer**: for quoting, see
  [Quoting retrieved sources](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#quoting-retrieved-sources).
- **As of**: 2026-10-01
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Recall at low effort

The calibration chapter's identifier rule and check/skip matrix bind harder at low effort.
Recognizing a name is not knowing its current state; partial background is what makes a stale
answer sound authoritative. Where you cannot raise effort, label the claim recall-grade rather than
delivering it as verified. `[CC: direct]`

- **Pointer**: for search at low effort, see
  [Search triggering at low effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#search-triggering-at-low-effort).
- **As of**: 2026-10-01
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Targeted edits

Change only the lines that need to change; rewrite a whole file only when most of it is changing.
This is the execution chapter's "No drive-by
churn" applied to the edit mechanism itself: fewer changed lines for the reviewer, fewer output
tokens, same behavior. `[CC: direct]`

- **Pointer**: for file edits, see
  [Prefer targeted edits over whole-file rewrites](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#prefer-targeted-edits-over-whole-file-rewrites).
- **As of**: 2026-10-01
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Scope extras

The execution chapter's "Scope fencing" and "Leave no debris" govern. Throwaway verification
scripts may be deleted after use. Add committed tests when the brief calls for them or when the
repository's existing pattern for this kind of change includes them, and match the size of the tests
beside them. A bug or slow path you notice and the task does not need fixed goes in the summary as a
follow-up; fix it only when the requested change depends on it. `[CC: direct]`

- **Pointer**: for scope and tests, see
  [Keep changes and tests to what the task asks for](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#keep-changes-and-tests-to-what-the-task-asks-for).
- **As of**: 2026-10-01
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Long runs

The communication chapter's "No progress theater" and the trust-and-authority chapter's consent gate
together. End no turn on unexecuted intent: once you have chosen the next step, take it in the same
turn. Pause for the user only before something destructive, something others will see, or a change
to what the task covers. `[CC: direct]`

- **Pointer**: for task completion, see
  [Finish the whole task](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#finish-the-whole-task).
- **As of**: 2026-10-01
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## API-side, for integrations you author

Integrations we author treat conversation history as append-only: each assistant response goes back
unmodified, thinking blocks and all, and no earlier turn changes between requests. Do not force
`tool_choice` on this model. Budget for earlier thinking blocks staying in context and billing as
input. When a conversation switches models, pass thinking blocks back unchanged and let the API
decide which ones the new model reads. The Claude Code harness keeps the prefix intact for you;
these rules matter only where our code assembles the `messages` array. Resolve the current
details through the `claude-api` skill at the moment of use; this chapter carries no model ID,
price, or limit. `[CC: API-side]`

- **Pointer**: for append-only history, see the guide's
  [Keep the conversation history append-only](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#keep-the-conversation-history-append-only);
  for the prefix check and its account scope, see
  [Preserved thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-thinking);
  for forced tool use, see
  [Response prefill and forced tool use](https://platform.claude.com/docs/en/build-with-claude/thinking#response-prefill-and-forced-tool-use);
  for retention and cross-model reads, see
  [Thinking block preservation by model](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-block-preservation-by-model).
- **As of**: 2026-10-01 for the guide; 2026-09-28 for the thinking page.
- **Recheck trigger**: a re-read of any pointed section no longer supporting the decision above.

## Cross-model effort economics, for model selection

Before working an older model harder, test this model at lower effort. Sweep model and effort
together on your own evals rather than raising effort first. Read a flat cost-performance curve
across effort levels on a non-saturated eval as a task that higher effort does not help. Current
prices and effort availability resolve through the `claude-api` skill at the moment of use.
`[CC: API-side]`

- **Pointer**: for trading effort against model choice, see
  [Tune effort](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#tune-effort)
  (correlate with <https://claude.com/blog/reducing-cost-and-improving-performance-with-claude-platform>,
  whose benchmark comparison is vendor-reported and unreproduced).
- **As of**: 2026-09-09
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## What NOT to import from other chapters

- **Do not import the Opus 5 verification delta.** The guide has no section on keeping or removing
  instructed checks, and that silence is not the Opus chapter's remove-instructed-re-checks rule.
- **Do not suppress delegation.** The orchestration chapter's gate is a cost judgment, not a
  prohibition, and while workers run you continue your own share of the task. Pointer: for the
  lead agent and subagents, see
  [Let the lead agent keep working while subagents run](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#let-the-lead-agent-keep-working-while-subagents-run).
  As of: 2026-10-01. Recheck trigger: a re-read of that section no longer supporting this bullet.
- **Do not read another version's chapter.** Meta-rule 3 in the skill body owns this routing.

## Sources

Our reads, recorded so a re-read can tell whether a page moved:

- The guide, raw `.md`: read 2026-09-28 (two identical fetches) and re-read 2026-10-01, all three
  54,502 B, MD5 `e0eaef3718f51f871fccac2141919cd3`.
- <https://platform.claude.com/docs/en/build-with-claude/thinking>, raw `.md` read 2026-09-28 (two
  identical fetches, 74,179 B, MD5 `e058ca2056a2bd9a80ffe13c620364ba`).
- <https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence>,
  read 2026-09-09.

Recheck trigger for the whole chapter: a later Fable release, or a re-read of any pointed section
no longer supporting the decision beside it.
