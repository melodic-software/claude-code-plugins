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

Harness facts verified against official docs this session
(<https://code.claude.com/docs/en/sub-agents>, <https://code.claude.com/docs/en/skills>,
<https://code.claude.com/docs/en/hooks>):

- **Subagent frontmatter fields**: `name`, `description`, `tools`, `disallowedTools`, `model`,
  `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`,
  `background`, `effort`, `isolation`, `color`, `initialPrompt`.
- **`skills:` preloads full skill content** at subagent startup. Requires the target skill to keep
  `disable-model-invocation: false` — all discovery skills qualify today. Preloading is not a
  restriction: the subagent can still invoke unlisted skills through the Skill tool.
- **Two tool filters narrow every subagent.** Filter 1 (everywhere): `Agent` (unless
  `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is set), `AskUserQuestion`, `Workflow`, `EnterPlanMode`,
  `ExitPlanMode`, `ScheduleWakeup`, `TaskOutput`, `WaitForMcpServers`, `EndConversation`. Filter 2
  (background only, and background is the default) reduces built-ins to `Read`, `Grep`, `Glob`,
  `Bash`, `PowerShell`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `TodoWrite`,
  `Skill`, `ToolSearch`, `EnterWorktree`, `ExitWorktree`, `Monitor`, `TaskStop`, `SendMessage`,
  `Artifact`, plus every MCP tool.
- **`Workflow` is unavailable in every subagent.** A workflow engine can only be dispatched from
  main context. `research-deep`'s existing inline-dispatcher requirement is therefore correct and
  load-bearing, not incidental.
- **`AskUserQuestion` is unavailable in every subagent.** `/explore`'s "surface open questions to
  the USER" contract degrades to text in the returned summary; the parent must re-surface them.
- **`TaskCreate`/`TaskGet`/`TaskList`/`TaskUpdate` do not survive the background filter**;
  `TodoWrite` does. Any coverage ledger a dispatched agent maintains must be a file on disk.
- **A `context: fork` skill is a regular agent type**, not a conversation fork. It receives the
  narrow background tool set unless it sets `background: false`, which makes it block the invoking
  turn. Only the `fork` subagent type (`/subtask`, `CLAUDE_CODE_FORK_SUBAGENT`) inherits the
  parent's exact tool pool.
- **Plugin-shipped agents ignore the `hooks`, `mcpServers`, and `permissionMode` frontmatter
  fields.** This costs less than it appears: `settings.json` hooks still fire inside subagent tool
  calls (the hook payload carries `agent_id`/`agent_type` precisely to distinguish them), subagents
  inherit the main conversation's MCP tools, and permission mode is inherited from the parent —
  a parent in `auto` mode yields a subagent in `auto` mode. The single real loss is the ability to
  give one agent a private inline MCP server the parent does not carry.
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

### Amendments pending confirmation (from the marketplace sweep)

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

- **Do the `-deep` variants collapse into their parents once the parents dispatch by default, or do
  the parents become dispatchers and the `-deep` skills retire?** — arbiter: USER-RESERVED. Resolution
  changes the acceptance criteria and the public skill surface.
- **Does dispatch-by-default apply when the invoking context is itself a subagent** (avoiding a
  needless second hop at spawn depth > 1)? — arbiter: `/planning:plan`.
- **Which of the 138 non-setup marketplace skills adopt the same dispatch posture** — being
  determined by the audit sweep recorded in
  `.work/discovery-subagent-dispatch/skill-dispatch-audit-checklist.md`.

## Plan

_Not yet written. `/planning:plan` fills this section._
