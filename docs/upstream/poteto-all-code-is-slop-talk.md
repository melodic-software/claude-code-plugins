# Upstream source: the "All Code Is Slop (Except Mine)" talk (Lauren Tan, poteto)

## Contents

- [Source and audit](#source-and-audit)
- [Her thesis](#her-thesis)
- [How to read the rows](#how-to-read-the-rows)
- [1. Opening (slides 1 to 5)](#1-opening-slides-1-to-5)
- [2. Trust model (slides 6 to 11)](#2-trust-model-slides-6-to-11)
- [3. Code is memory (slides 12 to 16)](#3-code-is-memory-slides-12-to-16)
- [4. Examples (slides 17 to 19)](#4-examples-slides-17-to-19)
- [5. Escape hatches (slides 20 to 22)](#5-escape-hatches-slides-20-to-22)
- [6. Corrections (slide 23)](#6-corrections-slide-23)
- [7. Verification (slides 24 to 28)](#7-verification-slides-24-to-28)
- [8. Why now (slides 29 to 32)](#8-why-now-slides-29-to-32)
- [9. Results (slides 33 to 38)](#9-results-slides-33-to-38)
- [10. Order of work (slides 39 to 44)](#10-order-of-work-slides-39-to-44)
- [Framing](#framing)
- [Her terms](#her-terms)
- [What the talk shows that her plugin does not contain](#what-the-talk-shows-that-her-plugin-does-not-contain)

This page records, for every idea in one conference talk, what this marketplace did with it. Her
`pstack` plugin has its own record, [`cursor-pstack.md`](cursor-pstack.md); a row here that touches
one of her skills points there instead of repeating it. Every decision below was made on the
decision map
[Map: integrate the 'All Code Is Slop (Except Mine)' talk into plugins and skills](https://github.com/melodic-software/claude-code-plugins/issues/15651),
whose body lists the chapters, constraints and decided work items and whose closing comment states
all 17 decisions.

## Source and audit

- **Talk**: "All Code Is Slop (Except Mine)", Lauren Tan (poteto), AI Engineer Code Summit,
  2026-11-11: the segment from 1:00:18 to 1:18:25 of the
  [day-one stream](https://www.youtube.com/watch?v=ZZ19zhYnDKY&t=3618s), 44 slides. Times below
  are stamps in that full video.
- **What we read**: our transcript, a re-transcription of its last minute, and slide-by-slide frame
  descriptions, in `melodic-software/knowledge-corpus` under
  [`sources/videos/all-code-is-slop-except-mine-lauren-tan-ZZ19zhYnDKY/`](https://github.com/melodic-software/knowledge-corpus/tree/main/sources/videos/all-code-is-slop-except-mine-lauren-tan-ZZ19zhYnDKY)
  (`transcript/transcript.txt`, `transcript/transcript-tail-1-17-20.txt`, `frames/visual-frames.md`).
  Read there, not here, for anything she said or showed.
- **When**: audited 2026-11-12 and 2026-11-13 through the decision map above, which closed on
  2026-11-13; a row-by-row coverage audit that day found every slide and term with an outcome once
  the owner settled its last gaps.
- **Recheck**: a recording does not change, and this page stores no number or string from the talk,
  so under the [upstream-drift contract](../contracts/upstream-drift/README.md#required-parts) it is
  a record of decisions with pointers and carries no as-of date or recheck trigger. A row whose
  decision has its own reopen condition states it as a named trigger.
- **Tracker states** (open, closed, merged) were read on 2026-11-13; the linked item holds the live
  state.
- **Her figures** (pull request counts, releases, contributors, revert rate, performance deltas, the
  share of tokens spent on verification) are not recorded; read them on the slides.

## Her thesis

With agents, the volume of code stops being the limit and trust becomes it. Trust is bought by
investing in the agent's environment, cheapest and most reliable layer first: the shape of the code,
deterministic checks, verification, written rules, and human review last. Every correction becomes a
check, review moves from diffs to evidence, and only a loop that already produces good work is worth
automating.

## How to read the rows

Each row names one idea in talk order, in our words, with its slide number and time. A slide title
appears in quotes only when it is four words or fewer. Dispositions:

- **Take**: we decided to build it; the row links the work item or the merged pull request.
- **Already have**: the row names the skill or file that does it.
- **Declined** or **Skipped**: the row gives the reason.
- **Out of scope**: her internal product, her numbers, or a rule that belongs to a consumer.
- **Framing**: nothing to integrate; listed once under [Framing](#framing).

The constraints cited as C1 to C11 are in the map's Notes; the Brief questions cited as Q1 to Q45
are in the resolution of
[What did the interview on the talk already settle?](https://github.com/melodic-software/claude-code-plugins/issues/15652).

## 1. Opening (slides 1 to 5)

Slides 1, 2, 4 and 5 are framing.

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 3 (1:02:10) | Her own monthly pull request count as evidence that volume is now possible | Out of scope: her numbers are unverifiable from outside and are not targets here | Map Out-of-scope |

## 2. Trust model (slides 6 to 11)

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 6, 7 (1:02:58, 1:03:14) | Two loops: a human checks the agent's work (low trust), or the agent checks it itself (high trust) | Already have: `/verification:confirm` proves a change before anyone reviews it. Take: review findings a run reproduced, as a fan-out setting | [Let the review fan-out label or require findings a run reproduced, under one shared rule for running reviewed code](https://github.com/melodic-software/claude-code-plugins/issues/15833) (open, awaiting its interview) |
| 8 (1:03:26) | An inverted pyramid ranking where to invest: codebase, static analysis, verification, prose, human review at the tip | Take: the enforcement ladder ([`plugins/review/context/enforcement-ladder.md`](../../plugins/review/context/enforcement-ladder.md)) is the one representation of the pyramid (Q11): capability-named rungs, a verification tier, the proportion in words (Q12), and every skill that places enforcement held to it (C8) | [Release enforcement ladder 3.0.0 with the verification tier and capability-named rungs](https://github.com/melodic-software/claude-code-plugins/issues/15708) (open), under [Resolve ecosystem specifics from the consumer repository and align the enforcement ladder with the talk's pyramid](https://github.com/melodic-software/claude-code-plugins/issues/15703) (open) |
| 9 (1:03:38) | The top two layers (code shape, then machine checks including tests and CI) are deterministic and constrain agents by default | Already have: the ladder's Tier 1 Codebase and Tier 2 Static analysis. Take: executed adapters stay while model-read tool choices leave skills (Q2, Q3); the contract and its review rules are merged | [docs(contracts): add the ecosystem-resolution contract, ADR 0101 and the review rules](https://github.com/melodic-software/claude-code-plugins/pull/15846) (merged); rest under [#15703](https://github.com/melodic-software/claude-code-plugins/issues/15703) |
| 10 (1:04:02) | Verification, runtime and formal, checks invariants and whether the agent understood the intent | Take: a verification tier in third place, after codebase and static analysis (Q37), with runtime-verification and formal-verification rungs | [#15708](https://github.com/melodic-software/claude-code-plugins/issues/15708) (open) |
| 11 (1:04:18) | Prose (rules, skills, AGENTS.md) is the layer for judgment calls only | Already have: the ladder's Guidance tier. Take: the retro asks whether a check could decide a finding before it proposes a prose rule | [Ask whether a check could decide a retro finding before proposing a prose rule](https://github.com/melodic-software/claude-code-plugins/issues/15935) (open); [pull request #15961](https://github.com/melodic-software/claude-code-plugins/pull/15961) (open, held for its eval compare) |

## 3. Code is memory (slides 12 to 16)

Slides 13 and 14 are framing.

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 12 (1:04:26) | "code is memory": the codebase is the agent's largest input, so fix a correction in code, not in another rule | Already have: the ladder section [The codebase and its history are the memory](../../plugins/review/context/enforcement-ladder.md#the-codebase-and-its-history-are-the-memory); `/corrections:codify` turns a correction into a check (slide 23) | [`plugins/corrections/skills/codify/SKILL.md`](../../plugins/corrections/skills/codify/SKILL.md) |
| 15 (1:05:58) | A workaround spreads because each copy looks like the house pattern | Already have: `/toolchain:ratchet` freezes a count so it cannot grow; the code-tidying plugin removes old patterns | [`plugins/toolchain/skills/ratchet/`](../../plugins/toolchain/skills/ratchet/SKILL.md) |
| 16 (1:06:14) | A human should still read the code now and then | Already have (owner, 2026-11-13): `/review:explain-change` walks a reader through a pull request; `/education:quiz-me` checks the reader understood it | [`plugins/review/skills/explain-change/`](../../plugins/review/skills/explain-change/SKILL.md), [`plugins/education/skills/quiz-me/`](../../plugins/education/skills/quiz-me/SKILL.md) |

## 4. Examples (slides 17 to 19)

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 17 (1:06:34) | Dune, her team's client framework, carrying one folder per feature, import bans and no code comments | Out of scope by name (internal framework). Its three constraints are the rows for slide 19 (folders, import bans) and slide 22 (comments) | Map Out-of-scope |
| 18 (1:07:06) | APIs that need nuance produce slop; her team banned one React hook in product code and designed better APIs instead | Out of scope: banning one API in a shared plugin is a consumer's rule, reached through `/corrections:codify` and `/implementation:implement` in the consumer's own linter (C2). Already have: designing the problem away is the ladder's Tier 1 Codebase | Map Out-of-scope |
| 19 (1:07:38, 1:08:02) | Directory names as context: two top-level folders with imports between them banned, and a file suffix marking per-tick code | Declined as shipped conventions; take a style-agnostic layout lens that checks whether files that change together live together. A consumer's own import ban is a check built through `/corrections:codify` and `/implementation:implement` (C2) | [Should folder-per-feature and file-suffix conventions be offered as derivable conventions?](https://github.com/melodic-software/claude-code-plugins/issues/15660) (closed); [Add a layout lens to architecture:improve that checks whether files that change together live together](https://github.com/melodic-software/claude-code-plugins/issues/15811) (open, awaiting its interview) |

## 5. Escape hatches (slides 20 to 22)

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 20 (1:08:26) | Agents write markdown nobody asked for (docs, comments, rules, skills) to justify a shortcut or to harden one small correction into a permanent rule; a cartoon agent invents a source | Declined: a write-time flag on a new markdown file, because a hook cannot tell whether the task asked for the file. Named trigger: reopen when an unrequested file is found merged. The rest (justifications in rules or skills, the invented source) is already covered: the owner judged her point to be mostly the comment ban (slide 22) | [Should a plugin flag a new markdown file the task did not ask for, at write time?](https://github.com/melodic-software/claude-code-plugins/issues/15654) (closed) |
| 21 (1:09:06) | Timer calls used as quick fixes over an architecture mismatch, defended in comments and copied until they spread | Already have: `/debugging:debug` writes a test that fails on the reported case, takes its expected value from the report, and then removes the root cause ([`plugins/debugging/skills/debug/SKILL.md`](../../plugins/debugging/skills/debug/SKILL.md), "With a correct seam"); the owner: "write a test for the bug before it's fixed". A banned API is a consumer's lint rule (slide 18 row); spreading copies are slide 15; the comments are slide 22 | Owner decision on the coverage gaps, 2026-11-13 |
| 22 (1:10:06) | "comments are liabilities": her team banned nearly all comments because they go stale, cannot be enforced and excuse shortcuts; her lint messages point the agent at the underlying problem | Take: no comments as the owner's and this repository's posture, with plugins shipping the keep-the-why default and the no-comments posture as a supported setting (C5). Already have: `/code-tidying:remove-comments` with `comment_posture: none`; its root-cause and reshape findings go to a findings file. Lint messages that name the fix are slide 23. Her `/no-comments` skill: see [`cursor-pstack.md`](cursor-pstack.md) | [Adopt the no-comments posture here and support it as a plugin setting](https://github.com/melodic-software/claude-code-plugins/issues/15647) (open, awaiting its interview); [Write remove-comments' root-cause and reshape findings to a findings file the fix skills can read](https://github.com/melodic-software/claude-code-plugins/issues/15841) (closed) |

## 6. Corrections (slide 23)

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 23 (1:10:46) | Every time a human corrects the agent, the correction becomes a deterministic check or the problem is designed away | Already have: `/corrections:codify` picks the strongest rung that can catch a correction and proves the check fails on the old code; `/implementation:implement` builds it in the consumer's tooling (C2) | [`plugins/corrections/skills/codify/SKILL.md`](../../plugins/corrections/skills/codify/SKILL.md) |
| 23 | A check's message names the fix | Take: every finding names a root-cause remedy first, covered checks are tested for it, and this repository's check scripts are held by a ratchet until none lacks one | [Should a check's output have to name the fix, and be tested for it?](https://github.com/melodic-software/claude-code-plugins/issues/15653) (closed) |
| 23 | Her running count of checks grows month by month | Take: count corrections that became checks and generate a rule-to-enforcer inventory | [Count corrections that became checks and generate the rule-to-enforcer inventory](https://github.com/melodic-software/claude-code-plugins/issues/15650) (open, awaiting its interview) |
| 23 | Applied to ourselves: this repository's own checkable prose rules become checks | Take, done: five checks plus the force-push alignment. Four rules with no violations and no fix history are skipped until a first violation | [Which of this repository's own checkable prose rules should get a check?](https://github.com/melodic-software/claude-code-plugins/issues/15663) (closed); merged: [ci: run the rules-index check on every pull request](https://github.com/melodic-software/claude-code-plugins/pull/15965), [ci: check that an as-of date in a skill file carries a recheck trigger](https://github.com/melodic-software/claude-code-plugins/pull/15989), [feat(ci): report a Follow-ups bullet without the advisory marker](https://github.com/melodic-software/claude-code-plugins/pull/16008), [feat(scripts): flag docs-page links with no section anchor in skill and agent files](https://github.com/melodic-software/claude-code-plugins/pull/15960), [ci: fail a price or savings figure in skills, docs and prompts](https://github.com/melodic-software/claude-code-plugins/pull/16022), [feat(guardrails): make the unpinned force-with-lease a setting; this repository blocks it](https://github.com/melodic-software/claude-code-plugins/pull/15968) |
| 23 | Applied to the owner's own instructions: checkable dotfiles rules become hooks or permission rules | Take, done in this repository: the foreground-wait hook and the stale guard comments. The dotfiles changes are built in the dotfiles repository, recorded on [dotfiles #1556](https://github.com/melodic-software/dotfiles/issues/1556) | [Which low-friction checkable dotfiles rules should become hooks or permission rules?](https://github.com/melodic-software/claude-code-plugins/issues/15665), [Should the dotfiles instructions drop the stale multi-line commit message rule?](https://github.com/melodic-software/claude-code-plugins/issues/15664), [Should the unproven "redirects under the work directory are blocked" reason be verified or deleted?](https://github.com/melodic-software/claude-code-plugins/issues/15666) (all closed); merged: [feat(guardrails): block foreground until loops and --watch waits](https://github.com/melodic-software/claude-code-plugins/pull/15955), [docs(guardrails): drop the removed block-hook-bypass guard from hook comments](https://github.com/melodic-software/claude-code-plugins/pull/15954); open: [Let a repository choose which guardrails hooks deny the call when they crash](https://github.com/melodic-software/claude-code-plugins/issues/15992) |

## 7. Verification (slides 24 to 28)

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 24 (1:11:10) | Review now means looking at verification artifacts (videos, screenshots, diagrams, formal results) rather than diffs | Already have: one evidence comment on the pull request after a confirmed head. Take: the local ready step posts it too. For a plugin pull request, evidence means that comment plus the eval compare on any change to skill text | [Should verification artifacts be shown in the pull request where a reviewer sees them?](https://github.com/melodic-software/claude-code-plugins/issues/15658) (closed); [Post the evidence comment from the ready step once the head is confirmed](https://github.com/melodic-software/claude-code-plugins/issues/15787) (open) |
| 25 (1:11:34) | Runtime verification: the agent runs the app itself, guided by a feature map from the user's side (each feature, the path a user takes to it, and the evidence that it works) | Already have: `/app-control:map` and `/app-control:drive`, with feature files written from the user's side ([`plugins/app-control/reference/control-skill.md`](../../plugins/app-control/reference/control-skill.md#feature-files)) and `sources` globs that let upkeep classify a change. Take: every drive step states its observable result, each feature ends with a proof step, and app-control is aligned with her verification skills in five items. Her `/create-verification-skill`: see [`cursor-pstack.md`](cursor-pstack.md) | [Should the feature map name a "what proves it works" part?](https://github.com/melodic-software/claude-code-plugins/issues/15659) and [Should each verification check record the files it covers, so upkeep can classify a change?](https://github.com/melodic-software/claude-code-plugins/issues/15656) (closed); open: [State the observable result on every drive step and end each feature with a proof step](https://github.com/melodic-software/claude-code-plugins/issues/15797), [Require preconditions and per-step evidence in control skills, and never weaken a journey to pass](https://github.com/melodic-software/claude-code-plugins/issues/15800), [Record how a control skill's app is launched and isolated, and make ready mean usable from empty data](https://github.com/melodic-software/claude-code-plugins/issues/15798), [Bring the control-skill refresh in line with her upkeep pass](https://github.com/melodic-software/claude-code-plugins/issues/15801); closed: [Add driving conventions and control-tool traits to the control-skill contract](https://github.com/melodic-software/claude-code-plugins/issues/15799) |
| 25 | The feature map gives the human and the agent shared names for parts of the app | Already covered (owner, 2026-11-13): the glossary work taken from Matt Pocock's domain-language course gives a shared language the feature map and the verification skills can use; the owner: "We're building out Matt Pocock's glossary" | [`aihero-domain-language.md`](aihero-domain-language.md) |
| 26 (1:12:06) | A small control CLI inside the verification skill, reused by every agent to drive the app, so runs are cheaper and testable | Already have: each control skill ships its own driver CLI ([`control-skill.md`, "Writing the driver CLI"](../../plugins/app-control/reference/control-skill.md#writing-the-driver-cli)) and `/app-control:drive` runs it; the control-tool traits landed with [#15799](https://github.com/melodic-software/claude-code-plugins/issues/15799). Her own CLI is out of scope by name | [`plugins/app-control/skills/drive/`](../../plugins/app-control/skills/drive/SKILL.md) |
| 26 | Driving this repository's own skills as the app | Take: `/app-control:drive` resolves a plugin's skill by its documented `<plugin>/<skill>` id here | [Make app-control:drive resolve a plugin's skill by its documented <plugin>/<skill> id in this repository](https://github.com/melodic-software/claude-code-plugins/issues/16007) (open) |
| 27 (1:12:26) | Formal verification: model checking major user flows in TLA+, proofs of one algorithm in Lean; one more layer, not a cure-all | Take: a formal-verification plugin absorbing her three formal-verification skills in three slices; the model-replay rule lives there, and the rule to suspect the observation method first goes once in `/verification:confirm`. Out of scope: TLA+ or Lean as a default step; the tool is opt-in, chosen by the question. Her skills: see [`cursor-pstack.md`](cursor-pstack.md) | [Add the formal-verification plugin's chart skill, setup and consumer contract, proven on the loop-lane claim protocol](https://github.com/melodic-software/claude-code-plugins/issues/15648), [Add the formal-verification specify skill's propose, create and check forms](https://github.com/melodic-software/claude-code-plugins/issues/15773), [Add the formal-verification specify skill's refresh action](https://github.com/melodic-software/claude-code-plugins/issues/15775) (open, awaiting their interviews); [Suspect the observation method first when a verification fails in verification:confirm](https://github.com/melodic-software/claude-code-plugins/issues/15776) (open); [Should we adopt her two one-line verification rules, and in which skills?](https://github.com/melodic-software/claude-code-plugins/issues/15657) (closed) |
| 28 (1:13:02) | Property-based testing of the UI with random input, through a third-party library | Take: property testing and flood-style fuzzing are one guidance in `/testing:write` ([`context/property.md`](../../plugins/testing/skills/write/context/property.md)), covering every target. The library is not named: skills ship no tool choice (C1) | [Say in the property guidance that it covers every target and that fuzzing follows it](https://github.com/melodic-software/claude-code-plugins/issues/15825) (open) |

## 8. Why now (slides 29 to 32)

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 29, 30 (1:13:18, 1:13:34) | Two posts by Cindy Sridharan, six months apart: subtle bugs merged before she had a verification process, and most of her token spend going to verification after | Skipped: evidence for the verification tier, not a budget target; no figure recorded | Owner decision on the coverage gaps, 2026-11-13 |
| 31 (1:13:58) | Sridharan's chart of test techniques by stage: none new, but agents make them affordable | Take, done: no technique-coverage lens; `/testing:plan` gains a fuzz-target row and a consumer-driven contract-test row | [Which test-stage chart techniques apply to what consumers of a plugin marketplace build?](https://github.com/melodic-software/claude-code-plugins/issues/15667) (closed); [feat(testing): plan fuzz targets and consumer-driven contract tests in testing:plan](https://github.com/melodic-software/claude-code-plugins/pull/15678) (merged) |
| 32 (1:14:18) | Her new statechart skill draws a checked state machine from the user's side, reviewed beside videos and screenshots | Take: the formal-verification plugin's chart skill. Her `/statechart`: see [`cursor-pstack.md`](cursor-pstack.md) | [#15648](https://github.com/melodic-software/claude-code-plugins/issues/15648) (open, awaiting its interview) |

## 9. Results (slides 33 to 38)

Slide 33 is framing.

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 34 (1:14:58) | Her team's monthly merged pull requests | Out of scope: her numbers as targets | Map Out-of-scope |
| 35 (1:15:10) | Desktop releases per month and time between releases | Out of scope as a target. The release cadence matters only as the trigger of the release pass (slide 43) | Map Out-of-scope |
| 36 (1:15:26) | Contributors per month, split into core, casual and drive-by | Out of scope: her numbers as targets | Map Out-of-scope |
| 37 (1:15:42) | Share of commits reverted, falling then flat | Already have: the revert rate through `/work-items:measure-delivery`. The no-human-touch share is computable only as a lower bound (signal: the Claude co-author trailer); corrections that became checks are counted by [#15650](https://github.com/melodic-software/claude-code-plugins/issues/15650). No other trust measure for now. Named trigger: revisit in the interview on #15650 | [Which trust measures can this repository compute today?](https://github.com/melodic-software/claude-code-plugins/issues/15668) (closed) |
| 38 (1:16:10) | Her app's performance before and after the pull request surge | Out of scope: her slide also shows four measures that got worse | Map Out-of-scope |

## 10. Order of work (slides 39 to 44)

Slides 40 and 44 are framing.

| Slide | What she shows or says | Disposition | Where |
|---|---|---|---|
| 39 (1:16:34) | Before automating: lint against new cases of a bad pattern, clean up the old ones, then strengthen verification | Take: the ladder states her order of work: lint first, clean up, strengthen verification, then automate (AC2). Already have: blocking new cases while old ones remain is `/toolchain:ratchet` | [#15708](https://github.com/melodic-software/claude-code-plugins/issues/15708) (open) |
| 41 (1:17:14) | Automating a loop that produces slop only multiplies it; improve the loop first | Take: the same order-of-work rule, whose last step is automation | [#15708](https://github.com/melodic-software/claude-code-plugins/issues/15708) (open) |
| 42 (1:17:34) | An outer loop: events (posts, tickets, chat messages, schedules, alerts) start agent runs through a shared team bot | Already have: issue-event lanes and scheduled routines ([loop-lane convention](../contracts/loop-lane/README.md#1-three-session-topology)). Declined for now: alert and chat-message triggers and a shared team bot; the owner: a connector is "just a Claude agent with MCP tools", and the outer loop must not be "locked into a specific Claude account"; it may be explored later. Out of scope: her product by name. The release trigger is slide 43 | Owner decision on the coverage gaps, 2026-11-13 |
| 43 (1:17:58) | Each release starts agents that use the whole build like a user, report bugs split into new and pre-existing, then open and merge fixes | Take: a whole-map live verification pass at each plugin release that drives every entry of this repository's control skill, no new skill; its report marks each finding new, pre-existing or gone against the last release, keyed by feature-map entry. Severity keeps our four levels (`plugins/bugs/skills/write/SKILL.md`). Ordering new first, merging duplicate pairs and checking build identity are questions in the open interview. Auto-merging the resulting fixes: not recorded | [Run a whole-map live verification pass on each release and report what is new since the last release](https://github.com/melodic-software/claude-code-plugins/issues/15649) (open, awaiting its interview); [Should the release exploring run keep a per-release baseline and report only new findings?](https://github.com/melodic-software/claude-code-plugins/issues/15655) (closed) |

## Framing

Named, nothing to integrate:

- Slides 1 (title), 2 (the same practices called craft when ours and slop when theirs), 4 ("quality & quantity": anyone can be a high-output engineer; her thesis, recorded above), 5 (trust needed grows with the number of agents), 13 and 14 (the codebase as a garden, "Organic Architecture"), 33 ("ok so what"), 40 (whether to automate writing and shipping code), 44 (closing).
- Terms: slop, gardening, coding machine.
- Spoken only: the host's introduction before slide 1, her six months of work before she could ship in her sleep (1:03:05), and the jump from a few colleague pull requests a day in 2024 to hundreds (1:05:04).

## Her terms

Each term from our glossary of the talk, with the row that holds its disposition.

| Term | Disposition |
|---|---|
| slop | Framing |
| trust | Slides 6, 7 and 37 |
| the pyramid and its layers (codebase, static analysis, verification, prose, human review) | Slides 8 to 11; human review is the ladder's Human only tier, and her shrinking of review to evidence is slide 24 |
| deterministic layers | Slide 9 |
| code is memory | Slide 12 |
| gardening, organic architecture | Framing |
| categorically eliminate | Slide 18 (the ladder's Tier 1 Codebase) |
| nuance leads to slop | Slide 18 |
| directory structure is context | Slide 19 |
| escape hatch | Her sense (prose that excuses a shortcut): slides 20 to 22. Her plugin's other sense, a permitted stop with a write-up on an overnight run: already covered by the lanes' stop rules ([loop-lane, "Loop-layer invariants"](../contracts/loop-lane/README.md#4-loop-layer-invariants), [When work stops for the owner](../contracts/loop-lane/README.md#when-work-stops-for-the-owner)); the owner also noted that `/goal` ends through stop hooks |
| unsolicited markdown | Slide 20 |
| quick fixes considered harmful | Slide 21 |
| the comment ban | Slide 22 |
| correction becomes a check | Slide 23 |
| verification artifact | Slide 24 |
| runtime verification | Slide 25 |
| feature map | Slide 25 |
| driver or control CLI | Slide 26 |
| formal verification | Slide 27 |
| property-based testing | Slide 28 |
| fuzz | Both of her meanings: random input is slide 28, the release-wide exploring run is slide 43 |
| statechart | Slide 32 |
| low-trust and high-trust loop | Slides 6 and 7 |
| factory (software factory) | Slides 40 (framing) and 41 |
| outer loop, inner loop | Slide 42 |
| automated trigger | Slides 42 and 43 |
| coding machine | Framing |

## What the talk shows that her plugin does not contain

Things she showed from her team's own tooling or side projects, which [`cursor-pstack.md`](cursor-pstack.md)
cannot record because her public plugin lacks them:

1. **Dune**, her team's client framework: out of scope by name; its constraints are slides 19 and 22.
2. **The ban on one React hook in product code**: out of scope, a consumer's rule (slide 18).
3. **The two-folder split with an import ban**: her app's layout is out of scope; a consumer's import
   ban goes through `/corrections:codify` and `/implementation:implement`; the layout lens is
   [#15811](https://github.com/melodic-software/claude-code-plugins/issues/15811) (slide 19).
4. **The per-tick file suffix**: declined as a shipped convention (slide 19).
5. **A check against unsolicited markdown**: declined, with a reopen trigger (slide 20).
6. **Her team's comment-ban mechanism**: not stated in the talk; ours is the no-comments posture and
   `/code-tidying:remove-comments` (slide 22). Her counts are not recorded.
7. **Her team's lint rules whose messages name the root cause, and their growth**: the fix-naming
   rule is [#15653](https://github.com/melodic-software/claude-code-plugins/issues/15653); the count
   is [#15650](https://github.com/melodic-software/claude-code-plugins/issues/15650) (slide 23).
8. **Her concrete driver CLI**: out of scope by name; ours is generated per control skill (slide 26).
9. **TLA+ models of notifications across devices**: out of scope by name; our formal-verification
   plugin is proven first on the loop-lane claim protocol
   ([#15648](https://github.com/melodic-software/claude-code-plugins/issues/15648), slide 27).
10. **Lean proofs for her virtualization library**: out of scope by name; a proof tool is opt-in,
    chosen by the question, never a default step (slide 27).
11. **UI property testing through a named library**: taken as tool-neutral property guidance
    ([#15825](https://github.com/melodic-software/claude-code-plugins/issues/15825), slide 28).
12. **The statechart of bugs in her side project**: her output, out of scope; the chart skill is
    [#15648](https://github.com/melodic-software/claude-code-plugins/issues/15648) (slide 32).
13. **Her team's bot as the outer loop**: declined for now, with the owner's reasons (slide 42).
14. **Release-triggered fuzzing that opens and merges fixes**: the release pass is
    [#15649](https://github.com/melodic-software/claude-code-plugins/issues/15649); auto-merging its
    fixes is not recorded (slide 43).
15. **Her team's metrics**: out of scope (slides 3 and 34 to 38).
16. **The pyramid, "code is memory", gardening and organic architecture as terms**: the ladder carries
    the pyramid and the memory point (slides 8 and 12); the rest is framing.
17. **Sridharan's test-stage chart**: decided in
    [#15667](https://github.com/melodic-software/claude-code-plugins/issues/15667) (slide 31).

Two places where the talk and her plugin pull apart, both settled: the escape hatch (see
[Her terms](#her-terms)), and comments, where her plugin keeps a comment for a reason the code
cannot show while the talk bans nearly all of them; our posture is in the slide 22 row (C5).
