# PLAN. Enforceability audit lane

Container: #3800. Planning slice: #3806. Implementation slice: #3815. Branch:
`plan/3806-enforcement-promotion-audit`.

This plan is contract-tier and is pruned before merge. Every contract a worker needs is written
into the #3815 issue body; this file is the reasoning behind that body, not a second source of
truth for it.

## Revision 2 (after the first verifier pass)

Revision 1 put the stubs in a topic slice, `<memory_dir>/<slug>/enforceability/`, and rejected a
reserved concern name as a convention spec change. Both were wrong. The review binding's ladder
resolves a review-artifacts location, and only its first and last rungs expose a memory root, so
`<memory_dir>` is underivable on rungs 2 to 4; a branch-derived slug violates the topic-slug spec
(40-char cap, reserved-name suffix); a same-slug existing directory is a resume into a live slice;
and a second artifact family in a leaf slice creates an `INDEX.md` obligation. Meanwhile the
convention's own changelog records `overengineering` joining the reserved first-level names as a
docs-only patch (2.5.1). Revision 2 adopts a reserved concern name, `enforceability/<branch-slug>/`,
bound exactly as `reviews/` is, and fences the writer against the fix action's resolved directory
rather than against the input file's directory.

## Brief

The container Brief on #3800 is the scope. In one sentence: a new read-only `audit` skill in the
`review` plugin reads one operator-named findings file, applies a crosswalk from finding class to
the cheapest deterministic enforcement rung and its owning implementer or upstream pointer, and
writes one proposal stub per finding outside the branch findings directory. It never implements a
rung.

### Constraints that govern every phase

- Verb `audit`: read-only findings report. The stubs are the report, written to the self-ignoring
  memory tier and consumed by no relay. Bare invocation writes them, the same posture as
  `overengineering:audit`, whose description reads "unasked writes stay in the self-ignored memory
  tier". The detector adopters that gate persistence behind `--persist-findings` do so because
  their files reach an apply relay; a stub reaches none.
- One findings file per invocation, named by the operator. A missing or unnamed file is an error
  and never a repository-wide scan.
- Stubs land in `<memory-root>/enforceability/<branch-slug>/`, never under the resolved
  `reviews/<branch-slug>/` the fix action scans, and carry none of the findings-file markers.
- Rungs another plugin owns are pointers. This skill proposes and routes only.
- Skill content is org-agnostic and self-contained: it restates what it needs and cites only
  `${CLAUDE_PLUGIN_ROOT}` surfaces, never a path in this repository's `docs/`.
- No issue numbers, incident narration, or model names in the skill body.

## Goal

**What**: add `/review:audit-enforceability` (working name, see Naming) with a crosswalk context
file, a stub-shape context file, a deterministic stub-writer script with a test and fixture, evals,
a new reserved concern name in the topic-docs convention, and the plugin bookkeeping a new skill
owes (README, binding, changelog, version, cheat sheet).

**Why**: recurring review findings are re-discovered by a model on every run. Nothing routes a
finding class to the cheapest deterministic check that would catch it. This skill turns each
finding into an actionable proposal with a named owner, so promotion to a deterministic rung is a
decision an operator can take rather than an observation.

## Standards grounding

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/PLUGIN-PHILOSOPHY.md` | Naming (verb table, qualifier rule); Design boundary (org-agnosticism) | team |
| `docs/conventions/seam-phrasing/README.md` | The shape (gate, fallback, ownership framing); install-recipe carve-out | team |
| `docs/conventions/detector-findings/README.md` | Why the contract is format-only; Where the file goes; Rule ids and thresholds; Boundary; Adopters; External authority | team |
| `docs/conventions/topic-docs/README.md` | The two tiers; Slug and filename spec (reserved names); Runtime guards; Implementers; Versioning | team |
| `docs/conventions/topic-docs/CHANGELOG.md` | 2.5.1 (precedent for adding a reserved name) | team |
| `plugins/review/reference/findings-file-shape.md` | Findings-file shape; Cell-escaping rule | team |
| `plugins/review/skills/fanout/context/fix-pass-mode.md` | Step 1 candidate predicate; Step 2 finding classes | team |
| `plugins/review/reference/topic-docs.md` | What this plugin writes; Resolution; Runtime guards | team |
| `plugins/overengineering/reference/topic-docs.md` | Resolution (model for a second concern's ladder) | team |
| `.claude/rules/skill-bodies-state-current-rules.md` | whole file | team |

## What the input actually carries (traced, not assumed)

A conforming findings file, per `findings-file-shape.md`, has frontmatter `type: review-findings`,
`branch:`, optionally `date:` and `tier:`, and a `## Findings` table with columns `Rank | Tier |
Confidence | Location | Surface(s) | Finding | Action`. There is **no finding-class column**. The
only class-bearing signals are:

1. A leading qualified rule id `<plugin>/<skill>/rule-<slug>` in the `Finding` cell. Present on
   every row a detector adopter emits (`mutation-testing:audit`, `testing:audit`, `ai-slop:audit`,
   `claude-config:audit-instructions`, `docs-hygiene:audit-noise`, `provenance:audit`). Absent
   on fanout's own rows.
2. `## By dimension` headings carrying fanout's Stage-0 category enum. The enum is open:
   `security`, `architecture`, `performance`, `testing`, `error-handling`, `concurrency`, `docs`,
   and more, with unmappable → `other`. Present only in files `review:fanout` wrote; every
   adopter omits the section.
3. The `Finding` and `Action` prose.

The fix action's admission test (fix-pass-mode Step 1) is: every `*.md` directly in the resolved
`reviews/<branch-slug>/` directory (non-recursive) whose frontmatter declares
`type: review-findings` and whose `branch:` equals the current branch exactly, plus a parseable
`## Findings` table. The scanned directory is the binding's resolved reviews location, not the
directory the operator's input file happens to sit in. That predicate and that directory are what
"the fix pass consumes none of the stubs" has to be proven against.

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
editing the one name in the issue body. One caution: every convention README in this repository
carries an `## Enforceability` section in the sense "is this convention machine-checkable", tiered
by a fleet standard (`enforceability-tiers.md`). The skill description states its own sense (can
this finding be caught deterministically, and at which rung) so the two do not blur, and the
Deferred section asks whether the crosswalk should adopt that tier vocabulary.

## Phase 1. Skill body, crosswalk, stub shape. #3815 [TODO]

**Create** `plugins/review/skills/audit-enforceability/SKILL.md`, `context/crosswalk.md`,
`context/stub-shape.md`.

### SKILL.md

Frontmatter: `description` (≤1024 codepoints; names the intent and trigger phrases such as
"which of these findings could a linter or analyzer catch", "audit enforceability", "promote
findings to a deterministic check", "what rung catches this"), `argument-hint:
"<findings-file>"`, `user-invocable: true`, `disable-model-invocation: false`, `allowed-tools`
(the git and file commands the body runs plus `Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-enforceability/scripts/emit-stubs.sh:*")`,
tightened to what the body actually runs, as `quality-gate` does), `shell: bash`,
`metadata: { workflow-stage: review, summary: ... }` (the cheat sheet reads `summary`).

Body, in order:

1. **Input gate.** `$ARGUMENTS` names exactly one file. Empty or missing path → print the usage
   line and STOP. Never glob a findings directory, never pick "the newest". Read the file; refuse
   (STOP with a diagnostic) unless its frontmatter declares `type: review-findings` and a
   `## Findings` table parses. A `branch:` mismatch with the current branch is NOT a refusal:
   the operator named the file, and stubs are proposals, not applied edits. Record the file's
   `branch:` in every stub and use it for the branch slug.
2. **Class derivation ladder**, per row, first hit wins, never a dropped row:
   - the exact qualified rule id leading the `Finding` cell matches a rule-id row in the
     crosswalk → that row's class (`class-basis: rule-id`);
   - the rule id's `<plugin>/<skill>/` prefix matches a rule-family row → that row's class
     (`class-basis: rule-family`);
   - the row's `## By dimension` heading, when the file has that section, matches a dimension row
     → that row's class (`class-basis: dimension`); an unlisted dimension falls through;
   - model judgment over `Finding` + `Action` text into the class vocabulary
     (`class-basis: judgment`);
   - unresolved → class `unclassified`, rung `llm-only`, `class-basis: unresolved`.
3. **Crosswalk lookup**: class → rung → owner or pointer, read from `context/crosswalk.md`.
4. **Resolve two homes** through `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`: the stub home
   (`enforceability/<branch-slug>/` under the binding's ladder for that concern) and the fix
   action's reviews location for the same branch (the binding's `reviews/<branch-slug>/` ladder).
   Follow the binding's Runtime guards: the self-ignore guard on the session's first memory-tier
   write, and the invalid-root cases where the write itself is refused (a root-equivalent memory
   root; a resolved root no checkout is detected as governing, except the plugin-data fallback).
   Non-interactive contexts take the binding's cited non-interactive collapse.
5. **Write stubs** by composing a classification TSV (one line per rank) and calling
   `scripts/emit-stubs.sh --findings <file> --classes <tsv> --out <stub-home> --scan-dir <reviews-home>`.
   The script owns parsing, the one-stub-per-row invariant, both home fences, and the marker
   self-check.
6. **Report**: a table of rank, class, basis, rung, owner, stub path; a count line
   `N findings → N stubs in <home>`; then the per-rung next steps, each phrased with its gate and
   fallback.
7. **Boundary** section, stating:
   - "promotion" in the detector-findings convention and the autonomy plugin means a candidate
     detector's guardrail class or a matrix cell's human-ratified knob flip across the C1–C5 work
     classes; enforcement promotion here means moving a finding class to a cheaper deterministic
     rung. Different meaning, different plugin.
   - "enforceability" of a convention (is it machine-checkable, at which tier) is a different
     question from the enforceability of one finding, which is what this skill answers.
   - Not the automation-landscape audit (`audit-automation-gaps` in the claude-config plugin walks
     the repo and self-generates candidates; this skill reads one findings file and walks nothing).
   - Not the fix action: it consumes findings; this skill only reads them and its stubs are
     invisible to it by construction.
   - Never implements a rung. Every rung is a proposal with an owner.
8. **Gotchas** (the skill-quality check's advisory surface): pipes inside cells are escaped as
   `\|` and must be unescaped before classifying; `Confidence` omitted is not low; a file with no
   `## By dimension` section is normal for adopter-produced files; the dimension enum is open.

Presence-gated references (seam-phrasing shape, gate names the plugin, fallback in the same
sentence):

- Semgrep rung: "invoke `/semgrep-rule-creator:semgrep-rule-creator` (if the
  `semgrep-rule-creator` plugin is installed); otherwise the stub points at Semgrep's rule-writing
  documentation and stops." Install recipe printed in the report, marketplace-qualified per the
  install-recipe carve-out: `/plugin marketplace add trailofbits/skills` then
  `/plugin install semgrep-rule-creator@trailofbits`. The marketplace name appears nowhere else.
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
| formatting, whitespace, ordering, naming style | `editorconfig-severity` | in-repo `.editorconfig` |
| a diagnostic an installed analyzer pack or linter already defines (a cited `CAxxxx`/`IDExxxx`/`SAxxxx`, ESLint, ruff, markdownlint id, or a rule the pack documents) | `analyzer-pack-rule` | in-repo configuration: enable or raise severity in `.editorconfig`, `.globalconfig`, or the linter config |
| a project-specific API or usage invariant in C# expressible over syntax or the semantic model (banned API, required attribute, misuse pattern) | `custom-analyzer` | Microsoft Learn analyzer tutorial |
| a code pattern expressible as a syntactic match in any language (dangerous call, injection sink, secret shape, cross-language invariant); also the custom-analyzer class in a non-.NET ecosystem | `semgrep-rule` | `semgrep-rule-creator` plugin, gated; else Semgrep rule-writing docs |
| dependency direction, layering, namespace-to-layer naming, forbidden references | `architecture-test` | ArchUnitNET docs (.NET); dependency-cruiser docs (JS/TS) |
| process and workflow: commit shape, file placement, generated-file freshness, session behaviour, anything observed at tool-call or commit time rather than in source | `hook` | `claude-config` plugin's `audit-automation-gaps hooks`, gated; else record and stop |
| design judgment, readability, correctness reasoning, prose quality, `unclassified` | `llm-only` | none; the finding stays a review-time judgment |

Then three lookup sections, each keyed the way the ladder step reads it:

- **Rule-id rows** (exact match on the qualified id, the detector-findings convention's one form):
  one row per rule id the six adopters emit today, each with its class. The producing detector is
  named as the owner where the detector itself is already the deterministic rung ("already
  deterministic: keep the detector", rung `analyzer-pack-rule`): every `ai-slop/audit/rule-*`,
  `docs-hygiene/audit-noise/rule-*`, `claude-config/audit-instructions/rule-*`, and
  `provenance/audit/rule-*` id. `testing/audit/rule-*` ids → `analyzer-pack-rule` where a
  test-framework analyzer covers the rule, else `custom-analyzer`. `mutation-testing/audit/rule-*`
  ids → `llm-only` (the covering test is judgment).
- **Rule-family rows** (prefix match on `<plugin>/<skill>/`, a distinct and lower ladder step, so a
  rule id added upstream after this table was written still lands on its family's class rather
  than on judgment): one row per adopter.
- **Dimension rows**: `architecture` → `architecture-test`; `security` → `semgrep-rule`; `docs` →
  `llm-only`; a default row: any other or unlisted dimension → fall through to the judgment step.

Every row carries its basis in one clause so a reader can dispute it.

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
class-basis: rule-id | rule-family | dimension | judgment | unresolved
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
top-level `branch:` key, a `## Findings` heading. Filename: `<rank, two digits>-<rung>-<slug>.md`
where `<slug>` is the first 40 chars of the `Location` sanitized to `[a-z0-9._-]`.

**Sanity Check** (each run against the unmodified tree; recorded exit code in parentheses):

- `test -f plugins/review/skills/audit-enforceability/SKILL.md` exits 0 (now 1).
- `test -f plugins/review/skills/audit-enforceability/context/crosswalk.md && test -f plugins/review/skills/audit-enforceability/context/stub-shape.md` exits 0 (now 1).
- `test -d plugins/review/skills/audit-enforceability && ! grep -rq -e '@melodic-software' -e 'MELODIC_' -e 'docs/conventions/' plugins/review/skills/audit-enforceability/` exits 0 (now 1; the `test -d` is what makes it fail, since a bare `! grep` on a missing directory passes).
- `grep -q 'C1' plugins/review/skills/audit-enforceability/SKILL.md && grep -qi 'different meaning' plugins/review/skills/audit-enforceability/SKILL.md` exits 0 (now 2).
- `test "$(grep -c 'if the .* plugin is installed' plugins/review/skills/audit-enforceability/SKILL.md 2>/dev/null || true)" -ge 2` exits 0 (now 2, an empty count on a missing file; `grep -c` exits 1 on zero matches, so the `|| true` keeps the count readable under `set -e`).

## Phase 2. Stub writer, test, fixture. #3815 [TODO]

**Create** `scripts/emit-stubs.sh`, `scripts/emit-stubs.test.sh`,
`evals/fixtures/findings-one-per-rung.md`, `evals/fixtures/classification-one-per-rung.tsv`.

### `emit-stubs.sh` CLI contract

```text
emit-stubs.sh --findings <file> --classes <tsv> --out <dir> --scan-dir <dir> [--dry-run]
```

- `--findings`: one file. Must exist, must declare `type: review-findings`, must carry a
  parseable `## Findings` table. Otherwise exit 2 with a one-line diagnostic and write nothing.
- `--classes`: TSV, one line per rank: `rank<TAB>class<TAB>basis<TAB>rung<TAB>owner`. A rank
  present in the table but absent from the TSV gets `unclassified / unresolved / llm-only / none`
  rather than no stub. A rank in the TSV absent from the table is a diagnostic, not a stub.
- `--out`: the resolved stub home. `--scan-dir`: the resolved reviews location the fix action
  scans for this branch. Both are resolved by the caller through the binding; the script never
  resolves either. The script refuses (exit 3, writes nothing) when `--out` resolves to
  `--scan-dir` or any path under it, and also when `--out` resolves to the findings file's own
  directory or any path under it (a second fence for an input that already sits in place).
- Parses the table by splitting on unescaped pipes, unescaping `\|` in cells. Filename per the
  stub shape. Never overwrites: an existing path takes a `-2`, `-3` suffix.
- After writing, re-reads every stub it wrote and fails (exit 4, stubs removed) if any contains a
  forbidden marker. The writer is the fence.
- Prints `N findings → N stubs in <out>` on success; exit 0. `--dry-run` prints the planned
  filenames and writes nothing.

### `emit-stubs.test.sh`

Shell test in the repo's `*.test.sh` idiom. Cases, each named:

1. fixture with seven rows (one per rung) → seven stubs, one per rank, exit 0;
2. every stub declares `type: enforceability-stub` and none matches
   `^type: review-findings|^type: fix-pass-record|^branch:|^## Findings`;
3. the fix action's Step 1 candidate predicate, replicated as
   `grep -l '^type: review-findings' <out>/*.md`, returns nothing;
4. `--out` equal to, or under, `--scan-dir` → exit 3, no files; `--out` equal to, or under, the
   findings file's directory → exit 3, no files;
5. missing `--findings` → exit 2; a file without `type: review-findings` → exit 2; missing
   `--scan-dir` → exit 2;
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

- `bash plugins/review/skills/audit-enforceability/scripts/emit-stubs.test.sh` exits 0 (now 127,
  the file does not exist).
- `bash scripts/affected-tests.sh --explain plugins/review/skills/audit-enforceability/scripts/emit-stubs.sh 2>&1 | grep -q 'emit-stubs.test.sh'` exits 0 (now 1; the selector itself exits 0 with "No suites selected", so the grep is the check).
- After the test runs its fixture into a temp dir `$T`: `! grep -rq -e '^type: review-findings' -e '^branch:' -e '^## Findings' "$T"` exits 0 and `ls "$T"/*.md | wc -l` prints 7.

## Phase 3. Reserved concern name, evals, plugin bookkeeping. #3815 [TODO]

**Create** `evals/evals.json`. **Modify** `plugins/review/README.md`,
`plugins/review/reference/topic-docs.md`, `plugins/review/CHANGELOG.md`,
`plugins/review/.claude-plugin/plugin.json`, `docs/SKILL-CHEAT-SHEET.md` (regenerated),
`docs/conventions/topic-docs/README.md`, `docs/conventions/topic-docs/topic-docs.schema.json`,
`docs/conventions/topic-docs/CHANGELOG.md`.

- **Reserved name `enforceability`** in the topic-docs convention, done exactly the way
  `overengineering` was added in 2.5.1: the "Memory, concern-scoped" tier row gains
  `.work/enforceability/<branch-slug>/` and "enforcement-rung proposal stubs"; the reserved
  first-level names list in "Slug and filename spec" gains `enforceability`; the Implementers row
  for `review` becomes "review reports; enforceability stubs | memory (`reviews/`,
  `enforceability/<branch-slug>/`)"; the schema's `memory_dir` description lists the new name;
  the CHANGELOG gains `## 3.1.1 — <date>` as a docs-only patch citing the 2.5.1 precedent. The
  parity script gates convention changelogs, so the heading form matters.
- `reference/topic-docs.md` (review binding): add the stub artifact row under "What this plugin
  writes" (`.work/enforceability/<branch-slug>/<rank>-<rung>-<slug>.md`, never committed); add a
  second resolution list for the `enforceability` concern with the same five rungs as `reviews/`
  (rung 1 and 5 compose `enforceability/<branch-slug>`; rungs 2 to 4 yield a declared, inferred,
  or chosen location; persisting at rungs 2 to 4 is ask-gated; non-interactive collapse cited);
  state that the fix action's scan directory is the reviews location and the stub home must never
  resolve inside it.
- `evals.json`: at least five cases: one-per-rung fixture run (expects seven stubs, each naming a
  rung and owner); a missing-file refusal; a rule-id row classified by its rule-id row, not prose;
  a Boundary question ("is this the C3 promotion thing?") answered with the disambiguation; a
  no-implementation case (asked to "just write the analyzer", the skill declines and points).
  Include one refusal case, which the eval-quality lint asks for.
- README `### Skills`: add the `/review:audit-enforceability <findings-file>` bullet. README
  "Findings location": one sentence that enforceability stubs land under the memory root's
  `enforceability/<branch-slug>/`, a sibling of `reviews/`, never inside it.
- `plugin.json`: version `0.27.0` (new skill is a minor bump; precedent: `setup` shipped as
  0.9.0 → 0.10.0); description names the new skill.
- `CHANGELOG.md`: `## [0.27.0]` / `### Added` entry.
- `docs/SKILL-CHEAT-SHEET.md`: run `node scripts/generate-cheatsheet.mjs`; do not hand-edit.
  `scripts/validate-plugins.sh` runs `generate-cheatsheet.mjs --check` in CI, so a stale sheet
  fails the build.
- Run `bash plugins/skill-quality/scripts/check-skill.sh --require-evals audit-enforceability`
  with `CHECK_SKILL_SKILLS_ROOT=plugins/review/skills`; fix every `FAIL:`.
- Run `npx markdownlint-cli2` over every changed markdown file.

**Sanity Check:**

- `CHECK_SKILL_SKILLS_ROOT=plugins/review/skills bash plugins/skill-quality/scripts/check-skill.sh --require-evals audit-enforceability` exits 0 (now 1).
- `grep -q 'audit-enforceability' plugins/review/README.md` exits 0 (now 1).
- `grep -q '^## \[0.27.0\]' plugins/review/CHANGELOG.md` exits 0 (now 1).
- `grep -q '"version": "0.27.0"' plugins/review/.claude-plugin/plugin.json` exits 0 (now 1).
- `grep -q 'review:audit-enforceability' docs/SKILL-CHEAT-SHEET.md` exits 0 (now 1).
- `grep -q 'enforceability' plugins/review/reference/topic-docs.md` exits 0 (now 1).
- `grep -q 'enforceability' docs/conventions/topic-docs/topic-docs.schema.json && grep -q '^## 3.1.1' docs/conventions/topic-docs/CHANGELOG.md` exits 0 (now 1).
- `test "$(grep -c 'enforceability' docs/conventions/topic-docs/README.md || true)" -ge 3` exits 0 (now 1; the tier row, the reserved list, and the Implementers row).

CI gates that must also pass, listed separately because they pass on the unmodified tree and so
prove nothing on their own: `bash scripts/check-changelog-parity.sh --check-bump origin/main`
exits 0; `node scripts/generate-cheatsheet.mjs --check` exits 0;
`npx markdownlint-cli2 "plugins/review/**/*.md" "docs/SKILL-CHEAT-SHEET.md" "docs/conventions/topic-docs/*.md"`
exits 0; `bash scripts/check-orphaned-fixtures.sh --check` exits 0.

## Test strategy

Two halves, verified differently, and the slice body says which proves what:

- **Writer invariants are deterministic** and are proven by `emit-stubs.test.sh`: one stub per
  row, no marker, no home inside the scanned directory or the input's directory, escaped pipes
  preserved, refusal on bad input, no overwrite. Test-first: write the eight cases, run red,
  implement the script.
- **Classification is a judgment step** and is proven by evals, not by a shell test: the
  one-per-rung fixture case asserts the rung and owner each row lands on; the rule-id case
  asserts the ladder's first step wins over prose.
- "The fix pass consumes none of the stubs" is proven structurally: test case 3 replicates the
  fix action's Step 1 predicate over the stub directory and asserts empty, and test case 4 proves
  the writer refuses a home inside the directory that action scans. Running the real fix action
  is not a test (it is model-driven and needs a branch with findings); the predicate replication
  plus the fence is, and the #3815 acceptance criterion says so.
- Boundaries driven by tests: `emit-stubs.sh`'s CLI (new). The findings-file shape (existing) is
  driven only as input.
- Existing tests to update: none. `standards-binding.test.sh` greps `quality-gate` and `setup`
  only.

## Files affected

| File | Action | What changes |
|---|---|---|
| `plugins/review/skills/audit-enforceability/SKILL.md` | Create | Skill body per Phase 1 |
| `plugins/review/skills/audit-enforceability/context/crosswalk.md` | Create | Class → rung → owner table; rule-id, rule-family, and dimension sections |
| `plugins/review/skills/audit-enforceability/context/stub-shape.md` | Create | Stub frontmatter, body, filename, forbidden markers |
| `plugins/review/skills/audit-enforceability/scripts/emit-stubs.sh` | Create | Deterministic writer with both fences |
| `plugins/review/skills/audit-enforceability/scripts/emit-stubs.test.sh` | Create | Eight cases |
| `plugins/review/skills/audit-enforceability/evals/evals.json` | Create | Five or more cases |
| `plugins/review/skills/audit-enforceability/evals/fixtures/findings-one-per-rung.md` | Create | Conforming fixture |
| `plugins/review/skills/audit-enforceability/evals/fixtures/classification-one-per-rung.tsv` | Create | Classification input for the test |
| `plugins/review/README.md` | Modify | Skills list; findings-location sentence |
| `plugins/review/reference/topic-docs.md` | Modify | New artifact row; second concern's resolution ladder; scan-directory statement |
| `plugins/review/CHANGELOG.md` | Modify | `## [0.27.0]` Added |
| `plugins/review/.claude-plugin/plugin.json` | Modify | version, description |
| `docs/SKILL-CHEAT-SHEET.md` | Modify | Regenerated |
| `docs/conventions/topic-docs/README.md` | Modify | Tier row, reserved list, Implementers row |
| `docs/conventions/topic-docs/topic-docs.schema.json` | Modify | `memory_dir` description lists the name |
| `docs/conventions/topic-docs/CHANGELOG.md` | Modify | `## 3.1.1 — <date>` docs-only patch |

Sixteen files, so the checkbox inventory lives in the #3815 body.

## Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Stubs in a topic slice `<memory_dir>/<slug>/enforceability/` (revision 1) | The review binding resolves a review-artifacts location, and only rungs 1 and 5 expose a memory root, so `<memory_dir>` is underivable at rungs 2 to 4; a branch-derived slug violates the topic-slug spec; a same-slug existing directory resumes into a live slice; a second artifact family in a leaf slice creates an `INDEX.md` obligation. | Never. |
| Stubs under `reviews/<branch-slug>/enforceability/` | The fix action's scan is a non-recursive glob over that directory, so a subdirectory is technically outside it, but the Brief says outside the branch findings directory and the convention keeps reserved names flat. | Never. |
| Model writes stubs directly, no script | The invariants that matter (no marker, outside the scan, one per row) would be instruction-strength only, and the acceptance criteria demand a fixture-driven proof. | Never for this increment. |
| Gate the stub write behind `--persist-stubs`, as detector adopters gate `--persist-findings` | Those adopters gate because their files reach an apply relay; stubs reach none and are the audit's report, the posture `overengineering:audit` already takes for its memory-tier findings artifact. The Brief's criterion says the skill emits stubs when given a file. | A consumer of stubs appears (then the write feeds a relay and earns a gate). |
| Extend the fix action with an "enforce" route | Mixes a mutating action with a proposal; the container's ownership decision already rejected widening an existing skill. | Never. |
| Key the crosswalk on rule id only | Fanout's own rows carry no rule id; the skill would emit LLM-only for every fanout finding. | Never; the ladder keeps rule id as its first step. |
| Widen `audit-automation-gaps` | Rejected on the container: wrong ownership boundary, no findings input path. | Never. |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Classification lands most rows on LLM-only, making the skill look useless | Med | Med | Rule-id, rule-family, and dimension sections give deterministic first steps; the report prints the basis per row so an operator sees why. |
| A stub is mistaken for a findings file by a future consumer | Low | High | Distinct `type:`, no `branch:` key, no `## Findings` heading, writer self-check, test cases 2 and 3. |
| Stub home resolves inside the fix action's scan directory at binding rungs 2 to 4 | Low | High | `--scan-dir` fence in the writer, test case 4; the binding states the rule. |
| The Roslyn owner pointer is a doc, not a skill, and the Brief promised a skill | High (already true) | Low | Brief amended with a dated note; deferred question asks the operator to name one. |
| Presence gate names a plugin from a foreign marketplace | Low | Med | Gate names the plugin only; the marketplace appears only in the printed install recipe, per the carve-out. |
| Cheat-sheet or changelog parity gate fails in CI | Med | Low | Phase 3 runs `generate-cheatsheet.mjs --check` and `check-changelog-parity.sh --check-bump` locally. |
| `emit-stubs.sh` table parser mishandles `\|` | Med | Med | Test case 6; parser splits on unescaped pipes only. |
| Reserved-name edit misses one of the four sites | Med | Low | Sanity Check counts three README hits and greps the schema. |

## Blast radius

- **Review plugin**: one new skill directory, README, binding, changelog, manifest. No existing
  skill body changes. `fanout` and `quality-gate` are untouched.
- **Topic-docs convention**: a new reserved first-level name, docs-only patch by the 2.5.1
  precedent. No tier moves, no key renames, no slug-spec change, no visibility change. Other
  implementers are unaffected: a reserved name only forbids a topic slug from colliding with it,
  and the `-x` suffix rule already covers that.
- **Generated docs**: cheat sheet regenerated.
- **Consumers**: none at runtime until an operator invokes the skill. The stub home is memory
  tier and self-ignoring.
- **CI**: `check-changed-skills.sh` runs the skill-quality gate with `--require-evals` on the
  new skill; `check-changelog-parity.sh --check-bump` sees the plugin and convention version
  changes; `validate-plugins.sh` runs the cheat-sheet drift check; the orphaned-fixtures gate sees
  the fixture consumed by the test and evals; `affected-tests.sh` maps the new script to its
  co-located test.

## Execution-shape analysis

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | SKILL.md, context/crosswalk.md, context/stub-shape.md | none |
| 2 | scripts/emit-stubs.sh, scripts/emit-stubs.test.sh, evals/fixtures/* | none |
| 3 | evals/evals.json, README, reference/topic-docs.md, CHANGELOG, plugin.json, cheat sheet, convention README, schema, convention changelog | none |

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
| Stub home is a reserved concern name `enforceability/<branch-slug>/` | Revision 2 note; 2.5.1 precedent makes it a docs-only patch; reserved names stay flat and resolve through the same binding shape as `reviews/` |
| Writer fences against the resolved reviews location, not the input's directory | The fix action scans the binding's resolved location; the input file may sit anywhere |
| Bare invocation writes stubs | They are the report, memory-tier, relay-free; `overengineering:audit` precedent |
| Roslyn rung owner is a doc pointer | No nameable installable skill exists; an unnamed collaborator cannot be gated |
| Hook handoff is operator-carried | The gaps skill self-generates candidates and has no findings input |
| Classification ladder: exact rule id, rule family, dimension, judgment, unresolved | The input carries no class column; exact match is the convention's one id form; the family step keeps upstream-added ids off the judgment step |
| Deterministic writer script with a test | The acceptance criteria demand fixture-driven proof of writer invariants |

## Deferred questions

- Which upstream Roslyn analyzer authoring skill did the Brief intend? If the operator names an
  installable plugin, the custom-analyzer row gains a presence gate and the doc pointer becomes
  its fallback.
- Should the crosswalk's rung vocabulary adopt or cite the fleet standard's enforceability-tier
  vocabulary (`enforceability-tiers.md` in the standards repository) rather than the Brief's
  seven-rung ladder? The Brief's ladder is a captured assumption; the two may be the same thing at
  different grain.
- Cross-run recurrence (carried from the container): evidence threshold and where history lives.
  The stub's `source-sha256` and `source-findings` fields are the hook a later increment keys on.
- Whether a stub should be gated behind a persist flag once a consumer of stubs exists.

## Handoff to implementation

The #3815 body carries every contract above that a worker needs: the working name, the class
ladder and vocabulary, the crosswalk table and its three lookup sections, the stub shape and
forbidden markers, the script CLI with both fences and its exit codes, the eight test cases, the
fixture requirements, the four reserved-name edit sites, the bookkeeping list, and the
presence-gated references with their fallbacks. A worker cut from `main` never sees this file.
