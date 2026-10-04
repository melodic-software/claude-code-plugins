---
description: "Prove a change achieved its intended outcome: a mechanical build+test+lint prerequisite (delegated to /toolchain:check and /toolchain:lint, STOPs if broken), then outcome verification. Does the change match the plan/intent and function correctly, with the criterion auto-detected by change-type (feature, fix, refactor). Use when: 'verify changes', 'prove this works', 'did we build the right thing', 'is this done', 'check my work', 'did the fix actually work'; for quick mechanical-only checks use /toolchain:check, for measurable-improvement claims use /verification:measure."
user-invocable: true
argument-hint: "[outcome|fix|refactor] [dotnet|python|typescript|bash|powershell|all]"
disable-model-invocation: false
effort: high
metadata:
  workflow-stage: verify
  summary: Prove the change achieved its intended outcome with evidence
---

**Arguments.** `[outcome|fix|refactor] [dotnet|python|typescript|bash|powershell|all]`. e.g., /verification:confirm, /verification:confirm outcome, /verification:confirm fix, /verification:confirm refactor, /verification:confirm dotnet

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Working tree status (empty = clean), `git status --porcelain`
- Changed files (vs HEAD), `git diff --name-only HEAD`
- Current branch, `git branch --show-current`
- Recent commits, `git log --oneline -5`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Purpose

`/verification:confirm` answers **"did we build the right thing, and does it work?"**. It proves a change achieved its intended outcome. It is an **orchestrator**, not a reimplementation of the mechanical pass.

Two stages, in order:

| Stage | Question | Mechanism |
|-------|----------|-----------|
| 1. Mechanical **prerequisite** | "does it build, pass tests, satisfy linters?" | invoke `/toolchain:check` and `/toolchain:lint` cross-cutting via the Skill tool, then the architecture-test gate. **STOP the flow if it fails**. Can't verify broken code |
| 2. Outcome **verification** (the core) | "does the change match the plan/intent and function correctly?" | intent match + evidence + (runtime) `/testing:run-e2e` / live-app observe |

The mechanical pass is a *gate*, not the point. `/toolchain:check` owns build+test+lint; `/toolchain:lint` owns cross-cutting checks. This skill composes them, then does the verification they cannot: did the change accomplish its goal.

**Quick mechanical-only?** Use `/toolchain:check` (not `/verification:confirm`). **Lint-only?** `/toolchain:lint`. **Tests-only?** `/toolchain:check <ecosystem>`. Reach for `/verification:confirm` when you need outcome confirmation. Proof, not just a green build.

## Arguments

`$ARGUMENTS`, optional mode and/or ecosystem filter.

**Modes** (each = an outcome criterion; Stage 1 runs first regardless):

| Mode | Outcome criterion |
|------|-------------------|
| (auto) | Detect change-type from conversation, then apply the matching criterion below |
| `outcome` | Feature / general: matches plan/design/discussion + functions (unit/integration) + (UI) looks correct (E2E + visual) |
| `fix` | Original bug symptom resolved + no regression |
| `refactor` | Behavior preserved. Same tests pass, no semantic change |

There is **no standalone "mechanical pass" mode**. That role belongs to `/toolchain:check`. Stage 1 here is the prerequisite gate for every outcome criterion. Measurable-improvement claims (`performance` / `metrics` vs a captured baseline) are `/verification:measure`, not a mode here.

**Ecosystem filters** (combinable with any mode): `dotnet`, `python`, `typescript` (or `ts`/`node`), `bash` (or `shell`), `powershell` (or `ps`/`pwsh`), `all`. If omitted, auto-detect from changed files.

## Mode dispatch

Parse `$ARGUMENTS` for a mode keyword first, then an ecosystem filter.

| Signal | Mode | Read |
|--------|------|------|
| `outcome`, "does this match intent", "prove this works", bare `/verification:confirm` with feature context | **outcome** | [context/outcome.md](context/outcome.md) |
| `fix`, "is this resolved", bug-fix context | **fix** | [context/fix.md](context/fix.md) |
| `refactor`, behavior preservation | **refactor** | [context/refactor.md](context/refactor.md) |
| `performance` / `metrics`, "before/after", "is it faster", "is it cleaner/simpler" | *redirect* | invoke `/verification:measure` via the Skill tool (measurable-delta twin) |

**Smart default (no mode argument)**. Detect from conversation:

- Bug-fix context → `fix`
- Refactor context → `refactor`
- Improvement claim (faster / simpler / cleaner / fewer deps) → redirect to `/verification:measure`
- Just finished implementation + review, or an approved plan exists → `outcome`
- Otherwise → `outcome` (the safe default. It subsumes intent match)

## Runtime-affecting paths

These categories decide when a change escalates beyond the per-ecosystem mechanical pass. When the consuming project documents its own runtime-affecting globs, those govern; otherwise use these portable defaults:

- **`e2e-app-runtime`**. API/app changes (endpoints, attributes, contracts, middleware): the project's app source directories
- **`e2e-ui-frontend`**. Components and static assets shipped to the browser: `**/*.razor`, `**/*.razor.cs`, `**/*.cshtml`, `**/wwwroot/**`, and the project's SPA/frontend source
- **`e2e-runtime-config`**. Runtime configuration (`**/appsettings*.json`, orchestrator config, env-shaping files)
- **`arch-test-triggers`**. Project-structure / dependency changes (`**/*.csproj`, `**/*.props`, `**/*.targets`, `**/Directory.Build.*`). Re-run the project's architecture-test suite when it has one

## Proof level

One setting, `proof_level`, decides how much evidence Stage 2 needs before a `CONFIRMED` verdict:
`path` (the default), `live` or `strict`. The user's option is `${user_config.proof_level}`; a
literal, unexpanded placeholder means unset. The repository value is `proof_level` in
`docs/conventions/verification.yaml` as committed on origin's default branch. Resolve it once,
before Stage 2, by the steps in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md` § Resolution](${CLAUDE_PLUGIN_ROOT}/reference/config.md#resolution):

- The stricter valid layer wins (`path` < `live` < `strict`); neither layer can lower the other.
- The repository copy comes from the default branch through
  `setup-apply.mjs --check --ref origin/<default>`, so a branch that edits its own copy is still
  verified at the default branch's level; when the two copies differ, the report names both.
- An invalid value is named with its file or option, the key and the value, and that layer is
  dropped. An invalid repository value resolves `path`. The run never stops on it.
- Resolution never asks the user. A layer that cannot be read (no `origin`, an unsafe branch name,
  node missing, the root rule) is skipped with its reason, so a pipeline lane running this skill
  unattended always gets a level.

Report one line before Stage 2 with the level and the layer that supplied it, for example
`proof_level: strict (docs/conventions/verification.yaml at origin/main, commit <sha>)` or
`proof_level: path (default)`.

## Stage 1. Mechanical prerequisite (delegate, don't reimplement)

The gate. Runs before any outcome criterion. **If it fails, STOP**. Report the failures; outcome confirmation is meaningless on code that doesn't build or pass tests.

Stage 1 delegates by invoking the `toolchain` plugin's `/toolchain:check` and `/toolchain:lint` via the Skill tool when that plugin is installed; when it is absent, run the project's own ecosystem-native build / test / lint commands (from its `CLAUDE.md` / rules) directly, the gate and its STOP-on-fail semantics are unchanged, only the executor differs. On that direct path, apply `/toolchain:check`'s counting rules yourself:

- A syntax-only command, or one that failed to start, is not a pass.
- When declared dependencies are missing, install them only from the lockfile with install scripts disabled, and only with `npm ci --ignore-scripts`, `uv sync --frozen --no-build --no-install-local` or `dotnet restore --locked-mode`, within the permission mode and never with `sudo`; any other package manager installs nothing and is a missing-dependency environment skip. The uv command builds nothing at install time: `--no-build` refuses third-party source builds and `--no-install-local` leaves out the project and its local packages, so a dependency with no wheel fails the install, which is also that skip (pointers: <https://docs.astral.sh/uv/reference/cli/#uv-sync--no-build>, <https://docs.astral.sh/uv/reference/cli/#uv-sync--no-install-local>; as of 2026-10-02; recheck trigger: either entry changes what it builds or installs). Never install a tool. If `git status --porcelain` or a hash of `git diff HEAD --binary` differs after the install, stop and report the changed paths.
- Name every skip with its reason. A missing tool (including an installed tool too old for the check, `skip (unsupported: ...)`) or missing dependencies is an environment skip; a consumer opt-out or a not-applicable command is not.

1. **Build + test + lint per ecosystem**, when changed files span multiple ecosystems or the mechanical pass spans more than a handful of commands, dispatch a subagent with the changed-file paths and `/toolchain:check`'s command tables, and verify its summary against the actual command output; otherwise invoke `/toolchain:check` via the Skill tool. `/toolchain:check` remains SSOT for ecosystem detection, CLI commands, and gotchas. Pass through the ecosystem filter from `$ARGUMENTS` if given; else `/toolchain:check` auto-detects from changed files.
2. **Architecture tests**, when changed files match the `arch-test-triggers` globs above and the project has an architecture-test suite, ensure it is included in the test step.
3. **Cross-cutting checks**. Invoke `/toolchain:lint cross-cutting` via the Skill tool. `/toolchain:lint` owns the cross-cutting tools with the presence-gated graceful-degradation pattern (missing tool → `skip`, never `FAIL`). Do **not** inline that bash here. `/toolchain:lint` is the SSOT.

**Gate result**, decided in this order:

1. Any FAIL from `/toolchain:check` or `/toolchain:lint cross-cutting`: stop and surface the failing command's key error lines. Fix mechanical failures before outcome verification proceeds.
2. A `STOPPED` run (a dependency install changed the tree): stop and report the changed paths.
3. No check ran because every one hit an environment skip (tool missing or too old, dependencies missing): stop. The verdict is `NOT VERIFIED`, listing each skip with its reason; Stage 2 does not run on a change nothing has exercised.
4. Otherwise proceed to Stage 2. Opt-in-unmet skips and not-applicable cells never hold the gate. An environment skip that remains (an `INCOMPLETE` run) carries into the verdict: the change can be `NOT VERIFIED` or `NEEDS WORK`, never `CONFIRMED`, until the skipped check runs. An ecosystem reported as `no real check ran (syntax only)` is not an environment skip and does not hold the verdict by itself, but the report names it and never counts it as a mechanical pass.

## Stage 2. Outcome verification (the core)

Read the criterion context file for the dispatched mode, then run the flow below. The shared spine (intent → inventory → match → evidence → report) is in [context/outcome.md](context/outcome.md); `fix` / `refactor` adapt it.

1. **Apply the proof level, then auto-trigger `/testing:run-e2e`**. The resolved `proof_level` (see Proof level above) sets what this step requires:
   - `path`: the runtime-path rule in the rest of this step, unchanged.
   - `live`: any change with a runnable surface is driven in the live app when the app can be launched, whether or not a changed file matches a runtime-affecting path. When the app cannot be launched, run the non-UI check the check-to-change table gives for that change, and the report says the app could not be launched. A change with no runnable surface (docs, tests only) is noted as such.
   - `strict`: fill the unit, live and perf boxes in [context/outcome.md § Proof boxes](context/outcome.md#proof-boxes) for each plan phase. Every box needs evidence or a reasoned not-applicable line before `CONFIRMED`.

   Under every level, inspect changed files. If any match an `e2e-*` category from the Runtime-affecting paths above, or touch observability code paths verifiable end-to-end, or the user said "test the app", invoke `/testing:run-e2e` via the Skill tool when the `testing` plugin is installed. Otherwise drive the live app directly (Claude Code's bundled `/run`, or a manual orchestrator launch) and capture the same evidence. When present, it validates prerequisites, starts the app, exercises the changed flow, and captures evidence (screenshots, console, network, traces). Carry that into the evidence table. If not runtime-affecting (pure refactor, internal lib, doc-only): note "E2E not applicable" and skip. Whether or not E2E applies, pick the check each changed area needs from the check-to-change table in [context/outcome.md § Which check proves which change](context/outcome.md#which-check-proves-which-change) (storage, parser or migration, command-line tool, user interface, performance).
2. **Intent retrieval**. Scan the conversation for the original request, the approved plan, refinements, and acceptance criteria. If none is clear, ask the user what the goal was.
3. **Implementation inventory**. Changed files, new capabilities, behavior changes, config/infra changes.
4. **Intent match**. Every requirement has implementation; every implementation traces to a requirement; flag scope additions and gaps (including implicit requirements. Error handling, edge cases, tests). Name the out-of-diff couplings: the existing behavior this change leans on, unchanged code whose contract the diff now depends on. A named coupling is checkable; an implied one is where regressions hide. The report carries them as their own table (see [context/outcome.md](context/outcome.md)).
5. **Evidence collection**. Stage-1 results, E2E results, test names + assertions proving the claimed behavior. For UI changes: the UI evidence artifacts per [context/outcome.md](context/outcome.md) (pre/action/post snapshot, console, network, behavior assertion. "screenshot looks fine" is NOT an assertion). When the plan states a measurable goal: the `/verification:measure` comparison table.
6. **Report + verdict**. Emit the outcome report (the proof-level line, the proof boxes under `strict`, intent-match table, mechanical results with every skip named and its reason, E2E + UI-evidence tables when triggered, evidence table, measurements when applicable) and a `CONFIRMED` / `NEEDS WORK` / `NOT VERIFIED` verdict. Report template and verdict criteria in [context/outcome.md](context/outcome.md). The report also states the effort level this run used: `${CLAUDE_EFFORT}`. The skill pins `effort: high`, a verdict lane's level, and no higher; an environment variable or an effort cap can still put the run at another level, which is why the report states it (pointer: the `effort` field in <https://code.claude.com/docs/en/skills#frontmatter-reference> and the `CLAUDE_EFFORT` row in <https://code.claude.com/docs/en/skills#available-string-substitutions>; as of 2026-10-02; recheck trigger: either row is renamed or removed, or the field stops overriding the session level). We pin the model-config row the pointer here names, and the fresh-context verifier below is raised to the model that produced the work whenever that model is known and stronger than this session's (see Independence of the verdict; pointer: the `high` row of <https://code.claude.com/docs/en/model-config#choose-an-effort-level> and the advisor capability rule in <https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool#model-compatibility>; as of 2026-10-02; recheck trigger: next model release).

**Independence of the verdict.** This skill usually runs in the context that produced the changes, and that context carries the assumptions that produced any defect, converging on approval rather than detection. Stage 1's mechanical pass/fail is objective and needs no escalation, but for the Stage 2 outcome verdict on anything beyond a mechanical, behavior-preserving change, render `CONFIRMED` / `NEEDS WORK` from an agent that did NOT produce the artifact: dispatch a fresh-context verifier with the acceptance criteria and the diff, withholding your rationale so it audits the artifact and not your story. When the work was produced on a model stronger than this session's (a security-surface phase routed to the frontier alias, say) and you know that model, pass the dispatch a per-invocation `model` at or above it; this override routes upward only and keeps the checked-work rule in the marketplace's `docs/plugin-philosophy.md` "Model tiers". When the producing model is not known, the report says the verifier's model was not matched to it. Where the outcome is high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor **when one is installed and set up**, e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs, with the fresh-context same-vendor verifier above as the stated fallback, never a route to a command that may not resolve (per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository).

When `/testing:run-e2e` ran, persist an assertion-only evidence manifest (what was asserted, at which commit. Record `verified_at_sha`) to the topic's memory slice at `<memory_dir>/<slug>/verification/` (default `.work/`), placed per the lifecycle artifact protocol ([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)). The manifest is never committed; paste it into the pull request body or the linked issue, its publication surface. It carries distilled assertions only, because the paste is shared. No raw command captures, no machine-local paths, no usernames or credentials; cite a `## Reproduction` block instead. Raw captures stay in the memory tier at `<memory_dir>/<slug>/scratch/` (default `.work/`), never committed.

## Delegation: live-app run + observe

For "run the live app and watch it behave," beyond automated `/testing:run-e2e`, `/verification:confirm` delegates rather than reimplementing app-launch:

- **Primary: invoke `/testing:run-e2e` via the Skill tool** (when the `testing` plugin is installed), the reliable path for orchestrated apps (Aspire, docker-compose, tilt) via the project's orchestrator tooling + Playwright CLI. It can isolate the drive loop in a subagent so the orchestrator consumes only evidence paths, emit an optional recording / session-artifact evidence tier (config-driven, defaults off. Screenshots stay the evidence floor), and on a failed prerequisite return a structured verification-environment gap report rather than a bare stop. Carry any recording and session-artifact pointers it produces into the evidence table.
- **Supplementary: Claude Code's bundled `/run`**, when a quick interactive run is enough and the orchestrated harness is overkill, and the client has it. For its sibling `/verify`, suggest that the person run it rather than delegating to it: the suggestion works whichever invocability state the client is in, and a delegated call can be refused at the tool layer. Our records for both live in [reference/native-verify.md](reference/native-verify.md).
  - **Pointer**: for the bundled `/run` and `/verify` skills, see <https://code.claude.com/docs/en/skills#run-and-verify-your-app>.
  - **As of**: 2026-08-10
  - **Recheck trigger**: a Claude Code release whose changelog names `/run`, `/verify`, `/run-skill-generator`, or bundled-skill invocability.
- **Graceful fallback**, if `/run` cannot infer the project's launch (or the CC version lacks it), fall back to invoking `/testing:run-e2e` via the Skill tool when the `testing` plugin is installed, or a manual orchestrator launch otherwise. Never silently downgrade live-app verification to a static check. Surface the gap.

## Edge cases

- **No git changes but user runs `/verification:confirm all`**: run Stage 1 across all ecosystems anyway (useful after a rebase or pull), then outcome verification if intent is in scope.
- **Changed file outside any known ecosystem**: Stage 1 skips it with a note; Stage 2 still assesses intent match.
- **Missing tools or dependencies**: `/toolchain:check` / `/toolchain:lint` report a named environment skip with the install hint, not a failure. It is never reported as done: it holds the verdict below `CONFIRMED` (Gate result, step 4), or stops the run when nothing else ran (step 3).
- **Invoked by a pipeline lane (no one to ask)**: the proof level still resolves (Proof level above); a layer that cannot be read is skipped with its reason and an invalid one falls back as stated, so the run reports the level it used and continues.
- **Invoked from a PR-prep flow**: treat the verdict as a hard gate. Any FAIL or unresolved CRITICAL gap blocks PR creation. A comprehension layer (an `education:quiz-me` report, when that plugin is enabled) may precede this gate and inform it; the merge gate itself lives here, one mechanism per concern.

## Skill chaining

| Condition | Action |
|-----------|--------|
| Review gate passes (no blocking findings, e.g. `/review:quality-gate` when installed) | Suggest `/verification:confirm` |
| Stage 1 fails | Fix build/test/lint/cross-cutting, then re-run `/verification:confirm` |
| Runtime-affecting change | Stage 2 auto-triggers `/testing:run-e2e` (bundled `/run` supplementary) |
| `/verification:confirm` finds CONFIRMED | Suggest a retro (`/session-flow:retro` when installed), then the project's PR flow (`/source-control:pull-request` when installed) |
| `/verification:confirm` finds gaps | Fix, then re-run `/verification:confirm` |
| Improvement claimed without data | Redirect to `/verification:measure` (`performance` or `metrics`; baseline captured at planning time) |

## Boundary, the bundled `verify` skill

Both answer "does this change actually work", so a request to verify a change can reach for
either.

- **`/verify` (bundled skill)**: the person's tool for driving the running app through the changed
  flow. We never invoke it from this skill, and we treat a first run as one that may write a project
  verify skill into the repository.
- **This skill (marketplace plugin).** The mechanical prerequisite, then outcome verification
  against the plan or intent by change type: the intent-match table, out-of-diff couplings, the
  evidence table, and an independent verdict.

**Routing.** When the change has a runtime surface to drive (an `e2e-*` category above, or any
product source), offer it to the person at the end of the run, beside the report: "you can run
`/verify` alongside this skill to drive the change end to end". Skip the offer for a diff touching
only tests, docs, or code with no runtime surface. An unattended run records the offer in its
output instead of asking. Its result is added evidence; it replaces neither Stage 1 nor the verdict.

**Mutation gate.** `/verify` may write a project verify skill on first use. This skill never
triggers it on its own behalf.

**Availability is never assumed.** `disableBundledSkills` or a `skillOverrides` entry hides it;
this section states what to do when it resolves, never that it is present. The records, each a
pointer with an as-of date and a recheck trigger, live in
[reference/native-verify.md](reference/native-verify.md).

## What this skill does NOT do

- **Does not reimplement the mechanical pass**. `/toolchain:check` (build+test+lint) and `/toolchain:lint` (cross-cutting) are SSOT. Stage 1 delegates to them.
- **Does not auto-fix**. Identifies failures and gaps; the implementer fixes them. For lint auto-fix, invoke `/toolchain:lint --fix` via the Skill tool when the `toolchain` plugin is installed; otherwise run the project's own lint fixer.
- **Does not check design quality for ship-readiness**. That's the project's review/quality-gate flow.
- **Does not verify measurable-improvement claims**. `/verification:measure` owns the baseline/compare mechanism; this skill redirects improvement claims there.
- **Does not replace PR prep**, the project's PR flow orchestrates review + verification + cleanup. This skill is the verification component.

## Gotchas

- **Stage 1 is a gate, not the deliverable.** A green build is the prerequisite; the deliverable is outcome confirmation. Don't stop at "it builds."
- **"It passes tests" is not outcome confirmation.** Tests prove behavior; outcome confirmation proves it's the RIGHT behavior. A well-tested feature that misses the intent is still wrong.
- **Don't skip outcome confirmation for "obvious" changes.** Small changes drift from intent unnoticed; the intent check catches scope creep and missed requirements tests don't cover.
- **Don't quantify improvement claims here.** "Faster" / "simpler" claims route to `/verification:measure` and its baseline discipline. Invoke it via the Skill tool; never assert an improvement from this skill's evidence alone.
- **Doubt the observation before the code.** When a check fails or contradicts the diff, first rule out how you looked: a stale build, a cached page, the wrong port or instance, a log read before the write landed, a stub still in place. Observe again by a second route; only a result that survives it counts against the change.
- **Don't re-run Stage 1 if it already passed this conversation** and nothing changed since. Reuse the results.
- **Live-app fallback is fidelity-preserving.** If the bundled `/run` can't launch the app, fall back to invoking `/testing:run-e2e` via the Skill tool when the `testing` plugin is installed, or a manual orchestrator launch otherwise, and say so explicitly, never silently swap live observation for a static check.
