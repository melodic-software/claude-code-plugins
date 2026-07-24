# Source decomposition — "The new rules of context engineering for Claude 5 models"

Author: Thariq ([@trq212](https://x.com/trq212)) · Published 2026-07-24 ·
Source: <https://x.com/trq212/status/2080710971228918066>

Every section, paragraph, and logical grouping of the source, with its claims stated so each one
can be traced to a check, a decision, or an explicit rejection. Claims are the source's, not this
repository's — verification status is tracked in [coverage-matrix.md](coverage-matrix.md) and
against official documentation in [official-corroboration.md](official-corroboration.md).

## Traceability

Every section resolves to a task, an incumbent that already covers it, or a recorded exclusion.
No section is unaccounted for.

The task named in each row designs that section's check. Which skill *owns* it, and what disposition
it received, are recorded in [proportionality-gate.md](proportionality-gate.md) — there is no new
catalog for a rule to be anchored in. The order it runs in is task #28. So a row's task is where the
rule is worked out, not where it finally lives.

| § | Subject | Where it goes |
|---|---|---|
| S1 | Context is assembled, reused, general | **Excluded — framing.** No rule to enforce. It is the problem statement in `PLAN.md`; nothing is auditable from it. |
| S2 | 80% removal; `/doctor` | Task #2 (closed — verified). `/doctor` is the incumbent; task #28 decides where the runbook hands off to it. |
| S3 | Cross-surface conflict | Task #19 — new check I12 in `claude-config:audit-instructions`. The one officially-backed new check. |
| S4 | Memory / artifacts / skills as destinations | Task #27 — folded into one consolidated C3 revision in `claude-memory:audit`, together with S7's memory half; they are the same rule. |
| S5 | Rules give way to judgement | **Partly covered** by `audit-instructions` checks I6 + I8, which de-prescribe but carry no a-priori bound on how far. Task #24 supplies the stopping condition, which is the remainder. |
| S6 | Examples give way to interface design | Task #22 — extends check I9's Remediate line in `audit-instructions` with the interface destination. `OPINION`-tier. |
| S7 | Progressive disclosure | Task #26 — splits by surface partition: tightens I3's Remediate line in `audit-instructions` for non-memory surfaces; the memory half joins S4's C3 revision. |
| S8 | Repetition gives way to tool descriptions | Task #23 — new locality check in `audit-instructions`, beside I3 and on a different axis from it (I3 is load timing; this is definition-site locality). `OPINION`-tier. |
| S9 | Auto-memory | **Covered** by `claude-memory:audit` / `stateless` and `/memory`. The auto-memory surface itself is audited under task #27. |
| S10 | Rich references, rubrics, verifier agents | Task #25 — deferred with a trigger; nothing is built. Trigger: an official page ranks reference formats or names artifacts as a plan/spec reference destination. |
| S11 | The system prompt | **Excluded — out of reach.** Claude Code's system prompt is not user-modifiable. The local analogue (agent definitions, prompt-type hooks, `--append-system-prompt`) is already inside `audit-instructions`' inventory and inside task #23's placement rule. |
| S12 | CLAUDE.md guidance | **Covered** by `/doctor` and `audit-instructions` I1–I5 routed to `claude-memory`. Verified verbatim against the official include/exclude table. |
| S13 | Skills guidance and the importance carve-out | Task #24 — a stopping condition on checks I6 and I8, `claude-config`-local. Enabled by default despite being `OPINION`-tier, because it withholds findings rather than emitting them. |
| S14 | References | Task #25, with S10 — deferred with a trigger; nothing is built. |
| S15 | Simplify; `claude doctor`; the Fable field guide | Task #15 (closed — both located and read). Ongoing: `criteria.md` already carries a supersession trigger for the model-specific guide. |

---

## S1 — Framing: context is not the prompt

- The user's message is a small part of what Claude receives.
- Context is assembled from the system prompt, Skills, `CLAUDE.md` files, memory, and other sources.
- That assembly is what "context engineering" names, and it drives result quality both in Claude
  Code and in a hand-built agent harness.
- Context is reused across many requests, so it cannot be as specific as a prompt.
- The authoring problem: write general guidance without knowing what the user will ask.
- The problem is moving, because Claude's own capabilities evolve underneath the guidance.

## S2 — The evidence claim and the shipped tool

- A large jump was observed in how the newest Claude models should be prompted.
- Over 80% of Claude Code's system prompt was removed for models like Claude Opus 5 and Claude
  Fable 5, with no measurable loss on Anthropic's coding evaluations.
- The resulting best practices ship inside `claude doctor`; `/doctor` in Claude Code rightsizes
  skills and `CLAUDE.md` files.

## S3 — Unhobbling: over-constraint and conflicting instructions

- Claude Code was over-constrained through its system prompt, and users' `CLAUDE.md` files and
  skills did the same.
- Transcripts of Anthropic's own internal use show conflicting messages inside a single request —
  cited example: "leave documentation as appropriate" against "DO NOT add comments" — as system
  prompt, skills, and the user request clash.
- Claude generally still interprets intent correctly, but must think harder about overlapping and
  conflicting messages before deciding.
- Constraints once needed to avoid worst-case outcomes can now be deleted, letting the model use
  surrounding context and judgement.

## S4 — Unhobbling: new primitives displace CLAUDE.md-as-memory

- Claude Code now has many more tools than when the guidance was written.
- `CLAUDE.md` used to be the source of memory, information, and guidance.
- Memory, artifacts, and skills now give Claude new ways to load and share context across sessions.

## S5 — Then/Now 1: rules give way to judgement

- Early guardrails existed to prevent worst cases such as deleting files, which meant strong
  guidance that was not always true.
- The retired system-prompt text, verbatim: *"In code: default to writing no comments. Never write
  multi-paragraph docstrings or multi-line comment blocks — one short line max. Don't create
  planning, decision, or analysis documents unless the user asks for them — work from conversation
  context, not intermediate files."*
- That guidance is wrong for a subset of prompts: the user may have their own documentation
  preferences, and specific parts of very complex code may need multi-line comment blocks.
- Older models made the tradeoff worth accepting; newer models have better judgement and handle the
  decision without explicit rules.
- The replacement text, verbatim: *"Write code that reads like the surrounding code: match its
  comment density, naming, and idiom."*

## S6 — Then/Now 2: examples give way to interface design

- The number-one rule for tool usage used to be giving Claude examples.
- With the newest models, examples constrain the model to a narrower exploration space.
- Invest instead in the design of tools, scripts, and files: what parameters exist, and how
  expressive they can be.
- Cited example: the Todo tool's `status` enumeration — `pending`, `in_progress`, `completed` —
  hints at correct usage by itself; the instruction to keep one item `in_progress` is what defines
  the requested behavior.

## S7 — Then/Now 3: upfront loading gives way to progressive disclosure

- Because Claude Code was coding-focused, its system prompt carried detailed code-review and
  verification guidance — not always needed, but crucial when it was.
- Claude Code has become competent at progressive disclosure: loading the right context at the
  right time. Verification and code review moved into separately callable skills.
- Progressive disclosure also applies to tools. Some tools are "deferred loading": the agent must
  search for their full definitions with `ToolSearch` before use, so more tools (the Task tools are
  cited) exist without consuming context until needed.
- The same applies to your own `CLAUDE.md` and `SKILL.md`. The myth to reject: that these must be a
  central repository of every practice you *might* run into, because Claude would not find it
  otherwise. The alternative: a tree of files loaded at the right time.

## S8 — Then/Now 4: repetition gives way to simple tool descriptions

- Earlier Claude models sometimes needed repeated instructions, and were more likely to follow
  instructions at the end of their context window than at the start.
- That produced a system prompt carrying tool references that also existed in the tool descriptions.
- Those repeats were deleted; instructions on how to use a tool now live in the tool description
  rather than the system prompt.

## S9 — Then/Now 5: CLAUDE.md memory gives way to auto-memory

- Users were previously encouraged to save things to Claude's memory with the `#` hotkey, which
  writes to `CLAUDE.md` automatically.
- Claude now automatically saves memories relevant to the work and to the user.

## S10 — Then/Now 6: simple specs give way to rich references

- Plan mode leaned heavily on markdown plan files; storing them helped Claude refer back to them.
  The companion practice was storing specs in the codebase for work spanning long projects.
- Claude now handles increasingly complicated references — HTML artifacts created by the artifacts
  feature, rather than simple markdown files.
- References may take the form of code: a spec may be a detailed test suite, or a function in a
  different codebase that Claude is to port.
- Rubrics are another reference form. They let Claude verify the user's taste in a field (the cited
  example is what good API design looks like) by using dynamic workflows to spin up verifier agents
  carrying those rubrics.

## S11 — Applying: the system prompt

- A system prompt is heavily tied to product context: it tells Claude what product it is operating
  in and what it is doing.
- Claude Code users will likely never modify it.
- Authors of their own agent harness should spend a lot of time here.

## S12 — Applying: CLAUDE.md

- Keep it lightweight; briefly describe what the repo is for.
- Spend most of the tokens on gotchas inside the codebase — the cited example is a codebase that
  keeps types in one monolithic file and nowhere else.
- Avoid stating "the obvious": things Claude can learn by looking at the file system or the repo.
- Use progressive disclosure for detail — several unique instructions on verifying work become a
  verification skill referenced from `CLAUDE.md`.

## S13 — Applying: Skills

- Think of skills as lightweight guides that let Claude find information when needed.
- Avoid making them overconstrained, **except in highly important areas**.
- For long skills, use progressive disclosure as much as possible: divide into many files and split
  them out.
- Skills are best when they encode particular opinions, knowledge, or best practices specific to
  you, your team, or your product.

## S14 — Applying: References

- `@` mentioning files includes them as references.
- References let Claude consult in-depth information about the current plan.
- They may be spec files, mockups, or entire codebases.
- Prefer files that are code: it gives clear, high-fidelity instructions in a language Claude knows
  very well.
- An HTML mockup of a design generally produces better results than a prose description or a
  screenshot of it.

## S15 — Closing: try simplifying

- Across system prompt, skills, and `CLAUDE.md` files, you may need to simplify as Anthropic did.
- `claude doctor` was rolled out to help do this automatically.
- The Fable field guide covers prompting more advanced models specifically.
