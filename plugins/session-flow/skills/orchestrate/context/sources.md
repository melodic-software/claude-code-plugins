# Sources behind the orchestration brief

Official sources backing each imperative in the brief. **URLs are authoritative; fetch them to
confirm.** Lines marked *(paraphrase)* are summarizer renderings captured during research
(2026-06-14), concept-faithful but not byte-exact — re-fetch the URL for verbatim wording. Lines
marked *(verbatim, verified)* were confirmed against the raw doc at capture time.

**What *(verbatim)* tolerates.** Quotes are reproduced word-for-word, with four presentational
normalizations that carry no meaning: markdown link syntax is stripped to its text
(`[depth limit](#anchor)` → `depth limit`), inline emphasis may be dropped or added, an escaped
`\_` in a raw changelog line is unescaped, and a fragment lifted mid-sentence may take a
sentence-final period. Anything that changes wording is **not** a normalization — a quote that no
longer matches the source is a defect, not a style choice.

## Imperative 1 — DELEGATE / FAN OUT

- **Start simple; a single agent goes far.** "Start with the simplest approach that works, and add
  complexity only when evidence supports it"; "A well-designed single agent with appropriate tools
  can accomplish far more than many developers expect." *(paraphrase)* —
  <https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them>
- **Decompose by context boundary, not work type.** "Group work by what context it requires, not
  by what kind of work it is"; sequential phases of one feature "share too much context."
  *(paraphrase)* — same URL
- **Coding is less parallelizable than research.** "Most coding tasks involve fewer truly
  parallelizable tasks than research." *(paraphrase)* —
  <https://www.anthropic.com/engineering/multi-agent-research-system>
- **Cost multipliers.** Multi-agent "typically use 3–10× more tokens than single-agent approaches";
  the research system reports ~4× per agent vs chat and ~15× for multi-agent; "token usage by
  itself explains 80% of the variance." *(paraphrase)* — both URLs above
- **Use multi-agent only for context-protection / parallelization / specialization; outside these
  "coordination costs typically exceed the benefits."** *(paraphrase)* —
  building-multi-agent-systems (URL above)

## Imperative 2 — SPEC EVERY SPAWN

- "Each subagent needs an objective, an output format, guidance on the tools and sources to use,
  and clear task boundaries." Without it, agents "duplicate work, leave gaps, or fail to find
  necessary information." *(paraphrase)* —
  <https://www.anthropic.com/engineering/multi-agent-research-system>
- Scale effort to complexity: "Simple fact-finding requires just 1 agent with 3–10 tool calls …
  complex research might use more than 10 subagents." *(paraphrase)* — same URL

## Imperative 3 — FRESH-CONTEXT VERIFY

- **Fresh context beats self-review.** A reviewer "running in a fresh subagent context sees only
  the diff and the criteria you give it, not the reasoning that produced the change."
  *(paraphrase)* — <https://code.claude.com/docs/en/best-practices>
- **Verifier needs explicit criteria or it rubber-stamps.** "A verifier told only to check whether
  output is good, with no further criteria, will rubber-stamp the generator's output"; specify
  "Run the full test suite and report all failures" rather than "make sure it works."
  *(paraphrase)* — <https://claude.com/blog/multi-agent-coordination-patterns> + best-practices
  (URL above)
- **Scope the reviewer.** "Tell the reviewer to flag only gaps that affect correctness or the
  stated requirements." *(paraphrase)* — best-practices (URL above)
- **Judge final state, not process.** "Evaluate whether it achieved the correct final state"
  rather than "whether the agent followed a specific process." *(paraphrase)* —
  <https://www.anthropic.com/engineering/multi-agent-research-system>
- Fable-5 verifier guidance (verbatim, verified): "Separate, fresh-context verifier subagents tend
  to outperform self-critique." —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>

## Imperative 4 — RUN WORKERS WELL

All three sub-behaviors are from the Fable 5 prompting guide (verbatim, verified) —
<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>:

- **Async over blocking:** "prefer asynchronous communication between orchestrator and subagents
  over blocking until each subagent returns"; "Delegate independent subtasks to subagents and keep
  working while they run."
- **Long-lived subagents:** "Long-lived subagents that keep their context across subtasks save
  time and cost through cache reads and avoid bottlenecking on the slowest subagent."
- **Monitor and steer:** "Intervene if a subagent goes off track or is missing relevant context."

The brief states these model-agnostically on purpose: they are correct standing imperatives for an
under-delegating model too.

## Imperative 5 — NESTED SUBAGENTS

Re-verified 2026-07-29 against two official surfaces — the prose page
<https://code.claude.com/docs/en/sub-agents> ("Let subagents spawn their own subagents") and the
release changelog <https://code.claude.com/docs/en/changelog> (raw markdown at `changelog.md`,
which is byte-exact where the rendered page summarizes), current through **v2.1.220**. The two
surfaces contradicted each other on 2026-07-26 and **agree as of 2026-07-29**; the resolved-drift
note below records what the split was, so a reader who meets an older copy of either surface knows
which way it broke.

- Shipped, **not** experimental. Changelog v2.1.172 *(verbatim, verified 2026-07-29)*:
  "Sub-agents can now spawn their own sub-agents (up to 5 levels deep)." **This version number is a
  historical citation — the release that shipped nesting — not a verification pin. Do not bump it.**
  The sub-agents page's own version-history note corroborates it *(verbatim, verified 2026-07-29)*:
  "**v2.1.172 through v2.1.216**: subagents could nest by default, up to five layers deep, and the
  limit couldn't be changed."
- **Current default depth is 3, and it is configurable.** Both surfaces now say so. Changelog
  v2.1.219 *(verbatim, verified 2026-07-29)*: "Subagents can now spawn nested subagents up to depth
  3 by default (was 1); set `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` to disable nesting." Sub-agents
  page *(verbatim, verified 2026-07-29)*: "By default, a subagent can spawn subagents of its own, up
  to three layers below the main conversation." The immediately preceding state was the opposite —
  changelog v2.1.217 *(verbatim, verified 2026-07-29)*: "Changed subagents to no longer spawn nested
  subagents by default; set `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` to allow deeper nesting."
- **The `Agent` tool is withheld at the depth limit, not while nesting is off** *(verbatim, verified
  2026-07-29 — sub-agents page)*: "At the depth limit, Claude Code withholds the `Agent` tool from
  every subagent except a fork, so a subagent at the limit does its delegated work itself and
  returns one summary. A fork at the limit keeps `Agent` in its inherited tool list, but the tool
  returns an error instead of spawning."
- Gating by tool list — necessary, not sufficient *(verbatim, verified 2026-07-29 — sub-agents
  page)*: "In a subagent definition, listing `Agent` in `tools` lets that subagent spawn subagents
  of its own while the depth limit allows it, but any type list inside the parentheses is ignored."
  To stop one spawning while nesting is on, "omit `Agent` from its `tools` list or add it to
  `disallowedTools`."
- Three separate caps, each with its own variable *(verbatim, verified 2026-07-29 — sub-agents
  page)*: "this one caps the total spawned over a session, the concurrent subagent limit stops
  Claude from spawning more while too many are running, and the depth limit caps how deeply
  subagents nest." Defaults: "at most 200 subagents per session"
  (`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`, v2.1.212+) and "when 20 subagents are running in a
  session, spawning another with the Agent tool fails with `Concurrent subagent limit reached`"
  (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, v2.1.217+). "A fork can't spawn further forks."
- **A permission gate can deny a spawn before depth is ever consulted.** Changelog v2.1.178
  *(verbatim, verified 2026-07-29)*: "Improved auto mode: subagent spawns are now evaluated by the
  classifier before launch, closing a gap where a subagent could request a blocked action without
  review." So a failed spawn needs its error text read before it counts as evidence about depth: a
  depth rejection names depth, a permission refusal names permission.

**Resolved-drift note — the prose page lagged the changelog by one release, and has since caught
up.** Between v2.1.219 and 2026-07-26 the sub-agents page still described the v2.1.217–2.1.218 state
*(page text as captured 2026-07-26 — no longer reproducible upstream)*: "By default, a subagent
can't spawn subagents of its own… While nesting is off, Claude Code withholds the `Agent` tool from
every subagent except a fork." So the changelog was treated as authoritative for the default and
the page as authoritative for the env-var mechanism and cap semantics. That call was corroborated
empirically on Claude Code **2.1.220**: a non-fork
`general-purpose` subagent one layer below a subagent held a fully-schema'd `Agent` tool with
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` unset in its environment — which the page's account at the
time forbade and the changelog's allowed. (The exact live ceiling was **not** pinned; the probe that
would have measured it was denied by the auto-mode classifier, a different gate.) As of 2026-07-29
the page states the depth-3 default itself and carries a version-history note covering all three
regimes, so no surface needs to be chosen over the other. The split is recorded because the page
carries no dated revision history: a cached, vendored, or offline copy can still be showing the old
account, and this note is how a reader tells that apart from a real behavior change.

The brief's "never author a tree that needs a specific or deep nesting level" is justified by
reliability degradation with depth, by the caps above, and — most of all — by the fact that the
default moved three times in seven weeks (fixed 5 → off → configurable 3). That volatility is the
argument, not any one of the values. The surfaces agreeing again does not weaken it.

## Imperative 6 — SURFACE DRIFT

Authoring convention, NOT canonical Anthropic orchestration guidance (it appears in none of the
multi-agent sources). Kept in the brief because drift-flagging is useful for any worker: a one-line
flag preserves the signal without derailing the task.

## Imperative 7 — CALIBRATE TO CONDITIONS

Part-sourced, part authoring convention — the boundary is called out per factor.

- **Size effort to complexity (S/M/L).** "Simple fact-finding requires just 1 agent with 3–10 tool
  calls … complex research might use more than 10 subagents." *(paraphrase — same quote backing
  imperative 2)* — <https://www.anthropic.com/engineering/multi-agent-research-system>
- **Single-agent is the floor; multi-agent is spent, not defaulted.** The 3–10× cost multiplier and
  "coordination costs typically exceed the benefits" outside context-protection / parallelization /
  specialization (both quotes backing imperative 1) are the reason a small ask stays single-agent.
  *(paraphrase)* —
  <https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them> +
  <https://www.anthropic.com/engineering/multi-agent-research-system>
- **Model capability shifts the sizing.** The Fable 5 guide frames delegation as a capability the
  orchestrator wields deliberately (async dispatch, long-lived subagents, monitor-and-steer — the
  quotes backing imperative 4), which presumes a model strong enough to orchestrate well; a weaker
  model needs more decomposition and tighter specs. *(interpretation of the same guide)* —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
- **Advisor / verifier availability, context pressure, and concurrent-session / rate-limit
  headroom** are operational authoring convention, NOT canonical Anthropic orchestration guidance —
  they scale the same underlying trade-offs (a fresh-context verifier is worth leaning on when one
  is on hand; a filling window is itself the context-protection trigger imperative 1 names; thin
  rate-limit headroom is a hard ceiling on parallel workers).
- **Per-worker model tier is an explicit spawn decision.** The subagents doc names cost control as
  a purpose of subagents: "Control costs by routing tasks to faster, cheaper models like Haiku"
  *(verbatim, verified)*, and documents the model-resolution order — `CLAUDE_CODE_SUBAGENT_MODEL`
  env var, then the per-invocation `model` parameter, then the agent definition's `model`
  frontmatter, then the main conversation's model; an omitted `model` "defaults to `inherit`"
  *(verbatim, verified)*. A spawn that never states a tier therefore runs every worker on the
  parent session's model — the mechanism behind premium-model fan-outs (imperatives 2 and 7's
  tiering clauses). — <https://code.claude.com/docs/en/sub-agents>
- **Tier is model AND effort — effort is a per-worker lever, not only the model.** The `effort`
  frontmatter field: "Effort level when this subagent is active. Overrides the session effort
  level. Default: inherits from session. Options: `low`, `medium`, `high`, `xhigh`, `max`;
  available levels depend on the model." *(verbatim, verified)* — this backs imperative 7's
  "match the reasoning depth (effort) to the subtask too" clause: a cheaper tier is a cheaper
  model, a lower effort, or both. — <https://code.claude.com/docs/en/sub-agents>
- **Volume-driven default: a fleet inherits the session model unless explicitly routed.** "Every
  agent in a workflow uses your session's model unless the script routes a stage to a different one
  or the `CLAUDE_CODE_SUBAGENT_MODEL` environment variable is set, which overrides both"; cost
  guidance: "Ask Claude to use a smaller model for stages that don't need the strongest one when
  you describe the task." *(verbatim, verified)* — this is the same inherit mechanism as the
  subagent path, at fan-out scale: the premium-fleet default imperative 7 flips. —
  <https://code.claude.com/docs/en/workflows>
- **The platform itself treats width as a volume threshold — the empirical anchor for
  "wide fan-out."** A run is flagged `Large workflow` "When a workflow schedules more than 25
  agents, or its projected token total passes 1.5 million" (min-version 2.1.203); the `/config`
  size guideline sets the agent count Claude aims for (`small` "Fewer than 5 agents", `medium`
  "Fewer than 15 agents", `large` "Fewer than 50 agents"), and the runtime caps a run at up to 16
  concurrent / 1,000 total agents. *(verbatim, verified 2026-07-29)* — these concrete numbers are
  version-pinned and stay in this sources file, NOT the model-/tool-agnostic brief, which speaks of
  a "wide fan-out" abstractly. — <https://code.claude.com/docs/en/workflows>
