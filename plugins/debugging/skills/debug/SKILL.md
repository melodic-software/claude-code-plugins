---
description: "Debug and diagnose broken behavior via a disciplined six-phase loop: build feedback loop → reproduce → hypothesize → instrument → fix + regression test → cleanup. Use when: the user reports an OBSERVED FAILURE with no pre-existing reproduction, in any of three shapes: wrong or broken behavior ('diagnose this', 'debug this', 'why is X broken', 'X is throwing'), a performance regression ('this is slow'), or an intermittent or flaky failure, whether seen in the UI, logs, production, or a screenshot. Phase 1 builds the loop; no phase proceeds without a fast, deterministic signal. Skip when: the symptom is already a failing test with no reproduction gap. Cycle it directly. Skip when a captured profile, trace or heap snapshot is in hand and the failure does not reproduce (`/debugging:analyze-profile`). Outputs: reproduction loop, root-cause hypothesis, regression test or documented seam gap, cleaned fix, post-mortem finding."
argument-hint: "[bug description or observation]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Diagnose broken behavior. Reproduce, hypothesize, instrument, fix with regression test
---

**Arguments.** `[bug description or observation]`. e.g., /debugging:debug photo uploads over 20 MB fail with a 502

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Recent commits, `git log --oneline -10`
- Working tree status (empty = clean), `git status --porcelain | head -10`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 10 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Variables

Arguments: `$ARGUMENTS`

## Purpose

This skill turns a reported failure into a command that answers one question, "is the bug still
here?", and then uses that command as the judge for every later step. The six phases below each end
in a gate. How well Phase 1 goes decides most of the outcome: with a quick, repeatable check that an
agent can run unattended, Phases 3 to 5 become routine work; without one, every hypothesis is a
guess. The usual way a debugging session goes wrong is starting on causes before any such check
exists. Phase 1 and Phase 6 (the check, and the cleanup that removes what the run added) carry the
weight; the three phases between them follow from the check.

Scope boundary: this skill starts from an **observed failure**: UI behaving wrong, a log line that should not appear, a performance regression, a screenshot of a bug, a production symptom. Its first job is to **construct** a reproduction loop. If the symptom is already a failing test with no reproduction gap, you do not need this skill. Cycle that test directly (reproduce → fix → retest → regression). What `/debugging:debug` adds over a bare fix loop is a critical edge case: **if no correct test seam exists, that absence IS the finding**, filed as an architectural recommendation, not a forced test in the wrong place.

Running example. The phases below follow one case: a photo larger than 20 MB uploaded through the
mobile API gets a 502 from the media service, while smaller photos upload normally.

## Adapting to your environment (graceful degrade)

This skill is self-contained. Where a phase below names an adjacent capability, such as a test-investigation routine, a TDD helper, a headless-browser driver, an architecture-audit agent, an issue tracker, or an outcome-verifier, treat it as **optional**: *if your environment provides that capability (a skill, plugin, agent, or tool), invoke it; otherwise proceed with the inline guidance given here, which stands on its own.* Never block a phase because an adjacent tool is absent. Consumer-specific conventions (naming, module layout, banned APIs, work-notes location) come from your own project's `CLAUDE.md` and tool config. Read them; this skill does not assume them.

## Secrets stay out of what you show

Anything this skill puts in a reply, a work note or a commit is a place a secret can leak. The rule
for each kind of text:

| Text | Rule |
|---|---|
| A loop script or harness you commit | It reads tokens and passwords from environment variables, so the file names the variable and never holds the value. |
| A command line you show | Same: the variable name appears, the value does not. |
| A capture (HAR file, log dump, replayed trace) | Assume it holds auth headers and session tokens. Show an excerpt of the lines where the failure appears, never the whole file. |
| Any secret still left in what you show | Replace it with `<REDACTED>` before the text leaves your hands. |

If the redacted excerpt is too thin to diagnose from, ask the user how to proceed; do not widen the
excerpt on your own.

## Emit checklist

For any diagnostic run (Phases 1-6), track phase completion. A ready-to-fill checklist is bundled at `${CLAUDE_PLUGIN_ROOT}/skills/debug/templates/checklist.md`. If your project has a working-notes or scratch location, copy it there; otherwise track the six phases inline. Phase 4 is SKIPPED when Phase 2 repro conclusively verifies the Phase 3 hypothesis without instrumentation.

## Phase 1: Build the reproduction loop

Write down what you are assuming about the failure first (for the running example: the 502 comes
from our media service, not the CDN in front of it; staging fails the same way production does). Phase 3 ranks
hypotheses against that list.

Most of this skill's effort belongs here. The loop is done when one command returns pass or fail
for this bug, quickly, the same way each time, with no person needed to run it.

### Picking a loop

Try the rows roughly in table order. A lower row usually costs more to build or tells you less, so
prefer the first row that can reach the failing code.

| Rank | Loop | Choose it when | In the running example |
|---|---|---|---|
| 1 | A failing test (unit, integration or end-to-end) | some test seam already reaches the failing code | an integration test that posts a 25 MB JPEG and asserts a 201 |
| 2 | A scripted HTTP call (curl or similar) | the failure shows at an endpoint of a dev server you can start | `curl` the upload endpoint with a 25 MB file and print the status code |
| 3 | A CLI run on a fixture file | the code has a command-line entry point | run the thumbnailer CLI on `large.jpg` and diff its output against a known-good copy |
| 4 | Browser automation run headless, through a Playwright-style driver if one is available | only the UI shows the failure | drive the web uploader and assert on the DOM, console and network panel |
| 5 | A recorded input played back | a real request body or event stream can be saved | save one failing multipart request to disk and send it to the upload handler alone |
| 6 | A disposable harness | starting the full stack takes minutes, but the failing module can be imported on its own | a scratch script imports the thumbnail module, swaps S3 for an in-memory store, and passes it `large.jpg` |
| 7 | A randomized-input loop (property or fuzz) | the output is wrong only for some inputs | generate a thousand images of random size and format and keep the ones that fail |
| 8 | An automated bisect | the bug has a history: an older release, data snapshot or dependency version where the upload still works | `check.sh` builds the checkout and exits 0 on a 201 for the 25 MB upload, 1 otherwise; `git bisect run ./check.sh` walks v3.2 to v3.4 with it |
| 9 | A side-by-side run | two builds or two configurations should agree | send the same file through last week's build and this week's, then diff the results |
| 10 | A human-driven script | a person has to click | see below |

A human-driven loop is the fallback when nothing above works. Copy the bundled template at
`${CLAUDE_PLUGIN_ROOT}/skills/debug/scripts/hitl-loop.template.sh`, replace its example prompts with
the steps for this bug, and ask the **user** to run it in their own terminal: its interactive `read`
prompts need a TTY that the Bash tool does not have. The script ends by printing a `=== results ===`
block of `NAME=value` lines; ask the user to paste that block back so each run reaches you in the
same shape.

### Loop-recursion hazard

When the loop IS a test the suite/runner discovers and runs, watch for self-invocation: a test file that invokes the very runner (or pre-push lane) which re-discovers and re-runs it recurses until the box saturates. Each nested run re-triggers the test. The symptom reads as a *hang*, but it is fork-bombing, not a slow test. Guard with a re-entrancy sentinel: set an env marker before the inner run; a nested invocation that sees the marker exits early. Same pattern for any loop that shells out to a command which re-enters the loop.

### Phase 1 exit check

A loop that merely runs is not finished. Before leaving Phase 1, hold it to all three requirements
below; each failing one has its own remedies.

| Requirement | Met when | If not met |
|---|---|---|
| Speed | one run finishes in about 2 seconds; a 30-second loop is not acceptable | run only the one test, keep the server or fixtures alive between runs, skip start-up work the failing path does not touch |
| One verdict | the same code gives the same verdict on every run; a loop that flips between runs tells you almost nothing | stub the network, give each run a fresh directory, seed the random generator, freeze the clock |
| Precision | it goes red on the reported symptom and on nothing else | assert on the 502 from the upload call itself, not on "the script exited non-zero" |

Per-ecosystem timing-injection patterns (and other I/O-seam abstractions) live in the bundled reference at `${CLAUDE_PLUGIN_ROOT}/skills/debug/reference/ecosystem-debugging.md`. See the `timing-injection` row for your stack. The universal principle: wrap I/O and time sources at the seam where they enter the code so the loop can swap a deterministic stand-in.

### Intermittent failures

Here the goal is a failure rate you can measure, not a failure on every run. Track the rate as a
number (failed runs out of total) and raise it until roughly every other run fails; at a rate near
one run in a hundred, the difference between two changes disappears into chance. Three levers raise
it, used in any combination:

| Lever | What to change |
|---|---|
| Timing | insert sleeps between the steps you suspect of racing, or shrink the gap between them |
| Pressure | load the machine (CPU, disk, network) while the loop runs |
| Volume | fire the trigger 100 times or more per loop run, and run several copies in parallel |

### When no loop can be built

This is a full stop: no Phase 2 and no guessing at causes. Report instead, in three parts:

1. **Tried.** Each loop kind from the table you attempted, and what blocked it.
2. **Blocker.** What is missing: the environment, the data, or a way to observe the failure.
3. **Request.** Ask the user for whichever of these would remove the blocker: permission to add
   short-lived production instrumentation, a redacted capture (a screen recording with timestamps,
   a core dump, a log dump, a HAR file), or access to an environment where the failure occurs.

When the artifact in hand is a CPU profile, heap snapshot or performance trace and nothing reproduces, hand it to `/debugging:analyze-profile`. It reads the recording down to a file:line cause without a loop; bring that cause back here for the fix and its regression test.

**Gate: Phase 2 starts only once you trust the loop.**

## Phase 2: Reproduce

Run the loop and see it fail. Then check three things before going on:

1. **It repeats.** The loop fails on every run, or, for an intermittent bug, at a rate high enough
   to compare runs.
2. **It is the reported failure.** The loop fails the way the **user** said it does. A nearby
   failure (a 413 where the user saw a 502) sends the fix to the wrong place.
3. **The symptom is on record.** Keep the exact error text, wrong value or timing, so Phase 5 can
   show the fix changed that symptom and not some other one.

**Gate: Phase 3 starts only once the loop has reproduced the bug.**

## Phase 3: Hypothesize

The output of this phase is a table, written down before any test runs. It holds **3 to 5 rows,
ranked**: a list of one invites every later test to be read as support for it.

| Rank | Cause | Refuted if | Supported if |
|---|---|---|---|
| 1 | the reverse proxy caps request bodies at 20 MB and drops the connection | raising the proxy cap to 50 MB leaves 25 MB uploads failing | the same upload sent past the proxy, straight to the service, succeeds |
| 2 | the resize step runs out of memory on large images | a 25 MB file in a format the resizer skips still fails | lowering the worker's memory limit makes 15 MB uploads fail too |

A row is ready only when its "refuted if" cell names a result you could observe. If you cannot fill
that cell, the cause is too vague to test: narrow it until you can, or delete the row.

Ground the ranking in real repo state before you rank: recent commits in the affected area, open issues, architecture decision records, banned-symbol entries, known-issue or quirks notes, and the project instruction files and ADRs nearest the affected file. A hypothesis that contradicts a documented constraint ranks low; one that matches a recent change ranks high.

**Restart with no code change.** Put stored state at the top of the ranking, checked in this order: serialized state the previous run wrote, caches, config the new process loads, lock files. Each costs one step to rule in or out: rename it, relaunch, run the loop.

**Uneven load.** If one worker, host, shard or tenant suffers far more than its peers, write a small script that tallies the symptom per actor and run it on every loop pass; a number read once off a dashboard cannot be compared between passes. Then compare the tallies. A leader that changes from pass to pass is noise. A leader that never changes points at the scheduling, routing or hashing code that picks it, and that code is the next hypothesis to test.

**Pick the test that rules out more.** When two tests cost about the same, run the one whose result eliminates more of the remaining hypotheses.

**Post the table, then start row 1 without waiting for an answer.** The user may know what the
repo cannot show: that staging runs the same proxy cap and accepts the file, that every failing
upload comes from the Android app, or that row 2 matches a ticket closed last month. One such reply
can drop a row, add one or change the order. In an unattended run nobody answers, and your ranking
stands.

## Phase 4: Instrument

A probe exists to fill one cell of the Phase 3 table: before adding it, name the row and the
"refuted if" or "supported if" result it will show. Between two loop runs, **change exactly one
thing**, so any change in the verdict has one explanation.

| Probe | Reach for it when | Note |
|---|---|---|
| Breakpoint in a debugger or REPL | the runtime supports one | first choice: one stop at the suspect line shows every local value at once |
| Log line | no debugger fits, or the evidence spans processes | place it at the boundary where two rows predict different values, such as the body size the media service receives; write it with the session marker Phase 6 searches for |
| Timer, benchmark, profiler or query plan | the report is "thumbnails got slow", not a wrong result | the first number is the baseline; bisect commits, inputs or code paths against it, and edit code only once the slow one is found |
| Log everything, then search the output | never | the volume hides the line you need |

Per-ecosystem logging API (idiomatic structured-logger choice for ad-hoc debug instrumentation), banned debug-output APIs, and the required tag-prefix convention live in the bundled reference at `${CLAUDE_PLUGIN_ROOT}/skills/debug/reference/ecosystem-debugging.md`. See the `logging` + `banned-output` rows for your stack.

Timing tools per stack (micro-bench libraries, query-plan inspection, profile primitives) live in the same reference; see its `perf-tooling` row.

**A probe that writes a profile.** When an instrument step produces a CPU profile, heap snapshot or trace, read it with `/debugging:analyze-profile` and test its file:line finding against the Phase 3 prediction it was meant to check.

**Cold-vs-warm + contention.** A single timing datapoint taken right after filesystem churn (freshly-created fixtures, a just-cloned repo) or while the box is under load (leaked process trees, a parallel build, antivirus scanning) is cold-cache- and contention-inflated, often by multiples. Before calling a perf number reproducible: re-measure warm, on a quiet box, best-of-N (or worst-of-N for a regression ceiling). A number that drops several-fold on the second clean run was measuring contention, not the code path. Never trust one datapoint after churn.

## Phase 5: Fix + regression test

### Is there a correct seam?

Decide this before writing the test. A seam is correct when a test placed there runs the bug the
way production reaches it at the call site (for example, through the same callers). Which seam that
is depends on the confirmed row. If row 1 holds (the proxy cap), a unit test that hands the resize
function a 25 MB buffer never passes through the proxy: it passes before the fix and after, and
proves nothing about the bug. If row 2 holds (resize runs out of memory), that same unit test
reaches the cause and is a correct seam.

| Seam | What to do |
|---|---|
| A correct seam exists | Write the regression test there, **before** the fix, using the steps below. |
| No correct seam: no test can reach the bug, or every seam that can is too shallow to rebuild it (the bug needs several components or callers acting together and the seam isolates one) | Write no regression test; one at a shallow seam would pass for the wrong reason and make the bug look covered. Record the gap as **the finding**: the design keeps this bug from being pinned by a test. It goes into the Phase 6 architecture recommendation. |

### With a correct seam

1. At that seam, write a test that fails on the minimized repro, following your project's test naming
   and layout. Take the expected value from the bug report (the behavior the reporter expected, or
   the documented correct output), never from what the fixed code returns.
2. Run it and see it fail (Red), and check that it fails **for the intended reason**. A typo, a bad
   import or an unrelated defect also turns a test red, and a fix that clears *that* red has not
   touched the bug. Compare the failure message with the root cause you are after; if they differ,
   repair the test or the reproduction before you edit any implementation code.
3. Make the smallest change that removes the **root cause** rather than the symptom (Green).
4. Run the test and see it pass.
5. Run the **Phase 1 loop** again on the original, full-size scenario. A passing test is required
   but does not prove the reported failure is gone.

Keep the fix diff focused on the root cause. Leave surrounding cleanup out of this change, even in files you touched. If the fix reveals a design problem, note it for a separate refactor commit or the Phase 6 architectural recommendation.

Before the fix commit, diff the tree against where the session started and drop every edit made for a hypothesis now marked refuted, such as a guard, a retry or a raised limit. The commit holds the confirmed cause's fix and its regression test, nothing else.

**Worked example: a load imbalance.** The Phase 3 tally shows export workers 2 and 5 claim most of the large jobs in every pass. The defect is in how a worker gets picked, so the fix goes there: for example, claim by least current work, cap the large jobs one worker may hold, or hash on a key with more spread. Raising the busy workers' memory limit or adding more workers leaves the picking code as it was, so treat either as a symptom fix.

## Phase 6: Cleanup + post-mortem

The run is not done until every line below holds. They fall into three groups.

**Remove what the run added.**

- No temporary log line is left. Cleanup finds only what it can search for, so Phase 4 writes each
  one with a marker chosen for this session, such as `[DEBUG-a4f2]`, and `grep -r "\[DEBUG-"` over
  the source now returns nothing. A line written without the marker can be found only by memory.
- Disposable harnesses and prototypes are deleted, or kept only in a directory clearly named as scratch.

**Prove the fix.**

- The Phase 1 loop, run again, no longer reproduces the failure.
- The regression test passes, or the missing correct seam is written up as an architecture finding.
- Two runs of the Phase 1 loop, redacted, appear in the user report and the PR description: red before the fix, green after. If the red run is missing, for example because the loop was built after a hotfix, that gap is written down along with the substitute evidence used
- Confirm the fix outcome: run the mechanical build/test/lint, then check the original symptom is resolved with no regression, and record the evidence. The context that produced the fix converges on approval rather than detection, so beyond those objective checks the outcome verdict should be rendered by an agent that did NOT produce the fix. If your environment has an outcome-verification capability, use it; otherwise dispatch a fresh-context verifier with the symptom, the fix diff, and pass/fail criteria. Boundary: `/debugging:debug` DOES the fix + regression test; a verifier VERIFIES the outcome

**Leave a record.**

- The commit message or PR description names the hypothesis that proved right, so whoever debugs
  this area next starts from it.
- If the loop revealed a recurring class of bug, record it in your project's known-issues / quirks notes

### Prevention

This step runs only after the fix has landed, never before it: by then the loop and the fix have
shown how the code really behaves, which the first guess at a cause did not know. Ask what would
have stopped this bug from being written. If the answer lies in the design (a missing abstraction,
two modules coupled in a way neither shows, callers tangled together, or no seam where a test could
reach the bug), write a recommendation:

- State its `Basis:`, `verified` with the `file:line` or loop output it rests on, or `judgment` (only when it is not consequential: cross-repo, shared infrastructure, irreversible, or security). A consequential one is grounded in its consumers first; one that cannot be settled is withheld and filed as an open question naming the evidence that would settle it. Contract: [`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../context/recommendation-basis.md); full convention: [recommendation-basis](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/recommendation-basis/README.md#grounding-bar)
- File it with your issue tracker as an architectural finding
- If your environment has an architecture-audit agent or a module-deepening review, suggest a focused audit of the affected module

**Optional view.** After the post-mortem is written, offer an interactive view of it (the hypotheses with their verdicts and evidence, a tick for each the reader would re-open, a copy-out of the challenge). The page is never written beside the post-mortem, which stays the record. Build it only with `${CLAUDE_PLUGIN_ROOT}/scripts/build-view.mjs`, never hand-written; the publish destination comes from the `medium` cascade key. Procedure and data shape: [`${CLAUDE_PLUGIN_ROOT}/skills/debug/reference/rendered-view.md`](reference/rendered-view.md).

## Boundary, the bundled `debug` skill

The names collide outright, so "debug this" can land on either, but the two debug different things.

- **`debug` (bundled skill)**: turns on debug logging for the current Claude Code session and
  troubleshoots Claude Code itself by reading that session's debug log. It is reserved for the
  person to run; the model does not invoke it.
- **This skill (marketplace plugin).** Debugs the user's application: build a reproduction loop,
  confirm it fails, rank causes, probe them, fix with a regression test, remove what the run added.

**Routing.** When the broken thing is Claude Code itself (a hook, a tool call, a permission, a
session misbehaving) rather than the user's code, offer it to the person: you can run `/debug`
instead of or alongside this skill. Make the offer at Phase 1, before building a loop against the
application. An unattended run records the offer in its output instead of asking.

**Mutation gate.** `debug` starts debug logging for the session from the moment it runs. This
skill never runs it on the person's behalf.

**Availability is never assumed.** Bundled skills are gated on settings, environment, plan, and
host; this section states what to do when the person can run it, never that it is present. The
four-part records live in [reference/native-debug.md](reference/native-debug.md).

## What this skill does NOT do

- **Does not ship without a feedback loop**. Phase 1 is a hard gate. If a loop cannot be built, that is the report you deliver
- **Does not retry blindly**. "tried it again and it worked" is not a fix. Intermittent passes mean the root cause is still present
- **Does not fix the symptom**. A null check at the call site is fixing the symptom; finding why the value is null is fixing the cause
- **Does not refactor mid-fix**. Keep the diff focused. Architectural findings go to Phase 6
- **Does not re-derive a known classification**. When the symptom matches a shape your environment already classifies (a known-error taxonomy, a test-investigation routine), lean on that instead of re-deriving it
- **Does not ship a workaround in place of the cause**. When a change needs comment prose to explain why its odd behavior is required, read that as a sign the cause is still unfound and go back to Phase 3. A workaround that ships anyway carries a tracking link or a removal condition in its comment; the code-tidying comment-residue audit flags one with neither as `unjustified-workaround`
- **Does not fix when the user asked only for a diagnosis**. Stop once a hypothesis is confirmed: report the cause at file:line with the loop output that confirms it, remove the Phase 4 instrumentation, and change no other code. Without that request, fixing is the default

## Next

- Fixed with a regression test: /verification:confirm fix.
- Stopped at a diagnosis on request: /implementation:implement fix.
- Artifact with no reproduction: /debugging:analyze-profile.

## When to escalate

**Second failed fix.** Name the belief behind every attempt so far in a single sentence, then check that belief directly with the loop, once a second fix fails the Phase 1 loop and before a third is written. If the symptom is skewed across actors, run the Phase 3 tally first. This step is advisory; Phase 1 stays the only hard gate.

If after 3 hypothesis-test cycles no candidate is panning out:

- The hypothesis ranking was probably wrong. Go back to Phase 3, re-survey the repo, look for what was missed
- The loop may not be tight enough. Go back to Phase 1 and hold the loop to the exit check again
- The bug may need redesign rather than a patch. Switch to broader replanning (an architecture/plan-review capability, if available)
- Do not push through a fifth or sixth attempt. That is how technical debt compounds and "fixes" break unrelated code
