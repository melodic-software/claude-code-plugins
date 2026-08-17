---
type: handoff
session_id: bd8a50ac-6403-5d4b-8d09-94a164d512d4
previous_handoff: none
branch: claude/context-window-setup-xnwt0w
written: 2026-08-17T05:56:10Z
topic: context-budget
note: >
  Committed to the contract tier deliberately: this handoff was written in a Claude Code cloud
  session whose container is reclaimed, so the default .work/handoffs/ location would not survive
  to the resuming session. A mirror copy exists at .work/handoffs/ for the standard local contract.
---

# Handoff — context-budget (build phases)

## Original goal

- **Goal (verbatim, 2026-08-17):** "I want to see if these are candidates to put into a plugin or
  just a reasonable prompt, I guess, because this is definitely tied into the unhobbling piece, but
  it's more on the context side."
- **Amended:**
  - amended 2026-08-17: "It'd be nice to have a skill that someone could run that walks them
    through that, lists out all of the tools, gives them the explanations, and says, 'Hey, which of
    these would you like to disable or enable based off existing permissions? What settings would
    you like to flag?'"
  - amended 2026-08-17: "we definitely want to be basing ours off of official research, the latest,
    greatest information. Obviously, we cite those things, and we don't copy those details. We cite
    the actual source documents and those because this stuff's probably going to change, so I don't
    want to bake in exact criteria."
- **Next action serves it by:** building the measurement engine (Phase 2) that the guided
  disable/enable walkthrough needs before it can tell the user what anything costs.

## Resumption brief

Written 2026-08-17 against `claude/context-window-setup-xnwt0w` (research, brief, Phase 0 probes,
and Phase 1 corrections all committed and pushed; this handoff is the branch tip). Design is fully
locked — every interview question answered or explicitly deferred-with-owner. The single next
action: start Phase 2, the measurement engine, per `docs/topics/context-budget/PLAN.md` (governing
section: Remaining actions, in order). Before changing anything, read Constraints that must hold.

## Completion criteria

Why: a `context-budget` plugin that makes a session's fixed startup payload measurable per item and
trims it only on honest, evidenced grounds. From PLAN.md acceptance criteria; all unmet — the build
has not started:

- [ ] Ranked per-item attribution for the built-in tool pool exists, derived by measurement, with
  the measured CLI version stamped on the report (test: run `/context-budget:audit` and see a
  ranked table with version)
- [ ] Every lever presented carries its honesty category and official citation (test: report
  review; no uncategorised lever)
- [ ] Baseline/compare ledger in `${CLAUDE_PLUGIN_DATA}` records measured before/after deltas
  (test: toggle a lever, re-run, ledger row shows both numbers)
- [ ] No skill content contains a transcribed token value, key inventory, or threshold (test: grep
  the shipped skill for figures from FINDINGS.md — zero hits)
- [ ] Degrades with a clear message when headless `/context`/SDK is unavailable (test: run with the
  SDK absent)
- [ ] `/doctor` territory routed to, never reimplemented (test: report cites `/doctor` for
  usage-based removal; no usage-scanning code in the plugin)

### Process milestones

- [x] Nine research runs complete, gates exit 0 (advances: every criterion; corpus in `research/`)
- [x] Phase 0 blockers resolved (advances: engine criterion) — verified this session
- [x] Phase 1 repo corrections landed (independent of the plugin)

## Constraints that must hold

- **Cite, never transcribe.** No token figure, key list, bundled-skill inventory, or threshold
  ships as skill content — violation makes the skill lie the moment upstream drifts. The full rule:
  `docs/topics/context-budget/research/DESIGN-PRINCIPLES.md`.
- **A lever whose honesty category cannot be determined is not offered.** Violation = the wizard
  recommends actions that do nothing (the course's own failure mode).
- **Settings writes go through a PreToolUse hook returning `permissionDecision: "ask"`** —
  documented as a checkpoint, not a guarantee. Violation = auto mode silently rewrites configs.
- **`~/.claude/settings.json` is never written, only printed.** "Never auto-approved" for protected
  paths means "not by a settings rule" — the auto-mode classifier can still approve with no human.
- **Persistent config emits `permissions.deny`, never a `disallowedTools` settings key** — the
  latter does not exist in settings.json and is silently ignored.
- **Pin and report the measured binary.** This machine carries two CLI versions with different
  `/context` category lists; unpinned measurement silently mixes schemas.
- **`System tools` is only comparable between runs with identical skill listings** — it has
  skill-frontmatter tokens subtracted. Violation = phantom deltas (this bit us once already).
- Repo conventions bind: naming grammar (`docs/PLUGIN-PHILOSOPHY.md` — verb contracts, no
  frontmatter `name`), plugin isolation (no sibling imports), changelog + version bump on every
  plugin change, guardrails hooks (no heredoc/inline-python file writes — use Write/Edit; force
  pushes need `--force-with-lease=<ref>:<sha>` with a literal SHA; no machine-specific paths in
  committed files).
- No compaction signal was present when this section closed; the visible conversation was re-scanned
  directly.

## Environment to re-establish

- **Cloud session, fresh container.** The repo clones to the session's project root (render it
  `<repo-root>` below); cloud bootstrap installs the 65 marketplace plugins at SessionStart.
  First-turn slash commands of just-installed plugins can return "Unknown command" (harness
  residual #2733) — follow the skill's SKILL.md from the working tree, as this session did
  throughout.
- **Branch:** `git fetch origin claude/context-window-setup-xnwt0w && git checkout
  claude/context-window-setup-xnwt0w` — confirm `git log --oneline -1` shows the handoff commit.
- **Task list:** none was in use; nothing to recreate.
- **SDK probe scaffolding** (optional, for Phase 2): `npm pack @anthropic-ai/claude-agent-sdk` into
  a scratch dir; probe pattern in Findings below. The native binary lives at
  `<repo-root>/node_modules/@anthropic-ai/claude-code-linux-x64/claude`.

## Side effects already applied

- Issues **#2895** (preload sentinel unsound, follow-up to #2338) and **#2896** (verb-contract
  mismatch check) are FILED — do not refile.
- `claude-config` is bumped to **0.38.7** with its CHANGELOG entry for the unhobble gotcha fix — do
  not re-bump for that change.
- The five Phase 1 corrections are LANDED (checks-and-sweep, coverage-matrix S7,
  permission-rule-hygiene 1.3, unhobble SKILL.md + eval 8, `_typos.toml` research exclusion) — do
  not re-apply.
- No PR is open for this branch — do not open one unless the user asks.
- The `.work/startup-context-baseline/` memory slice was PROMOTED to
  `docs/topics/context-budget/research/` — the committed copy is canonical now; do not re-promote
  or re-run the nine research dispatches.

## File roles in this work

- `docs/topics/context-budget/PLAN.md` — specification to obey; Brief locked, Phases 0–1 marked
  resolved, Phases 2–6 remaining.
- `docs/topics/context-budget/FINDINGS.md` — evidence record; cite it, never copy its numbers into
  skill content.
- `docs/topics/context-budget/research/` — reference for understanding; per-claim citations for
  Phase 3's lever catalogue. `MEASUREMENTS.md` (measured series), `DESIGN-PRINCIPLES.md` (binding),
  `source-levers.md` (L1–L12 completeness check), `INDEX.md` (run statuses),
  `interview-checklist.md` (decision ledger, gate-clean).
- `plugins/context-budget/` — still to create; nothing exists yet.
- `plugins/claude-config/` — modified and committed (0.38.7); no further work owed.
- `.claude-plugin/marketplace.json`, `docs/CATALOG.md` — still to modify when the new plugin lands
  (registration + catalogue row).

## Decisions already settled

All recorded with rationale in the interview ledger
(`docs/topics/context-budget/research/interview-checklist.md`, register gate exit 0) and PLAN.md.
Headlines: new `context-budget` plugin with single skill `/context-budget:audit` (audit = default
read-only action, fix path behind explicit override per the repo's verb contract); read all scopes,
write posture split by scope; SDK-primary hybrid measurement engine; measure-toggle-remeasure
ablation loop with ledger; `/doctor` routed to, never wrapped; lever catalogue as data rows. The
four operator-reserved decisions were answered 2026-08-17: declare the narrower (local-CLI) scope
honestly on cloud/web; measure-and-report rather than model-branched advice;
net-negative levers disclose-only; wizard UX deferred to Phase 5. Do not relitigate any of these.

## Approaches tried and abandoned

- **Two-skill split (audit + separate trim)** — rejected by the operator and by doctrine: the verb
  contract already permits mutation behind an explicit override; `claude-config:audit --fix` is the
  shipped precedent.
- **`AskUserQuestion` as the mutation gate** — falsified: no permission needed, denied in
  `dontAsk`, hook-answerable, auto-closable. The PreToolUse `ask` hook is the real gate.
- **Markdown-parser-primary measurement** — demoted to fallback once `getContextUsage()` was probed
  working.
- **The course's request logger as a component** — rejected: MITMs provider traffic, writes full
  system prompts to disk; fails the marketplace's deny-by-default egress stance. Documented as an
  optional operator-run method only.
- **`claude --safe-mode` / clean `CLAUDE_CONFIG_DIR` as clean-room baselines** — measured false;
  both leave all bundled skills loaded, and safe mode shifts the `Skills`/`System tools` split.

## Findings that cost effort to discover

The evidence record is `docs/topics/context-budget/FINDINGS.md` — read it in full before building;
it is the distillation of ~1.6M tokens of research. The ones a builder trips on fastest:

- **Rule shape decides schema removal.** Bare-name deny removes the tool definition from the
  request (measured: `Workflow` −7.9k, `Artifact` −4.4k, exactly additive); scoped rules remove
  nothing. Deferral does NOT shrink the request.
- **The skill listing is budget-capped (~1%)** — disabling skills or plugins saves zero listing
  tokens while over the cap (measured: 45 of 65 plugins disabled → no change). Agents are uncapped
  and scale. `skillListingBudgetFraction` / `skillListingMaxDescChars` are the documented knobs.
- **`getContextUsage()` (Agent SDK ≥0.3.233) returns exact integers matching the CLI**, but its
  `systemTools` / `deferredBuiltinTools` / `systemPromptSections` fields arrive unpopulated — same
  dead path as the renderer. Probe pattern: `query({prompt, options:{maxTurns:1,
  pathToClaudeCodeExecutable: <native binary>}})`, then `getContextUsage()` after the `init`
  message. A/B differencing is the only per-built-in-tool route.
- **`skillOverrides` is documented** (settings ref + skills page) and reaches bundled +
  claude.ai-synced skills, but NOT plugin skills. The earlier "binary-only" claim was a
  WebFetch-truncation artifact — a recurring trap: never conclude "key absent from docs" from a
  WebFetch summary of a 300KB+ page; fetch raw markdown.
- **`Agent(<name>)` deny does not remove an agent's description from the payload** (measured
  against a control) — plugin-level disable is the working agent lever.
- **`CLAUDE_CODE_SIMPLE` (= `--bare`) and `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` are two different env
  vars** (binary env map); the latter is the lean-prompt switch and is a measured no-op on models
  where lean is already default.
- **Parse traps** (if the markdown fallback is ever built): skill token cells format as `~<int>` or
  literal `< 20`; unredirected stdin prepends a warning line that breaks `JSON.parse`; format
  changed materially at v2.0.74/2.1.0/2.1.129/2.1.139/2.1.216.
- `www.aihero.dev` and `claude.com` are egress-blocked from cloud containers; the Anthropic 80%
  claim cites cleaner as changelog v2.1.154.

## Remaining actions, in order

Per PLAN.md phases; each lands as commits on this branch with the repo's gates run:

1. **Phase 2 — measurement engine.** Scaffold `plugins/context-budget/` (manifest, README,
   CHANGELOG, `skills/audit/`); build the SDK-primary meter + A/B differencing driver + ledger
   format + degradation path. Register in `.claude-plugin/marketplace.json`; add the
   `docs/CATALOG.md` row.
2. **Phase 3 — lever catalogue** as data rows (detection, honesty category, citation, scope,
   emitted config), sourced from `research/` sidecars.
3. **Phase 4 — the report** (default action, read-only, smart-zone framing).
4. **Phase 5 — guided fix path** (walkthrough behind explicit override; PreToolUse `ask` hook;
   scope-split write posture; ledger entries).
5. **Phase 6 — evals + acceptance gates** (`skill-quality:check`, `plugin-quality:audit`,
   changelog parity).
6. Optional at any point: dispatch fresh-context verifiers for the single-source claims flagged
   "Unresolved" in FINDINGS.md (§12).

## Open questions to investigate

- Does a PreToolUse `ask` survive `bypassPermissions`? Documented silence; probe empirically
  (precedent: `claude-config:audit-permission-state --oracle`). Affects only how the gate is
  worded, not whether it ships.
- Are HTTP/Streamable-HTTP MCP tools actually deferred at current versions
  (anthropics/claude-code#40314 was closed not-planned)? Phase 2 should measure deferral per
  session rather than trust the default — already a named assumption.
- Interactive-session deferral eligibility (`tengu_non_deferrable_builtins` is server-side) —
  measurable only by differencing an interactive session.
- Does the API bill for deferred-but-never-loaded tool definitions? Two `count_tokens` calls
  settle it; decides how the report words the deferred bucket's cost.

## Blockers needing an outside decision

None. Every reserved decision was answered by the operator on 2026-08-17 (recorded in Decisions
already settled).

## Suggested skills

- `/planning:plan` if Phase 2 wants a finer-grained implementation plan before code; otherwise
  build directly against PLAN.md.
- `/skill-quality:check` and `/plugin-quality:audit` before each phase's commit.
- `/evals:design` for Phase 6.
- `/verification:confirm` after each phase lands.
- `/discovery:research` only for the four open questions above — the corpus already covers
  everything else; do not re-research settled ground.
