# RESEARCH — Claude Code / Anthropic product surface (Boris Cherny "Steps of AI Adoption", Jul 16 2026)

## Task restatement

Characterize the product surface named in Boris Cherny's "Steps of AI Adoption" artifact. Two parts:

- **Part A** — the 12 linked docs: fetch each directly, describe the feature, what it does, its config surface, and maturity.
- **Part B** — the features Boris names *without* links: verdict of exists-today vs announced vs not-found, with a primary citation.

For every feature, map which ladder transition it serves: **1→2** (self-verification loop, auto mode, parallel agents, automated review), **2→3** (context-pull, loops/routines, Claude-kicks-off-Claude), **3→4** (scaled domain automation, cost/model controls for automation).

All docs below were fetched directly this run (not via SERP). Doc domain `code.claude.com/docs` is live; Claude Code upstream is at **v2.1.212 (Jul 17 2026)** per the changelog fetched this run.

---

## Summary

Every one of the 12 linked docs resolves to a **real, live** feature page, and **every** unlinked feature in Part B **exists today** — none is announced-only or not-found. The linked set is a ladder in miniature: sandboxing + auto mode + Chrome + subagent/worktree isolation power the **1→2** self-verification and parallel-agent rungs; memory, remote control, `/goal`, routines, Slack/Claude Tag, Cowork, and mobile power the **2→3** context-pull and Claude-kicks-off-Claude rungs; dynamic workflows, `/batch`, the Agent SDK, analytics, OpenTelemetry, cost controls, and the Compliance API power the **3→4** scaled-automation and governance rungs. The only Part B item that is *not* a Claude Code surface is **Claude Design**, a separate Anthropic Labs product that merely hands off to Claude Code.

---

## Part A — the 12 linked docs

### 1. Monitoring usage — OpenTelemetry export (`/en/monitoring-usage`)

- **What / does:** OTel integration exporting metrics, logs/events, and (beta) distributed traces for sessions, tokens, cost, lines of code, commits, PRs, tool decisions, permission decisions, MCP activity, and full identity attribution (`user.id`, `user.email`, `organization.id`) for audit.
- **Config surface:** env-driven — `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER` / `OTEL_LOGS_EXPORTER` / `OTEL_TRACES_EXPORTER`, `OTEL_EXPORTER_OTLP_ENDPOINT`/`_PROTOCOL`/`_HEADERS`, content-logging gates (`OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS`, …), cardinality controls, `OTEL_RESOURCE_ATTRIBUTES` for org/team segmentation, mTLS certs, and an `otelHeadersHelper` settings key. Metrics named `claude_code.*`.
- **Maturity:** Metrics & events **GA**; traces **beta** (`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`).
- **Ladder:** **3→4** — per-user token/cost/tool telemetry into your own stack is the instrumentation scaled automation needs.

### 2. Auto mode + classifier tuning (`/en/auto-mode-config`)

- **What / does:** Auto mode routes tool calls through a classifier that blocks anything irreversible, destructive, or aimed outside your environment, removing routine prompts. This page is the config reference for what the classifier trusts.
- **Config surface:** `autoMode.environment` (prose trust slots — repos, buckets, domains, services; splice defaults with `"$defaults"`), `autoMode.allow` / `soft_deny` / `hard_deny` (four-tier precedence), `autoMode.classifyAllShell`, and `claude auto-mode defaults|config|critique` CLI subcommands. Read from user/managed/`--settings` scopes only (not project settings). Pair with `permissions.ask`/`deny` for hard checkpoints.
- **Maturity:** **GA**, all providers; `CLAUDE_CODE_ENABLE_AUTO_MODE=1` no longer required as of v2.1.207.
- **Ladder:** **1→2** — auto mode is the named 1→2 rung; it removes per-tool prompts so agents run unattended.

### 3. Agent view (`/en/agent-view`)

- **What / does:** Terminal UI to dispatch and manage many *independent background sessions* from one screen — see state (working / needs input / idle / completed / failed / stopped), peek, attach, pin, rename, filter. Distinct from subagents (spawned within a session) and agent teams (message each other).
- **Config surface:** `claude agents`, `claude --bg "task"`, `/bg` / `/background`, `←` on empty prompt; keyboard-driven.
- **Maturity:** **Research preview**, requires v2.1.139+.
- **Ladder:** **1→2** — the parallel-agents rung (run several tasks at once, watch which need input).

### 4. Code Review (`/en/code-review`)

- **What / does:** Managed multi-agent PR review on Anthropic infra; posts severity-tagged inline comments (🔴 Important / 🟡 Nit / 🟣 Pre-existing), a verification step filters false positives, writes a neutral `Claude Code Review` check run (never blocks merge). Triggers: on-open / on-push / manual (`@claude review`, `@claude review once`). Tunable via `CLAUDE.md` and a highest-priority `REVIEW.md`. Local counterpart: `/code-review` command (branch diff + uncommitted; `--comment`, `--fix`, `ultra` cloud review).
- **Config surface:** admin enablement at claude.ai/admin-settings/claude-code; per-repo Review Behavior dropdown; `REVIEW.md` severity/skip/verification rules; machine-readable severity JSON in check-run output.
- **Maturity:** **Research preview**, Team/Enterprise, not for Zero Data Retention orgs. ~$15–25/review.
- **Ladder:** **1→2** — the automated-review rung.

### 5. Remote Control (`/en/remote-control`)

- **What / does:** Continue a *local* session from phone/tablet/browser (claude.ai/code or the Claude mobile app). Claude keeps running on your machine (local filesystem, MCP, tools stay local); web/mobile are windows into it. Subagent/workflow progress syncs across devices; survives sleep/network drops; mobile push notifications.
- **Config surface:** `claude remote-control` (server mode: `--spawn same-dir|worktree|session`, `--capacity`, `--continue`, `--session-id`), `claude --remote-control`/`--rc`, `/remote-control` in-session and in VS Code; auto-connect via `/config`; `disableRemoteControl` to kill it. Trusted Devices (beta) adds device enrollment + biometric step-up.
- **Maturity:** **Research preview**, all plans (off-by-default on Team/Enterprise until Owner enables); Anthropic-API only (not Bedrock/Vertex/Foundry); not for ZDR.
- **Ladder:** **2→3** — steer in-progress work from anywhere; keeps Claude working while you're away.

### 6. Analytics (`/en/analytics`)

- **What / does:** Org dashboards for usage, adoption, and engineering velocity. Team/Enterprise dashboard: lines accepted, suggestion accept rate, DAU/sessions, GitHub contribution metrics (PRs/lines with CC), leaderboard, CSV export, PR attribution (`claude-code-assisted` label). API/Console dashboard: usage + spend + team insights.
- **Config surface:** claude.ai/analytics/claude-code (Team/Ent) or platform.claude.com/claude-code (API); GitHub app install for contribution metrics; Enterprise Analytics API (`read:analytics` scope) / Claude Code Analytics API for programmatic pulls.
- **Maturity:** Usage metrics **GA**; contribution metrics **public beta**; not for ZDR.
- **Ladder:** **3→4** — measures scaled adoption/ROI across an org; the reporting layer for fleet automation.

### 7. Claude in Chrome (`/en/chrome`)

- **What / does:** Connects Claude Code to your Chrome/Edge/Chromium browser (shares your login state) to test web apps, read console/DOM, automate forms, upload files, extract data, record GIFs — chain browser actions with coding in one workflow.
- **Config surface:** `claude --chrome`, `/chrome` status/reconnect/pick-browser, "Enabled by default"; requires Claude in Chrome extension v1.0.36+; site permissions inherited from the extension; plan-mode read/write prompt semantics; not on WSL or third-party providers.
- **Maturity:** GA-track (direct Anthropic plan required; documented up to v2.1.211 behaviors).
- **Ladder:** **1→2** — the self-verification loop: build the code, then verify it in the real browser.

### 8. Dynamic workflows (`/en/workflows`)

- **What / does:** A JavaScript script Claude writes that orchestrates subagents at scale (`agent()`, `pipeline()`), running in a background runtime while the session stays responsive; intermediate results live in script variables, not context. Enables repeatable quality patterns (adversarial cross-review, multi-angle planning). Bundled `/deep-research`. Save runs as `/name` commands.
- **Config surface:** `ultracode` keyword or "use a workflow"; `/effort ultracode` (auto-orchestrate every task); `/workflows` progress view; save to `.claude/workflows/`; `args` global; caps (16 concurrent, 1,000 agents/run); `Dynamic workflow size` guideline; `CLAUDE_CODE_SUBAGENT_MODEL`; disable via `disableWorkflows` / `CLAUDE_CODE_DISABLE_WORKFLOWS=1`.
- **Maturity:** **GA-track**, v2.1.154+, all paid plans + all providers.
- **Ladder:** **3→4** (with a **2→3** foot) — codified orchestration of dozens–hundreds of agents; Claude writes the automation you rerun.

### 9. Sandboxing (`/en/sandboxing`)

- **What / does:** OS-enforced filesystem + network isolation for the Bash tool and all child processes, so Claude runs most commands without prompts. macOS Seatbelt / Linux+WSL2 bubblewrap+socat; network proxy with domain allowlist; credential deny/mask; `dangerouslyDisableSandbox` escape hatch.
- **Config surface:** `/sandbox` panel; `sandbox.enabled`, `failIfUnavailable`, `allowUnsandboxedCommands`, `filesystem.allowWrite/denyWrite/denyRead/allowRead`, `credentials.files/envVars` (deny/mask), `network.allowedDomains/tlsTerminate/httpProxyPort`, `excludedCommands`, managed-only lockdowns (`allowManagedDomainsOnly`, `allowManagedReadPathsOnly`). Not on native Windows.
- **Maturity:** **GA / built-in**; masking + `tlsTerminate` experimental (v2.1.199+).
- **Ladder:** **1→2 enabler** — the isolation boundary that makes auto mode, parallel agents, and unattended runs safe.

### 10. Costs (`/en/costs`)

- **What / does:** Token/cost management: `/usage` session + plan breakdown; `/usage-credits` spend limits + auto-reload; org spend caps (Team/Ent seat allowance, Console workspace limits, cloud budgets); per-user reporting paths; token-reduction playbook (model choice, `/clear`, `/compact`, hooks, skills, subagent delegation). Notes agent teams ≈7× tokens; `~$13/dev/active day`.
- **Config surface:** `/usage`, `/usage-credits`, `/model`, `/effort`, `MAX_THINKING_TOKENS`, `CLAUDE_CODE_SUBAGENT_MODEL`, workspace/seat spend limits, TPM/RPM sizing table.
- **Maturity:** **GA**.
- **Ladder:** **3→4** — the cost/model controls that make scaled, unattended automation affordable.

### 11. Memory (`/en/memory`)

- **What / does:** Two cross-session mechanisms — **CLAUDE.md** (you write; managed/user/project/local scopes; `@` imports; `.claude/rules/` path-scoped; `claudeMd`/`claudeMdExcludes` managed keys) and **auto memory** (Claude writes; per-repo `MEMORY.md` index + topic files; first 200 lines/25 KB loaded). Subagents can keep their own memory. "Lazy Skills": move specialized instructions into on-demand **skills** rather than always-loaded CLAUDE.md.
- **Config surface:** `/memory`, `/init` (+ `CLAUDE_CODE_NEW_INIT=1`), `autoMemoryEnabled`, `autoMemoryDirectory`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, `InstructionsLoaded` hook, `/doctor` trim.
- **Maturity:** CLAUDE.md **GA**; auto memory **GA** (on by default).
- **Ladder:** **2→3** — the persistent context/artifact layer (Boris's "give AI memory externally") that lets Claude pull context across turns and sessions.

### 12. claude-code-security-review (github.com/anthropics/claude-code-security-review)

- **What / does:** Open-source GitHub Action running Claude for diff-aware semantic security review on PRs; comments findings; detects injection, authn/authz, secret exposure, crypto, TOCTOU, supply-chain, XSS, etc.; false-positive filtering.
- **Config surface:** action inputs — `claude-api-key` (req), `comment-pr`, `upload-results`, `exclude-directories`, `claude-model` (default `claude-opus-4-1-20250805`), `claudecode-timeout` (20 min), `run-every-commit`, `custom-security-scan-instructions`, `false-positive-filtering-instructions`.
- **Maturity:** **Active OSS**, MIT, ~5.6k stars. Warns: not hardened against prompt injection — review trusted PRs only.
- **Ladder:** **1→2** — self-hosted automated (security) review in your own CI.

---

## Part B — features named without links (verdict + ladder)

| Feature | Verdict | Primary (fetched this run) | Maturity | Ladder |
|---|---|---|---|---|
| **`/goal` command** | **Exists** | `/en/goal`, `/en/commands` | GA, v2.1.139+ | **2→3** — session-scoped completion condition; a fast model checks after each turn and Claude keeps going until met (per-turn autonomy; complements auto mode's per-tool autonomy). |
| **`/batch` command** | **Exists** | `/en/commands` (bundled skill) | Bundled skill (prompt-based) | **3→4** — decomposes one large change into 5–30 units, one background subagent per unit in an isolated worktree, each opens a PR. Scaled domain automation. |
| **Routines (scheduled agents)** | **Exists** | `/en/routines` | **Research preview** | **2→3** — saved prompt+repos+connectors run on Anthropic cloud via schedule / API `/fire` endpoint / GitHub events; the "loops/routines, Claude-kicks-off-Claude" rung. `/schedule` in CLI; claude.ai/code/routines. |
| **Claude Tag (Slack agent)** | **Exists** | `/en/slack` (names Claude Tag, links claude.com/product/tag) | Replacing "Claude Code in Slack"; Team/Enterprise | **2→3** — `@Claude` in a channel routes a coding task to a Claude Code web session (Claude kicks off from a chat event). Claude Tag = org-shared @Claude identity with admin-configured access. |
| **Claude Cowork** | **Exists** | `/en/desktop` (Cowork tab; links claude.com/product/cowork) | Desktop tab; Dispatch requires Pro/Max (not Team/Ent) | **2→3 / 3→4** — the Desktop "Cowork" tab for Dispatch and longer agentic work; Dispatch delegates a task from your phone and can spawn a Code session on its own. |
| **Claude Design** | **Exists — but a separate product, not a Claude Code surface** | anthropic.com/news/claude-design-anthropic-labs | **Research preview**, launched Apr 17 2026, Opus 4.7, Pro/Max/Team/Ent | Tangential — AI-native design/prototype tool; can *hand off* designs to Claude Code for implementation. Include as adjacent, not a ladder rung. |
| **Claude Code on Mobile (iOS/Android)** | **Exists** | `/en/remote-control` (Claude app iOS/Android, Code tab; App Store/Play links) | Ships with Remote Control (research preview) + Dispatch | **2→3** — drive/steer sessions and pull context from the phone; `/mobile` shows a download QR. Mobile is a window into a local or cloud session, not a separate runtime. |
| **Cloud execution in Desktop** | **Exists** | `/en/desktop` ("Run long-running tasks remotely" — Remote environment) | Desktop Remote sessions on Anthropic cloud | **2→3 / 3→4** — pick **Remote** to run on Anthropic cloud infra (continues when the app is closed), multi-repo; "Continue in → Claude Code on the Web." Same infra as Claude Code on the web. |
| **Agent SDK — programmatic build + schedule of agents** | **Exists (build fully; schedule via exposed scheduling tools / routines)** | `/en/agent-sdk/overview` | Python + TS libraries (CLI `-p` for other langs) | **3→4** — same tools/agent-loop/context management as Claude Code as a library; subagents, hooks, MCP, sessions, workflows. Tools reference "includes scheduling and worktree tools"; scheduling of runs is via routines / SDK scheduling tools rather than one "schedule" call. Production automation. |
| **Compliance API for Claude Enterprise** | **Exists** | platform.claude.com/docs/en/manage-claude/compliance-api | Claude Enterprise (+ Platform); org-wide, not Claude-Code-specific | **3→4** — `/v1/compliance/*` Activity Feed + directory + content endpoints for security/legal/compliance; governance layer for scaled automation. Note: an org-level Anthropic feature that *covers* Claude Code activity, not a Claude Code feature per se. |
| **Worktree isolation for subagents** | **Exists** | `/en/worktrees` | GA (`isolation: worktree` frontmatter) | **1→2** — each subagent gets a temporary git worktree so parallel edits don't collide; auto-removed when clean. Underpins the parallel-agents and `/batch` rungs. |
| **Subagent orchestration surface** | **Exists** | `/en/sub-agents`, `/en/workflows`, `/en/agent-teams`, `/en/agent-view` | GA / mixed | **1→2 & 2→3** — four coordinated primitives: subagents (Claude-spawned workers), workflows (scripted orchestration), agent teams (peer sessions messaging each other; `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), agent view (many background sessions). |

---

## Conflicts

None material. All 12 doc pages and all Part B primaries agree with the changelog and with each other. One nuance flagged, not a conflict: **Claude Design** and the **Compliance API** are *not* Claude Code surfaces — Claude Design is an Anthropic Labs product that hands off to Claude Code, and the Compliance API is an org-wide Enterprise/Platform feature that *covers* Claude Code activity. Boris naming them in an adoption talk is about the surrounding Anthropic platform, not the Claude Code CLI proper.

## Gaps

- **The artifact itself** ("Steps of AI Adoption", Jul 16 2026) was **not** located as a fetchable URL this run — web search surfaced Boris Cherny adoption-ladder commentary (Lenny's Podcast, Sequoia AI Ascent, Platformer, Fortune) but not the specific artifact. The ladder-transition mapping above uses the team lead's supplied rung definitions, which are internally consistent with the docs; if the artifact assigns a feature to a different rung, defer to the artifact. (Owner of the artifact text: team-lead / ladder-explorer.)
- **Agent SDK "schedule"** half is inferred from the tools-reference pointer ("scheduling and worktree tools") + the routines API, not a single documented `schedule-an-agent` SDK call. Confidence HIGH that scheduling tooling exists; MEDIUM on the exact SDK ergonomics. A follow-up fetch of `/en/tools-reference` would close it if the artifact leans on SDK-native scheduling.

## Recency status

- Claude Code upstream **v2.1.212, published 2026-07-17T00:26Z** — confirmed from the **independent upstream pool** this run: `gh api repos/anthropics/claude-code/releases` (release timestamps) **and** raw `CHANGELOG.md`. This is a different source pool from `code.claude.com/docs`, and it corroborates the load-bearing feature set: **auto mode, routines (v2.1.207 fix), sandboxing, remote control, and dynamic workflows all appear in the upstream changelog**. (Note: the harness "today" is 2026-07-16; the upstream release timestamp for v2.1.212 is 2026-07-17T00:26Z — the version is real, not a summarizer confabulation.)
- Older version-gated names (`agent-view`/`/goal` @ v2.1.139, `/batch`) sit below the upstream changelog window the fast summarizer read; they are backed by their directly-fetched doc pages rather than by the upstream spot-check.
- Claude Design launch **Apr 17 2026** (research preview) — anthropic.com news fetched this run.
- Compliance API — platform docs fetched this run; example events dated Apr 2026.
- All 12 Part A pages fetched directly this run from `code.claude.com/docs`.

**Maturity-label caveat:** where a page carries an explicit banner (research preview, public beta, beta), the label is quoted. "GA" / "GA-track" for monitoring, chrome, workflows, sandboxing, costs, memory is *inferred from the absence of a preview/beta banner*, not a stated status.

## Project fit

This is external product research, not a change to the melodic-software repos; no CLAUDE.md/standards conventions apply beyond the research discipline (primary-source-first, direct fetch, per-claim Tier-1 + corroboration), which was followed. Artifact persisted to the requested `.work/ai-adoption-ladder/` path (memory-tier, not committed).

## Outcome gate

- **(1) Tier-0/1 primary per claim, fetched this run:** PASS — every Part A row and every Part B row cites a page/repo/news URL fetched this turn.
- **(2) No claim all-Tier-2:** PASS — `/batch`, Claude Design, and Compliance API were promoted from search synthesis to Tier-1 by direct fetches of `/en/commands`, the anthropic.com news page, and the platform.claude.com compliance doc.
- **(3) Phase 2/3 queries trace to gaps:** PASS — batch/design/compliance/slack/sdk/desktop-cloud each closed a named Part B gap; the `/batch` fetch was the falsification step (suspected not-found → confirmed exists).
- **(4) ≥2 independent corroborators:** PASS for the load-bearing feature set — the per-feature doc pages (pool 1: `code.claude.com/docs`) are corroborated by the **upstream `anthropics/claude-code` repo** (pool 2: `gh api` releases + raw `CHANGELOG.md`), which independently confirms auto mode, routines, sandboxing, remote control, and dynamic workflows, plus independent web results (pool 3) for Design/Compliance. Weakest rows: `agent-view`/`/goal`/`/batch` rest on pool 1 + pool 3 only (upstream summarizer window didn't reach their version gates) — flagged in Recency, not laundered.
- **(5) Falsification ran:** PASS — two falsification passes: (a) `/batch` "not-found?" → confirmed exists via `/en/commands`; (b) "are these docs-only artifacts / is v2.1.212 confabulated?" → refuted by the independent upstream GitHub pool confirming both the version/date and the major features.
- **(6) Recency:** PASS — the **upstream** repo (not the docs mirror) fetched this run: `gh api repos/anthropics/claude-code/releases` gives v2.1.212 @ 2026-07-17T00:26Z, cross-checked against the doc version annotations.
- **(7) HIGH confidence:** PASS for all except the Agent SDK *schedule* ergonomics (MEDIUM) — flagged in Gaps.
- **(8) Project fit:** PASS.

**Gate result: PASS** (one MEDIUM-confidence sub-claim flagged, not laundered into a finding).

---

## Next-stage handoff

**Settled facts:**

- All 12 linked docs are real/live; maturity split — GA: monitoring, auto-mode, chrome, workflows, sandboxing, costs, memory; research preview: agent-view, code-review, remote-control; public beta: analytics contribution metrics; active OSS: security-review.
- All 12 Part B features exist today; none announced-only or not-found. Claude Design is the only non-Claude-Code surface (separate Labs product, hands off to Claude Code). Compliance API is an org-wide Enterprise/Platform feature covering Claude Code activity.
- Ladder mapping (using team-lead rung defs): **1→2** = sandboxing, auto-mode, agent-view, code-review, chrome, security-review, worktree isolation, subagent orchestration; **2→3** = memory, remote-control, `/goal`, routines, Claude Tag, Cowork, mobile, cloud-in-Desktop; **3→4** = workflows, `/batch`, Agent SDK, analytics, monitoring/OTel, costs, Compliance API.

**Open decisions (for planning / artifact owner):**

- Confirm each feature's rung against the actual "Steps of AI Adoption" artifact text (not fetched this run); the artifact wins on any rung disagreement.
- Decide whether Claude Design and the Compliance API belong in a Claude-Code-scoped deliverable or a separate "surrounding Anthropic platform" section.
- If SDK-native scheduling ergonomics matter, fetch `/en/tools-reference` to pin the exact scheduling tool names.
