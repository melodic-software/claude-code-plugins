# Derivability route-to-sibling follow-ups (2026-08-15 sweep)

Durable tracking for the 174 route-to-sibling annotations from the repo-wide
`/docs-hygiene:audit-derivability` sweep (issue #2735 / session ledger
`derivability-ledger.json`, ephemeral). This file is the in-tree status board —
no new GitHub issues are opened from it.

## Batch record

| Pass | Date | Scope | Outcome |
|---|---|---|---|
| audit-noise re-scan | 2026-08-16 | all 38 noise-routed paths | 32 files scanner-clean under detect 0.14.5+ exemptions; 6 `CHANGELOG.md` basename-exempt; 1 Tier-2 ghost-ref remediated (commit-convention README → Sources) |
| extract-ssot triage | 2026-08-16 | all 136 ssot-routed paths | dispositions below; exact byte-identical `reference/artifact-protocol.md` cluster already registered in `scripts/cross-plugin-source-registry.txt` (keep-as-synced-copies, not pointer-extract) |
| false-keep sampling | deferred | 1089 `keep-owns-facts` from the original sweep | original session ledger ephemeral; future sweeps sample keeps per the post-#2695 contract — do not invent a one-off sample without the ledger |

## Route: audit-noise (38)

Disposition after the 2026-08-16 pass: **closed for scanner follow-up**. Line-level
noise the original sweep saw was largely false-positive under the pre-exemption
scanner; remaining real cite relocated.

| Path | Status |
|---|---|
| `CLAUDE.md` | clean |
| `docs/conventions/commit-convention/README.md` | remediated — design-topic ghost-ref moved to `## Sources` |
| `docs/conventions/config-cascade/README.md` | clean |
| `docs/conventions/ecosystem-commands/README.md` | clean |
| `docs/conventions/hook-observability/README.md` | clean |
| `docs/conventions/hook-telemetry/README.md` | clean |
| `docs/topics/context-engineering-claude-5/design/skill-inventory.md` | clean |
| `plugins/ai-briefing/skills/generate/references/build-pipeline.md` | clean |
| `plugins/ai-briefing/skills/generate/references/slide-generation.md` | clean |
| `plugins/architecture/CHANGELOG.md` | basename-exempt |
| `plugins/claude-ops/skills/known-issues/context/registry-schema.md` | clean (pointer-converted in #2695 — re-verified present) |
| `plugins/disk-hygiene/CHANGELOG.md` | basename-exempt |
| `plugins/domain-driven-design/README.md` | clean |
| `plugins/dometrain/README.md` | clean |
| `plugins/education/CHANGELOG.md` | basename-exempt |
| `plugins/education/README.md` | clean |
| `plugins/eol-normalizer/CHANGELOG.md` | basename-exempt |
| `plugins/eol-normalizer/README.md` | clean |
| `plugins/evals/CHANGELOG.md` | basename-exempt |
| `plugins/firecrawl/CHANGELOG.md` | basename-exempt |
| `plugins/knowledge/skills/youtube-digest/templates/sources.md` | clean |
| `plugins/knowledge/vendor/repo-analysis/README.md` | clean |
| `plugins/knowledge/vendor/video-digestion/TUNING.md` | clean |
| `plugins/machine-health/skills/audit/references/windows/check-catalog.md` | clean |
| `plugins/machine-health/skills/audit/references/windows/elevation-matrix.md` | clean |
| `plugins/mcp-tools/skills/audit/reference/server-discovery.md` | clean |
| `plugins/planning/reference/topic-docs.md` | clean |
| `plugins/planning/skills/draft-goal-condition/SKILL.md` | clean |
| `plugins/planning/skills/interview/context/session-config.md` | clean |
| `plugins/playbooks/skills/boris/SKILL.md` | clean |
| `plugins/songwriting/context/pat-pattison/research/ai-tools.md` | clean |
| `plugins/testing/README.md` | clean |
| `plugins/toolchain/skills/check/context/bash.md` | clean |
| `plugins/toolchain/skills/check/context/dotnet.md` | clean |
| `plugins/toolchain/skills/check/context/go.md` | clean |
| `plugins/toolchain/skills/check/context/python.md` | clean |
| `plugins/toolchain/skills/check/context/typescript.md` | clean |
| `plugins/typos-format/README.md` | clean |

## Route: extract-ssot (136)

Pragmatic triage (not a full Rule-of-Three extract pass). Categories:

### A — Keep as synced byte-identical cluster (registered)

Already enforced by `scripts/cross-plugin-source-registry.txt` +
`validate-plugin-contracts.mjs`. Pointer-extraction would break per-plugin
install copies.

- `plugins/{discovery,implementation,planning,verification}/reference/artifact-protocol.md`

### B — Functional artifacts / scaffolds (out of scope for dedup-into-prose-SSOT)

Per post-#2695 rubric: runtime checklists and similar scaffolds may duplicate
*shape* without being extract-ssot candidates into a shared prose SSOT.
Re-open only if two checklists are byte-identical and meant to stay that way
(then register like artifact-protocol).

- `plugins/**/templates/checklist.md` (planning, interview, session-flow,
  debugging, codebase-health, code-tidying, claude-config, source-control,
  work-items, …)
- `plugins/machine-health/skills/audit/scripts/{linux,macos}/NOT_IMPLEMENTED.md`
  (near-dup scaffolding; OS-specific on purpose)
- `plugins/claude-config/skills/audit/templates/checklist.md` and siblings

### C — CHANGELOG routes (changelog-parity before any dedup)

Do not collapse changelogs across concerns. Judge each against the
changelog-parity convention if a future pass revisits them.

- `docs/conventions/*/CHANGELOG.md` (finding-suppression, hook-telemetry,
  liveness-assertion, plugin-data-report-keying, standards)
- `plugins/mutation-testing/CHANGELOG.md`

### D — Pending extract-ssot candidates (not processed this batch)

Everything else on the original 136 list remains a **candidate** for a future
`/docs-hygiene:extract-ssot` identify pass (path/glob-scoped, not bare
whole-repo). Highest-leverage next slices when resumed:

1. Plugin README boilerplate clusters (format plugins, hygiene plugins) —
   similarity ~0.5–0.7, needs Rule-of-Three evidence before extract.
2. `plugins/docs-hygiene/skills/rename-references/context/{apply,audit,triage}.md`
   — same skill, likely progressive-disclosure not duplication.
3. Songwriting research/template prompt cluster — large; defer to a dedicated
   extract-ssot wave.
4. Autonomy setup templates — likely intentional variants.

Full original path list: GitHub issue #2735 (durable copy of the ephemeral
ledger). This file owns **status**, not a second full roster, so the two stay
aligned via the issue link rather than a duplicated 136-row table.

## False-keep sampling backlog

The completed sweep's 1089 `keep-owns-facts` verdicts were never sampled. The
contract now requires sampling keeps on future sweeps. A one-off 20-keep
fresh-context probe is blocked here because the session ledger is gone; do not
fabricate sample membership. Next full `audit-derivability` sweep must sample
keeps and record the sample set beside its ledger.
