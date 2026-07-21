# claude-config-audit-instructions

## Brief

### TLDR

- New skill `/claude-config:audit-instructions` (issue #800): read-only audit sweeping the
  locally-owned Claude Code instruction surfaces — user + project CLAUDE.md, skill bodies +
  context files, agent definitions, `.claude/rules/**/*.md`, prompt-type hooks, output styles —
  proposing removals/rewrites of instructions current models no longer need.
- Check catalog seeded from the 11 sourced seeds in knowledge-corpus
  `.work/youtube-watch/how-i-plan-build-and-run-loops-with-clau-aVO6E181cNU/research/findings/context-trimming.md`,
  each check cited to its official source.
- Findings tiered by evidence class: **mechanical** (pattern-detectable: bare prohibitions
  without rationale, inferable/redundant content, misplaced only-sometimes-relevant content,
  rule-to-hook candidates, show-your-thinking instructions, non-steering example blocks) vs
  **behavioral** (pruning-bar counterfactuals — "would removing this cause mistakes?" — whose
  ground truth is observed behavior, not static analysis).
- Execution shape: per-surface subagent lanes sharing one check catalog; large lanes (skills)
  fan out further. Every removal proposal passes an adversarial "would removing this cause
  mistakes?" verify pass before reaching the human-gated diff.
- Output: findings report + proposed diffs, human-gated, never auto-applied. Upstream-owned
  findings route out (standards-managed materializations → melodic-software/standards per
  sync-manifest; marketplace plugin content → claude-code-plugins issues), never edited in place.

### Goal

A claude-config audit-family skill that, on demand or after a model-generation upgrade, tells the
operator exactly which instruction lines across their locally-owned Claude Code configuration are
no longer earning their context cost — with each finding cited to current official prompting
doctrine, classified by how confident the evidence can be, and packaged as a proposed diff the
human approves or rejects — so instruction surfaces shrink as models improve instead of accreting
prior-model-era scar tissue.

### Constraints

- Name locked: `audit-instructions` (this session, via naming pipeline). Family grammar:
  `audit` = read-only findings report; mutation never on bare invocation
  (`docs/PLUGIN-PHILOSOPHY.md` naming table).
- Human-gated output only: findings report + proposed diffs; never auto-applies. No `--fix`
  in scope for this issue.
- Scope bound (locked in issue #800 follow-up): audit only locally-owned surfaces (user
  CLAUDE.md, `~/.claude/rules`, project `.claude/`). Marketplace plugin cache content is
  upstream-owned — findings there route to claude-code-plugins issues, never local cache edits.
- Cross-repo routing: findings inside standards-managed materializations route upstream to
  melodic-software/standards per `standards/distribution/sync-manifest.yml` ownership.
- Composes by pointer, distinct intents (locked): `skill-quality:check` (structural lint),
  `docs-hygiene:compress` (token brevity), `claude-config:audit` (config-file mechanics —
  settings.json, .mcp.json, hooks wiring). This skill owns instruction *content* vs current
  model capability; no overlap restated.
- Check catalog is cited doctrine, not copied prose: each check carries its source URL
  (code.claude.com best-practices, platform.claude.com Fable 5 + prompting best-practices pages)
  with verified date and a recheck trigger — model-specific pages get superseded per release.
- Repo obligations: plugin version bump + CHANGELOG entry, skill-quality:check pass,
  validate-plugin-contracts gate, commit via `git commit -F - --cleanup=verbatim`.

### Acceptance criteria

1. `plugins/claude-config/skills/audit-instructions/` ships; frontmatter description carries the
   discovery triggers (post-model-upgrade, "prune my CLAUDE.md", "are my instructions holding
   the model back") and the distinguishing object in its first clause.
2. Check catalog covers all 11 seeds (pinned in the plan appendix); every check cites its
   official source and declares its surface applicability per the claude-memory partition
   (hygiene checks I1–I5 route to claude-memory:audit on memory-layer surfaces when that
   plugin is installed).
3. Findings report tiers every finding mechanical vs behavioral; every removal/rewrite proposal
   carries the adversarial verify verdict before it is surfaced.
4. Bare invocation is read-only end-to-end; diffs are proposed artifacts, never applied.
5. Scope guard enforced in skill flow: plugin-cache and standards-managed paths are excluded
   from the editable set and their findings emitted as routing recommendations instead.
6. Per-surface lane execution shape (subagent per surface, shared catalog, fan-out for skills)
   is the documented default flow.
7. skill-quality:check passes for the new skill; claude-config version bumped with CHANGELOG
   entry; PR closes #800.

### Captured assumptions

- The 11-seed catalog reflects official doctrine as of 2026-07-21, re-verified against live
  docs this session (research pass) — revisit on next frontier model release or when either
  prompting page changes (recheck trigger recorded in the skill's sources).
- Attribution (research-verified 2026-07-21): the pruning bar "Would removing this cause
  Claude to make mistakes?" and the delete-and-watch loop ("test changes by observing whether
  Claude's behavior actually shifts") are Anthropic best-practices doctrine. Boris Cherny's
  documented practice is the additive write-it-down loop plus `/checkup` (dedup, split big
  CLAUDE.md into nested files + skills); a periodic full-delete ritual is unconfirmed in any
  primary source — the skill must not cite it as his.
- Bare-prohibition remediation (research-verified): the docs' primary target form is positive
  reframing ("tell Claude what to do instead of what not to do"); adding rationale is
  separately supported ("give the reason, not only the request"). The check offers positive
  rewrite first, prohibition-plus-rationale as the fallback where a genuine hard "never"
  survives.
- Examples remain officially recommended (3–5, format/tone/structure steering) for all current
  models including Fable-class — the audit flags example blocks only when they are behavioral
  scaffolding pinning the model's approach, never format steering; revisit if the
  best-practices page drops the recommendation.
- Behavioral-tier caution is itself sourced: Anthropic's postmortem on the ~80% system-prompt
  cut (InfoQ/VentureBeat coverage) records that narrow evals missed a ~3% regression —
  grounding why behavioral findings ship as proposals with the delete-and-watch loop, never
  as confident removals.

### Out-of-scope

- #798 (`library_dir` indirection) — separate item, not folded in.
- Any auto-apply / autofix mode.
- Building an eval harness for instruction A/B testing (the report may *recommend* the
  empirical loop; shipping tooling for it is not this issue).
- Auditing upstream plugin content in place (routing-only, per scope bound).

### Deferred questions

- Empirical validation posture: does the findings report prescribe the delete-and-watch +
  re-add-on-mistake loop (and cheap A/B for example blocks) as its recommended follow-through,
  or stop at the human-gated diff? — defer until /planning:plan; **arbiter: USER-RESERVED**
  (changes report shape and acceptance criterion 3's follow-through).
- Upgrade-trigger mechanics: how "upgrade-triggered" fires (manual invocation documented as the
  trigger vs any automation/hook seam) — defer until /planning:plan; **arbiter: /architect**
  (issue text already sanctions "upgrade-triggered or on-demand"; execution-shape decision).

## Plan

Standards grounding: repo `CLAUDE.md` (fresh-docs mandate, design rules), `docs/PLUGIN-PHILOSOPHY.md`
(naming, config ownership, fresh-eyes checkpoints, two-lane convention posture, prerequisites/degrade,
cross-platform), skill-quality 18-check gate, `scripts/validate-plugin-contracts.mjs`, portability-lint,
changelog-parity. Precedent map: memory slice `EXPLORE.md` (canonical checkout,
`.work/claude-config-audit-instructions/`).

### Open Decisions (resolved pre-plan; override any at the gate)

- **D1 claude-memory boundary — complementary partition** (revised after plan review verified
  `claude-memory:audit` C1–C8 already implement the hygiene seeds for CLAUDE.md/rules: C2 =
  deletion test, C1 = line budget, C3 = placement, C5 = inferable content, C8 = enforcement
  hierarchy). Partition, not overlap-with-disclaimer:
  - Memory-layer surfaces (CLAUDE.md, CLAUDE.local.md, `.claude/rules`): this skill runs ONLY
    the model-era checks (I6–I11); hygiene checks route out to `claude-memory:audit` (gated
    "when installed", fallback = one-line pointer to the official include/exclude table).
  - Non-memory surfaces (skill bodies + context files, agent definitions, prompt-type hooks,
    output styles): FULL catalog applies — no incumbent auditor (`skill-quality:check` is
    structural lint only).
  - Trigger disambiguation: description triggers are capability-framed ('after a model
    upgrade', 'too prescriptive', 'instructions the model no longer needs', 'holding the
    model back') — NOT 'prune my CLAUDE.md'/'audit CLAUDE.md' ('prune instructions' family is
    claude-memory:audit's claimed trigger space).
  - Reconciliation: fix the stale route-out reference in sibling
    `audit-permission-grants/SKILL.md` (names a nonexistent claude-memory `health` skill;
    actual name `audit`) — same plugin, this PR (Phase 5). A reciprocal boundary note in
    claude-memory:audit itself is a separate-plugin change → follow-up issue filed at PR time
    (cited in `## Related`).
- **D2 catalog carrier** — `reference/criteria.md`, versioned + dated, per-check authority tag
  (mcp-tools idiom) — 11 checks don't warrant machine-health JSONC machinery. Escape hatch
  recorded: graduate to `catalog/checks.jsonc` + schema if the catalog grows past ~20 checks
  or gains self-maintenance counters.
- **D3 severity vocabulary** — `error`/`warning`/`info` severity axis (family precedent) +
  independent **authority** tag (`ANTHROPIC-DOCS` / `TALK` / `OPINION`) + independent
  **evidence tier** (`mechanical` / `behavioral`). Three orthogonal axes, no conflation.
- **D4 deterministic spine in v1** — YES, minimal: one advisory scanner script (bare-prohibition
  lines and reasoning-echo phrases), always exit 0, `exit 2` on missing dep, `--count` flag,
  co-located test — claude-memory deterministic-spine + permission-grants script idiom. It
  seeds the mechanical tier; the model layer refines its hits (a grep cannot judge rationale
  presence reliably — the script marks candidates, the lane classifies).
- **D5 plugin version** — 0.8.0 (additive skill = minor; changelog-parity gate satisfied by a
  new `## [0.8.0]` entry).
- **D6 empirical-validation posture (was USER-RESERVED)** — the report ENDS with a
  "Recommended follow-through" section prescribing the official behavioral loop
  (delete-and-watch: "test changes by observing whether Claude's behavior actually shifts";
  re-add-on-mistake as the compounding safety net; cheap A/B against the no-example default
  for example blocks). Prose guidance only — no eval tooling shipped (Brief out-of-scope).
  Ratified by approving this plan.
- **D7 upgrade-trigger mechanics** — manual invocation only in v1; the description's trigger
  phrases carry the post-upgrade moment; no hook/automation (native-first: no lifecycle event
  exists for "model changed"; a consumer can pair with /loop or a scheduled routine —
  documented as a one-line note, not built).

### Phase 1: Skill core — SKILL.md [DONE]

Create `plugins/claude-config/skills/audit-instructions/SKILL.md`:

- Frontmatter: `name: audit-instructions`; `description` with distinguishing object in first
  clause + single-quoted 'Use when' triggers per D1's capability-framed set ('after a model
  upgrade', 'are my instructions holding the model back', 'instructions the model no longer
  needs', 'audit instructions', 'instruction audit', 'too prescriptive') + trailing
  "Report-only." note; `argument-hint:
  "[scope] — scope: claude-md|rules|skills|agents|hooks|output-styles|all (default: all)"`;
  `user-invocable: true`; `disable-model-invocation: false`. Description+when_to_use ≤1536
  chars (check 2).
- Body sections (permission-grants lean idiom, <200 lines soft target): Purpose; **Scope
  boundary (route out)** per D1 — every cross-plugin route seam-phrased per
  `docs/conventions/seam-phrasing/README.md` (gate "when <plugin> is installed" + stated
  fallback); Arguments; **Phase A Inventory** — enumerate locally-owned surfaces: user
  CLAUDE.md, user rules dir, user skills (`~/.claude/skills`) and agents, project CLAUDE.md,
  project `.claude/` (rules, skills, agents, output styles), prompt-type hooks — exact
  user-level paths (`~/.claude/rules` et al.) doc-verified at implementation per the
  fresh-docs mandate; EXCLUDE plugin cache (upstream-owned → findings become routing
  recommendations to the owning repo's tracker) and managed materializations
  (detection-first, org-agnostic: when the consuming repo's own docs declare a
  managed/locally-owned distribution seam — any sync-manifest convention — route managed-file
  findings upstream; no such declaration → no exclusion; no publisher names or hardcoded
  manifest paths in the skill); **Phase B Per-surface lanes** — fresh read-only subagent per
  surface sharing `reference/criteria.md` with D1's per-surface check partition, bounded
  concurrency 3–5, skills lane fans out per skill, cost gate: confirm with user before total
  dispatches (lanes + verifiers) exceed ~20, tier-transparency line naming surfaces run AND
  skipped; **Phase C Verify pass** — removal/rewrite proposals re-judged by fresh-context
  NON-FORK subagents prompted to refute ("would removing this cause mistakes? argue the
  instruction is still load-bearing") — self-grade class, fresh-eyes mandatory; batched one
  verifier per surface (not per finding), counted under the same ~20 dispatch gate; refuted
  proposals demoted to `info`/kept; **Phase D Report** — findings table
  `| # | Check | Surface:Line | Severity | Tier | Authority | Finding | Proposed change |`,
  proposed diffs as fenced blocks per finding, "a clean audit is a valid outcome",
  "Recommended follow-through" per D6, routing subsection for out-of-scope surfaces; report
  persisted to `${CLAUDE_PLUGIN_DATA}/audit-instructions/last-audit.md` (claude-memory
  persistence idiom) + chat summary; Gotchas (inline `## Gotchas` — check 11); What this
  skill does NOT do (never edits, never auto-files, not a brevity pass, not memory-layer
  hygiene).
- Read-only wording: "This skill is report-only. There is no `--fix`: instruction files are
  the operator's voice — every change is applied by the human (or explicitly delegated
  afterwards), never by this skill."

**Sanity Check** (runs at the Phase 1–3 commit boundary — check 5 needs criteria.md and the
script to exist before check-skill passes):
`CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/claude-config/skills" bash
plugins/skill-quality/scripts/check-skill.sh audit-instructions` exits 0 with no FAIL;
`grep -c "Scope boundary" plugins/claude-config/skills/audit-instructions/SKILL.md` ≥ 1;
`grep -Ec "^## Gotchas" SKILL.md` = 1.

### Phase 2: Check catalog — reference/criteria.md [DONE]

Create `plugins/claude-config/skills/audit-instructions/reference/criteria.md`:

- Header: `Version: 1.0.0`, `Last updated: 2026-07-21`, recheck triggers (next frontier model
  release; change to either prompting page; best-practices page change), source URL list.
- 11 checks `I1`–`I11` mapping the seeds: I1 line-necessity bar; I2 length/skimmability; I3
  broad-applicability placement (CLAUDE.md vs skill); I4 inferable/redundant content
  (include/exclude table); I5 rule-to-hook conversion; I6 bare prohibition → positive
  reframing first, prohibition-plus-rationale fallback for genuine hard nevers; I7
  reason-with-request; I8 model-era re-audit (prior-model workarounds, too-prescriptive
  skills); I9 example hygiene (keep 3–5 format/tone steering; flag behavioral scaffolding);
  I10 reasoning-echo instructions (`reasoning_extraction` hazard); I11 CLI-over-MCP.
- Each check: id, title, evidence tier (mechanical/behavioral), authority tag, severity
  default, **surface applicability per D1's partition** (I1–I5: non-memory surfaces only,
  memory-layer occurrences route to claude-memory:audit when installed; I6–I11: all
  surfaces), detection guidance, remediation form, source URL. Point-don't-copy: quote only
  the decisive line per source.

**Sanity Check:** `grep -Ec "^### I(10|11|[1-9]):" reference/criteria.md` = 11; `grep -c
"https://" reference/criteria.md` ≥ 5; check-skill.sh check 5 resolves the SKILL.md →
criteria.md reference (exit 0 overall).

### Phase 3: Deterministic spine — scripts [DONE]

Create `plugins/claude-config/skills/audit-instructions/scripts/instruction-scan.sh` +
`…/scripts/instruction-scan.test.sh` (skill-local, sibling idiom — NOT repo-root
`scripts/`) (per D4): scans
given file paths for I6 candidates (bare `never|do not|don't` lines lacking
because/since/so-that rationale markers) and I10 candidates (show-your-thinking phrases);
outputs `file:line:check-id` advisory rows; `--count` flag; always exit 0 (advisory), exit 2
if a required tool is missing; POSIX-lean bash, no jq requirement; Windows path via Git Bash
documented in SKILL.md prerequisites. Add the script to `skills/setup/SKILL.md` tool
inventory.

**Sanity Check:** `bash plugins/claude-config/skills/audit-instructions/scripts/instruction-scan.test.sh`
exits 0; `bash …/instruction-scan.sh --count <fixture>` prints an integer and exits 0.

### Phase 4: Evals [TODO]

Create `evals/evals.json` (schema `plugins/skill-quality/reference/evals.schema.json`): cases —
(1) bare invocation stays read-only (expectations: no Edit/Write of audited files, report
produced); (2) scope-boundary-routes-out (memory-health request → points at claude-memory);
(3) plugin-cache finding routed not edited; (4) example-block nuance (format-steering examples
NOT flagged); (5) verify-pass demotion (refuted removal not presented as error).

**Sanity Check:** `pipx run check-jsonschema --schemafile
plugins/skill-quality/reference/evals.schema.json
plugins/claude-config/skills/audit-instructions/evals/evals.json` exits 0 — the Python tool
CI uses (`check-jsonschema` is NOT an npm package; prior session verified npx form fails).

### Phase 5: Plugin integration [TODO]

- `plugins/claude-config/.claude-plugin/plugin.json`: version → 0.8.0; description string
  extended to four skills.
- `plugins/claude-config/CHANGELOG.md`: new `## [0.8.0]` → `### Added` entry (+ `### Fixed`
  for the stale route-out reference below).
- `plugins/claude-config/README.md`: one-question table row + "What each skill does"
  subsection.
- `plugins/claude-config/skills/audit-permission-grants/SKILL.md`: fix stale route-out —
  "`health` skill in the `claude-memory` plugin" → the actual `audit` skill (D1
  reconciliation, same plugin).
- Root README catalog is GENERATED — run `node scripts/generate-catalog.mjs` after the
  plugin.json description change (hand-editing drifts; CI runs `--check`).

**Sanity Check:** `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0;
`grep -c "audit-instructions" plugins/claude-config/README.md` ≥ 2; `node
scripts/validate-plugin-contracts.mjs` exits 0; `node scripts/generate-catalog.mjs --check`
exits 0; `grep -c "health" plugins/claude-config/skills/audit-permission-grants/SKILL.md`
returns 0 for the stale-reference form.

### Phase 6: Gates, review, PR [TODO]

Full local gate run (check-skill, contracts, portability, markdownlint, changelog parity,
plugin tests), independent review pass (fresh-context reviewer per repo doctrine), then PR:
title Conventional Commits; body `Closes #800`, non-empty `## Related` (#798 sibling effort,
knowledge-corpus#3 digest provenance), approved PLAN.md in `<details>`; prune topic slice in
final pre-merge commit. Merge surfaced to user per never-merge boundary.

**Sanity Check:** all listed gate commands exit 0 locally; `gh pr view --json body` contains
`Closes #800` and a `## Related` section; ci-status green.

### Appendix: pinned seed catalog (durable copy — source repo's `.work/` slice is ephemeral)

Source: knowledge-corpus, memory slice
`.work/youtube-watch/how-i-plan-build-and-run-loops-with-clau-aVO6E181cNU/research/findings/context-trimming.md`
(committed in knowledge-corpus#3). Pinned 2026-07-21 so AC2 stays verifiable if that slice
moves:

| Seed | Check | Summary | Source |
|---|---|---|---|
| 1 | I1 | Line-necessity: "Would removing this cause Claude to make mistakes?" else cut | code.claude.com/docs/en/best-practices |
| 2 | I2 | Length/skimmability gate; bloat causes instruction-ignoring | code.claude.com/docs/en/best-practices |
| 3 | I3 | Only-sometimes-relevant content → skill, not always-loaded CLAUDE.md | code.claude.com/docs/en/best-practices |
| 4 | I4 | Exclude inferable content (code, standard conventions, linked API docs, truisms) | code.claude.com/docs/en/best-practices (include/exclude table) |
| 5 | I5 | Rule already followed or 100%-required → hook or delete | code.claude.com/docs/en/best-practices |
| 6 | I6 | Bare prohibition → positive reframing first; rationale fallback for hard nevers | platform.claude.com …/claude-prompting-best-practices |
| 7 | I7 | Carry intent/motivation with instructions | same + …/prompting-claude-fable-5 ("Give the reason") |
| 8 | I8 | Release-time re-audit; prior-model skills often too prescriptive, degrade quality | platform.claude.com …/prompting-claude-fable-5 |
| 9 | I9 | Examples only for format/tone/structure steering (3–5); flag behavioral scaffolding | …/claude-prompting-best-practices + Fable 5 page |
| 10 | I10 | Flag show-your-thinking/reasoning-echo instructions (`reasoning_extraction` refusal) | platform.claude.com …/prompting-claude-fable-5 |
| 11 | I11 | Prefer CLI over MCP where equivalent (context cost) | code.claude.com/docs/en/best-practices |

## Blast radius

LOW — additive markdown skill + one advisory script inside one plugin; no runtime code paths
of other skills touched; plugin.json description/version edits are metadata. Cross-plugin
surface limited to README/catalog rows. No consumer-breaking contract changes.

## Stress-test summary

Fresh-context plan reviewer (Step 3) returned 1 CRITICAL / 6 IMPORTANT / 4 SUGGESTION; all
verified against the repo before applying. Applied: D1 rewritten as a complementary partition
(claude-memory:audit C1–C8 verified to already cover the hygiene seeds on memory-layer
surfaces), capability-framed trigger set, seam-phrased route-outs, stale `health` reference
fix folded into Phase 5, `pipx run check-jsonschema` (npm package does not exist),
generated-catalog regen + `--check` sanity, Phase 1–3 single commit unit (check 5 reference
resolution), skill-local script path, pinned seed appendix, org-agnostic managed-seam
detection, verify-pass batching under the shared ~20-dispatch gate, surface enumeration
completed (user skills/agents) with user-path doc-verification note, report persistence to
`${CLAUDE_PLUGIN_DATA}`. Formal /devils-advocate skipped: blast radius LOW, no triggers
matched.

## Execution shape

Sequential, single scope-fenced implementation worker in this worktree (orchestrator never
edits source; work-items:work dispatch posture). Phases 1–3 are ONE commit unit (skill-quality
check 5 requires SKILL.md's criteria.md and script references to resolve), then 4, 5 as
separate commits; 6 closes. No parallel wave: file sets are small and Phase 5 depends on 1–4
outputs.

| Phase | Surface | Basis |
|---|---|---|
| 1–5 | implementation worker subagent (this worktree) | mechanical authoring against locked plan; orchestrator-never-edits |
| 6 | orchestrator (gates, PR) + fresh-context reviewer | judgment + repo doctrine (producer ≠ critic) |

Sequential fallback: n/a (already sequential).

## Open questions

None unresolved — D1–D7 locked above pending gate approval; D6 was USER-RESERVED and is
ratified by plan approval.

## Handoff to implementation

### User-approval gates

- Plan approval (this gate) ratifies D6 (follow-through section) and D1 (stay in
  claude-config).
- PR merge is surfaced to the user (never-merge boundary) unless the user delegates to the
  babysit worker tier.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Single worker, sequential phases, commit boundaries as listed in Execution
  shape.
- Worker ALLOWED: `plugins/claude-config/**` (includes the audit-permission-grants stale-ref
  fix), root `README.md` ONLY via `node scripts/generate-catalog.mjs` (generated, never
  hand-edited). FORBIDDEN: other plugins' files except read; `.github/**`;
  `docs/topics/**` (PLAN.md status tags are orchestrator-only).

### Mechanical work

Commit per phase boundary with `-F - --cleanup=verbatim`; run Phase sanity checks at each
green checkpoint; divergence from plan → back to /planning:plan review, never push through.
