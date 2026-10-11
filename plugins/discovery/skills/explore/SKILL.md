---
description: "Explore the local codebase before changes; a folder outside any repo, or machine state, is research's. Persists EXPLORE.md via a fresh-context subagent. Use when: 'explore the codebase', 'what exists for X', 'how does this work', 'trace the dependencies', 'what tests cover this', or as step 1 before a code change. Skip a bare locate ('where is X', 'what calls Y'): dispatch the built-in Explore agent. Skip why it was built that way: '/discovery:trace-intent'."
argument-hint: "[scope]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: explore
  summary: Explore code, history, tests, and config before changing anything
---

**Arguments.** `[scope]`. e.g., /discovery:explore payments module dependencies, /discovery:explore tests, /discovery:explore git, /discovery:explore config

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`
- Project root, `git rev-parse --show-toplevel`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 20 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git. The dated record for that composition claim is the worktree skill's
[reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

These values orient this session only. The project root is an absolute machine path. Use it to resolve files while working, but never echo it into `EXPLORE.md`; the handoff artifact records relative paths (see the outcome gate below).

## Routing. Dispatch by default

**From the main conversation, this skill dispatches the `discovery:explorer` subagent.** Exploration reads many files; keeping that out of the orchestrator's context window is the point. The agent loads the project's path-scoped rules, runs the six dimensions, writes the artifact set, and returns a bounded summary plus a file pointer, not the reads. The parent resolves the **pre-dispatch envelope** first, six fields (scope, reason, memory-slice path, memory root, budget, capability flags), written into the dispatch prompt as the labeled template in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), not as prose the agent has to parse, and owns the **post-dispatch boundary** after: re-surfacing `open_questions` to the user, dispatching the sibling verifier, and **writing its verdict back into `EXPLORE.md`** (which agent, its prompt, the literal `verification:` line, and what to write when no verifier can run: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), "The sibling verifier, stated once"), the explorer always returns `verification: pending` because it may not grade its own work, so an artifact left saying `pending` after the parent verified it cannot be told apart from one whose verifier never ran, and this artifact is the whole handoff a fresh session resumes from.

**Run inline instead when any of these holds**. Inline runs the identical workflow, and the escape hatch relaxes nothing:

- **Tight turn-by-turn iteration**. ≤~5 known files, findings feeding a same-session edit, and you will redirect as results land.
- **Cost**, a dispatched run pays the full six dimensions every time; a single-file question does not need an envelope.
- **The invoking context is already a subagent**. Dispatch-by-default is scoped to the main-conversation boundary. Hoisting, not nesting: the outer dispatch already supplied the fresh context, so a second hop only spends the inner agent's own window.

**When selecting the dispatched route:** probe `check-dispatch-artifact.sh --help` before dispatching; a denied or errored probe **halts**. An un-runnable post-dispatch gate is not a reason to take the inline escape hatch *to dodge the gate*. A legitimate inline run (tight iteration, cost, already-a-subagent) does not owe that script, it has no script verdict to self-grade, so do not apply this precondition to the inline path. Invocation forms: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md).

**Which agent, decided by four tests.** The named alternative is the **built-in Explore subagent**, and these four decide between it and `discovery:explorer`. **Any one YES routes to `discovery:explorer`**, and all four NO means this skill is the wrong entry point altogether, dispatch built-in Explore and do not invoke this skill:

1. **Must a graded artifact survive the run?** Built-in Explore cannot write one.
2. **Do project conventions constrain the answer** (`.claude/rules/`, a nested `AGENTS.md`, declared layer rules)? Built-in Explore never sees them.
3. **Will a conclusion rest on the contents of a file** rather than its location? A built-in agent runs a prompt you cannot inspect and its report does not say how much of a file it read, so what it returns backs `verified: grep`, never `verified: read`.
4. **Might the run truncate and need resuming?** Built-in Explore is one-shot.

Each NO above is a harness denial, not a preference, and the four are recorded once with their basis in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), "The built-in Explore agent cannot hold this plugin's contract". Read it before arguing with a test; do not restate the denials anywhere else.

Built-in Explore is therefore a **scout under a worker, never the worker**. Where it earns its place: the locate-tier legwork inside a larger exploration, per the fan-out rules below. When dispatching one, pass a thoroughness level (`quick`, `medium`, `very thorough`) and restate any convention that bounds the search, because it arrives convention-blind.

**Preload-liveness sentinel.** A dispatched agent receives this body through its `skills:` preload, and a preload that fails to resolve is skipped **silently**. Logged to the debug log and nowhere else. The dated record for that harness behavior is [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), "Harness facts the dispatch design rests on". A dispatched run therefore echoes this token verbatim as `preload_token` in its return payload. The disk fallback Reads this same file, so a matching `preload_token` is file-identity, **not** proof that preload fired:

```text
discovery-explore-preload-8e2b7d
```

A missing or mismatched token is a **hard failure: the parent discards the run**, never downgrades or accepts the artifact. Without it, a preload miss produces an undisciplined run that still writes an artifact. Indistinguishable from success at every other seam. Provenance is `preload: fired | fallback`; `fallback` is the accepted recovery, not a discard. Rationale and the parent-side contract: [`${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md`](${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md), "Discipline liveness".

**Post-dispatch acceptance gate. Parent-side, before the payload is believed.** `status: complete` is the agent's claim about its own run, and a claim is not evidence. Grade the run **off disk**, against the memory-slice path from the parent's own pre-dispatch envelope, **carry that path across the dispatch, because it is this gate's input**, and never a path read out of the payload, because the failure this gate exists to catch is a payload that comes back carrying no pointer at all. In order:

**Pre-dispatch:** create the memory slice and touch `<that slice>/.explore-dispatch` as the gate's freshness baseline, then hand that file to the gate as `--newer-than`. Without it a slice that already holds an earlier run's artifact set passes every on-disk check even when this dispatch wrote nothing at all. **Both shell forms of that one command are in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md) ("The pre-dispatch baseline"). Copy the one matching this session's shell, because the POSIX form's `touch` is not a command in PowerShell and its directory flag is a parameter error there. Same file carries the envelope template this dispatch also owes.** The memory root's self-ignoring `.gitignore` guard is a separate obligation this gate does not grade. Same file, "What this gate does not grade".

1. **The payload is well-formed**. `preload_token` matches the sentinel verbatim, `preload:` is `fired` or `fallback`, and an `artifact:` pointer is present. Missing token or artifact is a **failed dispatch** whatever the `status` field says; a missing token is a discard, per the rule above. A missing or unrecognized `preload:` field is an out-of-date agent definition, not a pass. A matching token does not prove preload fired; `preload: fallback` is not a discard.

   **And `scope_as_received` matches the scope the parent actually sent**. Compared against the envelope the parent wrote, not against what it meant. It is the only check here that fires on an input that is present and wrong. A mismatch is a **failed dispatch**: re-dispatch with the scope restated in a form that survives the trip (see the caveat under **Scope**); do not accept the artifact and mentally translate it. A well-formed payload carrying no `scope_as_received` is an out-of-date agent definition, not a pass.
2. **The artifact set is actually on disk, and this run put it there:**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch-artifact.sh" <the retained memory-slice path> \
     --index-name EXPLORE.md \
     --newer-than <that slice>/.explore-dispatch --expect-index <the payload's artifact: value>
   ```

   `--index-name` is required, not defaulted, the same gate grades `/discovery:research` runs, the two artifact families differ only in that name, and a gate that fails closed everywhere else must not guess which family it is looking at.

   The gate grades exactly the slice path it is given and never scans the slice for an index elsewhere, so on a collision the envelope's slice path is already the sub-slice the parent assigned pre-dispatch, and that same assigned path is the one handed here.

   Cite the **exit status**, 0 usable, 1 no usable artifact set, 2 ungradeable, not a reading of the directory, because the context most motivated to call the dispatch finished is the one that would be doing the reading. Only the slice path and `--index-name` are required, and that bare form is still a real gate: every optional check reports `unchecked` rather than passing quietly. Append `--expect-sidecars <n>` when the payload reported a `sidecars:` count, and **drop any flag whose value the payload did not supply**.

   **The `index=` path in that output is authoritative** downstream: the verifier's target and the handoff pointer both come from it, not from `artifact:`. `pointer=mismatch` means the payload named a file this gate never graded, a defect in the payload, not a naming preference to reconcile.

**Any non-zero exit halts the workflow, and a gate that could not run at all is a FAIL, never a skip.** An invocation above that is denied, prompts and is declined, or errors out halts exactly as a non-zero exit does; do not fall back to reading the directory. Do **not** proceed to research, planning, or an edit on the strength of an exploration that did not happen. Proceeding is the damage a silently-empty return actually causes; the missing artifact is only how it starts. Recovery ladder, and why a resume beats a re-dispatch: [`${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md`](${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md).

**One named exception, and it is an exception to the halt, not to the gate.** Exit 1 with `persistence: by-value` in the payload means the agent finished and its environment refused every write, the one failure where a re-dispatch pays full price to reproduce the same refusal. There the parent **writes the slice itself** from the artifact bodies the payload carries verbatim, into the memory-slice path it resolved before dispatch (on that path the payload's `artifact:` value is a *destination* the agent names, never the anchor), and then **re-runs the identical gate command above**. The workflow proceeds only on a subsequent exit 0. If the second run is non-zero, the halt stands and the ladder resumes at the rung it was on. The freshness check needs nothing special: the parent writes after its own pre-dispatch `touch`, so the index is strictly newer than the baseline.

Read the by-value rung before performing that write: [`${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md`](${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md). It carries the two conditions that bind the write (filename checking and the collision rule) and why a by-value payload of findings rather than artifact bodies is a failed dispatch rather than a fallback.

**Coverage discipline** when fanning out: (1) write a numbered gap-list before any deepen pass; (2) fan out by disjoint area, never split the six dimensions across agents; (3) whoever holds the workflow writes `EXPLORE.md`. `discovery:explorer` writes its own, while built-in Explore agents cannot write one at all, so their caller does.

**A gap asking why the code was built this way is routed, not explored.** Git history shows what changed and when; the reasons sit in pull requests, issues and reviews this skill does not read. Record such a gap as `→ /discovery:trace-intent <subject>` in the gap-list and the Next-stage handoff, and do not deepen on it here.

**When to fan out, and to what.** Fan-out is the worker's, not the parent's: the parent dispatches **one** `discovery:explorer`, which scales inside its own run. Two triggers, either one: the scope names **two or more disjoint areas**, or the numbered gap-list after the first pass carries **four or more** entries in areas that share no files. Below that, go sequential; a scout costs a spawn and returns a pointer, which a single-area scope does not need. The worker type is the **built-in Explore scout** described above, one per disjoint area, each told what it owns and what it must not wander into. **Spawn at most a dozen scouts at once.** That is this plugin's own ceiling, not the session's: the harness enforces a separate concurrency limit whose value this body does not restate and which a consumer can configure *below* a dozen, so a wave of twelve is not guaranteed to fit. Treat a refused spawn as an area **deferred, not dropped**: hold it and re-spawn it in the next wave, and let the gap-list rather than the first wave decide when coverage is done. The scout is locate-tier: its hits are pointers, and the worker Reads the file itself before any sidecar records `verified: read`.

**One `EXPLORE.md`, one worker.** Fanning the six dimensions across *parent-side* explorers, the shape `/discovery:research-deep` uses for N independent topics, is deliberately not done here. Research topics are independent; codebase areas share a dependency graph, and dimension 3 is the one a parent-side split severs. Revisit only when an ask arrives as N genuinely separable modules with no cross-area dependency; then the sub-slice machinery this plugin already has applies unchanged.

## Worker procedure

Load [reference/workflow.md](reference/workflow.md) when you are the worker (inline, or the dispatched `discovery:explorer`), before the first dimension. It holds purpose, the six dimensions, exploration modes, and the output format. The parent does not load it to dispatch. The outcome gate below still applies.

## Outcome gate (before EXPLORE.md handoff)

Before writing EXPLORE.md (or returning the summary), check the artifact against **binary criteria read off it**, not a "did I explore enough?" recap. Any FAIL → return to the named dimension and fix before handoff:

- **Every Output-format section populated with specifics**. Each of the 7 sections carries concrete findings, not placeholders or "TBD".
- **Every load-bearing area covered OR listed as a numbered gap**. Nothing the task plausibly depends on is silently unexplored.
- **Conclusion-driving claims are Read-verified, not inferred from a filename or grep hit**. Anything a downstream decision rests on came from reading the file or code.
- **A pass/fail claim was run, not read**. Every claim that a test or check passes, fails or builds carries `verified: ran` with its `command:` and observed `result:`; a test that was only opened supports no such claim.
- **The index pins and lists what it cites**. Its frontmatter `repos:` carries each explored repository's `sha` and `dirty` flag, its `## Code references` section opens with `coverage: exhaustive` or `coverage: key-files`, and every abstract states a finding rather than naming what was covered.
- **Paths are machine-agnostic**. No finding in the artifact echoes an absolute machine path (notably the project root gathered above); every path it records is written relative to the repo root, or, when there is no repo root, to the current working directory, so the handoff stays portable across machines.
- **Open questions handed off, never dropped**. Surfaced to the user inline, or carried in the payload's `open_questions` for the parent to surface under dispatch. Each with a recommended default.

## Scope

Explore the following: $ARGUMENTS

**A dispatched run does not read that line.** The scope does not reach a preloaded body by argument substitution, and a non-fork subagent has no view of the conversation to fall back on, so **do not rely on seeing an unfilled slot**: for a dispatched run the scope arrives in the dispatch prompt, and its absence is a parent-envelope failure the agent reports rather than repairs, whatever the line above renders as. There is no unscoped orientation mode under dispatch: a general repository sweep would hand back a plausible artifact answering a question nobody asked. What is documented about that path, and what is not, in either direction, is recorded once in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md). Running **inline** with no scope supplied above, infer it from the current conversation context. Identify what area of the codebase is relevant to the task at hand and explore that.

**Caveat, a `${CLAUDE_…}`-shaped token in a scope may not arrive as you typed it**, which is a different question from the paragraph above and not evidence for or against it. What was observed, what is documented, what is not, and the practical rule: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md) ("A different question"). The `scope_as_received` echo-back in the acceptance gate is what catches it whichever way the substitution actually runs.

## Final step: persist artifact for handoff

Write the exploration output to `<memory_dir>/<slug>/EXPLORE.md`, a memory-tier artifact, never committed. Destination and slug resolve per the lifecycle artifact protocol ([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)).

This file is the authoritative stage summary, a fresh session must be able to resume external research or planning reading only this artifact.

**`EXPLORE.md` is always an INDEX**, at every size, not only past an overflow threshold. It carries a task restatement, a one-line abstract per sidecar copied verbatim from that sidecar's header, a section → file + anchor table, a `## Code references` listing with its `coverage:` line, and the closing Next-stage-handoff naming what external research (`/discovery:research`) or planning needs. The 7-point Output format's content lives in sibling `EXPLORE-<section>.md` sidecars in the same directory, each opening with a machine-readable YAML header so a consumer can grep headers and read exactly one file. Schema, the `repos:` commit pin, and the two load-bearing placement rules. Sidecars stay inside `<memory_dir>/<slug>/`, and `EXPLORE.md` stays the entry point: [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md).

**Sidecar bodies match their length to what the section needs**. Cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate; the index's one-line abstracts and the outcome gate's specifics are the floor, not an invitation to narrate.

**Sidecar filenames are keyed on the SECTION, not the scope**, a run has one scope and many sections, so a scope-keyed name gives every sidecar the same filename and later sections overwrite earlier ones. Use the same stable id the header's `section` field and the index anchor carry.

**Sidecar headers use the EXPLORE schema, not the research one.** Local evidence is a repository path and whether the file was actually Read. `verified: read | ran | grep | inferred`, not a URL, a source tier, and a publishing pool. Handed the research header, a run either fabricates fields it has no values for or improvises a shape no consumer can parse; the fabrication is worse, because it launders a grep hit into the field a fetched primary would occupy. Schema and why `verified` is load-bearing: the artifact-shape spoke's "EXPLORE.md sidecar header" section.

**If an unrelated `EXPLORE.md` already exists** in that slice, do not clobber it, and do not rename the index to dodge it, since `EXPLORE-*.md` is the sidecar pattern and a renamed index collides with its own sidecars. Occupancy is the PARENT's to resolve, before any write: stat the slice root pre-dispatch, and when it is occupied assign a sub-slice `<memory_dir>/<slug>/<scope-slug>/` as the envelope's slice path, so the whole artifact set is written there under its normal names. A worker never picks a sub-slice itself, and on an inline run this session is the parent and applies the same check before writing. A prior exploration lost to a filename collision is silent and unrecoverable.

## Boundary, the built-in `Explore` agent

Both answer "what is in this codebase", so a request to explore can route to either.

- **`Explore` (built-in subagent)**: a one-shot locator that returns excerpts to its caller and
  skips CLAUDE.md. It mutates nothing: it cannot write files. It is reached through the Agent
  tool's `subagent_type`.
- **This skill (marketplace plugin)**: the full exploration: six dimensions, the project's rules
  loaded, and a persisted, verified `EXPLORE.md` a cleared session resumes from.

**Routing.** When the built-in `Explore` agent resolves in this session, dispatch it directly for a
bare locate ("where is X", "what calls Y"); use this skill when the four tests under Routing above
send the run to `discovery:explorer`. Inside this skill's run, `Explore` is the locate-tier scout,
never the worker.

**Mutation gate.** `Explore` writes nothing. This skill writes the artifact set in the memory slice
only.

The four-part records live in [reference/native-explore.md](reference/native-explore.md).

## Next

- Findings raise a question about current external practice: `/discovery:research <topic>`.
- The picture is enough, no contract is locked, and the diff will not be quick to review and cheap to retry: `/planning:interview`.
- The contract is locked and the work adds types, contracts, or module boundaries: `/planning:design`.
- Unsure where this leaves the work, or arrived mid-flow: `/session-flow:workflow`.

## Gotchas

- **Fan-out without a numbered gap-list**. Dispatching subagents before writing gaps produces duplicate reads and missed areas. The gap-list is the coverage-discipline gate.
- **Handing off with placeholder sections**. Every Output-format section needs specifics or an explicit numbered gap. "TBD" fails the outcome gate.
- **Inferring from filenames without Read**. Grep hits are discovery only; conclusion-driving claims need Read verification.
- **Investigating deleted files without asking**, when `git status` shows intentional deletes, ask before archaeology.

## What this skill does NOT do

- **Does not research externally**. That's `/discovery:research`. This skill reads local code, git, and file system only
- **Does not make changes**. It explores. Execution is a separate step
- **Does not make decisions**. It presents what IS. The planning step decides what SHOULD BE
- **Does not skip dimensions for "simple" tasks**, a quick bug fix still benefits from reading the surrounding code and checking for tests
- **Does not substitute for reading**, when uncertain, Read the file. Don't infer from file names or git log alone
