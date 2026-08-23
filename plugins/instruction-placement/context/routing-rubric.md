# Routing rubric — deciding where one piece of instruction content belongs

The adjudication layer. `audit` applies it to classify; `realign` applies it to execute what the
operator accepts. Both read this file; neither restates it.

The unit of adjudication is a **candidate**: one contiguous run of instruction content — normally a
heading and its body — that could move as a whole. A candidate is never a single line pulled out of
a section, and never a whole file when only one section of it is misplaced.

## Contents

- [Gate 0 — the hard-deny classes](#gate-0--the-hard-deny-classes)
- [The decision ladder](#the-decision-ladder)
- [Scope shape: glob or subtree](#scope-shape-glob-or-subtree)
- [Deriving the glob](#deriving-the-glob)
- [The promote lane](#the-promote-lane)
- [Pricing every move](#pricing-every-move)
- [What this rubric does not decide](#what-this-rubric-does-not-decide)

## Gate 0 — the hard-deny classes

**Runs before every other question. A candidate matching any class below is excluded from the
candidate set entirely** — not surfaced as a risky option, not applicable behind a confirmation.
`audit` reports what it held back and why, so the exclusion is visible rather than silent;
`realign` has no path that can apply one.

The justification is asymmetric consequence. Demotion trades guaranteed presence for conditional
presence. When a style convention goes missing the cost is a nit in review. When a safety rail goes
missing the cost is unbounded and often unrecoverable — and per
[`verified-mechanics.md`](verified-mechanics.md), the three gaps guarantee that "missing" is a real
state, not a hypothetical one.

| Class | Signal | Examples |
|---|---|---|
| `irreversible-action` | Prohibits or constrains an action that cannot be undone | force-push, history rewrite, `rm -rf`, `DROP`/`TRUNCATE`, `reset --hard`, branch deletion |
| `secret-handling` | Governs credentials, tokens, keys, PII | "never commit `.env`", secret-scanning obligations, redaction rules |
| `data-integrity` | Governs migrations, backfills, or destructive data operations | migration ordering, backup-before-migrate, production data access |
| `external-publication` | Governs anything that leaves the machine | opening PRs, deploying, posting, sending mail, publishing packages |
| `legal-compliance` | License, attribution, regulatory, or contractual obligation | license headers, export restrictions, audit-trail requirements |
| `agent-authority` | Bounds what the agent itself may decide or do unattended | approval gates, "ask before", autonomy limits, spend caps |

**Recognition is by consequence, not by phrasing.** "Prefer `git switch` over `git checkout`" is a
style convention that happens to name a git command; "never force-push a shared branch" is an
`irreversible-action` rail that happens to be one sentence. Ask what breaks when the instruction is
absent at the moment it was needed, not how the sentence is worded.

**Two structural denies, from the mechanics rather than from consequence:**

- **Creation-governing content is denied the `paths:` destination.** Path scoping triggers on read,
  and creating a new file is not a read, so a rule governing how new files are made would not fire
  in the case it exists for. It may still route to a subtree destination, or stay. This is a deny of
  one *destination*, not of the candidate.
- **A candidate whose body is only an `@import` is never routed to a path-scoped rule.** The import
  inlines at session start and defeats the scoping, producing a move that reads as a saving and is
  not one.

When a hard-deny candidate is genuinely bloating an always-loaded file, the honest remedy is
compression in place — tighten the wording, cut what is derivable — not relocation. Say that rather
than proposing nothing.

## The decision ladder

First match wins. Stop at the first rung that fits; do not shop for a better-sounding destination
further down.

**0. Hard-deny gate.** Any class above → **stays put**, excluded from the candidate set.

**1. Does removing it cause a mistake?** No → **delete**. The official deletion test: content Claude
can derive from the code (directory layouts, dependency lists, restatements of well-named APIs) is
cut, not relocated. Relocating derivable content just moves the waste.

**2. Is it mechanically checkable?** A compiler, linter, formatter, analyzer, or hook could enforce
it deterministically → **route to that mechanism**. Formatting rules, import ordering, naming
patterns a regex can express. Never send an agent to do a linter's job. This plugin *reports* the
routing; it does not author linters, and it does not delete the prose until the mechanism exists.

**3. Is it a multi-step procedure?** Content that reads as *how to do a task* rather than *a fact to
hold* → **skill**. Trigger words: numbered steps, "first… then…", a workflow with branches. Note the
listing cost: a **new** skill adds an always-loaded listing entry (`name` plus `description`,
truncated at 1,536 chars), so the saving is the body minus that entry; folding into an **existing**
skill adds nothing.

**4. Is its scope narrower than the repo?** Yes → **demote**, destination by scope shape below.

**5. Otherwise** → **stays** in the always-loaded surface. A repo-wide fact that applies in every
session is already where it belongs, and "it is long" is not by itself a reason to move it —
compress it in place instead.

## Scope shape: glob or subtree

Rung 4 splits on what the content is keyed to. Get this wrong and the rule either never fires or
fires constantly.

**Keyed to a file kind → path-scoped rule** (`.claude/rules/<topic>.md` with `paths:`). The content
governs files identified by extension or filename pattern, wherever they sit: C# conventions, test
file conventions, migration file conventions. Cross-cutting by nature.

**Keyed to a place → nested `AGENTS.md` + `CLAUDE.md` shim** in that directory. The content governs
a module, package, or subtree regardless of file type: "the billing service owns its own retry
policy", "everything under `infra/` is applied by CI, never locally". The shim is mandatory —
`verified-mechanics.md` finding 3 — and is exactly two lines:

```markdown
@AGENTS.md
```

**Keyed to both** — a file kind *within* a subtree — takes the path-scoped rule with a glob rooted
at the subtree (`src/billing/**/*.ts`). One surface, one trigger, no duplication.

**Ambiguous** → prefer the subtree destination. It is the more conservative of the two: it carries
no glob to get wrong, it survives the write-trigger gap, and it stays portable to other agents.

### Why the portable pair is the subtree default

A nested `AGENTS.md` is read by other coding agents natively — the `AGENTS.md` convention is
nearest-file-wins across the directory tree — while `.claude/rules/` is Claude-only. Putting shared
content in the `AGENTS.md` and keeping the `CLAUDE.md` beside it as a shim (plus any genuinely
Claude-specific additions below the import) means one copy serves every agent.

Note the semantic difference and do not paper over it: `AGENTS.md` resolution is **nearest-wins**,
while Claude concatenates every `CLAUDE.md` from the root down. So content that *overrides* an
ancestor instruction behaves differently under the two tools — under Claude both statements are in
context and the contradiction is live. Write subtree content as additive and self-contained rather
than as an override, and a candidate that only makes sense as an override does not belong in this
destination.

## Deriving the glob

A path-scoped rule is only as good as its `paths:` list. Derivation is a proposal by the model,
**validated mechanically** before it is ever applied — see the plugin's `glob-tools.sh`.

Derive from what the content actually names, in this order:

1. **An explicit path or extension in the text** — "files under `src/api/`", "`*.tsx` components".
   Use it directly; it is the author's own statement of scope.
2. **A language or framework named in the text** — map to that ecosystem's source extensions, and
   only those. "C# conventions" → `**/*.cs`, not `**/*.{cs,csproj,sln}` unless the content actually
   discusses project files.
3. **A directory the content is about** — `src/billing/**`.
4. **Nothing derivable** → do not invent one. The candidate drops to the subtree destination, or
   stays. A guessed glob is worse than no move.

Validation gates every derived glob:

- **Matches at least one tracked file.** A zero-match glob is a rule that never fires, and Claude
  Code reports nothing when that happens.
- **Is not over-broad.** A glob matching effectively the whole repo (`**/*`, or a match set within a
  small margin of the tracked-file count) is a demotion that saves nothing while adding a surface.
- **Stays inside the brace budget** — 1,000 expanded patterns and 4 MiB across the rule's whole
  `paths:` list. Over budget, the pattern is used unexpanded and matches nothing.
- **Has valid bracket expressions.** An unbalanced `[` silently matches nothing.

Prefer the narrowest glob that covers the content's real scope. Breadth is not safety here: an
over-broad glob loads the content constantly, which is the cost the move exists to avoid.

## The promote lane

The mirror direction, and the one with no downside to weigh. Convention content living in ordinary
documentation — `docs/`, `CONTRIBUTING.md`, a module README — is loaded by Claude **never**. There
is no presence to lose, so the compaction and subagent gaps do not apply: any working destination is
a strict improvement over the status quo.

A promote candidate must be genuinely **normative** — it tells someone what to do or not do — rather
than explanatory, historical, or a tutorial. A design rationale document is not a convention just
because a convention is mentioned inside it.

**Single-source-of-truth is the live risk here, not context cost.** Copying a section out of a
contributor guide into a rule creates two statements that drift. Resolve it per candidate:

| Situation | Action |
|---|---|
| The doc section exists to be *read by humans* and the rule would duplicate it | Rule body is a short **pointer** to the doc, scoped by `paths:` — the agent reads the source on trigger |
| The doc section is agent-facing and the human doc would not miss it | **Move** it, leaving a pointer in the doc back to the rule |
| The content is already duplicated across several docs | Out of scope here — that is a deduplication concern; report and route it rather than picking a winner |

## Pricing every move

Every recommendation states its cost alongside its benefit. A proposal that names only the saving is
incomplete, and the operator cannot gate what they cannot see.

State, for each candidate: the destination and its trigger; roughly what leaves the always-loaded
budget; that the content is absent from subagents unless reached through the index; and, for
path-scoped destinations, that it returns after compaction only when a matching file is read again.

## What this rubric does not decide

Named so a reader chasing one of these lands somewhere real rather than bending this rubric.

- **Whether an instruction is still needed by the current model** — prior-model workarounds,
  over-prescriptive scaffolding. A model-era-fit question, not a placement question.
- **Whether a whole document earns its existence** — derivability of an entire file, as opposed to a
  section within one.
- **General markdown noise, prose flavor, or brevity** — compression is a separate craft and this
  rubric never rewrites content for style while moving it.
- **Whether two instructions contradict each other** — consistency across the instruction layer is
  its own audit. This rubric moves content; it does not adjudicate conflicts, and a candidate known
  to conflict with another surface is reported rather than moved.
- **Authoring the linter, hook, or skill** that rung 2 and rung 3 route to. The routing is the
  output; building the destination is separate work.
