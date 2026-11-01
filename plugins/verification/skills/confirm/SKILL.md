---
description: "Prove a change achieved its intended outcome: a mechanical build+test+lint prerequisite (delegated to /toolchain:check and /toolchain:lint, STOPs if broken), then outcome verification. Does the change match the plan/intent and function correctly, with the criterion auto-detected by change-type (feature, fix, refactor). Use when: 'verify changes', 'prove this works', 'did we build the right thing', 'is this done', 'check my work', 'did the fix actually work'; for quick mechanical-only checks use /toolchain:check, for measurable-improvement claims use /verification:measure."
user-invocable: true
argument-hint: "[outcome|fix|refactor] [--unattended] [dotnet|python|typescript|bash|powershell|all]"
disable-model-invocation: false
effort: high
metadata:
  workflow-stage: verify
  summary: Prove the change achieved its intended outcome with evidence
---

**Arguments.** `[outcome|fix|refactor] [--unattended] [dotnet|python|typescript|bash|powershell|all]`. e.g., /verification:confirm, /verification:confirm outcome, /verification:confirm fix, /verification:confirm refactor, /verification:confirm dotnet

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

**What kind of proof this is.** This skill proves by tests and observed behavior, not by formal methods such as model checking or proof. A change whose correctness rests on concurrency or protocol invariants should say so in the report, because passing tests and a clean live drive do not establish those invariants.

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

Parse `$ARGUMENTS` for a mode keyword first, then an ecosystem filter. `--unattended`, anywhere in the arguments, is
consumed before both: the caller declaring that nobody is present, which governs the `/verify`
offer under "Routing" and whether the `affected`, `/testing:run-e2e` and touched-feature refresh
calls in Stage 2 step 1 pass `--unattended`.

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
  dropped: it counts as absent, so the other layer still applies, and with neither valid the key
  resolves `path`. The run never stops on it.
- Resolution never asks the user. A layer that cannot be read (no `origin`, an unsafe branch name,
  node missing, the root rule) is skipped with its reason, so a pipeline lane running this skill
  unattended always gets a level.

Report one line before Stage 2 with the level and the layer that supplied it, for example
`proof_level: strict (docs/conventions/verification.yaml at origin/<default>, commit <sha>)` or
`proof_level: path (default)`.

## Live workers

A second setting, `live_workers`, decides how many workers share the live drive in Stage 2 step 1;
`proof_level` still decides whether a live drive is required at all. The user's option is
`${user_config.live_workers}`; a literal, unexpanded placeholder means unset. The repository value
is `live_workers` in `docs/conventions/verification.yaml`, read from origin's default branch by the
same `setup-apply.mjs --check --ref origin/<default>` call that reads `proof_level`. Resolve it once,
beside the proof level, by
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md` § Resolving `live_workers`](${CLAUDE_PLUGIN_ROOT}/reference/config.md#resolving-live_workers):

- The later layer wins: the repository value over the user option over the default, `1`.
- A value in either layer that is not a whole number of at least 1 is named with its file or option,
  the key and the value, and that layer is dropped: a valid higher layer still wins, otherwise `1`,
  never a lower layer's value. The run never stops on it.

Report one line before Stage 2 with the count and the layer that supplied it, for example
`live_workers: 2 (docs/conventions/verification.yaml at origin/<default>, commit <sha>)` or
`live_workers: 1 (default)`.

## Stage 1. Mechanical prerequisite (delegate, don't reimplement)

The gate. Runs before any outcome criterion. **If it fails, STOP**. Report the failures; outcome confirmation is meaningless on code that doesn't build or pass tests.

Stage 1 delegates by invoking the `toolchain` plugin's `/toolchain:check` and `/toolchain:lint` via the Skill tool when that plugin is installed; when it is absent, run the project's own ecosystem-native build / test / lint commands (from its `CLAUDE.md` / rules) directly, the gate and its STOP-on-fail semantics are unchanged, only the executor differs. On that direct path, apply `/toolchain:check`'s counting rules yourself:

- A syntax-only command, or one that failed to start, is not a pass.
- When declared dependencies are missing, install them only from the lockfile with install scripts disabled, and only with `npm ci --ignore-scripts`, `uv sync --frozen --no-build --no-install-local` or `dotnet restore --locked-mode`, within the permission mode and never with `sudo`; any other package manager installs nothing and is a missing-dependency environment skip. The uv command builds nothing at install time: `--no-build` refuses third-party source builds and `--no-install-local` leaves out the project and its local packages, so a dependency with no wheel fails the install, which is also that skip (pointers: <https://docs.astral.sh/uv/reference/cli/#uv-sync--no-build>, <https://docs.astral.sh/uv/reference/cli/#uv-sync--no-install-local>; as of 2026-10-02; recheck trigger: either entry changes what it builds or installs). Never install a tool. If `git status --porcelain` or a hash of `git diff HEAD --binary` differs after the install, stop and report the changed paths.
- Name every skip with its reason. A missing tool (including an installed tool too old for the check, `skip (unsupported: ...)`) or missing dependencies is an environment skip; a consumer opt-out or a not-applicable command is not.

1. **Build + test + lint per ecosystem**, when changed files span multiple ecosystems or the mechanical pass spans more than a handful of commands, dispatch a subagent with the changed-file paths and `/toolchain:check`'s command tables, and verify its summary against the actual command output: a command result counts as evidence only when this session ran it or the harness recorded it, never on an agent's say-so (the evidence ranking in `/implementation:implement-dispatch`'s command-evidence reference); otherwise invoke `/toolchain:check` via the Skill tool. `/toolchain:check` remains SSOT for ecosystem detection, CLI commands, and gotchas. Pass through the ecosystem filter from `$ARGUMENTS` if given; else `/toolchain:check` auto-detects from changed files.
2. **Architecture tests**, when changed files match the `arch-test-triggers` globs above and the project has an architecture-test suite, ensure it is included in the test step.
3. **Cross-cutting checks**. Invoke `/toolchain:lint cross-cutting` via the Skill tool. `/toolchain:lint` owns the cross-cutting tools with the presence-gated graceful-degradation pattern (missing tool → `skip (tool missing: <tool>)`, never `FAIL`; with nothing failed, its Overall line reads `INCOMPLETE`). Do **not** inline that bash here. `/toolchain:lint` is the SSOT.

**Gate result**, decided in this order:

1. Any FAIL from `/toolchain:check` or `/toolchain:lint cross-cutting`: stop and surface the failing command's key error lines. Fix mechanical failures before outcome verification proceeds.
2. A `STOPPED` run (a dependency install changed the tree): stop and report the changed paths.
3. No check ran because every one hit an environment skip (tool missing or too old, dependencies missing): stop. The verdict is `NOT VERIFIED`, listing each skip with its reason; Stage 2 does not run on a change nothing has exercised.
4. Otherwise proceed to Stage 2. Opt-in-unmet skips and not-applicable cells never hold the gate. An environment skip that remains (an `INCOMPLETE` run from `/toolchain:check` or `/toolchain:lint`, a lint-only one included) carries into the verdict: the change can be `NOT VERIFIED` or `NEEDS WORK`, never `CONFIRMED`, until the skipped check runs. An ecosystem reported as `no real check ran (syntax only)` is not an environment skip and does not hold the verdict by itself, but the report names it and never counts it as a mechanical pass.

## Stage 2. Outcome verification (the core)

Read the criterion context file for the dispatched mode, then run the flow below. The shared spine (intent → inventory → match → evidence → report) is in [context/outcome.md](context/outcome.md); `fix` / `refactor` adapt it.

1. **Apply the proof level, then auto-trigger `/testing:run-e2e`**. The resolved `proof_level` (see Proof level above) sets what this step requires:
   - `path`: the runtime-path rule in the rest of this step, unchanged.
   - `live`: any change with a runnable surface is driven in the live app when the app can be launched, whether or not a changed file matches a runtime-affecting path. When the app cannot be launched, run the non-UI check the check-to-change table gives for that change, and the report says the app could not be launched. A change with no runnable surface (docs, tests only) is noted as such.
   - `strict`: fill the unit, live and perf boxes in [context/outcome.md § Proof boxes](context/outcome.md#proof-boxes) for each plan phase. Every box needs evidence or a reasoned not-applicable line before `CONFIRMED`.

   **Touched features come from `affected`.** This skill never matches changed files against a control skill's `sources` globs; `/app-control:drive affected` owns that matching. When `/app-control:drive` resolves, invoke `/app-control:drive affected --base <ref> --out <evidence dir>/affected` through the Skill tool, adding `--unattended` only when this skill's caller passed `--unattended`. `<ref>` is the default branch's remote-tracking ref (`git symbolic-ref --short refs/remotes/origin/HEAD`), and `<evidence dir>` is this run's directory under Evidence retention below. When that command prints no ref (CI checkouts and shallow clones often lack `origin/HEAD`), guess no other branch: invoke no `affected`, report `blocked: no base ref` and match no feature. `affected` diffs committed changes only (`<ref>...HEAD`); when the gathered working-tree status is not empty, the report says the uncommitted files were not matched to features. Read `<evidence dir>/affected/affected.json` as data: its `features` list is the touched features, by id. When `affected` writes no `affected.json`, carry its `blocked:` line into the report and match no feature. When `/app-control:drive` does not resolve, the report carries `touched features not matched (app-control not installed)` and matches no feature. In every case the `e2e-*` path categories still apply, and neither a `blocked:` line nor app-control's absence holds the verdict.

   Under every level, inspect changed files. If any match an `e2e-*` category from the Runtime-affecting paths above, or `affected.json` lists a touched feature, or they touch observability code paths verifiable end-to-end, or the user said "test the app", invoke `/testing:run-e2e` via the Skill tool when the `testing` plugin is installed, adding `--unattended` only when this skill's caller passed `--unattended`. Otherwise drive the live app directly (Claude Code's bundled `/run`, or a manual orchestrator launch) and capture the same evidence. When present, it validates prerequisites, starts the app, exercises the changed flow, and captures evidence (screenshots, console, network, traces). Carry that into the evidence table. If not runtime-affecting (pure refactor, internal lib, doc-only): note "E2E not applicable" and skip. Whether or not E2E applies, pick the check each changed area needs from the check-to-change table in [context/outcome.md § Which check proves which change](context/outcome.md#which-check-proves-which-change) (storage, parser or migration, command-line tool, user interface, performance).

   When `/testing:run-e2e` reports per entry point (the repository has a feature map), an entry point the map lists for a changed feature that is missing from that report holds the verdict below `CONFIRMED`.

   **Keep touched features current.** `/testing:run-e2e` owns this step (its Step 4, Keep touched features current). When it ran, carry its refresh or drift lines into the report and refresh nothing again. When the drive was split across workers, tell each worker to skip that step, then run it once here over the merged report. When it did not run, run the step here over the touched features `affected.json` lists: call `/app-control:map refresh <feature id>` per touched feature when `/app-control:map` resolves, adding `--unattended` only when this skill's caller passed `--unattended`, carrying that feature's lesson (Lessons, below) in the same call; otherwise report the drift and name `/app-control:map refresh <feature id>` in `## Next`. When `/app-control:drive` does not resolve, no feature was matched, so nothing is refreshed and `## Next` names installing app-control. Neither the drift nor app-control's absence holds the verdict, and this skill never edits a control skill.

   **Capture status.** Take it from the `capture` object (`status`, `reason`, `count`) of the `e2e-summary.json` `/testing:run-e2e` wrote; with no summary, from its report: `ran` with the number of evidence artifacts kept when an entry point was driven, else `blocked` with the reason. A live drive without `/testing:run-e2e` (the bundled `/run`, a manual orchestrator launch) is `ran` with the number of evidence artifacts it kept, or `blocked` with the reason the app could not be launched or driven. With no live drive at all, it is `not-applicable` with the reason E2E did not apply. A capture that could not run (`blocked`: no usable driver, a gap-report stop, an environment failure) is never by itself a reason for `NEEDS WORK`: the verdict notes `Capture: blocked (<reason>)` and rests on the rest of the evidence. A criterion that only the capture could prove stays unproven, which makes the verdict `NOT VERIFIED`, not `NEEDS WORK`.

   **Split the drive across `live_workers`.** When the live drive runs and `live_workers` (see Live workers above) resolves above 1, it is split across workers; at 1 it runs as one worker, as before.
   - **Split by entry point.** List the feature-map entry points the drive must cover and give each worker a disjoint share, never more workers than entry points. Each worker invokes `/testing:run-e2e` for its share only. With no feature map there is nothing to split by: one worker runs, and the report says so.
   - **Local workers need a Workspace environment entry.** More than one worker on this machine needs a "Workspace environment" entry in `docs/conventions/workspace-environment.md` on origin's default branch, read the way `/testing:run-e2e` reads it (the fetched default-branch commit, never the working tree). Each worker then drives from its own linked worktree of the commit under verification, created and removed through `/source-control:worktree` when that plugin is enabled, so the entry's `up` runs under that worktree's own `WORKSPACE_ID`. With no entry, one worker drives every entry point, and the report says how many workers were asked for and why one ran: without the entry, parallel instances would share ports, containers and databases. The same holds when the stage under verification reads untrusted input (a fork pull request, an `untrusted-provenance` item) and the session is not on a cloud host whose stage-start probe passed: `/testing:run-e2e` then runs neither the entry's `up` nor its `info`, so the entry isolates nothing, one worker drives every entry point, and the report says how many workers were asked for and that the untrusted stage is why one ran.
   - **Per-worker session names.** When `/testing:run-e2e` drives the app itself, each worker's browser sessions carry its own workspace part and run id, as run-e2e composes them (the Session names section of its own-driving context), so no two workers open or close the same session. When it runs through `/app-control:drive`, drive and the app's control skill own the browser sessions, and drive stops only what its own run started.
   - **Merged report.** The missing-entry-point check above reads the merged per-entry-point report of every worker: an entry point no worker reported holds the verdict exactly as it would in a single drive.
   - **Measured usage per worker.** For each worker the report lists its entry points, its result and its usage as measured: the tokens and wall time the Agent tool's result reports for that worker, never an estimate, and never a price or cost figure.
   - **Cloud host.** When this run is on a cloud execution target (`CLAUDE_CODE_REMOTE` is `true` in the session, or the stage's `execution_target` in `docs/conventions/execution-target.yaml` resolved to a cloud value), the report adds the line `live-UI step unverified on this host`.
     - **Pointer**: the `CLAUDE_CODE_REMOTE` row of <https://code.claude.com/docs/en/env-vars>; for the subagent result whose usage each worker line reports, <https://code.claude.com/docs/en/agent-sdk/typescript#agent-2>.
     - **As of**: 2026-10-31
     - **Recheck trigger**: the env-vars row changes, or a Claude Code release changes the Agent tool result or its usage format.

   **Three rules for the live drive.**
   - **Ready means usable.** The app counts as ready only when a user could use it from an empty data directory, migrations and seed data included. A port answering or a health check passing is not enough: a database health check can pass while its init scripts still run.
   - **Never weaken a user journey to make it pass.** When the seed data lacks a precondition a journey needs, report that journey as failed with that reason. The verdict does not count it as passed, and the journey is not edited to pass.
   - **Stand-in caveat.** When the proof ran on a stand-in for the real target (a container instead of a fresh machine, a local stack instead of a remote one), the report lists every setup step the stand-in did that the target will not, and marks those unverified.
2. **Intent retrieval**. Walk the ladder in [context/intent.md](context/intent.md): the PLAN.md Brief, then the pull request body's acceptance criteria, then the linked issue, then the conversation; the report's `Intent source:` line names the one that supplied it. With none, ask; with no one to ask, the verdict is `NOT VERIFIED: no intent source`.
3. **Implementation inventory**. Changed files, new capabilities, behavior changes, config/infra changes.
4. **Intent match**. Every requirement has implementation; every implementation traces to a requirement; flag scope additions and gaps (including implicit requirements. Error handling, edge cases, tests). Name the out-of-diff couplings: the existing behavior this change leans on, unchanged code whose contract the diff now depends on. A named coupling is checkable; an implied one is where regressions hide. The report carries them as their own table (see [context/outcome.md](context/outcome.md)).
5. **Evidence collection**. Stage-1 results, E2E results, test names + assertions proving the claimed behavior. For UI changes: the UI evidence artifacts per [context/outcome.md](context/outcome.md) (pre/action/post snapshot, console, network, behavior assertion, and the render-check results: axe, geometry, pixel baseline, vision review as leads only. "screenshot looks fine" is NOT an assertion). When the plan states a measurable goal: the `/verification:measure` comparison table. Rank the test evidence by independence and label each test the producing session wrote as self-authored, per [context/outcome.md](context/outcome.md) "Evidence ranking".
6. **Report + verdict**. Emit the outcome report (the proof-level line, the worker line, the proof boxes under `strict`, intent-match table, mechanical results with every skip named and its reason, E2E + UI-evidence tables when triggered, evidence table, measurements when applicable, and the lessons the run learned, each with its scope and route in the Lessons table) and a `CONFIRMED` / `NEEDS WORK` / `NOT VERIFIED` verdict. Report template and verdict criteria in [context/outcome.md](context/outcome.md). The report also states the effort level this run used: `${CLAUDE_EFFORT}`. The skill pins `effort: high`, a verdict lane's level, and no higher; an environment variable or an effort cap can still put the run at another level, which is why the report states it (pointer: the `effort` field in <https://code.claude.com/docs/en/skills#frontmatter-reference> and the `CLAUDE_EFFORT` row in <https://code.claude.com/docs/en/skills#available-string-substitutions>; as of 2026-10-02; recheck trigger: either row is renamed or removed, or the field stops overriding the session level). We pin the model-config row the pointer here names, and the fresh-context verifier below is raised to the model that produced the work whenever that model is known and stronger than this session's (see Independence of the verdict; pointer: the `high` row of <https://code.claude.com/docs/en/model-config#choose-an-effort-level> and the advisor capability rule in <https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool#model-compatibility>; as of 2026-10-10; recheck trigger: next model release).

**Independence of the verdict.** This skill usually runs in the context that produced the changes, and that context carries the assumptions that produced any defect, converging on approval rather than detection. Stage 1's mechanical pass/fail is objective and needs no escalation, but for the Stage 2 outcome verdict on anything beyond a mechanical, behavior-preserving change, render `CONFIRMED` / `NEEDS WORK` from an agent that did NOT produce the artifact: dispatch a fresh-context verifier with the acceptance criteria, the diff and the path of this run's evidence directory (Evidence retention below), withholding your rationale so it audits the artifact and not your story. The verifier reads the whole local directory, raw captures included, and the run directory `/testing:run-e2e` used; `publishable` in `e2e-summary.json` decides only what may be uploaded or pasted, never what the verifier reads, and the directory itself is never uploaded. The verifier checks the provenance of every test it cites (`/testing:test-value`): a test added or changed in the diff under review is a producer claim until its expected value names an independent source. This is stricter than the `implementation:phase-verifier` agent, which reports an unsourced expected value as a finding without changing its verdict: here a criterion proved only by such a test is not COMPLETE ([context/outcome.md](context/outcome.md) "Evidence ranking"). When the work was produced on a model stronger than this session's (a security-surface phase routed to the frontier alias, say) and you know that model, pass the dispatch a per-invocation `model` at or above it (for the aliases that call accepts, see <https://code.claude.com/docs/en/sub-agents#choose-a-model>, as of 2026-10-31; recheck when that list or the resolution order changes); this override routes upward only and keeps the checked-work rule in the marketplace's `docs/plugin-philosophy.md` "Model tiers". When the producing model is not known, the report says the verifier's model was not matched to it. Where the outcome is high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor **when one is installed and set up**, e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs, with the fresh-context same-vendor verifier above as the stated fallback, never a route to a command that may not resolve (per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository).

**Record the verdict for the head it judged.** Once the verdict is final (including a
`NOT VERIFIED` from the Stage 1 gate), store it for the commit it judged, so the pull request
`ready` report can name it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/confirm-verdict.sh" record --head <sha> --verdict '<verdict>' --missing '<item>' --partial '<item>'
```

- `<sha>` is the full `git rev-parse HEAD`, run as its own call.
- Pass one `--missing` per `MISSING` plan item and one `--partial` per `PARTIAL` one, each a single
  line naming the requirement, and none for `COMPLETE` items.
- Skip the record when the gathered working-tree status was not empty: the verdict then judged
  uncommitted changes, not that head. The report says the verdict was not recorded and why.
- A non-zero exit leaves no record; the report names it and the verdict stands.

The record is advisory. It never gates the `ready` flip, and a commit after it leaves the new head
with no verdict.

Once the verdict is final, persist an assertion-only evidence manifest (the verdict, the `Capture:` and `Evidence loop:` lines, and, when `/testing:run-e2e` ran, what was asserted, at which commit. Record `verified_at_sha`) to the topic's memory slice at `<memory_dir>/<slug>/verification/` (default `.work/`), placed per the lifecycle artifact protocol ([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)). The manifest is never committed; paste it into the pull request body or the linked issue, its publication surface. It carries distilled assertions only, because the paste is shared. No raw command captures, no machine-local paths, no usernames or credentials; cite a `## Reproduction` block instead. Raw captures stay in the memory tier at `<memory_dir>/<slug>/scratch/` (default `.work/`), never committed.

## Evidence loop

A `NEEDS WORK` verdict sends the change back to implementation, at most 3 times per branch. The
count lives in `<memory_dir>/<slug>/verification/evidence-loop.<branch-slug>.json` (default
`.work/`), never committed:

```json
{"cap": 3, "count": 1, "heads": [{"sha": "<full sha>", "verdict": "NEEDS WORK", "at": "<UTC date-time>"}]}
```

- `<branch-slug>` is the gathered current branch, lowercased, with `/` and every other character
  outside `[a-z0-9._-]` replaced by `-`. With no current branch (a detached head) the loop is not
  tracked: nothing is read or written, and the line reads `Evidence loop: not tracked (detached head)`.
- Read the file before the verdict. A missing file is `count` 0 with no heads. A file that does not
  parse, or whose `cap` is not 3 or whose `count` is outside 0 to 3, is named in the report and read
  as `count` 0 with no heads.
- After the verdict is final, append an entry to `heads` (the full `git rev-parse HEAD`, the
  verdict, the time); earlier entries stay, so a head re-judged keeps its first `NEEDS WORK`
  record. `count` rises by 1 when the verdict is `NEEDS WORK`, no earlier entry for that `sha` is
  `NEEDS WORK`, and `count` is below 3. A head is distinct by its `sha`: a head that only rebased
  the same change and is judged `NEEDS WORK` counts.
- Write atomically: write the whole object to `evidence-loop.<branch-slug>.json.tmp` in the same
  directory, then rename it over the file with `mv`, so no reader sees a half-written file.
- Skip the write under the same rule as the verdict record: a non-empty gathered working-tree status
  means the verdict judged uncommitted changes, not that head. The line then reads
  `Evidence loop: <k>/3 (not written: uncommitted changes)`, `<k>` the count read.

What the count decides, read before this verdict's write:

| Count before | Verdict | Loop-back | `Evidence loop:` line | Next |
|---|---|---|---|---|
| 0 to 2 | `NEEDS WORK` | yes: the gaps go back to implementation | `<count after>/3` | fix the gaps, then `/verification:confirm` |
| 3 | `NEEDS WORK` | no | `3/3 cap reached, last NEEDS WORK` | open the pull request through the project's PR flow; its own park-and-retry path takes over |
| any | `CONFIRMED` or `NOT VERIFIED` | no | `<count>/3` | as the verdict routes |

In this marketplace's pipeline that path is `max-verify-fails` and `verify-cap-attempts` in
`docs/conventions/pr-pipeline.yaml`: pr-verify FAILs at that many distinct heads hold the pull
request from unattended merge, the pr-merge lane closes a lanes App pull request for a fresh attempt
at its issue, and the issue is parked once its fresh attempts are used up.

The report's Assessment and the manifest carry the `Evidence loop:` line, and the `Capture:` line
with the capture status, its reason and its count (Stage 2 step 1).

**Evidence retention.** Each run's local evidence (the `affected` output, the `/testing:run-e2e`
run directory or a pointer to it, raw captures) goes in its evidence directory,
`<memory_dir>/<slug>/scratch/evidence/<branch-slug>/<sha>/`; a run on uncommitted changes uses
`<sha>-uncommitted/`, and a detached head uses `detached` for `<branch-slug>`. After the run, under
that `<branch-slug>/` directory keep the directories of the 3 heads with the latest entries in
`heads` and delete every other directory, `-uncommitted` ones included except this run's; under
`detached/`, keep the 3 most recently written. The pasted manifest lives as long as the pull request
or issue that carries it.

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
| `/verification:confirm` finds gaps | Fix, then re-run `/verification:confirm`, unless the evidence loop was already at its cap of 3 before this verdict (Evidence loop) |
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
product source), offer it to the person at the end of the run, beside the report:
If /verify is available in your session (gate basis: `disableBundledSkills` or a `skillOverrides`
entry hides it; records in [reference/native-verify.md](reference/native-verify.md)), you can run
it alongside this skill to drive the change end to end. Skip the offer for a diff touching
only tests, docs, or code with no runtime surface. When the caller passes `--unattended`, the run records the offer in its output instead of asking; without that flag
it asks. Its result is added evidence; it replaces neither Stage 1 nor the verdict.

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

## Next

- Verdict CONFIRMED: /source-control:pull-request.
- Improvement claimed without data: /verification:measure.
- Gaps found, evidence loop count below 3 before this verdict: fix them, then /verification:confirm.
- NEEDS WORK with `Evidence loop: 3/3 cap reached, last NEEDS WORK`: /source-control:pull-request,
  so the pipeline's park-and-retry path takes over.
- Touched features not matched (app-control not installed): install the app-control plugin.
- Lessons listed, or a touched feature's control skill not refreshed: /app-control:map refresh
  <feature> ["<lesson>"] (or <control skill path> for every feature), or /corrections:codify
  "<lesson>" for one not about driving the app.

## Gotchas

- **Stage 1 is a gate, not the deliverable.** A green build is the prerequisite; the deliverable is outcome confirmation. Don't stop at "it builds."
- **"It passes tests" is not outcome confirmation.** Tests prove behavior; outcome confirmation proves it's the RIGHT behavior. A well-tested feature that misses the intent is still wrong.
- **Don't skip outcome confirmation for "obvious" changes.** Small changes drift from intent unnoticed; the intent check catches scope creep and missed requirements tests don't cover.
- **Don't quantify improvement claims here.** "Faster" / "simpler" claims route to `/verification:measure` and its baseline discipline. Invoke it via the Skill tool; never assert an improvement from this skill's evidence alone.
- **Doubt the observation before the code.** When a check fails or contradicts the diff, first rule out how you looked: a stale build, a cached page, the wrong port or instance, a log read before the write landed, a stub still in place. Observe again by a second route; only a result that survives it counts against the change.
- **Don't re-run Stage 1 if it already passed this conversation** and nothing changed since. Reuse the results.
- **Live-app fallback is fidelity-preserving.** If the bundled `/run` can't launch the app, fall back to invoking `/testing:run-e2e` via the Skill tool when the `testing` plugin is installed, or a manual orchestrator launch otherwise, and say so explicitly, never silently swap live observation for a static check.
