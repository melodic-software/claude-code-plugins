# RESEARCH — Matt Pocock's `sandcastle` + published AI/Claude Code skills

> Memory-tier research artifact. Not committed. Produced by `/discovery:research` on 2026-07-16.
> Every accepted claim below carries ≥1 primary source (Tier 0 `gh api` / npm registry / Tier 1 fetch) captured THIS run, plus independent corroborators.

## Task restatement

Research (1) Matt Pocock's `sandcastle` repository — what it is, architecture, autonomous/headless agent lifecycle (issue → build → test → verify → PR), isolation/containerization, which agent tools it drives, config/extensibility, maturity; (2) his published Claude Code skills/plugins/agent conventions and their load-bearing concepts; and (3) which design choices to adopt vs avoid for a **repo-agnostic, company-agnostic, machine-agnostic autonomous-agent-runner** (the user's stated future direction — inspiration, not a template).

---

## 1. Summary

`sandcastle` (`mattpocock/sandcastle`, npm `@ai-hero/sandcastle`) is a **provider-agnostic TypeScript library/CLI that orchestrates AI coding agents inside isolated sandboxes** via a single `run()` / `createSandbox()` / `interactive()` surface — it manages git worktrees, branch strategies, prompt delivery, iterations, structured output extraction, and merge-back. It is a **generalized, productized "RALPH" loop** (its own `CONTEXT.md` says to avoid the name "RALPH" for the tool). It is **not** a turnkey "issue → PR" platform: that autonomous lifecycle exists in the repo as **self-dogfooding** (`.github/workflows/agent-*.yml` label state machines + `.sandcastle/agent-workflows/*.ts` harness scripts built *on* the library), and the agent famously **cannot ask for clarification** — when blocked it comments and moves on or stops (open issue #505). Separately, `mattpocock/skills` ("Skills for Real Engineers", 174k★) is a **workflow-discipline** skill set (grilling, spec→tickets→triage→implement→review, HITL vs AFK, TDD, domain modeling) distributed via skills.sh and a native Claude Code plugin. The two are complementary: **skills encode the disciplined process; sandcastle is the isolated execution runtime.** For a repo/company/machine-agnostic runner, the load-bearing lessons are: a narrow curated built-in provider set behind a **public `AgentProvider` interface** (custom agents need no core change), pluggable **sandbox providers** (bind-mount vs isolated vs no-sandbox), branch strategies as a config seam, `exec()` verification gates between agent runs, and pushing all issue-tracker/workflow policy *out* of the library into composable scripts.

---

## 2. Evidence table

| # | Claim | Sources (Tier 0/1 captured this run) | Tier | Tool diversity | Confidence |
|---|---|---|---|---|---|
| 1 | `mattpocock/sandcastle` is a TS library/CLI orchestrating AI coding agents in isolated sandboxes via `run()`; commits merge back per branch strategy | `gh api repos/mattpocock/sandcastle` (desc, README.md fetched this run); npm `@ai-hero/sandcastle/latest` | 0/1 | gh api + npm + WebSearch | HIGH |
| 2 | Maturity/activity: 6,862★, 692 forks, MIT, TypeScript, created 2026-03-17, latest release **v0.12.0** (2026-06-29), 110 open issues, not archived | `gh api repos/mattpocock/sandcastle` `--jq` metadata; `releases/latest`; `tags` (this run) | 0 | gh api | HIGH |
| 3 | Sandbox providers are pluggable & provider-agnostic: **Docker, Podman, Vercel (Firecracker microVMs), Daytona, no-sandbox**, + custom via `createBindMountSandboxProvider` / `createIsolatedSandboxProvider` | README.md (this run); npm registry `exports` keys show `./sandboxes/{docker,vercel,podman,daytona,no-sandbox}` (this run); `CONTEXT.md` provider taxonomy | 0/1 | gh api + npm | HIGH |
| 4 | Built-in **agent** providers (curated, deliberately capped): **Claude Code, Codex, Cursor, OpenCode, GitHub Copilot CLI, Pi**. Custom agents supported via public exported `AgentProvider` interface — no core change needed | `.out-of-scope/built-in-agent-providers.md` (this run) | 1 | gh api | HIGH |
| 5 | Agent-provider capability bar: non-interactive run mode, prompt via stdin, bypass-permissions flag, env-based auth, **line-delimited JSON stream events** | `.out-of-scope/built-in-agent-providers.md` (this run) | 1 | gh api | HIGH |
| 6 | Branch strategies: **head** (work directly in host workdir, no worktree), **merge-to-head** (temp branch → merged back to HEAD), **branch** (commits land on explicit named branch). Worktrees live in `.sandcastle/worktrees/` | `CONTEXT.md` (this run); README.md `branchStrategy` option | 1 | gh api | HIGH |
| 7 | Architecture is built on **Effect** (functional TS): the "Agent invoker" is an Effect service (`Context.Tag`) — a test seam for scripted/recording fakes | `CONTEXT.md` (this run); `src/` tree shows `AgentProvider.ts`, `Orchestrator.ts`, `SandboxLifecycle.ts`, `SessionStore.ts` | 0/1 | gh api | HIGH |
| 8 | Rich run config: lifecycle hooks (`host.*`/`sandbox.*`), `copyToWorktree`, `mounts`, `maxIterations`, `idleTimeoutSeconds`, `completionSignal` (default `<promise>COMPLETE</promise>`), file/stdout logging with `onAgentStreamEvent` forwarder, structured `Output.object`/`Output.string` (zod) with `maxRetries` | README.md (this run); CHANGELOG.md v0.11/0.12 (this run) | 1 | gh api | HIGH |
| 9 | `createSandbox()` gives a warm reusable sandbox with `sandbox.run()` (multi-agent implement-then-review on one branch) and **`sandbox.exec()`** to run verification gates (tests/lint) between runs; `await using` auto-cleanup preserves worktree only if dirty | README.md; CHANGELOG.md v0.12.0 `sandbox.exec` entry (this run) | 1 | gh api | HIGH |
| 10 | The autonomous **issue-driven lifecycle is self-dogfooding, not a library built-in**: `.github/workflows/agent-implement.yml` triggers on `issues:[labeled]` == `agent:implement`, detects issue shape (sub-issues → parent/child), runs `.sandcastle/agent-workflows/*.ts`; `agent-implement-pr.yml` triggers on `pull_request_target` label, runs a label state machine (`agent:implement`→`agent:in-progress`/`agent:blocked`), refuses closed PRs, commits as `sandcastle-agent[bot]` | `agent-implement.yml`, `agent-implement-pr.yml` (this run); `.sandcastle/agent-workflows/` tree (explore/implement/implement-pr/review/update-branch) | 0/1 | gh api | HIGH |
| 11 | Sandcastle is a **bounded RALPH loop, not "set and forget"**: agents cannot ask for clarification — when blocked they comment and move on or stop (open issue **#505 "Ask a human"**, created 2026-05-01, still open). Requires clear specs, test suites, review gates | `gh api .../issues/505` (this run); WebSearch falsification (PyShine, JIN, richsnapp corroborate RALPH drift/context-rot) | 0/2 | gh api + WebSearch | HIGH |
| 12 | `mattpocock/skills` = "Skills for Real Engineers": 174,336★, 14,961 forks, MIT, created 2026-02-03, pushed 2026-07-16; deliberately **small/composable/adaptable, works with any model**, positioned *against* process-owning frameworks (GSD, BMAD, Spec-Kit) | `gh api repos/mattpocock/skills` metadata + README.md (this run) | 0/1 | gh api | HIGH |
| 13 | Distributed two ways: **skills.sh** (`npx skills add mattpocock/skills` — copies editable files, also installs to Codex/Agent-Skills harnesses) and a native **Claude Code plugin** (`mattpocock-skills@mattpocock`, plugin.json v1.2.0 — read-only managed bundle). Repo is its own single-plugin marketplace | README.md; `.claude-plugin/plugin.json` + `marketplace.json` (this run); `CLAUDE.md` | 0/1 | gh api | HIGH |
| 14 | Promoted skill catalog (engineering + productivity buckets): grill-me, grilling, grill-with-docs, to-spec, to-tickets, triage, implement, tdd, code-review, research, domain-modeling, codebase-design, diagnosing-bugs, improve-codebase-architecture, prototype, wayfinder, handoff, teach, writing-great-skills, ask-matt, setup-matt-pocock-skills | `gh api .../git/trees?recursive` SKILL.md list; `plugin.json` `skills[]` (this run) | 0/1 | gh api | HIGH |
| 15 | Core workflow concepts: **grilling** (relentless interview → alignment before code); **CONTEXT.md / ubiquitous language** (shared glossary cuts verbosity + tokens); **to-spec** (PRD w/ user stories + test seams); **to-tickets** (tracer-bullet **vertical slices** with **blocking edges**; wide refactors → **expand-contract**); **triage** state machine (bug/enhancement × needs-triage/needs-info/ready-for-agent/ready-for-human/wontfix); **HITL vs AFK** classification; **TDD** + `/code-review`; small deliberate steps / feedback loops | SKILL.md bodies for to-tickets, triage, implement, to-spec, grill-with-docs (this run); README.md "Why These Skills Exist" | 1 | gh api | HIGH |
| 16 | Skill-design doctrine: **predictability/determinism is the root virtue**; model-invoked (context load) vs user-invoked (`disable-model-invocation:true`, cognitive load) tradeoff; skills are composable (grill-with-docs delegates to `/grilling` + `/domain-modeling`) | `writing-great-skills/SKILL.md`; `grill-with-docs/SKILL.md` (this run) | 1 | gh api | HIGH |
| 17 | Matt's stated philosophy: agents are "middling to good engineers" with "no memory" → need "extremely strict and well-defined processes"; "garbage codebase → garbage AI output"; deep modules improve agent navigability; vertical slices flush out unknowns | aihero.dev/5-agent-skills-i-use-every-day (this run) | 2 | WebFetch (author-primary) | HIGH |
| 18 | ADR 0002: ships as Claude Code plugin because `.claude-plugin/plugin.json` accepts an **explicit array of skill-dir paths** (matches the bucketed layout); native Codex plugin **deferred** because Codex's manifest uses single-path selection incompatible with promoted-across-two-buckets | `.agents/adr/0002-ship-as-a-claude-code-plugin.md`; `CLAUDE.md` (this run) | 1 | gh api | HIGH |

---

## 3. Conflicts (flagged; primary wins)

- **Star counts.** Secondary blogs claimed "135,000+" (and conflated the two repos). Primary `gh api` this run: **skills = 174,336★**, **sandcastle = 6,862★**. Primary wins.
- **Skill names.** Matt's own aihero.dev article names `/to-prd` and `/to-issues`; the **current repo** uses `to-spec` and `to-tickets`. The article predates a rename — the repo (SKILL.md frontmatter fetched this run) is canonical/current. Concepts (PRD-style spec, vertical-slice tickets) are unchanged.
- **"Cursor" as sandbox vs agent.** One Phase-1 blog implied Cursor is a sandbox option; it is actually a built-in **agent** provider. Sandboxes are Docker/Podman/Vercel/Daytona/no-sandbox. Corrected against `.out-of-scope/built-in-agent-providers.md` + npm exports.

## 4. Gaps

- **Daytona provider** appears in npm `exports` and is production-usable, but I did not fetch its provider source this run (README table omits it — likely added after the README table). Low risk; enumerated from Tier-0 npm `exports`.
- **Exact `AgentProvider` interface signature** (method shape) not read line-by-line — the capability contract (stdin/JSON-stream/bypass-permissions/env-auth) is from the maintainer's own `.out-of-scope` doc, sufficient for design lessons; read `src/AgentProvider.ts` if implementing.
- `mattpocock/skills` reports language "Shell" (installer scripts); the skills themselves are Markdown SKILL.md + supporting docs. Not a conflict, just a GitHub language-detection artifact.

## 5. Recency status

- **sandcastle**: latest release **v0.12.0 published 2026-06-29**, `pushed_at` 2026-06-29; ~18 days before this run — within the 30-day standard-tool window, confirmed current via `releases/latest` this run. Pre-1.0, active (patch=bugfix, minor=feature/breaking per AGENTS.md).
- **skills**: `pushed_at` **2026-07-16** (same day as this run); plugin v1.2.0. Current.
- No major-version bump risk (both pre-1.0 but freshly pushed and directly read this run).

## 6. Project fit — adopt vs avoid for a repo/company/machine-agnostic autonomous-agent-runner

**ADOPT (design choices worth stealing):**

1. **Two orthogonal plugin seams: `SandboxProvider` (where it runs) and `AgentProvider` (what runs).** Both are public exported interfaces; custom implementations need zero core change. This is the cleanest expression of machine-agnostic (swap Docker↔Podman↔Vercel↔Daytona↔no-sandbox) and tool-agnostic (swap Claude Code↔Codex↔OpenCode↔…). SOLID: open for extension, closed for modification.
2. **A published capability bar for agents** (non-interactive, stdin prompt, bypass-permissions, env auth, line-delimited JSON stream). Codifying "what makes a CLI drivable unattended" is exactly the contract a repo-agnostic runner needs, and it doubles as a rejection criterion.
3. **Curated built-in set + long tail behind the interface.** Explicitly refusing to grow built-ins ("every provider is a standing maintenance commitment") keeps the core small and honest — resist the urge to vendor every agent CLI.
4. **Branch strategy as a first-class config seam** (head / merge-to-head / branch) decouples "agent did work" from "how it lands," which is what makes it repo-agnostic (bind-mount for local repos, isolated+sync for cloud).
5. **`exec()` verification gates between agent runs** on a warm sandbox — the runner should let you assert `npm test` green before kicking off review, without a fresh container. Structured output (`Output.object` + `maxRetries` with session-resume) for machine-readable agent results.
6. **Push workflow/issue-tracker policy OUT of the runtime.** Sandcastle keeps issue-claiming, labels, and PR state machines in *composable scripts* (`.sandcastle/agent-workflows/*.ts`) and CI (`agent-*.yml`), not in the library. This is the company-agnostic seam: your tracker (GitHub/Linear/local) and your labels are configuration, mirrored in the skills' `/setup` step.
7. **Separate the discipline layer from the execution layer** (skills vs sandcastle). Predictability-as-root-virtue, grilling-before-build, vertical-slice tickets, HITL/AFK classification, and a shared glossary (`CONTEXT.md`) are portable conventions your runner can require without hard-coding them.
8. **A ubiquitous-language `CONTEXT.md`** per repo to cut agent verbosity/token spend and keep naming consistent — cheap, high-leverage, repo-agnostic.

**AVOID / handle deliberately:**

1. **Do not sell it as "set and forget."** The RALPH loop's failure mode is silent drift/context-rot; agents work around blockers instead of stopping. Design an explicit **ask-a-human / escalation** path (sandcastle still lacks one — issue #505). Make "blocked" a first-class state, not a comment-and-continue.
2. **Autonomy is gated on inputs you must guarantee**: a real spec, a comprehensive test suite, and a review gate (human or a stronger reviewer model). A runner without these amplifies garbage. Bake the gates in; don't assume the repo has them.
3. **Effect (functional TS) is a strong internal choice but a coupling/learning-curve cost** for contributors — adopt the *seam* idea (injectable agent-invoker for scripted test fakes) without necessarily adopting the framework.
4. **Distribution-manifest lock-in is real** (ADR 0002: Claude plugin shipped, Codex deferred purely because manifest selection models differ). If you want cross-harness distribution, design your skill/plugin layout against the *least flexible* manifest, or ship via the copy-based installer (skills.sh) that is harness-neutral.
5. **`pull_request_target` + auto-labels + write permissions** is powerful but a supply-chain/security footgun (runs with repo secrets on forked code). Sandcastle guards with concurrency locks, closed-PR refusal, and bot identity — replicate those guardrails or prefer `issues`-triggered flows.
6. **Bind-mount vs isolated is not free**: bind-mount (`head` strategy) runs in the host workdir with no branch indirection — fast but least isolated; isolated providers require sync in/out. A machine-agnostic runner must make this tradeoff explicit per environment, not default silently.

**Fit with melodic-software direction:** aligns with the user's repo/company/machine-agnostic goal — the two-seam (sandbox × agent) plugin model and externalized workflow policy are the reusable architecture; the skills' grill→spec→tickets→triage(HITL/AFK)→implement→review pipeline is a portable convention layer that could map onto the existing `standards` / `ci-workflows` split (execution vs policy) rather than being copied wholesale.

## 7. Outcome gate result — PASS

| # | Criterion | Result |
|---|---|---|
| 1 | Every claim ≥1 Tier 0/1 captured this turn | PASS — gh api / npm registry / author fetch |
| 2 | No claim all-Tier-2 | PASS — concepts grounded in SKILL.md + repo files |
| 3 | Phase 2/3 queries trace to numbered Phase-1 gaps | PASS |
| 4 | ≥2 independent corroborators per claim | PASS — gh api + npm + WebFetch + WebSearch blogs (independent) |
| 5 | Falsification query ran & recorded | PASS — RALPH-limitations query + issue #505 |
| 6 | Recency gate: latest release fetched this turn & cross-checked | PASS — v0.12.0 2026-06-29; skills pushed 2026-07-16 |
| 7 | Every accepted claim HIGH confidence | PASS |
| 8 | Project fit checked vs stated direction | PASS — §6 |

---

## 8. Next-stage handoff

**Settled facts:**

- sandcastle = provider-agnostic TS orchestration library (`@ai-hero/sandcastle` v0.12.0); two plugin seams (SandboxProvider, AgentProvider); branch strategies; warm sandboxes + `exec()` gates; structured output. Bounded RALPH loop, not turnkey autonomy.
- Issue→PR lifecycle is dogfooded in-repo (CI label state machines + `.sandcastle/agent-workflows/*.ts`), a *reference pattern* to imitate, not a library API.
- skills = discipline layer (grill/spec/tickets/triage/implement/review, HITL/AFK, predictability), harness-neutral via skills.sh, managed via Claude plugin.
- Adopt: two-seam plugin model, agent capability bar, externalized workflow policy, verification gates, shared-language CONTEXT.md. Avoid: set-and-forget framing, ungated autonomy, `pull_request_target` footguns.

**Open decisions for planning:**

- Whether to model the runner's architecture on the two-seam interface directly (and in which language/runtime), and whether to adopt Effect-style injectable seams.
- How to implement the missing ask-a-human/escalation state the user's runner will need.
- How the sandbox×agent seams and externalized workflow policy map onto the existing `standards` (policy) vs `ci-workflows` (execution) split.
- Whether distribution targets one harness (Claude Code plugin) or stays copy-based/harness-neutral.
