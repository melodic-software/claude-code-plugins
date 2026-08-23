---
description: "Write human-facing prose well at the moment of writing — end-user READMEs, RFCs, design docs, release notes, changelog entries, tutorials, how-to guides, reference pages, and explanations. Resolves the consuming project's own style guide first and applies a named default set only as the fallback (Diátaxis document modes, Google developer style, ASD-STE100 instruction rules, Global English disambiguation). Use when: 'write the README', 'draft an RFC', 'write the release notes', 'write a how-to for X', 'document this for users', 'write this up for humans', 'what kind of doc is this', 'is this the right kind of doc', 'make this doc readable', 'this doc reads like a machine wrote it'. NOT for: markdown an agent will load — CLAUDE.md or AGENTS.md content, rules files, agent-loaded reference docs — which is docs-hygiene:write-for-agents; auditing prose that already exists (the docs-hygiene audit skills own structure and derivability, ai-slop:audit owns AI-writing tells); commit-message or PR-body shape, owned by source-control; or product UI strings, which follow your product's own copy guidelines."
argument-hint: "[<doc or section being written>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Authoring-time doctrine for human-read documentation
---

# Write For Humans

## Why this skill exists

`docs-hygiene:write-for-agents` is the write-side doctrine for markdown an agent loads, and it
excludes human-facing prose deliberately, in its description and again in its own
"What this skill does NOT do": end-user READMEs, changelogs, and marketing prose "have a different
reader and different rules." This skill is those rules. The two are siblings on the same axis:
one moment (while the doc is being written), split by who reads the result.

The reader here is a tired engineer on their first read. Four questions get you to prose they
understand: what kind of document is this, how do sentences address them, how much does each
sentence carry, and can any sentence be read two ways.

## Resolve the standard before you apply one

**The project's own style guide wins. Always.** Before writing, look for one — a `STYLE.md`, a
documentation contributing guide, a house standard named in the contributor docs, or a linter config
encoding prose rules. When the project declares a standard, it is authoritative and everything below
is a fallback you do not reach for. Say which one you resolved, in one line, before you write.

The layers below are a **named default set**, not this plugin's house rules:

| Layer | Question it answers | Standard |
|---|---|---|
| Mode | What kind of document is this? | Diátaxis |
| Address | How do sentences talk to the reader? | Google developer documentation style |
| Load | How much does each sentence carry? | ASD-STE100 Simplified Technical English |
| Ambiguity | Can this be read two ways? | Global English |

A project that adopted a different guide — Microsoft's, Chicago, an in-house one — gets that guide,
not these. A project with none gets these, and you say so, so the choice stays visible and the
project can overrule it later. Never silently impose one.

When a rule makes a sentence worse, fix the sentence another way or leave it alone. The rules serve
the reader; a sentence that obeys every rule and sounds machine-written has failed.

## Three rules that survive a declared guide

These are the only part of this skill that outlives a project's own guide: they are about doing the
work, not picking a style, and no standard asks you to keep dead words or rename the thing you are
documenting. Apply them whichever standard you resolved — and if a project's guide somehow
contradicts one, the guide still wins.

- **Cut every word that does no work.** If the sentence survives without a word, the word goes.
  "In order to" is "to". "It is important to note that" is nothing.
- **Use the short, everyday word.** "Use", not "utilize". "Help", not "facilitate". A long word has
  to buy its length with precision.
- **Write the real name, and the real number.** The thing being documented supplies the vocabulary:
  the actual symbol, file, flag, or command name, never a synonym or a description of it. Do not
  invent jargon — use the words a developer would say out loud ("move", "delete", "a budget that
  only decreases", not "evacuate", "ratchet", "endgame"); a named pattern is fine when the doc says
  what it means the first time. Counts, file trees, and inventories are claims too: each must be
  true at the commit that lands it, and the doc should carry the command that regenerates it.

## Pick the mode first

One document, one mode. Two questions pick it: does the content serve **doing** or
**understanding**, and does it serve **learning** or **work**?

- Doing + learning → **tutorial**
- Doing + work → **how-to**
- Understanding + work → **reference**
- Understanding + learning → **explanation**

Use the compass on a whole document or on a single sentence. Reach for it whenever you feel unsure
what you are writing; gut feel is often wrong here.

**Tutorial — learning by doing.** You are the teacher and the learner's success is your job. Open
by saying what they will build, not what they will "learn". Every step produces a visible result,
and you tell them what they should see: the expected output, the prompt change, the log line. Cut
explanation to one clause and a link — teaching pauses break the lesson. Write as "we", in commands.

**How-to — steps to a goal.** Solve a problem a person has, not an operation the machine can
perform. Assume competence, skip teaching, allow forks ("if you want x, do y"). Name the guide by
the task ("How to calibrate the radar array", not "Radar array calibration").

**Reference — facts for lookup.** Describe, and only describe. No instruction, no persuasion, no
opinion, no hedging: state facts, options, limits, and errors. Mirror the structure of the thing
described so code and docs navigate together, and generate from source where you can so it stays
true.

**Explanation — understanding and why.** One bounded topic, readable away from the product. Each
title should tolerate an implicit "About…" in front. Give design decisions, history, constraints,
and alternatives. Opinion is allowed here and nowhere else.

**Do not mix modes.** No reference tables inside a tutorial, no hand-holding inside reference, no
arguing inside a how-to. Split and link instead.

## Vary the rhythm

A document can obey every layer and still read machine-written: every sentence clipped short, no
view anywhere, nothing specific.

- Mix sentence lengths on purpose. Short sentences land a point; a longer one that takes its time
  carries a fact with its condition or consequence.
- One thought per sentence is not one length per sentence. Split the sentence carrying two
  thoughts. Keep the long sentence carrying one.
- Have a view where the mode allows it. Explanation weighs trade-offs, so say what you make of them
  instead of listing pros and cons. Reference stays dry.
- Be specific over sterile. Not "schema changes can cause issues" but "a column rename fails the
  build".

## Write the sentences

The three sentence-level layers — address, load, ambiguity — apply to every sentence at once, so
they live together in one place rather than three:
[`reference/sentence-rules.md`](reference/sentence-rules.md). Read it while drafting, not after.

## A worked example

The names below are placeholders standing in for whatever the real symbols are; in a real document
they would be the actual file and flag names, per the third rule above.

Before:

> Configuration of the retry attempt limit parameters is performed via the settings file. Note that
> it is important to remember that running with the reset flag, which updates the stored limit to
> reflect the current value, should only be done when lowering it. If exceeded, the request fails.

After:

> The client reads its retry limit from the settings file. If a request exceeds the limit, the
> request fails. Use the reset flag only to lower the limit.

The fixes, by layer. "Configuration is performed" becomes "the client reads", so someone does
something (address). The five-noun string "retry attempt limit parameters" breaks into plain clauses
(ambiguity). The hedge "note that it is important to remember" is deleted (cut every word that does
no work). The failure condition moves ahead of the step it explains (load). The buried "should only
be done when lowering" becomes a command with "only" next to the verb it changes (load and
ambiguity). "If exceeded" gets a subject: the request (ambiguity).

## After writing

- **Check for AI-writing tells.** Invoke `/ai-slop:audit` via the Skill tool when it is available in
  the session; when it is not, re-read for the obvious tells yourself — filler, stacked hedging,
  negative parallelism, promotional tone — and say that you did the lighter pass.
- **Repeated the same prose in another file — even a second occurrence, or a recap of an SSOT that
  already exists?** Invoke `/docs-hygiene:extract-ssot` via the Skill tool. Creating a new shared
  home still waits for the third occurrence; below that it remedies the repetition in place.
- **The draft is over-long rather than misshapen?** Invoke `/docs-hygiene:compress` via the Skill
  tool; it trims flavor behind a semantic-diff guard rather than rewriting.
- **Writing markdown an agent will load instead?** That is `/docs-hygiene:write-for-agents`.

## Self-check before handing back

**Check the draft against the standard you resolved.** Questions 4, 6 and 7 restate the three rules
above, so they apply whichever standard that was. The other four come from the bundled layers: when
the project declared its own guide, that guide supplies their equivalents and these four do not
apply — reaching for them would impose the bundled set on a project that already chose. Answer
whichever apply against the text you just wrote, not from memory of writing it.

1. Is each document one mode, with links where modes meet? Confirm it by naming the mode.
2. Is every instruction a command, with its condition in front?
3. Does any sentence carry two instructions, or two thoughts? Split it until each carries one.
4. Can any word be cut without losing meaning? Cut it.
5. Is "only" next to the word it changes? Does every "it" point at one obvious thing? Does every
   clause keep its verb?
6. Does each thing have exactly one name throughout?
7. Would a developer say these words out loud? Replace invented metaphors and fancy synonyms with
   the plain word or the real name.

The draft is done when every answer is yes. A "no" is a rewrite now, not a note for later.

## What this skill does NOT do

- **Does not impose a style guide.** The consuming project's declared standard wins; the bundled set
  is a fallback, and which one was applied is stated in the output.
- **Does not audit existing prose.** Structure and derivability belong to the `docs-hygiene` audit
  siblings; AI-writing tells belong to `ai-slop:audit`. This skill fires at the writing moment only.
- **Does not write agent-consumed markdown** — CLAUDE.md or AGENTS.md content, rules files, and
  agent-loaded reference docs are `docs-hygiene:write-for-agents`.
- **Does not touch commit messages or PR bodies.** Their shape is owned by `source-control:commit`'s
  subject-convention ladder and the marketplace's PR-body-sections convention, and the
  markdown-prose regime already excludes them.
- **Does not cover product UI strings.** Button labels, empty states, and error toasts are product
  copy, not documentation; they follow your product's own copy guidelines.
- **Does not author skills** — a SKILL.md is `playbooks:skill-authoring` and `skill-quality:check`
  territory.
- **Does not claim to be the standards it names.** Each layer is a paraphrase of a published
  standard; see the source records below.

## Gotchas

- **Falling back because no `STYLE.md` sat in the root.** Style rules also live in contributor
  guides, docs READMEs, and prose-linter configs. Look in all of them before reaching for the
  bundled set — an unnoticed house guide is the failure this skill's first step exists to prevent.
- **Rewording a passage the edit did not touch.** It costs a reviewer a diff they must read for
  nothing, and it teaches the codebase two names for one thing. Change what the edit is about.
- **Flattening explanation into reference.** Explanation is the one mode that permits a view, and
  stripping its opinions into a neutral list of trade-offs is the usual way a good design document
  dies. If it answers "why", say what you make of it.
- **Treating the mode as a whole-document decision only.** A tutorial carrying one reference table
  is still a mixed document. The compass applies to the paragraph in front of you.

## Source records

The four bundled layers are distilled paraphrases of published standards, each with a four-part
drift stamp — claim, basis, as-of date, recheck trigger — in
[`reference/sources.md`](reference/sources.md). Read it before citing a layer as the standard: the
STE layer is a principles subset, and a document written to it is not thereby STE-conformant.
