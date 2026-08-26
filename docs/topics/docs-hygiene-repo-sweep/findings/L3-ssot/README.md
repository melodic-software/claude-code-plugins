# L3-ssot findings

Lane lead for `/docs-hygiene:extract-ssot`, wave 1, read-only. Corpus is the 1302 files in
`inventory/manifest.tsv`.

## Headline

The corpus has **already been through this lane**. `plugins/docs-hygiene/skills/extract-ssot/context/lessons.md`
records a whole-repo `extract-ssot` batch executed 2026-08-15 (clusters C01 through C25) and a
replay of it, and the fleet CHANGELOGs record the result in 41 plugins. Most of what a duplication
scan finds here is that batch's deliberate output, not a defect.

The dominant reason is a doctrine this repository has written down and this lane must respect:
**plugins ship to consumers who do not have the marketplace repository, so a contract is carried
inline at every adopting site and the citation is provenance-only.** Stated at
`docs/conventions/untrusted-content/README.md:34`, generalized as `context/lessons.md` "Lesson 13".
Against a plugin runtime surface, `trim-to-citation` is structurally unavailable: the target is
unreachable at runtime. The available remedies are `normalize-wording` and `name-an-owner`, both of
which this sweep's rule-of-one policy already prefers.

So this lane's yield is not size reduction. It is **drift elimination and named ownership**, in
places where the fleet's own inline-carry pattern was applied incompletely or not at all.

## Roster by bucket

| Bucket | Clusters | Instances rostered | Clusters remediated | Clusters refused |
|---|---|---|---|---|
| N>=3 | 19 | ~337 | 7 | 12 |
| N=2 | 6 | 14 | 5 | 1 |
| N=1 | 1 | 1 | 1 | 0 |
| **Total** | **26** | **~352** | **13** | **13** |

**No cluster proposes a new SSOT artifact.** Every remedy is an in-place fix against a file that
already exists. Detail in "New-artifact decisions" below.

### N>=3, remediated

| # | Cluster | Instances | Existing owner | Remedy | ROI |
|---|---|---|---|---|---|
| 1 | `lane-telemetry-upsert` | 3 | `plugins/claude-ops/skills/lanes/SKILL.md` "Never pass a body as an `@path` string" | `name-an-owner` + `normalize-wording` | HIGH |
| 2 | `dynamic-context-git-preamble` | 44 (26 edited) | none; propose `docs/PLUGIN-PHILOSOPHY.md` "Inline-template conventions" | `normalize-wording` + `edit-existing-rule` | MED-HIGH |
| 3 | `setup-probe-dont-recite` | 17 | `docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" (clause absent) | `edit-existing-rule` | MEDIUM |
| 4 | `setup-headless-reconfigure-recipe` | 22 (6 edited) | `docs/PLUGIN-PHILOSOPHY.md` "Configuration ownership and scope" | `normalize-wording` | MEDIUM |
| 5 | `detector-findings-producer-preamble` | 4 | `docs/conventions/detector-findings/README.md` (fetchable URL) | `normalize-wording` | MEDIUM |
| 6 | `songwriting-persistence-block` | 9 | `plugins/songwriting/context/pat-pattison/research/artifact-persistence.md` | `trim-to-citation` | MEDIUM |
| 7 | `setup-never-writes-boundary` | 41 (34 edited) | `docs/PLUGIN-PHILOSOPHY.md` "Configuration ownership and scope" | `normalize-wording` | LOW |

Cluster 6 is the only `trim-to-citation` in the lane, because it is the only N>=3 cluster whose
owner sits inside the same plugin as its call sites.

### N=2, remediated

| # | Cluster | The two files | Owner declared? | Remedy | ROI |
|---|---|---|---|---|---|
| P1 | `statusline-shim-durable-wiring` | `context-guard` / `rate-limit-guard` setup skills (+ READMEs) | no, and the scripts have already drifted | `name-an-owner` | HIGH |
| P3 | `toolchain-remote-resolution-snippet` | `toolchain:check` / `toolchain:lint` | no | `name-an-owner` | MEDIUM |
| P4 | `prototype-throwaway-constraints` | `prototype:explore-directions` / `prototype:pressure-test` | no | `name-an-owner` | MEDIUM |
| P5 | `github-read-only-posture` | `github:advise` / `github:audit` | no | `name-an-owner` | MEDIUM |
| P6 | `marketplace-bootstrap-placeholders` | `dometrain` / `miro` setup skills | no | `edit-existing-rule` + `normalize-wording` | LOW-MED |

### N=1, remediated

| # | Cluster | Site | Canonical home | Remedy | ROI |
|---|---|---|---|---|---|
| 1 | `planning-setup-uncited-reconfigure-recap` | `plugins/planning/skills/setup/SKILL.md:120-141` | `docs/PLUGIN-PHILOSOPHY.md`, two headings | `normalize-wording` + add provenance citation | HIGH for its size |

Admission gate satisfied: a canonical home exists, and this is the only setup skill in the fleet
carrying the reconfiguration block with no citation to it anywhere in the file. Verified by
scripted set difference over all 51 setup skills.

### Refused

13 clusters, roughly 197 instances. Full evidence in `refused-deliberate-duplication.md` plus two
refusals recorded inside their concept files.

| Cluster | Instances | Refusal ground |
|---|---|---|
| `plugin-lifecycle-artifact-protocol` | 6 | registered cluster, CI check `validate-plugin-contracts.mjs` |
| `standards-contract-mirror` | 3 | registered cluster, CI check `sync-standards-contract.sh` |
| `plugin-options-generated-block` | 34 | generator-owned, `sync-plugin-options-docs.py` |
| `fleet-changelog-entries` | 64 | per-plugin historical record |
| `untrusted-content-spine` | ~18 | convention mandates inline carry, with a conformance sweep |
| `rate-limit-guard-floor-inline` | 4 | declared inline-floor rule, provenance-only citation, byte-identical |
| `autonomy-routine-axis-scaffolding` | 10 | every row cites its owner; per-identity table data; no drift |
| `discovery-agents-tool-honesty` | 3 | locked by `plugins/discovery/agents/tool-honesty.test.sh` |
| `topic-docs-plugin-slices` (+ the discovery/verification setup pair) | 12 | cited convention slices; the pair carries a recorded prior refusal |
| `formatter-readme-requirements` | 12 | EXPOSE surface, primary-source URL, no drift |
| `commit-convention-well-known-path` | 4 | template-owned, byte-identical to the emitting template |
| `setup-write-vs-session-effect` | 18 | 17 of 18 already carry a document-scope citation |
| `songwriting-author-seam` | 9 | 9 of 9 already cite by exact heading |

## New-artifact decisions

**Zero clusters propose a new SSOT artifact.** Three passed the Rule of Three and were still
resolved in place. Recording why, since the brief asks:

**`dynamic-context-git-preamble` (44 instances).** The largest N>=3 cluster with no owner. Refused a
new artifact on two grounds. First, file class: these are `!` shell injections that Claude Code
substitutes at skill load, so there is no include mechanism a rule file could replace. Second,
reachability: a rule under `docs/conventions/` cannot be read by an installed plugin, so the text
stays inline at all 44 sites regardless and a new file would buy a name and nothing else. The
in-place fix, one canonical fallback string, corrects a live mislabel (`echo "clean"` on a failed
`git status`) at 15 sites. An `edit-existing-rule` addition to `docs/PLUGIN-PHILOSOPHY.md` is
proposed alongside so future authors have a stated home.

**`setup-probe-dont-recite` (17 instances).** No owner states the rule. Routed to
`edit-existing-rule` rather than a new rule file because all 17 sites already cite
`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" at document scope. Adding a clause to
the contract they already name is strictly better than minting a second contract they would then
also have to name.

**`lane-telemetry-upsert` (3 instances).** Rule of Three met, real divergence found, and still no
new artifact: `plugins/claude-ops/skills/lanes/SKILL.md` already licenses the inline form and is the
natural place to name its canonical text. The repository already runs this exact pattern
successfully for the rate-limit floor in the same three files.

## Method, and what it did not reach

**Instrument.** Two mechanical passes over the 1302-file manifest, both written and run this
session. Scripts are in the session scratchpad, not committed.

1. **Normalized-line frequency.** Every line stripped of list markers, heading hashes, blockquote
   markers, and inline emphasis, lowercased, whitespace-collapsed. Lines of 8 or more words
   appearing in 2 or more distinct files. Result: **1885 repeated lines, 771 of them in 3 or more
   files.**
2. **Maximal repeated-block detection.** For each file, grew maximal runs of consecutive normalized
   lines that appear identically in at least one other file, keeping runs of 2 or more lines and 20
   or more words. Generated-content regions (between `ai-slop-ignore-start` / `BEGIN GENERATED`
   markers) were blanked before matching. Result: **364 repeated blocks across 2 or more files**,
   the largest being 1930 words in 3 files.

Every candidate was then promoted to Tier 0 by hand: a discriminating-phrase grep this session, a
read of the surrounding context to establish citation state, and an SSOT-existence check. Where the
verdict turned on drift, exact variants were enumerated by grep or `md5sum` rather than asserted.

### Recall limits, stated plainly

- **Pass A is literal only, over 4-word normalized lines.** It finds verbatim and near-verbatim
  reproduction. It will miss a paragraph that asserts the same rule in wholly different words with
  no shared 4-word run.
- **Pass B, semantic clustering, was partial.** The method calls for reading-driven clustering
  across a pre-seeded concept axis list. I ran it against the axes the literal pass surfaced
  (setup contract, configuration ownership, untrusted content, rate-limit floor, telemetry,
  topic-docs, detector findings, commit convention, repository-context preamble) and against the
  `docs/conventions/` registry, 27 convention directories, checking each for consumers that restate
  rather than cite. **I did not read every one of the 1049 T3 files.** A semantic cluster whose
  members share no vocabulary with any convention directory name and produced no literal match
  would not have been found.
- **Hard-wrapped prose defeats line-level matching.** Two files stating the same sentence with
  different line breaks share no normalized line. The block pass mitigates this only where the
  wrapping happens to agree. This is a real and unquantified recall hole in a corpus that wraps at
  roughly 100 columns throughout.
- **Tables and code fences were matched as ordinary lines.** A table whose rows were reordered, or a
  fenced block re-indented, would not cluster.
- **CHANGELOGs were excluded from the block pass** (`NOCL=1`) after the line pass established that
  they dominate the signal with historical-record duplication. They were counted in the line pass
  and are rostered as one refused cluster. A genuine non-changelog duplicate that appears only in
  CHANGELOGs would have been missed.
- **The `plugins/songwriting/context/pat-pattison/research/**` tree was scanned but not analyzed.**
  Twelve repeated passages were found there and dropped as distilled external teaching material.
- **No fan-out.** The brief asked for one worker per concept cluster, capped at four concurrent.
  **This session exposes no subagent-dispatch tool.** `ToolSearch` returned no `Task`-equivalent;
  the only spawn mechanism available is `create_session`, which would start sibling cloud sessions
  with no shared working tree. I verified every cluster myself instead. The practical consequence is
  breadth: a single verifier working serially reached 26 clusters, where four parallel workers
  would have gone deeper into the long tail of the 364-block roster. **Roughly 200 of the 364 blocks
  are pair-level overlaps below 70 words that I triaged by first line and did not individually
  verify.** Most are almost certainly form (g) or form (h), but that is a judgment from the roster,
  not from Tier 0 evidence, and it should be read as such.

### What would improve recall on a re-run

A shingled n-gram pass over whitespace-normalized text with line breaks removed entirely, rather
than line-anchored matching. That is the single change that would close the hard-wrap hole, and it
is what I would run first with more budget.

## Wave 3 sequencing

**Hot files.** These carry findings from more than one cluster and must not be edited by two
workers in parallel:

| File | Clusters touching it |
|---|---|
| `plugins/*/skills/setup/SKILL.md` (about 45 files) | setup sub-clusters 1, 2, 3, 4, 5 |
| `plugins/planning/skills/setup/SKILL.md` | setup sub-clusters 1, 2, 4, and the N=1 cluster |
| `plugins/source-control/skills/babysit-loop/SKILL.md` | `lane-telemetry-upsert`, P2 |
| `plugins/work-items/skills/work-loop/SKILL.md` | `lane-telemetry-upsert`, P2 |
| `plugins/work-items/skills/attend-queue/SKILL.md` | `lane-telemetry-upsert`, R6 |
| `plugins/context-guard/skills/setup/SKILL.md`, `plugins/rate-limit-guard/skills/setup/SKILL.md` | setup sub-clusters 1, 2, 4; P1 |
| `plugins/github/skills/advise/SKILL.md`, `plugins/github/skills/audit/SKILL.md` | P5, R5 |
| `docs/PLUGIN-PHILOSOPHY.md` | setup sub-cluster 3, `dynamic-context-git-preamble`, P6 |
| `plugins/docs-hygiene/skills/audit-noise/context/persist-findings.md` | `detector-findings-producer-preamble` |

**Suggested waves.**

- Wave A, sequential, single worker: all `docs/PLUGIN-PHILOSOPHY.md` owner additions (setup
  sub-cluster 3, the preamble convention, P6). Every later cluster cites this file.
- Wave B, parallel-safe, three workers: `lane-telemetry-upsert`; `dynamic-context-git-preamble`;
  `songwriting-persistence-block`. Disjoint file sets.
- Wave C, sequential, single worker: the whole setup-skill family (sub-clusters 1, 4, 5, and the
  N=1 residual) in one pass per file, because four sub-clusters touch the same 45 files.
- Wave D, parallel-safe, four workers: P1, P3, P4, P5, plus `detector-findings-producer-preamble`.

**Re-count before editing.** `context/lessons.md` "Lesson 14": L1 deletes files and L2 splits them
before this lane runs. Every instance count and line number in these findings is a snapshot taken
against the pre-sweep tree. Re-derive each cluster's site roster with a fresh grep at apply time and
explain every delta, rather than trusting these line numbers. Line numbers in particular will be
wrong wherever L2 has split a file.

## Cross-lane observations

Encapsulation issues, for L4, not decided here:

- `lane-telemetry-upsert` and P1 both propose provenance-only citations that name a path inside
  another skill's `reference/` or `skills/` body. Whether that is permitted, or whether the citation
  must route through a plugin-level public surface, is L4's call.
- P5 proposes replacing a restatement with a citation to
  `plugins/github/reference/browser-automation.md`, a plugin-level reference cited from that
  plugin's own skills. Confirm the direction is allowed.
- No external file was found citing a path inside a skill's private body as part of this lane's
  cluster work. That is not a clean bill of health for the corpus, only for the files I read.

Other lanes:

- `plugins/knowledge/skills/setup/SKILL.md:67` starts a continuation line at column 0 inside an
  indented list item, breaking the list. L5/L6.
- Two em dashes sit in instruction surfaces this lane touches:
  `plugins/mutation-testing/skills/audit/context/persist-findings.md:1` and `:5`. The
  `detector-findings-producer-preamble` remedy removes both as a side effect. Flagged so the fix is
  not applied twice.
- `plugins/skill-quality/skills/check/SKILL.md` runs 25 static checks over skills, including
  injection shell-declaration and precompute opportunity. None of them would catch the
  `dynamic-context-git-preamble` drift. A 26th check is worth considering; out of scope here.
- Three `code-extract-advisory` items are recorded in the cluster files: a drift check for the
  telemetry upsert trio, a registry decision for the statusline shim pair, and a drift check for the
  four emitted `.claude/source-control.md` copies. None is a docs-hygiene edit.

## Files in this directory

| File | Contents |
|---|---|
| `README.md` | this roll-up |
| `plugin-setup-contract-recaps.md` | the uniform setup contract family: 4 sub-clusters at N>=3 plus the lane's only N=1 |
| `lane-telemetry-upsert.md` | the highest-value N>=3 cluster: a drifted, unowned, unguarded contract in 3 files |
| `dynamic-context-git-preamble.md` | 44 skills, 15 fallback-string variants, one canonical form |
| `detector-findings-producer-preamble.md` | 4 producer slices, 4 drift points, one canonical preamble |
| `songwriting-shared-blocks.md` | the lane's only `trim-to-citation`, plus one refusal |
| `paired-contract-recaps.md` | the N=2 bucket: 6 clusters, 5 remedied by naming an owner |
| `refused-deliberate-duplication.md` | 13 refusals with the evidence that refuses each, so nobody re-opens them |
