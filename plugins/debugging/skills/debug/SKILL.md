---
name: debug
description: "Debug and diagnose broken behavior via a disciplined six-phase loop: build feedback loop → reproduce → hypothesise → instrument → fix + regression test → cleanup. Use when: \"diagnose this\", \"debug this\", \"why is X broken\", \"X is throwing\", \"something is wrong with\", \"investigate this bug\", \"performance regression\", \"this is slow\", \"intermittent failure\", broken behavior in UI / logs / production / screenshot, flaky test traced to root cause — any OBSERVED FAILURE without a pre-existing reproduction. Phase 1 builds the loop; no phase proceeds without a fast, deterministic signal. Skip when: the symptom is already a failing test with no reproduction gap — cycle it directly. Outputs: reproduction loop, root-cause hypothesis, regression test or documented seam gap, cleaned fix, post-mortem finding."
argument-hint: "[bug description or observation] (e.g., /debugging:debug checkout times out for orders over $1k)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -10 2>/dev/null || echo "no commits"`
Working tree status: !`git status --porcelain 2>/dev/null | head -10 || echo "clean"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Hard bugs are won or lost in **Phase 1**. Without a fast, deterministic, agent-runnable signal that says "bug present / bug fixed", every later phase is guessing — and most failed debugging sessions fail because the engineer skipped straight to hypothesising without building a loop.

This skill enforces the discipline. Six phases, each with a clear gate before the next. The middle three (hypothesise → instrument → fix) are mechanical once Phase 1 is solid; the bookends (loop, cleanup) are the load-bearing work.

Scope boundary — this skill starts from an **observed failure**: UI behaving wrong, a log line that should not appear, a performance regression, a screenshot of a bug, a production symptom. Its first job is to **construct** a reproduction loop. If the symptom is already a failing test with no reproduction gap, you do not need this skill — cycle that test directly (reproduce → fix → retest → regression). What `/debugging:debug` adds over a bare fix loop is a critical edge case: **if no correct test seam exists, that absence IS the finding** — filed as an architectural recommendation, not a forced test in the wrong place.

## Adapting to your environment (graceful degrade)

This skill is self-contained. Where a phase below names an adjacent capability — a test-investigation routine, a TDD helper, a headless-browser driver, an architecture-audit agent, an issue tracker, an outcome-verifier — treat it as **optional**: *if your environment provides that capability (a skill, plugin, agent, or tool), invoke it; otherwise proceed with the inline guidance given here, which stands on its own.* Never block a phase because an adjacent tool is absent. Consumer-specific conventions (naming, module layout, banned APIs, work-notes location) come from your own project's `CLAUDE.md` and tool config — read them; this skill does not assume them.

## Emit checklist

For any diagnostic run (Phases 1-6), track phase completion. A ready-to-fill checklist is bundled at `${CLAUDE_PLUGIN_ROOT}/skills/debug/templates/checklist.md` — if your project has a working-notes or scratch location, copy it there; otherwise track the six phases inline. Phase 4 is SKIPPED when Phase 2 repro conclusively verifies the Phase 3 hypothesis without instrumentation.

## Phase 1 — Build a tight feedback loop

Before loop construction begins, run a short pre-investigation discipline pass. If a behavioral-guidelines capability is available (e.g. the `andrej-karpathy-skills:karpathy-guidelines` skill from the `karpathy-skills` marketplace), invoke it — it primes four rules (think-before-code, simplicity-first, surgical-changes, goal-driven-execution) ahead of hypothesis formation. If it is not installed, degrade gracefully and apply the same discipline directly:

- **Surface assumptions before you rank** — state what you are taking for granted about the failure before Phase 3.
- **Simplest explanation first** — do not reach for an exotic cause while a mundane one is untested.
- **Keep changes surgical** — instrument and fix at the narrowest seam that reaches the bug.
- **Frame the goal as a verifiable signal** — Phase 1's success criterion is literally "a fast, deterministic, agent-runnable pass/fail signal exists."

**This is the skill.** Everything else is mechanical. The **tight loop** — a fast, deterministic, agent-runnable pass/fail signal — is the load-bearing artifact. If that signal exists, the cause will be found. Without one, no amount of staring at code will save you.

Spend disproportionate effort here. Be aggressive. Be creative. Refuse to give up.

### Construction strategies — try in roughly this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e
2. **Curl / HTTP script** against a running dev server (bring your dev server up however your stack does)
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot
4. **Headless browser script** (a Playwright-style driver, if available) — drives UI, asserts on DOM/console/network
5. **Replay a captured trace** — save a real network request / payload / event log to disk, replay through the code path in isolation
6. **Throwaway harness** — minimal subset of the system (one service, mocked deps) exercising the bug code path with a single function call
7. **Property / fuzz loop** — for "sometimes wrong output", run 1000 random inputs and look for the failure mode
8. **Bisection harness** — if the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so `git bisect run` works
9. **Differential loop** — same input through old-version vs new-version (or two configs), diff outputs
10. **HITL bash script** — last resort. If a human must click, copy the bundled template at `${CLAUDE_PLUGIN_ROOT}/skills/debug/scripts/hitl-loop.template.sh`, customize the steps, and ask the **user** to run it in their terminal (the Bash tool cannot satisfy interactive `read` prompts). Have them paste the `--- Captured ---` KEY=VALUE stdout back into the session so the loop stays structured

### Loop-recursion hazard

When the loop IS a test the suite/runner discovers and runs, watch for self-invocation: a test file that invokes the very runner (or pre-push lane) which re-discovers and re-runs it recurses until the box saturates — each nested run re-triggers the test. The symptom reads as a *hang*, but it is fork-bombing, not a slow test. Guard with a re-entrancy sentinel: set an env marker before the inner run; a nested invocation that sees the marker exits early. Same pattern for any loop that shells out to a command which re-enters the loop.

### Iterate on the loop itself

Treat the loop as a product. Once *a* loop exists, ask:

- Can it be **faster**? Cache setup, skip unrelated init, narrow test scope
- Can the **signal be sharper**? Assert on the specific symptom, not "didn't crash"
- Can it be **more deterministic**? Pin time, seed RNG, isolate filesystem, freeze network

A 30-second flaky loop is barely better than no loop. A 2-second deterministic loop is a debugging superpower. Per-ecosystem timing-injection patterns (and other I/O-seam abstractions) live in the bundled reference at `${CLAUDE_PLUGIN_ROOT}/skills/debug/reference/ecosystem-debugging.md` — see the `timing-injection` row for your stack. The universal principle: wrap I/O and time sources at the seam where they enter the code so the loop can swap a deterministic stand-in.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not — keep raising the rate until it is.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what was tried. Ask the user for: (a) access to whatever environment reproduces it, (b) a captured artifact (HAR file, log dump, core dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** proceed to hypothesise without a loop.

**Do not proceed to Phase 2 until you have a loop you believe in.**

## Phase 2 — Reproduce

Run the loop. Watch the bug appear.

Confirm:

- The loop produces the failure mode the **user** described — not a different failure that happens to be nearby. Wrong bug = wrong fix
- The failure is reproducible across multiple runs (or, for non-deterministic bugs, reproducible at a high enough rate to debug against)
- The exact symptom (error message, wrong output, slow timing) is captured so later phases can verify the fix actually addresses it

Do not proceed until the bug is reproduced.

## Phase 3 — Hypothesise

Generate **3-5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea and wastes the next hour.

Each hypothesis must be **falsifiable** — state the prediction it makes:

> "If `<X>` is the cause, then changing `<Y>` will make the bug disappear / changing `<Z>` will make it worse."

If you cannot state the prediction, the hypothesis is a vibe — discard or sharpen it.

Ground the ranking in real repo state (survey the landscape before you rank): recent commits in the affected area, open issues, architecture decision records, banned-symbol entries, known-issue / quirks notes. A hypothesis that contradicts a documented constraint should rank low; one that matches a recent change should rank high. Anchor hypotheses against the **nearest** context files — walk up from the affected file to the repository root and read the closest `CLAUDE.md` / `AGENTS.md` / ubiquitous-language / ADRs in that module, so hypotheses reference real constraints rather than blind speculation.

**Show the ranked list to the user before testing.** They often have domain knowledge that re-ranks instantly ("we just deployed a change that touches #3"), or know hypotheses they have already ruled out. Cheap checkpoint, big time saver. Do not block on it — proceed with your ranking if the user is AFK.

## Phase 4 — Instrument

Each probe must map to a specific prediction from Phase 3. **Change one variable at a time.**

Tool preference, in order:

1. **Debugger / REPL inspection** if the env supports it. One breakpoint beats ten logs
2. **Targeted logs** at the boundaries that distinguish hypotheses
3. **Never "log everything and grep"** — that produces noise that hides the signal

**Tag every debug log** with a unique short prefix, e.g. `[DEBUG-a4f2]`. Cleanup at the end becomes a single `grep -r "\[DEBUG-a4f2\]"`. Untagged debug logs survive across PRs; tagged logs die on cue.

Per-ecosystem logging API (idiomatic structured-logger choice for ad-hoc debug instrumentation), banned debug-output APIs, and the required tag-prefix convention live in the bundled reference at `${CLAUDE_PLUGIN_ROOT}/skills/debug/reference/ecosystem-debugging.md` — see the `logging` + `banned-output` rows for your stack.

**Performance branch.** For perf regressions, logs are usually wrong. Instead: establish a **baseline measurement** using your ecosystem's standard timing / benchmark primitives, then bisect against the baseline. **Measure first, fix second.** Per-ecosystem perf-tooling references (micro-bench libraries, query-plan inspection, profile primitives) live in the reference — see the `perf-tooling` row for your stack.

**Cold-vs-warm + contention.** A single timing datapoint taken right after filesystem churn (freshly-created fixtures, a just-cloned repo) or while the box is under load (leaked process trees, a parallel build, antivirus scanning) is cold-cache- and contention-inflated, often by multiples. Before calling a perf number reproducible: re-measure warm, on a quiet box, best-of-N (or worst-of-N for a regression ceiling). A number that drops several-fold on the second clean run was measuring contention, not the code path — never trust one datapoint after churn.

**Discovery / glob cost.** When the slow path is *discovery* itself — a tree walk, `glob`/dotglob expansion, recursive find — check whether it descends into large vendored or build-output subtrees (dependency caches, VCS internals, compiled output) before excluding them. That is O(tree size), not O(matches). Prefer index-based enumeration (e.g. the VCS's own tracked-file listing) or prune-first traversal that never enters the excluded subtrees. A discovery step walking a multi-GB tree to find a handful of files is the regression.

## Phase 5 — Fix + regression test

Write the regression test **before the fix** — but only if there is a **correct seam** for it.

A correct seam is one where the test exercises the **real bug pattern as it occurs at the call site**. If the only available seam is too shallow (single-caller test when the bug needs multiple callers, unit test that cannot replicate the chain that triggered the bug), a regression test there gives **false confidence**.

**If no correct seam exists, that itself is the finding.** Note it. The codebase architecture is preventing the bug from being locked down. Do not force a test in the wrong place — file the architectural finding in Phase 6 instead.

If a correct seam exists:

1. Turn the minimised repro into a failing test at that seam — follow your project's test naming + structure conventions
2. Watch it fail (Red)
3. Apply the smallest fix that addresses the **root cause**, not the symptom (Green)
4. Watch the test pass
5. Re-run the **Phase 1 feedback loop** against the original (un-minimised) scenario — the test passing is necessary but not sufficient

Resist refactoring during the fix. The Boy Scout Rule applies to files touched, but keep behavioural changes focused. If the fix reveals a design problem, note it for a separate refactor commit (or the Phase 6 architectural recommendation).

## Phase 6 — Cleanup + post-mortem

Required before declaring done:

- Original repro no longer reproduces (re-run the Phase 1 loop)
- Regression test passes (or absence of correct seam is documented as an architectural finding)
- All `[DEBUG-...]` instrumentation removed (`grep -r "\[DEBUG-` returns nothing in source)
- Throwaway prototypes deleted (or moved to a clearly-marked sandbox location)
- The hypothesis that turned out correct is stated in the **commit message / PR description** — so the next debugger learns
- If the loop revealed a recurring class of bug, record it in your project's known-issues / quirks notes
- Confirm the fix outcome: run the mechanical build/test/lint, then check the original symptom is resolved with no regression, and record the evidence. The context that produced the fix converges on approval rather than detection, so beyond those objective checks the outcome verdict should be rendered by an agent that did NOT produce the fix — if your environment has an outcome-verification capability, use it; otherwise dispatch a fresh-context verifier with the symptom, the fix diff, and pass/fail criteria. Boundary: `/debugging:debug` DOES the fix + regression test; a verifier VERIFIES the outcome

**Then ask: what would have prevented this bug?** If the answer involves architectural change (no good test seam, tangled callers, hidden coupling, missing abstraction):

- File the architectural finding with your issue tracker
- If your environment has an architecture-audit agent or a module-deepening review, suggest a focused audit of the affected module
- Make the recommendation **after** the fix is in, not before — the post-fix view has more information than the pre-fix one

## What this skill does NOT do

- **Does not ship without a feedback loop** — Phase 1 is a hard gate. If a loop cannot be built, that is the report you deliver
- **Does not retry blindly** — "tried it again and it worked" is not a fix. Intermittent passes mean the root cause is still present
- **Does not fix the symptom** — a null check at the call site is fixing the symptom; finding why the value is null is fixing the cause
- **Does not refactor mid-fix** — keep the diff focused. Architectural findings go to Phase 6
- **Does not re-derive a known classification** — when the symptom matches a shape your environment already classifies (a known-error taxonomy, a test-investigation routine), lean on that instead of re-deriving it

## When to escalate

If after 3 hypothesis-test cycles no candidate is panning out:

- The hypothesis ranking was probably wrong — go back to Phase 3, re-survey the repo, look for what was missed
- The loop may not be tight enough — re-iterate Phase 1 (faster, sharper, more deterministic)
- The bug may need redesign rather than a patch — switch to broader replanning (an architecture/plan-review capability, if available)
- Do not push through a fifth or sixth attempt — that is how technical debt compounds and "fixes" break unrelated code
