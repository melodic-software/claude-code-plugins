# Docs-hygiene repo-wide sweep

Coordination plan for running all eight `docs-hygiene` skills against the whole tracked markdown
corpus in one change set.

## Corpus

`inventory/manifest.tsv` is the single source of truth for what is in scope. Columns:
`group`, `tier`, `audience`, `bytes`, `path`. Regenerate it, never hand-edit it.

1302 files, ~17.0 MB. Scope is every tracked `.md` **except**:

- `plugins/*/skills/*/vendor/**` (22 files). Upstream reference material, excluded by
  `.claude/rules/vendor-docs-are-not-style.md`.
- Everything under `docs/topics/docs-hygiene-repo-sweep/`, this sweep's own artifacts. A lane
  that audited its own findings would feed on itself.

### Load tier

Tier drives how much a finding is worth, because it sets how often the content is paid for.

| Tier | Meaning | Count |
|---|---|---|
| `T1` | Always loaded every session | 3 |
| `T2` | Loaded for the rest of a session once the skill or agent triggers | 250 |
| `T3` | On demand, free until something reads it | 1049 |

`T1` is three files: `AGENTS.md`, `CLAUDE.md`, `.claude/rules/vendor-docs-are-not-style.md`.
`AGENTS.md` is empty and `CLAUDE.md` is a single `@AGENTS.md` import, so the always-loaded budget is
already near zero. Report that as a finding if a lane wants to change it; do not treat it as a
defect by default.

### Audience

`AGENT` (994 files) routes to `write-for-agents` doctrine. `HUMAN` (308 files: plugin READMEs,
CHANGELOGs, `docs/**`, `prompts/**`, `SECURITY.md`) routes to `write-for-humans`. The audience
column is a starting classification, not a verdict. A lane that finds a misclassified file reports
the reclassification as a finding.

## Groups

Partitioned for cohesion, not for equal size: cross-file lanes need a whole plugin in one worker's
view. Sizes are uneven on purpose; workers subdivide large groups themselves.

| Group | Files | KB | T2 | Human | Plugins |
|---|---|---|---|---|---|
| `A-doc-quality` | 78 | 872 | 15 | 8 | `ai-slop`, `docs-hygiene`, `markdown-format`, `typos-format` |
| `B-cc-config-ops` | 130 | 2225 | 29 | 15 | `claude-config`, `claude-memory`, `claude-ops`, `context-budget`, `context-guard`, `guardrails`, `rate-limit-guard` |
| `C-vcs-repo` | 93 | 1766 | 17 | 11 | `disk-hygiene`, `github`, `repo-fleet-hygiene`, `repo-hygiene`, `source-control` |
| `D-work-planning` | 109 | 1308 | 28 | 14 | `implementation`, `planning`, `prototype`, `work-items` |
| `E-session-behavior` | 145 | 1735 | 38 | 11 | `adhd`, `autonomy`, `discipline`, `playbooks`, `session-flow` |
| `F-quality-verify` | 121 | 998 | 31 | 18 | `bugs`, `codebase-health`, `debugging`, `evals`, `mutation-testing`, `review`, `tdd`, `testing`, `verification` |
| `G-code-design` | 94 | 990 | 17 | 16 | `architecture`, `code-tidying`, `coupling`, `domain-driven-design`, `event-storming`, `improvement`, `naming`, `overengineering` |
| `H-knowledge-research` | 133 | 1268 | 32 | 21 | `ai-briefing`, `context7`, `discovery`, `dometrain`, `education`, `firecrawl`, `knowledge`, `miro`, `visualization`, `x` |
| `I-songwriting` | 106 | 2009 | 12 | 2 | `songwriting` |
| `J-toolchain-platform` | 137 | 1166 | 31 | 39 | `actionlint`, `bash-format`, `biome-format`, `computer-use`, `desktop-notification`, `eol-normalizer`, `go-format`, `instruction-placement`, `kindle-dedrm`, `machine-health`, `mcp-tools`, `playwright`, `plugin-quality`, `powershell-format`, `ruff-format`, `skill-quality`, `toolchain`, `wizard` |
| `K-repo-docs` | 89 | 1515 | 0 | 89 | `docs/adr`, `docs/conventions`, `docs/specs`, `docs/upstream`, `docs/` root |
| `L-docs-topics` | 57 | 1021 | 0 | 57 | `docs/topics/**` |
| `M-repo-root` | 10 | 141 | 0 | 4 | repo root, `.claude/`, `.github/`, `prompts/` |

The grouping is the default partition. Two lanes should ignore it and pick their own, because their
findings are cross-file by construction:

- `extract-ssot` partitions by **concept cluster**, since duplication crosses plugin boundaries.
- `audit-encapsulation` partitions by **cited skill**, since a violation is by definition an
  external file reaching into a skill it does not own.

## Lanes

One level-1 lead per skill. A lead owns its skill's judgment end to end: the audit, the remediation
spec, and the applied edit.

| Lane | Skill | Mutation class |
|---|---|---|
| `L1-derivability` | `/docs-hygiene:audit-derivability` | deletes files, converts docs to pointers |
| `L2-progressive-disclosure` | `/docs-hygiene:audit-progressive-disclosure` | splits files, creates spokes |
| `L3-ssot` | `/docs-hygiene:extract-ssot` | dedups across files, may mint SSOT artifacts |
| `L4-encapsulation` | `/docs-hygiene:audit-encapsulation` | rewrites citations |
| `L5-noise` | `/docs-hygiene:audit-noise` | in-file removal |
| `L6-compress` | `/docs-hygiene:compress` | in-file word-level trimming |
| `L7-write-for-agents` | `/docs-hygiene:write-for-agents` | in-file conformance rewrite (`AGENT` audience) |
| `L8-write-for-humans` | `/docs-hygiene:write-for-humans` | in-file conformance rewrite (`HUMAN` audience) |

`write-for-agents` and `write-for-humans` have no scan mode; they are authoring-time doctrine. Their
leads load the doctrine as a rubric and audit the corpus for violations of it, then apply
conformance fixes to their own audience slice.

## Waves

Eight agents editing 1302 shared files at once collide, and several lanes have real ordering
dependencies on each other. So the sweep audits first and applies second.

### Wave 1. Audit, all eight lanes in parallel, read-only

Every lane covers the full corpus and writes findings to `findings/<lane>/`. **No lane edits a
source file in wave 1.** A lane that wants an edit records it as a remediation spec.

### Wave 2. Reconcile

The orchestrator merges the eight findings sets into `remediation/per-file-plan.md`: one ordered
edit list per file, with exactly one owning agent. Cross-lane conflicts resolve by the wave 3
order below.

### Wave 3. Apply, in dependency order

Order is a real dependency chain, not a preference. Compressing a doc that a later lane deletes
wastes the work; rewriting a citation before a split targets a path that is about to move.

1. **`L1-derivability`**. Deletions and pointer conversions. Removing a file moots every other
   lane's findings against it.
2. **`L2-progressive-disclosure`**. Splits. Creates the file structure the next lanes cite.
3. **`L3-ssot`**. Dedup, over the post-split structure.
4. **`L4-encapsulation`**. Citation rewrites, over the final paths.
5. **In-file prose pass**. `L5` to `L8` merged into one pass, partitioned by file so exactly one
   editor touches any given file. Each editor applies that file's noise, compress, and
   audience-appropriate write-for-* findings together.

### Wave 4. Verify and ship

Fresh-context verifiers semantic-diff the edited files against their pre-sweep state. Then
`markdownlint-cli2`, `typos`, `editorconfig-checker`, and link checking. Then commit.

## Standing rules for every agent in this sweep

- **Latitude is full.** Deletions, splits, and new SSOT artifacts are all authorized. What is not
  authorized is an edit you cannot justify from the skill's own rubric.
- **Dedup prefers rule-of-one.** Report duplication at every multiplicity. Remedy single-consumer
  and pair cases **in place**, by citing the existing owner. That is the preferred outcome. Mint a
  new SSOT artifact only at three or more instances and only when you judge the artifact genuinely
  better than an in-place fix.
- **Never invent a finding to fill a quota.** A group with no findings reports none. Padding a
  findings file with `Tier 3` non-defects makes the reconciliation worse, not better.
- **Cite file and line.** Every finding needs `path:line` and a verbatim quote of the offending
  text. A finding that cannot be located cannot be applied or verified.
- **Vendor tree is off limits.** Do not read `plugins/*/skills/*/vendor/**` for style, and never
  edit it.
- **This repo's prose style** is `plugins/ai-slop/skills/audit/reference/rewrite-guide.md`. No em
  dashes in this repo's own instruction surfaces.
- **No fan-out is available.** Lane leads cannot spawn subagents. No `Agent` or `Task` tool exists
  in a subagent's context here and `ToolSearch` will not find one; `create_session` spawns a
  separate container with no access to this checkout, so it is not a substitute. Four lanes
  confirmed this independently before it was written down. The tree is two levels: orchestrator,
  then one lead per lane.

  Substitute corpus-wide mechanical detectors for fan-out, then apply judgment to the candidates.
  Every lane that has finished did exactly this and reached all 1302 files.
- **State recall honestly.** With no fan-out, every lane has one adjudicator for the whole corpus,
  so partial coverage is the expected outcome, not a failure. Name what you sampled rather than
  read, and what your mechanical pass could not reach. A silent cap reads as full coverage and
  corrupts the reconciliation. Sampling and saying so is good work; sampling and implying
  completeness is not.
