# Sources behind the orchestration brief

Official sources backing each imperative in the brief. **URLs are authoritative; fetch them to
confirm.** Lines marked *(paraphrase)* are summarizer renderings captured during research
(2026-06-14), concept-faithful but not byte-exact — re-fetch the URL for verbatim wording. Lines
marked *(verbatim, verified)* were confirmed against the raw doc at capture time.

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

Verbatim, verified against <https://code.claude.com/docs/en/sub-agents> ("Spawn nested subagents",
min-version 2.1.172):

- Shipped, **not** experimental: "As of Claude Code v2.1.172, a subagent can spawn its own
  subagents."
- Gating: "listing `Agent` in `tools` lets that subagent spawn nested subagents"; "If `Agent` is
  omitted … the agent cannot spawn any subagents."
- Depth: foreground "can spawn at any depth … self-limiting"; background "a background subagent at
  depth five does not receive the Agent tool and cannot spawn further. The limit is fixed and not
  configurable."

The brief's "never author a tree that needs a specific or deep nesting level" is justified by
reliability degradation with depth plus the platform caps above.

## Imperative 6 — SURFACE DRIFT

Authoring convention, NOT canonical Anthropic orchestration guidance (it appears in none of the
multi-agent sources). Kept in the brief because drift-flagging is useful for any worker: a one-line
flag preserves the signal without derailing the task.
