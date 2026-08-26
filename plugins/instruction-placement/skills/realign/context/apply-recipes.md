# Apply recipes — the exact edit sequence per destination

One recipe per destination the rubric can name. Each states the files touched, the order, and the
verification the move owes before its finding may be marked `applied`.

Two invariants hold across every recipe:

- **Create before excise.** An interruption must leave content duplicated, never deleted.
  Duplication is visible and repairable; deletion of the only copy is not.
- **Relocate, never rewrite.** Content moves byte-for-byte apart from the mechanical adjustments each
  recipe names (heading level, frontmatter). Improving prose during a move makes the diff
  unreviewable and slips an unapproved edit past the gate.

## Contents

- [Recipe A — path-scoped rule](#recipe-a--path-scoped-rule)
- [Recipe B — nested AGENTS.md plus shim](#recipe-b--nested-agentsmd-plus-shim)
- [Recipe C — promote from ordinary documentation](#recipe-c--promote-from-ordinary-documentation)
- [Recipe D — re-scope an existing rule](#recipe-d--re-scope-an-existing-rule)
- [Recipe E — delete](#recipe-e--delete)
- [Report-only outcomes](#report-only-outcomes)
- [Rollback](#rollback)

## Recipe A — path-scoped rule

The common case: content keyed to a file kind moves to `.claude/rules/<topic>.md`.

1. **Re-validate the glob.** The repository may have moved since the audit.

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh" validate --glob '<glob>'
   ```

   Anything other than `ok` or `over-broad` stops the move.

2. **Create the rule file.** Filename is topic-based and hyphenated — `csharp-naming.md`, not
   `rule1.md` or `claude-md-section-4.md`. The index shows this name to a reader deciding whether to
   open it.

   ```markdown
   ---
   description: "<one line: what this rule covers>"
   paths:
     - "<validated glob>"
   ---

   # <Topic>

   <the relocated content, verbatim>
   ```

   `description:` is optional and Claude Code ignores it, but the index generator prefers it over the
   H1 — worth writing when the H1 alone would not tell a reader when to open the file.

3. **Adjust heading levels only.** If the content was `## X` inside a larger file it becomes `# X`
   here. Relative links must be rewritten to resolve from `.claude/rules/`. Nothing else changes.

4. **Excise the source**, leaving no stub. A "moved to `.claude/rules/…`" breadcrumb in an
   always-loaded file spends the budget the move just freed; the index already carries that pointer.

5. **Regenerate the index.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh" write --file <index-file>
   ```

6. **Verify.** The glob still resolves, the index reports `IN-SYNC`, and the source no longer
   contains the moved text.

**Cite** the shared file from a path-scoped rule by path, never with an `@import`: the import
inlines at session start and defeats the scoping, so the move would read as a saving and not be one.

## Recipe B — nested AGENTS.md plus shim

Content keyed to a place rather than a file kind.

1. **Create `<dir>/AGENTS.md`** with the relocated content under a `#` heading naming the subtree.

2. **Create `<dir>/CLAUDE.md` — mandatory, exactly:**

   ```markdown
   @AGENTS.md
   ```

   A nested `AGENTS.md` with no shim beside it is never loaded by Claude Code. This is measured, not
   inferred. Skipping the shim produces a file that looks correct in review and reaches nothing.

3. **Merge, do not clobber.** If either file already exists, append under a new heading and preserve
   what is there. Claude-specific additions go in the `CLAUDE.md` *below* the import line, never
   inside the `AGENTS.md`, which other agents also read.

4. **Excise the source, regenerate the index, verify** as in Recipe A. Verification here also checks
   that the shim exists and that its import resolves.

The content must read as **additive and self-contained**. Other agents resolve `AGENTS.md`
nearest-wins while Claude concatenates the whole ancestor chain, so a subtree file written as an
override behaves differently under the two tools. A candidate that only makes sense as an override
does not belong in this destination — mark the finding `blocked` and say why.

## Recipe C — promote from ordinary documentation

Content Claude never loads today. No presence to lose, so the only real question is duplication.

**Move variant** — the content is agent-facing and the human document would not miss it. Run Recipe
A or B, then leave a pointer *in the source document* back to the new location. A human doc may
carry a breadcrumb; it costs no always-loaded budget.

**Pointer variant** — the section exists to be read by humans and a copy would drift. The rule body
is a short scoped pointer rather than a copy:

```markdown
---
description: "Where the API conventions live"
paths:
  - "src/api/**/*.ts"
---

# API conventions

The conventions for this area are maintained in [`docs/api-guidelines.md`](../../docs/api-guidelines.md).
Read it before changing an endpoint, a response shape, or an error contract.
```

A pointer earns its place only if it says **when** to read the target, not merely that it exists. A
bare "see the docs" is a blind pointer and buys nothing.

Content already duplicated across several documents is **not** resolved here. Mark the finding
`blocked`, name the copies, and route it out — picking a winner among existing duplicates is a
deduplication decision, not a placement one.

## Recipe D — re-scope an existing rule

The rule is in the right place with the wrong glob: unscoped when it should be scoped, or scoped too
broadly.

Edit `paths:` in place. No file is created, no content moves, nothing is excised. Re-validate, then
regenerate the index — adding `paths:` to a previously unscoped rule *adds* it to the index, since
the rule now defers and needs to be reachable.

State the direction of the trade out loud: adding `paths:` to an unscoped rule removes it from every
session it used to be present in. That is the point, and it is also the risk.

## Recipe E — delete

Content that fails the deletion test. Only reachable through a finding the audit classified at ladder
rung 1 and the operator explicitly accepted.

Excise it. Do not relocate it, do not archive it into a spoke file, and do not leave a commented-out
copy. If the operator is unsure, the honest answer is `declined`, not a hedge that keeps the content
in a quieter place.

## Report-only outcomes

Two ladder rungs produce findings this skill deliberately cannot execute, because the destination is
not this plugin's to build:

- **Rung 2, mechanical enforcement.** The remedy is a linter, formatter, analyzer, or hook. Report
  the routing and leave the prose in place — deleting an instruction before its replacement mechanism
  exists removes the only thing enforcing it.
- **Rung 3, a skill.** Authoring a skill is separate work with its own quality bar. Report the
  routing; do not scaffold one mid-migration.

Mark both `blocked` with the reason. `blocked` here means "correctly classified, executed elsewhere",
not "failed".

## Rollback

Every move is an ordinary file change on a branch, so `git` is the rollback mechanism and the recipes
assume nothing else. Two consequences worth stating:

- **Do not apply findings on a dirty tree without saying so.** A mixed working tree makes it hard to
  tell a migration edit from an unrelated one. Report the uncommitted count and let the operator
  decide before starting.
- **A finding marked `applied` is reversible by reverting its change.** Reverting does not rewrite
  the artifact — re-run the audit if the operator wants the finding re-proposed, and note that a
  `declined` decision survives a re-audit by design.
