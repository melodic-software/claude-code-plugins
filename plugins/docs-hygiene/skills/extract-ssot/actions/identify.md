# `identify` action — exhaustive duplication survey

Default mode dispatches a read-only exploration subagent that runs 30+ duplication heuristics across all markdown surfaces, emits a ranked candidate roster, computes a file-overlap matrix, and returns a batch-sequencing recommendation ready to feed `/extract-ssot batch`.

Private surface — external consumers invoke `/extract-ssot identify`, never cite this file directly (contract: `/encapsulation-audit`).

## Two modes

| Invocation | Mode | Behavior |
|------------|------|----------|
| `/extract-ssot identify` | Exhaustive (default) | Read-only subagent deep survey across instruction files, rules, skills, agents, ADRs, docs. Returns a ranked candidate roster + dependency chains + file-overlap matrix + batch wave plan |
| `/extract-ssot identify <cluster-name>` | Targeted | Tier 0 grep on a named cluster only. Returns instance count + Tier 0 evidence + suggested output type. No subagent dispatch |

User signals like "find ANY and ALL", "deep dive", "exhaustive", "full list", or `/extract-ssot identify` with no args = default to exhaustive mode.

## When to invoke

| Use case | Mode |
|----------|------|
| User asks for full duplication audit | Exhaustive |
| Maintenance / quarterly sweep | Exhaustive |
| User has one cluster in mind already | Targeted |
| Resume from working notes holding a candidate roster | Skip identify; route to `verify` / `plan` / `execute` / `batch` |

## Inputs

```text
/extract-ssot identify              # exhaustive default
/extract-ssot identify <cluster>    # targeted
```

## Exhaustive mode steps

```text
1. Pre-flight: confirm no working notes with an active candidate roster (would imply resume, not new identify)
2. Dispatch a read-only exploration subagent with the survey prompt (template below)
3. Subagent searches markdown surfaces with 30+ heuristics (template lists them)
4. Subagent returns ranked candidate table + dependency chains + file-overlap matrix
5. Main session classifies output: deduplicate against context/lessons.md known-refused patterns
6. Main session emits batch-sequencing recommendation (waves, sequential vs parallel, hot files)
7. Main session offers user: dispatch /extract-ssot batch with top-N waves, or pick specific clusters
8. Persist the roster to working notes so the user can resume from durable state
```

## Subagent prompt template

The subagent receives a self-contained prompt. Skeleton:

```text
Goal: EXHAUSTIVE duplication survey for /extract-ssot. Find ANY and ALL duplication
candidates across markdown in this repo. Apply STRICT Tier 0 discipline — see
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

## Discrimination rules — CRITICAL

Each candidate MUST be classified by repetition form. Forms (a), (e)+(framing-only), and
(i) count as extraction candidates. Form (c2) full-paragraph semantic reword also counts
when the stability+reader-burden test passes.

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
| (i) Semantic-paraphrase cluster — 3+ instances assert same canonical truth in different wording; no shared verbatim ≥8 word phrase but reader could not tell which is canonical | YES — extract iff stability OR reader-burden test passes | A commit-policy framing restated across the instruction file + 3 skills + 2 prompts in different words |

**Stability + reader-burden combined test — applies to forms (c2), (e), (i).** Extract iff EITHER:
- Changing the canonical truth would force updates in 3+ places in lockstep (maintenance burden), OR
- Reader cannot tell which instance is canonical (ambiguity)

If only ONE passes: borderline (mark WARN). If NEITHER: REFUSE-low-roi.

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
6. **SSOT existence check** — does a canonical file already exist? If yes, what % of call sites cite it? If 100% cite → REFUSE-already-cites-canonical.
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
- Instance count
- 1-line description
- SSOT exists? (path or "no")
- Suggested output: rule-file | new-skill | new-action | edit-existing-rule
  | trim-to-citation | code-extract-advisory | config-extract-advisory
- ROI: HIGH / MEDIUM / LOW
- Dependency on other candidates (so batch ordering is clear)
- File-overlap (which other candidates touch same files — for batch sequencing)

**Existing-owner pre-check — route before suggesting a creation output.** Gate the `Suggested output`
field on the SSOT-existence check (the `SSOT exists?` capture field + per-candidate evidence item 6): if
an existing rule/skill/doc already owns the concept and ≥1 consumer still recaps it inline, suggest the
consolidation outputs — `edit-existing-rule` (extend the home only where a consumer carries nuance it lacks)
and/or `trim-to-citation` (replace each inline recap with a citation) — NOT a creation output. If the home
is complete and 100% of sites already cite it → no work (`REFUSE-already-cites-canonical` per `verify`
Gate 2). Reserve `rule-file` / `new-skill` / `new-action` for concepts with NO existing home.

Output: ONE big ranked table (ROI desc, dependency-grouped). Then a batch-sequencing
recommendation grouping non-overlapping candidates that can run in parallel +
dependency chains that must run sequentially.

Mark with ⭐ any cluster where an SSOT already exists but call sites STILL inline
(highest signal — quick wins).

Time budget: large. Aim thoroughness > speed. Do NOT edit files.
```

## Output shape (exhaustive mode)

Main session presents to user:

```markdown
# Duplication survey — N candidates

## HIGH ROI (no dependencies, ⭐ SSOT-exists-but-inlined)
<table: # | cluster | inlined-count | cite-to | ROI>

## HIGH ROI (with dependencies)
<chain notation: A → B → C>

## MEDIUM ROI
<table>

## LOW ROI / advisory
<bulleted list>

## Code/config advisory (out of scope)
<bulleted list>

## Dependency chains (must run sequential)
<named chains>

## Hot files (must NOT run candidates touching them in parallel)
<file: candidate-count>

## Batch dispatch plan
<Wave 1 sequential, Wave 2 sequential, ..., Wave N parallel-safe>

## Recommended next step
`/extract-ssot batch <Wave-1-cluster-list>`
```

The ranked table + wave plan is then persisted to working notes so the user can reset context and resume from durable state.

## Targeted mode steps

```text
1. Tier 0 grep across markdown for the named cluster's distinctive phrase
2. Capture: instance count, file list, line numbers
3. Run quick instance-stability check (Rule of Three; do they change together?)
4. Suggest output type per `context/decision-framework.md`
5. Return candidate spec ready for `/extract-ssot verify <cluster>`
```

No subagent dispatch. No batch sequencing. Single-cluster sanity check only.

## Anti-patterns guarded

- **Premature exhaustive mode** — dispatching a survey subagent when the user already has 1-2 clusters in mind wastes a dispatch. Detect via the argument.
- **Synthesis-only output** — a subagent return is unverified synthesis, not Tier 0 evidence. Each cluster MUST be promoted to Tier 0 (grep this turn) before `/extract-ssot plan` or `execute` runs. The `verify` action enforces this.
- **Skipping the user-review gate** — exhaustive mode can emit a roster of dozens of candidates. NEVER auto-dispatch the whole roster without user confirmation. Default policy: present roster + recommend top wave; user picks scope.
- **Roster decay** — the survey is point-in-time. If `/extract-ssot batch` partial-completes and the user resumes weeks later, re-run `identify` rather than trusting a stale roster.

## Sanity checks

| When | Check | Evidence |
|------|-------|----------|
| Pre-dispatch | No active working-notes candidate roster | Read of the notes |
| Post-dispatch | Subagent returned ≥10 candidates (an exhaustive survey should be productive) | Count |
| Post-dispatch | Each candidate has a Tier 0 grep evidence path | Spot check 3 candidates |
| Pre-handoff | Wave plan respects the file-overlap matrix (no parallel candidates touching the same file) | Cross-check matrix |
| Pre-handoff | User has reviewed the roster and picked scope | Explicit user response |

## Cross-references

- `actions/batch.md` — consumes the wave plan from this action's output
- `actions/verify.md` — promotes each candidate from synthesis to Tier 0 before `plan`/`execute`
- `context/decision-framework.md` — output type decision matrix consumed in survey output
- `context/lessons.md` — known-refused patterns deduplicated from new survey results
- SKILL.md "Evidence discipline" — Tier 0 definition; subagent return is synthesis by default
