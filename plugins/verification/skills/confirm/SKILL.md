---
name: confirm
description: "Prove a change achieved its intended outcome: a mechanical build+test+lint prerequisite (delegated to /toolchain:check and /toolchain:lint, STOPs if broken), then outcome verification — does the change match the plan/intent and function correctly, with the criterion auto-detected by change-type (feature, fix, refactor). Use for 'verify changes', 'prove this works', 'did we build the right thing'; for quick mechanical-only checks use /toolchain:check, for measurable-improvement claims use /verification:measure."
user-invocable: true
argument-hint: "[mode] [ecosystem] (e.g., /verification:confirm, /verification:confirm outcome, /verification:confirm fix, /verification:confirm refactor, /verification:confirm dotnet)"
disable-model-invocation: false
---

## Pre-computed context

Working tree status: !`git status --porcelain 2>/dev/null || echo ""`
Changed files (vs HEAD): !`git diff --name-only HEAD 2>/dev/null || echo ""`
Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`

## Purpose

`/verification:confirm` answers **"did we build the right thing, and does it work?"** — it proves a change achieved its intended outcome. It is an **orchestrator**, not a reimplementation of the mechanical pass.

Two stages, in order:

| Stage | Question | Mechanism |
|-------|----------|-----------|
| 1. Mechanical **prerequisite** | "does it build, pass tests, satisfy linters?" | delegate `/toolchain:check` + `/toolchain:lint` cross-cutting + architecture-test gate. **STOP the flow if it fails** — can't verify broken code |
| 2. Outcome **verification** (the core) | "does the change match the plan/intent and function correctly?" | intent match + evidence + (runtime) `/testing:e2e` / live-app observe |

The mechanical pass is a *gate*, not the point. `/toolchain:check` owns build+test+lint; `/toolchain:lint` owns cross-cutting checks. This skill composes them, then does the verification they cannot: did the change accomplish its goal.

**Quick mechanical-only?** Use `/toolchain:check` (not `/verification:confirm`). **Lint-only?** `/toolchain:lint`. **Tests-only?** `/toolchain:check <ecosystem>`. Reach for `/verification:confirm` when you need outcome confirmation — proof, not just a green build.

## Arguments

`$ARGUMENTS` — optional mode and/or ecosystem filter.

**Modes** (each = an outcome criterion; Stage 1 runs first regardless):

| Mode | Outcome criterion |
|------|-------------------|
| (auto) | Detect change-type from conversation, then apply the matching criterion below |
| `outcome` | Feature / general: matches plan/design/discussion + functions (unit/integration) + (UI) looks correct (E2E + visual) |
| `fix` | Original bug symptom resolved + no regression |
| `refactor` | Behavior preserved — same tests pass, no semantic change |

There is **no standalone "mechanical pass" mode** — that role belongs to `/toolchain:check`. Stage 1 here is the prerequisite gate for every outcome criterion. Measurable-improvement claims (`performance` / `metrics` vs a captured baseline) are `/verification:measure`, not a mode here.

**Ecosystem filters** (combinable with any mode): `dotnet`, `python`, `typescript` (or `ts`/`node`), `bash` (or `shell`), `powershell` (or `ps`/`pwsh`), `all`. If omitted, auto-detect from changed files.

## Mode dispatch

Parse `$ARGUMENTS` for a mode keyword first, then an ecosystem filter.

| Signal | Mode | Read |
|--------|------|------|
| `outcome`, "does this match intent", "prove this works", bare `/verification:confirm` with feature context | **outcome** | [context/outcome.md](context/outcome.md) |
| `fix`, "is this resolved", bug-fix context | **fix** | [context/fix.md](context/fix.md) |
| `refactor`, behavior preservation | **refactor** | [context/refactor.md](context/refactor.md) |
| `performance` / `metrics`, "before/after", "is it faster", "is it cleaner/simpler" | *redirect* | invoke `/verification:measure` (measurable-delta twin) |

**Smart default (no mode argument)** — detect from conversation:

- Bug-fix context → `fix`
- Refactor context → `refactor`
- Improvement claim (faster / simpler / cleaner / fewer deps) → redirect to `/verification:measure`
- Just finished implementation + review, or an approved plan exists → `outcome`
- Otherwise → `outcome` (the safe default — it subsumes intent match)

## Runtime-affecting paths

These categories decide when a change escalates beyond the per-ecosystem mechanical pass. When the consuming project documents its own runtime-affecting globs, those govern; otherwise use these portable defaults:

- **`e2e-app-runtime`** — API/app changes (endpoints, attributes, contracts, middleware): the project's app source directories
- **`e2e-ui-frontend`** — components and static assets shipped to the browser: `**/*.razor`, `**/*.razor.cs`, `**/*.cshtml`, `**/wwwroot/**`, and the project's SPA/frontend source
- **`e2e-runtime-config`** — runtime configuration (`**/appsettings*.json`, orchestrator config, env-shaping files)
- **`arch-test-triggers`** — project-structure / dependency changes (`**/*.csproj`, `**/*.props`, `**/*.targets`, `**/Directory.Build.*`) — re-run the project's architecture-test suite when it has one

## Stage 1 — Mechanical prerequisite (delegate, don't reimplement)

The gate. Runs before any outcome criterion. **If it fails, STOP** — report the failures; outcome confirmation is meaningless on code that doesn't build or pass tests.

Stage 1 delegates to the `toolchain` plugin's `/toolchain:check` and `/toolchain:lint` when that plugin is installed; when it is absent, run the project's own ecosystem-native build / test / lint commands (from its `CLAUDE.md` / rules) directly — the gate and its STOP-on-fail semantics are unchanged, only the executor differs.

1. **Build + test + lint per ecosystem** — when changed files span multiple ecosystems or the mechanical pass is non-trivial, dispatch a subagent with the changed-file paths and `/toolchain:check`'s command tables, and verify its summary against the actual command output; otherwise invoke `/toolchain:check` via the Skill tool. `/toolchain:check` remains SSOT for ecosystem detection, CLI commands, and gotchas. Pass through the ecosystem filter from `$ARGUMENTS` if given; else `/toolchain:check` auto-detects from changed files.
2. **Architecture tests** — when changed files match the `arch-test-triggers` globs above and the project has an architecture-test suite, ensure it is included in the test step.
3. **Cross-cutting checks** — invoke `/toolchain:lint cross-cutting` via the Skill tool. `/toolchain:lint` owns the cross-cutting tools with the presence-gated graceful-degradation pattern (missing tool → `skip`, never `FAIL`). Do **not** inline that bash here — `/toolchain:lint` is the SSOT.

**Gate result:** if `/toolchain:check` or `/toolchain:lint cross-cutting` reports any FAIL, stop and surface the failing command's key error lines. Fix mechanical failures before outcome verification proceeds. If everything passes (or `skip`s), proceed to Stage 2.

## Stage 2 — Outcome verification (the core)

Read the criterion context file for the dispatched mode, then run the flow below. The shared spine (intent → inventory → match → evidence → report) is in [context/outcome.md](context/outcome.md); `fix` / `refactor` adapt it.

1. **Auto-trigger `/testing:e2e` (when runtime-affecting)** — inspect changed files. If any match an `e2e-*` category from the Runtime-affecting paths above, or touch observability code paths verifiable end-to-end, or the user said "test the app", invoke `/testing:e2e` via the Skill tool when the `testing` plugin is installed — otherwise drive the live app directly (Claude Code's bundled `/verify` + `/run`, or a manual orchestrator launch) and capture the same evidence. When present, it validates prerequisites, starts the app, exercises the changed flow, and captures evidence (screenshots, console, network, traces). Carry that into the evidence table. If not runtime-affecting (pure refactor, internal lib, doc-only): note "E2E not applicable" and skip.
2. **Intent retrieval** — scan the conversation for the original request, the approved plan, refinements, and acceptance criteria. If none is clear, ask the user what the goal was.
3. **Implementation inventory** — changed files, new capabilities, behavior changes, config/infra changes.
4. **Intent match** — every requirement has implementation; every implementation traces to a requirement; flag scope additions and gaps (including implicit requirements — error handling, edge cases, tests).
5. **Evidence collection** — Stage-1 results, E2E results, test names + assertions proving the claimed behavior. For UI changes: the UI evidence artifacts per [context/outcome.md](context/outcome.md) (pre/action/post snapshot, console, network, behavior assertion — "screenshot looks fine" is NOT an assertion). When the plan states a measurable goal: the `/verification:measure` comparison table.
6. **Report + verdict** — emit the outcome report (intent-match table, mechanical results, E2E + UI-evidence tables when triggered, evidence table, measurements when applicable) and a `CONFIRMED` / `NEEDS WORK` verdict. Report template + severity vocabulary in [context/outcome.md](context/outcome.md).

**Independence of the verdict.** This skill usually runs in the context that produced the changes — and that context carries the assumptions that produced any defect, converging on approval rather than detection. Stage 1's mechanical pass/fail is objective and needs no escalation, but for the Stage 2 outcome verdict on anything beyond a mechanical, behavior-preserving change, render `CONFIRMED` / `NEEDS WORK` from an agent that did NOT produce the artifact: dispatch a fresh-context verifier with the acceptance criteria and the diff, withholding your rationale so it audits the artifact and not your story. Where the outcome is high-stakes and correlated blind spots are the risk, prefer a cross-vendor reviewer **when one is installed** — e.g. the OpenAI Codex plugin's `/codex:review` (read-only) or `/codex:adversarial-review`, so the second opinion comes from a different model rather than a same-vendor echo. When no cross-vendor reviewer is available, the same-vendor fresh-context verifier above is the fallback — never route the verdict to a command that may not resolve.

When `/testing:e2e` ran, persist an assertion-only evidence manifest (what was asserted, at which commit — record `verified_at_sha`) to the topic's contract slice at `<contract_dir>/<slug>/verification/` (default `docs/topics/`; the memory slice under `contract_tier: local`), resolved per the topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)). Under `contract_tier: branch` the manifest is committed on the task branch; under `local` it stays in the self-ignored memory slice (the PR-description paste is its publication surface). Either way it meets the contract's redaction bar: distilled assertions only — no raw command captures, no machine-local paths, no usernames or credentials; cite a `## Reproduction` block instead. Raw captures stay in the memory tier at `<memory_dir>/<slug>/scratch/` (default `.work/`), never committed.

## Delegation: live-app run + observe

For "run the live app and watch it behave" — beyond automated `/testing:e2e` — `/verification:confirm` delegates rather than reimplementing app-launch:

- **Primary: `/testing:e2e`** (when the `testing` plugin is installed) — the reliable path for orchestrated apps (Aspire, docker-compose, tilt) via the project's orchestrator tooling + Playwright CLI.
- **Supplementary: Claude Code's bundled `/verify` + `/run`** — when a quick interactive run is enough and the orchestrated harness is overkill (requires Claude Code ≥2.1.145 — verified 2026-07-18 against [bundled skills](https://code.claude.com/docs/en/skills#bundled-skills)).
- **Graceful fallback** — if the bundled skills cannot infer the project's launch (or the CC version lacks them), fall back to `/testing:e2e` when the `testing` plugin is installed, or a manual orchestrator launch otherwise. Never silently downgrade live-app verification to a static check — surface the gap.

## Edge cases

- **No git changes but user runs `/verification:confirm all`**: run Stage 1 across all ecosystems anyway (useful after a rebase or pull), then outcome verification if intent is in scope.
- **Changed file outside any known ecosystem**: Stage 1 skips it with a note; Stage 2 still assesses intent match.
- **Missing tools**: `/toolchain:check` / `/toolchain:lint` report `skip` with install hint, not failure — except the core toolchain the project's own code requires.
- **Invoked from a PR-prep flow**: treat the verdict as a hard gate — any FAIL or unresolved CRITICAL gap blocks PR creation.

## Skill chaining

| Condition | Action |
|-----------|--------|
| Review gate passes (no blocking findings — e.g. `/review:quality-gate` when installed) | Suggest `/verification:confirm` |
| Stage 1 fails | Fix build/test/lint/cross-cutting, then re-run `/verification:confirm` |
| Runtime-affecting change | Stage 2 auto-triggers `/testing:e2e` (bundled `/verify` / `/run` supplementary) |
| `/verification:confirm` finds CONFIRMED | Suggest a retro (`/session-flow:retro` when installed), then the project's PR flow (`/source-control:pull-request` when installed) |
| `/verification:confirm` finds gaps | Fix, then re-run `/verification:confirm` |
| Improvement claimed without data | Redirect to `/verification:measure` (`performance` or `metrics`; baseline captured at planning time) |

## What this skill does NOT do

- **Does not reimplement the mechanical pass** — `/toolchain:check` (build+test+lint) and `/toolchain:lint` (cross-cutting) are SSOT. Stage 1 delegates to them.
- **Does not auto-fix** — identifies failures and gaps; the implementer fixes them. For lint auto-fix, run `/toolchain:lint --fix`.
- **Does not check design quality for ship-readiness** — that's the project's review/quality-gate flow.
- **Does not verify measurable-improvement claims** — `/verification:measure` owns the baseline/compare mechanism; this skill redirects improvement claims there.
- **Does not replace PR prep** — the project's PR flow orchestrates review + verification + cleanup. This skill is the verification component.

## Gotchas

- **Stage 1 is a gate, not the deliverable.** A green build is the prerequisite; the deliverable is outcome confirmation. Don't stop at "it builds."
- **"It passes tests" is not outcome confirmation.** Tests prove behavior; outcome confirmation proves it's the RIGHT behavior. A well-tested feature that misses the intent is still wrong.
- **Don't skip outcome confirmation for "obvious" changes.** Small changes drift from intent unnoticed; the intent check catches scope creep and missed requirements tests don't cover.
- **Don't quantify improvement claims here.** "Faster" / "simpler" claims route to `/verification:measure` and its baseline discipline — never assert an improvement from this skill's evidence alone.
- **Don't re-run Stage 1 if it already passed this conversation** and nothing changed since — reuse the results.
- **Live-app fallback is fidelity-preserving.** If the bundled `/verify` / `/run` can't launch the app, fall back to `/testing:e2e` and SAY SO — never silently swap live observation for a static check.
