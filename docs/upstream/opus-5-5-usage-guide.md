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

- Guide: `https://claude.dev/blog/getting-the-most-out-of-opus-5-5/`, by Addy Osmani, published
  2026-09-22, read 2026-09-23.
- Primary docs used alongside it, read 2026-09-23: the "Prompting Claude Opus 5.5" guide on the
  Claude platform docs, and the Claude Code model-config page (effort defaults, the `opus` alias,
  `MAX_THINKING_TOKENS`, and the "Automatic model fallback" section).
- Vendor-reported claims (for example, that Opus 5.5 at its lowest effort caught more bugs than
  Opus 5 at high effort) are recorded as vendor-reported, not as verified facts.

## Row schema

Each row is a four-part record per
[docs/conventions/upstream-drift/README.md](../conventions/upstream-drift/README.md): the claim, the
basis it was derived against, the as-of date, and a recheck trigger. Shared basis for every row
below: the guide as read 2026-09-23. Shared recheck trigger: a revised Opus 5.5 guide, or the next
Opus release.

The guide's "Try this first" items and closing checklist restate the sections below, so they carry
no rows of their own: handing over the whole task maps to G1.1 and G2.1, deleting think-carefully
lines to G1.2, and reading what it needs from you first to G3.1. Each checklist line maps to G1.1,
G1.2, G1.4, G4.1, G2.1 to G2.3, G3.1 to G3.3, or the fallback row.

## How to ask

| Guide item | Ours | Verdict |
|---|---|---|
| G1.1 Say what "done" looks like, then let it run | Root `AGENTS.md` stop rule; `claude-config:audit-prompting-postures` P6 (finish line and both kinds of stop); `docs-hygiene:write-for-agents`; dispatch briefs in codebase-health, batch-simplify, coupling, mutation-testing, review:fanout, course-digest, architecture:improve; implementation and planning briefs | ADOPT |
| G1.2 Stop telling it to "think hard" | `audit-instructions` I8-f (scoped to Opus 5.5 targets, because the model-agnostic best-practices page still recommends thinking steers) and widened I8-c; `write-for-agents` defers to I8-f for the target model; the one live steer found (event-storming simulation) replaced; boris `autonomy.md` carries an amendment note | ADOPT |
| G1.3 Add to a running task | A user habit in the Claude Code UI, with no repository instruction to change | N/A |
| G1.4 Name the design styles to leave out | `audit-instructions` I26 extended; visualization, prototype, playgrounds, education (eli5, teach), and adhd:clarify name exclusions, extend the list when the user dislikes a choice, and render again | ADOPT |

## Steering a long run

| Guide item | Ours | Verdict |
|---|---|---|
| G2.1 Tell it which stops you want | Root `AGENTS.md` rule (keep going with status in the same message; stop before destructive or outside-this-checkout actions; keep permission prompts on); postures P6; fable-5 `communication.md`; adhd:shape; knowledge:docpage-digest; implementation:implement-dispatch autonomous mode; autonomy `lane-stop-gate`; session-flow orchestrate and keep-going; the worker and merge lane launch prompts in `prompts/loops/loop-lane-prompts.md`. No existing confirmation gate was weakened. Left by decision: babysit-loop and work-loop (the loop-lane convention keeps those clauses in the launch prompts), continue-in-background (its resume wording is pinned by `save_point.py`) | ADOPT |
| G2.2 Split big work across subagents and check each result | postures P1; review:fanout, mcp-tools:audit, ai-slop rubric fan-out, docs-hygiene:audit-encapsulation, course-digest, discipline fan-out now check each worker's evidence before accepting it. Already present in bugs:scan, codebase-health, plugin-quality, map-corpus, architecture:improve, verification:confirm | ADOPT / COVERED |
| G2.3 Keep the task list in a file | Root `AGENTS.md`; postures P9 (an existing ledger counts). Already present in batch-simplify, coupling, docpage-digest, map-corpus, discovery, disk-hygiene, machine-health, unhobble, audit-pass | ADOPT / COVERED |

## Checking the result

| Guide item | Ours | Verdict |
|---|---|---|
| G3.1 Read what it needs from you first | Root `AGENTS.md` ("Blocked on me, Changed, Found"); postures P11; reports in bugs, codebase-health, mutation-testing, discovery, architecture, machine-health, batch-simplify, coupling, ai-briefing, claude-config:audit-pass, session-flow (keep-going, reconcile, clean-stop), source-control (babysit-prs, pull-request monitor and readiness), repo-hygiene batch runs, repo-fleet-hygiene apply, work-items drain mode, and the loop-lane launch prompts now lead with what waits on the user. A skill's own report template keeps its headings (for example "Needs you") | ADOPT |
| G3.2 Ask it to review the code | review:code-review and security-review findings carry file and line, why it is wrong, and how to show it fails; quality-gate PR mode leads with merge-blocking findings; claude-config:audit-automation-gaps. The CI lane keeps its "block or flag" bar by decision | ADOPT |
| G3.3 Mark what it couldn't confirm | dometrain grounding added. Already present in discovery research and trace-intent, github:audit, ai-briefing, postures P4 and P5 | ADOPT / COVERED |

## In Claude apps

| Guide item | Ours | Verdict |
|---|---|---|
| G4.1 Share the chart or screenshot itself | playwright reads the screenshot file for visual questions. Already present in computer-use and the knowledge video and course digests | ADOPT / COVERED |
| G4.2 Ask it to check a long document | review `doc-drift-detector` checks for self-contradicting numbers, dates, and names, quoting both locations | ADOPT |
| G4.3 Ask for the finished file | wizard already produces the finished script; no skill here returns an outline where a file is wanted | COVERED |
| G4.4 Say when answers are settled | `audit-instructions` I35 flags the instruction on analysis and agentic surfaces, where a later step can show an earlier mistake. No repository surface is a long-chat project | ADOPT (audit only) |

## Flagged messages

| Guide item | Ours | Verdict |
|---|---|---|
| Fallback on a flagged message | `opus-5-5.md` records the fallback targets; fable-5 meta-rule 3 re-resolves the adaptation chapter against the model now answering; claude-ops known-issues covers the switch-back steps | ADOPT |
| G5.1 Don't ask it to show its reasoning in the reply | `audit-instructions` I10 widened to Opus 5.5 targets; `write-for-agents` never asks the model to reproduce its reasoning; prompts/loops ask for a one-line rationale instead of "your reasoning" | ADOPT |

## Speed

| Guide item | Ours | Verdict |
|---|---|---|
| G6.1 Fast mode | Recorded in `opus-5-5.md`. A per-session user choice with extra cost, so no skill turns it on | ADOPT (chapter only) |

## Model currency

| Claim | Ours | Verdict |
|---|---|---|
| Opus 5.5 is the current Opus; `opus` resolves to it | New `plugins/playbooks/reference/model-adaptation/opus-5-5.md`; live docs (official-docs, plugin-philosophy, loop-lane README) updated | ADOPT |
| Opus 5 and Opus 4.8 chapters | Kept: per model-config, flagged Fable 5.1, Fable 5, and Opus 5.5 requests re-run on Opus 5 (biology) or Opus 4.8 (cybersecurity). Each chapter states this at its top | KEEP, TRACK #4349 |

## Decisions and follow-ups

Decisions made by the owner on 2026-09-23:

- `review:code-review` keeps its "block or flag" bar; each finding gains the guide's evidence.
- The visualization chrome keeps its off-white background and monospace labels as the house look;
  its exclusion list names only the habits the chrome does not set.
- The `audit-instructions` think-carefully row (I8-f) stays scoped to Opus 5.5 targets.

Filed:

- #4346 regenerate the fable-5 doctrine for Fable 5.1.
- #4347 Sonnet 5.5 adaptation chapter, on release.
- #4348 Haiku 5.5 adaptation chapter, on release.
- #4349 retire the Opus 5 and Opus 4.8 chapters once they stop being fallback targets.
- #4351 three skill descriptions over the 1024-codepoint limit (already on `main`).
