---
description: "Execute an instruction-placement audit's findings behind an explicit per-item human gate. Consumes the findings artifact the audit skill produced. It never re-judges the surface itself. For each finding the operator accepts, it performs the whole move atomically: create the path-scoped `.claude/rules/` file with its validated `paths:` glob (or the nested AGENTS.md plus its mandatory CLAUDE.md shim), excise the content from its source, regenerate the always-loaded rules index so the demoted surface stays reachable from subagents, and verify the result. Hard-denied safety content has no code path here. Use when: 'apply the placement findings', 'do the migration', 'move those conventions to rules', 'execute finding IP-004', 'realign our instruction layer', 'the audit says move it, do it'. This is the only skill in this plugin that changes anything, and there is no blanket-approve path."
argument-hint: "[finding-id ...]. Default: every finding awaiting a decision, in ranked order"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  [
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/verify-load.sh:*)",
    "Read",
    "Edit",
    "Write",
    "Grep",
    "Glob",
  ]
shell: bash
metadata:
  workflow-stage: implement
  summary: Apply accepted placement findings behind a per-item human gate
---

## Pre-computed context

!`"${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh" realign 2>/dev/null || echo "- Orientation unavailable"`

## Purpose

Execute what the audit found, one finding at a time, with the operator deciding each one. This is
the **only** mutating surface in this plugin, and the per-item gate below is the entire reason it is
safe to point at a repository nobody has reviewed.

What makes these edits unusual is their target: every file this skill touches is a file that steers
the agent's own behavior. A bad code edit fails a test. A bad instruction edit quietly changes what
the agent does in every future session, and nothing goes red.

## Read these before executing anything

Not restated here. A paraphrase inside a proposal is a drift seed.

| Read | For |
|---|---|
| [`../../context/findings-artifact.md`](../../context/findings-artifact.md) | The artifact's location, fields, status vocabulary, merge rules, and the finding-id constituents a suppression entry is keyed by |
| [`../../reference/consumer-config.md`](../../reference/consumer-config.md) | The suppression surface a decline is recorded on: its layers, its per-key merge, and the offered-never-taken rule |
| [`../../context/routing-rubric.md`](../../context/routing-rubric.md) | The hard-deny classes and what each destination means |
| [`../../context/verified-mechanics.md`](../../context/verified-mechanics.md) | Why the shim is mandatory and why the index exists |
| [`context/apply-recipes.md`](context/apply-recipes.md) | The exact edit sequence per destination, and the verification each one owes |

## The per-item gate

**Nothing mutates without an explicit acceptance of that finding, from the operator, at the moment
it is presented.** Say so in the run's opening line, then hold it literally.

- **One finding, one acceptance.** Accepting IP-003 authorizes IP-003 and nothing else, not its
  neighbours, not the rest of its file, not the obvious next one.
- **Blanket approval is not the gate.** "Approve everything", "do whatever the audit says", and a
  standing authorization from earlier in the session are all declined, out loud, with an offer to
  walk the findings one at a time. This is not pedantry: the whole value of the gate is that a human
  looked at each destination, and a blanket yes means nobody did.
- **Present before asking.** The source and its line range, the destination, the exact `paths:` glob
  with its validated match count, what leaves the always-loaded budget, and the cost: subagent
  invisibility, and post-compaction behavior for that destination.
- **A decline is recorded, not argued.** Write `declined` into the artifact and move on. A declined
  finding is not re-proposed by a later audit.

## Recording a decline so it survives the checkout

The artifact is memory tier: branch-keyed, invisible from every other worktree, and gone with the
memory root. A decline written only there is a judgment the next checkout never sees, and the
operator is asked again. So a decline has **two** writes, and the second is what makes it durable.

1. **`declined` into the findings artifact.** Unchanged, and still the record this branch's run
   reads.
2. **An entry on the tracked suppression surface**, `${CLAUDE_PROJECT_DIR}/.claude/instruction-placement.md`.
   Git carries that file to every checkout whose branch holds the commit, which is the only mechanism
   that crosses checkouts at all.

The entry's five required keys, its `finding_id`, and the layer rules are owned by the two documents
in the table above. Do not invent a format here. Four rules bind the write:

- **Offered, never taken.** Show the composed entry in full (`check`, `claim`, `sites`, the `reason`
  in the operator's own words, `date`), and write it only on an explicit yes. Declining a *finding*
  and agreeing to *never be asked again* are two decisions, and the second silences a future report.
- **A reason is required, and it is theirs, not yours.** An entry with no stated reason cannot be
  reviewed or retired later. If the operator gives none, ask once; if they still give none, record
  `declined` in the artifact only and say the decline will not survive this checkout.
- **Team layer only.** Write `${CLAUDE_PROJECT_DIR}/.claude/instruction-placement.md`, never
  `~/.claude/**` and never the `.local.md` overlay: a personal-layer entry the team layer does not
  carry is reported `personal-only, not applied` and suppresses nothing, so writing one would look
  like recording a decision while recording none.
- **Say that it needs committing.** The file is tracked, and an uncommitted entry has reached no
  other worktree yet. Name that rather than implying the decision is already everywhere.

## Prerequisites

Read the artifact from the home the plugin's topic-docs binding resolves
([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).

If it is absent, say no audit has been run for this branch and offer to run one. Do **not** fall
back to another path or another branch's artifact: findings cite line ranges, and a range derived
elsewhere points at different text here. Name such a file as a leftover and run a fresh audit
instead of acting on it.

Three staleness checks before the first edit, because acting on a stale artifact edits the wrong
lines:

1. **Branch match.** The artifact's `branch:` frontmatter against the current branch. On a mismatch,
   stop and re-audit. The directory a file sits in never proves which branch it describes.
2. **Source drift.** For each finding, that the cited content still exists at the cited location.
   Content that moved is re-audited, not guessed at.
3. **Version drift.** The artifact's `claude_code_version` against the running one. On a material
   difference, re-verify the mechanics before trusting destination choices that depend on them.

## Execution

Per accepted finding, in ranked order, following the recipe for its destination:

1. Re-validate the glob immediately before writing it. The repository may have changed since the
   audit, and a glob that now matches nothing must not be committed.
2. Perform the move: create the destination, then excise the source. In that order, so an
   interruption leaves content duplicated rather than deleted.
3. Regenerate the index:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh" write --file <index-file>
   ```

4. Verify statically: the destination file's frontmatter parses, its glob resolves, the index is in
   sync and its target is reachable, and the source no longer carries the moved content.
5. Verify empirically when the operator wants proof, or when the destination is one you are unsure
   of:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/verify-load.sh" \
     --trigger <a file the new surface covers> --expect <the new surface>
   ```

   This drives the real CLI with an `InstructionsLoaded` hook and reports what actually loaded,
   the only check in this plugin that observes Claude Code rather than reasoning about it, and the
   one that catches a surface passing every static gate while never entering context. It costs a
   model call, so it earns its place on the first move of a migration and on anything unusual, not
   on every finding. `VERDICT UNKNOWN` means the probe could not run: that is never a pass, and
   never grounds for marking the finding applied.
6. Record `applied` in the artifact, with the destination path.

**One finding is one reviewable unit of work.** Do not batch several findings into one edit sweep
even when they share a destination file. A reviewer needs to see which change came from which
accepted proposal.

## Hard rules

- **No blanket approval, ever.** Not on request, not for a batch, not for "the trivial ones". That
  covers suppression entries too: a standing "and never ask me about any of these again" is declined
  the same way, with an offer to compose one entry at a time.
- **Hard-denied content is not applicable.** The held-back section carries no destination and there
  is no code path that gives it one. If the operator asks for one, explain the class and offer
  compression in place. This is the one place where the operator's instruction does not carry.
- **Never re-judge the surface.** This skill executes classifications the audit made; it does not
  reclassify, discover new candidates, or improve a destination it thinks the audit got wrong. If a
  finding looks wrong, say so and stop. The fix is a re-audit, not an improvised alternative.
- **Never rewrite content while moving it.** The move is a relocation. Tightening prose during a
  relocation makes the diff unreviewable and smuggles an unapproved edit past the gate.
- **The shim is mandatory.** A nested `AGENTS.md` without a `CLAUDE.md` beside it importing it is
  never loaded by Claude Code. That is measured, not inferred. Writing one without the other
  produces content that silently reaches nothing.
- **Never leave the index stale.** Regenerating it is part of the move, not a follow-up. An
  un-indexed demotion is exactly the subagent gap this plugin exists to close.
- **Stop on a failed verification.** Report what failed and leave the finding `blocked`. Do not
  proceed to the next finding on a broken tree.

## Gotchas

Observed failure modes. Every one leaves a repository that looks migrated and is not.

- **Writing the nested `AGENTS.md` without the `CLAUDE.md` shim.** The most likely mistake in this
  whole plugin, because the result reviews as correct: a well-written conventions file, in the
  right directory, that Claude Code never loads at any level of the tree. Measured, not inferred.
- **Forgetting the index regeneration.** The move succeeds, the rule fires on read, and the content
  is invisible to every subagent, which in a delegation-heavy repo is most of the work. The index
  is part of the move, not a follow-up task.
- **Excising before creating.** An interruption between the two then deletes the only copy. The
  ordering is not stylistic; it is the difference between a recoverable and an unrecoverable
  failure.
- **Tightening prose "while you're in there".** It makes the diff unreviewable and slips an edit
  past the gate the operator thought they were approving. Relocate verbatim.
- **Treating a run-level "yes, all good" as acceptance.** An operator who has skimmed the findings
  has not gated each destination. The gate is per item because the value is per item.
- **Acting on line numbers from an artifact written before the file changed.** Excising a stale
  line range removes the wrong content, and the audit's own record then describes something that
  never happened. The staleness checks run before the first edit for this reason.
- **Re-proposing a declined finding.** A `declined` status is a decision, not a gap to be filled on
  the next run. Resurrecting it trains the operator to stop reading carefully, which is how a
  per-item gate degrades into a rubber stamp.
- **Marking a report-only rung `applied`.** A linter or skill routing has no destination this skill
  builds. `blocked` there means "executed elsewhere", and recording it as applied hides work that
  still needs doing.
