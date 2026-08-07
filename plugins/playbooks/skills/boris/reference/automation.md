# Setup Maintenance & Automation as Infrastructure — Sections 104–109

Two Boris threads: `/checkup`, the one-command setup tune-up (Part 20, July 8, 2026), and *"Automation as infrastructure"* (Part 21, July 15, 2026) on why automating your own work is the highest-leverage thing an engineer does.

## 104. /checkup — The One-Command Tune-Up

Setups drift: skills you stopped using, a CLAUDE.md that quietly grew, hooks taxing every turn, a version several releases behind. `/checkup` audits the whole install and proposes fixes — the keep-your-setup-lean playbook (Sections 88, 4, 89) run in one pass. It can clean up unused skills, MCPs, and plugins; dedup a local CLAUDE.md against the checked-in one; break a large root CLAUDE.md into nested files plus skills so context loads only where relevant; turn off slow hooks; update Claude Code; enable auto mode by default; and pre-approve frequently-denied read-only commands.

## 105. /checkup is Safe by Default

It never changes anything behind your back. It surfaces a plan — what is broken, what is unused, what it would change — and waits; nothing is modified until you choose. Changes are reversible: settings are one-line toggles, and CLAUDE.md edits stay in the working tree for `git diff` review. Scope is yours, from clean-up-everything through pick-the-groups to report-only.

## 106. /checkup — The Run

Boris posted his own result: a broken `claude` launcher (a test run had overwritten it), 38 project skills never used across 2,345 sessions, and a CLAUDE.md loading roughly 10k tokens every session. Cleaning it up repairs the install and saves about 5.5k tokens of context per session — a permanent tax lifted off every future turn. The lesson under the feature: setups accumulate silent waste you never notice until something measures it.

## 107. Automation Is the Meta-Skill

The best engineers always spent real time automating their own work — editor macros, lint rules for repeat issues, e2e suites instead of hand smoke-testing — because it multiplied their own output. With agents this compounds: infrastructure and developer-experience automation speeds up every agent in the fleet, not just you. More automation means more output per unit time, multiplied by the number of agents working.

## 108. Move Fixes From Prompts Into Code

There is a difference between fixing an issue and eliminating a *class* of issue. An agent that re-fixes the same issue on every run burns tokens and misses cases; an agent that writes a lint rule, a CI step, or a routine automates that class forever, for every future run and every contributor. Boris frames this as what people actually mean by loops — automating entire types of busywork rather than solving them one-off. It generalizes Section 89: a chat correction fixes one run, encoded infrastructure fixes every run.

## 109. Encode Domain Knowledge as Infrastructure

The genuinely new reason: automation is what lets *others* contribute. Engineers contribute on day one because Claude can navigate the codebase for them, and non-engineers can contribute as effectively as engineers. What blocks both is domain knowledge living in people's heads. What changed is the ceiling on what can be encoded — no longer just lint rules, types, and tests, but nearly all domain knowledge, as code comments, skills, CLAUDE.md, REVIEW.md, docs, and memories, so an agent or a new human works productively with zero additional context from the prompter.

Boris's reframe: a PR rejected for not following a framework or an architectural pattern the contributor could not have known is a **failure of automation** — that knowledge should have been encoded rather than left in a reviewer's head. Builds on Sections 4, 5, 32, and 89.
