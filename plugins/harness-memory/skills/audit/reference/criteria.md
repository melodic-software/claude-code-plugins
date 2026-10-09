# Memory Health Criteria

## Contents

- [Checks for CLAUDE.md and CLAUDE.local.md](#checks-for-claudemd-and-claudelocalmd)
- [Checks for .claude/rules/ files](#checks-for-clauderules-files)
- [Checks for auto-memory (MEMORY.md + topic files)](#checks-for-auto-memory-memorymd--topic-files)
- [Audit output format](#audit-output-format)

Version: 1.7.0
Last updated: 2026-09-20
Source: Official Claude Code docs (code.claude.com/docs/en/memory, code.claude.com/docs/en/best-practices, code.claude.com/docs/en/sub-agents, code.claude.com/docs/en/skills)

`<skill-dir>` in the commands below is the parent of this file's `reference/` directory. SKILL.md
"Script paths" renders its absolute path; put it in place of the placeholder before running a
command.

This file defines every check the audit runs. Each check has a severity, description, and instructions
for evaluation. The audit applies checks per-entity-type (CLAUDE.md, rules, memory).

Every firing rule here is our decision, in our words; a doc-derived check names the docs section it
rests on as a **Pointer** and stores none of the page's text. Unless a check says otherwise, each
pointer's as-of date is 2026-09-20 (the "Last updated" date above) and its recheck trigger is a
Claude Code release note or docs change touching the section it points at.

To refresh this file against current official guidance, run the skill's `update` action.

---

## Checks for CLAUDE.md and CLAUDE.local.md

Every C-check here applies equally to each project root `AGENTS.md` that discovery emits as an
`agents-md` surface (`AGENTS.md` and `.claude/AGENTS.md`; we audit both and assume no precedence
between them): that file IS the project instructions for the session, so the same budget, content
and currency criteria govern it. Discovery emits it only where Claude Code reads it, which
is why a repo under a one-line `@AGENTS.md` shim has no such row (the import already counts inside
the CLAUDE.md's expanded figure) and a displaced `AGENTS.md` has none either. Cite the finding
against `AGENTS.md`, not against a CLAUDE.md that is not there.

- **Pointer**: for when Claude Code reads `AGENTS.md`, see
  [When Claude Code reads AGENTS.md](https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md);
  the condition discovery applies is recorded in `scripts/lib/agents-md.sh`.
- **As of**: 2026-09-20
- **Recheck trigger**: the recheck trigger recorded in `scripts/lib/agents-md.sh` fires.

### C1: Line Budget [FAIL]

**What**: Count the visible lines that load for the file, its `@` imports expanded. Compare to the
200-line target per file.

**How to check**:

1. Run `bash "<skill-dir>/scripts/instruction-load-stats.sh" --lines --file <path>`.
   It strips block-level HTML comments (kept inside fenced code), expands `@path` imports the way
   the loader does (relative to the importing file, four hops, code spans and fences skipped), and
   counts the non-empty lines that remain. `--breakdown` lists every file that contributed, plus
   any import that is `missing`, `external` (outside the repository, listed but not expanded), or
   past the `depth` cap
2. FAIL if > 200 lines without documented justification
3. WARN if > 150 lines (approaching limit)
4. PASS if <= 150 lines
5. Report the expanded figure and, when imports contributed, the per-file breakdown: a one-line
   `CLAUDE.md` importing a 300-line `AGENTS.md` is a 301-line file for this check

**Why**: We take the docs' per-file size target as this check's 200-line budget, and read a file
over it as an adherence risk. We count `@` imports because we treat imported files as loading at
launch, so a split saves nothing; a raw line count of the root file alone passes a layer the loader
treats as one file.

- **Pointer**: for the size target, see
  [Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions);
  for imports, see [Import additional files](https://code.claude.com/docs/en/memory#import-additional-files).

**Diagnostic**: We read a rule Claude keeps ignoring as a sign the file is too long. When the audit
was prompted by a rule being ignored, add a C1 WARN naming that symptom even when steps 4-6 pass.
The branch is prompt-conditioned, so it belongs to the judgment tier. Label it "judgment
candidate" in the report; steps 1-6 remain the deterministic spine, unaffected.

- **Pointer**: for the ignored-rule symptom, see
  [Write an effective CLAUDE.md](https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md).

**Allowances**: Complex monorepos using `.claude/rules/` extensively may justify overages, and a repo
may document a deliberate exemption in its own rules (see SKILL.md "Consumer-convention extension
seam"). Report overage and justification together.

### C2: Deletion Test [WARN per line]

**What**: Flag each line whose removal would not lead Claude into a mistake.

**How to check**:

1. Strip HTML comment blocks (human-only reference, as in C1) and skip blank and purely structural
   lines (headers, separators, table/list scaffolding): only substantive instruction lines enter
   the loop
2. For each remaining line, evaluate:
   - A command Claude can't guess? → KEEP
   - A gotcha or non-obvious pattern? → KEEP
   - A project-specific convention? → KEEP
   - Could Claude figure this out by reading the code? → FLAG
   - A standard convention any senior engineer knows? → FLAG
   - Detailed reference material better suited to a skill? → FLAG
3. WARN per flagged line, with the reason ("could infer from code", "standard practice", "move to
   skill"); group findings by H1/H2 section, and collapse a section whose every line flags into one
   section-level finding

**Why**: This is the docs' per-line pruning test, applied line by line; we treat surplus lines as
diluting the ones that matter.

- **Pointer**: [Write an effective CLAUDE.md](https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md).

### C3: Content Placement [WARN]

**What**: Is each piece of content in the right layer?

**How to check**: For each section, evaluate whether it belongs in:

| Content type | Correct placement |
|-------------|------------------|
| Always-on project conventions | CLAUDE.md |
| Machine-specific config/preferences | CLAUDE.local.md |
| Language/framework-specific rules | `.claude/rules/` (path-scoped when that fits) |
| Subdirectory-specific conventions | Nested `CLAUDE.md` in that subdirectory, which we treat as on-demand for that subdirectory; post-compaction re-injection priced below. Pointer: [Choose where to put CLAUDE.md files](https://code.claude.com/docs/en/memory#choose-where-to-put-claude-md-files) |
| One-off steering for the current conversation | A conversational `@`-mention of the file (pointer: [Reference files and directories](https://code.claude.com/docs/en/common-workflows#reference-files-and-directories)); distinct from `@path` imports *in* CLAUDE.md, which load at launch every session (priced in the imports row below). **Provenance**: the one-conversation scope and the cheaper-than-any-permanent-pointer framing are inferred, not doc-stated, and the placement posture is a repo extension (that doc is outside this file's `Source:` set), so the `update` action must not overwrite this row |
| Reference material needed sometimes | Skills: the body loads on demand; a new skill's listing entry does not (priced below) |
| Learnings Claude discovered while working, not instructions you authored | Auto memory, which Claude writes rather than you; a request to remember something also belongs here rather than in CLAUDE.md. Available only while auto memory is enabled (gated below) |
| Deterministic enforcement | Hooks (guaranteed execution) |
| Compile-time/build-time rules | Analyzers, linters, architecture tests |
| Information that changes frequently | Neither: keep it out |
| Content split out of a long CLAUDE.md purely to shorten it | **Not `@path` imports**: imported files load at launch, so the split reorganizes and saves nothing |

Flag content in the wrong layer. WARN severity because moving content is a judgment call.

**Auto memory is a destination only while it is enabled. Resolve that before routing to it.** We
treat it as on by default and as switched off by `autoMemoryEnabled` or
`CLAUDE_CODE_DISABLE_AUTO_MEMORY`, with nothing written or loaded while off. Recommending that
accumulated learnings leave `CLAUDE.md` for auto memory in that state deletes them from every
future session instead of relocating them.

- **Pointer**: [Enable or disable auto memory](https://code.claude.com/docs/en/memory#enable-or-disable-auto-memory).

Rather than reading a single scope, resolve the **effective** state with the algorithm the sibling
`stateless` skill already owns in
[`skills/stateless/context/status.md`](../../stateless/context/status.md), "Resolve the effective
state": the environment variable is authoritative wherever it is
set (`1` → off, `0` → on even against `autoMemoryEnabled: false`), and only when it is unset does
settings precedence (managed > local > project > user) pick the winning `autoMemoryEnabled`, default
`true`. A `false` in a lower-precedence scope therefore does not by itself disable the destination.
When the resolved state is off, either name a destination that does load or state that enabling auto
memory is a precondition of the move, rather than proposing it unconditionally.

**Import inside a path-scoped rule: verified, not doc-stated.** A rule whose body is only
`@some/file.md` has its *imported* content inlined at session start while the rule's own body
correctly defers, so moving content into a path-scoped rule and pulling it in by import saves
nothing. Reproduced first-party on Claude Code 2.1.219 (2026-07-24); no official page states it.
**Provenance**: empirical extension, not doc-derived, so the `update` action must not overwrite it
with doc-sourced text, and it needs re-verification on a current version rather than a doc re-fetch.

**Price the move with the recommendation.** Moving content out of an always-loaded surface trades
per-session cost for post-compaction absence, and the trade differs by destination. Read the
destination's row in [official-guidance.md](official-guidance.md), "Compaction by steering method",
which holds the audit's per-destination model and its pointer, before recommending a move, and
state the cost alongside it. A rule that must persist across compaction stays unscoped or
in the project-root CLAUDE.md. A recommendation that omits this proposes a silent behavior change in
long sessions.

A **new** skill carries a second cost the compaction table does not show: the body defers, but we
price the listing entry it adds as always in context: `name` plus the combined `description` and
`when_to_use`, at up to 1,536 characters. The saving is the body minus that entry rather than
the whole body. Moving content into a skill that **already exists** adds no listing entry and does not carry
this cost. Price the entry as zero only for a skill with `disable-model-invocation: true` (which
also leaves it user-invocable only); never on the strength of `user-invocable: false`, or of a
`skillOverrides` entry against a plugin skill. State the entry as a cost of the recommended move.
Whether the target's listing budget is oversubscribed is a separate question this check does not
answer.

**Why**: We place sometimes-needed domain knowledge in skills, deterministic enforcement in hooks,
and never count an `@path` split as a saving. The per-destination compaction model and its pointer
live in [official-guidance.md](official-guidance.md), not here.

- **Pointer**: for skills and hooks as alternatives to CLAUDE.md, see
  [Write an effective CLAUDE.md](https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md)
  and [Set up hooks](https://code.claude.com/docs/en/best-practices#set-up-hooks); for imports, see
  [Import additional files](https://code.claude.com/docs/en/memory#import-additional-files).
- **Pointer** (the listing-entry cost and the zero-cost rule): for the listing cap, invocation
  control and visibility overrides, see
  [Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference),
  [Control who invokes a skill](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill)
  and [Override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings).
- **As of** (the listing-entry pointer): 2026-08-31
- **Recheck trigger** (the listing-entry pointer): a fetch of those sections no longer supports the
  1,536-character cap, the zero-cost rule, or the plugin-skill exclusion above; re-derive this
  paragraph and the listing-entry cost from them.

### C4: Specificity [WARN]

**What**: Are instructions concrete enough to verify?

**How to check**:

1. Scan for vague instructions, such as "tidy up the formatting", "keep things organized",
   "follow best practices", "write clean code"
2. Scan for instructions without actionable verbs or concrete outcomes
3. WARN for each vague instruction
4. Include a suggested rewrite

**Why**: We want each instruction concrete enough to check: a named value or command, such as
"indent with 4 spaces" or "run `make check` before pushing", rather than a quality adjective.

- **Pointer**: [Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions).

### C5: Non-obvious Only [WARN]

**What**: Does the file contain content Claude could infer from reading code?

**How to check**:

1. Flag file-by-file codebase descriptions (Claude can `ls` and read files), with a
   **navigation-pointer carve-out**. A curated navigation pointer is KEEP, not a codebase
   description: a short entry routing to a non-obvious doc or surface that work depends on,
   saying where to look and when. The distinction is curation: a pointer to something Claude could not
   cheaply rediscover (a buried runbook, a convention registry, the one doc that owns a
   decision) earns its line; a file-by-file inventory of what Claude can rebuild with
   `ls`/Glob stays FLAG.
2. Flag standard language conventions Claude already knows
3. Flag framework documentation that should be linked, not copied
4. WARN per instance

**Provenance**: the KEEP branch is a **repo extension, not doc-derived**: we found no navigation
posture in the docs' include/exclude table (checked 2026-08-17), so the `update` action must not
overwrite it.

**Why**: Steps 1-3 apply the exclude side of the docs' include/exclude table, in our words.

- **Pointer**: for the include/exclude table, see
  [Write an effective CLAUDE.md](https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md).
- **As of**: 2026-08-17
- **Recheck trigger**: the table gains a navigation-pointer row, or drops an exclude row steps 1-3
  apply.

### C6: Consistency [FAIL]

**What**: Do any instructions contradict each other across CLAUDE.md, a root AGENTS.md read in a
CLAUDE.md's place, CLAUDE.local.md, and rules files, including across **user and project** scope
when both sides are in the `discover-instruction-surfaces` population?

**How to check**:

1. Identify instructions touching the same topic across files discovered by
   `scripts/discover-instruction-surfaces.sh` (project and user scope)
2. Check for contradictions (e.g., "always use X" in one file, "never use X" in another)
3. Check for redundancy (same instruction in multiple files)
4. Compare **user**-scope surfaces against project ones. Both load together, so a
   user↔project contradiction is a live conflict (see Step 3 in `context/audit.md`)
5. FAIL for contradictions (which side Claude follows is undefined)
6. WARN for redundancy (wastes context budget)

**Boundary**: This check owns instruction-content conflicts whose **both** anchors are in the
discover-instruction-surfaces population. Nested `CLAUDE.md` files, auto-memory, settings, hooks,
skills, agents, and output styles are outside that population, so those pairs belong to
`harness-config:audit-instructions` I15 (and its precedence / co-residency adjudication), not here.

**Why**: A contradiction leaves which instruction Claude follows undefined, so we fail it rather
than warn.

- **Pointer**: [Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions).

### C7: Currency [FAIL]

**What**: Do referenced files, versions, and counts match reality?

**How to check**:

1. Extract all file path references (e.g., "`docs/foo.md`", "`.claude/rules/bar.md`")
2. Verify each referenced file exists, **reading each reference in context**: instructional files
   cite non-existent paths on purpose (examples, counter-examples, future-deferred refs, regex
   patterns), so a blind existence check false-flags heavily
3. Check version numbers against the repo's actual pin files (e.g. an SDK pin vs `global.json`, a Node
   pin vs `.nvmrc`)
4. Check counts (e.g., "13 MCP servers" vs actual `.mcp.json`)
5. FAIL for missing files or wrong versions
6. WARN for stale counts

**Navigation-section note**: stale pointers are the standing cost of the curated navigation
sections C5's KEEP branch permits, and a stale one is worse than none: a pointer that outlives its
target misroutes every future session. This check's missing-file FAIL is what keeps
that posture honest, so give C5-kept navigation entries particular attention here.

**Why**: Stale references cause Claude to hallucinate or waste time looking for nonexistent files.

### C8: Enforcement Hierarchy [WARN]

**What**: Could any CLAUDE.md instruction be enforced by a tool higher in the enforcement hierarchy?

**How to check**:

1. For each rule/instruction, check if it could be:
   - A compiler setting (nullable, warnings-as-errors)
   - A static-analyzer or linter rule
   - An architecture test
   - A pre-commit/pre-push git hook
   - A CI gate
   - A Claude Code hook (deterministic)
2. WARN per instruction that could move up the hierarchy
3. Include which enforcement level it could move to

**Why**: Prefer deterministic enforcement over documentation. When a guideline can become a
compile-time or runtime check, that is the stronger default.

### C9: Build and Test Commands Present [FAIL]

**What**: Does a project CLAUDE.md state the repo's exact build and test commands, and are the
commands it states correct?

The only CLAUDE.md check that looks for missing or wrong content rather than surplus. C4 asks
whether an instruction that exists is concrete, C5 whether it should have been cut. Applies to
project CLAUDE.md only; skip for CLAUDE.local.md and for personal (`~/.claude/CLAUDE.md`) files,
which are not repo-scoped.

**How to check**:

0. First ask whether the commands are stated on another loaded surface: a nested CLAUDE.md, a
   path-scoped rule, or auto memory. If they are, this is a C3 placement question, not a C9
   finding for ABSENCE: do not WARN that CLAUDE.md omits them. The carve-out suppresses only the
   absence branch. Any command CLAUDE.md itself still states goes through steps 2-3 regardless,
   because a stale stated command misleads whether or not a correct one exists elsewhere
1. Look for the repo's build and test invocations stated as runnable commands
2. Verify each stated command against the repo's own manifest or task runner (`package.json`
   scripts, `Makefile`, `*.csproj`, `pyproject.toml`, or ecosystem equivalent)
3. FAIL for a stated command that does not exist there, which is worse than an absent one: Claude runs it
   and the check fails for the wrong reason
4. WARN if either command is absent, or if present only as prose naming the tool without the
   invocation ("we use pytest" is not a command)
5. Do not flag a repo that has no build or test step; flag only a missing statement of one that exists

**Boundary with C7.** C7 owns *references*: file paths, version pins, counts. C9 owns *commands*.
A wrong build command is not a C7 finding today, because a command is none of the three things C7
checks. Report a wrong command under C9 only, and do not double-report it.

**Why**: We treat the repo's build and test commands as core project-instruction content: without
a statement of them, every session infers them rather than reads them. This check fires on a
CLAUDE.md that exists but omits them. Absent commands make every verification loop start by
guessing how to run the check.

- **Pointer**: [Set up a project CLAUDE.md](https://code.claude.com/docs/en/memory#set-up-a-project-claude-md).

**Counter-evidence, and why step 0 exists**: the same page's CLAUDE.md-vs-auto-memory comparison
also bears on where build commands belong (pointer:
[CLAUDE.md vs auto memory](https://code.claude.com/docs/en/memory#claude-md-vs-auto-memory)). We
therefore require the commands to be *reachable* on some loaded surface, not to sit in CLAUDE.md
specifically. Step 0 is what keeps this check from flagging a repo that put them on another loaded
surface.

---

## Checks for .claude/rules/ files

### R1: Duplication with CLAUDE.md [WARN]

**What**: Does this rule duplicate content already in CLAUDE.md?

**How to check**: Compare rule content against CLAUDE.md sections. Flag significant overlap.

**Which CLAUDE.md**: two can be in scope, so name the pairing rather than leaving it to be
guessed. Compare against the one at the rule's **own scope**: a project rule against the project
`CLAUDE.md`, a user rule against the user `CLAUDE.md`. R1 is a redundancy the owner of that layer fixes
by deleting one of the two, and only a same-scope pair is theirs to fix. Overlap **across** scopes is
real and is not R1. The audit workflow's cross-scope consistency step owns it, reports it against the
pair, and names which side each came from. Routing it here as well would report one overlap twice and
address it to the wrong person.

**A `both`-scoped rule has no same-scope partner, so it pairs with each.** `both` means one physical
rule file that each layer loads, which arises in a `~`-rooted repo, and there the two `CLAUDE.md`
files stay distinct, so there is no `both`-scoped `CLAUDE.md` to pair against. Compare such a rule
against **every** `CLAUDE.md` in scope, and attribute each finding to the scope of the `CLAUDE.md` it
overlapped. That is not double-reporting: the rule is genuinely loaded alongside both, and a
duplication against either is a real redundancy for that layer.

### R2: Path Scoping Fit [INFO]

**What**: Should this rule carry `paths:` frontmatter so it loads only when matching files are read?

**How to check**: If the rule applies only to specific file types or directories but has no `paths:`
frontmatter, note it as a path-scoping candidate: an always-loaded rule costs context every session.

### R3: Currency [FAIL]

**What**: Same as C7: verify file references, versions, and facts within rules files.

### R4: Staleness [WARN]

**What**: Does this rule reference features, patterns, or tools that no longer exist in the codebase?

**How to check**: Cross-reference key claims against actual code, configs, and dependencies.

### RD1: Orphan always-loaded rule [WARN], deterministic

**What**: An always-loaded `.claude/rules/*.md` file (no `paths:` frontmatter, so it costs context
EVERY session) that carries no `description:` frontmatter AND that NO tracked file references. A rule
nothing names and nothing describes has no owner anyone can find: per-session token tax until someone
trips over it, or a candidate for a `description:` line, path-scoping (`paths:` frontmatter), or
removal. The doc-derived checks (C7/R3/R4/M2) all run memory/rules → codebase; RD1 runs the reverse
direction, codebase → layer.

An always-loaded rule is in context every session by construction, and the always-loaded rules
index the `instruction-placement` plugin renders deliberately omits unscoped rules (indexing what
already loads would spend budget restating it), so "unreferenced" alone proves nothing. The
`description:` line is the rule naming its own purpose; a rule that has one is never an orphan.

**How to check**: run
`bash "<skill-dir>/scripts/orphan-rule-check.sh"` (deterministic
set-difference: enumerate always-loaded rules without `description:`, `git grep` each basename across
tracked files excluding the rule's own file; zero hits = orphan). Path-scoped rules are exempt: they
load only on matching-file Read, so being unreferenced costs nothing per session. WARN per orphan.
Each finding carries the file's provenance (see "Provenance routing" below): a synced rule is still a
finding, but its fix line names the sync's source rather than a local edit.

**Provenance**: repo-agnostic extension, not doc-derived, so the `update` action must not overwrite it.

---

## Checks for nested instruction files

### N1: Nested AGENTS.md reachability [FAIL], deterministic

**What**: A tracked `AGENTS.md` below the repository root that a `CLAUDE.md`, `.claude/CLAUDE.md` or
`CLAUDE.local.md` on its own path displaces, and that none of them reaches by import or symlink.
Such a file never loads, however well written, and every static gate around it reports green. A
nested `AGENTS.md` with none of those files above it is read directly and is not a finding.

**How to check**: run
`bash "<skill-dir>/scripts/nested-agents-check.sh"` and fold each FAIL line
into the report. The script enumerates tracked `**/AGENTS.md` below the root (skipping `.claude`,
`.codex`, `.cursor`, `.github`, `node_modules`, `vendor`, and `.git` trees, so another tool's own
instruction files are never reported as a missing Claude shim), and for each asks first whether any
`CLAUDE.md` or `CLAUDE.local.md` on its path displaces it, and then whether one of them is the file
(symlink) or imports it within four hops, using the same import parser C1's expansion uses. The root
`AGENTS.md` is the root `CLAUDE.md`'s business and is not examined here. Discovery for the C-checks
stays depth-1: this check is about the pointer, not the nested file's content. FAIL per displaced,
unimported file; the fix is a one-line `@AGENTS.md` `CLAUDE.md` beside it.

**Why**: The script models a nested `AGENTS.md` as read directly only when no `CLAUDE.md`,
`.claude/CLAUDE.md` or `CLAUDE.local.md` on its path displaces it, and otherwise as reachable only
through an import or symlink from one of those files. An import from a `CLAUDE.md` is also the
fix where direct reading is unavailable, so the fix line names it in every case.

- **Pointer**: for when an `AGENTS.md` is read and the fallback where support is unavailable, see
  [When Claude Code reads AGENTS.md](https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md)
  and [When AGENTS.md support is unavailable](https://code.claude.com/docs/en/memory#when-agents-md-support-is-unavailable).
- **As of**: 2026-09-19
- **Recheck trigger**: a fetch of those sections changes which file names displace an `AGENTS.md`.

The earlier basis for this check (verified 2026-09-08) was the page's former CLAUDE.md-only
reading model. Its trigger fired: the page had changed when fetched 2026-09-19, and direct
`AGENTS.md` reading shipped in v2.1.277. That basis is superseded and is no current claim.

---

## Provenance routing

Every finding proposes a change to a file. When that file is a synced copy of a source elsewhere,
the change is overwritten by the next sync, so the finding stands but its fix belongs upstream. Run
`bash "<skill-dir>/scripts/file-provenance.sh" <path>` for each flagged
repository file: `synced` (a `SYNC-MANAGED` marker in the file, or a last commit by the standards
sync) makes the report's fix line name the upstream (`owner/repo` when the marker names one) instead
of a local edit; `local` keeps the ordinary fix line. RD1 does this itself; the judgment-tier checks
(C7, R3, R4, and the C-checks on an imported file) do it in the report. The `fix` action never edits a
`synced` file.

**Provenance**: repo-agnostic extension, not doc-derived, so the `update` action must not overwrite it.

---

## Checks for auto-memory (MEMORY.md + topic files)

### M1: Index Size [FAIL]

**What**: Is MEMORY.md under 200 lines / 25KB?

**How to check**: Count lines and file size on the content that loads. Strip YAML frontmatter and
block-level HTML comments first: we count only loaded content toward the limits. The SKILL.md
pre-computed context already reports both post-strip figures
(`memory-dir-stats.sh --memory-lines` / `--memory-bytes`); use them rather than re-measuring the raw
file. This check sets the limit at the first 200 loaded lines or 25KB and treats anything beyond
as not loaded at session start.

- **Pointer**: for the auto-memory load limits, see
  [How it works](https://code.claude.com/docs/en/memory#how-it-works).

Four readings the strip applies, so a hand count matches the reported figures:

1. A block counts only once it closes, and a leading `---` opens frontmatter only for as long as
   what follows is shaped like frontmatter. An opening `---` or `<!--` with no closing delimiter is
   ordinary content and is counted. So is a leading `---` whose block reaches a line that is
   neither blank nor a `key:` mapping entry, or that runs past 20 lines, or past 1KB. Markdown
   prose opening `Note:` parses as a mapping entry, so without the weight bound one long
   paragraph would be stripped however much it weighed. Markdown carries thematic breaks freely,
   so the next `---` in a file is usually another break rather than a frontmatter close, and
   without all three bounds the entire span between the two would be stripped.
   A leading thematic break, or frontmatter clipped mid-file, must not blank the count. A `#`
   line ends the block: it is a comment to YAML but a heading to markdown, and headings are
   loaded content. When the block ends this way nothing in it is stripped: the opening `---`,
   every entry held so far, and the rest of the block through its closing `---` all count.
2. A block-level comment occupies whole lines. Text sharing a line with the comment's open or
   close loads, and is counted, including text between two comments on one line, since each
   comment ends at the first `-->` after its own opener.
3. Comments inside fenced code blocks are preserved: a comment inside a fence is code, not
   block-level markdown.
4. Byte counts measure LF-normalized content, so a CRLF index reports about one byte per line
   under its on-disk size, well under 1% of the 25KB cap.

**Provenance**: the strip rule itself is doc-derived (pointer above). The four readings are not:
they cover cases we did not find the docs to settle for MEMORY.md (fenced code, unterminated or
unbounded blocks, partial lines, line endings). They are this plugin's reading, chosen so that no
input silently under-reports and leaves this `[FAIL]` gate unable to fire. Where a reading has to guess, it guesses
toward counting: an over-count can only make the gate fire early on a file near its limit, while an
under-count stops it firing at all. The `update` action must not overwrite them.

### M2: Stale Entries [WARN]

**What**: Do any memory entries reference files, features, or decisions that no longer exist?

**How to check**:

1. Run `bash "<skill-dir>/scripts/memory-index-refs-check.sh"` for the
   deterministic index↔topic-file integrity half (missing targets + orphan topic files)
2. For entries referencing specific files/features, verify they still exist (judgment half: the
   script checks existence, not content)
3. WARN for entries pointing to removed/renamed content

### M3: Duplicate Topics [WARN]

**What**: Are there multiple memory entries covering the same topic?

**How to check**: Compare entry titles and descriptions. Flag entries with >80% semantic overlap.

### M4: Type Correctness [INFO]

**What**: Are memory entries categorized correctly (user/feedback/project/reference)?

**How to check**: Read topic files, check `type:` frontmatter against content. INFO severity, since
miscategorization is cosmetic but reduces findability.

---

## Audit output format

Present findings as a deterministic report:

```text
## Memory Health Report, {date}

### Summary
- Files audited: X
- FAIL: X findings
- WARN: X findings
- INFO: X findings
- Estimated context cost: ~X tokens (bytes / 4 over the always-loaded set in both scopes, project and user, `instruction-load-stats.sh --tokens`; an estimate, never a measurement. When the `context-budget` plugin is installed, `/context-budget:audit` measures it)

### FAIL findings (must fix)
| # | Check | File | Finding |
|---|-------|------|---------|
| 1 | C1 | CLAUDE.md | 273 visible lines (200 target, 37% over) |
| 2 | C7 | CLAUDE.md | `docs/missing.md` referenced but doesn't exist |

### WARN findings (should evaluate)
| # | Check | File | Finding |
|---|-------|------|---------|

### INFO findings (informational)
| # | Check | File | Finding |
|---|-------|------|---------|
```

Save the report to the path SKILL.md resolves in "Report location",
`audit/<state-key>/last-audit.md` under the plugin data directory, so the `report` and `fix` actions
retrieve **this project's** report rather than whichever one was written last on this machine. The
key is derived by the resolver SKILL.md names; this file states the format, not the path.
