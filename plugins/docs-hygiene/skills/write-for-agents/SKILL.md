---
description: "Write or trim agent-consumed markdown: CLAUDE.md or AGENTS.md content, .claude/rules files, agent-loaded reference docs, navigation pointers, and doc-plus-pointer extractions. Use when: 'add this to CLAUDE.md', 'trim this AGENTS.md', 'cut it down to what earns its place', 'prune what an agent could derive', 'write a rule for X', 'write this up for the agent', 'add a pointer to the docs', 'move this section into its own doc', 'draft an AGENTS.md section', or any edit to markdown an agent loads. SKILL.md authoring is playbooks:skill-authoring; human-facing docs are docs-hygiene:write-for-humans."
argument-hint: "[<file or section being written>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Authoring-time doctrine for agent-consumed markdown
---

# Write For Agents

## Why this skill exists

The docs-hygiene siblings audit docs that already exist. This skill is the write-side complement:
it fires while the doc is written, so the problems the audits catch are never created. Its scope
is any markdown an agent will consume; the auto-read surfaces (CLAUDE.md scopes, `.claude/rules`,
auto-memory, and their kin) are the high-value core because their cost recurs every session. Read
[`reference/agent-doc-surfaces.md`](reference/agent-doc-surfaces.md) when you need to know
whether, when, and how much of a target file the harness loads. Write differently for an
always-loaded surface than for an on-demand one.

## Budget both loads

Every line spends two budgets, and cutting one can overspend the other:

- **Context load**. Tokens the agent pays, every session for always-loaded surfaces. Governed
  marketplace-wide by plugin-philosophy's Instruction economy: an instruction earns its place
  with observed-stumble evidence, or it goes.
- **Cognitive load**. Attention the human maintainer pays: they must be able to hold the map of
  where things live. Ten tiny fragment files can be cheaper for the agent and ruinous for the
  human; one 500-line file the reverse. When the two budgets conflict, say which one you spent
  and why.

Fewer words spends less of both. The universal brevity rules apply: no more words than the meaning
needs, no filler, hedging, intensifiers, expletive openings, or restatement of an adjacent line;
active voice; one idea per sentence; a factual register with nothing sold. `/writing:be-concise`
owns those rules when the `writing` plugin is installed; without it, apply them from this
paragraph. Take those rules and no more of that doctrine: its human-only rules do not transfer. A
bottom-line-first opening, headings written to be skimmed, bullet lists for scanning, and bounded
bold serve a person moving down a page fast; an agent needs the rule stated where it applies, not
staged for a skim.

## Know which surfaces are system prompt

Three vehicles shape the system prompt: a subagent definition's body, an output style, and the
launch flags that replace or append to it (`--system-prompt`, `--append-system-prompt`, and their
`-file` forms). CLAUDE.md files, rules, and skill bodies reach the model as conversation content in
the user turn: write them as instructions read in the conversation, stating the rule, its scope,
and its reason. A rule that must hold at system-prompt level goes in a subagent body, an output
style, or a launch flag.

- **Pointer**: for how CLAUDE.md content is delivered, see
  <https://code.claude.com/docs/en/memory#troubleshoot-memory-issues>; for a subagent body, see
  <https://code.claude.com/docs/en/sub-agents#write-subagent-files>; for output styles, see
  <https://code.claude.com/docs/en/output-styles#how-output-styles-work>; for the flags, see
  <https://code.claude.com/docs/en/cli-reference#system-prompt-flags>; for skill content, see
  <https://code.claude.com/docs/en/skills#skill-content-lifecycle>.
- **As of**: 2026-10-01
- **Recheck trigger**: one of those sections changes how its content reaches the model.

## Write pointers that cover their branches

A pointer is a routing instruction: the reader decides from the pointer text alone whether to
follow it, without opening the target.

- **Put the matching term first.** Open with the term the reader is matching on ("Deploys:
  see…", never "See the following doc for information about deploys").
- **Cover the branches.** State when to follow it and what the reader gets ("for tracked-changes
  output specifically, read X"), so both the follow and the skip are informed decisions.
- A pointer that exists only because changes must be mirrored across distant folders can mask a
  cohesion problem. Before adding it, consider restructuring so things that change together live
  together: a pointer papering over low cohesion outlives the reorganization that would have
  removed it. (Audit-side remediation home: `harness-memory:audit`'s C5 fix guidance, if that
  plugin is enabled.)

The sibling audit skill owns the full pointer-quality criteria. Invoke
`/docs-hygiene:audit-progressive-disclosure` via the Skill tool to grade a draft against them,
rather than failing them at audit time.

## Separate steps from reference, and co-locate what runs together

Steps are read in order and executed; reference is jumped into and queried. Mixing them hurts
both: lookup tables interrupt a procedure's thread, and reference buried in a procedure is
unfindable.

- Put the procedure in one contiguous block; move lookup material below it or into a spoke file
  with a conditioned pointer.
- Co-locate what is consumed together: the fact a step depends on belongs beside the step, not
  three sections away. Distance a reader must jump during execution is a defect.
- Sprawl is the failure of both: when a file serves several audiences or moments, split it along
  who-reads-when lines, not topic lines.

## Give every step a completion criterion

A step is done when its criterion says so, not when text resembling the step has been produced.

- **Clarity and demand.** State what "done" observably is, and demand it: "run X; the step is
  complete when Y appears" beats "run X".
- **Premature completion** is the shape to design against: a step satisfiable before its
  goal-state is reached will be marked complete at first plausible output. Make the criterion
  the goal-state, never the attempt.
- **Post-completion steps.** When finishing creates an obligation (regenerate, notify, clean
  up), state it in the step; an obligation after "done" is otherwise dropped.
- **The agent does the legwork.** Write steps that resolve their own facts from the environment;
  a step that sends the human to look up something the agent could read is a defect.
- **Hiding later steps** from the agent works only across a real context boundary (a hand-off or
  a subagent dispatch); an inline call leaves the later steps in context.

A task-shaped or long-run instruction also names the whole task's finish line and its stops:

- **Keep going** when a step needs no input, with status notes in the same message as the next
  action, not a summary that names the next step, an offer to continue, or a list of choices that
  block nothing.
- **Stop and ask** only when nothing can move without the human, or before a destructive,
  hard-to-undo, or outward action. Never pair a keep-going rule with turning off permission prompts
  or confirmation gates.
- **Long runs** keep the task list in a file, ticked as items finish, since compaction summarizes
  the scrollback; reuse a ledger the workflow already has. The final report opens with what is
  blocked on the human, then what changed and what was found.

## Split by sequence; choose invocation by the rubric

When one doc serves two moments in time, split it at the moment boundary: the reader at step one
should not scroll past material for step nine. Splitting an instruction surface into skills with
different invocation modes is a different axis with its own decision rubric: follow the
[invocation-mode rubric](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/invocation-mode/README.md)
(§ Splitting by invocation) rather than deciding it ad hoc.

## Prompt the positive

Write what to do, not what to avoid: a prohibition drags the banned behavior into context, and
pretrained leading words are the compact anchors that steer ("Prefer X" over "Never do Y unless").
Keep a negation only when the positive form genuinely loses the constraint, and state the positive
alternative in the same sentence. A design exclusion is the exception that stays negative: name
the specific styles to leave out ("no hero banner, no pill-shaped buttons"),
since "avoid a generic look" swaps one default for another.

Ask for outcomes, not thinking. Whether a "think carefully" line helps depends on the target model,
so follow `/harness-config:audit-instructions` criterion I8-f for the model the text will run on:
it drops these lines for Opus 5.5, where depth is the effort setting's job and a quick answer is
a lower effort level first, "Answer directly." second. A line telling the model to think less or
not at all is I8-c's, scoped per model the same way. Never ask the model to show or reproduce
its reasoning in the reply, which some models decline; ask for what the reader needs, such as the
rationale in two or three sentences or the evidence as a list.

## Be strict with precise words

Words like "reasonably", "tasteful" and "where appropriate" are too soft to force the agent to
follow them, so it falls back to its defaults: those sentences don't change behavior. State the
number, the condition or the boundary instead, which narrows the answers the agent has to choose
from. An example of the form:

```text
Bad:  Keep the summary reasonably short and mention the tests where appropriate.
Good: The summary is at most three sentences. Name each test command you ran with its
      pass and fail counts.
```

Strict means precise, not loud. Keep firm words (never, always) for a hard limit no hook
enforces, since that is the one rule that must not bend to context, and write no all-caps
emphasis: reframe the line and give its reason instead. A firm word anywhere else is a flag to
reconsider, not a ban.

- **Pointer**: skill-creator,
  [How to think about improvements](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md#how-to-think-about-improvements).
- **As of**: 2026-10-29
- **Recheck trigger**: that section moves or changes its guidance on emphasis.

## Leading words

A leading word is a compact concept the model already holds from pretraining, repeated as a token
and never re-explained, so it anchors a region of behavior in few tokens.

- **Prefer an existing word to a coined one.** A coined word must be defined, and it recruits no
  prior.
- **Look for collapse candidates.** A triad spelled out at several sites, or a pointer spending a
  sentence on one idea, is a candidate to collapse into one word.

## The no-op test

Run it sentence by sentence. An instruction the model already follows by default spends load and
says nothing. Running the document, not debate, settles whether a sentence changes behavior.
Delete a failing sentence whole. A word too weak to beat the default is a no-op too; the fix is a
stronger word: a more precise one, and a firm one only for a hard limit
([Be strict with precise words](#be-strict-with-precise-words)).

## After writing

- Repeated the same prose in another file, even a second occurrence or a recap of an SSOT that
  already exists? Invoke `/docs-hygiene:extract-ssot` via the Skill tool. A new shared home still
  waits for the third occurrence; below that it remedies the repetition in place.
- Resolved or coined a term in the **consuming project's** domain? Invoke
  `/domain-driven-design:curate-language` via the Skill tool (if that plugin is enabled) rather
  than hand-writing the entry. A skill defining its own working vocabulary is out of that skill's
  scope and stays where it is.
- Editing exposed pre-existing problems in the surrounding doc? Invoke the fitting audit
  sibling via the Skill tool (`/docs-hygiene:audit-noise`, `/docs-hygiene:audit-derivability`,
  `/docs-hygiene:audit-progressive-disclosure`) rather than expanding this write into an audit.

## What this skill does not do

- **Does not author skills.** Whether a skill should exist, what it triggers on, its frontmatter,
  action shape and body structure are `/playbooks:skill-authoring` territory (description shape
  and caps: `## Descriptions`; body size: `## Body`), enforced by `/skill-quality:check`. Prose
  inside an already-authored SKILL.md is still this skill's, since a SKILL.md is agent-consumed
  markdown. The boundary is authorship against wording, not a whole file this skill may not look
  at; read otherwise, the largest agent-facing surface most repos have is governed by no
  authoring doctrine at all.
- **Does not audit existing docs**: the audit siblings own read-only findings; this skill fires
  at the writing moment only.
- **Does not write human-facing docs**. End-user READMEs, changelogs, and marketing prose have
  a different reader and different rules: they belong to the sibling
  `docs-hygiene:write-for-humans`, which fires at this same moment and resolves the consuming
  project's own style guide first.
- **Does not enforce via hooks**. Trigger reliability rests on this skill's description and its
  eval suite, deliberately not on a forcing hook.
