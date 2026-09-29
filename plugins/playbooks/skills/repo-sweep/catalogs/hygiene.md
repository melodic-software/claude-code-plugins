# Playbook: hygiene

File order is run order. Phase headings group entries for display only. Arguments in angle
brackets are resolved per repo by `plan` before the step runs.

## Phase 1: code

### dead-code

- skill: code-tidying:audit-dead-code
- args: .
- applies-when: repo has source code
- checked: true

#### Notes

Authorize the candidate-count consent gate for the whole repo. Tag any `alive` notes it adds with
`dissolve-comments-ignore` so the residue-dissolve step keeps them.

### batch-simplify

- skill: code-tidying:batch-simplify
- args: repo docs in-place
- applies-when: repo has source code
- checked: true

### residue-dissolve

- skill: code-tidying:audit-comment-residue, code-tidying:dissolve-comments
- args: .
- applies-when: repo has non-config source code with comments outside CI workflows and synced files
- checked: true

#### Notes

One step: the residue audit's Tier 1 rows are the dissolve pass's input, so run both in the same
session without `/clear` between them. CI workflows stay excluded unless the operator lifts them
by hand, for example `dissolve-comments override .github/workflows/ci.yml`; the skill's Hard rules
section owns the exclusion and its lift channels. Findings on files synced from another repository
are fixed upstream, never in this sweep; filter them out before fixing.

### testing-audit

- skill: testing:audit
- args: .
- applies-when: repo has tests in JavaScript, TypeScript, Python, or C#
- prime: false
- checked: true

### scan-todos

- skill: work-items:scan-todos
- args: .
- applies-when: repo has TODO, FIXME, HACK, or XXX markers in source
- checked: true

#### Notes

Resolve or delete each marker in place. Do not file work items to a tracker; list any marker that
needs tracked work in the step's `Scope decisions:` instead.

### tidy

- skill: code-tidying:tidy
- args: <lane> | <lane1>,<lane2>,... | all
- applies-when: repo has source code or prose that at least one tidy lane covers
- checked: false

#### Notes

`code-tidying:tidy` runs one lane per invocation. When the sweep should tidy more than one lane,
resolve `args` to a comma-separated lane list or `all` (every lane in the union of bundled and
`.claude/tidy-lanes/*.md` names that applies to this repo, excluding the maintainer-only
`self-update` lane). `next` invokes tidy once per lane in that list inside this single step.
Present findings from every lane together for review; one step commit covers all lanes. Pass
`in-place` on every tidy invocation: it stays on the current branch, opens no branch or PR, and
leaves the changes staged for the step commit. Glob scope runs through tidy's `<glob>...` row.

Claim: tidy takes one lane per call, its catalog is the union of `.claude/tidy-lanes/*.md` and its
bundled lanes, `self-update` is maintainer-only, and `in-place` is a flag on every invocation.
Basis: `code-tidying` 0.23.20 `skills/tidy/SKILL.md` (argument-hint, Action Router `<glob>...`,
`in-place`, and `self-update` rows). As of: 2026-09-29. Recheck: tidy accepts several lanes in one
call, changes where it reads lanes from, or renames `in-place`; prefer the lane list tidy's own
`help` prints over this note when they differ.

## Phase 2: existence and copies

### derivability

- skill: docs-hygiene:audit-derivability
- args: sweep .
- applies-when: repo has tracked markdown
- checked: true

### provenance

- skill: attribution:audit
- args: audit
- applies-when: repo has tracked markdown
- checked: true

#### Notes

Runs before every prose rewriter so fingerprints stay intact. `audit` is the read-only action;
`sweep` is the fix pipeline and would apply fixes before the user reviews the findings. Apply the
approved findings with `attribution:audit fix <file>`, one file at a time when the per-file
closure record is wanted.

### codebase-health

- skill: codebase-health:audit
- args:
- applies-when: repo has docs or config that describe its code
- checked: true

#### Notes

The audit's `--fix` applies nothing: it suggests `/implementation:implement` and then
`/verification:confirm`, and tells the model not to invoke either. The bare audit stops at the
report, and the step applies the agreed fixes itself.

### overengineering

- skill: overengineering:audit, overengineering:realign
- args: agent-instructions repo-hooks vcs-hooks ci-lanes gate-scripts satellite-workflows
- applies-when: repo has hooks, CI workflows, rules, or gate scripts
- checked: false

#### Notes

The args are the layers the repository owns. `agent-hooks` also walks user- and machine-scope
settings and every enabled plugin's hook manifest, and `branch-protection`, `forge-apps`, and
`external-integrations` live on the forge or an outside service, so this sweep could only record
them as delegated. Audit those four in a separate org- or machine-level pass.

### native-overlap

- skill: claude-ops:audit-native-overlap
- args:
- applies-when: repo ships Claude Code skills or agents
- checked: false

### claude-config

- skill: claude-config:audit
- args: --fix
- applies-when: repo has .claude/settings.json or .mcp.json
- checked: false

#### Notes

Project scope only. Drop findings on user-scope or managed settings.

## Phase 3: instruction content

### prompt-audit

- skill: claude-api
- args: prompt-audit
- applies-when: repo has agent-instruction files or prompt strings in code
- checked: true

#### Notes

Audit agent-instruction files only (CLAUDE.md, AGENTS.md, rules, skill and agent bodies, prompt
strings in code), never human-facing docs. Ask it to apply the accepted edits. Apply deletes and
rewrites only; moves belong to the instruction-placement step.

### audit-instructions

- skill: claude-config:audit-instructions
- args: all
- applies-when: repo has Claude Code instruction surfaces
- checked: true

#### Notes

Apply repo-scope delete and rewrite findings only; moves belong to the instruction-placement step.
Drop findings on `~/.claude`; the dotfiles sweep handles them.

### claude-memory

- skill: claude-memory:audit
- args:
- applies-when: repo has CLAUDE.md, AGENTS.md, or .claude/rules
- checked: true

#### Notes

Run the audit, then `fix`. Apply deletes and rewrites only; skip C1 and C3 moves, which belong to
the instruction-placement step. C9 additions are in scope too: one line per missing build or test
command, verified against the repo's manifest or task runner. Drop findings on `~/.claude` and
auto-memory; the dotfiles sweep handles them.

### prompting-postures

- skill: claude-config:audit-prompting-postures
- args:
- applies-when: repo has Claude Code instruction components
- checked: false

#### Notes

Project scope only.

### mcp-tools

- skill: mcp-tools:audit
- args:
- applies-when: repo defines MCP servers
- checked: false

## Phase 4: structure

### audit-noise

- skill: docs-hygiene:audit-noise
- args:
- applies-when: repo has tracked markdown
- checked: true

#### Notes

Accept its offered repo-wide tracked run rather than passing `.`.

### extract-ssot

- skill: docs-hygiene:extract-ssot
- args: identify
- applies-when: repo has tracked markdown
- checked: true

#### Notes

Apply the identified clusters with `batch --commit-mode=none`, which makes no commits and leaves the
migrations in the working tree for the step commit.

### instruction-placement

- skill: instruction-placement:audit, instruction-placement:realign, instruction-placement:check
- args:
- applies-when: repo has CLAUDE.md, AGENTS.md, or .claude/rules
- checked: true

#### Notes

One step: audit, then realign the accepted findings, then check.

### progressive-disclosure

- skill: docs-hygiene:audit-progressive-disclosure
- args: <instruction roots>
- applies-when: repo has agent-instruction markdown
- checked: true

#### Notes

Pass the instruction roots (CLAUDE.md, AGENTS.md, .claude/, skill directories), not `.`.

### encapsulation

- skill: docs-hygiene:audit-encapsulation
- args: sweep
- applies-when: repo ships skills
- checked: true

### file-names

- skill: docs-hygiene:audit-file-names, docs-hygiene:realign-file-names
- args:
- applies-when: repo has a docs tree and a file-name casing rule
- checked: false

### coupling

- skill: coupling:reduce
- args:
- applies-when: repo has several modules or cross-linked docs
- checked: false

#### Override

Stay on the current branch. Do not create a branch or a pull request, and do not commit per reduction; leave all changes uncommitted, repo-sweep makes the step commit. Record route-lane findings in the ledger; file tracker items only when the user approves.

## Phase 5: prose

### be-concise

- skill: writing:be-concise
- args: <human-facing markdown files> edit in place
- applies-when: repo has human-facing markdown such as READMEs or docs
- checked: true

#### Notes

Name each human-facing file explicitly. Never pass agent-instruction files.

### compress

- skill: docs-hygiene:compress
- args: <markdown files>
- applies-when: repo has prose markdown the be-concise step did not cover
- checked: false

#### Notes

Run only on files the be-concise step did not edit.

### ai-slop

- skill: ai-slop:audit
- args: audit fix .
- applies-when: repo has tracked markdown
- checked: true

## Phase 6: checks

### lint

- skill: toolchain:lint
- args: all --fix
- applies-when: always
- prime: false
- checked: true

#### Notes

`--fix` runs only each ecosystem's format-only `fix-cmd`. After it, run `/toolchain:lint all` in
check mode so every ecosystem's `check-cmd` also covers the whole repository, and report its
failures.

Claim: `toolchain:lint` with `--fix` runs only each ecosystem's format-only `fix-cmd`, check mode
runs `check-cmd`, and the `all` filter widens the file list to the whole repository. Basis:
`toolchain` 0.13.18 `skills/lint/SKILL.md` (Mode flags table, command-selection table, and the
`all` filter rule). As of: 2026-09-29. Recheck: `--fix` also runs `check-cmd`, the check-mode
default changes, or `all` stops widening the file list.

### skill-quality

- skill: skill-quality:check
- args: check
- applies-when: repo has skills
- prime: false
- checked: true

### evals-validate

- skill: evals:validate
- args: <eval suite paths>
- applies-when: repo has plugin eval suites
- prime: false
- checked: true

### verify

- skill: verification:confirm
- args:
- applies-when: always
- checked: true
