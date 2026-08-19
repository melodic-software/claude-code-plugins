---
description: "Write agent-consumed markdown well at the moment of writing — CLAUDE.md or AGENTS.md content, .claude/rules files, agent-loaded reference/context docs, navigation-pointer lines, and doc-plus-pointer extractions. Use when: 'add this to CLAUDE.md', 'write a rule for X', 'write this up for the agent', 'add a pointer to the docs', 'move this section into its own doc', 'draft an AGENTS.md section', or any drafting or editing of a markdown file an agent will load. NOT for: creating or editing a SKILL.md (playbooks:skill-authoring and skill-quality:check own that), auditing existing docs (the docs-hygiene audit skills own that), or human-facing docs such as end-user READMEs and changelogs."
argument-hint: "[<file or section being written>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Authoring-time doctrine for agent-consumed markdown
---

# Write For Agents

## Why this skill exists

The docs-hygiene siblings are audit-shaped: they find problems in docs that already exist. This
skill is the write-side complement — it fires while the doc is being written, so the problems the
audits catch are not created in the first place. Its scope is any markdown an agent will consume;
the auto-read surfaces (CLAUDE.md scopes, `.claude/rules`, auto-memory, and their kin) are the
high-value core because their cost recurs every session. Read
[`reference/agent-doc-surfaces.md`](reference/agent-doc-surfaces.md) when you need to know
whether, when, and how much of a target file the harness actually loads — write differently for
an always-loaded surface than for an on-demand one.

## Budget both loads

Every line you write spends two budgets, and cutting one can overspend the other:

- **Context load** — tokens the agent pays, every session for always-loaded surfaces. Governed
  marketplace-wide by PLUGIN-PHILOSOPHY's Instruction economy: an instruction earns its place
  with observed-stumble evidence, or it goes.
- **Cognitive load** — attention the human maintainer pays. The human is the index of the doc
  set: they must be able to hold where things live. Ten tiny fragment files can be cheaper for
  the agent and ruinous for the human; one 500-line file the reverse. When the two budgets
  conflict, say which one you spent and why.

## Write pointers that cover their branches

A pointer is a routing instruction; the reader decides whether to follow it from the pointer
text alone, without opening the target.

- **Front-load the leading word.** Open with the term the reader is matching on ("Deploys:
  see…", never "See the following doc for information about deploys").
- **Cover the branches.** State when to follow it AND what the reader gets ("for tracked-changes
  output specifically, read X"), so both the follow and the skip are informed decisions.
- A pointer that exists only because changes must be mirrored across distant folders can mask a
  cohesion problem. Before adding it, consider restructuring so the things that change together
  live together — a pointer papering over low cohesion outlives the reorganization that would
  have removed it. (Audit-side remediation home: `claude-memory:audit`'s C5 fix guidance, if
  that plugin is installed.)

The full pointer-quality criteria are owned by the sibling audit skill — invoke
`/docs-hygiene:audit-progressive-disclosure` via the Skill tool to grade a draft against them,
rather than failing them at audit time.

## Separate steps from reference, and co-locate what runs together

Steps are read in order and executed; reference is jumped into and queried. Mixing them makes
both worse — a procedure interrupted by lookup tables loses its thread, and reference buried in
a procedure is unfindable.

- Put the procedure in one contiguous block; move lookup material below it or into a spoke file
  with a conditioned pointer.
- Co-locate what is consumed together: the fact a step depends on belongs beside the step, not
  three sections away. Distance a reader must jump during execution is a defect.
- Sprawl is the failure of both: when a file serves several audiences or moments, split it along
  who-reads-when lines, not topic lines.

## Give every step a completion criterion

A step is done when its criterion says so — not when text resembling the step has been produced.

- **Clarity and demand.** State what "done" observably is, and demand it: "run X; the step is
  complete when Y appears" beats "run X".
- **Premature completion** is the shape to design against: a step satisfiable before its
  goal-state is reached will be marked complete at first plausible output. Make the criterion
  the goal-state, never the attempt.
- **Post-completion steps.** When finishing creates an obligation (regenerate, notify, clean
  up), state it in the step — an obligation after "done" is otherwise dropped.
- **The agent does the legwork.** Write steps that resolve their own facts from the environment;
  a step that sends the human to look something up the agent could read is a defect.

## Split by sequence; choose invocation by the rubric

When one doc serves two moments in time, split it at the moment boundary — the reader at step
one should not scroll past material for step nine. Splitting an instruction surface into skills
with different invocation modes is a different axis with its own decision rubric: follow the
[invocation-mode rubric](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/invocation-mode/README.md)
(§ Splitting by invocation) rather than deciding it ad hoc.

## Prompt the positive

Write what to do, not what to avoid: a prohibition drags the banned behavior into context, and
pretrained leading words are the compact anchors that steer ("Prefer X" over "Never do Y unless").
Keep a negation only when the positive form genuinely loses the constraint — then pair it with
the positive alternative in the same sentence.

## After writing

- Repeated the same prose a third time? Invoke `/docs-hygiene:extract-ssot` via the Skill tool.
- Resolved or coined a domain term? Invoke `/domain-driven-design:curate-language` via the
  Skill tool (if that plugin is installed) — never hand-write a glossary entry.
- Editing exposed pre-existing problems in the surrounding doc? Invoke the fitting audit
  sibling via the Skill tool (`/docs-hygiene:audit-noise`, `/docs-hygiene:audit-derivability`,
  `/docs-hygiene:audit-progressive-disclosure`) rather than expanding this write into an audit.

## What this skill does NOT do

- **Does not author skills** — a SKILL.md is `playbooks:skill-authoring` + `skill-quality:check`
  territory; this skill's doctrine reaches skill authors through those surfaces.
- **Does not audit existing docs** — the audit siblings own read-only findings; this skill fires
  at the writing moment only.
- **Does not write human-facing docs** — end-user READMEs, changelogs, and marketing prose have
  a different reader and different rules.
- **Does not enforce via hooks** — trigger reliability is carried by this skill's description
  and its eval suite, deliberately not by a forcing hook.
