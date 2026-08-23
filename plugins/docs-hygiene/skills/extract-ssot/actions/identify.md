# `identify` action — exhaustive duplication survey

## Contents

- [Two modes](#two-modes)
- [When to invoke](#when-to-invoke)
- [Multiplicity buckets](#multiplicity-buckets)
- [Inputs](#inputs)
- [Flags](#flags)
- [Exhaustive mode steps](#exhaustive-mode-steps)
- [Subagent prompt template](#subagent-prompt-template)
- [Output shape (exhaustive mode)](#output-shape-exhaustive-mode)
- [Targeted mode steps](#targeted-mode-steps)
- [Anti-patterns guarded](#anti-patterns-guarded)
- [Sanity checks](#sanity-checks)
- [Cross-references](#cross-references)

Default mode dispatches a read-only exploration subagent that runs 30+ duplication heuristics across all markdown surfaces, emits a ranked candidate roster, computes a file-overlap matrix, and returns a batch-sequencing recommendation ready to feed `/docs-hygiene:extract-ssot batch`.

Private surface — external consumers invoke `/docs-hygiene:extract-ssot identify`, never cite this file directly (contract: `/docs-hygiene:audit-encapsulation`).

## Two modes

| Invocation | Mode | Behavior |
|------------|------|----------|
| `/docs-hygiene:extract-ssot identify` | Exhaustive (default) | Read-only subagent deep survey across instruction files, rules, skills, agents, ADRs, docs. Returns a ranked candidate roster + dependency chains + file-overlap matrix + batch wave plan |
| `/docs-hygiene:extract-ssot identify` + confirmed path/glob scope | Exhaustive (path-scoped) | Same survey heuristics and roster shape as whole-repo exhaustive, but the subagent's search roots are the named directories / globs only (tracked markdown under that pathspec). Not a single-cluster grep |
| `/docs-hygiene:extract-ssot identify <cluster-name>` | Targeted | Tier 0 grep on a named cluster only. Returns instance count + Tier 0 evidence + suggested output type. No subagent dispatch |

User signals like "find ANY and ALL", "deep dive", "exhaustive", "full list", or `/docs-hygiene:extract-ssot identify` with no args = default to exhaustive mode. Path/glob scope from the confirm-scope gate (SKILL.md) keeps exhaustive mode and narrows roots — it does not switch to targeted.

## When to invoke

| Use case | Mode |
|----------|------|
| User asks for full duplication audit | Exhaustive |
| Maintenance / quarterly sweep | Exhaustive |
| User has one cluster in mind already | Targeted |
| Resume from working notes holding a candidate roster | Skip identify; route to `verify` / `plan` / `execute` / `batch` |

## Multiplicity buckets

`identify` rosters candidates at EVERY multiplicity. The Rule of Three gates which remedies a
candidate may be offered — never whether the candidate reaches the user. `N` is the count of full
reproductions under the evidence discipline below (discriminating-phrase grep for literal clusters,
reading-driven canonical-truth clustering for semantic ones) — not keyword density, not
section-header count.

| Bucket | What it means | Permitted `Suggested output` | Creates a new artifact? |
|---|---|---|---|
| **N=1** | An inline recap of an SSOT that ALREADY EXISTS — one consumer restates the canonical instead of citing it | `trim-to-citation`, `normalize-wording` | never |
| **N=2** | Source-of-truth bifurcation risk — two files assert the same contract and neither is the declared owner, so they drift | `edit-existing-rule`, `name-an-owner`, `normalize-wording` | never |
| **N≥3** | Rule of Three met | all of the above, plus `rule-file` / `new-skill` / `new-action` | only behind the 6-test gate (`context/decision-framework.md`) |

**The N=1 bucket is NOT "report every paragraph".** A lone paragraph with no existing canonical
home is not duplication — nothing is being duplicated — and is NOT rostered. The N=1 bucket admits
a candidate only when the SSOT-existence check finds a canonical home the site should be citing.
That precondition is what keeps a rule-of-one default from degenerating into report-everything.

**N=1 and N=2 candidates can NEVER be routed to `rule-file` / `new-skill` / `new-action`.** A
sub-three candidate carrying an artifact-creating suggested output is a roster defect; correct it
to the bucket's permitted set before emitting. `verify` Gate 1 refuses it independently
(`REFUSE-rule-of-three-fails`).

## Inputs

```text
/docs-hygiene:extract-ssot identify              # exhaustive default
/docs-hygiene:extract-ssot identify <cluster>    # targeted
```

## Flags

Read-only is the default. A bare invocation (no flags) rosters the buckets, reports, and stops —
it applies no edits. `batch` accepts the same flags and passes them through.

| Flag | Default | Behavior |
|------|---------|----------|
| `--min-instances=<N>` | `1` | Lowest bucket to roster. `--min-instances=2` drops the N=1 bucket; `--min-instances=3` is the **regression guard** — it reproduces the pre-bucket behavior exactly, rostering only N≥3 clusters and refusing sub-three candidates outright |
| `--buckets=<list>` | all | Comma-separated bucket filter applied to the roster, e.g. `--buckets=1,2` for the non-abstracting work only. Composes with `--min-instances`; the narrower of the two wins |
| `--fix` | off | Apply ONLY the non-abstracting remedies — `trim-to-citation` and `normalize-wording`. It NEVER creates a new artifact and never applies `name-an-owner` / `edit-existing-rule` (those change which file is canonical — a judgment call that stays with the user). Honors the per-bucket review gate unless `--yes` |
| `--dry-run` | off | Print the diff `--fix` would apply; write nothing. Implies no edits even if `--fix` is also passed |
| `--yes` | off | Non-interactive; skip the per-bucket review gate. Only meaningful alongside `--fix` |

**Per-bucket review gate.** With `--fix` and without `--yes`, present the proposed edits one bucket
at a time and take the user's decision per bucket before writing. This keeps the N=1 sweep — the
highest-volume bucket — from landing as one unreviewable diff.

## Exhaustive mode steps

```text
0. Scope gate: exhaustive mode needs an affirmative scope — an explicit argument/user signal, the
   SKILL.md "Bare invocation — confirm scope first" ask answered whole-repo, or that ask answered
   with named paths/globs (path-scoped exhaustive). Whole-repo large repos run the batch under
   `context/orchestrated-mode.md` defaults; path-scoped surveys inherit the same concurrency
   ceiling when they fan into verify/execute
1. Pre-flight: confirm no working notes with an active candidate roster (would imply resume, not new identify)
2. Dispatch a read-only exploration subagent with the survey prompt (template below)
3. Subagent searches markdown surfaces with 30+ heuristics (template lists them)
4. Subagent returns ranked candidate table + dependency chains + file-overlap matrix
5. Main session classifies output: assign each candidate its bucket from the instance count; apply
   --min-instances / --buckets; deduplicate against context/lessons.md known-refused patterns;
   downgrade any sub-three candidate carrying an artifact-creating suggested output
6. Main session emits batch-sequencing recommendation (waves, sequential vs parallel, hot files)
7. Main session offers user: dispatch /docs-hygiene:extract-ssot batch with top-N waves, or pick
   specific clusters. With --fix, walk the non-abstracting remedies one bucket at a time through
   the review gate (skipped by --yes); without --fix, report and stop
8. Persist the roster (buckets included) to working notes so the user can resume from durable state
```

## Subagent prompt template

The subagent receives a self-contained prompt. Skeleton:

```text
Goal: EXHAUSTIVE duplication survey for /docs-hygiene:extract-ssot. Find ANY and ALL duplication
candidates across markdown in this repo. Apply Tier 0 discipline — see
"Discrimination rules" below before adding any candidate to the roster.

Repo: <repo-root>

## Survey scope — git-tracked files only

Use `git ls-files` to enumerate the survey universe. EXCLUDE:
- Gitignored files (anything `git check-ignore <path>` returns exit 0 for)
- Ephemeral task/working-notes directories
- Vendored/third-party verbatim content (upstream copies, NOT repo authoring)
- Distilled external teaching material (course notes, book digests — content, NOT repo convention)
- Test fixtures and eval data (test inputs, NOT call sites)
- Run logs and other generated output
- Single-use / archived prompts

In-scope authoring surfaces (adapt to what this repo actually has):
- CLAUDE.md, AGENTS.md, README.md, and other root instruction files
- .claude/rules/**/*.md (incl. nested subdirectories)
- .claude/skills/**/*.md (SKILL.md, context/, reference/, actions/, templates/)
- .claude/agents/*.md
- Automation / routine / scheduled-agent prompts (NOT their run logs)
- ADRs and docs/**/*.md
- .github/**/*.md and per-tool markdown (contributor docs, tool READMEs)

## Discrimination rules

Each candidate MUST be classified by repetition form. Forms (a), (e)+(framing-only), and
(i) count as duplication candidates. Form (c2) full-paragraph semantic reword also counts
when the stability+reader-burden test passes.

A form's YES/NO decides whether the thing is duplication at all. The instance count then decides
the BUCKET, never whether the candidate is dropped: a YES at 1 or 2 instances lands in the N=1 or
N=2 bucket with that bucket's permitted remedies. A NO form is still discarded at any count.

| Form | Counts as duplication? | Example |
|------|------------------------|---------|
| (a) Verbatim block reproduction (≥15 words, copy-paste) | YES | The same dependency-direction rule text in 5 files |
| (b) Section-header presence (same `## X` heading, different body) | NO — convention/template | `## What this skill does NOT do` in 18 skills with unique non-goals each |
| (c1) 1-line teaching reference / single concept mention | NO | A verification tier mentioned once in a paragraph |
| (c2) Full-paragraph reword of same canonical truth (no verbatim ≥8 word phrase shared) | YES — semantic cluster; gate via stability+reader-burden test | 4 skills each restate the same session-hygiene rule in their own wording |
| (d) Correct citation to existing SSOT (`per X.md "Y"`) | NO — desired state | Citation IS the architecture |
| (e) Shared framing + per-instance unique data | BORDERLINE — extract framing IF stability+reader-burden test passes | 5 agents share an intro paragraph; only the examples differ |
| (f) Language-native dedup (bash `source`, Python `import`, MSBuild `<Import>`, JSON `$ref`) | NO — already extracted | 34 hooks `source hook-utils.sh` IS the dedup |
| (g) Per-instance unique scope-specific list (exclusion lists, allowed-file lists, etc.) | NO — content unique even when section-header shared | Per-prompt exclusion lists are scope-specific |
| (h) Domain-specific application of shared rule | NO — context-specific | Each skill applies a testing default in its own framing |
| (i) Semantic-paraphrase cluster — 2+ instances assert same canonical truth in different wording; no shared verbatim ≥8 word phrase but reader could not tell which is canonical | YES — roster iff stability OR reader-burden test passes | A commit-policy framing restated across the instruction file + 3 skills + 2 prompts in different words |

**Stability + reader-burden combined test — applies to forms (c2), (e), (i).** Roster iff EITHER:
- Changing the canonical truth would force updates in 3+ places in lockstep (maintenance burden), OR
- Reader cannot tell which instance is canonical (ambiguity)

If only ONE passes: borderline (mark WARN). If NEITHER: REFUSE-low-roi. At N=2 only the
reader-burden branch can pass — which is exactly the N=2 bucket's defect (no declared owner).

**Two-pass survey required.** Run BOTH:
- **Pass A — literal:** verbatim discriminating-phrase grep. Catches (a).
- **Pass B — semantic:** for each known canonical SSOT (the repo's rule files and
  always-loaded instruction files) AND for each topical concept the survey surfaces,
  read consumer files looking for paragraphs that restate the rule in DIFFERENT WORDS.
  Cluster by canonical-truth, not by shared phrase. Catches (c2), (e), (i).

Pass A alone systematically misses (c2)/(i).

## Per-candidate evidence requirement

For EACH candidate, capture (NOT optional). Use ONE of two evidence shapes depending on form:

**Literal shape (forms a, e):**

1. **Discriminating phrase** (≥8 words, verbatim, unique enough for clean grep)
2. **Reproduction count** = distinct files containing the discriminating phrase in form (a) or (e). NOT keyword density. NOT section-header count.
3. **Body excerpt** (first 2 reproductions verbatim) for human review

**Semantic shape (forms c2, i):**

1. **Canonical-truth one-sentence statement** — the single rule/fact each reproduction asserts in its own words
2. **Reproduction count** = distinct files whose paragraph reproduces the canonical-truth in any phrasing. Reading-driven clustering, NOT phrase-grep counting.
3. **Body excerpt** (first 3 reproductions verbatim — even though wording differs, capture each instance's actual phrasing so the reviewer can verify the semantic match)
4. **Stability+reader-burden test result** — note which test passes and why

**Both shapes also require:**

5. **Citation state** — for each match, is the surrounding context "inline reproduction" or "citation to existing SSOT"? Count separately. For semantic shape: a paragraph that BOTH restates AND cites is form (d) — count as already-cited.
6. **SSOT existence check** — does a canonical file already exist? If yes, what % of call sites cite it? If 100% cite → REFUSE-already-cites-canonical. This check is also the N=1 bucket's admission gate: a single site is rostered ONLY when a canonical home exists that it recaps instead of cites; with no existing home, a lone paragraph is not duplication and is dropped.
7. **Language-native check** — is the cluster a shared library, helper module, build-tool import, JSON $ref? If yes → out-of-scope.

A candidate without the appropriate evidence shape fields populated is REFUSED automatically.

## Heuristic checklist (Pass A literal + Pass B semantic):

**Pass A — literal grep aggressively (catches form a, partial e):**

1. Repeated paragraphs / sentences ≥15 words across files
2. Repeated H2/H3 section bodies (same heading + similar content)
3. Repeated tables (same column headers + overlapping rows)
4. Repeated code/command snippets (bash idioms, gh CLI, build/test commands, jq, git)
5. Repeated frontmatter patterns (same YAML fields/values across skills)
6. Repeated lists (same bullets across multiple files)
7. Inlined concepts that already have an SSOT in the repo (verification vocabulary,
   workflow primitives, naming schemes, citation form, encapsulation rule,
   frontmatter field tables, env var tables)
8. Cross-skill convention duplication (multiple skills restating the same primitive)
9. ADR cross-reference duplication (same ADR with same explanation in 3+ files)
10. Issue # / PR # / version qualifier patterns (same number cited identically)
11. Recheck-trigger row duplication (same condition + action across files)
12. Acronym / glossary repetition (domain term defined in N files)
13. Permission/auth setup steps (CLI auth, token env vars repeated)
14. MCP server registration patterns (config shape / wrapper repeated)
15. Hook authoring boilerplate (kill switch, exit codes, JSON schemas)
16. Environment-detection logic (CI / remote / non-interactive checks repeated)
17. Worktree or branch setup / lifecycle ritual repeated
18. Script headers (`#!/usr/bin/env bash`, `set -euo pipefail`, source utils)
19. Platform quirks repeated (Windows/shell gotchas restated per file)
20. Skill description trigger phrases that overlap
21. "What this skill does NOT do" boilerplate items repeated across skills
22. Citation text — `per X.md` patterns where the same X.md "<heading>" is cited in 3+ files
23. Test framework setup (framework pattern explanations repeated)
24. PR title / commit format explained in N places
25. Branch naming prefix tables / lists repeated
26. Effort/verbosity levels explained across skills
27. Model selection rationale repeated
28. Subagent dispatch boilerplate (preamble repeated)
29. Common error message / status interpretations repeated
30. Recheck-triggers / cross-references H2 boilerplate (structure-only)

**Pass B — semantic clustering (catches forms c2, i — REQUIRED, not optional):**

For Pass B, the SUBAGENT MUST do reading-driven clustering, not phrase grep. Method:

a. **Concept-axis enumeration.** Pre-seed by enumerating the concepts asserted in the
   repo's always-loaded instruction surfaces (CLAUDE.md, AGENTS.md, always-loaded rules) —
   those are the truths most likely to be restated elsewhere. High-likelihood reword
   targets in most repos:
   - Commit / stage / push policy (who commits, when, with what message shape)
   - Environment / session detection (CI vs local, interactive vs autonomous)
   - Merge mechanics and branch naming restated across workflow docs and skills
   - The repo's workflow-stage chain restated across multiple stage skills
   - Budget/limit conventions (token, time, size caps) restated across skills and rules
   - Commit-message or PR conventions across contributor docs, rules, and skills
   - Status/resume conventions for multi-session work restated across skills
   - Trust/verification discipline ("subagent output must be re-verified") restated
     across rules and skill bodies
   - Session-hygiene guidance (clear/compact between stages) across multiple skills
   - Cleanup-in-passing / Boy Scout rules across instruction files and skills
   - Response-formatting or side-observation limits across instruction files and agents
   - Per-prompt exclusion-list patterns (usually per-instance unique — form g, REFUSE —
     but check)
   - Hook/script authoring boilerplate across the rule that owns it + skills that author hooks

b. **For each concept above, sample 3-5 candidate consumer files and READ the relevant
   section** (not grep). Compare the paragraphs' assertions for semantic equivalence:
   - Same canonical truth asserted? → semantic cluster (form c2 or i)
   - Each file applies the rule to its own scope? → form (h) domain-specific application, REFUSE
   - Each file teaches the rule for its own audience with intentionally different framing?
     → intentional bifurcation, REFUSE

c. **Don't stop at the pre-seeded list.** As reading progresses, surface NEW concept axes
   the subagent notices being restated. Append them to the candidate list.

For EACH candidate cluster (both passes), capture:
- Cluster name (kebab-case slug)
- File list with line ranges where possible
- Instance count (full reproductions)
- Bucket: N=1 | N=2 | N≥3 — assigned from the instance count; MUST be emitted with every candidate
- 1-line description
- SSOT exists? (path or "no")
- Suggested output, constrained to the bucket's permitted set:
  - any bucket: `trim-to-citation` | `normalize-wording` (align divergent phrasings onto the
    canonical/agreed wording in place; no new file)
  - N=2 and up: `edit-existing-rule` | `name-an-owner` (declare one existing file the canonical
    owner and make the other cite it; no new file)
  - N≥3 only: `rule-file` | `new-skill` | `new-action`
  - any bucket, out-of-scope advisory: `code-extract-advisory` | `config-extract-advisory`
- ROI: HIGH / MEDIUM / LOW
- Dependency on other candidates (so batch ordering is clear)
- File-overlap (which other candidates touch same files — for batch sequencing)

**Existing-owner pre-check — route before suggesting a creation output.** Gate the `Suggested output`
field on the SSOT-existence check (the `SSOT exists?` capture field + per-candidate evidence item 6): if
an existing rule/skill/doc already owns the concept and ≥1 consumer still recaps it inline, suggest the
consolidation outputs — `edit-existing-rule` (extend the home only where a consumer carries nuance it lacks)
and/or `trim-to-citation` (replace each inline recap with a citation) — NOT a creation output. If the home
is complete and 100% of sites already cite it → no work (`REFUSE-already-cites-canonical` per `verify`
Gate 2). Reserve `rule-file` / `new-skill` / `new-action` for concepts with NO existing home **and** N≥3.

Bucket routing of the pre-check:

- **N=1, home exists** → `trim-to-citation` (replace the recap with a citation); add
  `normalize-wording` when the recap has drifted from the home's wording.
- **N=2, home exists** → `trim-to-citation` / `edit-existing-rule` against that home.
- **N=2, no home** → `name-an-owner`: pick the better-placed of the two files as canonical, make
  the other cite it. `normalize-wording` first if the two have already drifted. This is the
  accidental branch of anti-pattern #11; the intentional two-audience case still refuses (`verify`
  Gate 4).
- **N≥3, no home** → creation output, subject to the 6-test gate.

Output: ONE ranked table PER BUCKET (three labelled sections, ROI desc, dependency-grouped within
each). Then a batch-sequencing recommendation grouping non-overlapping candidates that can run in
parallel + dependency chains that must run sequentially.

Mark with ⭐ any cluster where an SSOT already exists but call sites STILL inline
(highest signal — quick wins).

Time budget: large. Aim thoroughness > speed. Do NOT edit files.
```

## Output shape (exhaustive mode)

Main session presents to user:

Every candidate table carries the bucket and the instance count per row, and the roster is grouped
into the three labelled bucket sections. Bucket sections the flags filtered out are still named,
with a one-line note saying they were suppressed and by which flag — a silently missing bucket
reads as "nothing found there".

```markdown
# Duplication survey — N candidates (N=1: a | N=2: b | N≥3: c)

## Bucket N≥3 — Rule of Three met (artifact creation permitted, 6-test gate applies)

### HIGH ROI (no dependencies, ⭐ SSOT-exists-but-inlined)
<table: # | cluster | bucket | instances | inlined-count | cite-to | suggested output | ROI>

### HIGH ROI (with dependencies)
<chain notation: A → B → C>

### MEDIUM ROI
<table>

### LOW ROI / advisory
<bulleted list>

## Bucket N=2 — source-of-truth bifurcation risk (no new artifact)
<table: # | cluster | bucket | instances | the two files | declared owner? | suggested output (edit-existing-rule | name-an-owner | normalize-wording) | ROI>

## Bucket N=1 — inline recap of an existing SSOT (no new artifact)
<table: # | cluster | bucket | instances | recapping file | canonical home | suggested output (trim-to-citation | normalize-wording) | ROI>

## Code/config advisory (out of scope)
<bulleted list>

## Dependency chains (must run sequential)
<named chains>

## Hot files (must NOT run candidates touching them in parallel)
<file: candidate-count>

## Batch dispatch plan
<Wave 1 sequential, Wave 2 sequential, ..., Wave N parallel-safe>

## Recommended next step
`/docs-hygiene:extract-ssot batch <Wave-1-cluster-list>`
```

The ranked table + wave plan is then persisted to working notes so the user can reset context and resume from durable state.

## Targeted mode steps

```text
1. Tier 0 grep across markdown for the named cluster's distinctive phrase
2. Capture: instance count, file list, line numbers
3. Assign the bucket from the full-reproduction count (N=1 / N=2 / N>=3). At N=1, confirm the
   admission gate: a canonical home exists that this site recaps instead of cites
4. Run quick instance-stability check (do they change together?). At N>=3 the Rule of Three is met
   and artifact creation is on the table; below it, the remedy set is the bucket's non-abstracting one
5. Suggest output type per `context/decision-framework.md`, constrained to the bucket
6. Return candidate spec (bucket included) ready for `/docs-hygiene:extract-ssot verify <cluster>`
```

No subagent dispatch. No batch sequencing. Single-cluster sanity check only.

## Anti-patterns guarded

- **Premature exhaustive mode** — dispatching a survey subagent when the user already has 1-2 clusters in mind wastes a dispatch. Detect via the argument.
- **Synthesis-only output** — a subagent return is unverified synthesis, not Tier 0 evidence. Each cluster MUST be promoted to Tier 0 (grep this turn) before `/docs-hygiene:extract-ssot plan` or `execute` runs. The `verify` action enforces this.
- **Skipping the user-review gate** — exhaustive mode can emit a roster of dozens of candidates. NEVER auto-dispatch the whole roster without user confirmation. Default policy: present roster + recommend top wave; user picks scope.
- **Roster decay** — the survey is point-in-time. If `/docs-hygiene:extract-ssot batch` partial-completes and the user resumes weeks later, re-run `identify` rather than trusting a stale roster.
- **Rule-of-one as report-everything** — rostering a lone paragraph that no canonical home duplicates. The N=1 bucket admits a candidate only when the SSOT-existence check finds the home it should be citing; without that, there is no duplication to report.
- **Bucket leakage** — offering `rule-file` / `new-skill` / `new-action` to an N=1 or N=2 candidate. The reporting threshold moved; the abstraction threshold did not. Constrain the suggested output to the bucket's permitted set before emitting.

## Sanity checks

| When | Check | Evidence |
|------|-------|----------|
| Pre-dispatch | No active working-notes candidate roster | Read of the notes |
| Post-dispatch | Subagent returned ≥10 candidates (an exhaustive survey should be productive) | Count |
| Post-dispatch | Each candidate has a Tier 0 grep evidence path | Spot check 3 candidates |
| Post-dispatch | Every candidate carries a bucket + instance count, and no sub-three candidate carries an artifact-creating suggested output | Scan the roster's bucket column |
| Pre-handoff | With `--fix`, only `trim-to-citation` / `normalize-wording` edits are staged, and no new file appears in the diff | `git status` / diff review |
| Pre-handoff | Wave plan respects the file-overlap matrix (no parallel candidates touching the same file) | Cross-check matrix |
| Pre-handoff | User has reviewed the roster and picked scope | Explicit user response |

## Cross-references

- `actions/batch.md` — consumes the wave plan from this action's output
- `actions/verify.md` — promotes each candidate from synthesis to Tier 0 before `plan`/`execute`
- `context/decision-framework.md` — output type decision matrix consumed in survey output
- `context/lessons.md` — known-refused patterns deduplicated from new survey results
- SKILL.md "Evidence discipline" — Tier 0 definition; subagent return is synthesis by default
