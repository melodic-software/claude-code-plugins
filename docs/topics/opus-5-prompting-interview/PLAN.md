# PLAN — opus-5-prompting-interview

## Brief

Interview completed 2026-07-26 (sessions 13ea1cdf + continuation). Every answer validated by three
independent fresh-context validators (Claude Opus 5, Claude Fable 5, Codex GPT-5.6 Sol high);
verdicts + merged triage in `validation/`. Written to `.work` because the shared checkout moved to
an unrelated task branch mid-session; graduate this file to `docs/topics/opus-5-prompting-interview/PLAN.md`
on the build task branch.

### TLDR

Turn the dual-verified Opus 5 corpus (prompting guide + system card) into: refreshed per-model
doctrine in the existing `playbooks` model-adaptation seam, an Opus-5 model-delta rule class in
`claude-config:audit-instructions`, a reusable doc-ingestion skill in the `knowledge` plugin, and
graduation of the corpus to `knowledge-corpus`. Everything model-scoped with a defined fleet-wide
promotion gate and a Claude-Code-applicability filter with teeth.

### Goal

Make Anthropic's Opus 5 guidance operational in daily Claude Code sessions without adding
instruction noise: remove instructed self-check scaffolding where Opus 5 runs, keep architected
independent review, deliver model-matched deltas through existing seams, and codify the ingestion
pipeline so the queued docs (Fable 5, Sonnet 5, effort, guardrails, choosing-a-model, best
practices, blogs) repeat cheaply.

### Deliverables (build order suggested, plan phase decides)

1. **playbooks model-adaptation refresh** — generalize `plugins/playbooks/skills/fable-5/context/`
   to `context/model-adaptation/<model>.md`; add `opus-5.md` carrying: verified behavioral deltas;
   the architected-vs-instructed verification doctrine WITH the recorded residual tension (the
   reconciliation is inference — source line 25 vs 65/78/83 never reconciled upstream); thinking
   controls (Alt+T, `alwaysThinkingEnabled`, `MAX_THINKING_TOKENS=0`; Fable-5-only carve-out) +
   thinking-off leakage guidance + 400-at-xhigh/max constraint; deliverable-length calibration
   sentence verbatim (tested-phrasing exception); effort guidance (start high/default, low/medium
   liberal); injection-robustness note (auto-mode-0% qualifier; trigger names the Haiku-unmeasured
   gap; bug-bounty re-read linked to same trigger). Fix or retire the stale `opus-adaptation.md`
   (Opus-4.8-calibrated; guide reverses it on effort floor, per-edit-batch verifier dispatch,
   delegation bias, scope literalism; I15-shaped conflict with SKILL.md meta-rule 3) in the same
   change. Hard facts (pricing, IDs, effort ladder) POINT at the `claude-api` skill — never copied.
   Pinned agent defs use conditional framing ("if you are not X…") because spawn-time overrides can
   desync body text from the running model.
2. **audit-instructions extension** — extend I8 (model-era re-audit) with Opus-5 rows, not a
   parallel class: instructed self-check/double-check/re-verification removal;
   report-everything-vs-conservative detection (BEHAVIORAL, with scope fence — known false positive
   in code-tidying tidyings.md:102); don't-think/don't-reason directive check. Add explicit
   target-model argument (skills are model-blind) defaulting to the pinned fleet model. Migrate I8
   and I10 to model-scoped per the promotion gate. Price the runtime/confirmation-gate cost.
   Report-only stays.
3. **knowledge plugin: 4th sibling ingestion skill** (name via tournament at build) —
   self-contained like book-distill/course-digest/youtube-digest; pipeline mechanics
   (fetch → inventory → digest fan-out → dual cross-vendor verification → interview handoff)
   generic/multi-purpose by design; the Anthropic profile (raw-`.md` fetch channel,
   CC-applicability filter, model-matched digest agents, doc queue, artifact targets) is a
   SEPARABLE context file so a second profile can join and the engine can be extracted at the
   third (Rule of Three). Check `review:fanout` overlap before duplicating dual verification.
   PROCESS.md queue migrates into it.
4. **knowledge-corpus graduation** — both slices, ALL unaltered originals (source.md, source.pdf
   via existing LFS `.pdf` rule, source.txt) + digests + verification records; new
   `sources/<category>/` sibling (docs category); follow the repo's source-URL convention
   (provenance + retention terms). Fix the mechanisms-research stale cell (skills DO accept
   `model` frontmatter — selects executing model, does not branch) before it graduates.
5. **Effort-doc slice** — run the pipeline on
   `platform.claude.com/docs/en/build-with-claude/effort` BEFORE building effort artifacts (guide's
   ladder is truncated; verified live).
6. **Effort judgment recalibration** — no eval suite exists; reframed from "sweep". Execute with
   the choosing-a-model routing-vet slice (task #18). Distinguish pinnable vs session-only effort
   lanes.

### Constraints

- Model-scoped by default; fleet-wide promotion ONLY via the gate: an authoritative model-agnostic
  upstream doc states it, OR multiple model guides converge.
- CC-applicability filter with teeth: every harness-applicability tag is a claim verified against
  live code.claude.com docs at tag time (answer 17 was the filter's first application and it
  missed by inference).
- Verification doctrine: remove instructed self-checks on Opus 5; keep architected independent
  review. Re-check surfaces classified by reviewer INDEPENDENCE, not invocation source. Advisor
  counts on the stronger-model axis only (sees full conversation — not context-independent).
- Mandatory-verification carve-outs regardless of model deltas: security review, destructive
  operations, managed-upstream-file changes, PR merge gates.
- Point-dont-copy everywhere; local copies only for tested-verbatim phrasing or frozen verification
  snapshots (MD5-pinned corpus).
- Primer/delta payload minimal — curated deltas only; instruction compounding applies to the primer
  itself.
- `.work/` stays untracked; nothing commits without explicit decision; verdict files are historical
  records (errata pattern — corrections in corrections-applied files, never rewrites).
- Session verifier policy for this workstream: dual verifiers (Claude high + Codex GPT-5.6 Sol
  high) on everything produced.

### Acceptance criteria

- `opus-adaptation.md` conflict resolved: no surviving instruction tells Opus 5 to apply
  4.8-calibrated counter-steers verbatim.
- `context/model-adaptation/opus-5.md` exists; every claim carries source + CC-applicability tag;
  hard facts are pointers.
- audit-instructions run over this repo + user scope surfaces the instructed-self-check findings
  with the Opus-5 target-model argument; scope fence keeps the known false positive out.
- Ingestion skill re-runs the pipeline end-to-end on the effort doc (deliverable 5 doubles as its
  acceptance test).
- Both slices resolvable in knowledge-corpus with intact MD5s + source-URL records.

### Captured assumptions

- Architected-vs-instructed reading is inference shared by 4 digests + all 3 validators + both
  corpus verifiers; recorded as such in the delta chapter so a future upstream clarification has a
  landing spot. If Anthropic reconciles differently, cluster-1 decisions move together.
- "Agent preloaded with a skill" seam (user recollection) — verify at build; not load-bearing.

### Out of scope

- Chat-verbosity instruction (ground held by existing rules + harness).
- Narration artifact (harness ships near-identical guidance; verified in two live system prompts).
- New hallucination/uncertainty instruction (saturated behaviors; citation-strengthening only).
- Routing-lane changes from injection data (deferred with trigger).
- Paste templates for non-CC surfaces (no API-side prompt authoring exists today).
- Figure-value recovery from the card PDF (unless a decision leans on a missing number).

### Deferred questions

- Empirical: what does Claude Code send at thinking-off + xhigh/max (400 or clamp)? → /planning:plan
  (build-time test; docs silent).
- Thinking-off usage opportunities (user: "anything else we could make use of… don't lose sight") →
  /planning:plan; record as exploration item with the delta chapter as its home.
- Ingestion-skill name → /planning:plan (naming tournament; candidates: ingest, doc-distill, absorb).
- Statusline prime-drift indicator (Fable proposal) → /planning:plan (cheap, optional).
- SessionStart pointer-only auto-prime → deferred-with-trigger (manual priming proves forgettable).
- USER-RESERVED: any fleet effort-pin change resulting from recalibration (dotfiles
  `.chezmoidata/claude.json` seam; never machine-local).
- USER-RESERVED: committing/graduating any `.work` content beyond the knowledge-corpus move.

## Plan

All sanity-check commands run under Git Bash (verified available: GNU grep, md5sum coreutils 8.32,
git-lfs 3.7.1).

### Standards grounding

No `.claude/standards.yaml` / `docs/standards/` index exists — resolution ladder rung 4 (inference
from repo-declared docs). `.claude/topic-docs.yaml` absent → topic-docs documented default
`contract_tier: branch` applies (convention: `docs/conventions/topic-docs/README.md`; the `:210`
YAML is its illustrative example, not a repo setting). Surfaces loaded:

| Surface | Sections cited | Layer provenance |
|---------|----------------|------------------|
| `CLAUDE.md` | Fresh-docs mandate (:8-27); plugin design rules incl. semver versioning (:29-43); branching & PRs (:51-55) | team/repo |
| `AGENTS.md` | Synced standards overwritten not edited (:9-16); stage explicit paths (:18-22); Conventional-Commits PR titles (:24-27) | team/repo |
| `README.md` | Repo shape + documented validation commands (exact lint/test invocations resolved here at build time) | team/repo |
| `docs/MIGRATION-PLAYBOOK.md` | Skill-split-on-discovery-intent (:28-35); naming precedence (:95-168); evals warrant policy (:298-359); version-bump delivery (:373-382); knowledge-corpus decision record (:1370-1402) | team/repo |
| `docs/conventions/topic-docs/README.md` | Contract-tier default (branch) + prune-before-merge lifecycle | team/repo |
| CI (`.github/workflows/ci.yml`) | `changelog-parity-gate` (:452), `contract-slice-prune-gate` (:482), `skill-quality-gate` (:806), `portability-lint`, `shell-portability-lint`, `skill-leaf-name-gate`, `orphaned-fixture-gate` | team/repo |
| User CLAUDE.md | pointer-not-copy; producer≠critic; fresh-docs verification posture | user-global |

### Phase 1: Contract commit + memory-slice hygiene [DONE]

The contract slice (this PLAN + `design/design-resolution.md`) is already authored on disk,
untracked — this phase COMMITS it (do not re-create or overwrite) and fixes the one known stale
research cell before anything downstream cites it.

**Files affected:**

| File | Action | What changes |
|------|--------|-------------|
| `docs/topics/opus-5-prompting-interview/PLAN.md` | COMMIT | Already authored (this file); stage + commit as-is |
| `docs/topics/opus-5-prompting-interview/design/design-resolution.md` | COMMIT | Already authored |
| `.work/opus-5-prompting-interview/PLAN.md` | MODIFY | ADD a graduation header note (authoritative copy now at `docs/topics/...`); body KEPT INTACT until close-out completes its PR-body paste — pointer-ization is a Phase 7 step, never before, so the workstream always holds one durable copy (graduation of THIS file is explicitly instructed by the Brief header — briefed exception to the USER-RESERVED `.work` clause) |
| `.work/opus-5-prompting-interview/model-conditional-mechanisms-research.md` | MODIFY | Fix stale "Skills/commands" cell: skills DO accept `model` frontmatter (selects executing model, does not branch); verify against live `code.claude.com/docs/en/skills.md` at edit time and cite the URL in the row. Living research doc — edited in place; errata pattern reserved for verdict files (verdicts are append-only historical records) |

Work items:

0. Sync: `git fetch` + rebase the task branch onto `origin/main` (verified 8 commits behind at
   plan time; main's playbooks is 0.5.2, not the checkout's 0.5.1), then re-verify every version
   number and line citation this plan hardcodes. Version from-values below are plan-time
   observations — the phase re-reads them at start; bumps are relative (next minor), not absolute.
1. Pre-flight: confirm no file this plan touches is a managed materialization — check the local
   `melodic-software/standards` checkout's `distribution/sync-manifest.yml` for this repo's managed
   paths (expected: none of `plugins/**` or `docs/topics/**` are managed; record the check).
2. Verify the skills `model`-frontmatter claim against live docs (fresh-docs mandate); fix the cell
   with URL citation.
3. Commit (`docs(topics): graduate opus-5-prompting-interview contract`), explicit paths only.

**Sanity Check:**

- `git ls-files docs/topics/opus-5-prompting-interview/` lists `PLAN.md` and `design/design-resolution.md`.
- `grep -A3 "^## Stress-test summary" docs/topics/opus-5-prompting-interview/PLAN.md | grep -c "dual review"` returns ≥1 (summary filled, not a placeholder).
- `grep -E "selects the executing model" .work/opus-5-prompting-interview/model-conditional-mechanisms-research.md | grep -c "https://code.claude.com"` returns ≥1 (corrected claim + live citation on the same row).
- Work-item-1 check output recorded in the phase notes (managed-path result).

### Phase 2: playbooks model-adaptation refresh [DONE]

Review: code-design

Generalize the model-adaptation seam and land the Opus 5 delta chapter (Brief deliverable 1).

**Files affected:**

| File | Action | What changes |
|------|--------|-------------|
| `plugins/playbooks/skills/fable-5/context/opus-adaptation.md` | MOVE | `git mv` → `context/model-adaptation/opus-4-8.md`; title/preamble stay 4.8-scoped; deltas unchanged (still valid for their calibration target) |
| `plugins/playbooks/skills/fable-5/context/model-adaptation/opus-5.md` | CREATE | The Opus 5 delta chapter (content contract below) |
| `plugins/playbooks/skills/fable-5/SKILL.md` | MODIFY | Meta-rule 3 rewritten: route by model VERSION to `context/model-adaptation/<model>.md`; kill "if you are Opus, apply them verbatim" (the I15-shaped conflict); update chapter-routing row + "What this skill is NOT" pointer |
| `plugins/playbooks/skills/fable-5/context/orchestration.md` | MODIFY | Line 3 "the opus-adaptation chapter's concern" → model-adaptation phrasing (rename sweep) |
| `plugins/playbooks/.claude-plugin/plugin.json` | MODIFY | Next-minor bump (main is at 0.5.2 → 0.6.0; re-verify post-rebase) |
| `plugins/playbooks/CHANGELOG.md` | MODIFY | New-version entry per house shape; existing entries' `opus-adaptation` mentions stay (history) |

`opus-5.md` content contract (each claim: source citation + CC-applicability tag, tags verified
against live code.claude.com docs at tag time):

- Verified behavioral deltas (from the 9 guide digests + card digests).
- Architected-vs-instructed verification doctrine WITH recorded residual tension (reconciliation
  is inference; source line 25 vs 65/78/83 never reconciled upstream) — landing spot for a future
  upstream clarification.
- Thinking controls: Alt+T, `alwaysThinkingEnabled`, `MAX_THINKING_TOKENS=0`, Fable-5-only
  carve-out; thinking-off leakage guidance; 400-at-xhigh/max constraint. Cites the probe artifact
  (below).
- Thinking-off usage opportunities recorded as a tagged exploration item (this chapter is the
  designated home).
- Deliverable-length calibration sentence verbatim (tested-phrasing exception to point-dont-copy).
- Effort guidance: ONLY guide-verbatim model-scoped claims (start high/default; low/medium
  liberal). The effort ladder itself is a POINTER to the `claude-api` skill — never restated. Any
  claim that would need the effort doc is deferred to the Phase 6 cross-check (dependency noted
  there) — this keeps deliverable 5's ordering constraint honest without serializing Phase 2
  behind the new skill.
- Injection-robustness note: auto-mode-0% qualifier; deferred-with-trigger routing note whose
  trigger names the Haiku-unmeasured gap; bug-bounty re-read linked to the same trigger.
- Hard facts (pricing, model IDs, effort ladder) are pointers to the `claude-api` skill.
- Payload discipline: curated deltas only — instruction compounding applies to this file itself.
- Public-repo quotation note: this plugin repo is PUBLIC; the chapter's one verbatim upstream
  sentence (deliverable-length calibration) ships with source attribution — record the de-minimis
  quotation rationale in the chapter's Sources section (licensing analysis, Phase 2's own
  pre-flight; the Phase 5 licensing pre-flight covers only the private corpus repo).

Work items:

1. Pre-flight: sweep live branches/worktrees for concurrent edits to
   `plugins/playbooks/skills/fable-5/` (`git worktree list` + `git branch --contains` scan; the
   `docs/ignition-rebind-note` worktree is known to hold the same SKILL.md region) — sequence or
   rebase deliberately before rewriting.
2. Fetch live docs for every harness claim (thinking controls, settings keys); cite URLs in the
   chapter's Sources section.
3. Empirical probe, thinking-off + xhigh/max: record a dated observation artifact at
   `.work/opus-5-prompting-interview/build-verification/thinking-off-probe-<date>.md` capturing CC
   version (`claude --version`), relevant settings snapshot, method (observation point for the
   request/error), result (400 vs clamp), and limitations. `opus-5.md` cites it as
   session-observed (docs silent). Probe is non-mutating.
4. Author `opus-5.md` from corpus digests (curated, minimal).
5. `git mv` + preamble edit for `opus-4-8.md`; rewrite SKILL.md meta-rule 3 + routing row; fix
   `orchestration.md:3`.
6. Rename sweep via `docs-hygiene:rename-references` over LIVING surfaces only —
   `docs/topics/fable-field-guide-audit/**` and CHANGELOG history stay untouched (historical
   records; errata pattern).
7. Version bump + CHANGELOG.
8. Dual verification (fresh Claude high + Codex GPT-5.6 Sol high, text-embedded while task #15
   open) of the chapter against the corpus; records land in
   `.work/opus-5-prompting-interview/build-verification/`; corrections applied to the ARTIFACT
   before commit (verification records themselves append-only).

**Sanity Check:**

- `grep -rn "apply them verbatim" plugins/playbooks/` returns 0 hits.
- `ls plugins/playbooks/skills/fable-5/context/model-adaptation/` shows `opus-4-8.md` and `opus-5.md`.
- `grep -rn "opus-adaptation" plugins/playbooks/ --include="*.md" | grep -v CHANGELOG` returns 0 hits.
- plugin.json shows `0.6.0`; CHANGELOG has `## [0.6.0]`.
- Point-dont-copy: `grep -cE "\\$[0-9]|per MTok|MTok" .../opus-5.md` = 0 AND `grep -cE "claude-[a-z]+-[0-9]" .../opus-5.md` = 0 (no API model IDs) AND `grep -icE "low.*medium.*high.*xhigh|xhigh.*max" .../opus-5.md` = 0 (no ladder enumeration).
- Probe artifact exists and is cited: `grep -c "thinking-off-probe" .../opus-5.md` ≥ 1.
- Required content markers each present (one grep per item): residual-tension label, verbatim
  deliverable-length sentence, exploration-item tag, auto-mode qualifier, Haiku-unmeasured trigger.
- markdownlint (repo's documented command) passes on changed files; `portability-lint` expectations
  hold (no machine paths).

### Phase 3: audit-instructions Opus-5 extension [DONE]

Review: code-design

Extend I8 with Opus-5 model-delta rows (not a parallel class), add target-model semantics, and
model-scope I8/I10 per the promotion gate.

**Target-model semantics (the deliverable's hinge):** the skill gains `--target-model <value>`
taking a model VERSION (e.g. `opus-5`). Default resolution: read the resolved settings `model`
value, then normalize alias→version against live model docs at run time; the pinned fleet value is
an alias with a context-window suffix (verified this session: `opus[1m]`, settings.json:438), so
normalization MUST fail loud when the alias is version-ambiguous and demand the explicit argument —
never silently treat `opus` as `opus-5`. Model-scoped rows FIRE only when the resolved target
matches their scope; otherwise they are inert (report lists them as skipped-for-target). The value
is data — no hardcoded model branch in prose.

**Files affected:**

| File | Action | What changes |
|------|--------|-------------|
| `plugins/claude-config/skills/audit-instructions/reference/criteria.md` | MODIFY | I8 gains Opus-5-scoped rows: (a) instructed self-check/double-check/re-verification removal — carve-out lanes (security review, destructive ops, managed-file changes, PR merge gates) + independence classification (architected review survives); (b) report-everything-vs-conservative detection, BEHAVIORAL, with TWO fences: restraint-clause shape (the `tidyings.md:102` "When NOT to apply" case) AND quoted/meta-surface exclusion (documents that DISCUSS the pattern — criteria.md itself, the opus-5 delta chapter — are not findings); (c) don't-think/don't-reason directive check. Fences OWNED here (the model lane adjudicates; scanner stays advisory). I8 + I10 annotated model-scoped (single-model guide sources; promotion gate unmet). Criteria version 1.2.0 → 1.3.0 |
| `plugins/claude-config/skills/audit-instructions/SKILL.md` | MODIFY | `argument-hint` + parsing for `--target-model`; normalization + fail-loud rule above; cost pricing: report header states added per-surface check count + estimated token delta AND confirms zero new interactive gates (report-only unchanged) |
| `plugins/claude-config/skills/audit-instructions/scripts/instruction-scan.sh` | MODIFY | ADVISORY candidate patterns only (self-check phrasing, don't-think, conservative-phrasing) — over-production is by design per the script's own contract; header/`--help` updated to list the new pattern families |
| `plugins/claude-config/skills/audit-instructions/scripts/instruction-scan.test.sh` | MODIFY | TDD: failing cases first. Positive fixtures: instructed self-check, don't-think, "be conservative" directive. Negative fixtures at the CRITERIA level are exercised via the acceptance run (fence is criteria-owned); scanner tests assert candidates are EMITTED for all shapes including tidyings-like text (advisory over-production is correct scanner behavior) |
| `plugins/claude-config/.claude-plugin/plugin.json` | MODIFY | 0.13.0 → 0.14.0 |
| `plugins/claude-config/CHANGELOG.md` | MODIFY | 0.14.0 `### Added` bullets per house shape |

Work items:

1. TDD: scan-script fixtures (failing) → patterns (green); `shell-portability-lint` constraints
   respected (no GNU-only constructs).
2. Author I8 rows + both fences + model-scope annotations (I8, I10) in criteria.md.
3. Target-model argument + normalization + cost pricing in SKILL.md.
4. Version bump + CHANGELOG.
5. Acceptance run (AFTER Phase 2 lands — a clean playbooks result proves the conflict fix).
   PRECONDITION (verified this session): the audit resolves plugin surfaces from the SELECTED
   install record's cache path and rejects tree-walking (SKILL.md:115, :172-176) — the repo
   working tree is invisible to it. So FIRST install the task branch as a local-path marketplace
   (repo ships `.claude-plugin/marketplace.json`) so the selected install records point at the
   branch's playbooks/claude-config; record the install-record switch and its revert in the phase
   notes. Then run the audit over this repo + user scope with `--target-model opus-5` under Git
   Bash; report path resolved from `${CLAUDE_PLUGIN_DATA}/audit-instructions/last-audit.md` at run
   time. Fallback if local-path install proves unavailable: re-scope this run as post-merge
   verification and drop the Phase 2 → Phase 3 dependency edge (record the re-scope).
6. Dual verification of criteria/SKILL diffs; records in `build-verification/`.
7. Line budget: SKILL.md is 314/500 lines with a soft-target WARN already firing — additions
   (argument parsing, normalization rule, cost line) capped at ~60 lines; overflow goes to a
   `reference/` spoke.

**Sanity Check:**

- `bash plugins/claude-config/skills/audit-instructions/scripts/instruction-scan.test.sh` exits 0.
- `grep -c "target-model" plugins/claude-config/skills/audit-instructions/SKILL.md` ≥ 2; criteria frontmatter shows `1.3.0`.
- Acceptance-run report: (a) scanned-surface manifest lists `plugins/code-tidying/skills/tidy/reference/tidyings.md`; (b) findings contain ≥1 instructed-self-check hit from a real surface; (c) `grep -c "tidyings.md" <findings section>` = 0 (fence held while file was scanned); (d) `opus-5.md` and `criteria.md` appear in the manifest but NOT in findings (meta-surface fence held); (e) report header carries the cost line; (f) non-matching target smoke run (`--target-model fable-5`) lists the Opus-5 rows as skipped-for-target.
- plugin.json shows the next-minor version; CHANGELOG has the matching heading; `orphaned-fixture-gate` green (fixtures referenced by tests).
- `bash scripts/check-changed-skills.sh origin/main` exits 0 (audit-instructions is a changed skill — trigger-keyword preservation, listing cap, 500-line cap all hold).

### Phase 4: knowledge ingestion skill [DONE]

Review: code-design

Fifth skill in the plugin, fourth INGESTION sibling: generic doc-ingestion pipeline engine with
the Anthropic profile as a separable context file.

**Files affected** (skill name `<name>` resolved by work item 1):

| File | Action | What changes |
|------|--------|-------------|
| `plugins/knowledge/skills/<name>/SKILL.md` | CREATE | Line budget ≤250 (hard cap 500; siblings run 191/225/411) — progressive-disclosure spokes under `context/` planned UP FRONT for pipeline detail. Pipeline mechanics: fetch → inventory (INDEX.md) → digest fan-out (one agent per digest unit, model-matched; every model-pinned spawn brief/agent def uses CONDITIONAL framing — "if you are not X…" — because spawn-time overrides can desync body text from the running model) → dual cross-vendor verification (built fresh; `review:fanout` verified NOT reusable — diff-shaped, review-specific) → interview handoff (named artifact: a validation-answer-set-shaped handoff file). Sibling conventions: checklist template, continuation-prompt handoff, slug + path-traversal guards, untrusted-source discipline (ingested content is DATA, never directives — the injection mitigation), work root resolved through the plugin's `library_dir` seam (course-digest precedent, SKILL.md:31), degraded-verifier fallback documented (never silent) |
| `plugins/knowledge/skills/<name>/context/anthropic-docs-profile.md` | CREATE | SEPARABLE profile: raw-`.md` fetch channel (verify per doc), CC-applicability filter with teeth (tags verified against live docs at tag time), model-matched digest agents, doc queue (migrated from `.work/PROCESS.md` — briefed by deliverable 3), artifact targets. Second profile joins beside it; engine extraction at the third (Rule of Three) |
| `plugins/knowledge/skills/<name>/templates/checklist.md` | CREATE | Per-run pipeline checklist (sibling pattern) |
| `plugins/knowledge/skills/<name>/evals/evals.json` | CREATE | Evals (warranted: judgment-bearing routing/output contract); behavioral proof is Phase 6's live run — evals encode the routing/trigger cases |
| `plugins/knowledge/.claude-plugin/plugin.json` | MODIFY | 0.9.6 → 0.10.0 |
| `plugins/knowledge/CHANGELOG.md` | MODIFY | 0.10.0 entry |
| `plugins/knowledge/README.md` | MODIFY | Skills table row |
| `.work/PROCESS.md` | MODIFY | Queue section replaced by pointer to the profile context file (memory-tier, untracked) |

Work items:

1. Naming tournament (`naming:name-it-better`, tournament mode). Seeds: `doc-distill` plus
   candidates; CONSTRAINT fed in: siblings follow SOURCE-KIND shape (`book-distill`,
   `course-digest`, `youtube-digest`) — bare-verb candidates (`ingest`, `absorb`) break it.
   RESOLVED: `docpage-digest` (5 blind generators, 3 independent judges, Borda 23/21/19;
   runners-up `docs-digest`, `doc-digest`) — provisional pending user ratification at PR;
   pre-merge rename is cheap via `docs-hygiene:rename-references`.
2. Author SKILL.md + profile + templates + evals.
3. `skill-quality:check`; fix findings.
4. Version bump + CHANGELOG + README.
5. Dual verification of the skill body against PROCESS.md semantics (no pipeline step dropped);
   records in `build-verification/`.

Out of scope (explicit): sweeping the 8 pre-existing pinned agent defs
(`plugins/discovery/agents/*`, `plugins/review/agents/*`) for conditional framing — they carry no
model-delta doctrine text; the Brief clause governs artifacts THIS workstream authors. Recorded as
a decisions-table row; revisit if a model-delta chapter ever lands inside an agent body.

**Sanity Check:**

- `scripts/check-changed-skills.sh` passes; evals.json validates against `plugins/skill-quality/reference/evals.schema.json`; `skill-leaf-name-gate` green.
- `grep -c "prompting-claude-fable-5" .../context/anthropic-docs-profile.md` ≥ 1 AND queue-entry count in the profile ≥ the count in `.work/PROCESS.md`'s pre-migration queue (no entry dropped).
- `grep -c "if you are not" .../SKILL.md` ≥ 1 (conditional-framing contract present).
- `grep -ci "library_dir" .../SKILL.md` ≥ 1 (work-root seam, not a hardcoded path).
- plugin.json `0.10.0`; CHANGELOG `## [0.10.0]`; README table lists `<name>`.

### Phase 5: knowledge-corpus graduation [DONE]

Cross-repo phase (repo: `melodic-software/knowledge-corpus`, local checkout verified; own branch +
PR there).

**Hash doctrine (split two concepts — audit-time pins vs graduation pins):** the prompting slice's
recorded pin (`opus-verdict.md:44-55`) predates 28 applied corrections; only `source.md` still
matches. So: (a) immutable UPSTREAM ORIGINALS (`source.md`, `source.pdf`, `source.txt`) are
verified against existing pins where one exists and pinned fresh where none does; (b) derived
artifacts (INDEX, digests — corrected-derived, NOT unaltered — and verification records) get a
FRESH dated graduation pin per slice; (c) `PROCESS.md` is dropped from any pinned set (moved +
still-living file). Existing verdict files are never rewritten. Acceptance criterion "intact MD5s"
is met as: originals bit-identical to `.work`, all files covered by a current pin record.

**Files affected (knowledge-corpus repo):**

| File | Action | What changes |
|------|--------|-------------|
| `sources/docs/opus-5-prompting/**` | CREATE | Full slice copy: source.md (original), INDEX.md + digests/ (9, corrected-derived) + verification/ (3) |
| `sources/docs/opus-5-system-card/**` | CREATE | Full slice copy: source.pdf (LFS via existing `*.pdf` rule) + source.txt (originals); reflow_78_105.txt (tool-DERIVED, pinned under the derived-artifact rule); INDEX.md + digests/ (9) + verification/ (6 incl. tool.py) |
| `sources/docs/opus-5-prompting/README.md` | CREATE | Provenance, required fields: canonical origin URL, fetch date, fetch channel (raw `.md`), retention terms |
| `sources/docs/opus-5-system-card/README.md` | CREATE | Same fields + PDF origin |
| `sources/docs/opus-5-prompting/verification/graduation-pin-2026-07-26.md` | CREATE | Fresh dated MD5 manifest: every file in the slice, with per-file original/corrected-derived label; notes the audit-time pin divergence cause (corrections-applied) |
| `sources/docs/opus-5-system-card/verification/graduation-pin-2026-07-26.md` | CREATE | Same (this slice had NO prior pin — first hash record) |

Work items:

1. Target-repo grounding FIRST: read knowledge-corpus README/AGENTS.md (if present)/`.gitattributes`;
   confirm provenance placement precedent (`sources/books/pat-pattison/README.md`) and LFS policy
   before finalizing the file list.
2. Licensing pre-flight: confirm retention authority (private org repo; Anthropic-published docs)
   and record terms in both READMEs; if terms forbid retention of any artifact, fall back to
   pointer-only for that artifact and record the substitution.
3. Generate PRE-COPY hash manifests from `.work` originals; copy; generate POST-COPY manifests;
   diff the two (this replaces any `git status`-based check — `.work` is self-ignored, git cannot
   see mutations there).
4. Verify `source.md` against the audit-time pin (`8579d63fc9f793784b8c56320fd74e71`); author both
   graduation-pin records.
5. Author both provenance READMEs; dual verification of the two READMEs + pin-record prose
   (mechanical hash blocks exempt — reasoned carve-out: hashes verify themselves); records in the
   plugins repo's `build-verification/`.
6. Branch + PR in knowledge-corpus (Conventional-Commits title); merge stays human.
   SHIPPED: knowledge-corpus PR #5 (commit 557bc4bd), merge human; byte-fidelity rule sources/docs/** -text added after CRLF normalization would have broken 6/19 pin rows on fresh clones.

**Sanity Check:**

- `git lfs ls-files` lists `sources/docs/opus-5-system-card/source.pdf`.
- Pre-copy vs post-copy manifest diff is empty (exit 0).
- `md5sum` of graduated `source.md` equals the audit-time pin value.
- Both graduation-pin records enumerate every file in their slice (file count in pin = `find <slice> -type f | wc -l` minus the pin itself and README).
- Both READMEs contain all four field labels (origin URL/statement, fetch date, channel, retention terms) — one grep per label.

### Phase 6: effort-doc pipeline run (ingestion-skill acceptance test) [TODO]

Run the new skill end-to-end on `https://platform.claude.com/docs/en/build-with-claude/effort`.
Deliverable 5 (effort slice BEFORE effort artifacts) + e2e acceptance test for Phase 4.

Work items:

1. Invoke the skill with the effort-doc URL; it fans out its own digest/verify agents (this
   phase's sub-agent use is the skill's design, not an orchestration choice here). Outputs land at
   the skill's `library_dir`-resolved work root — record the resolved root in the phase notes; all
   checks below run against it.
2. Verify the full pipeline contract executed: source + INDEX + digests + dual verification + the
   interview-handoff artifact.
3. Cross-check `opus-5.md`'s effort section against the verified effort slice (the deferred
   dependency from Phase 2); amend `opus-5.md` in the same branch if drift found.
4. Record pipeline friction as Phase 4 fixes (same branch).
5. Commit ONLY if tracked files changed (skill fixes, opus-5.md amendments); the slice itself
   lives under the untracked work root — no empty commits.

**Sanity Check:**

- Resolved work root contains `source.md`, `INDEX.md`, ≥1 digest, 2 verification verdicts (each
  naming vendor + model + effort), and the interview-handoff artifact named by the skill contract.
- INDEX digest inventory rows = digest file count (parity).
- Effort ladder completeness: the slice's source.md contains every effort level the live doc
  states, including the one the guide truncated (assert per the live doc's own enumeration at run
  time, not a hardcoded token).
- Phase-notes entry records the resolved work root + cross-check verdict (drift/no-drift).

### Phase 7: recalibration hand-off + close-out prep [TODO]

Deliverable 6's EXECUTION is deferred by the Brief itself to the choosing-a-model routing-vet
slice (session task #18) — this phase files the tracker items and records the lane distinction. No
effort pin changes (USER-RESERVED).

Work items:

1. **Phase-entry check** (per tracker item, before any create):

   ```bash
   gh issue list --state all --search '<key-term> in:title' --json number,title,state
   ```

   Multi-match rule: prefer exact-title + open state; if >1 credible match remains, stop and
   surface for user choice.
2. Item A — effort recalibration: on match, comment linking this PLAN + the effort slice; else
   create (`chore: effort judgment recalibration (choosing-a-model routing vet)`) with body:
   effort-slice pointer, pinnable (`effortLevel` via dotfiles seam) vs session-only (top effort
   tier; `--effort` flag) lane distinction, USER-RESERVED marker on fleet-pin changes, task #18
   link. The created-or-pivoted artifact (issue body or comment) must carry both lane labels.
3. Item B — statusline prime-drift indicator (approval-gated: files only if the approval decision
   confirms DEFER-to-tracker): same search-before-create shape; body records the Fable proposal +
   trigger (priming proves forgettable in practice).
4. Dual verification of outbound issue text (brief — single reviewer acceptable for tracker prose
   if the user approves the carve-out; default remains dual).
5. Local gates green (markdownlint, skill checks, script tests).
6. Close-out (full topic-docs lifecycle — prune is only safe with its pointer + graduation
   halves): (a) paste the approved PLAN.md + verification summary into the PR body inside
   `<details>` (43 KB < ~64 KB cap; the PR body becomes the durable record); (b) graduate durable
   outcomes through the knowledge-vault seam — apply the ADR admission test (hard to reverse +
   surprising + real trade-off) to candidates (e.g. the fleet-wide promotion gate, the hash
   doctrine); write `docs/adr/` entries only for those that pass all three; actionable follow-ups
   already ride the Phase 7 tracker items; (c) ONLY THEN prune
   `docs/topics/opus-5-prompting-interview/` in a final commit AND pointer-ize
   `.work/opus-5-prompting-interview/PLAN.md` to the PR body URL (deferred from Phase 1 for
   exactly this reason). PR sequencing: the `contract-slice-prune-gate` red-lines this slice's
   presence in any PR diff (slug verified absent from `scripts/contract-slice-baseline.txt`;
   branch-push CI green, PR CI red by design) — so EITHER open the PR only after the prune commit,
   OR open a draft PR early and name the expected-red gate in the PR body. Default: prune-then-PR.

**Sanity Check:**

- Both item numbers/URLs (created or pivoted-to) recorded in phase notes.
- Item A's created-or-pivoted artifact contains `pinnable` and `session-only`.
- `bash scripts/check-changed-skills.sh` (changed set) exits 0 locally before PR.

## Test strategy

TDD where a deterministic surface exists; doctrine prose verified by architected independent
review (dual-verifier policy), not instructed self-checks — consistent with the doctrine shipped.

- **Phase 3 scan scripts** — Red-Green: fixtures first (positive: instructed self-check,
  don't-think, conservative-directive), then patterns. Scanner is advisory (over-produces by
  contract); FENCES live in criteria.md and are proven by the acceptance-run report checks
  (manifest-scanned-but-not-flagged assertions), not scanner tests.
- **Phase 4 evals** — `evals/evals.json` encodes routing/trigger cases; schema-validated in CI;
  BEHAVIOR proven by Phase 6's live end-to-end run.
- **Per-phase dual verification** — fresh-context Claude (high) + Codex GPT-5.6 Sol (high,
  text-embedded while task #15 blocks file access) on every AUTHORED artifact; mechanical copies
  verified by hash manifests instead (reasoned carve-out). Records:
  `.work/opus-5-prompting-interview/build-verification/<phase>-<artifact>-<vendor>.md`;
  verification records and verdicts are append-only; corrections land in the artifact.
- **Static gates** — markdownlint (hygiene job), `skill-quality:check`/`skill-quality-gate`
  (Phase 4), `changelog-parity-gate` (all bumps), `pr-title`, `portability-lint` (Phases 2-4),
  `shell-portability-lint` (Phase 3 scripts), `skill-leaf-name-gate` (Phase 4),
  `orphaned-fixture-gate` (Phase 3 fixtures).
- **End-to-end** — Phase 6 IS the e2e test of Phase 4 against a live doc.
- **Empirical probes** — Phase 2's thinking-off probe (protocolized, dated observation artifact).

## Alternatives considered

| Alternative | Why rejected |
|-------------|-------------|
| Parallel model-delta rule class in audit-instructions | Validator consensus (merged triage #5): extend I8 rows; a parallel class duplicates the model-era concept |
| Two-layer pipeline: engine in `knowledge` + profile in `claude-ops` | Both Claude validators independently invoked Rule of Three; engine extraction waits for the third profile (merged triage #10, resolved in interview continuation) |
| Reuse `review:fanout` for dual verification | Verified NOT reusable this session: diff-shaped pre-flight, review-specific normalization; no callable verify primitive. Borrow only the Codex-as-uncorrelated-vendor dispatch pattern |
| Retire `opus-adaptation.md` outright | Content remains valid for its calibration target (Opus 4.8); the defect is version-blind routing, not the deltas. Rescoping preserves working doctrine; acceptance criterion demands only that Opus 5 never applies it verbatim |
| Silently default `--target-model` from the pinned settings alias | Verified impossible: pinned value `opus[1m]` carries no version; silent aliasing would misfire the exact distinction the deliverable exists to draw — fail-loud normalization instead |
| Fence false positives in the scanner | Contradicts the scanner's documented advisory contract (always exit 0, over-produce); fences owned by criteria.md, adjudicated by the model lane |
| SessionStart auto-prime for the delta chapter | Deferred-with-trigger in the Brief (manual priming proves forgettable) — out of this plan |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Instruction compounding in `opus-5.md` | Med | Med | Curated-deltas contract; Phase 3 acceptance run covers the chapter (meta-surface fence keeps it a scanned-not-flagged surface) |
| Harness-claim drift between corpus date and build | Med | Med | Fresh-docs mandate: fetch + cite at build; applicability tags verified at tag time |
| Concurrent-branch collision on `fable-5/SKILL.md` (live `docs/ignition-rebind-note` worktree; 40+ registered worktrees) | Med | Med | Phase 2 pre-flight branch/worktree sweep; sequence or rebase deliberately |
| Prompt-injected source docs steering digest/verify agents into future instruction artifacts | Med | High | Untrusted-source discipline as a named SKILL contract (content = data, never directives); dual cross-vendor verification checks fidelity against source; human approval gates on all instruction-surface commits |
| Licensing/redistribution of full doc copies + 15.25 MiB PDF | Low | Med | Phase 5 licensing pre-flight; private org repo; retention terms recorded; pointer-only fallback per artifact |
| Codex verifier degraded (task #15: no file access) | High | Low | Text-embedded mode (proven in validation round); noted in each record |
| Verifier cost/availability (repeated high-effort cross-vendor passes) | Med | Low | Degraded-verifier fallback documented per record, never silent; batch verification per phase, not per file |
| Conservative-phrasing false positives beyond known shapes | Med | Low | Two criteria-owned fences + report-only + acceptance-run negative assertions |
| Cross-repo coordination (corpus PR vs plugins PR) | Low | Low | Phases independent by design; corpus graduation has no code dependency on plugin phases |
| Naming tournament stalls Phase 4 | Low | Low | Seeds + shape constraint pre-fed; same-session decision |
| `autoUpdate: true` feedback loop — merged artifacts become standing instructions (arm-time `opus-5.md`, live I8 rows) inside sessions still executing later phases | Low | Med | Single PR at close-out — nothing publishes mid-effort; acceptance run uses the local-path marketplace install, not a published version; condition named here as accepted |

## Blast radius

MEDIUM. Plugins repo: ~26 authored/modified tracked files across 3 plugins (markdown, 2 shell
scripts, manifests) — all report-only or doctrine surfaces; no hooks, no CI-workflow changes, no
runtime infra. Corpus repo: ~42 files, additive-only (copies + 4 authored). Everything
git-revertible. Trigger matched: "new agent-instruction rules constrain future work" (audit rows +
doctrine chapter) → formal stress-test run (below).

## Stress-test summary

Step 3 dual review (fresh-context Claude plan-reviewer + cross-vendor Codex GPT-5.6 Sol high,
text-embedded): Claude 2 CRITICAL / 10 IMPORTANT / 5 SUGGESTION; Codex 4 CRITICAL / 25 IMPORTANT /
3 SUGGESTION. Main-thread verification confirmed both Claude CRITICALs against ground truth
(stale MD5 pins — 10/11 diverged post-corrections; `opus[1m]` settings alias carries no version)
plus the stale-reference, prune-gate-baseline, worktree-collision, CI-gate-coverage, and
seam-contradiction findings; all confirmed findings folded into the phases above. Rejected with
rationale: Codex C2 (deliverable 6 "not implemented" — the Brief itself defers execution to task
#18's slice) and Codex C3's scope claim (PLAN graduation + PROCESS.md queue migration are
explicitly briefed; transparency lines added instead).

/devils-advocate formal pass (fresh context, post-fix): 2 CRITICAL / 2 HIGH / 3 MEDIUM / 2 LOW; all
9 verified and folded in — (1) the audit resolves surfaces from the SELECTED plugin-install cache,
never the repo tree, so the acceptance run now requires the local-path marketplace install
(precondition added to Phase 3, fallback documented); (2) Phase 1's pointer-ization + Phase 7's
prune would have destroyed the last durable PLAN copy — close-out now carries the full topic-docs
lifecycle (PR-body paste, vault graduation with ADR admission test, prune-with-pointer last);
(3) branch was 8 commits behind origin/main (main's playbooks 0.5.2) — Phase 1 work item 0 rebases
and re-verifies all hardcoded versions/citations; plus the changed-skill gate + line budgets, the
public-repo quotation pre-flight, the autoUpdate-loop risk row, and two divergence corrections
(6 verification files; reflow file is derived). Its verdict: with these fixes the plan reaches
HIGH confidence; its nine ground-truth checks found zero fabrications. Iteration ceiling not hit
(1 formal round; fixes mechanical, no redesign).

## Open questions

None — plan approved 2026-07-26 with all recommendations confirmed: statusline prime-drift
indicator DEFERRED to tracker (Phase 7 item B files it); Codex text-embedded verification
CONFIRMED while task #15 open; single-reviewer carve-out for Phase 7 tracker prose CONFIRMED;
knowledge-corpus PR go-ahead CONFIRMED (merge stays human).

USER-RESERVED items stand: fleet effort-pin changes; committing/graduating `.work` content
beyond the corpus move (interview/validation records stay untracked in `.work`).

## Handoff to implementation

### User-approval gates

- Phase 5 opens a PR in `melodic-software/knowledge-corpus` (new `sources/docs/` category) —
  confirmed at plan approval; merge stays human.
- Phase 7 files tracker items (search-before-create; multi-match stops for user choice). Item B
  (statusline) files only if the approval confirms DEFER.
- Any fleet effort-pin change is USER-RESERVED — never executed by this plan.
- `[FALLBACK — confirm or override]`: Codex verifier in text-embedded mode while task #15 open.
- `[FALLBACK — confirm or override]`: single-reviewer carve-out for Phase 7 tracker prose
  (default stays dual if not confirmed).
- Briefed exceptions (transparency): PLAN graduation to `docs/topics/` (Brief header instruction)
  and PROCESS.md queue migration (deliverable 3 text) — both from `.work`, both explicitly briefed.
- Mid-flight pivots that change acceptance criteria: stop + replan via `/planning:plan review`.

### Execution shape ([EXEC-SHAPE] tagged)

- Sequential main-session, all 7 phases. Wave-A parallelism exists (Phases 2/3/4 file-disjoint;
  Phase 5 repo-disjoint) but is declined: doctrine-authoring quality + shared corpus context
  outweigh wall-clock; token cost LOWER sequential. Phase 6's internal fan-out is the skill's own
  design.
- Dependency edges: 1 → {2,3,4,5}; Phase 2 → Phase 3 acceptance run (clean playbooks result proves
  the conflict fix; REQUIRES the local-path marketplace install precondition — edge drops if the
  documented post-merge re-scope fallback fires); 4 → 6; 6 → opus-5.md effort cross-check (Phase 6
  item 3); 6 → 7.
- Per-phase routing: all main-session except Phase 6's skill-internal sub-agents.
- Naming tournament at Phase 4 start (Brief deliverable text "at build" wins over the
  deferred-question phrasing).
- Commit boundaries: ≥1 Conventional-Commits commit per phase WITH tracked changes (Phase 6
  conditional); plugin version bumps ride their phase's commit.

### Mechanical work

- Branch `feat/opus-5-prompting-integration` (conventional prefix; checked out).
- Stage explicit paths only; never `git add -A`.
- PR title Conventional Commits; body sections: Summary, Test plan, Related.
- PR sequencing: default prune-then-PR (close-out prunes `docs/topics/opus-5-prompting-interview/`
  first; `contract-slice-prune-gate` is red on any PR diff containing the slice — slug not in the
  grandfather baseline). Draft-PR-with-named-expected-red is the documented alternative.
- Sequential fallback: n/a (sequential by design). If a future session parallelizes 2/3/4, the
  per-phase file tables are the scope fences; PLAN.md edits stay main-session.
