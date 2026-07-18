# RESEARCH — Peer frameworks to Matt Pocock's `sandcastle`

## Task

Identify frameworks/libraries comparable to `sandcastle` (github.com/mattpocock/sandcastle) — orchestrators that run AI coding agents autonomously/headlessly in isolated sandboxes, ideally provider-agnostic across agent CLIs (Claude Code, Codex, Cursor, Copilot…) and/or sandbox backends (Docker, Firecracker, cloud) — as of mid-2026. Apply a **hard credibility filter**: author/org must be a proven trusted industry figure or established company, and the project must be actively maintained. Characterize each qualifying candidate, mark pass/fail, and produce a shortlist ranked by fit for a **repo-agnostic, company-agnostic, machine-agnostic autonomous-runner with an interactive-upstream / autonomous-downstream split**. Decide whether building on one beats building inspired-by-sandcastle from scratch.

Run per `/discovery:research` disciplines (broad-topic → doubled minimums: 6+ queries/phase, 5+ tool types, 4+ Tier 0/1 per shortlist claim; mandatory Phase-2 falsification; primary sources fetched directly this turn).

---

## 1. Summary

**Sandcastle occupies a genuinely distinct niche and survives falsification: it is the rare thing that is agent-CLI-agnostic AND sandbox-backend-agnostic AND open/self-hostable, packaged as a minimal composable TypeScript library with a `run()` (autonomous) / `interactive()` (human) split.** Applying the credibility filter to the ~100+ orchestrator long tail leaves ~5 institution/figure-backed peers, and **none of them dominates sandcastle on all three axes**: Vercel's `HarnessAgent` is a complementary agent-CLI *adapter* layer (not a competitor) but its practical sandbox is Vercel-cloud-leaning; Steve Yegge's **gastown** has the richest built-in lifecycle (merge queue + verification gates + severity-routed human escalation) but isolates only via git worktrees and is an opinionated end-to-end system; **OpenHands** (All Hands AI) is the most mature and now agent-agnostic, but is a full self-hosted *platform*; **OpenAI Symphony** has the best work-management/verification framing but is Codex-oriented and spec-first. **Verdict: building on / inspired-by sandcastle is justified** — no single established-vendor stack is a machine-agnostic, multi-agent, self-hostable drop-in; the pragmatic architecture composes sandcastle's orchestration+sandbox spine with Vercel/AI-SDK adapters, gastown's lifecycle model, and a pluggable backend.

---

## 2. The deciding discriminator (three axes + one split)

The team lead's requirement (repo-agnostic + company-agnostic + machine-agnostic, interactive-upstream/autonomous-downstream) resolves to:

- **Axis A — agent-CLI-agnostic:** wraps multiple *existing* agent CLIs (Claude Code, Codex, Cursor, Copilot, Gemini, opencode…), not one hard-wired agent.
- **Axis B — sandbox-backend-agnostic:** pluggable isolation (Docker/Podman, Firecracker/microVM, gVisor, cloud, custom) — the "machine-agnostic" gate.
- **Axis C — open + self-hostable:** not locked to a single vendor's cloud — the "company-agnostic" gate.
- **The split:** a headless autonomous path AND a human/interactive path (sandcastle's `run()` vs `interactive()`).

Sandcastle is A✓ B✓ C✓ + split. Every established-vendor alternative breaks at least one.

---

## 3. Candidate dispositions (PASS credibility filter / FAIL, with reason)

### 3a. Shortlist — PASS filter, plausibly buildable-on (programmable orchestration peers)

| Framework (owner) | Tier-0 (this turn) | A agent-agnostic | B sandbox-agnostic | C open/self-host | Lifecycle / verify / escalate | Shape |
|---|---|---|---|---|---|---|
| **sandcastle** (Matt Pocock) | `gh api`: 6,862★, MIT, TS, pushed 2026-06-29, rel **v0.12.0** | ✓ `claudeCode`,`codex`,`cursor`,`copilot`,`opencode`,`pi` | ✓ Docker/Podman bind-mount, Vercel Firecracker, no-sandbox, **custom** via `createBindMountSandboxProvider`/`createIsolatedSandboxProvider` | ✓ MIT, 100% offline-capable | user-code (templates: `simple-loop`, `parallel-planner`, `sequential-reviewer`); `sandbox.exec()` for gates; `interactive()` for human | **minimal library** (`sandcastle.run()`) |
| **Vercel AI SDK `HarnessAgent`** (Vercel) | `gh api` vercel/sandbox: Apache-2.0, pushed 2026-07-16; docs fetched | ✓ Claude Code, Codex, Pi, **+ OpenCode, Deep Agents** adapters | ~ `HarnessV1SandboxProvider` iface (pluggable in principle); bridge harnesses "require a real network sandbox like `@ai-sdk/sandbox-vercel`" | ~ AI SDK open, but practical sandbox = **Vercel cloud** | user-code; `generate()`/`stream()`, `createSession()` | **library** (agent-CLI *adapter* layer) |
| **gastown / "Gas Town"** (Steve Yegge) | `gh api`: 17,059★, MIT, Go, pushed 2026-07-15, rel **v1.2.1** | ✓ Claude Code, Copilot, Codex, Gemini, Cursor (per-rig config) | ~ **git-worktree isolation only** (no container/VM plug-in) | ✓ MIT; native macOS/Linux/Windows + Docker Compose | **✓✓ built-in**: Bors-style merge queue "**Refinery**" (batches MRs, runs gates, bisects failures); **severity-routed escalation** (Deacon→Mayor→Overseer, P0/P1/P2); persistent work tracking | **opinionated end-to-end system** |
| **OpenHands** (All Hands AI) | `gh api`: 81,028★, pushed 2026-07-17, rel **cloud-1.46.2** (2026-07-15) | ✓ own OSS agent **+ "any third-party agent like Claude Code and Codex"** | ~ Docker container / VM runtime (direct-install = full host access) | ✓ "self-hosted developer control center"; local/Docker/VM | GitHub-issue decomposition; CI/GH integration (full issue→PR verify not fully documented) | **self-hosted platform / control center** |
| **Symphony** (OpenAI) | `gh api`: 25,995★, Apache-2.0, Elixir, pushed 2026-06-09; homepage openai.com/index/open-source-codex-orchestration-symphony | ~ **Codex-oriented** ("open-source Codex orchestration") | ? not documented | ✓ open; spec + Elixir reference impl | **✓** monitors a **Linear board** → spawns autonomous runs → **proof-of-work verification** (CI status, PR review, complexity, walkthrough videos) | **spec + reference implementation** ("manage work, not agents") |

### 3b. PASS filter but different shape — autonomous *agent products* (fail Axis A: they ARE the agent)

| Project (owner) | Tier-0 (this turn) | Why not a sandcastle peer |
|---|---|---|
| **Goose** (Agentic AI Foundation / Linux Foundation; originated at Block) | `gh api` `aaif-goose/goose`: 51,206★, Apache-2.0, Rust, pushed 2026-07-17, rel **v1.43.0** (+ v2.0.0-rc); org bio "goose ai agent platform" | Single extensible agent (spawns subagents), LLM-agnostic (15+ providers), self-host, has "sandbox mode" — but it **is** the agent, not a multi-CLI wrapper. Credibility: Linux Foundation, vendor-neutral. |
| **SWE-agent** (Princeton — SWE-agent org) | `gh api`: 19,831★, MIT, Python, pushed 2026-07-16 | Single agent: GitHub issue → patch with any LM; research/CTF focus. Not a CLI-agnostic orchestrator. Academic credibility. |
| **Codex** (OpenAI) | `gh api` `openai/codex`: 98,890★, Apache-2.0, Rust | The agent CLI + cloud itself — a **target** sandcastle wraps, not a peer. |
| **Cursor / GitHub Copilot coding agents** | (vendor products) | Vendor-hosted single agents; Copilot coding agent runs in GitHub Actions. Not open multi-CLI orchestrators. |
| **Devin** (Cognition, cognition.com) | site is commercial (cognition.ai→cognition.com) | **Closed commercial SaaS** autonomous engineer; no open library, not self-hostable, not agent-agnostic. Relevant product, **not buildable-on**. |

### 3c. PASS filter but different layer — components / general SDKs (not orchestrator peers)

| Project (owner) | Tier-0 (this turn) | Role |
|---|---|---|
| **E2B** | `gh api` `e2b-dev/E2B`: 13,011★, Apache-2.0, pushed 2026-07-16 | **Sandbox backend** (Firecracker microVM, dedicated kernel). Axis-B provider, not an orchestrator. |
| **Daytona** | `gh api`: 72,275★, pushed 2026-07-09 | **Sandbox backend** (container + optional Kata/Sysbox; fastest cold start, ~27–90 ms). Axis-B provider. |
| **Modal** | `gh api` `modal-labs/modal-client`: Apache-2.0, pushed 2026-07-16 | **Sandbox/compute backend** (gVisor + syscall filtering). Axis-B provider. |
| **Vercel Sandbox** | `gh api` `vercel/sandbox`: 163★, Apache-2.0, pushed 2026-07-16 | **Sandbox backend** (Firecracker microVM) — already one of sandcastle's built-in providers. |
| **Anthropic Claude Agent SDK** | `gh api` `anthropics/claude-agent-sdk-python`: 7,646★, MIT, pushed 2026-07-17 | Primitive to **build** agents (Claude Code is built on it). A dependency/target, not a peer. |
| **Microsoft Agent Framework** (successor to AutoGen + Semantic Kernel) | Microsoft Learn (fetched): "direct successor… combines AutoGen + Semantic Kernel"; `gh api` `microsoft/agent-framework` rel **python-1.11.0** (2026-07-10). AutoGen now maintenance (pushed 2026-04-15). | **General multi-agent SDK** (build agents from LLMs, graph workflows, human-in-loop). Not a coding-CLI-in-sandbox orchestrator. Wrong shape. |
| **Docker cagent** (`docker/docker-agent`) | `gh api`: 3,192★, Apache-2.0, Go, pushed 2026-07-16 | "AI Agent Builder and Runtime by Docker Engineering" — general agent builder/runtime, not a coding-CLI orchestrator. Adjacent. |

### 3d. FAIL credibility filter (architecturally close, excluded per user requirement)

| Project | Tier-0 (this turn) | Why excluded |
|---|---|---|
| **agentbox** (`madarco/agentbox`) | 261★, User account, created 2026-05-12 | Architecturally the closest clone (parallel agents in Docker/cloud VMs), but **unknown individual author** — fails filter despite fit. |
| **agent-orchestrator** (`ComposioHQ/…` → `AgentWrapper/…`) | 8,311★, but repo **transferred out of the Composio org to a personal `AgentWrapper` User account** | No longer an established-company project; ownership provenance broken. |
| **vibe-kanban** (Bloop AI) | 27,405★, Apache-2.0, but pushed **2026-04-24 (~3 mo stale)** | Bloop AI is credible, but it's a kanban UI over agents and shows a maintenance gap; not a library. |
| **loom** (`ghuntley/loom`, Geoffrey Huntley) | 1,350★, **no license**, README: "if your name is not Geoffrey Huntley then do not use loom" | Credible individual, but explicitly personal-only + unlicensed → not buildable-on. |
| **opencode** (`anomalyco/opencode`) | 186,593★, MIT | An **agent CLI** (a target sandcastle wraps), not an orchestrator peer; also under a lesser-known org (Anomaly). |
| ~100+ long-tail (claude-squad, crystal, cmux, emdash, claude-flow, ralph-*, agenttier, kodo, etc.) | various | Anonymous/hobby TUIs, desktop apps, and swarm experiments — fail the proven-figure/established-company bar. |

### 3e. Recognized authority (Phase-3 source, not a framework)

- **Simon Willison** — builds the agent/CLI layer (`llm`, `llm-coding-agent` v0.1a0 released **July 2026**, `shot-scraper`, `files-to-prompt`), **not** a sandbox orchestrator. Cited as an industry authority on the landscape and agent-safety, not a peer to build on.

---

## 4. Evidence table (per-claim sourcing)

| # | Claim | Sources (Tier 0/1 fetched THIS turn) | Tier | Tool diversity | Confidence |
|---|---|---|---|---|---|
| 1 | Sandcastle = library orchestrating 6 agent CLIs across pluggable sandboxes (Docker/Podman/Vercel-Firecracker/custom), MIT, git-worktree branch strategies, no built-in queue/verify/escalation | `gh api repos/mattpocock/sandcastle` (6,862★, MIT, v0.12.0, 2026-06-29) + WebFetch raw README `main/README.md` | 0+1 | gh api, WebFetch, WebSearch | HIGH |
| 2 | Sandcastle & Vercel `HarnessAgent` are **complementary, not redundant** (adapter layer vs sandbox-lifecycle layer) | WebSearch falsification query + WebFetch `ai-sdk.dev/docs/ai-sdk-harnesses/harness-agent` + WebFetch `vercel.com/changelog/program-agent-harnesses-with-ai-sdk` | 1+2 | WebSearch, WebFetch(×2) | HIGH |
| 3 | Vercel `HarnessAgent`: programmable lib, harnesses = CC/Codex/Pi(+OpenCode/DeepAgents), sandbox pluggable-in-principle (`HarnessV1SandboxProvider`) but bridge harnesses need `@ai-sdk/sandbox-vercel` → Vercel-cloud-leaning | WebFetch `ai-sdk.dev/docs/ai-sdk-harnesses/harness-agent` + Vercel changelog + `gh api repos/vercel/sandbox` | 0+1 | WebFetch(×2), gh api | HIGH |
| 4 | gastown = **Steve Yegge**; agent-agnostic; git-worktree isolation; Refinery merge queue + verification gates + severity-routed escalation; self-host; MIT; v1.2.1 (2026-06-06) | WebFetch raw README `gastownhall/gastown` (author refs `steveyegge/gastown`,`steveyegge/beads`) + `gh api repos/gastownhall/gastown` + `.../releases/latest` | 0+1 | WebFetch, gh api | HIGH |
| 5 | Symphony = **OpenAI**; Linear-board→autonomous runs; proof-of-work verification; Apache-2.0; Elixir ref impl; spec-first; Codex-oriented | `gh api repos/openai/symphony` (homepage openai.com/index/open-source-codex-orchestration-symphony) + WebFetch raw README | 0+1 | gh api, WebFetch | HIGH |
| 6 | OpenHands = All Hands AI; self-hosted control center; can drive its own agent **or** any third-party agent (Claude Code/Codex); Docker/VM sandbox; LLM-agnostic; 81k★; rel cloud-1.46.2 (2026-07-15) | WebFetch raw README `OpenHands/OpenHands` + `gh api repos/OpenHands/OpenHands` + releases | 0+1 | WebFetch, gh api | HIGH |
| 7 | Goose = single extensible agent under **Agentic AI Foundation (Linux Foundation)**; LLM-agnostic (15+); self-host; sandbox mode; Apache-2.0; v1.43.0 (2026-07-14) | WebFetch `goose-docs.ai` + `gh api orgs/aaif-goose` + `gh api repos/aaif-goose/goose` + releases | 0+1 | WebFetch, gh api | HIGH (steward) / HIGH (agent role) |
| 8 | AutoGen superseded by Microsoft Agent Framework (general agent SDK, not coding-CLI sandbox orchestrator); AutoGen in maintenance | Microsoft Learn MCP `microsoft_docs_search` ("direct successor…") + `gh api repos/microsoft/autogen` (pushed 2026-04-15) + `microsoft/agent-framework` rel python-1.11.0 | 0+1 | MS Learn MCP, gh api | HIGH |
| 9 | E2B/Daytona/Modal/Vercel Sandbox are **backends** (Firecracker / container+Kata / gVisor / Firecracker), i.e. Axis-B components not orchestrator peers | `gh api` on all four repos (this turn) + WebSearch backend comparison | 0+2 | gh api, WebSearch | HIGH |
| 10 | Devin (Cognition) = closed commercial SaaS, no open library, not self-hostable/agent-agnostic | WebFetch cognition.ai→cognition.com redirect (commercial site) + task-given candidate | 1(partial)+3 | WebFetch | MEDIUM |
| 11 | Sandcastle is uniquely A✓B✓C✓ as a minimal library; no PASS candidate dominates all three axes + minimal-lib shape | Synthesis of rows 1–9 (each primary-grounded this turn) | 0/1 composite | gh api, WebFetch, WebSearch, MS Learn MCP | HIGH |

**Tool types used across the topic (6):** `gh api` (Tier 0), WebFetch on raw READMEs/docs (Tier 1), WebSearch (discovery), Microsoft Learn MCP (Tier 1 MS docs), WebFetch on curated awesome-lists (Tier 2 discovery), direct vendor-docs fetch (ai-sdk.dev, vercel.com, goose-docs.ai). Exceeds the 5+ broad-topic bar.

---

## 5. Conflicts (flagged; primary wins)

- **Star counts:** secondary sources cited sandcastle at ~5,200★; Tier-0 `gh api` = **6,862★** (authoritative). Resolved in favor of primary.
- **Vercel `HarnessAgent` adapter list:** the changelog names Claude Code/Codex/Pi and a follow-up changelog adds OpenCode + Deep Agents; the harness-agent docs page only fully documented Claude Code/Codex/Pi. No contradiction — docs lag the changelog (recency: changelog wins).
- **gastown ownership:** awesome-list said `steveyegge/gastown`; live repo is `gastownhall/gastown`. README author references confirm **Steve Yegge** (org rename, not a different author). Resolved.

---

## 6. Gaps

- **Vercel `HarnessAgent` non-Vercel sandbox (Axis B/C):** the `HarnessV1SandboxProvider` interface implies custom providers, but **no non-Vercel provider is documented**, and bridge harnesses are steered to `@ai-sdk/sandbox-vercel`. Whether a fully self-hosted (Docker/local) sandbox works end-to-end with bridge harnesses is **unconfirmed** (MEDIUM). Trigger to re-check: `@ai-sdk/sandbox-*` package list on npm.
- **Symphony sandbox/isolation backend & agent breadth:** README does not document the isolation model or whether it drives non-Codex agents (Codex-oriented by naming). MEDIUM on Axis A/B for Symphony.
- **Devin (row 10):** primary not cleanly re-fetched this turn (301 redirect cognition.ai→cognition.com); disposition rests on the commercial-site redirect + task framing. MEDIUM. It is a FAIL-to-build-on disposition, not an accepted finding.
- **Goose exact steward transition (Block → AAIF):** confirmed AAIF/Linux-Foundation governance and Apache-2.0 this turn; the Block→foundation handoff history is inferred, not primary-sourced. Does not affect credibility (Linux Foundation passes).

None of these gaps sits under an accepted shortlist *recommendation*; each is flagged rather than laundered.

---

## 7. Recency status (all fetched THIS turn)

| Project | Latest release / push (this turn) | Within gate |
|---|---|---|
| sandcastle | v0.12.0 (2026-06-29), pushed 2026-06-29 | ✓ (very active) |
| gastown | v1.2.1 (2026-06-06), pushed 2026-07-15 | ✓ |
| Symphony | no tagged releases (spec-first), pushed 2026-06-09 | ✓ (active repo) |
| OpenHands | cloud-1.46.2 (2026-07-15), pushed 2026-07-17 | ✓ |
| Goose | v1.43.0 (2026-07-14) + v2.0.0-rc, pushed 2026-07-17 | ✓ |
| Microsoft Agent Framework | python-1.11.0 (2026-07-10) | ✓ |
| Vercel sandbox / AI SDK | pushed 2026-07-16; AI SDK Harness = experimental | ✓ |
| E2B / Daytona / Modal | pushed 2026-07-16 / 07-09 / 07-16 | ✓ |
| AutoGen | pushed 2026-04-15 (maintenance; superseded) | flagged, superseded |

---

## 8. Shortlist ranking (PASS-filter only) — fit for a repo/company/machine-agnostic autonomous-runner with interactive/autonomous split

1. **sandcastle** — the only A✓ B✓ C✓ *minimal composable library* with a native `run()`/`interactive()` split. Best fit **by definition**; everything else trades away an axis.
2. **gastown** (Steve Yegge) — best if you want **batteries-included lifecycle** (merge queue, verification gates, human escalation) over composability; A✓ C✓, self-host, MIT. Weaker on Axis B (worktree-only isolation) and it's an opinionated system, not a primitive.
3. **Vercel AI SDK `HarnessAgent`** — strongest institutional backing and the cleanest **agent-CLI adapter layer**; **complementary** to sandcastle (use it *inside* your orchestrator). Machine-agnostic gate weakened by Vercel-cloud-leaning sandbox.
4. **OpenHands** (All Hands AI) — most mature/largest, self-host, now agent-agnostic; but a **full platform/control-center**, heavier to embed as a library spine.
5. **OpenAI Symphony** — best **work-management/verification** framing (proof-of-work gates) and OpenAI-backed; Codex-oriented and spec-first (Elixir), not a drop-in TS library.

---

## 9. Build-on vs. build-inspired-by-sandcastle — verdict

**Building on / inspired-by sandcastle is justified over wholesale-adopting any single established-vendor stack.** The falsification target ("an established vendor already ships a strict superset") **failed**: sandcastle is uniquely two-axis-agnostic AND self-hostable AND minimal-library-shaped, and each vendor option breaks a required axis —

- Vercel/AI-SDK → machine-agnostic (Vercel-cloud sandbox in practice),
- OpenHands/Goose/Codex → single-agent origin or platform-shaped (Axis A/shape),
- Microsoft Agent Framework / Docker cagent → wrong shape (general agent SDK / runtime),
- E2B/Daytona/Modal/Vercel Sandbox → backends, not orchestrators,
- Devin → closed SaaS.

**Recommended composition** (serves the interactive-upstream / autonomous-downstream split directly):

- **Spine:** sandcastle (or its pattern) for orchestration + pluggable sandbox lifecycle + git-worktree branch strategies → satisfies A✓ B✓ C✓.
- **Agent-CLI adapter:** Vercel AI SDK `HarnessAgent` adapters (or sandcastle's own agent providers) → broad, maintained CLI coverage.
- **Lifecycle:** borrow gastown's **Refinery** merge-queue + severity-routed escalation model for claim→build→test→verify→PR with an ask-a-human path; OpenAI Symphony's proof-of-work verification is a second reference.
- **Backend:** choose per machine-agnostic need (Docker/Podman local; E2B/Daytona/Modal/Vercel microVM cloud) — sandcastle already abstracts this.
- **Interactive upstream:** sandcastle `interactive()` + escalation (gastown-style / HumanLayer-style approval); **autonomous downstream:** sandcastle `run()` + queue-driven work runs (Symphony-style).

---

## 10. Next-stage handoff

**Settled (HIGH confidence, primary-grounded this turn):**

- Sandcastle's niche is real and uncontested by any single established vendor; it is the best-fit spine for the target autonomous-runner.
- The credible peer set is small: gastown, Vercel `HarnessAgent`, OpenHands, Symphony (+ agent products Goose/SWE-agent/Codex and backends E2B/Daytona/Modal/Vercel Sandbox as components).
- Vercel `HarnessAgent` is complementary (adapter), not a competitor; gastown is the richest lifecycle reference; Symphony is the best work-management reference.
- Recommended architecture = compose, don't adopt-wholesale.

**Open decisions for planning:**

- Adopt sandcastle as a dependency vs. reimplement its pattern (license MIT permits either; drift risk if reimplemented).
- Whether Axis B (multi-backend isolation) is a launch requirement or deferrable — if Vercel-cloud-only is acceptable, `HarnessAgent` + Vercel Sandbox shortens the build materially.
- Confirm Vercel `HarnessAgent` self-hosted-sandbox viability (Gap §6) before betting the adapter layer on it.
- Lifecycle depth: adopt a gastown-style merge queue + escalation now, or start with sandcastle templates and grow into it.

**Related sibling artifacts in this directory:** `RESEARCH-sandcastle-pocock.md` (sandcastle internals), `RESEARCH-headless-agents.md`, `RESEARCH-product-surface.md`.
