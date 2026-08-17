# progressive-disclosure-skill

## Brief

### TLDR

- New read-only audit skill `/docs-hygiene:audit-progressive-disclosure` in the docs-hygiene
  plugin: one findings taxonomy over a three-tier load-cost model (always-loaded /
  invocation-loaded / on-demand) covering both lanes of progressive-disclosure hygiene —
  finding oversized or mixed-concern instruction files worth splitting, and auditing existing
  hub/spoke structures for tier-appropriate relevance and pointer quality.
- Seven finding shapes across the two lanes: `oversize`, `mixed-concerns`, `tier-mismatch`
  (split-opportunity lane) and `blind-pointer`, `orphan-spoke`, `deep-nesting`, `missing-toc`
  (structure lane), with audit-noise-style Tier 1/2/3 semantics and per-shape treatment guidance.
- Architecture mirrors the `audit-*` family: deterministic `detect.sh` fact emitter + model
  judgment, shared clean-tree fallback participation, evals with fixtures, read-only (author
  applies every treatment edit).
- All thresholds are advisory and grounded in verified research
  (`.work/progressive-disclosure-skill/RESEARCH.md`, memory tier): 500-line SKILL.md cap
  ("approaching" is the trigger), 200-line CLAUDE.md target, two-band TOC treatment
  (>300 definite / 100–300 awareness, reflecting the official intra-Anthropic conflict),
  one-level pointer-depth rule, never flagging small single-file skills for lacking spokes.
- docs-hygiene bumps to 0.16.0 with the standard integration set.

### Goal

An author invokes `/docs-hygiene:audit-progressive-disclosure` on a file, directory, or corpus
and receives a deterministic, tiered findings report that (a) identifies instruction files whose
size, concern-mixing, or tier placement makes them worth splitting for progressive disclosure,
and (b) grades existing hub/spoke structures so that everything always-loaded is relevant to an
entire conversation and every spoke is reachable through a pointer good enough that an agent
pulls in exactly the file it needs when it needs it. The skill never edits; every finding
carries treatment guidance the author applies by hand.

### Constraints

- **Home and name locked**: docs-hygiene plugin, skill directory `audit-progressive-disclosure`
  (explicit over implicit — "disclosure" unqualified is ambiguous; no per-disclosure-type
  actions planned).
- **Read-only v1**: no Edit/Write/mutating Bash; a `split` action is deferred until real demand
  (audit-noise `relocate` precedent).
- **Corpus**: agent-facing instruction markdown only (CLAUDE.md/AGENTS.md, `.claude/rules/`,
  skill/agent/command bodies, their context/reference spokes, agent-facing docs). Non-markdown
  surfaces (MCP tool descriptions, hook config text) are documented out-of-scope. Human-facing
  docs are out of the tier model's cost claims.
- **Repo-agnostic with graceful degradation**: in a repo with no Claude Code configuration the
  tier classification collapses to on-demand and the size/mixed-concern lane still works.
- **Threshold posture**: advisory, tier-calibrated, never hard gates; consuming repos can refine
  via their own CLAUDE.md/rules (family convention).
- **Citation posture**: vendor-defined numerics (500/200/1,024/1,536/1%/~100 tokens/5k/25k) are
  cited as Anthropic-prescribed; "consensus" language is reserved for independently corroborated
  claims (hub/spoke value, tier costs, pointer discipline, depth/scale boundaries).
- **Research boundaries adopted as posture**: never flag a small single-file skill for lacking
  spokes (disclosure is a scaling tool); flag pointer chains deeper than one level from the hub.
- **Family conventions hold**: detect.sh + contract test mirroring sibling script conventions;
  shared clean-tree fallback (`context/clean-tree-fallback.md`) participation with a new row in
  its table; deterministic output ordering; opt-out markers respected where applicable;
  `skill-quality:check` and `validate-evals` must pass.
- **The when-NOT-to-use description clause** (community-sourced, happyskills) appears only as
  advisory color inside `blind-pointer` findings on skill descriptions, labeled as
  community-sourced — not a separate shape, not presented as official guidance.

### Acceptance criteria

- `plugins/docs-hygiene/skills/audit-progressive-disclosure/SKILL.md` exists with: trigger-rich
  description (progressive disclosure, split this file, hub and spoke, context loading, etc.),
  action router (default = audit), the 7-shape/2-lane taxonomy table with tiers and treatments,
  the load-tier model, hard rules (read-only, tier semantics, deterministic output), output
  schema (per-file load-tier header + tier table + batch aggregate), "What this skill is NOT"
  (boundaries vs compress/audit-noise/extract-ssot/audit-derivability/skill-quality), and a
  Sources section citing the official pages.
- `scripts/detect.sh` emits deterministic facts — per-file line/word counts, per-section sizes,
  heading census, load-tier classification (path + frontmatter), pointer inventory (outbound md
  links with surrounding-line context, when-clause presence signal), orphan-spoke detection,
  pointer nesting depth, TOC presence — and `scripts/detect.test.sh` passes, mirroring sibling
  test conventions.
- `evals/evals.json` validates against the marketplace schema with three fixture sets: an
  oversized mixed-concern instruction file (findings fire), a healthy hub/spoke skill (audits
  clean — false-positive guard), a broken hub/spoke (blind pointers + orphan spoke detected).
- Two-band TOC treatment implemented: reference file >300 lines without a TOC = Tier 1;
  100–300 without = Tier 3 awareness citing the official 100-vs-300 conflict.
- Shared clean-tree fallback: bare invocation on a clean tree offers (never auto-starts) a
  corpus run; `context/clean-tree-fallback.md` gains the skill's row.
- Integration set complete: docs-hygiene `plugin.json` at 0.16.0 with updated description +
  keywords, README skill-table row, CHANGELOG entry, marketplace.json docs-hygiene tags gain
  `progressive-disclosure`.
- Quality gates pass: `skill-quality:check` (all checks), `validate-evals`, detect.test.sh,
  repo linters (markdownlint, shellcheck via toolchain), on the designated branch
  `claude/progressive-disclosure-skill-b84q34`, committed and pushed.

### Captured assumptions

- The research artifact set (memory tier, uncommitted) remains available this session; the
  durable design facts it grounds are restated in this Brief and in the skill's own Sources, so
  the skill does not cite the memory slice (ghost-ref discipline).
- Load-tier classification can be derived cheaply from path + frontmatter heuristics
  (CLAUDE.md/AGENTS.md/unscoped rules = always; SKILL.md/agent/command bodies = invocation;
  context//reference//docs = on-demand); ambiguous files are classified by the model judgment
  layer, not the script.

### Out-of-scope

- Applying splits (`split` action) — deferred until demand.
- Non-markdown context surfaces (MCP tool descriptions, hook instruction text, agent
  frontmatter beyond tier classification).
- Skill-listing budget auditing (owned by `skill-quality:check` listing-budget) and description
  authoring QA (owned by `skill-quality:check`) — this skill cross-references, never duplicates.
- Human-facing documentation quality (READMEs, guides) beyond their role as spoke targets.

### Deferred questions

- None — all 16 interview questions resolved (register: 16 answered, 0 open/deferred/blocked).

## Plan

(To be filled by /planning:plan or direct implementation.)
