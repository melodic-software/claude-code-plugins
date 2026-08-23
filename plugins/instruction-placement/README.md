# instruction-placement

Routes agent-instruction content to the surface that loads it at the right moment.

A convention that only matters when someone edits a `.cs` file should not be paid for in every
session. Claude Code already provides the machinery to fix that — path-scoped rules, nested
instruction files — but using it correctly is harder than it looks, and every way of getting it
wrong fails silently. This plugin finds the content worth moving, validates the move mechanically
before proposing it, and executes it behind a human gate.

## Skills

| Skill | Verb contract | What it does |
|---|---|---|
| `/instruction-placement:audit` | Read-only findings report | Sweeps the instruction layer and ordinary markdown, classifies candidates, emits a diffable findings artifact |
| `/instruction-placement:realign` | Per-item human-gated apply | Executes accepted findings; the only mutating surface, with no blanket-approve path |
| `/instruction-placement:check` | Deterministic pass/fail gate | Verifies every rule glob resolves and the always-loaded index is current |
| `/instruction-placement:setup` | Verify prerequisites, report config | Confirms the index target is one Claude Code will actually read, and resolves every setting with its source |

Run `setup` first on a new repository — it catches the one failure the other gates cannot see, an
index Claude Code never loads. Then `audit`. Nothing changes until you accept a specific finding in
`realign`. Wire `check`
into CI beside the linters.

## Why this is not just "move things into `.claude/rules/`"

Four facts make the naive version of this migration actively harmful, and each one shapes the design.
The full evidence, including a first-party repro, is in
[`context/verified-mechanics.md`](context/verified-mechanics.md).

**A rule without `paths:` costs exactly what `CLAUDE.md` costs.** Unscoped rules load at launch with
the same priority as `.claude/CLAUDE.md`. Moving a section into `.claude/rules/` without a glob is
bookkeeping, not a saving. The glob is the product.

**Everything that defers is invisible inside subagents.** Measured on Claude Code 2.1.238: a subagent
dispatched *after* its parent had loaded a nested `CLAUDE.md`, a nested `AGENTS.md`, and a
path-scoped rule saw none of them. In a repository where the file editing is delegated, a naive
demotion puts the C# conventions out of reach of the agent editing C#. This is why every accepted
move regenerates an **always-loaded index** of deferred surfaces — the one thing that does reach a
subagent, and that turns an invisible rule into one an ordinary `Read` can fetch.

**Path scoping triggers on read, not write.** Creating a new file is not a read, so a rule governing
how new files are made would not fire in the case it exists for. Creation-governing content is denied
the path-scoped destination structurally, not by judgment.

**A nested `AGENTS.md` with no `CLAUDE.md` shim is never loaded.** Claude Code reads `CLAUDE.md`, not
`AGENTS.md`, at every level of the tree. The shim is a correctness requirement; writing the
`AGENTS.md` alone produces a file that reviews as correct and reaches nothing.

## What this plugin does NOT buy you

An earlier version of this README claimed that path-scoping improves *adherence* — that a convention
arriving when a matching file is read is followed more reliably than the same text buried in a large
always-loaded file. **That claim was measured and not supported**, so it has been removed rather than
softened.

Across 32 trials at two bloat levels — a realistic 251-line always-loaded file and an extreme
1,927-line one, nearly ten times the official 200-line guidance — a clear convention was followed
**100% of the time in both arms**. Full method, caveats, and the ceiling effect the run hit:
[`evals/adherence-results.md`](evals/adherence-results.md).

Weigh a migration on context cost and on the promote lane. Do not expect your instructions to be
obeyed better afterwards.

## The hard-deny classes

Some content is never proposed for demotion, however path-local it looks: irreversible actions,
secret handling, data integrity, external publication, legal and compliance obligations, and bounds
on the agent's own authority.

The reasoning is asymmetric consequence. Demotion trades guaranteed presence for conditional
presence. When a style convention goes missing the cost is a nit in review; when a safety rail goes
missing the cost is unbounded. The index mitigates absence but cannot guarantee attention —
injection is automatic, a pointer is discretionary — so safety rails stay where injection reaches
them.

`audit` reports what it held back and why, so the exclusion is visible. `realign` has no code path
that can apply one. This is the single place where an operator instruction does not carry.

## Portability

`.claude/rules/` is Claude-only. `AGENTS.md` is read by other coding agents. The plugin's default
posture keeps shared content portable: subtree conventions go in a nested `AGENTS.md` with a
`CLAUDE.md` shim beside it, and the generated index lives in the root `AGENTS.md` when one exists.

One semantic difference is deliberately not papered over: other agents resolve `AGENTS.md`
nearest-wins, while Claude concatenates the whole ancestor chain. Subtree content is therefore
written as additive and self-contained, and a candidate that only makes sense as an override is
reported rather than moved.

## Scope boundary — what this plugin does not own

Placement is one question about an instruction, and it is not the only one. Where a sibling plugin
owns a neighbouring question, route to it rather than bending this rubric. Each is optional: when it
is not installed, keep the observation in the report rather than judging it here.

| Question | Owner |
|---|---|
| Is this instruction still needed by the current model? | `claude-config`'s instruction audit |
| Is the memory layer healthy — size, index integrity, conflicts? | `claude-memory`'s audit |
| Does this whole document earn its existence? | `docs-hygiene`'s derivability audit |
| Is this file structured well for progressive disclosure generally? | `docs-hygiene`'s progressive-disclosure audit |
| Is the same content repeated across several files? | `docs-hygiene`'s single-source-of-truth extraction |
| Is the prose too long or too noisy? | `docs-hygiene`'s compression and noise audits |

The dividing line: those audits ask whether a piece of content is *good*, *needed*, or *duplicated*.
This plugin asks only where it should **live**, and owns the one capability none of them has — the
validated move, including glob derivation and the index that keeps the result reachable.

These routes are **operative, not decorative**. When a candidate raises one of these questions, the
audit invokes the named skill via the Skill tool if its plugin is installed, and otherwise keeps the
observation in the report as an unjudged note. A routed candidate is reported as routed — never
silently dropped, and never re-classified as a placement finding just because the sibling was
missing. A section can be both misplaced and duplicated; routing one question does not cancel the
other finding.

Two rungs of this plugin's own ladder are deliberately report-only. Content that a linter should
enforce, and content that should become a skill, are routed rather than executed: authoring the
replacement mechanism is separate work, and deleting an instruction before its replacement exists
removes the only thing enforcing it.

## Revisit triggers

Conditions that should change this plugin, recorded so they are acted on rather than forgotten.

| Trigger | Action |
|---|---|
| Claude Code makes deferred surfaces visible to subagents | Re-run the measurements; the index's justification weakens and the hard-deny classes may narrow |
| Path scoping gains a write trigger | Drop the structural deny on creation-governing content |
| Rules gain an official `description:` frontmatter field | Make the index's description source explicit rather than a preferred-if-present convention |
| A second consumer needs the findings artifact | Promote its contract to a documented cross-plugin seam before the second consumer ships |
| The glob engine needs semantics bash cannot express cleanly | Reconsider the hand-rolled expander; it exists to avoid `eval` on repository content |
