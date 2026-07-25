# fact-check-skill

## Brief

### TLDR

An on-demand fresh-eyes claim-audit capability was proposed as a new `/fact-check` skill. Investigation found the capability already ships, the proposed component has no buildable trigger, and the org's own enforceability convention argues against automating the judgment half yet. The work that survives is: closing a real gap in the quick research tier, naming an axis the plugin does not model, building only the deterministic guards that clear the tier honestly, deferring the rest with a written trigger, routing two gaps upstream, and fixing four defects found during the investigation.

### Goal

Close the verification gaps that are real, in the components that already own them, without adding a parallel entry point to territory three skills already cover.

### What was rejected, and why

**A new `/fact-check` skill.** `plugins/discipline/skills/do-your-research/SKILL.md` already declares the triggers `'fact-check'`, `'fact check this'`, `'make sure that's right'` and is model-invocable. `plugins/discipline/skills/do-your-research-deep/SKILL.md` already enumerates a typed full inventory of session claims, fans blind fresh-context subagents out in throttled waves, and reports a per-item ledger carrying verdict, source, source tier, consensus count, and recency, at a configurable depth. A fourth entry point is the silent second way `/discipline:reuse-or-replace` exists to catch.

**A reusable verifier agent component.** Retracted on two independent grounds.

*Trigger.* Claude Code ships `type: "agent"` hooks (verified <https://code.claude.com/docs/en/hooks>, 2026-07-24), but their worker is defined inline via `prompt`; the documented field set is `type`, `prompt`, `model`, `timeout`, `if`, `statusMessage`, and **none references a named subagent**. A shipped agent component would have no hook trigger. Agent hooks are additionally marked experimental, which `docs/PLUGIN-PHILOSOPHY.md`'s native-first adoption gate (criterion 2) routes to Wait.

*Doctrine.* Open PR #1096 authors a **named-agent bar** into `docs/PLUGIN-PHILOSOPHY.md` "Delegation mechanics": the default worker is a generic fresh-context subagent carrying rich inline instructions, and a named agent is earned only when *the same worker with the same instructions dispatches from multiple sites AND a model pin or an enforced tool restriction is load-bearing*. This capability meets neither half. It also retracts an earlier claim made during this investigation — that the described-in-prose dispatch was a missing "executable component". Under the incoming doctrine, inline-instruction dispatch **is** the sanctioned default form, not a gap.

**A literal `/fact-check` command name.** No alias or alternate-name frontmatter field exists (<https://code.claude.com/docs/en/skills>, 2026-07-24); `name` defaults to the directory name. A literal `/fact-check` would require a directory named that plus a naming-exception entry, for zero capability gain.

### Scope

1. **Consensus contract in the quick tier.** `plugins/discipline/skills/do-your-research/SKILL.md` asks for "an authoritative source"; the stated bar is consensus across official docs, articles, and recognized experts. Add the source-tier / consensus / recency contract by pointing at `plugins/discovery/skills/research/context/discipline.md`. Never copy it — `/discipline:point-dont-copy` pins the duplication threshold at two.

2. **Name the preventive/detective axis.** The plugin splits on **depth** (inline vs fan-out); the missing distinction is **direction** — grounding work before assertion vs verifying claims already asserted. Orthogonal axes; only depth is modeled. Make the direction distinction explicit in the discipline text and keep depth as the skill boundary.

3. **Class B guards in `guardrails`.** Each classified honestly against `standards` `conventions/engineering/enforceability-tiers.md`, because the tier decides what the guard is permitted to be:
   - **Deterministic** — nonexistent repo-relative path asserted in written content. Oracle is a filesystem test; exact.
   - **Deterministic** — version string disagreeing with the owning manifest. Oracle is a manifest comparison; exact.
   - **Detect-then-judge** — nonexistent `/plugin:skill` or agent reference written into a doc. *Reclassified.* Globbing the plugins tree is exact only inside this repo, and `docs/PLUGIN-PHILOSOPHY.md` requires repo-agnostic plugins; in a consumer repo the reference may target a plugin from another marketplace or one not installed. The convention routes detect-then-judge to advisory-plus-human-verdict and never auto-fix — which all three guards already are — so the guard survives, but it must be declared detect-then-judge, never sold as deterministic.

4. **Defer the `SubagentStop` verifier, with a written trigger.** Correct target — `plugins/discovery/skills/research/SKILL.md` already declares subagent returns Tier 3 synthesis, not corroborators, and nothing enforces it. Zero plugins currently use `Stop` or `SubagentStop`. Revisit trigger: agent hooks leave experimental status, OR a named-subagent reference field appears in the prompt/agent hook contract. Record it in the native form PR #1096 introduces — the exemption directive `<!-- fresh-eyes-exempt: deferred -- <reason> -->`, whose closed class set already includes `deferred` — rather than inventing a parallel deferral notation.

5. **Route two gaps upstream to `melodic-software/standards`.** No ranked source-authority or citation-tier scale exists anywhere in `conventions/`. And `conventions/review/ai-generated-code.md` is scoped to diff-time review of AI-authored code; no convention covers verifying claims made during a session. Draft and offer; never open without explicit opt-in.

6. **Defects found during investigation** (separate from the capability work):
   - `plugins/discovery` gates skill-level `context: fork` behind `CLAUDE_CODE_FORK_SUBAGENT`. Wrong mechanism, inverted effect, and the documented fallback branch is unreachable. Loci: `skills/explore-deep/SKILL.md:3`, `README.md:12`, `skills/explore/SKILL.md:24`, `skills/explore-deep/evals/evals.json:16-26`.
   - `plugins/discovery/skills/explore-deep/SKILL.md:24` claims parent-full-toolset inheritance; a backgrounded fork runs with the narrower background tool set.
   - `docs/PLUGIN-PHILOSOPHY.md:128` hooks stance describes command-hook form only; the live page documents five hook types and 30 events.
   - `docs/topics/plugin-audit-port/PLAN.md:78,457` and `design/design-resolution.md:25` reject `context: fork` because it "inherits the degraded history". A forked skill has no history. Decision stands on the correct rationale stated elsewhere in the same PLAN; only the reason is wrong.

### Constraints

- **Fresh-docs mandate.** Repo `CLAUDE.md` requires a WebFetch of the relevant official page, cited, before any change here. `docs/MIGRATION-PLAYBOOK.md:576-580` repeats it as step 1 of the per-component migration gate, whose header is per-component: "For each skill/hook/agent being migrated."
- **Plugin-acceptance security review** (`docs/MIGRATION-PLAYBOOK.md:645-647`) applies to every new hook as a code-execution trust surface (criterion 1), and `:375-379` re-triggers it on a version bump that adds a trust surface.
- **Per-hook kill switch mandatory** — a `userConfig` boolean defaulting `true`, read through the `CLAUDE_PLUGIN_OPTION_*` mirror. Plus `statusMessage` on the handler, telemetry emission, and a co-located `*.test.sh` with MUST-fire and MUST-stay-quiet cases.
- **`lib/hook-utils.sh` is the single source of truth**; plugin copies are synced via `scripts/sync-hook-utils.sh` and CI rejects drift. Never edit a copy.
- **Enforceability tier governs what may be automated.** `standards` `conventions/engineering/enforceability-tiers.md`: deterministic goes to a hook; detect-then-judge stays advisory with a human verdict and is never auto-fix; reasoning-only stays in prose. Classify first, justify automation second, default "not yet".
- **Shared-policy changes go upstream**, never patched into a downstream copy.
- **Branching.** PRs required, squash merge, branch `<type>/<description>`, PR title in Conventional Commits (enforced by `.github/workflows/pr-title.yml`).
- **Point, don't copy** binds every artifact produced here, including this Brief.
- **Open PR #1096 is an upstream dependency.** It authors "Delegation mechanics" into `docs/PLUGIN-PHILOSOPHY.md` (dispatch ladder, named-agent bar, inline-template conventions, model tiers, declared patterns) and adds conformance check 21 to `skill-quality`. Any edit to a `discipline` skill's discipline text lands under that check: a same-context judgment step must match the POSIX ERE `fresh[- ]context` on a line that also names the worker or dispatch, or carry an exemption directive from the closed class set `deterministic-gate | external-input | deferred`. Its philosophy hunks are at the convention registry and the Fresh-eyes section; the stale hooks stance at `:128` is untouched by it, so the two edits do not overlap textually but do share the file.

### Acceptance criteria

- `do-your-research` states the source-tier / consensus / recency contract by reference to the discovery discipline file, with no copied tier table.
- The preventive/detective distinction is stated in the discipline text, and the depth-based skill boundary is unchanged.
- Each new guard is deterministic (mechanical oracle, no judgment), advisory (exit 0), independently toggleable, telemetry-emitting, and covered by a test asserting both firing and silence.
- The deferred `SubagentStop` verifier is recorded with its revisit trigger and its sources, not silently dropped.
- Both standards gaps are drafted and offered upstream; neither is patched downstream.
- Each defect is corrected at every locus enumerated above, with the unreachable eval case removed rather than adjusted.
- No new skill, no new agent component, and no new entry point in fact-check territory.

### Captured assumptions

- Agent hooks remain experimental as of 2026-07-24; the deferral is re-evaluated when that changes.
- The three deterministic guards fire rarely enough to justify their maintenance cost. Unmeasured — `enforceability-tiers.md` says the worth-mechanizing question is separate from the tier question, and its default is "not yet". If any guard proves noisy, it retires rather than gets tuned indefinitely.
- `docs/topics/fresh-eyes-checkpoint-audit/design/` was not read. Prior program #304 covers adjacent ground and may already constrain some of this.

### Out of scope

- Class A skill-bypass nudges ("this action should route through that skill"). A real line of work, deliberately not sharing a component with Class B hallucination guards.
- A `Stop` end-of-turn claim sweep. No mechanical oracle, fires every turn, and fails the user-set criterion that a trigger forcing an agent must be locked in and non-fuzzy.
- Link and in-repo anchor resolution — already covered by `lychee.toml` (`include_fragments = "full"`).
- Hallucinated CLI flags — owned by `guardrails` `cli-flag-verify`.
- Retuning or expanding `do-your-research-deep`'s existing fan-out.

### Deferred questions

- **PR decomposition and sequencing across the two repos.** — `USER-RESERVED`: changes what lands, in what order, and what can merge independently.
- **Whether the deferred `SubagentStop` verifier is recorded as a tracked work item or a doc-only entry with its trigger.** — `USER-RESERVED`: determines whether it resurfaces automatically.
- **Whether adding an agent to an existing plugin re-triggers the plugin-acceptance security review.** `docs/MIGRATION-PLAYBOOK.md` keys the review on trust surfaces and does not enumerate agents as one; the document resolves this neither way. — `USER-RESERVED`: a standards-ownership question, and moot for this Brief since no agent is being added.
- **Whether the stale hooks stance at `docs/PLUGIN-PHILOSOPHY.md:128` is corrected here or routed to a fleet-audit cycle.** — `/planning:plan` may decide.

## Plan

Executed 2026-07-24/25. Six tracked items; three landed or built, two blocked
externally, one held behind the user's cross-repo opt-in gate.

### Disposition

| # | Issue | Outcome |
|---|---|---|
| 1 | #1267 | **MERGED** — PR #1273, squash. Dropped the `CLAUDE_CODE_FORK_SUBAGENT` gate from `plugins/discovery`; deleted the unreachable fallback eval case; version-floored the tool-set claim at ≥2.1.218 and replaced a hand-copied enumeration with a pointer |
| 2 | #1268 | PR #1274 open, not mergeable — two cross-vendor findings outstanding, one of them a defect this program introduced (see below) |
| 3 | #1269 | **BLOCKED** on #1096, which is `DIRTY` (conflicted with main, unrebased) |
| 4 | #1270 | **PR #1284 OPEN.** Two guards shipped, scope amended from three. Opened deliberately WITHOUT a completed independent review: a subagent security review was dispatched twice and never reported, and a real-world false-positive measurement was dispatched then stopped at the session pause. The PR body says so and asks reviewers not to merge on the author's say-so. Opening engages the repo's own `security-review` / `review` / cross-vendor checks rather than bypassing them |
| 5 | standards#269 | Two conventions drafted and committed locally. **Never pushed** — the user reserved the cross-repo gate |
| 6 | #1271 | **UNBLOCKED, unstarted** — the `re-anchor` → `discipline` rename merged as PR #1276 (branch `refactor/rename-re-anchor-to-discipline`; the commit this program tracked, `33be004a`, was rebased away and exists on no branch). Body rewritten, `status: ready` + `agent-ready` added. Its measured figures are stale by construction — re-measure at authoring time, as its own acceptance criteria already require |

### Deferred questions, as resolved

- **PR decomposition and sequencing** — `USER-RESERVED`, answered: all six issues
  opened at once so the overlap with a concurrent session became visible before
  either side wrote code; then PRs 1 and 2 first, PR 4 after, PRs 3 and 6 held.
  The original sequencing assumed PR 4 should wait for the guardrails queue; that
  was **overturned on evidence** — #1097, #1085 and #853 are all `DIRTY` and
  unchanged since 2026-07-23, so waiting bought nothing.
- **The deferred `SubagentStop` verifier** — `USER-RESERVED`, unresolved. Not
  filed. It survives only in this Brief, so it does not resurface automatically.
- **Whether adding an agent re-triggers the plugin-acceptance security review** —
  moot as predicted; no agent was added. PR 4 ships two hooks, which *are* an
  enumerated trust surface, and is gated on a security review accordingly.
- **The stale hooks stance at `PLUGIN-PHILOSOPHY.md:128`** — routed out, not fixed
  here. #1096 is actively rewriting that file and an edit from another branch
  would collide.

### Findings this program produced beyond its own scope

- **#1270's third guard has no buildable trigger.** A version-versus-manifest
  guard was scoped, then dropped on enumeration: its only in-repo shape is already
  covered by `check-changelog-parity.sh --check-bump`, and the residual prose
  surface is historical, minimum-floor, and planned claims a manifest-compare
  oracle reads wrong. The checked and unchecked sets are both recorded on #1270.
- **#448 reopened.** The C1 slow-sink flake reproduces on clean `origin/main`. Its
  own recommended fix was never applied — what shipped derives the threshold as
  half the sink sleep, so widening the sleep widens the threshold and the margin
  ratio cannot improve. The same construction is duplicated in `markdown-format`
  via #1209.
- **A shipped skill still carries the false fork claim.**
  `plugins/plugin-quality/skills/audit/SKILL.md` tells every audit invocation that
  a fork "would inherit this session's degraded history." Found by cross-vendor
  review of PR #1274 — this program had corrected the design doc and left the
  user-facing code wrong.
- **"A forked skill is anonymous" is false.** The skills frontmatter documents an
  `agent` field selecting the subagent type when `context: fork` is set, and
  `plugins/discovery/skills/explore-deep/SKILL.md` proves the pairing. PR #1274
  replaced one unsupported rationale with another and is being corrected.
- **The contract-slice prune gate does not exist.** This convention's step 5
  specifies a required check that the net PR diff contains no path under
  `docs/topics/**`. No such gate is wired: `docs/topics/` appears in
  `scripts/docs-only-paths.txt` as a docs-only *allowlist* entry only. Evidence
  that it is unenforced is that `docs/topics/plugin-audit-port/` is on `main` now.
  Not filed.

### Disposition of this file

Contract tier — committed on a task branch only, pruned before merge, per
`docs/conventions/topic-docs/README.md`. It was never committed. Its durable
outcomes have graduated to the tracker (#1267-#1271, standards#269, #448) and to
PR bodies, which is what the lifecycle asks for. The two items with no tracked
home are the `SubagentStop` verifier and the unwired prune gate; both are recorded
above and nowhere else.
