# Upstream source: "Getting the most out of Opus 5.5 in Claude and Claude Code"

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Row schema](#row-schema)
- [How to ask](#how-to-ask)
- [Steering a long run](#steering-a-long-run)
- [Checking the result](#checking-the-result)
- [In Claude apps](#in-claude-apps)
- [Flagged messages](#flagged-messages)
- [Speed](#speed)
- [Model currency](#model-currency)
- [Decisions and follow-ups](#decisions-and-follow-ups)

This is the provenance record for applying the Opus 5.5 usage guide across this marketplace. It
follows the record pattern set by [aihero-course.md](aihero-course.md) and
[claudedevs-cost-performance.md](claudedevs-cost-performance.md). Each guide item has one row. Each
row either names the surfaces that now carry the guidance, gives evidence that they already did,
or says why the item does not apply to repository instructions.

## Status

Applied 2026-09-23 on branch `feat/apply-opus-5-5-guide`. The work was split into five
compartments with disjoint plugin ownership, each run by its own subagent. The orchestrating session
reviewed each compartment's diff before committing it. Follow-ups that need a model release or
their own session are filed as issues (see [Decisions and follow-ups](#decisions-and-follow-ups)).

## Source and verification

- Pointer for every row: [Prompting Claude Opus 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5)
  on the Claude platform docs, read 2026-09-23. The usage guide by Addy Osmani, published
  2026-09-22: (correlate with `https://claude.dev/blog/getting-the-most-out-of-opus-5-5/`).
- Pointer for model behavior: the Claude Code
  [Model configuration](https://code.claude.com/docs/en/model-config) page, read 2026-09-23 (effort
  defaults, the `opus` alias, `MAX_THINKING_TOKENS`, and
  [Automatic model fallback](https://code.claude.com/docs/en/model-config#automatic-model-fallback)).
- Vendor-reported performance claims are not recorded here; read them at the source.

## Row schema

Each row is an [upstream-drift](../conventions/upstream-drift/README.md#required-parts) record. The
**Topic** column names the guide item in our words, with an ID other files cite; **Ours** and
**Verdict** are our decision. No row restates the guide. Shared for every row:

- **Pointer**: the pages in [Source and verification](#source-and-verification).
- **As of**: 2026-09-23
- **Recheck trigger**: a revised Opus 5.5 prompting page or usage guide, or the next Opus release.

The guide's opening and closing summary sections map onto the rows below and carry no rows of
their own.

## How to ask

| Topic | Ours | Verdict |
|---|---|---|
| G1.1 The finish line in a request | Root `AGENTS.md` stop rule; `harness-config:audit-prompting-postures` P6 (finish line and both kinds of stop); `docs-hygiene:write-for-agents`; dispatch briefs in codebase-health, batch-simplify, coupling, mutation-testing, review:fanout, course-digest, architecture:improve; implementation and planning briefs | ADOPT |
| G1.2 Thinking steers in prompts | `audit-instructions` I8-f (scoped to Opus 5.5 targets, because the Opus 5.5 page and the model-agnostic [Thinking and reasoning](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#thinking-and-reasoning) section disagree on thinking steers) and widened I8-c; `write-for-agents` defers to I8-f for the target model; the one live steer found (event-storming simulation) replaced; boris `autonomy.md` carries an amendment note | ADOPT |
| G1.3 Adding to a running task | A user habit in the Claude Code UI, with no repository instruction to change | N/A |
| G1.4 Excluded design styles | `audit-instructions` I26 extended; visualization, prototype, playgrounds, education (eli5, teach), and adhd:clarify name exclusions, extend the list when the user dislikes a choice, and render again | ADOPT |

## Steering a long run

| Topic | Ours | Verdict |
|---|---|---|
| G2.1 The stops a user wants | Root `AGENTS.md` rule (keep going with status in the same message; stop before destructive or outside-this-checkout actions; keep permission prompts on); postures P6; fable-5 `communication.md`; adhd:shape; knowledge:docpage-digest; implementation:implement-dispatch autonomous mode; autonomy `lane-stop-gate`; session-flow orchestrate and keep-going; the worker and merge lane launch prompts in `prompts/loops/loop-lane-prompts.md`. No existing confirmation gate was weakened. Left by decision: babysit-loop and work-loop (the loop-lane convention keeps those clauses in the launch prompts), continue-in-background (its resume wording is pinned by `save_point.py`) | ADOPT |
| G2.2 Subagent splits and per-result checks | postures P1; review:fanout, mcp-tools:audit, ai-slop rubric fan-out, docs-hygiene:audit-encapsulation, course-digest, discipline fan-out now check each worker's evidence before accepting it. Already present in bugs:scan, codebase-health, plugin-quality, map-corpus, architecture:improve, verification:confirm | ADOPT / COVERED |
| G2.3 A task list kept in a file | Root `AGENTS.md`; postures P9 (an existing ledger counts). Already present in batch-simplify, coupling, docpage-digest, map-corpus, discovery, disk-hygiene, machine-health, unhobble, audit-pass | ADOPT / COVERED |

## Checking the result

| Topic | Ours | Verdict |
|---|---|---|
| G3.1 What the reader must act on, first | Root `AGENTS.md` ("Blocked on me, Changed, Found"); postures P11; reports in bugs, codebase-health, mutation-testing, discovery, architecture, machine-health, batch-simplify, coupling, ai-briefing, harness-config:audit-pass, session-flow (keep-going, reconcile, clean-stop), source-control (babysit-prs, pull-request monitor and readiness), repo-hygiene batch runs, repo-fleet-hygiene apply, work-items drain mode, and the loop-lane launch prompts now lead with what waits on the user. A skill's own report template keeps its headings (for example "Needs you") | ADOPT |
| G3.2 Code review requests | review:code-review and security-review findings carry file and line, the reason it is a defect, and a way to demonstrate the failure; quality-gate PR mode leads with merge-blocking findings; harness-config:audit-automation-gaps. The CI lane keeps its "block or flag" bar by decision | ADOPT |
| G3.3 Unconfirmed claims | dometrain grounding added. Already present in discovery research and trace-intent, github:audit, ai-briefing, postures P4 and P5 | ADOPT / COVERED |

## In Claude apps

| Topic | Ours | Verdict |
|---|---|---|
| G4.1 Visual inputs | playwright reads the screenshot file for visual questions. Already present in computer-use and the knowledge video and course digests | ADOPT / COVERED |
| G4.2 Long-document consistency checks | review `doc-drift-detector` checks for self-contradicting numbers, dates, and names, quoting both locations | ADOPT |
| G4.3 Finished files over outlines | wizard already produces the finished script; no skill here returns an outline where a file is wanted | COVERED |
| G4.4 Settled answers | `audit-instructions` I35 flags the instruction on analysis and agentic surfaces, where later steps may expose an earlier error. No repository surface is a long-chat project | ADOPT (audit only) |

## Flagged messages

| Topic | Ours | Verdict |
|---|---|---|
| Fallback on a flagged message | `opus-5-5.md` records the fallback targets; fable-5 meta-rule 3 re-resolves the adaptation chapter against the model now answering; harness-ops known-issues covers the switch-back steps | ADOPT |
| G5.1 Reasoning shown in the reply | `audit-instructions` I10 widened to Opus 5.5 targets; `write-for-agents` never asks the model to write out its hidden thinking; prompts/loops ask for a one-line rationale instead of "your reasoning" | ADOPT |

## Speed

| Topic | Ours | Verdict |
|---|---|---|
| G6.1 Fast mode | Recorded in `opus-5-5.md`. A per-session user choice with extra cost, so no skill turns it on | ADOPT (chapter only) |

## Model currency

| Topic | Ours | Verdict |
|---|---|---|
| The current Opus and the `opus` alias (pointer: [Model aliases](https://code.claude.com/docs/en/model-config#model-aliases), as of 2026-09-23) | New `plugins/playbooks/reference/model-adaptation/opus-5-5.md`; live docs (official-docs, plugin-philosophy, loop-lane README) updated | ADOPT |
| Opus 5 and Opus 4.8 chapters | Kept while they are fallback targets for a flagged request (pointer: [Automatic model fallback](https://code.claude.com/docs/en/model-config#automatic-model-fallback), as of 2026-09-28). Each chapter carries its own record of this at its top. #4349 stays open until that section no longer names them | KEEP, TRACK #4349 |

## Decisions and follow-ups

Decisions made by the owner on 2026-09-23:

- `review:code-review` keeps its "block or flag" bar; each finding gains file and line, the reason
  it is a defect, and a way to demonstrate the failure.
- The visualization chrome keeps its off-white background and monospace labels as the house look;
  its exclusion list names only the habits the chrome does not set.
- The `audit-instructions` think-carefully row (I8-f) stays scoped to Opus 5.5 targets.

Filed:

- #4346 regenerate the fable-5 doctrine for Fable 5.1.
- #4347 Sonnet 5.5 adaptation chapter, on release.
- #4348 Haiku 5.5 adaptation chapter, on release.
- #4349 retire the Opus 5 and Opus 4.8 chapters once they stop being fallback targets
  (open: as of 2026-09-28 the trigger has not fired; recheck when model-config "Automatic
  model fallback" no longer names them).
- #4351 three skill descriptions over the 1024-codepoint limit (already on `main`).
