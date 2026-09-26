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
- args: repo docs
- applies-when: repo has source code
- checked: true
- issue: #4503

#### Override

Stay on the current branch. Do not create a branch or a pull request, and do not commit per
group; leave all changes uncommitted, repo-sweep makes the step commit. Tracking issue:
melodic-software/claude-code-plugins#4503.

### residue-dissolve

- skill: code-tidying:audit-comment-residue, code-tidying:dissolve-comments
- args: .
- applies-when: repo has source code with comments
- checked: true

#### Notes

One step: the residue audit's Tier 1 rows are the dissolve pass's input, so run both in the same
session without `/clear` between them.

### testing-audit

- skill: testing:audit
- args: .
- applies-when: repo has tests in JavaScript, TypeScript, Python, or C#
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
- args: <lane>
- applies-when: repo has source code and the user wants one tidying lane in this sweep
- checked: false
- issue: #4503

#### Override

Stay on the current branch. Do not create a branch or a pull request, and do not commit per
tidying; leave all changes uncommitted, repo-sweep makes the step commit. Tracking issue:
melodic-software/claude-code-plugins#4503.

## Phase 2: existence and copies

### derivability

- skill: docs-hygiene:audit-derivability
- args: sweep .
- applies-when: repo has tracked markdown
- checked: true

### provenance

- skill: provenance:audit
- args: sweep
- applies-when: repo has tracked markdown
- checked: true

#### Notes

Runs before every prose rewriter so fingerprints stay intact.

### codebase-health

- skill: codebase-health:audit
- args: --fix
- applies-when: repo has docs or config that describe its code
- checked: true

### overengineering

- skill: overengineering:audit, overengineering:realign
- args:
- applies-when: repo has hooks, CI workflows, rules, or gate scripts
- checked: false

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
the instruction-placement step. Drop findings on `~/.claude` and auto-memory; the dotfiles sweep
handles them.

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
- issue: #4504

#### Override

Apply with `batch` or `--fix` after `identify`. Do not commit per wave; leave all changes
uncommitted, repo-sweep makes the step commit. Tracking issue:
melodic-software/claude-code-plugins#4504.

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
- args: --fix
- applies-when: always
- checked: true

### skill-quality

- skill: skill-quality:check
- args: check
- applies-when: repo has skills
- checked: true

### evals-validate

- skill: evals:validate
- args: <eval suite paths>
- applies-when: repo has plugin eval suites
- checked: true

### verify

- skill: verification:confirm
- args:
- applies-when: always
- checked: true
