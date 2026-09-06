# PLAN. Enforceability audit lane

Container: #3800. Planning slice: #3806. Implementation slice: #3815. Branch:
`plan/3806-enforcement-promotion-audit`.

This plan is contract-tier and is pruned before merge. Every contract a worker needs is written
into the #3815 issue body; this file is the reasoning behind that body, not a second source of
truth for it.

## Brief

The container Brief on #3800 is the scope. In one sentence: a new read-only `audit` skill in the
`review` plugin reads one operator-named findings file, applies a crosswalk from finding class to
the cheapest deterministic enforcement rung and its owning implementer or upstream pointer, and
writes one proposal stub per finding outside the branch findings directory. It never implements a
rung.

### Constraints that govern every phase

- Verb `audit`: read-only findings report. Stub emission is artifact emission, not target
  mutation, the same distinction the fleet's other audit-verb detectors already rely on.
- One findings file per invocation, named by the operator. A missing or unnamed file is an error
  and never a repository-wide scan.
- Stubs land outside the branch findings directory and carry none of the findings-file markers.
- Rungs another plugin owns are pointers. This skill proposes and routes only.
- Skill content is org-agnostic and self-contained: it restates what it needs and cites only
  `${CLAUDE_PLUGIN_ROOT}` surfaces, never a path in this repository's `docs/`.
- No issue numbers, incident narration, or model names in the skill body.

## Goal

**What**: add `/review:audit-enforceability` (working name, see Naming) with a crosswalk context
file, a stub-shape context file, a deterministic stub-writer script with a test and fixture, evals,
and the plugin bookkeeping a new skill owes (README, binding, changelog, version, cheat sheet).

**Why**: recurring review findings are re-discovered by a model on every run. Nothing routes a
finding class to the cheapest deterministic check that would catch it. This skill turns each
finding into an actionable proposal with a named owner, so promotion to a deterministic rung is a
decision an operator can take rather than an observation.

## Standards grounding

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/PLUGIN-PHILOSOPHY.md` | Naming (verb table, qualifier rule); Design boundary (org-agnosticism) | team |
| `docs/conventions/seam-phrasing/README.md` | The shape (gate, fallback, ownership framing); install-recipe carve-out | team |
| `docs/conventions/detector-findings/README.md` | Why the contract is format-only; Where the file goes; Rule ids and thresholds; Boundary | team |
| `docs/conventions/topic-docs/README.md` | The two tiers; The slice tree (interior-freedom clause); Slug and filename spec; Implementers; Versioning | team |
| `plugins/review/reference/findings-file-shape.md` | Findings-file shape; Cell-escaping rule | team |
| `plugins/review/skills/fanout/context/fix-pass-mode.md` | Step 1 candidate predicate; Step 2 finding classes | team |
| `plugins/review/reference/topic-docs.md` | What this plugin writes; Resolution; Runtime guards | team |
| `.claude/rules/skill-bodies-state-current-rules.md` | whole file | team |

## What the input actually carries (traced, not assumed)

A conforming findings file, per `findings-file-shape.md`, has frontmatter `type: review-findings`,
`branch:`, optionally `date:` and `tier:`, and a `## Findings` table with columns `Rank | Tier |
Confidence | Location | Surface(s) | Finding | Action`. There is **no finding-class column**. The
only class-bearing signals are:

1. A leading qualified rule id `<plugin>/<skill>/rule-<slug>` in the `Finding` cell. Present on
   every row a detector adopter emits (`mutation-testing:audit`, `testing:audit`, `ai-slop:audit`,
   `claude-config:audit-instructions`, `docs-hygiene:audit-noise`). Absent on fanout's own rows.
2. `## By dimension` headings carrying fanout's Stage-0 category enum (`security`, `architecture`,
   `performance`, `testing`, `error-handling`, `concurrency`, `docs`, `other`). Present only in
   files `review:fanout` wrote; every adopter omits the section.
3. The `Finding` and `Action` prose.

The fix action's admission test (fix-pass-mode Step 1) is: a `*.md` file in the resolved
`reviews/<branch-slug>/` directory whose frontmatter declares `type: review-findings` and whose
`branch:` equals the current branch exactly, plus a parseable `## Findings` table. That predicate
is what "the fix pass consumes none of the stubs" has to be proven against.

## Dependency chain

Single implementation slice (#3815). Its three phases are sequential within one PR: the crosswalk
and stub shape fix what the script writes; the script and fixture fix what the evals and test
assert; the bookkeeping cites all of it.

## Naming

`/naming:name-it-better` ran with three blind generators (responsibility-literal, moment-of-use,
domain-lore). Merged, deduplicated, collision-checked against `quality-gate`, `fanout`,
`code-review`, `security-review`, `setup`, and `audit-automation-gaps`. Scored on the fleet's
declared grammar (imperative verb, fixed verb meaning, topic qualifier) and the skill's own
criteria order (semantic accuracy, scope fit, comprehensibility, trigger utility).

| Rank | Candidate | Rationale |
|---|---|---|
| 1 (RECOMMENDED) | `audit-enforceability` | Answers the exact per-finding question ("can this be enforced deterministically, and at what rung"). Same grammar as `audit-derivability`. The automation-gaps skill already calls this "a separate enforceability question", so the two skills partition cleanly. |
| 2 | `audit-enforcement-fit` | Accurate; two words; "fit" is vaguer than "enforceability". |
| 3 | `audit-mechanization` | Accurate but broad; risks being read as the automation-landscape audit. |
| 4 | `audit-rungs` | Terse; opaque to a reader who does not know the fleet's ladder vocabulary. |
| 5 | `audit-codification` | "Codify" is overloaded (rules, docs, laws). |
| 6 | `audit-shift-left` | Evocative; semantically loose (shift-left is about pipeline stage, not determinism). |

Disqualified: `audit-gate-fit` (collides with `quality-gate`), `audit-linter-fit` (misleading, the
ladder includes tests and hooks), `audit-check-fit` (`check` is a reserved verb with a different
contract), `audit-catchability` (coined), `audit-enforcement-lookup` (weakest form of rank 2).

The naming skill never auto-locks. `audit-enforceability` is recorded as the **working name** in
the #3815 body so the slice is dispatch-ready; the operator may override it before dispatch by
editing the one name in the issue body. One caution: `Enforceability` also heads a section of the
detector-findings convention in the sense "is the convention machine-checkable"; the skill
description states its own sense so the two do not blur.

## Phase 1. Skill body, crosswalk, stub shape. #3815 [TODO]

**Create** `plugins/review/skills/audit-enforceability/SKILL.md`, `context/crosswalk.md`,
`context/stub-shape.md`.

### SKILL.md

Frontmatter: `description` (≤1024 codepoints; names the intent and trigger phrases such as
"which of these findings could a linter or analyzer catch", "audit enforceability", "promote
findings to a deterministic check", "what rung catches this"), `argument-hint: "<findings-file>
[--topic <slug>]"`, `user-invocable: true`, `disable-model-invocation: false`, `shell: bash`,
`metadata: { workflow-stage: review, summary: ... }`. Model the frontmatter on `quality-gate`.

Body, in order:

1. **Input gate.** `$ARGUMENTS` names exactly one file. Empty or missing path → print the usage
   line and STOP. Never glob the findings directory, never pick "the newest". Read the file; refuse
   (STOP with a diagnostic) unless its frontmatter declares `type: review-findings` and a
   `## Findings` table parses. A `branch:` mismatch with the current branch is NOT a refusal:
   the operator named the file, and stubs are proposals, not applied edits. Record the file's
   `branch:` in every stub.
2. **Class derivation ladder**, per row, first hit wins, never a dropped row:
   - rule id leading the `Finding` cell → class from the crosswalk's rule-family rows;
   - the row's `## By dimension` heading when the file has that section → class from the
     dimension rows;
   - model judgment over `Finding` + `Action` text into the class vocabulary, recording
     `class-basis: judgment`;
   - unresolved → class `unclassified`, rung `LLM-only`, `class-basis: unresolved`.
3. **Crosswalk lookup**: class → rung → owner or pointer, read from `context/crosswalk.md`.
4. **Resolve the stub home** through `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md` (the
   binding's five-rung ladder and its non-interactive collapse). The home is
   `<memory_dir>/<slug>/enforceability/`, where `<slug>` is `--topic` when given, else the
   findings file's `branch:` value slugified per the binding's branch-slug rule, else the current
   branch. Run the self-ignore guard on the session's first memory-tier write. Never write under
   the resolved `reviews/` concern name.
5. **Write stubs** by calling `scripts/emit-stubs.sh` with the findings file, a classification
   file the model composed (one line per rank), and the resolved home. The script owns parsing,
   the one-stub-per-row invariant, the home check, and the marker self-check.
6. **Report**: a table of rank, class, basis, rung, owner, stub path; a count line
   `N findings → N stubs in <home>`; then the per-rung next steps, each phrased with its gate and
   fallback.
7. **Boundary** section, stating:
   - "promotion" in the detector-findings convention and the autonomy plugin means a candidate
     detector's guardrail class or a matrix cell's human-ratified knob flip across the C1–C5 work
     classes; enforcement promotion here means moving a finding class to a cheaper deterministic
     rung. Different meaning, different plugin.
   - Not the automation-landscape audit (`audit-automation-gaps` in the claude-config plugin walks
     the repo and self-generates candidates; this skill reads one findings file and walks nothing).
   - Not the fix action: it consumes findings; this skill only reads them and its stubs are
     invisible to it by construction.
   - Never implements a rung. Every rung is a proposal with an owner.
8. **Gotchas** (the skill-quality check's advisory surface): pipes inside cells are escaped as
   `\|` and must be unescaped before classifying; `Confidence` omitted is not low; a file with no
   `## By dimension` section is normal for adopters.

Presence-gated references (seam-phrasing shape, gate names the plugin, fallback in the same
sentence):

- Semgrep rung: "invoke `/semgrep-rule-creator:semgrep-rule-creator` (if the
  `semgrep-rule-creator` plugin is installed); otherwise the stub points at Semgrep's rule-writing
  documentation and stops." Install recipe printed in the report, marketplace-qualified per the
  install-recipe carve-out: `/plugin marketplace add trailofbits/skills` then
  `/plugin install semgrep-rule-creator@trailofbits`.
- Hook rung: "run `/claude-config:audit-automation-gaps hooks` (if the `claude-config` plugin is
  installed) and present the stub as a candidate in its candidate-list step, which is
  self-generated and takes no findings input; otherwise the stub records the candidate with the
  evidence that skill's gates ask for (frequency, incident history, enforcement level already
  covering it) and stops."
- Custom Roslyn analyzer rung: doc pointer only (Microsoft Learn, "Tutorial: Write your first
  analyzer and code fix"). No installable upstream skill could be named; see Deferred.
- Architecture test rung: doc pointers only (ArchUnitNET docs for .NET; the dependency-cruiser
  repository docs for JS/TS).

### context/crosswalk.md

Three columns: finding class, candidate rung, owner or pointer. Rungs in the Brief's fixed
cheapest-first order. The class vocabulary and its rung:

| Finding class | Rung | Owner or pointer |
|---|---|---|
| formatting, whitespace, ordering, naming style | editorconfig severity | in-repo `.editorconfig` |
| a diagnostic an installed analyzer pack or linter already defines (a cited `CAxxxx`/`IDExxxx`/`SAxxxx`, ESLint, ruff, markdownlint id, or a rule the pack documents) | existing analyzer pack rule | in-repo configuration: enable or raise severity in `.editorconfig`, `.globalconfig`, or the linter config |
| a project-specific API or usage invariant in C# expressible over syntax or the semantic model (banned API, required attribute, misuse pattern) | custom Roslyn analyzer | Microsoft Learn analyzer tutorial |
| a code pattern expressible as a syntactic match in any language (dangerous call, injection sink, secret shape, cross-language invariant); also the custom-analyzer class in a non-.NET ecosystem | Semgrep rule | `semgrep-rule-creator` plugin, gated; else Semgrep rule-writing docs |
| dependency direction, layering, namespace-to-layer naming, forbidden references | architecture test | ArchUnitNET docs (.NET); dependency-cruiser docs (JS/TS) |
| process and workflow: commit shape, file placement, generated-file freshness, session behaviour, anything observed at tool-call or commit time rather than in source | hook | `claude-config` plugin's `audit-automation-gaps hooks`, gated; else record and stop |
| design judgment, readability, correctness reasoning, prose quality, `unclassified` | LLM-only | none; the finding stays a review-time judgment |

Plus a rule-family section mapping each known adopter's rule ids to a class (for example
`testing/audit/rule-*` → existing analyzer pack rule where a test-framework analyzer covers it,
else custom analyzer; `ai-slop/audit/rule-*` and `docs-hygiene/audit-noise/rule-*` → the
detector itself is already the deterministic rung, so the stub names "already deterministic:
keep the detector" and the rung is the existing analyzer pack rule with the detector as owner;
`mutation-testing/audit/rule-*` → LLM-only, the covering test is judgment), and a dimension
section mapping fanout's Stage-0 categories to a default class (`architecture` → architecture
test; `security` → Semgrep rule; `docs` → LLM-only unless a rule id is present; the rest → judgment
ladder step). Every row carries its basis in one clause so a reader can dispute it.

### context/stub-shape.md

```markdown
---
type: enforceability-stub
date: <ISO-8601 UTC, the write instant>
source-findings: <file name>
source-sha256: <first 12 hex of the findings file's content digest>
source-branch: <the findings file's branch: value>
rank: <Rank>
finding-class: <class>
class-basis: rule-id | dimension | judgment | unresolved
rung: editorconfig-severity | analyzer-pack-rule | custom-analyzer | semgrep-rule | architecture-test | hook | llm-only
owner: <invocation, plugin name, or URL>
---

## Finding

<Location, Tier, Confidence, Surface(s), Finding, Action, verbatim, pipes unescaped>

## Proposed rung

<one paragraph: the rung, why this class lands there, what the check would assert>

## Next step

<the gated invocation or the pointer, with the fallback when the plugin is absent>

## Not done here

This stub proposes. Nothing was implemented.
```

Forbidden in a stub, checked by the writer: `type: review-findings`, `type: fix-pass-record`, a
top-level `branch:` key, a `## Findings` heading. Filename: `<rank-2digits>-<rung>-<slug>.md`
where `<slug>` is the first 40 chars of the sanitized `Location`.

**Sanity Check:**

- `test -f plugins/review/skills/audit-enforceability/SKILL.md` exits 0 (fails on the unmodified
  tree: exit 1, verified).
- `test -f plugins/review/skills/audit-enforceability/context/crosswalk.md && test -f plugins/review/skills/audit-enforceability/context/stub-shape.md` exits 0.
- `test -d plugins/review/skills/audit-enforceability && ! grep -rq -e '@melodic-software' -e 'MELODIC_' -e 'docs/conventions/' plugins/review/skills/audit-enforceability/` exits 0 (the `test -d` is what makes this fail on the unmodified tree; a bare `! grep` on a missing directory passes, verified).
- `grep -q 'C1' plugins/review/skills/audit-enforceability/SKILL.md && grep -qi 'different meaning' plugins/review/skills/audit-enforceability/SKILL.md` exits 0.
- `grep -c 'if the .* plugin is installed' plugins/review/skills/audit-enforceability/SKILL.md` prints at least 2.

## Phase 2. Stub writer, test, fixture. #3815 [TODO]

**Create** `scripts/emit-stubs.sh`, `scripts/emit-stubs.test.sh`,
`evals/fixtures/findings-one-per-rung.md`, `evals/fixtures/classification-one-per-rung.tsv`.

### `emit-stubs.sh` CLI contract

```text
emit-stubs.sh --findings <file> --classes <tsv> --out <dir> [--dry-run]
```

- `--findings`: one file. Must exist, must declare `type: review-findings`, must carry a
  parseable `## Findings` table. Otherwise exit 2 with a one-line diagnostic and write nothing.
- `--classes`: TSV, one line per rank: `rank<TAB>class<TAB>basis<TAB>rung<TAB>owner`. A rank
  present in the table but absent from the TSV gets `unclassified / unresolved / llm-only / none`
  rather than no stub. A rank in the TSV absent from the table is a diagnostic, not a stub.
- `--out`: the resolved home. The script refuses (exit 3, writes nothing) when `--out` resolves to
  the findings file's own directory or any path under it; the fix action scans that directory.
- Parses the table by splitting on unescaped pipes, unescaping `\|` in cells. Filename per the
  stub shape. Never overwrites: an existing path takes a `-2`, `-3` suffix.
- After writing, re-reads every stub it wrote and fails (exit 4, stubs removed) if any contains a
  forbidden marker. The writer is the fence.
- Prints `N findings → N stubs in <out>` on success; exit 0. `--dry-run` prints the planned
  filenames and writes nothing.
- The home is never resolved here. The caller resolves it through the binding and hands it in,
  the same division the fleet's `emit-findings.sh` writers use.

### `emit-stubs.test.sh`

Shell test in the repo's `*.test.sh` idiom. Cases, each named:

1. fixture with seven rows (one per rung) → seven stubs, one per rank, exit 0;
2. every stub declares `type: enforceability-stub` and none matches
   `^type: review-findings|^type: fix-pass-record|^branch:|^## Findings`;
3. the fix action's Step 1 candidate predicate, replicated as
   `grep -l '^type: review-findings' <out>/*.md`, returns nothing;
4. `--out` equal to, or under, the findings file's directory → exit 3, no files;
5. missing `--findings` → exit 2; a file without `type: review-findings` → exit 2;
6. a `Finding` cell containing `\|` reaches the stub unescaped and unsplit;
7. a rank missing from `--classes` still yields a stub with rung `llm-only`;
8. re-running into the same `--out` writes `-2` siblings, never overwrites.

### Fixture

`findings-one-per-rung.md`: a conforming file with `type: review-findings`, `branch: fixture`,
`date:`, seven rows whose `Finding` cells exercise each class (one leading with a qualified rule
id, one with an escaped pipe), a `## By dimension` section with two headings, `## Unparsed`,
`## Surfaces`. Referenced by basename in the test and by path in `evals.json`, so the
orphaned-fixtures gate counts it consumed.

**Sanity Check:**

- `bash plugins/review/skills/audit-enforceability/scripts/emit-stubs.test.sh` exits 0 (the
  file does not exist on the unmodified tree).
- `bash scripts/affected-tests.sh --explain plugins/review/skills/audit-enforceability/scripts/emit-stubs.sh 2>&1 | grep -q 'emit-stubs.test.sh'` exits 0 (on the unmodified tree the selector prints "No suites selected" and exits 0, so the grep is the check, verified).
- After the test runs its fixture into a temp dir `$T`: `! grep -rq -e '^type: review-findings' -e '^branch:' -e '^## Findings' "$T"` exits 0 and `ls "$T"/*.md | wc -l` prints 7.

## Phase 3. Evals and plugin bookkeeping. #3815 [TODO]

**Create** `evals/evals.json`. **Modify** `plugins/review/README.md`,
`plugins/review/reference/topic-docs.md`, `plugins/review/CHANGELOG.md`,
`plugins/review/.claude-plugin/plugin.json`, `docs/SKILL-CHEAT-SHEET.md` (regenerated),
`docs/conventions/topic-docs/README.md` (Implementers row), `docs/conventions/topic-docs/CHANGELOG.md`.

- `evals.json`: at least five cases: one-per-rung fixture run (expects seven stubs, each naming a
  rung and owner); a missing-file refusal; a rule-id row classified by rule family, not prose; a
  Boundary question ("is this the C3 promotion thing?") answered with the disambiguation; a
  no-implementation case (asked to "just write the analyzer", the skill declines and points).
  Include one refusal case, which the eval-quality lint asks for.
- README `### Skills`: add the `/review:audit-enforceability <findings-file>` bullet. README
  "Findings location": one sentence that enforceability stubs land in the topic slice, not
  under `reviews/`.
- `reference/topic-docs.md`: add a row for the stub artifact under "What this plugin writes" and
  reword "Memory tier only, concern-scoped" to admit the topic-slice write, with the reason (the
  stubs must be invisible to the fix action's scan, which is directory-scoped).
- `plugin.json`: version `0.27.0` (new skill is a minor bump); description names the new skill.
- `CHANGELOG.md`: `## [0.27.0]` / `### Added` entry.
- `docs/SKILL-CHEAT-SHEET.md`: run `node scripts/generate-cheatsheet.mjs`; do not hand-edit.
- `docs/conventions/topic-docs/README.md` Implementers table: review row becomes
  "review reports; enforceability stubs | memory (`reviews/`; `<slug>/enforceability/`)". Record
  it as a minor entry in that convention's CHANGELOG (additive guidance, per its Versioning
  section).
- Run `bash plugins/skill-quality/scripts/check-skill.sh --require-evals audit-enforceability`
  with `CHECK_SKILL_SKILLS_ROOT=plugins/review/skills`; fix every `FAIL:`.
- Run `npx markdownlint-cli2` over every changed markdown file.

**Sanity Check:**

- `CHECK_SKILL_SKILLS_ROOT=plugins/review/skills bash plugins/skill-quality/scripts/check-skill.sh --require-evals audit-enforceability` exits 0 (exit 1 on the unmodified tree, verified).
- `grep -q 'audit-enforceability' plugins/review/README.md` exits 0 (exit 1 now, verified).
- `grep -q '^## \[0.27.0\]' plugins/review/CHANGELOG.md` exits 0 (exit 1 now, verified).
- `grep -q '"version": "0.27.0"' plugins/review/.claude-plugin/plugin.json` exits 0 (exit 1 now, verified).
- `grep -q 'review:audit-enforceability' docs/SKILL-CHEAT-SHEET.md` exits 0.
- `grep -q 'enforceability' plugins/review/reference/topic-docs.md` exits 0.

CI gates that must also pass, listed separately because they pass on the unmodified tree and so
prove nothing on their own: `bash scripts/check-changelog-parity.sh --check-bump origin/main`
exits 0; `npx markdownlint-cli2 "plugins/review/**/*.md" "docs/SKILL-CHEAT-SHEET.md" "docs/conventions/topic-docs/*.md"` exits 0;
`bash scripts/check-orphaned-fixtures.sh --check` exits 0.

## Test strategy

Two halves, verified differently, and the slice body says which proves what:

- **Writer invariants are deterministic** and are proven by `emit-stubs.test.sh`: one stub per
  row, no marker, no home under the findings directory, escaped pipes preserved, refusal on
  bad input, no overwrite. Test-first: write the eight cases, run red, implement the script.
- **Classification is a judgment step** and is proven by evals, not by a shell test: the
  one-per-rung fixture case asserts the rung and owner each row lands on; the rule-id case
  asserts the ladder's first step wins over prose.
- "The fix pass consumes none of the stubs" is proven structurally: test case 3 replicates the
  fix action's Step 1 predicate over the stub directory and asserts empty, and test case 4 proves
  the writer refuses a home inside the scanned directory. Running the real fix action is not a
  test (it is model-driven and would need a branch with findings); the predicate replication is.
- Boundaries driven by tests: `emit-stubs.sh`'s CLI (new). The findings-file shape (existing) is
  driven only as input.
- Existing tests to update: none. `standards-binding.test.sh` greps the existing skills only.

## Files affected

| File | Action | What changes |
|---|---|---|
| `plugins/review/skills/audit-enforceability/SKILL.md` | Create | Skill body per Phase 1 |
| `plugins/review/skills/audit-enforceability/context/crosswalk.md` | Create | Class → rung → owner table, rule-family and dimension sections |
| `plugins/review/skills/audit-enforceability/context/stub-shape.md` | Create | Stub frontmatter, body, filename, forbidden markers |
| `plugins/review/skills/audit-enforceability/scripts/emit-stubs.sh` | Create | Deterministic writer |
| `plugins/review/skills/audit-enforceability/scripts/emit-stubs.test.sh` | Create | Eight cases |
| `plugins/review/skills/audit-enforceability/evals/evals.json` | Create | Five or more cases |
| `plugins/review/skills/audit-enforceability/evals/fixtures/findings-one-per-rung.md` | Create | Conforming fixture |
| `plugins/review/skills/audit-enforceability/evals/fixtures/classification-one-per-rung.tsv` | Create | Classification input for the test |
| `plugins/review/README.md` | Modify | Skills list; findings-location sentence |
| `plugins/review/reference/topic-docs.md` | Modify | New artifact row; tier sentence |
| `plugins/review/CHANGELOG.md` | Modify | `## [0.27.0]` Added |
| `plugins/review/.claude-plugin/plugin.json` | Modify | version, description |
| `docs/SKILL-CHEAT-SHEET.md` | Modify | Regenerated |
| `docs/conventions/topic-docs/README.md` | Modify | Implementers row for review |
| `docs/conventions/topic-docs/CHANGELOG.md` | Modify | Minor entry |

Fifteen files, so the checkbox inventory lives in the #3815 body.

## Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Stubs under `reviews/<branch-slug>/enforceability/` | Fix-pass Step 1 scans "every `*.md` in that directory"; a subdirectory is not provably outside, and the Brief says outside. | Never. |
| A new reserved concern name `enforceability/<branch-slug>/` in the topic-docs convention | Right axis (branch), but adds a reserved first-level name, which the convention treats as a spec change for every implementer. Blast radius exceeds one increment. | A second consumer of stubs appears (recurrence detection, a realign-style executor). Then promote. |
| Model writes stubs directly, no script | The invariants that matter (no marker, outside the scan, one per row) would be instruction-strength only, and the acceptance criteria demand a fixture-driven proof. | Never for this increment. |
| Extend the fix action with an "enforce" route | Mixes a mutating action with a proposal; the container's ownership decision already rejected widening an existing skill. | Never. |
| Key the crosswalk on rule id only | Fanout's own rows carry no rule id; the skill would emit LLM-only for every fanout finding. | Never; the ladder keeps rule id as its first step. |
| Widen `audit-automation-gaps` | Rejected on the container: wrong ownership boundary, no findings input path. | Never. |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Classification lands most rows on LLM-only, making the skill look useless | Med | Med | Rule-family and dimension sections give deterministic first steps; the report prints the basis per row so an operator sees why. |
| A stub is mistaken for a findings file by a future consumer | Low | High | Distinct `type:`, no `branch:` key, no `## Findings` heading, writer self-check, test case 2 and 3. |
| The Roslyn owner pointer is a doc, not a skill, and the Brief promised a skill | High (already true) | Low | Brief amended with a dated note; deferred question asks the operator to name one. |
| Presence gate names a plugin from a foreign marketplace | Low | Med | Gate names the plugin only; the marketplace appears only in the printed install recipe, per the carve-out. |
| Cheat-sheet or changelog parity gate fails in CI | Med | Low | Phase 3 sanity checks run both locally. |
| `emit-stubs.sh` table parser mishandles `\|` | Med | Med | Test case 6; parser splits on unescaped pipes only. |

## Blast radius

- **Review plugin**: one new skill directory, README, binding, changelog, manifest. No existing
  skill body changes. `fanout` and `quality-gate` are untouched.
- **Convention docs**: one Implementers row and one changelog entry in topic-docs. No tier, key,
  slug, or visibility change.
- **Generated docs**: cheat sheet regenerated.
- **Consumers**: none at runtime until an operator invokes the skill. The stub home is memory
  tier and self-ignoring.
- **CI**: `check-changed-skills.sh` runs the skill-quality gate with `--require-evals` on the
  new skill; `check-changelog-parity.sh --check-bump` sees the version change; the orphaned-fixtures
  gate sees the fixture consumed by the test and evals; `affected-tests.sh` maps the new script to
  its co-located test.

## Execution-shape analysis

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | SKILL.md, context/crosswalk.md, context/stub-shape.md | none |
| 2 | scripts/emit-stubs.sh, scripts/emit-stubs.test.sh, evals/fixtures/* | none |
| 3 | evals/evals.json, README, reference/topic-docs.md, CHANGELOG, plugin.json, cheat sheet, convention row and changelog | none |

### Dependency graph

- 1 → 2: the script implements the stub shape and forbidden-marker list Phase 1 fixes.
- 2 → 3: evals reference the fixture; the changelog describes the script.
- Sequential, one worker, one PR. Three phases are three commits, not three dispatches.

### Recommended shape

> Fully sequential: 1 → 2 → 3 in one worktree, one PR (per-item PRs is the container's execution
> shape and this container has one implementation item).

### Per-phase routing table

| Phase | Surface | Basis |
|---|---|---|
| 1 | sub-agent worker | prose authoring against a fixed contract in the issue body |
| 2 | sub-agent worker | script plus test, mechanical, test-first |
| 3 | sub-agent worker | bookkeeping, all mechanical |

Divergence escalation clause goes into the worker brief verbatim (planning plugin's plan template).

## Decisions made

| Decision | Basis |
|---|---|
| Working name `audit-enforceability` | Naming pass above; operator-overridable before dispatch |
| Stub home is the topic slice, not a reserved concern name | Interior-freedom clause admits it without a convention spec change; the switch condition is recorded |
| Roslyn rung owner is a doc pointer | No nameable installable skill exists; an unnamed collaborator cannot be gated |
| Hook handoff is operator-carried | The gaps skill self-generates candidates and has no findings input |
| Classification is a ladder, rule id first | The input carries no class column; traced above |
| Deterministic writer script with a test | The acceptance criteria demand fixture-driven proof of writer invariants |

## Deferred questions

- Which upstream Roslyn analyzer authoring skill did the Brief intend? If the operator names an
  installable plugin, the custom-analyzer row gains a presence gate and the doc pointer becomes
  its fallback.
- Cross-run recurrence (carried from the container): evidence threshold and where history lives.
  The stub's `source-sha256` and `source-findings` fields are the hook a later increment keys on.
- Whether the topic-slice home should become a reserved concern name once a second consumer
  exists.

## Handoff to implementation

The #3815 body carries every contract above that a worker needs: the class ladder, the crosswalk
table, the stub shape and forbidden markers, the script CLI and exit codes, the test cases, the
fixture requirements, the bookkeeping list, and the presence-gated references with their fallbacks.
A worker cut from `main` never sees this file.
