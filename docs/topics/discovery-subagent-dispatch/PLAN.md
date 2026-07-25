# discovery-subagent-dispatch

## Brief

### TLDR

Make `/discovery:research` and `/discovery:explore` dispatch a purpose-built plugin subagent by
default instead of executing in main context. The subagent runs the full discipline, writes an
index-plus-sidecar artifact set into the topic's memory slice, and returns only a file pointer plus a
one-paragraph summary. Add a corpus-enumeration phase and a coverage-ledger artifact so bounded
corpora are exhaustively accounted for rather than skimmed. Then sweep the other 138 marketplace
skills for the same treatment.

### Goal

Move exploration and research execution off the orchestrator's context window. The orchestrator's
job becomes routing file pointers between stages and deciding, per stage, whether it needs to read
an artifact at all. Artifacts are structured for progressive disclosure so any consumer — parent or
sibling agent — reads only the slice it needs.

### Constraints

**Version floor: Claude Code 2.1.219** (the version these facts were verified on). Every claim below
is version-gated in the source docs, and several are false on versions still in the field — record the
floor with the claims or the contract silently misleads:

- Background as the default subagent execution mode — **v2.1.198**. Below it, the "background filter
  is the default filter" premise fails outright.
- `background: false` on a `context: fork` skill — **v2.1.218**. Below it, forked skills always blocked
  the turn, so the escape hatch named below does not exist.
- The narrow tool set applying to a backgrounded `context: fork` skill — **v2.1.218**.
- `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` — from **v2.1.172 through v2.1.216** subagents nested by
  default up to five layers and the limit could not be changed. On that range the env change recorded
  below is inert *and unnecessary*. It is correct on 2.1.219.
- `/subtask` (the forked-subagent command) — **v2.1.212**; it was `/fork` before.
- The `skills:` preload exclusion for bundled `/verify` and `/code-review` — **v2.1.215**.

Harness facts verified against official docs this session
(<https://code.claude.com/docs/en/sub-agents>, <https://code.claude.com/docs/en/skills>,
<https://code.claude.com/docs/en/hooks>):

- **Subagent frontmatter fields**: `name`, `description`, `tools`, `disallowedTools`, `model`,
  `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`,
  `background`, `effort`, `isolation`, `color`, `initialPrompt`.
- **`skills:` preloads full skill content** at subagent startup. Requires the target skill to keep
  `disable-model-invocation: false` — all discovery skills qualify today. Preloading is not a
  restriction: the subagent can still invoke unlisted skills through the Skill tool.
- **Two tool filters narrow every subagent — except a conversation fork.** The docs are explicit:
  "Forks skip both filters and receive the main conversation's exact tool pool," with `Agent` the
  only carve-out inside that exemption ("in a fork the tool stays listed but returns an error instead
  of spawning"). A fork IS a subagent, so every unconditional "in every subagent" claim below is
  scoped to **non-fork** subagents. This matters because `history-fork` is one of the four mechanisms
  in the audit vocabulary. Whether `AskUserQuestion` *functions* from a background fork is
  undocumented in either direction — do not assume it does.
  Filter 1 (every non-fork subagent): `Agent` (unless
  `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is set), `AskUserQuestion`, `Workflow`, `EnterPlanMode`,
  `ExitPlanMode`, `ScheduleWakeup`, `TaskOutput`, `WaitForMcpServers`, `EndConversation`. Filter 2
  (background only, and background is the default) reduces built-ins to `Read`, `Grep`, `Glob`,
  `Bash`, `PowerShell`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `TodoWrite`,
  `Skill`, `ToolSearch`, `EnterWorktree`, `ExitWorktree`, `Monitor`, `TaskStop`, `SendMessage`,
  `Artifact`, plus every MCP tool.
- **`Workflow` is unavailable in every non-fork subagent.** `research-deep`'s inline-dispatcher
  requirement is still correct, but rests on independent grounds — the skill states it itself
  (`research-deep/SKILL.md:19`) and its multi-topic path needs `Agent`, which errors even in a fork.
  The filter argument alone does not cover a fork.
- **`AskUserQuestion` is unavailable in every non-fork subagent.** `/explore`'s "surface open
  questions to the USER" contract degrades to text in the returned summary; the parent must
  re-surface them.
- **`TaskCreate`/`TaskGet`/`TaskList`/`TaskUpdate` do not survive the background filter** for a
  subagent spawned through the Agent tool; `TodoWrite` does. **Carve-out:** teammates in agent teams
  additionally keep the task tools and the cron tools, so this is a property of the dispatch
  mechanism, not of dispatch as such — state the carve-out wherever the rule is applied, or it
  over-blocks any row whose only blocker is a task tool. Decision 5's "ledger must be a file" holds
  regardless, but on durability and parent-readability, not on this filter.
- **A `context: fork` skill is a regular agent type**, not a conversation fork. It receives the
  narrow background tool set unless it sets `background: false`, which makes it block the invoking
  turn. Only the `fork` subagent type (`/subtask`, `CLAUDE_CODE_FORK_SUBAGENT`) inherits the
  parent's exact tool pool.
- **Plugin-shipped agents ignore the `hooks`, `mcpServers`, and `permissionMode` frontmatter
  fields.** This costs less than it appears: `settings.json` hooks still fire inside subagent tool
  calls (the hook payload carries `agent_id`/`agent_type` precisely to distinguish them), subagents
  inherit the main conversation's MCP tools, and permission mode is inherited from the parent —
  a parent in `auto` mode yields a subagent in `auto` mode. **Two further losses, previously
  understated:** (1) `permissionMode` inheritance is total only under specific parent modes — under a
  parent in the shipped `default` mode a project or user agent *can* override to `plan`/`acceptEdits`/
  `dontAsk`/`bypassPermissions` and a plugin agent cannot; the earlier claim generalized from `auto`,
  the one parent mode where the loss is nil. (2) session-level hooks give *observability* inside a
  subagent (`agent_id`/`agent_type` in the payload) but not *scoping* — `PreToolUse` matchers filter
  on tool name, so per-agent behavior must be branched inside the hook script, and frontmatter hooks
  have a cleanup lifecycle the settings form lacks.
- **Topic-docs placement**: `.claude/topic-docs.yaml` is absent from this repo, so defaults apply —
  memory slice `.work/<slug>/`, contract slice `docs/topics/<slug>/`. Discovery writes memory tier
  only; that does not change.
- **Precedent**: this marketplace already ships plugin subagents in `review/` (6) and
  `plugin-quality/` (1).

Environment change made this session: `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH: "5"` added to
`~/.claude/settings.json` (chezmoi-tracked; backfill to `melodic-software/dotfiles` is owed). Env
vars are read at session start, so nested spawning is inert until the next session.

### Decisions

| # | Decision | Resolution |
|---|---|---|
| 1 | Default execution posture | `/research` and `/explore` **dispatch a subagent by default**, with a documented inline escape hatch for tight turn-by-turn iteration. This deliberately overrides `research/SKILL.md`'s current "prefer direct research when results inform decisions" guidance; summarization loss is bounded because the full artifact is on disk and the parent may read it on demand. |
| 2 | Mechanism | **Custom plugin subagents** (`discovery:researcher`, `discovery:explorer`) with `skills:` preload, dispatched by the parent skill. Rejected: `context: fork` on the existing skills (no per-invocation prompt beyond `$ARGUMENTS`, silent narrow-tool-set trap) and dispatcher-only with a prose discipline reminder (discipline arrives as recall, not content). |
| 3 | Nested fan-out | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is an **optional detected capability**, not a hard requirement. `discovery:setup` recommends it; without it the dispatched agent does its breadth sequentially — slower, same coverage. Same graceful-degradation shape as `explore-deep`'s existing `CLAUDE_CODE_FORK_SUBAGENT` note. |
| 4 | Progressive disclosure | `RESEARCH.md` / `EXPLORE.md` are **always an index**, with content in sidecars from the start — not only past the current ~2000-word overflow threshold. The index carries a task restatement, a one-line abstract per sidecar, and a section/claim → file+anchor table. Sidecars carry a machine-readable header (topic, claims, confidence) so a consumer can grep-then-read a single section. |
| 5 | Coverage discipline | A new **mandatory** discipline in `research/SKILL.md`, its recipe in `context/discipline.md`, materialized as a `research-checklist.md` in the memory slice. Kept distinct from the existing Phase-1 numbered-gap list: that one chases *unknowns*, this one enforces exhaustive coverage of a *bounded corpus*. The file is mandatory because dispatched agents have no Task tools. |
| 6 | Corpus enumeration | Gets its **own Phase 0** — enumerate the corpus and write the checklist before any query. Sections, topics, subjects, and the per-item depth criterion are fixed up front and become the ledger; Phase 1 researches against it. Folding enumeration into Phase 1 lets breadth queries crowd it out, which is the speed-reading failure being fixed. |

| 7 | **Dispatch is the default posture; INLINE-ONLY is the claim needing justification** | Preserving the MAIN agent's context is the primary goal of this effort. A skill that would flood main context dispatches unless there is a real reason it cannot. This inverts the sweep's original burden of proof and is what re-derived 15 of the original 57 INLINE-ONLY verdicts. |
| 8 | **The orchestration boundary** (the unifying principle) | The parent owns the **pre-dispatch envelope** — precomputed values, scope confirmation, intake answers, budget authorization, capability checks — resolved in main context and passed into the dispatch prompt. The agent owns a bounded middle: no load-time machinery, no user turn, no unresolved scope. The parent also owns the **post-dispatch boundary**: verification hand-off. **A dispatched agent never verifies its own work.** Three independent agents converged on the second half without seeing each other. |
| 9 | Nested spawning (supersedes Decision 3's degradation clause) | Classify every nested spawn by what it buys. **Throughput** nesting (N independent units, identical epistemic standing) — Decision 3 stands: absent nesting the agent goes sequential, slower with the same coverage. **Independence** nesting (a context that has not seen what the parent produced) — Decision 3's clause is false: self-critique is not a slower control, it is the absence of one. Remedy is neither the env var nor blocking dispatch: the dispatched agent does **not** run the step, returns `verification: pending` plus a verification request, and the orchestrator dispatches the verifier as a **sibling**. Independence is a property of context provenance, not spawn parentage — a verifier reading the artifact off disk has never seen the producing context, whoever spawned it. `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` reverts to a recommended optimization. |
| 10 | Dispatch and producer ≠ critic | Dispatch **satisfies** the requirement by construction under a criteria-only envelope; the dispatched agent then runs the checklist inline rather than re-dispatching, because it *is* the fresh pair of eyes. Hoisting, not nesting. Distinguish two guarantees: **independence** (who renders the verdict — dispatch buys it) from **decorrelation** (how many priors examine it — dispatch does not, and never claimed to; the remedy is a cross-vendor reviewer, orthogonal to dispatch). |
| 11 | Interactive gates — the three-cell test (supersedes the positional "mid-flow" wording) | **Parameter** question: answerable from intent, arguments, and the conversation before the run starts — never a blocker. Test: *could the parent ask this without having read a single file the skill reads?* **Discovered** question: existence or content depends on what the run finds — blocks only if it steers. **Elicitation** question: blocks when the answer IS the deliverable. Batches split because "mid-flow" was read positionally (inside the step list) rather than temporally. |
| 12 | Discipline delivery to a dispatched agent | Preload the **existing** `discovery:research` skill via the agent's `skills:` field. Author no new contract skill: the thin-mandate / heavy-reference split already exists in the file tree (SKILL.md carries the bars, phases, and outcome gate; `context/discipline.md` carries tier tables, recipes, calibration). Measured: preload injects the SKILL.md body **only** — supporting files stay on demand — and `${CLAUDE_PLUGIN_ROOT}` expands on the preload path, so the pointer to the sibling arrives working at turn zero. The mandate must arrive **guaranteed**, not on request, because the skill exists to stop an agent doing less than the bars require. Dispatch the skill **by name**; never transcribe it into a prompt (that breaks `${CLAUDE_PLUGIN_ROOT}` expansion, drops `!` precompute, and freezes a drifting copy). |
| 13 | Dispatch granularity (revises Decision 1) | **Phase-level.** The dispatch unit is a phase or action; the whole-skill verdict is a **roll-up**, so the 138-row ledger survives as an index. No new frontmatter — two shipped declaration shapes suffice: an execution-site column on an action-router table, and per-step annotation plus a handoff contract. For `/discovery:research`: one dispatched span covering Phase 0 through Phase 4 and the outcome gate's mechanical criteria; parent keeps topic resolution at the front and presentation at the back; the gate's confidence criterion moves to a **parent-dispatched sibling verifier**; project-fit stays with the parent, which alone holds the consuming project's conventions. |
| 14 | `-deep` variants | **Split, not symmetric.** **Keep `research-deep`** — Tier 1 needs `Workflow` and the multi-topic path needs `Agent`, which errors even inside a true fork, so its heaviest tier is genuinely not runtime-selectable from a dispatched context. The governing convention's operative test is *same execution path vs. a second execution path*, not frontmatter-vs-runtime, so runtime dispatch does not void it. **Retire `explore-deep` conditionally** — relocate into `plugins/discovery/agents/explorer.md`, but only once that agent reproduces its project-memory loading and sidecar-on-collision behavior. `plugins/discovery/agents/` does not exist yet. |

### Amendments (ratified 2026-07-24)

1. **Decision 2 under-specified the discipline-delivery path.** A plugin agent can receive its
   discipline via `skills:` preload or by granting the `Skill` tool and invoking at runtime. All
   seven agents this marketplace ships today use runtime invocation; none uses `skills:`. Whether
   `!`-precompute blocks, `allowed-tools` grants, and `${user_config.…}` substitution fire under
   preload is **unverified** — the docs specify them for when a skill *runs*. Proposed: prefer
   runtime invocation, reserving `skills:` preload for skills with no load-time machinery.
2. **`disable-model-invocation: true` blocks BOTH paths, not just preload.** It bars preloading and
   bars the `Skill` tool from invoking the skill at all. Skills carrying it are undispatchable
   without flipping the flag: `dometrain:sync`, `education:teach`, `firecrawl:update`,
   `planning:questionnaire` (sweep incomplete).
3. **A fourth mechanism exists.** The Agent tool's `subagent_type: "fork"` is the only one inheriting
   the live transcript; `plugin-agent` and `context-fork` both discard it. Skills whose input is the
   conversation itself require it. It is rollout-gated by `CLAUDE_CODE_FORK_SUBAGENT`, degrades to
   *stop* rather than *inline*, and its cost scales with transcript length — inverting this Brief's
   context-saving premise on a long session.
4. **Decision 3's optional nesting has a correctness edge, not just a speed one.** A skill that
   mandates its own fresh-context fan-out as a control (`planning:plan` Step 3, labelled "MANDATORY —
   never skip"; `planning:audit-answers` Step 2) silently degrades that step to inline self-critique
   when dispatched without `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`. Proposed: nesting is a hard
   prerequisite for dispatching that subset, optional elsewhere.
5. **Decision 4 is not universal.** `/education:quiz-me`'s report contract explicitly forbids linking
   `.work/` or `docs/topics/` paths — the sidecar shape. Index-plus-sidecars applies to
   artifact-producing skills, not to every dispatched skill.
6. **State the interactive blocker as the absence of a USER**, not of `AskUserQuestion`. Several
   skills gate that tool behind a `use_ask_user_question` config defaulting OFF and fall back to
   inline prose rounds, equally unreachable from a subagent.
7. **`!` precompute may optimize, never enable — fleet-wide, independent of dispatch.** The managed
   setting `disableSkillShellExecution: true` disables `!` substitution for plugin-sourced skills and
   cannot be overridden. Any plugin-shipped skill whose *correctness* depends on `!` output is
   therefore broken in exactly the managed/enterprise posture this marketplace designs for. 64 of the
   138 non-`setup` skills carry `!` precompute; each must be correct without it. A standing authoring
   rule, not a dispatch concern.
7b. **`CLAUDE_CODE_FORK_SUBAGENT` is a control, not a gate — the "rollout-gated" framing is stale.**
   Forks have been enabled by default since **v2.1.161**; the variable now only forces on (`1`) or off
   (`0`), and the command is `/subtask` as of v2.1.212. So `history-fork` is *less* caveated than
   recorded, not more. The residual caveat that does stand: "Letting Claude itself spawn forks is
   experimental and may change in future releases." The same stale requirement is reproduced in
   shipped skill text at `plugins/discovery/skills/explore-deep/SKILL.md:3` — which is doubly wrong,
   since it is also attached to the wrong mechanism (`context: fork` is not the `fork` subagent type).
8. **Discipline delivery: preload a thin contract, `Read` the bulk.** Supersedes the earlier
   preload-vs-runtime framing, which posed a false binary — and the binary was false in a second way:
   `plugin-quality:auditor` uses **neither** path. Its `tools` list omits `Skill` entirely and it
   declares no `skills:`, so its discipline arrives as method in the agent body plus files it `Read`s
   from paths handed to it in the dispatch prompt. That third shape is immune to both the preload
   uncertainty and the `disable-model-invocation` block, and it is essentially what this amendment
   converges on. The six `review/` agents do grant `Skill`, so "runtime invocation is the
   marketplace's proven default" survives; "all seven use it" does not. The documented supporting-files pattern is
   strictly better: `skills:` preloads ONE small always-applies contract skill (phase gates, outcome
   gate, non-negotiables; well under the 500-line guidance; authored to need zero `!`,
   `${user_config.…}`, or `allowed-tools`), while the heavy multi-phase reference lives in sibling
   files read with `Read` at the phase that needs them. This beats runtime-invoking a heavy skill on
   two counts: the bulk no longer depends on the model electing to call `Skill`, and a phase-scoped
   file read costs less than landing a whole skill in context. Discovery is already shaped this way —
   `skills/research/context/discipline.md` is already a bundled reference — so this is a small delta,
   not a rewrite. Keep `Skill` in the agent's `tools` regardless. The contract skill must NOT set
   `disable-model-invocation: true`, which silently blocks preload; `user-invocable: false` is the
   correct flag for hiding it from the slash menu while keeping it preloadable.
9a. **Three preload behaviors now settled empirically** (probe plugin loaded via `--plugin-dir`,
   headless `-p`, subagent defined with `tools: []` and `tool_uses: 0` so it could not have shelled
   out to forge the values):
   - **`!` shell substitution FIRES on the preload path**, and its output is byte-identical to the
     normal `Skill`-tool invocation. Preload is not a degraded injection path. This retires the
     largest part of the risk — 36 of the 49 dispatch candidates had `!` as their only concern.
   - **`allowed-tools` grants DO NOT fire on the preload path**, verified against a positive control
     (slash invocation permits the declared command, exit 127) and a no-skill baseline (identical
     refusal). **Broader finding: the grant does not fire on the `Skill`-tool path either** — in this
     build it appears honored only on slash invocation. So any skill relying on its own
     `allowed-tools` when invoked by a model rather than typed by a user is already silently
     degraded today, dispatch or not. 13 skills corpus-wide carry one.
   - **`${user_config.…}` remains INCONCLUSIVE.** The placeholder survived literally on every path
     tested including slash invocation, so no positive control was achieved; the probe rig's
     `--plugin-dir` plugin likely has no resolvable `pluginConfigs` identity. A real verdict needs a
     marketplace-installed plugin with a confirmed-live value. 25 skills carry the substitution.
9b. **Two further preload behaviors settled empirically** (probe against installed discovery v0.8.2
   via plugin-agent frontmatter; scripts and transcripts in the session scratchpad, `run11`/`run12`):
   - **Preload injects the `SKILL.md` body ONLY.** Supporting files under the skill directory stay
     on-demand — they are not dragged into the agent's startup context. This is the property that
     makes the recommended shape work: the mandate arrives guaranteed while the heavy reference stays
     lazy, so preload and progressive disclosure are not in tension.
   - **`${CLAUDE_PLUGIN_ROOT}` expands on the preload path.** The pointer a preloaded skill carries to
     its sibling reference file therefore arrives as a working absolute path at turn zero, with no
     resolution step required of the agent.
9c. **Two preload behaviors remain undocumented and untested.** Whether preload still fires when
   `Skill` is absent from `tools` or listed in `disallowedTools` (strongly implied by two doc
   sentences read together, never asserted); and whether preloaded content survives auto-compaction —
   the re-attachment budget is defined over "the most recent *invocation*", and a preloaded skill was
   never invoked. Amendment 8 is chosen so neither is load-bearing.
   Note that `!` firing does **not** argue for preloading precompute: it fires at every spawn before
   the agent knows it needs the data, which multiplies under fan-out.

### Acceptance criteria

- Invoking `/discovery:research <topic>` with no other arguments dispatches a subagent; the main
  conversation gains a file pointer and a summary, not the research transcript.
- The same holds for `/discovery:explore <scope>`.
- Both skills document the inline escape hatch and the condition under which it is correct.
- `discovery:researcher` and `discovery:explorer` agent definitions exist under
  `plugins/discovery/agents/`, preload their skill via `skills:`, and declare no
  `hooks`/`mcpServers`/`permissionMode` (ignored for plugin agents).
- A research run over a bounded corpus produces `research-checklist.md` enumerating every corpus
  item with a per-item depth criterion and a completion mark, and the outcome gate fails when any
  item is unmarked.
- `RESEARCH.md` and `EXPLORE.md` are indexes with per-sidecar abstracts and a section → file+anchor
  table, regardless of total size.
- Sidecars carry a machine-readable header.
- `discovery:setup` detects `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` and recommends setting it;
  absence degrades rather than blocks.
- `research-deep` still dispatches Tier 1 from main context (`Workflow` is subagent-unavailable).
- Open questions a dispatched agent surfaces are re-surfaced by the parent, since the agent cannot
  call `AskUserQuestion`.

### Captured assumptions

- Downstream consumers of `RESEARCH.md`/`EXPLORE.md` tolerate an index-plus-sidecar shape without
  code changes. Unverified — consumers across `planning`, `implementation`, and `session-flow` have
  not been audited. Flagged for the plan step.
- `.claude/topic-docs.yaml` stays absent in this repo, so slice defaults hold.
- Dispatch-by-default carries no cost ceiling the user wants enforced (no per-invocation token cap
  was requested).

### Out of scope

- Changing where discovery artifacts land (memory tier, `.work/<slug>/`) — unchanged.
- Giving discovery agents contract-tier write access — unchanged.
- Editing vendored skills under any `vendor/` directory — upstream-owned.
- The `setup` skills across the marketplace (39 of them) — install/config surface, never dispatch
  candidates.

### Deferred questions

- ~~**Do the `-deep` variants collapse?**~~ — **RESOLVED 2026-07-24**, Decision 14. Split: keep
  `research-deep`, retire `explore-deep` conditionally.
- ~~**Which of the 138 skills adopt the dispatch posture?**~~ — **RESOLVED**. Sweep complete and
  ratified: DISPATCH-DEFAULT 22, DISPATCH-OPTIONAL 44, INLINE-ONLY 39, NO-CHANGE 33. Per-skill in
  `.work/discovery-subagent-dispatch/skill-dispatch-audit-checklist.md`.
- **Does dispatch-by-default apply when the invoking context is itself a subagent** (avoiding a
  needless second hop at spawn depth > 1)? — arbiter: `/planning:plan`. Still open, and Decision 10's
  hoisting rule is the likely answer: the outer dispatch already supplied the fresh context, so the
  inner hop dissolves rather than repeating.
- **Coverage residual:** 32 of the original 57 INLINE-ONLY rows were upheld without an independent
  read — inherited from batch rationale rather than verified against the skill's own text. A
  scripted predictor over those 32 returned three hits, all benign, so the estimated risk is low but
  unmeasured. A close-out pass is running; results land in
  `.work/discovery-subagent-dispatch/decide/D9-close-unverified.md`.
- **Harness-adaptive detection.** Skills must detect capability at runtime — version, fork
  availability, nesting depth — rather than assume it. The version floor above shows the cost of
  assuming: several claims are false on releases still in the field, and shipped skill text still
  cites a gate removed in v2.1.161. Mechanism for detection is unspecified; arbiter:
  `/planning:plan`.

## Plan

> **STATUS 2026-07-25 — APPROVED BY USER. Cleared for execution.** Both review gates ran; all 28
> findings across the two passes are resolved or folded into phases. Both CRITICAL blockers are fixed
> at their source in `design/contract-spec.md` (dated amendments to C1, C2, C3), not merely noted here.
>
> **F10 resolved as option (a)** — dispatch stays uncapped, and the skill text must name cost as a
> reason to reach for the inline escape hatch (not only "tight turn-by-turn iteration"). This was the
> RECOMMENDED option and rode the plan approval; the user may override it at any point.
>
> **Outward-facing work is authorized by the user**: complete the remaining work, push, open a PR,
> and merge. This authorization covers the Phase 0 merge of #1260, this branch's own PR, and the
> Phase 7 tracker writes and upstream comments. It does **not** waive the search-before-create rule
> on tracker writes, and it does not authorize force-pushing a shared branch or editing a `managed`
> upstream materialization.
>
> Live state at approval (2026-07-25): **#1260 OPEN / MERGEABLE** (06:51Z), **#1096 OPEN /
> CONFLICTING** (07:09Z). Both are time-sensitive — **re-verify before acting on either.** Nothing
> outside `docs/topics/discovery-subagent-dispatch/` has been modified on this branch yet.

### Scope of this PLAN

**Discovery plugin only.** The 138-skill marketplace sweep is promoted to its own topic — it clears
every sub-topic promotion trigger (66 dispatch verdicts, >30 plugins, its own commit boundary) and is
filed as a tracked work item in Phase 7, linked to #1225. The sweep's evidence
(`.work/discovery-subagent-dispatch/skill-dispatch-audit-checklist.md` plus the eleven batch
artifacts) is a completed input to that topic, not work this branch executes.

### Standards grounding

No `.claude/standards-index.md` exists in this repo, so the resolution ladder falls to inference. The
surfaces this plan touches and the conventions loaded for each:

| Surface | Convention loaded |
|---|---|
| Plugin artifacts, memory vs contract tier | `docs/conventions/topic-docs/`, `docs/PLUGIN-ARTIFACT-PROTOCOL.md` |
| Agent + skill authoring | `docs/PLUGIN-PHILOSOPHY.md` as it exists today |
| Delegation doctrine | **Not yet in the repo.** Verified: `docs/PLUGIN-PHILOSOPHY.md` contains no `Delegation mechanics`, `fresh-eyes`, or `named-agent bar` text. The section arrives with PR #1096, which is CONFLICTING and unreviewed. Every reference to it in this plan is **aspirational, not grounded** |
| Commit subjects | `docs/conventions/commit-convention/` |
| PR body | `docs/conventions/pr-body-convention/` |
| Shipped shell gates | `scripts/run-plugin-tests.sh` auto-discovery of `plugins/**/*.test.sh` |

Repo `CLAUDE.md` and `AGENTS.md` are ambient and are not re-pulled here.

### Resolutions this plan makes (the Brief's two open arbiter questions)

- **Dispatch when the invoking context is itself a subagent** → **hoisting; the inner hop dissolves.**
  Dispatch-by-default is scoped to the main-conversation boundary. A subagent invoking
  `/discovery:research` runs it inline: the outer dispatch already supplied the fresh context, and a
  second hop spends the inner agent's own window rather than saving anything. Stated as a rule in
  both skills' routing sections (Phases 2 and 3).
- **Harness-adaptive capability detection** → **`discovery:setup check` probes and reports; skill
  text carries the version floor plus graceful degradation.** No per-invocation runtime probe (it
  costs a turn at every spawn and multiplies under fan-out). Phase 4.

### Phase 0: Merge gate — #1260 lands, branch rebases [TODO]

Hard precondition on every later phase: no `plugins/discovery/` edit happens before this closes.
PR #1260 (`feat(discovery): artifact ladder, large-doc fetch, absence enumeration`) edits the exact
five files this work edits and adds outcome-gate criteria 9 and 10 to the table C2's ownership split
is written against. As of planning it is OPEN, MERGEABLE, 26/26 checks SUCCESS, no requested reviews
outstanding — it appears mergeable now.

> **Scope-change note, 2026-07-25 — Phase 0 step 1 changes from *merge* to *wait for MERGED*.**
> #1260 is being driven by a **concurrent standing `babysit_loop` worker lane**, not by this session.
> The repo's own `.claude/source-control.md` declares `babysit_loop_stop_mode: standing`,
> `babysit_loop_tier: worker`, `babysit_loop_merge: c2-mechanical` — a worker-tier loop with merge
> authority over gate-proven PRs on this exact repo. Observed live: three commits appeared on
> `feat/research-primary-source-ladder` from that lane inside one hour, two of them fixing the same
> Codex finding this session was mid-fix on. The plan's "merge #1260" step assumed a single actor.
> Merging out from under an active worker lane mid-edit would truncate its work, so this session
> polls for `MERGED` instead of racing it. What this session did contribute before the lane was
> identified, and which is now in the PR's history: `b8052a5b` (scope the fetch-log changelog row to
> release-bearing claims) and `52795d05` (make the size-failure recipe artifact-type-aware).

1. Wait for #1260 to reach `MERGED` — see the scope-change note above; this session does not merge it.
2. Rebase `feat/discovery-subagent-dispatch` onto updated `main`.
3. Re-read the post-merge outcome-gate table in `research/SKILL.md`; record the actual criterion
   numbers rather than trusting C2's projection.
4. Re-verify T1's evidence survived the merge: re-hash the five `artifact-protocol.md` copies.
5. Re-locate `research/SKILL.md:148` (the Tier-3 subagent-return sentence) — the line number moves.

**Sanity Check:**

- `gh pr view 1260 --json state --jq .state` returns `MERGED`.
- `git fetch origin main` **first**, then `git merge-base --is-ancestor origin/main HEAD` exits 0 — without the fetch this passes vacuously against a stale ref, which is exactly the state of a session that just watched #1260 merge.
- `jq -r .version plugins/discovery/.claude-plugin/plugin.json` is **recorded in this PLAN** — it becomes the base Phase 6 bumps. Expected `0.8.3` (verified in #1260's diff), but the recorded value governs.
- `md5sum docs/PLUGIN-ARTIFACT-PROTOCOL.md plugins/{discovery,implementation,planning,verification}/reference/artifact-protocol.md | awk '{print $1}' | sort -u | wc -l` returns `1` — T1's byte-identity evidence survives the merge. (Asserted directly rather than via `scripts/check-cross-plugin-source-drift.sh`, which exits 0 while printing `DIFFERS` lines for unrelated registry rows and so is not a clean signal for this specific claim.)
- The outcome-gate table has 10 rows, counted **scoped to that table** — `awk '/^## Outcome gate/,/^## /' plugins/discovery/skills/research/SKILL.md | grep -c '^| [0-9]* |'`. An unscoped file-wide count silently breaks the moment #1260 or a later edit adds another numbered table.
- `grep -n 'Subagent returns are Tier 3' plugins/discovery/skills/research/SKILL.md` returns exactly one line; its number is recorded in this PLAN before Phase 2 starts.

### Phase 1: Agent definitions + end-to-end dispatch probe [TODO]

The integration slice. Two files, one live runtime probe — the tracer bullet that proves preload,
artifact write, and return payload work together before any skill text is rewritten.

**Work item 0 — close two evidence gaps BEFORE writing either agent file.** Both are testable in the
probe rig that produced Amendments 9a/9b, both feed the F2 blocker, and both fail *silently* if
guessed wrong:

- **The resolvable `skills:` value form.** The only documented example is a YAML list of bare names
  (`skills:\n  - api-conventions`). C1 originally used a quoted plugin-scoped string
  (`"discovery:research"`), which appears nowhere in the docs. Determine empirically what a
  plugin-shipped agent must write to preload a skill in its own plugin — bare leaf name, scoped
  name, or either — and record the answer here before authoring.
- **`$ARGUMENTS` under preload.** Documented only for the *invocation* path and probed by none of
  Amendments 9a–9c. `research/SKILL.md:24` is literally `Research the following topic: $ARGUMENTS`.
  If it does not resolve on the preload path, the preloaded body instructs the agent to research an
  unsubstituted literal.

Neither may be assumed. A wrong `skills:` value produces exactly F2's failure: skipped preload, debug-log
warning only, and a confident undisciplined run.

**RESOLVED 2026-07-25 — both gaps closed empirically, plus a third result nobody asked for.** Rig:
a throwaway `dispatchprobe` plugin loaded via `--plugin-dir`, headless `claude -p`, three plugin-shipped
agent files with identical bodies and `tools: []` so no agent could Read the skill and forge a value.
Sentinels appear nowhere in the dispatch prompt. Rig and raw transcripts:
`<session-scratchpad>/dispatchprobe/`, `probe-a.sh`, `probe-{scoped,bare,miss}.json`.

| Agent | `skills:` value | Result |
|---|---|---|
| `scopedprobe` | `dispatchprobe:mandate` | preload landed — `SENTINEL_BODY_LANDED_9931` quoted back |
| `bareprobe` | `mandate` | preload landed — same sentinel quoted back |
| `missprobe` | `dispatchprobe:nosuchskill` | `NO_SKILL_CONTENT` — **no error, no refusal, agent ran anyway** |

- **Both reference forms resolve** for an agent preloading a skill in its own plugin. C1's quoted
  plugin-scoped string is valid, and so is the bare leaf name the docs example uses. The scoped form
  is what Amendment 9b's `run12` already exercised cross-plugin, so it is now confirmed on both the
  same-plugin and cross-plugin paths. **Ship the scoped form** — it is the one with evidence on both
  paths and it survives a future leaf-name collision.
- **`$ARGUMENTS` is substituted with the EMPTY STRING on the preload path**, not left literal. The
  probe line `FIELD_ARGS_OPEN $ARGUMENTS FIELD_ARGS_CLOSE` came back as `FIELD_ARGS_OPEN  FIELD_ARGS_CLOSE`
  — two spaces, the token gone — identically on both resolving agents. Recorded as an inference, not a
  raw observation: the prompt asked for character-for-character reproduction, so a model could in
  principle have dropped a literal token rather than reported an empty substitution. Two independent
  runs agreeing, and the two-space signature being the expected artifact of empty substitution, is why
  it is treated as settled.
  **Consequence for Phase 2 work item 4:** `research/SKILL.md:24` (`Research the following topic: $ARGUMENTS`)
  arrives at a dispatched agent as an instruction with nothing after the colon — not as a visible
  literal the agent could recognize as unfilled. Combined with `:26`'s "infer from the current
  conversation context", which a non-fork subagent cannot do, the preloaded body gives the agent no
  topic and no way to notice. The topic MUST arrive in the dispatch prompt via Decision 8's
  pre-dispatch envelope, and the agent body's refuse-to-guess rule is what makes the absence loud.
- **F2's silent-miss premise is now empirically confirmed, not merely doc-quoted.** The negative
  control declared a skill that does not exist and the agent started, reported `NO_SKILL_CONTENT`, and
  would have proceeded — no error surfaced to the dispatching parent. This upgrades C2's
  `preload_token` sentinel from a precaution against a documented behavior to the observed-necessary
  detector for a failure this rig reproduced on demand.
- **`${CLAUDE_PLUGIN_ROOT}` expansion re-confirmed** on the preload path (Amendment 9b), and the
  sibling-file pointer arrived as a working absolute path whose *contents* stayed absent — the
  progressive-disclosure property Amendment 8 depends on.

| File | Action | Rationale |
|---|---|---|
| `plugins/discovery/agents/researcher.md` | CREATE | C1 frontmatter + agent body |
| `plugins/discovery/agents/explorer.md` | CREATE | C1 frontmatter + agent body |

Frontmatter is C1 verbatim. Bodies carry:

- The **dispatch-prompt contract** — what the parent must supply in the pre-dispatch envelope
  (Decision 8): resolved topic/scope, memory-slice path, budget, capability flags. The agent refuses
  to guess an unresolved scope rather than inventing one.
- A **tool-honesty note** following the `plugin-quality:auditor` precedent, stated at its true
  strength: `Bash` and `Write` are not read-only, `Write` targets the topic's memory slice only, and
  `Edit`'s absence buys no single-call in-place mutation of an existing repo file — **not** read-only
  status and **not** mechanical enforcement of the memory-tier invariant. Do not write the stronger
  claim; `memory` is omitted precisely so this weaker one stays true.
- The **preload-liveness sentinel** — the agent echoes the token verbatim into the C2 payload.
- The **C2 return payload** as the required final output, with `verification: pending` non-negotiable
  — the producer renders no verdict on its own confidence criterion.
- **Open questions return as text**, because `AskUserQuestion` is unavailable in a non-fork subagent;
  the parent re-surfaces them.
- The **hoisting rule**: already dispatched, so run the discipline inline; never re-dispatch.

`plugins/review/.claude-plugin/plugin.json` carries `agents` only as a keyword — agent directories
are auto-discovered, so no manifest path entry is added.

**Correct C1's precedent sentence while here.** It says the shape "follows the seven already
shipped". Verified: `plugins/plugin-quality/agents/auditor.md` declares only `name`, `description`,
`tools` — no `memory`, `effort`, or `maxTurns`. The claim holds for the **six `review/` agents**, not
the seventh. The chosen field set does not change; the citation does.

**Sanity Check:**

- `claude plugin validate plugins/discovery` exits 0. **This validates the manifest only** — verified by running it: its output names `.claude-plugin/plugin.json` and it never opens `agents/*.md`. It is not a check on the agent definitions, so the assertions below carry that weight.
- `grep -c '^skills:' plugins/discovery/agents/*.md` returns 1 per file, in the value form work item 0 established.
- `grep -c '^model: inherit' plugins/discovery/agents/*.md` returns 1 per file.
- `grep -cE '^(name|description|tools|effort|maxTurns):' plugins/discovery/agents/researcher.md` returns 5, and the same for `explorer.md` — every C1 field present, none dropped.
- **`! grep -q '^memory:' plugins/discovery/agents/*.md` exits 0.** Declaring `memory` auto-enables `Edit` regardless of `tools` (docs, verbatim: "Read, Write, and Edit tools are automatically enabled so the subagent can manage its memory files"), which would falsify the agent body's own tool-honesty note. Its absence is load-bearing, so it is asserted, not assumed.
- **Runtime assertion, not prose: the probe confirms `Edit` is genuinely unavailable to the dispatched agent** — ask it to attempt one edit and assert it cannot.
- The probe's returned payload carries a matching `preload_token`; a missing or mismatched token fails this phase.
- Frontmatter parses as YAML: `node -e "const m=require('fs').readFileSync(p,'utf8').split('---')[1]; require('yaml')" ` or equivalent — assert both files open and close a `---` block with no tab characters inside.
- Neither declares an ignored field — `grep -E '^(hooks|mcpServers|permissionMode):' plugins/discovery/agents/*.md` returns no match (exit 1).
- **Runtime probe (end-to-end):** dispatch `discovery:researcher` on a small bounded topic; assert (a) the returned text contains the C2 YAML block, (b) `verification: pending` is present, (c) the named artifact exists on disk, (d) the transcript shows the discipline's phase structure, proving `skills:` preload landed.

### Phase 2: `research/SKILL.md` — dispatch posture, Phase 0 corpus enumeration, coverage gate [TODO]

The largest phase. Contract migration, so it opens with a consumer pre-flight.

| File | Action | Rationale |
|---|---|---|
| `plugins/discovery/skills/research/SKILL.md` | MODIFY | routing, Phase 0, gate rows, T8 exception, sidecar index |
| `plugins/discovery/skills/research/context/discipline.md` | MODIFY | Phase 0 recipe, coverage-ledger recipe |
| `plugins/discovery/scripts/check-coverage-complete.sh` | CREATE | C4 deterministic gate |
| `plugins/discovery/scripts/check-coverage-complete.test.sh` | CREATE | auto-discovered by `scripts/run-plugin-tests.sh` |
| `plugins/discovery/skills/research/evals/evals.json` | MODIFY | dispatch + coverage-ledger cases |
| `plugins/discovery/reference/artifact-protocol.md` | KEEP | T1: no version bump; byte-identity is CI-enforced |

Work items in order:

1. **Identify consumers (pre-flight, first).** `Grep` + `Glob` for anything parsing the outcome-gate
   table, the `RESEARCH.md` filename, or the artifact's section structure — across `plugins/**`,
   `scripts/**`, `.github/workflows/**`. T1's sweep found only path-forwarders and naming references
   plus one sibling producer (`knowledge/youtube-digest`), which discharges the Brief's captured
   assumption; this item re-runs it against post-#1260 `main` and records the parse paths found.

   **RUN 2026-07-25 against pre-merge `HEAD`; treat the post-merge run as confirmation, not
   discovery.** #1260's five files are `plugins/discovery/{.claude-plugin/plugin.json,CHANGELOG.md,
   skills/research/{SKILL.md,context/discipline.md,evals/evals.json}}` — all producer-side. It adds
   no consumer, so the consumer set cannot have grown. Findings:

   - **No parser of the outcome-gate table exists anywhere.** `grep -rn 'Outcome gate\|outcome-gate'
     scripts/ .github/` returns nothing. The table is read by models, never by code, so Phase 2's
     row additions and the C2 ownership column break no gate.
   - **Every cross-plugin `RESEARCH.md` reference outside `plugins/discovery/` is a naming
     reference**, in `plugins/{implementation,planning,verification}/reference/artifact-protocol.md`
     — the byte-identical protocol copies T1 already covers, which name the file in a memory-tier
     inventory line and parse nothing.
   - **One executable touches a file of this name:** `plugins/knowledge/skills/youtube-digest/
     extraction/evals/check-research-complete.js`. It resolves `path.join(sliceDir, "RESEARCH.md")`
     inside **youtube-digest's own slice** — the sibling producer T1 named — and asserts a **minimum
     length** (`FAIL: RESEARCH.md too short`), not a section structure. Unaffected by Decision 4,
     because discovery does not write that slice. **Recorded anyway as the one shape that would
     break:** a min-length gate is exactly what an always-an-index artifact fails, so if the index
     shape is ever generalized beyond discovery, this check is the first casualty. Out of scope
     here; it belongs to the sweep topic.
2. **Mechanical sweep before any edit** — do not hand-enumerate the subagent-incompatible text. A
   hand list already missed four sites across two files. Grep both SKILL.md bodies for every
   instruction that names the user, a filtered tool, plan mode, main-context execution, or an inline
   preference, and record the hit list in this PLAN before editing. The repo scripts this class
   elsewhere (`check-silent-skips.sh`, `check-skill-portability.sh`); this is the same discipline.
3. **Overturn all three inline-preference statements**, not just one. Verified present:
   - `:126` — "prefer direct research when results inform decisions" (Decision 1 overrides it).
   - `:65` — "**Prefer direct-context web** (WebSearch / WebFetch in the main session) … results land
     without summarization loss." The same claim stated more strongly, inside Phase 1.
   - `:18` — "For context-heavy passes, use `/research-deep` (dispatches to an isolated execution
     tier; keeps main context clean)." False framing once `/research` also dispatches.
4. **Reconcile `$ARGUMENTS` and conversation-context inference** — `:24` (`Research the following
   topic: $ARGUMENTS`) and `:26` ("infer the research topic from the current conversation context").
   A non-fork subagent has no conversation context, so `:26` contradicts the agent body's
   refuse-to-guess rule. Resolve per work item 0's `$ARGUMENTS` finding.
3. **Routing section** — dispatch-by-default, the documented inline escape hatch and the condition
   under which it is correct (tight turn-by-turn iteration), and the hoisting rule.
4. **Phase 0 (corpus enumeration)** — enumerate the corpus and write `research-checklist.md` before
   any query, with a per-item depth criterion fixed at enumeration time. Recipe in `discipline.md`.
5. **Outcome-gate row** — coverage ledger fully marked, verdict cited from the script's exit status.
   Script-verified today; it earns check 21's `deterministic-gate` exemption class only **once #1096
   lands** — that check does not exist yet, and neither does
   `plugins/skill-quality/skills/check/reference/` (verified: the `check` skill directory holds only
   `SKILL.md` and `evals/`). Do not write the skill text as though the exemption is already
   claimable.
   The skill must cite the gate as `${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh` —
   `check-skill.sh` check 5 resolves a backtick-cited relative `scripts/…` path against the *skill*
   directory and would FAIL. Note also that check 7 runs `<skill>/scripts/*.test.sh` only, so the
   research skill's own gate does not run this test; CI's `run-plugin-tests.sh` is the seam that
   does.
6. **T8 scoped exception** at the Tier-3 subagent-return sentence: the tier attaches to the artifact
   and its captured primaries, never to the transport. Named case: a dispatched agent that ran the
   full discipline and wrote every primary URL into the artifact. Without this, Decision 1
   contradicts the skill it modifies.
7. **Gate ownership split** per C2 — rows 4 and 7 to the sibling verifier, row 8 to the parent, the
   rest to the producer. Marked in the table itself so a dispatched run knows what it may not
   self-grade.
8. **Index-plus-sidecars** — `RESEARCH.md` is always an index (not past ~2000 words); sidecars carry
   the C3 YAML header. Constraint from T1: sidecars stay inside `<memory_dir>/<topic-slug>/` and
   `RESEARCH.md` stays the entry point, or T1 reopens.
9. **`check-coverage-complete.sh`** — non-zero when any `Done` cell is unmarked. `#!/usr/bin/env bash`.
   Must also define behavior on a **malformed or hand-edited ledger** (missing table, no rows,
   mangled columns): fail closed with a distinct exit code, never silently pass.
10. **Set the exec bit explicitly.** This worktree has `core.filemode=false` (verified), so a new
    `.sh` lands `100644` in the index while every existing plugin script is `100755` (verified
    against `plugins/planning/scripts/`). CI's shebang-executable step feeds
    `scripts/aggregate-hygiene-results.sh`, which fails the hygiene job on any non-`success`
    outcome. Run `git update-index --chmod=+x` on both new files.
11. **Clear the two existing skill-quality warnings** — `research` PASSes today with `no Gotchas
    surface` and `description has no 'Use when:' trigger phrasing`. Add a `## Gotchas` section, and
    rewrite the description into `Use when:` phrasing **preserving every existing quoted trigger
    phrase verbatim** — check 3 compares the description against HEAD and FAILs on a dropped tracked
    phrase.
12. **evals** — add a dispatch case and a coverage-ledger case.

**Sanity Check:**

- All three inline-preference statements are gone, not just one: `! grep -qE 'prefer direct research|Prefer direct-context web|keeps main context clean' plugins/discovery/skills/research/SKILL.md` exits 0.
- The mechanical sweep's hit list is recorded in this PLAN, and every hit is either edited or explicitly marked correct-under-dispatch.
- `grep -c 'research-checklist.md' plugins/discovery/skills/research/SKILL.md` ≥ 1 and the same in `context/discipline.md`.
- `bash plugins/discovery/scripts/check-coverage-complete.test.sh` exits 0.
- `bash plugins/discovery/scripts/check-coverage-complete.sh <fixture-with-unmarked-row>` exits non-zero; the all-marked fixture exits 0; the malformed fixture exits non-zero with the fail-closed code.
- `shellcheck -x plugins/discovery/scripts/*.sh` exits 0 — CI runs ShellCheck against `.shellcheckrc` and it feeds the job-failing hygiene aggregate.
- `git ls-files -s plugins/discovery/scripts/` shows `100755` for both files.
- Sidecar placement is pinned in the skill text, not merely in this plan: `grep -c 'memory_dir\|<topic-slug>/' plugins/discovery/skills/research/SKILL.md` ≥ 1 in the sidecar section, and `grep -c 'RESEARCH.md' …` shows it named as the entry-point index — T1's two reopen conditions enforced mechanically rather than by prose alone.
- An eval case asserts a sidecar lands inside the topic's memory slice.
- `CHECK_SKILL_SKILLS_ROOT=plugins/discovery/skills bash plugins/skill-quality/scripts/check-skill.sh research` exits 0 **with zero warnings** — the skill carries two today (no Gotchas surface; no `Use when:` trigger phrasing) and this phase is the touch that clears them.
- `awk 'END{exit NR>=500}' plugins/discovery/skills/research/SKILL.md` — the file stays under check 4's 500-line hard cap after Phase 0 and the routing section are added.
- `node -e "JSON.parse(require('fs').readFileSync('plugins/discovery/skills/research/evals/evals.json'))"` exits 0.
- `bash scripts/check-skill-portability.sh --all` exits 0 (the bare form is a usage error — the script requires `<base-ref>`, `--all`, or `--paths`).

### Phase 3: `explore/SKILL.md` — same posture, index shape, open-question hand-back [TODO]

| File | Action | Rationale |
|---|---|---|
| `plugins/discovery/skills/explore/SKILL.md` | MODIFY | routing rewrite, index shape, open-question contract |
| `plugins/discovery/skills/explore/evals/evals.json` | MODIFY | dispatch case |
| `plugins/discovery/skills/explore/reference/ecosystem-discovery.md` | KEEP | dimension reference, unaffected |

0. **Identify consumers (pre-flight, first).** `EXPLORE.md`'s shape migration is as cross-boundary as
   `RESEARCH.md`'s — mirror Phase 2's item 1 for `EXPLORE.md`: `Grep` + `Glob` for anything parsing
   the filename or the artifact's section structure across `plugins/**`, `scripts/**`,
   `.github/workflows/**`, run against post-#1260 `main`, and record the parse paths found.

   **RUN 2026-07-25.** `EXPLORE.md` is named in 40 places; **none parses its section structure.**
   They partition into naming references (the four `artifact-protocol.md` copies plus
   `docs/PLUGIN-ARTIFACT-PROTOCOL.md`, the plugin README and root catalog, `reference/topic-docs.md`),
   CHANGELOG history, sibling hand-off references (`blindspot/SKILL.md` and its evals, which assert
   the run does **not** write the artifact), and two test fixtures using the filename as an arbitrary
   nested-path token (`source-control/scripts/worktree-create.test.sh`,
   `docs-hygiene/skills/audit-noise/scripts/detect.test.sh`).

   **The one glob-shaped coupling is already sidecar-aware, verified rather than assumed.**
   `docs/conventions/topic-docs/README.md` documents the `.worktreeinclude` recipe as six patterns —
   `.work/.gitignore`, `.work/*/EXPLORE.md`, `.work/*/EXPLORE-*.md`, `.work/*/RESEARCH.md`,
   `.work/*/RESEARCH-*.md`, `.work/*/*-checklist.md`. A bare `.work/*/EXPLORE.md` would have carried
   the index into a new worktree and dropped every sidecar, which under Decision 4 is strictly worse
   than today's self-contained artifact. The sidecar globs are already there, and so is
   `*-checklist.md`, which Decision 5's `research-checklist.md` needs. **The Brief's captured
   assumption — "downstream consumers tolerate an index-plus-sidecar shape without code changes" —
   holds for `EXPLORE.md`, and now on evidence.**

0b. **Mechanical sweep — RUN 2026-07-25, hit list below.** Phase 2 work item 2's method, inherited
   here and run first because `explore/SKILL.md` is **not** among #1260's five files, so its line
   numbers are stable across the Phase 0 rebase and the sweep does not have to wait. Script:
   `<session-scratchpad>/sweep-subagent-incompatible.sh`, six pattern classes — filtered tools,
   instructions presupposing a human turn, plan mode, main-context assertions, inline preferences,
   and `$ARGUMENTS`. Every hit is a candidate; the disposition column is the judgment.

   | Line | Class | Text | Disposition |
   |---|---|---|---|
   | 20 | main-context | "keeping that out of the main conversation is what subagents are for. Three ways to run it" | EDIT — item 1's routing rewrite |
   | 22 | main-context | built-in Explore subagent bullet, "the main session synthesizes their summaries and persists the artifact" | EDIT — retained as a named alternative, but the synthesis sentence is false once `discovery:explorer` writes the artifact itself |
   | 23 | main-context | inline `/explore` bullet, "Runs the full 6 dimensions in main context" | EDIT — becomes the escape hatch, with F10's cost reason named alongside tight iteration |
   | 24 | main-context | `/explore-deep` bullet, incl. the stale `CLAUDE_CODE_FORK_SUBAGENT=1` requirement | EDIT — written so Phase 5 removes a bullet rather than rewriting the section twice |
   | 26 | main-context | "the main session synthesizes and writes `EXPLORE.md` (built-in Explore agents cannot write it)" | EDIT — the parenthetical stays true of *built-in* Explore agents; the leading clause is false under dispatch and must be scoped to the fan-out case it describes |
   | 36 | plan-mode | "switch into plan mode for harness-level read-only protection" | EDIT — work item 3b; Filter-1 tools |
   | 40 | `$ARGUMENTS` | "Explore the following: `$ARGUMENTS`" | EDIT — empty under preload (work item 0); scope arrives in the dispatch prompt |
   | 42 | main-context | "infer the exploration scope from the current conversation context" | EDIT — a non-fork subagent has none; contradicts the agent body's refuse-to-guess rule |
   | 66 | user-turn | "**ask the user before investigating**" deleted files | EDIT — work item 3b |
   | **108** | `$ARGUMENTS` | "The `$ARGUMENTS` value shapes the exploration focus:" | **EDIT — NEW SITE, absent from every hand list including this plan's own Phase 3 items.** Same defect as `:40` and reached only by the sweep. Third confirmation that hand enumeration under-reads this file |
   | 122 | user-turn | "Surfacing the USER's unknown-unknowns … is the sibling `/discovery:blindspot` skill" | CORRECT UNDER DISPATCH — describes a *sibling skill's* deliverable, issues no instruction to this run |
   | 134 | user-turn | Output-format item 7, "**Surface these to the USER**" | EDIT — item 3 |
   | 146 | user-turn | outcome-gate bullet, "Open questions surfaced to the user" | EDIT — item 3 |

   Eleven edits, one correct-under-dispatch, one site (`:108`) that no hand pass had found.

1. **Rewrite the routing section (currently lines 18–26).** It names three ways to explore and
   makes inline the structured default. Post-change: `discovery:explorer` is the default,
   with the built-in Explore subagent and inline retained as named alternatives and the escape-hatch
   condition documented. The `explore-deep` bullet's fate is Phase 5's gate — write this section so
   Phase 5 removes a bullet rather than rewriting the section twice.
2. **Index-plus-sidecars** for `EXPLORE.md`, C3 header on sidecars, same T1 constraints.
3. **Open questions** (Output-format item 7 and the outcome-gate bullet at `:146`) — currently
   "Surface these to the USER". A dispatched agent cannot. Reword to: the agent returns them in the
   C2 payload; the parent surfaces them to the user. The anti-pattern being guarded (silent
   downstream resolution) survives intact.
3b. **Two further user-interaction sites the first pass missed** — found by the same mechanical sweep
   Phase 2 work item 2 mandates, which applies here too:
   - `:66` — "**ask the user before investigating**" deleted files. A non-fork subagent cannot ask,
     so under dispatch this becomes either a stall or a silent violation of a rule that exists to
     protect *intentional* deletions. Reword to: record the deleted-file question as an
     `open_questions` entry and do **not** perform git archaeology on it.
   - `:36` — recommends switching into plan mode. `EnterPlanMode` / `ExitPlanMode` are in Filter 1 of
     this Brief's own Constraints block, so the recommendation is unreachable from a dispatched run.
     Scope it to the inline path.
4. **Hoisting rule**, same wording as Phase 2.
5. **evals** — dispatch case.

**Sanity Check:**

- `! grep -q 'Surface these to the USER' plugins/discovery/skills/explore/SKILL.md` exits 0 (`grep -c` exits 1 on a zero count, so the passing case must be written this way).
- `! grep -q 'ask the user before investigating' plugins/discovery/skills/explore/SKILL.md` exits 0 — the unreachable block at `:66` is reworded, not left to stall a dispatched run.
- The plan-mode recommendation at `:36` is scoped to the inline path: `grep -n 'plan mode' plugins/discovery/skills/explore/SKILL.md` shows it qualified, since `EnterPlanMode`/`ExitPlanMode` are Filter-1 tools.
- `grep -n 'open_questions' plugins/discovery/skills/explore/SKILL.md` returns ≥ 1 (the C2 hand-back is named).
- `CHECK_SKILL_SKILLS_ROOT=plugins/discovery/skills bash plugins/skill-quality/scripts/check-skill.sh explore` exits 0 with zero warnings — it carries 1 today, and the description rewrite must preserve its 1 tracked trigger phrase verbatim or check 3 FAILs.
- Sidecar placement pinned in the skill text and covered by an eval, same as Phase 2 — T1's two reopen conditions.
- `awk 'END{exit NR>=500}' plugins/discovery/skills/explore/SKILL.md` — under the 500-line cap.
- `node -e "JSON.parse(require('fs').readFileSync('plugins/discovery/skills/explore/evals/evals.json'))"` exits 0.

### Phase 4: `setup/SKILL.md` capability detection + sibling-skill audit [TODO]

| File | Action | Rationale |
|---|---|---|
| `plugins/discovery/skills/setup/SKILL.md` | MODIFY | add capability probe to `check`; recommend in `apply` |
| `plugins/discovery/skills/research-deep/SKILL.md` | AUDIT, modify only if needed | acceptance criterion 9 |
| `plugins/discovery/skills/blindspot/SKILL.md` | AUDIT, modify only if needed | the plugin's fourth skill; not silently omitted |

**Sibling-skill audit** — the two discovery skills this plan does not otherwise touch still need an
explicit disposition, or the plugin ships an inconsistent posture. **The same mechanical sweep was run
over all three of this phase's files on 2026-07-25** (none is among #1260's five, so the results are
rebase-stable), which turns the dispositions below from assertions into readings:

- **`setup/SKILL.md` — ZERO hits across all six pattern classes.** No filtered tool, no human-turn
  instruction, no plan mode, no main-context assertion, no inline preference, no `$ARGUMENTS`. This
  phase's work on it is therefore purely additive; nothing existing has to be reconciled.
- **`research-deep/SKILL.md` — every hit is the skill arguing its own inline requirement**, which is
  exactly what acceptance criterion 9 demands survive. `:18` ("It must run in main context to reach
  the Workflow tool … a subagent cannot") and `:82` ("Does NOT run the deep pass itself in main
  context — it dispatches") are the criterion's evidence, in the file, unedited. `:28`'s multi-topic
  path names the `Agent` tool, which errors even inside a fork — Decision 14's second independent
  ground. **No edit required**; the audit's job is to confirm Phase 2's routing section does not
  contradict these, not to change them.
- **`blindspot/SKILL.md` — hits confirm INLINE-ONLY on the merits, not by inheritance.** `:34`
  ("**Intake** — ask the user's starting point first (one question)") is a genuine elicitation gate
  under Decision 11's three-cell test: the answer is not derivable from arguments or prior
  conversation, and the deliverable is calibrated to it. `:3`, `:20`, `:25`, `:45`, and `:72` all
  restate that the deliverable *is* a better prompt for the USER — Amendment 5's exclusion, evidenced.
  `NO-CHANGE` is therefore the recorded outcome with a reason, not a default.

- **`research-deep`** — Decision 14 keeps it, and acceptance criterion 9 requires it to *still*
  dispatch Tier 1 from main context. Its inline-dispatcher requirement rests on independent grounds
  (`Workflow` is unavailable in every non-fork subagent, and its multi-topic path needs `Agent`,
  which errors even in a fork). Confirm its text still says so and does not accidentally inherit
  Phase 2's dispatch-by-default posture; if `research/SKILL.md` gained a routing section that
  `research-deep` now contradicts, reconcile the two.
- **`blindspot`** — **dispatch posture only.** Its deliverable is a better prompt for the USER, not
  an artifact, so Amendment 5 scopes index-plus-sidecars away from it; `NO-CHANGE` is a valid, stated
  outcome. Its `/discovery:explore-deep` references (`SKILL.md`, and two in `evals/evals.json`) are
  **explicitly out of scope here** — they depend on Phase 5's retirement gate, which runs after this
  phase, and are owned by Phase 5's live-reference table. Deciding them here would pre-empt Phase 5.

`check` gains a capability block reporting, as PASS/INFO rows:

- Harness version against the **2.1.219** floor, naming which Brief-recorded behaviors are false below it.
- `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` — present or absent; absence is INFO plus the recommendation, never FAIL (Decision 9 demoted it to an optimization).
- Fork availability — default-on since v2.1.161; the variable now only forces on or off. Do not reproduce the stale "rollout-gated" framing.

Absence degrades, never blocks. No new config keys — the topic-docs concern file's schema is
untouched.

**Sanity Check:**

- `grep -c 'CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH' plugins/discovery/skills/setup/SKILL.md` ≥ 1.
- `grep -n '2\.1\.219' plugins/discovery/skills/setup/SKILL.md` returns ≥ 1.
- `grep -n 'rollout-gated\|CLAUDE_CODE_FORK_SUBAGENT=1' plugins/discovery/skills/setup/SKILL.md` returns no stale-gate phrasing.
- `CHECK_SKILL_SKILLS_ROOT=plugins/discovery/skills bash plugins/skill-quality/scripts/check-skill.sh setup` exits 0 with zero warnings — it carries 1 today, and `setup` has **5 tracked trigger phrases**; any description rewrite must preserve all five verbatim or check 3 FAILs.
- `grep -n 'Workflow' plugins/discovery/skills/research-deep/SKILL.md` still shows the subagent-unavailability rationale — acceptance criterion 9 holds.
- `grep -rn 'dispatch' plugins/discovery/skills/research-deep/SKILL.md plugins/discovery/skills/blindspot/SKILL.md` — every hit is reconciled with Phase 2's routing section, or this PLAN records the skill as `NO-CHANGE` with its reason.
- `CHECK_SKILL_SKILLS_ROOT=plugins/discovery/skills bash plugins/skill-quality/scripts/check-skill.sh research-deep` and `… blindspot` both exit 0 with zero warnings.
- `git diff --name-only` for this phase shows no change to `blindspot/evals/evals.json` — its `explore-deep` references belong to Phase 5.

### Phase 5: `explore-deep` retirement — conditional [TODO]

Decision 14 retires `explore-deep` **only once `explorer.md` reproduces its project-memory loading
and sidecar-on-collision behavior**. This phase evaluates that condition and branches.

1. Read `explore-deep/SKILL.md` end to end; enumerate every behavior it carries beyond `/explore`.

   **DONE 2026-07-25 — enumeration below, read against the file at `c583705121`.** Pulled forward out
   of Phase 5 on purpose: Decision 14's gate is "does `explorer.md` reproduce these", and `explorer.md`
   is authored in **Phase 1**. Discovering the list only at Phase 5 would mean either a rewrite or a
   retirement blocked on work Phase 1 could have done. Phase 1 authors against this table; Phase 5
   grades against it.

   | # | Behavior beyond `/explore` | Site | Phase 1 obligation |
   |---|---|---|---|
   | 1 | **Path-scoped project rules loaded explicitly** — a subagent does not auto-load `.claude/rules/`, so scope-relevant rule files are Read before scope work begins | `:30` | **Decision 14 gate condition A.** `explorer.md` must carry this or `explore-deep` cannot retire |
   | 2 | **Sidecar on collision** — an existing unrelated `EXPLORE.md` diverts the write to `EXPLORE-<scope>.md`, and the filename choice is surfaced in the return | `:50` | **Decision 14 gate condition B.** Same |
   | 3 | **Scope comes only from `$ARGUMENTS`, with a defined empty-scope fallback** — a general repository-orientation pass, declared as unscoped in *both* artifact and summary | `:32` | Reframe, do not copy: work item 0 settled that `$ARGUMENTS` is empty under preload, so the agent's scope arrives in the dispatch prompt. The *fallback* survives as the refuse-to-guess rule; the empty-scope orientation pass does not, because a dispatched agent with no scope is a parent-envelope failure, not a mode |
   | 4 | **Absolute project root resolved but never echoed into the artifact** — machine-agnostic relative paths only | `:18` | Carry into `explorer.md`; it is an artifact-portability invariant, independent of dispatch |
   | 5 | **Read-only boundary stated as instruction, not tool enforcement** — no Edit, no mutating Bash; the only writes are the artifact and the memory root's self-ignoring `.gitignore` guard | `:24` | Already the shape of Phase 1's tool-honesty note. Note the `.gitignore` guard write — it is a second permitted write target and the note must not claim a single one |
   | 6 | **Outcome gate runs BEFORE the write**, as a binary artifact self-check rather than a did-I-explore-enough recap | `:46` | Carry over, reconciled with C2's `verification: pending` — the producer still renders no verdict on the criteria C2 assigns away |
   | 7 | **Assumed destinations are flagged in the return summary** under the non-interactive/forked-mode rule | `:48` | Folds into the C2 payload rather than prose |
   | 8 | **Return shape is bounded** — one 3–5 sentence paragraph, the artifact path, blocking open questions, and explicitly NOT the 7-section report | `:54`–`:60` | Already C2's shape; confirms C2 was derived from a real precedent rather than invented |
   | 9 | **`!` precompute of branch, working-tree status, and project root** | `:14`–`:16` | **Do not reproduce.** Amendment 9c's rule: precompute fires at every spawn before the agent knows it needs the data, and multiplies under fan-out. Amendment 7 additionally bars correctness from depending on it |
   | 10 | **Stale `CLAUDE_CODE_FORK_SUBAGENT=1` requirement in the description** | `:3` | Not a behavior — the defect #1267 tracks, doubly wrong for also attaching the gate to `context: fork` rather than the `fork` subagent type. Step 4's disposition covers it |

2. Check each against `plugins/discovery/agents/explorer.md` as written in Phase 1.
3. **Gate:** every behavior reproduced → retire. Any behavior missing → **do not retire**; add it to
   `explorer.md` if cheap, else leave `explore-deep` in place and file the residue as a work item.

   The retire branch is **not three actions** — a live-reference sweep found seven files outside
   `docs/topics/**` and outside `explore-deep/` that name the skill. Retiring without them ships
   dangling references to a deleted user-invocable skill, two of them in doctrine docs that cite it
   as *the* isolated-execution-tier example:

   | File | What it needs |
   |---|---|
   | `plugins/discovery/skills/explore/SKILL.md` | remove the routing bullet added in Phase 3 |
   | `plugins/discovery/skills/blindspot/SKILL.md` | re-point the sibling reference |
   | `plugins/discovery/skills/blindspot/evals/evals.json` | re-point two expectations |
   | `plugins/discovery/README.md` | drop the skill from the listing |
   | `plugins/discovery/reference/topic-docs.md` | re-point two references |
   | `docs/MIGRATION-PLAYBOOK.md` | re-point the example |
   | `docs/PLUGIN-PHILOSOPHY.md` | re-point the isolated-execution-tier example to `discovery:explorer` |
   | `plugins/discovery/CHANGELOG.md` | breaking-change entry for `/discovery:explore-deep` callers |

   `docs/PLUGIN-PHILOSOPHY.md` is also #1096's edit surface — coordinate that edit or sequence it
   after #1096 merges rather than creating a second conflict.
4. Either way, comment on **#1267** (`status: ready`, names `explore-deep/SKILL.md:3` — the stale
   `CLAUDE_CODE_FORK_SUBAGENT=1` requirement attached to the wrong mechanism). If retired, #1267
   dissolves and says so; if not retired, this phase fixes line 3 in passing and closes #1267.
   Never edit that line and leave #1267 open in parallel.

**Sanity Check:**

- Retire branch: `ls plugins/discovery/skills/explore-deep` fails, and `grep -rl 'explore-deep' plugins/ docs/ README.md | grep -v 'docs/topics/' | grep -v CHANGELOG` returns nothing (exit 1) — zero live references outside history and this topic's own docs.
- Keep branch: `grep -n 'CLAUDE_CODE_FORK_SUBAGENT' plugins/discovery/skills/explore-deep/SKILL.md` shows the corrected, non-gate wording and names `context: fork` as distinct from the `fork` subagent type.
- Either branch: `claude plugin validate plugins/discovery` exits 0 and `bash scripts/run-plugin-tests.sh` exits 0.

### Phase 6: Manifest, CHANGELOG, README, catalog [TODO]

Serialized last on purpose — issue #464 records that same-plugin version bumps plus top-inserted
CHANGELOG entries serialize concurrent PRs by construction. Touching these first would re-create the
#1260 collision this plan spent Phase 0 clearing.

| File | Action | Rationale |
|---|---|---|
| `plugins/discovery/.claude-plugin/plugin.json` | MODIFY | version bump; description drops the stale "inline or in an isolated forked subagent" framing |
| `plugins/discovery/CHANGELOG.md` | MODIFY | top-inserted entry |
| `plugins/discovery/README.md` | MODIFY | dispatch posture, the two agents, the escape hatch |
| `README.md` (repo root) | REGENERATE | carries the plugin description **verbatim** at line 58; `scripts/validate-plugins.sh` runs `node scripts/generate-catalog.mjs --check`, so editing the manifest description without regenerating fails this phase's own gate |

**Version is derived, not literal.** #1260 bumps discovery to **0.8.3** (verified in the PR diff), so
the post-rebase base is 0.8.3, not the 0.8.2 on disk today. Phase 0 records the actual post-rebase
value; this phase bumps that value **one minor** — new agent components, a new mandatory research
phase, and a changed default posture make it minor, not patch. Never hardcode the target.

Work item order: edit `plugin.json` and `CHANGELOG.md`, then run
`node scripts/generate-catalog.mjs` to regenerate the root README, then verify.

**Sanity Check:**

- `jq -r .version plugins/discovery/.claude-plugin/plugin.json` returns exactly one minor above the value Phase 0 recorded (expected `0.9.0` if the post-rebase base is `0.8.3`, but the recorded value governs).
- The regenerated catalog picked up the new description (asserted above).
- `bash scripts/check-changelog-parity.sh --check` exits 0, and `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0 (the bump form is what CI's `changelog-parity-gate` runs).
- `! grep -q 'forked subagent' plugins/discovery/.claude-plugin/plugin.json` exits 0, and `! grep -q 'inline or in an isolated forked subagent' README.md` exits 0.
- `bash scripts/validate-plugins.sh` exits 0 — this is the gate that catches a manifest description edited without regenerating the root README catalog.
- `git diff --stat` for this phase includes `README.md`; a Phase 6 diff without it means the catalog was not regenerated.

### Phase 7: Upstream contributions and tracker writes — off this branch [TODO]

None of this edits this branch's files. **Every item searches before it creates** — a duplicate
issue is worse than no issue.

1. `gh issue list --search "<terms>" --state all` for each candidate below. On a match: comment on
   the existing item instead of filing, and record the match in this phase's Sanity Check.
2. **#304 / #1096 proposal** — admit `skills:` preload as a third named-agent qualifier. This is the
   T2 fork's mitigation: C1's second conjunct is argued from the tool cage, not met, and the cage
   holds `Bash` and `Write` so it narrows rather than enforces. Comment on #1096 (currently
   **CONFLICTING**, unreviewed) rather than blocking on it.
3. **C5 execution-site declaration** — extend `plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md`
   and check 21 with the closed value set `dispatch | inline | either`. Sequenced **after** #1096
   merges; spec ownership stays with `skill-quality`, discovery is a consumer.
4. **#1225** — comment linking this topic as its execution, with the scope statement: Part 1's
   conventions research is this Brief's Constraints block, retargeted at `docs/OFFICIAL-DOCS.md`
   under the locked pointer-not-copy rule; Part 2's audit is the 138-row ledger.
5. **File the sweep topic** (Decision 1a) — the 138-skill dispatch-posture sweep.
   **The ledger must be promoted before the issue is filed.** Verified: `.work/.gitignore` contains
   `*`, so `skill-dispatch-audit-checklist.md` and all eleven batch artifacts are untracked and
   worktree-local — they vanish on worktree cleanup and are invisible to any other clone or session
   that picks up the sweep. Filing an issue that points at them hands the next session a dangling
   reference. Promote them to a tracked location (`docs/topics/<sweep-slug>/`) or attach them to the
   issue body **first**, then file.
6. **File the `playbooks:fable-5` conflict** — its core doctrine encodes a competing delegation rule
   whose 5+-item fan-out floor is stricter than this sweep's DISPATCH-DEFAULT signals. Surfaced by
   D9, unresolved.
7. **Dotfiles backfill** — `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH: "5"` was added to
   `~/.claude/settings.json` this session; that file is chezmoi-tracked and the backfill to
   `melodic-software/dotfiles` is owed. Route through the dotfiles repo's own flow; never
   `chezmoi apply` from an agent context.

**Sanity Check:**

- Every filed item's search command and its result (match / no match) is recorded in this PLAN before the item is created.
- `gh issue list --search "dispatch posture sweep" --state all` returns the sweep topic exactly once.
- `gh issue view 1225 --json comments` shows the linkage comment.
- `gh issue view 1267 --json comments` shows Phase 5's disposition comment.

### Blast radius

**HIGH.** Changes the default execution posture of two skills the rest of the marketplace's
documented workflows chain through; adds the plugin's first agent components; adds a mandatory
research phase and a new gate row; conditionally deletes a shipped skill (`explore-deep`), which is a
breaking change for any caller. Triggers matched: cross-cutting behavior change, new component type,
public-surface deletion, contract migration.

### Test strategy

TDD applies where there is executable code: `check-coverage-complete.test.sh` is written **before**
`check-coverage-complete.sh` (Red-Green-Refactor), with fixtures for the all-marked, one-unmarked,
and malformed-table cases. Everything else in this plan is skill and agent markdown, where the
verification seams are the ones the repo already runs — `check-skill.sh` per skill,
`scripts/run-plugin-tests.sh` for shipped shell, `claude plugin validate` for the manifest, and
`evals/evals.json` per skill for behavioral expectations. No new test seam is introduced (T9's
resolved position). The Phase 1 runtime probe is the one genuinely new verification: a live dispatch
asserting preload, artifact write, and payload shape end to end — the only way to catch a preload
regression that no static check sees.

### Execution shape

**Recommendation: sequential, main-session, with one optional parallel wave.**

File-overlap matrix — Phases 2, 3, and 4 touch disjoint file sets (`skills/research/**` +
`scripts/**`, `skills/explore/**`, `skills/setup/**` respectively) and have no inter-phase data
dependency. They are the only parallel-safe set.

| Phase | Surface | Basis |
|---|---|---|
| 0 | main session | Merge + rebase is a judgment-and-authorization act, not delegable work |
| 1 | main session | Two files, high judgment density, and the runtime probe needs the session's dispatch capability |
| 2 | main session (or sub-agent worker in Wave A) | Largest volume, but the T8 exception wording and the gate-ownership split are judgment calls |
| 3 | main session (or sub-agent worker in Wave A) | Routing rewrite is judgment; the sidecar shape is mechanical |
| 4 | sub-agent worker (or main) | Mostly mechanical text addition against a fixed fact list |
| 5 | main session | A conditional retirement gate; a delete decision should not be delegated |
| 6 | main session | Single-file contention on manifest + CHANGELOG; must be last |
| 7 | main session | Tracker writes and upstream comments are outward-facing; each needs confirmation |

Dependency order: **0 → 1 → {2, 3, 4} → 5 → 6**. Phase 7 is independent of all of them and can run
any time after Phase 5 decides `explore-deep`'s fate (item 4 depends on that outcome).

Sequential is the recommended default here: the parallel saving is roughly one phase of wall-clock
across three phases that are each judgment-heavy, and three agents cost roughly 3× the tokens of one
pass. Parallelism is offered, not assumed.

If Wave A is run in parallel, scope fences:

| Agent | ALLOWED | FORBIDDEN |
|---|---|---|
| research-worker | `plugins/discovery/skills/research/**`, `plugins/discovery/scripts/**` | `PLAN.md`, `skills/explore/**`, `skills/setup/**`, `.claude-plugin/**`, `CHANGELOG.md`, `README.md` |
| explore-worker | `plugins/discovery/skills/explore/**` | `PLAN.md`, `skills/research/**`, `skills/setup/**`, `.claude-plugin/**`, `CHANGELOG.md`, `README.md` |
| setup-worker | `plugins/discovery/skills/setup/**` | `PLAN.md`, `skills/research/**`, `skills/explore/**`, `.claude-plugin/**`, `CHANGELOG.md`, `README.md` |

`PLAN.md` is main-session-only in every shape — status-tag edits would race. Workers report back;
the main session advances the tags.

**Sequential fallback:** on any scope-fence violation, concurrent-edit race, or a worker reporting it
cannot complete, abandon the wave, `git checkout` the affected paths, and run Phases 2 → 3 → 4 in
order on the main session. No phase depends on parallelism for correctness.

### Stress-test summary

Two independent fresh-context reviewers: a plan reviewer (structural and mechanical integrity) and
an adversarial stress-test (assumptions, premise, failure scenarios).

**Plan reviewer: 3 CRITICAL, 9 IMPORTANT, 5 SUGGESTION. Every finding was re-verified against the
repo before being applied; all 17 held.** Dispositions:

| # | Finding | Disposition |
|---|---|---|
| 1 | Version target hardcoded `0.8.2 → 0.9.0`; #1260 bumps discovery to **0.8.3** | FIXED — target is now derived from the value Phase 0 records |
| 2 | Phase 6 edits the manifest description but omits the repo-root `README.md`, which carries it verbatim; `validate-plugins.sh` runs `generate-catalog.mjs --check`, so Phase 6's own gate could not pass | FIXED — root README added as REGENERATE with a catalog work item |
| 3 | `explore-deep` retirement listed 3 actions; **7 live-reference files** exist outside history, two of them doctrine docs citing it as *the* isolated-execution-tier example | FIXED — full table added; sanity grep rewritten to assert zero live references |
| 4 | `claude plugin validate` covers the manifest only and never opens `agents/*.md` | FIXED — mechanical frontmatter assertions added; the limitation is stated |
| 5 | New `.sh` files land `100644` under this worktree's `core.filemode=false`; the hygiene aggregate fails on a non-executable shebang file | FIXED — `git update-index --chmod=+x` work item plus a mode assertion |
| 6 | Phase 4's blindspot audit could not render a disposition without pre-empting Phase 5's retirement gate | FIXED — scoped to dispatch posture only; `explore-deep` refs moved to Phase 5 |
| 7 | Phases demanded zero warnings but no work item cleared them; check 3 FAILs if a description rewrite drops a tracked trigger phrase (`explore` 1, `setup` 5) | FIXED — explicit work items, with the phrase-preservation constraint stated per skill |
| 8 | Phase 3 migrates `EXPLORE.md`'s shape with no consumer pre-flight | FIXED — pre-flight added as work item 0 |
| 9 | `Delegation mechanics` does not exist in `PLUGIN-PHILOSOPHY.md`; check 21 and `skill-quality/skills/check/reference/` do not exist; the plan contradicted itself on this | FIXED — grounding table marks it unmerged/aspirational; the exemption claim is now conditional on #1096 |
| 10 | The sweep ledger lives under `.work/`, whose `.gitignore` is `*` — worktree-local and invisible to the session that inherits the sweep | FIXED — promotion required **before** the issue is filed |
| 11 | T1's two reopen conditions were prose-only, unenforced | FIXED — mechanical assertions plus an eval per skill |
| 12 | No shell linter named, though CI runs ShellCheck into the job-failing hygiene aggregate | FIXED — `shellcheck -x` added |
| 13 | Gate-table row count unscoped; breaks silently if another numbered table appears | FIXED — scoped with `awk` |
| 14 | `merge-base --is-ancestor` passes vacuously against a stale `origin/main` | FIXED — `git fetch origin main` first |
| 15 | `grep -c … returns 0` exits 1 on the passing case | FIXED — normalized to `! grep -q` |
| 16 | C1 claims the shape follows "the seven already shipped"; `plugin-quality:auditor` declares only three fields | FIXED — Phase 1 corrects the citation to the six `review/` agents |
| 17 | `check-skill.sh` check 5 resolves a backtick-cited `scripts/…` against the skill dir; check 7 only runs `<skill>/scripts/*.test.sh` | FIXED — `${CLAUDE_PLUGIN_ROOT}` citation required; CI named as the test seam |

**Adversarial stress-test: 2 CRITICAL, 6 IMPORTANT, 3 SUGGESTION — all resolved or folded, 2026-07-25.**
The stress-test independently reproduced five of the plan reviewer's findings (already fixed) and
then found eleven more, two of which were blockers. **Both blockers lived in `contract-spec.md`,
which neither review pass had examined** — the plan reviewer audited plan mechanics, and the design
gate predated both. Both are now fixed at source via dated amendments to C1, C2, and C3, which is
why this is a design correction and not only a plan edit.

The verdict on the reviewed revision was "materially closer, but not safe as written." The
dispositions below record what changed in response.

| # | Severity | Finding | Verification status |
|---|---|---|---|
| F1 | **CRITICAL** | `memory: local` silently re-enables the `Edit` tool on both agents. C1 calls `Edit` "absent by design" and Phase 1 ships that as a tool-honesty note in the agent body — so the agent would misdescribe its own tool set. The cage is C1's **sole** support for #1096's second conjunct, so T2's fork moves from *argued* to *refuted*. Every Phase 1 static check passes regardless. | Repo half **CONFIRMED**: `plugin-quality:auditor` (the one shipped agent carrying `Write`) declares **no** `memory`; all six `review/` agents declare it and are read-only. Doc half **CONFIRMED INDEPENDENTLY** against <https://code.claude.com/docs/en/sub-agents>, which states verbatim: "Read, Write, and Edit tools are automatically enabled so the subagent can manage its memory files." **F1 is fully verified — the `Edit`-absent-by-design claim in C1 is false as written.** |
| F2 | **CRITICAL** | A preload miss degrades **silently** into an undisciplined run that still writes an artifact and still self-reports `coverage: complete`. Docs say a missing or disabled listed skill is skipped with a warning to the debug log only. Nothing in C2, C4, or the coverage script observes whether the discipline actually landed — the failure mode is indistinguishable from success at every seam this plan builds, which is precisely what Decision 12's guaranteed-mandate property exists to prevent. | Reviewer-quoted from official docs; **independent confirmation owed on resume.** |
| F3 | IMPORTANT | `maxTurns` has no documented failure semantics and the plan has no partial-run recovery path. A turn-limit stop leaves a half-marked ledger, orphan sidecars, an index naming files never written, and **no C2 payload** — so the parent never learns the run died. The skill's own text is explicitly unbounded ("No limit on additional phases"), and 40 is a guess inherited from the review agents. | Owed |
| F4 | IMPORTANT | Phase 3 misses two user-interaction sites in `explore/SKILL.md`. | **CONFIRMED**: `:66` — "**ask the user before investigating**" (a hard block a non-fork subagent cannot satisfy, guarding *intentional deletions*); `:36` — recommends plan mode, whose `EnterPlanMode`/`ExitPlanMode` sit in Filter 1 of this Brief's own Constraints block |
| F5 | IMPORTANT | Phase 2 overturns only line 126; two more inline-preference statements survive and the Sanity Check would certify the contradictory result. | **CONFIRMED**: `:65` — "**Prefer direct-context web** … results land without summarization loss" (the same claim, stated more strongly, inside Phase 1); `:18` — "For context-heavy passes, use `/research-deep`… keeps main context clean" (false framing once `/research` also dispatches) |
| F6 | IMPORTANT | Subagent-incompatible skill text is enumerated **by hand**, not swept mechanically — and that method has already missed four sites across two files (F4, F5). For a HIGH-blast-radius migration whose central risk is "text authored for the invocation path now runs in a filtered subagent," a hand list is the wrong instrument; the repo scripts this class elsewhere (`check-silent-skips.sh`, `check-skill-portability.sh`). | Method finding; F4 and F5 are its evidence |
| F7 | IMPORTANT | The sibling verifier is handed a gate row it **cannot grade from the persisted artifact**. Row 7 is gradeable (C3 carries `claims[].confidence`); row 4 — "≥2 **independent** corroborators, not one upstream pool" — is not, because C3 persists only `tiers: [0,1]`, which encodes neither independence nor pool provenance. The skill's own gate demands criteria be read off an artifact, and the verifier has never seen the run. | Owed |
| F8 | IMPORTANT | The preloaded skill body instructs behavior that is false in the dispatched context. `research/SKILL.md:24` is `Research the following topic: $ARGUMENTS` and `:26` says "infer … from the current conversation context" — a non-fork subagent has no conversation context, and `$ARGUMENTS`-under-preload is documented nowhere and probed in none of Amendments 9a–9c. The preloaded text contradicts the agent body's "refuse to guess an unresolved scope." | **CONFIRMED** in both files: `research/SKILL.md:24,26` and `explore/SKILL.md:40,42` |
| F9 | SUGGESTION | `memory: local` is epistemically wrong for a research agent independent of F1: memory injects up to 200 lines of `MEMORY.md` for cross-session learning, while the research skill's core rule is that training-data recall is Tier 3 and inadmissible. An accumulating memory file is a laundering channel for exactly that. | Owed |
| F10 | SUGGESTION | Cost is asserted un-capped and never priced. The captured assumption treats *absence of a request* as a decision. With `effort: high`, `maxTurns: 40`, and "Task size does NOT reduce phase count," every `/discovery:research` — including a one-line version lookup — pays a full dispatched run. | Owed — surface as a user decision |
| F11 | SUGGESTION | Operational: on this Windows / Git Bash / D:-drive worktree, `check-skill.sh`, `git log`, and `cd`-prefixed commands repeatedly exceeded 60–300s. The per-phase gate loop is heavier than the plan reads. Sanity Checks assume `md5sum`, `jq`, `node`, `gh`, `awk` on PATH. | **CONFIRMED independently** — several verification commands in this very session timed out |

**Dispositions, 2026-07-25.** Every "Owed" status above is closed; the two doc questions were
confirmed verbatim against <https://code.claude.com/docs/en/sub-agents>.

| # | Resolution |
|---|---|
| F1 | **FIXED at source.** `memory:` dropped from both agents (C1 amendment). Doc claim confirmed verbatim. Phase 1 now asserts `! grep -q '^memory:'` **and** adds a runtime assertion that `Edit` is genuinely unavailable — prose replaced by a check. C1's tool-cage rationale rewritten to claim only what the cage buys; the bar's second conjunct is now stated as "argued, not met" wherever it appears |
| F2 | **FIXED at source.** Doc claim confirmed verbatim: a missing or disabled listed skill "logs a warning to the debug log" and nothing else. C2 gains a mandatory `preload_token` sentinel echoed from the preloaded skill; the parent treats a missing or mismatched token as a hard failure and discards the run. Phase 1 work item 0 additionally closes the `skills:` value form empirically — the only documented form is a **YAML list of bare names**, and C1's quoted scoped string was undocumented and would have failed in exactly this silent way |
| F3 | **FIXED at source.** C2 gains `status: complete \| truncated`; the agent writes `truncated` before its budget is exhausted, a returnless dispatch is treated as truncated-without-warning, and the parent discards the partial slice rather than resuming it |
| F4 | **FOLDED into Phase 3** as work item 3b. Both sites confirmed present: `:66` (ask-the-user block, unreachable) and `:36` (plan mode, Filter-1 tools). Two new Sanity Checks |
| F5 | **FOLDED into Phase 2** work item 3. All three inline-preference statements confirmed present at `:126`, `:65`, `:18`; the Sanity Check now greps for all three |
| F6 | **FOLDED into Phase 2** as work item 2 and inherited by Phase 3 — a mechanical sweep replaces hand enumeration, with the hit list recorded in this PLAN before edits begin |
| F7 | **FIXED at source.** C3's header extended with per-claim `sources[]` carrying `url`, `tier`, and `pool`, which is what makes row 4's independence judgment gradeable from the artifact by a verifier that never saw the run |
| F8 | **FOLDED into Phase 2** work item 4 and gated by Phase 1 work item 0's `$ARGUMENTS` probe. Confirmed present in both skills (`research:24,26`, `explore:40,42`) |
| F9 | **RESOLVED as a side effect of F1** — dropping `memory` removes the `MEMORY.md` Tier-3-recall laundering channel on its own merits, not only as F1's remedy |
| F10 | **OPEN — surfaced as a user decision below.** Not silently accepted |
| F11 | **ACKNOWLEDGED.** Confirmed independently — several verification commands in these sessions exceeded 60–300s. Recorded in the handoff as a tooling prerequisite and a reason to batch the per-skill gate runs |

**On the premise.** The stress-test accepts dispatch-by-default but rejects the claim that its costs
are bounded: summarization loss is bounded for *content* and unbounded for *process* (the gap lists,
tool-diversity audit, and fetch log are the gate's own inputs and nothing requires persisting them —
which is what F7 exposes); debuggability is worse than bounded, since background is the default
execution mode and a failed run's transcript is not in the conversation at all; steerability's
escape hatch is a pre-dispatch choice while the loss is mid-run at the Phase 1→2 chaining point; and
cost is an assumption rather than a decision.

**Two evidence gaps to close before Phase 1, both testable in the probe rig that produced Amendments
9a/9b:** the accepted `skills:` value form (a YAML list of bare names is the only documented example;
C1 uses a quoted plugin-scoped string) and `$ARGUMENTS`-under-preload. They feed F2 and F8.

**Stated limitation — no cross-vendor review.** The Brief's own Decision 10 distinguishes
**independence** (who renders the verdict — a dispatched fresh context buys it) from
**decorrelation** (how many distinct priors examine it — only a cross-vendor reviewer buys that).
This plan has the first and not the second. Codex was invoked twice and read nothing: the first job
orphaned, the second failed because `codex-windows-sandbox-setup.exe` is absent from the local
install. The gap is environmental, not a judgment that decorrelation was unnecessary — re-run the
cross-vendor pass if the install is repaired before execution begins.

### Open questions

- **`${user_config.…}` under preload remains INCONCLUSIVE** (Amendment 9a). Not load-bearing here —
  neither discovery skill uses the substitution — but it stays unresolved fleet-wide.
- **Preload survival across auto-compaction is untested** (Amendment 9c). Amendment 8's shape was
  chosen so it is not load-bearing; a long dispatched run that compacts is the untested case.
- **#1096's merge outcome.** If it merges with the named-agent bar unchanged *and* the third-qualifier
  proposal is rejected, C1's agents do not clear the bar and Decision 2 reopens — fallback is a
  generic fresh-context subagent with rich inline instructions, which costs Decision 12's
  guaranteed-mandate property. Not a blocker on this branch; a watch item on Phase 7 item 2.
- **B09's coverage-accounting gap** (D9) — 10 INLINE-ONLY rows sit in no normalization bucket. They
  independently applied the amended criteria, so the risk is low but the accounting is incomplete.
  Inherited by the sweep topic, not by this branch.

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Sweep promoted to its own topic `[EXEC-SHAPE]` | This PLAN covers the discovery plugin only; the 138-skill sweep becomes a separate tracked topic (Phase 7 item 5) | 66 dispatch verdicts across >30 plugins clears every sub-topic promotion trigger; the completed ledger is an input to that topic, not work this branch executes |
| Phase 0 is a merge-and-rebase gate `[EXEC-SHAPE]` | Nothing touches `plugins/discovery/` until #1260 merges | Verified live: #1260 is OPEN, MERGEABLE, 26/26 checks SUCCESS, and edits exactly the five files this work edits, adding gate criteria 9 and 10 to the table C2's split is written against |
| Named agents ship before #1096 resolves `[EXEC-SHAPE]` | Phase 1 proceeds; the bar-conformance mitigation becomes Phase 7 item 2 rather than a blocker | Verified live: #1096 is CONFLICTING and unreviewed, touches only `docs/PLUGIN-PHILOSOPHY.md` and `plugins/skill-quality/**`, and its check 21 does not exist until it merges — so nothing mechanical gates this branch |
| Hoisting resolves the nested-dispatch question `[EXEC-SHAPE]` | Both skills state that dispatch-by-default is scoped to the main-conversation boundary; a subagent invoking them runs inline | Brief Decision 10's hoisting rule is directly on point: the outer dispatch already supplied the fresh context, and the inner hop spends the inner agent's own window rather than saving anything |
| Capability detection lives in `setup check` `[EXEC-SHAPE]` | Phase 4 adds a probe to an existing check-centric skill instead of a per-invocation runtime probe | A per-spawn probe costs a turn before the agent knows it needs the data and multiplies under fan-out — the same argument Amendment 9c makes against preloading precompute |
| Version bump is 0.9.0 `[EXEC-SHAPE]` | Phase 6 sets minor, not patch | New agent components, a new mandatory phase, and a changed default posture; the plugin is pre-1.0 and this claims no stability guarantee |
| Coverage gate ships in `plugins/discovery/scripts/` `[EXEC-SHAPE]` | Phase 2 creates the plugin's first `scripts/` directory | Verified live: six plugins already ship one, and `scripts/run-plugin-tests.sh` auto-discovers `plugins/**/*.test.sh`, so the test seam exists with no CI change |
| Sequential execution recommended `[EXEC-SHAPE]` | Phases run 0 → 1 → {2,3,4} → 5 → 6 on the main session; the parallel wave is offered, not assumed | The only parallel-safe set is three judgment-heavy phases; ~3× token cost for roughly one phase of wall-clock |
| `explore-deep` retirement stays conditional `[FALLBACK — confirm or override]` | Phase 5 evaluates the gate and may decide NOT to retire, leaving the skill in place and filing the residue | Decision 14 makes retirement conditional on `explorer.md` reproducing project-memory loading and sidecar-on-collision; deleting a shipped user-invocable skill before that holds would break callers with no replacement |
| Skill-quality warnings cleared while touching `[EXEC-SHAPE]` | Phase 2/3/4 Sanity Checks demand zero warnings, not just exit 0 | Verified live: `research` currently PASSes with 2 warnings (no Gotchas surface, no `Use when:` trigger phrasing); the never-ignore-a-diagnostic rule plus the Boy Scout Rule make the touching phase own them |

### Handoff to implementation

#### User-approval gates

Implementation must stop and surface, not decide:

- **Phase 0** — merging #1260 is an outward-facing act on a shared repo. Confirm before merging.
- **Phase 5** — the `explore-deep` retirement branch (`[FALLBACK]`). Deleting a shipped
  user-invocable skill needs explicit confirmation even when the gate passes.
- **Phase 7** — every tracker write and every upstream comment. Each is outward-facing and
  permanent; search-before-create results get surfaced with the proposed text before anything is
  filed.
- **Any scope expansion** beyond the eight phases, including adopting a reviewer finding that adds
  work rather than correcting existing work.

#### Execution shape

Sequential, main-session, dependency order 0 → 1 → {2, 3, 4} → 5 → 6, with Phase 7 after Phase 5
decides `explore-deep`'s fate. The optional Wave A parallelization of Phases 2–4, its scope-fencing
tables, and the sequential fallback path are specified in "Execution shape" above. `PLAN.md` is
main-session-only in every shape.

#### Mechanical work

- **Commit boundaries** — one commit per phase, subject per `docs/conventions/commit-convention/`.
  Phase 6's manifest and CHANGELOG edits ride their own commit, last, to keep the #464 serialization
  surface as small as possible.
- **Verification checkpoints** — each phase's Sanity Check block runs before its commit; a failing
  check blocks the commit rather than deferring to CI.
- **PLAN.md status tags** — advance `[TODO]` → `[DOING]` → `[DONE]` on the main session as each
  phase completes, riding that phase's commit.
- **Divergence** — if implementation diverges from this plan, route back to `/planning:plan review`
  and append a dated scope-change note rather than pushing through.

