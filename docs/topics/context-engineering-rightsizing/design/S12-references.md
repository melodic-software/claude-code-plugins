# S12 — "Applying this to your context → References"

Source span: `source-article.md:111-114`.

## Claims

1. **`@` mention loads a file as a reference.**
   > "You can @ mention files to include them as references."

2. **References serve in-depth information about the current plan.**
   > "References allow Claude to refer to in-depth information about the current plan."

3. **A reference may be a spec file, a mockup, or an entire codebase.**
   > "This might be in specs files, mockups, or even entire codebases."

4. **Prefer code-shaped references, because code is high-fidelity in a language Claude knows well.**
   > "Generally you should prefer files that are in code as it provides clear, high-fidelity
   > instructions to Claude in a language it knows very well."

5. **Worked ordering: HTML mockup > prose description > screenshot.**
   > "For example, a HTML mockup of a design will generally produce better results than a description
   > of the design or a screenshot."

## Evidence status

All URLs fetched this session (2026-07-24).

### Claim 1 — CONFIRMED, with three precisions the article omits

<https://code.claude.com/docs/en/common-workflows.md>, "Reference files and directories":

> "Use @ to quickly include files or directories without waiting for Claude to read them."
> "\[Reference a single file] … This includes the full content of the file in the conversation."
> "\[Reference a directory] … This provides a directory listing with file information."
> "Directory references show file listings, not contents"
> "@ file references add `CLAUDE.md` in the file's directory and parent directories to context"
> "\[Reference MCP resources] … This fetches data from connected MCP servers using the format
> @server:resource."

<https://code.claude.com/docs/en/best-practices.md>, "Provide rich content":

> "**Reference files with `@`** instead of describing where code lives. Claude reads the file before
> responding."

**Load timing — eager.** The two pages word the mechanism differently ("includes the full content in
the conversation" vs. "Claude reads the file before responding"). The *observable* both agree on: the
file's content is present before Claude's first response and costs its full token count on that turn.
I state the observable, not the implementation — I did not find a page that settles whether the
content is injected into the user message or produced by a forced read.

**Not the same as an import.** `@path/to/import` inside a CLAUDE.md is a distinct mechanism.
<https://code.claude.com/docs/en/memory.md>:

> "CLAUDE.md files can import additional files using `@path/to/import` syntax. Imported files are
> expanded and loaded into context at launch alongside the CLAUDE.md that references them."
> "Imported files can recursively import other files, with a maximum depth of four hops."
> "Import parsing skips Markdown code spans and fenced code blocks."
> "Splitting into [`@path` imports](#import-additional-files) helps organization but doesn't reduce
> context, since imported files load at launch."
> "You can also split content into imports for organization, though imported files still load and
> enter the context window at launch."

Difference that matters: a prompt `@` is **elected by the human, once, at the point of need**; a
CLAUDE.md `@` import is **unconditional and recurring — every session, before any task is known**.

**No size threshold.** No fetched page gives a file-size or token limit above which `@` is
discouraged. Any threshold in a downstream criterion is ours, not Anthropic's.

**`@` is a memory-file / prompt mechanism, not a skill mechanism.** Nothing in
<https://code.claude.com/docs/en/skills.md> gives `@path` meaning inside a `SKILL.md`. Skill
supporting files load the other way:

> "Skills can include multiple files in their directory. This keeps `SKILL.md` focused on the
> essentials while letting Claude access detailed reference material only when needed. Large
> reference docs, API specifications, or example collections don't need to load into context every
> time the skill runs."

### Claim 2 — PARTIAL

Docs endorse pointing Claude at sources and at a written spec, and describe what a good spec
contains (<https://code.claude.com/docs/en/best-practices.md>):

> "**Point to sources.** Direct Claude to the source that can answer a question."
> "**Reference existing patterns.** Point Claude to patterns in your codebase."
> "The most useful specs are self-contained: they name the files and interfaces involved, state what
> is out of scope, and end with an end-to-end verification step that proves the feature works."

Unbacked half: no fetched page names "references" as a context-engineering primitive, and none ties
`@` mentions specifically to *the current plan*. The plan-mode pages describe plans as Claude's own
output for approval, not as a thing references attach to. The article is coining a category here.

### Claim 3 — PARTIAL (precision, not contradiction)

- **Spec files** — CONFIRMED. best-practices.md documents the interview → `SPEC.md` → fresh session
  workflow: "Keep interviewing until we've covered everything, then write a complete spec to
  SPEC.md. … Once the spec is complete, start a fresh session to execute it."
- **Mockups** — CONFIRMED for images. common-workflows.md, "Work with images": "Generate CSS to match
  this design mockup", "What HTML structure would recreate this component?"
- **Entire codebases** — PARTIAL. `@dir` yields a listing, not contents ("Directory references show
  file listings, not contents"). This does not make the claim false: the reference is a *pointer* the
  agent then pulls from with its own tools. It does mean "reference an entire codebase" cannot be
  read as "`@` the repo root and it loads."

### Claim 4 — UNBACKED

No fetched page states a preference ordering between code-shaped and prose references. Docs
consistently favor *specificity* and *verifiability* (a test suite, a build exit code, a diff against
a fixture, a screenshot comparison), which is adjacent but not the same claim. This is a legitimate
UNBACKED, not a failure — it is Anthropic-authored guidance published outside the docs site.

### Claim 5 — UNBACKED, and in friction with two doc workflows

No page ranks HTML mockup / prose description / screenshot. The docs instead present the screenshot
as a first-class design source of truth. best-practices.md, "Give Claude a way to verify its work":

> "**Verify UI changes visually** … *"\[paste screenshot] implement this design. take a screenshot of
> the result and compare it to the original. list differences and fix them"*"

and:

> "The check is anything that returns a signal Claude can read in the conversation: a test suite, a
> build exit code, a linter, a script that diffs output against a fixture, or a browser screenshot
> compared against a design."

The article says "generally," so this is friction rather than contradiction — but a criterion that
penalizes screenshots would contradict current official guidance. See Conflicts.

## Criteria

### C12.1 — An eager import must earn every session (highest leverage)

- **Surface**: `CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/*.md` — this repo, and (routed only)
  user scope.
- **Detection (mechanical)**: an `@path` token outside backticks and outside a fenced block that
  resolves to a file. Every hit is surfaced; the import loads at launch regardless of task,
  recursively to four hops.
- **Adjudication (human, not mechanical)**: a surfaced hit passes or fails on the question "is this
  content needed in *every* session of this scope?" There is no mechanical substitute — the docs give
  no size threshold (see Conflicts), and inventing one locally would be the over-constraint the
  article argues against. Stating this split matters: a judgment dressed as an observable would give
  a false sense of a decidable check.
- **Must NOT flag**: a backticked path (`` `@README` `` — docs state this stays literal); a markdown
  link such as `[docs/PLUGIN-PHILOSOPHY.md](docs/PLUGIN-PHILOSOPHY.md)`, which does not load; `@`
  inside a fenced block; `@anthropic-ai/...` package scopes; email addresses; `@username` handles; an
  import that genuinely is needed every session (e.g. `@AGENTS.md` as the documented single-source
  pattern).

### C12.2 — `@` in a SKILL.md is literal text, not a load

- **Surface**: SKILL.md body, skill `references/*.md`, agent definitions, plugin READMEs.
- **Observable**: FAIL when `@path.ext` appears in prose in a way that implies it loads the file
  (e.g. "see @reference.md for details"). The correct form on this surface is a path plus an explicit
  instruction to read it.
- **Must NOT flag**: package scopes, decorators, emails, handles, backticked `@`, or a path written
  without `@`.
- Forward-looking guard: this is the single most likely way an author mis-applies S12's one sentence
  to the wrong surface.

### C12.3 — Do not restate in markdown a structure a machine-readable sibling already defines

- **Surface**: SKILL.md body, skill `references/*.md`, plugin README.
- **Observable**: FAIL when the markdown embeds or enumerates a structure (field list, `required`
  set, allowed values) that a sibling `*.schema.json` or catalog `*.jsonc` already defines, and does
  not cite that artifact by path.
- **Must NOT flag**: a one-line summary that names the artifact by path and stops; a structure with
  no machine-readable counterpart (the markdown copy is then the only source and is legitimate);
  tooling config such as `.markdownlint-cli2.jsonc`; test fixtures; anything under `evals/`.

### C12.4 — A plan's reference slot must admit code-shaped artifacts

- **Surface**: plan/spec templates and the artifacts they produce.
- **Observable**: FAIL when the template prompts for the artifacts a plan is built against **nowhere**
  — not in a dedicated section, not in its steps, not in a grounding slot. Where such a slot exists,
  FAIL instead when its wording admits only documentary sources and gives no place for a schema, a
  failing test, an implementation to port, or a mockup, cited by path.
- **Must NOT flag**: the abbreviated template for trivial tasks; a plan whose work has no external
  reference; a plan that cites references inline in its steps rather than in a dedicated section
  (this is why the check is on the template's prompting, not on a heading name).

### C12.5 — Prefer the code-shaped form only when one exists or is cheap

- **Surface**: SKILL.md, plugin README, plan/spec artifact.
- **Observable**: FAIL when the artifact describes a target output, design, or contract in prose
  **and** a code-shaped form of the same thing already exists uncited in the tree.
- **Must NOT flag**: prose chosen because the code-shaped form demonstrably cannot express the
  constraint, when the rationale is recorded (see the verified example under Targets); prose that is
  the deliverable itself (a skill body is prose by construction — see Conflicts).

## Targets in this repo

Population commands were run in `D:/repos/.worktrees/context-engineering-rightsizing`.

```
find plugins -name SKILL.md -path '*/skills/*' | wc -l      → 187
ls -1d plugins/*/ | wc -l                                    → 60
find plugins -name 'evals.json' | wc -l                      → 155
find plugins -name '*schema*.json' | wc -l                   → 5
grep -rln --include='*.md' '"\$schema"' plugins/ docs/       → 2 (1 false positive)
grep -rn --include=SKILL.md -E '(^|[[:space:]])@[a-zA-Z0-9_./~-]+\.(md|json|ts|js|py|sh|ps1)' plugins/ → 0
grep -nE '(^|[[:space:]])@[a-zA-Z0-9_./~-]+' CLAUDE.md       → 0
```

### C12.1 / C12.2 — zero current hits, both forward-looking

- `CLAUDE.md:1-63` — no `@` imports. Cross-file pointers use markdown links
  (`CLAUDE.md:54-57`), which do not load eagerly. Correct on both axes; **must not flag**.
- `~/.claude/CLAUDE.md:58-69` (user scope, read-only, verified by reading the file) — the "Reference
  docs (read on demand)" section lists five backticked paths under the explicit line "These files are
  not loaded automatically. Use the Read tool when the task touches that domain." Zero `@` imports in
  the file. This is S12 and S5 jointly satisfied and is the canonical **must not flag** case. Routed
  as an observation only; no change proposed.
- 187 SKILL.md files, 0 uses of `@path.ext`. The guard has no current violations.
- **Transitive cost of a prompt `@` is currently nil.** common-workflows.md states "@ file references
  add `CLAUDE.md` in the file's directory and parent directories to context", which makes a
  prompt-level `@` on a nested file a transitively eager load in a repo with nested memory files.
  `find . -name 'CLAUDE.md' -not -path './node_modules/*'` returns exactly one hit (`./CLAUDE.md`,
  63 lines) and `find . -type d -name 'rules' -path '*.claude*'` returns none. So `@`-mentioning any
  file here pulls in only the root CLAUDE.md, which a session rooted here already loads — no
  additional cost today. Re-check if per-plugin CLAUDE.md files or `.claude/rules/` are ever added;
  at that point C12.1's surface list grows and the per-`@` cost stops being free.

### C12.3 — one real target, verified

`plugins/machine-health/skills/audit/references/shared/output-schema.md:1-39` opens with

> "The schemas below are normative — every check script, every remediation script, and the
> orchestrator must produce output validating against them."

and then embeds a hand-maintained draft-07 JSON Schema for `CheckResult` in a fenced block
(`:9-39`). A machine-readable `CheckResult` schema already exists at
`plugins/machine-health/skills/audit/catalog/schemas/check-result.schema.json:1-109`, whose own
description (`:5`) claims the enforcement role: "Enforced by `Write-HealthResult` at emit time;
orchestrator re-validates on receipt."

Two artifacts claim normativity, and they have already diverged (both read in full this session):

| Aspect | `output-schema.md:9-39` | `check-result.schema.json` |
|---|---|---|
| dialect | draft-07 | 2020-12 |
| `required` | 9 fields | 14 fields (adds `commands`, `detail`, `error`, `notes`, `trend`) |
| `additionalProperties` | absent (open) | `false` (`:7`) |
| `id` | no pattern | kebab-case regex (`:27`) |
| `summary` | plain string | `minLength: 1`, `maxLength: 240` (`:47-48`) |
| `duration_ms` | `minimum: 0` | `minimum: 0`, `maximum: 90000` (`:67-68`) |
| `notes` | `"type": "string"` | `["string", "null"]` (`:83`) |
| `trend.adjusted_from` | free `["string","null"]` | `$ref` to the `Severity` enum (`:77-79`) |
| conditional rule | none | `allOf`/`if`: `ran_successfully: false` ⇒ severity `UNKNOWN` and non-empty `error` (`:91-102`) |

The three other structures in the same file — `RunSnapshot` (`:71-96`), `RemediationAttempt`
(`:102-119`), history line (`:125-140`) — have **no** machine-readable counterpart, so the markdown
copy is the only source and **must not be flagged**. The criterion is per-structure, not per-file.

Related, and weaker: `catalog/schemas/checks.schema.json` is referenced from no markdown at all —
its only citation in the tree is a PowerShell comment,
`plugins/machine-health/skills/audit/scripts/windows/lib/Assert-CatalogEntry.ps1:9` ("authoritative
schema lives in catalog/schemas/checks.schema.json"). That is code pointing at code, which satisfies
the spirit of claim 4; the gap is only that `SKILL.md` and `references/shared/discovery-guide.md:35`
prescribe catalog fields (`added_on`, `crash_count`, `identical_streak`) without the pointer.

Contrast — already correct, **must not flag**:
- `plugins/autonomy/skills/setup/SKILL.md:164,264,315` cites
  `schemas/guardrails-security-binding.schema.json` three times as a linked path.
- `plugins/skill-quality/skills/check/SKILL.md:92` cites
  `${CLAUDE_PLUGIN_ROOT}/reference/evals.schema.json` as a linked path.
- `plugins/machine-health/skills/audit/references/shared/approvals.md:5` — "Schema:
  `catalog/schemas/approvals.schema.json`" — pointer, no restatement. This is the exact shape
  `output-schema.md` should take.
- `CLAUDE.md:32-35` points at the two SchemaStore URLs for `marketplace.json` and `plugin.json`
  instead of restating either manifest's fields.

### C12.4 — a slot exists, but it admits only documentary sources

Not an absence finding. `plugins/planning/skills/plan/context/plan-template.md:13-19` already carries
a reference-citation slot, read in full:

> `## Standards grounding`
> `<which consumer standards shaped this plan — from the grounding step. …>`
> `| Surface | Sections cited | Layer provenance |`

That is a by-path citation table with provenance — structurally the right thing. Its scope is the
problem: "consumer standards" and "file + section(s) loaded" admit governance prose and nothing else.
A schema, a failing test, an implementation to port, or an HTML mockup has no row it fits. So C12.4
fires on wording, not absence, and the remedy is an amendment to an existing slot rather than a new
section.

- `grep -rn '^#\+ *References' plugins/planning/` returns nothing, but per the criterion that alone
  decides nothing — heading names are not the observable.
- `plugins/planning/skills/interview/templates/checklist.md:11` defines the persisted contract as
  "goal + constraints + acceptance criteria + captured assumptions". No reference slot at all here,
  documentary or otherwise.
- Nearest existing hook: `plan-template.md:152` already requires mechanically verifiable sanity
  checks ("a specific grep, file Read assertion, build exit code, test exit code, or runtime probe"),
  which is claim 4's spirit applied to *verification*. Extending it to *inputs* is the small edit.

### C12.5 — the repo mostly already complies

- `plugins/prototype/skills/explore-directions/SKILL.md:46-107` ships a "self-contained HTML mockup"
  substrate as a first-class output, alongside the real-stack substrate. This is claim 5's preferred
  artifact already implemented as a capability. **Must not flag**; cite as the positive case.
- `plugins/implementation/skills/implement/context/bugfix.md:7` — "the failing test IS the bug
  report" — and `plugins/implementation/skills/implement/SKILL.md:68` (Red-Green-Refactor, one test
  at a time) are claim 4 applied to specs. Already aligned.
- `docs/topics/plugin-fleet-sync-skill/PLAN.md:176` is the verified **must not flag** for C12.5: the
  plan fetched the manifest schema, established that `userConfig` has no `enum` key
  (`additionalProperties: false`), and recorded prose validation as the documented fallback. The
  code-shaped form was unavailable and the rationale is on the page.

### The "could exist" half — swept, nothing found, here is where I looked

The brief asked where the repo steers toward prose when a structured reference **exists or could
exist**. The "exists" half is C12.3 above. For "could exist" I found no target, and the surfaces
swept were:

```
grep -rlnE '^#+ .*(output format|report format|output shape|response format)' --include=SKILL.md plugins/  → 7
grep -rlniE 'json (shape|schema|contract)|output contract' --include=README.md plugins/                     → 3
```

The 7 SKILL.md hits (`plugins/codebase-health/skills/audit/SKILL.md:208`,
`plugins/discovery/skills/blindspot/SKILL.md:51`, `plugins/discovery/skills/explore/SKILL.md:124`,
`plugins/discovery/skills/research/SKILL.md:152`,
`plugins/docs-hygiene/skills/audit-encapsulation/SKILL.md:118`,
`plugins/knowledge/skills/course-digest/SKILL.md:209`,
`plugins/planning/skills/devils-advocate/SKILL.md:169`) all specify a **human-facing markdown report
shape**, not a machine-parsed payload. There is nothing for a schema to validate, so introducing one
would be worse, not better. Recorded as a negative result rather than a finding; the "could exist"
lever is genuinely not loaded in this repo today.

## Conflicts and ambiguity

**1. S12 vs. S5, and where the boundary actually falls.** The article says references carry
"in-depth information" and, four paragraphs earlier (`source-article.md:58-67`), says to use
progressive disclosure and to stop treating instruction files as central repositories. Both are true;
the axis that separates them is not eager-vs-lazy, because **both `@` forms are eager**. It is
*unconditional and recurring* vs. *elected at the point of need*:

| Mechanism | Loads | Cost profile | Progressive? |
|---|---|---|---|
| `@file` in a prompt | full content, that turn | once, when the human decides it is needed | yes — disclosure performed by the human |
| `@path` import in CLAUDE.md | full content, at launch, recursive to 4 hops | every session, before any task is known | **no** — docs: "doesn't reduce context" |
| skill supporting file | on demand via Read | only when the skill runs and needs it | yes |

So there is no tension at all for the prompt-level `@` the article is describing — a large reference
pulled in deliberately for one plan is exactly what S5 wants. The tension is real and sharp only for
a reader who applies S12's sentence inside a CLAUDE.md, where the same character means something
else. That mis-application is the single most valuable thing this section produces.

**2. No size boundary exists in the docs.** I looked for one on memory.md, best-practices.md,
common-workflows.md, context-window.md (via the index), and skills.md, and found none for `@`. The
only quantified limits I found are unrelated (CLAUDE.md's advisory "target under 200 lines"; auto
memory's 200-line / 25KB index cap). Any threshold this repo adopts is a local convention and must be
labeled as such.

**3. "Entire codebases" does not survive a literal reading.** `@dir` returns a listing. The claim
holds only under the pointer reading. A criterion that told authors to `@` a directory expecting its
contents would be wrong.

**4. Claim 5's ordering contradicts the docs' own screenshot workflows.** best-practices.md makes a
pasted screenshot the design source of truth in its headline verification example, and
common-workflows.md's image section endorses screenshot-to-CSS directly. A rule penalizing
screenshots would fight current official guidance. The defensible form is narrow: *when an HTML
mockup already exists, cite it rather than describing it* — which is C12.5, not a ban on screenshots.

**5. The evals population is a trap, and it does not survive.** 155 `evals.json` files exist; only 2
SKILL.md files mention `evals/` at all. That ratio looks like a finding and is not one. Evals are QA
inputs consumed by `skill-quality:check` (`plugins/skill-quality/skills/check/SKILL.md:92`,
`plugins/skill-quality/README.md:59`), not runtime references for the executing model. A criterion
requiring a SKILL.md to cite its own evals would misfire on roughly 153 correctly-designed skills and
would add eager noise to every skill body. Recorded here so a later pass does not rediscover it as an
opportunity. The same reasoning retires the raw scan hits at
`plugins/claude-ops/skills/plugins/scripts/fixtures/*.json` and
`plugins/knowledge/skills/youtube-digest/extraction/harvesting/fixtures/*.json`: those are test
fixtures consumed by `fleet-state.test.sh` and by extraction tests, not model-facing references.

**6. Claim 4 would attack this repo's core artifact if applied naively.** A plugin marketplace ships
skills, and a skill *is* prose by construction — that is the format's contract. "Prefer files that
are in code" cannot mean "convert skill bodies to code." It applies only where two forms of the same
information already coexist, or where a structured form is cheap and the prose is a lossy copy of it.
C12.3 and C12.5 are scoped that way deliberately.

**7. Scope fence against S11.** `source-article.md:88` ("A spec may also be a detailed test suite, or
a function in a different codebase that Claude might port") and `:90` (rubrics) belong to the
"Simple specs → Rich references" then/now pair, which is another agent's section. That line is the
strongest available support for building criteria on test suites and evals — which is a further
reason not to build them here. My claims stop at `:111-114`.

**8. `output-schema.md` is a documentation-drift bug as much as a context-engineering finding.** The
divergences in the table above are behavioral (a script written against the markdown copy would emit
output the real schema rejects — nine required fields vs. fourteen, and `additionalProperties: false`
is unforgiving). Fixing it under this pass and filing it as a defect both work; the operator should
pick one rather than have both happen.

## Open questions for the operator

- **Does C12.3 land as a fix or a note in this pass?** Recommendation: fix. Replace the `CheckResult`
  fence in `output-schema.md:9-39` with a pointer to `catalog/schemas/check-result.schema.json` in
  the shape already used at `references/shared/approvals.md:5`; leave the three counterpart-less
  structures as-is. The two copies have measurably drifted, so this is not cosmetic.
- **Do C12.1 and C12.2 ship with zero current hits?** Recommendation: yes. Both are one-line greps
  with cheap must-not-flag lists, and they guard the exact mistake this article invites. Home them in
  an existing audit skill rather than a one-off topic artifact.
- **Amend `plan-template.md`'s existing slot, or add a new one?** Recommendation: amend. `Standards
  grounding` (`:13-19`) is already a by-path citation table; widen its wording and columns to admit
  code-shaped inputs (schema, failing test, implementation to port, mockup) rather than bolting on a
  second References section that would compete with it. Full Template only; keep it out of the
  Abbreviated Template. A new section is the wrong call precisely because the slot already exists.
- **Does the repo adopt a size threshold for `@`?** Recommendation: no. The docs give none; inventing
  one would be exactly the over-constraint the article argues against. Decide by need, not by bytes.
- **Is the machine-health schema drift in scope here or filed separately?** Recommendation: file
  separately as a defect and cite this section as the source, so the context-engineering pass does not
  silently absorb a correctness fix.

## Fence events

None. No path under `docs/topics/context-engineering-claude-5/`,
`docs/topics/fable-field-guide-audit/`, `.work/fable-field-guide-audit/`, or any other worktree was
read, listed, or grepped. `docs/topics/` was touched only at
`docs/topics/plugin-fleet-sync-skill/PLAN.md`, which is an unrelated topic. No other agent's file
under `sections/` was read; the directory was empty when I created it.
