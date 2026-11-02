---
description: "Write human-facing prose: READMEs, RFCs, design docs, release notes, changelog entries, tutorials, how-tos, reference, explanations, per the project style guide. Use when: 'write the README', 'draft an RFC', 'write the release notes', 'write a how-to for X', 'document this for users', 'write this up for humans', 'what kind of doc is this', 'is this the right kind of doc', 'make this doc readable', 'this doc reads like a machine wrote it'. Agent-loaded markdown: docs-hygiene:write-for-agents."
argument-hint: "[<doc or section being written>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Authoring-time doctrine for human-read documentation
---

# Write For Humans

## Why this skill exists

`docs-hygiene:write-for-agents` covers markdown an agent loads and excludes end-user READMEs,
changelogs, and marketing prose, which "have a different reader and different rules." This skill
holds those rules: the same moment (while the doc is written), a different reader.

## Resolve the standard before you apply one

**The project's own style guide wins. Always.** Before writing, look for one: a `STYLE.md`, a
documentation contributing guide, a house standard named in the contributor docs, or a linter
config encoding prose rules. A declared standard is authoritative and everything below is a
fallback you do not reach for. Say which one you resolved, in one line, before you write.

The layers below are a **named default set**, not this plugin's house rules. Each settles one
question about the draft, and a finished draft answers all four:

| Layer | Question it answers | Standard |
|---|---|---|
| Mode | Which kind of document is it? | Diátaxis |
| Address | How does a sentence speak to its reader? | Google developer documentation style |
| Load | How much does one sentence hold? | ASD-STE100 Simplified Technical English |
| Ambiguity | Can this be read two ways? | Global English |

A project that adopted a different guide (Microsoft's, Chicago, an in-house one) gets that guide.
A project with none gets these, and you say so, so the choice stays visible and the project can
overrule it later. Never silently impose one.

## Four rules that survive a declared guide

A project's own guide replaces everything else in this skill, but not these four: they concern
doing the work, not choosing a style. Apply them under whatever standard you resolved. If a
project's guide contradicts one of them, the project's guide wins.

| Rule | The test | Example |
|---|---|---|
| **Delete every word that carries nothing.** | Delete the word and reread. If the meaning holds, it stays deleted. | "At this point in time" becomes "now". "It should be noted that" becomes nothing at all. |
| **Prefer the short, common word.** | A longer word stays only when it is more exact than the short one. | "Start", not "commence". "About", not "approximately". |
| **Write the real name, and the real number.** | Could a reader paste the term into a codebase search and find it? Name a symbol, file, option, or command as the code names it, not by a description or synonym. | `retry_limit`, not "the retry setting". |
| **Introduce each concept before a sentence relies on it, or name it as assumed knowledge.** | Read as someone new to the system. Find the first sentence that uses each term they may not know, including a common word that names one specific thing ("the broker", "the vault"). Its definition goes in that sentence or an earlier one, never the next: a reader who meets an unexplained word has to guess. Without one, name the term as assumed knowledge before that sentence, or add the definition. Notes often define a term after using it; reorder rather than copy that order. | Before "To write an archive to your vault, run `stash export`.", a README says "Stash keeps your archives in a vault, a folder that `stash init` creates." Or its opening says "This guide assumes you have a stash vault." Not "Run `stash export` to write an archive to your vault. A vault is a folder…": the definition comes one sentence late. |

Two cases the third rule's test misses:

- **A count or a listing.** "Twelve modules", a directory tree, or a file list describes one
  commit and drifts after it. Verify it against the commit that adds it, and show beside it how
  you got it, such as `ls src/modules | wc -l`, so a later editor can rerun that and compare.
- **A word you made up.** Figurative labels ("ratchet", "north star", "substrate", "wedge in")
  fail the search test. Write what the thing is in plain words: "a limit that can only go down",
  "the goal", "the base", "add". A document may name a pattern, as long as the sentence where the
  name first appears says what it means.

## Pick the mode first

Each document has exactly one mode. Two questions choose it: will the reader act on this
(**doing**) or think about it (**understanding**)? Is the reader studying (**learning**) or on the
job (**work**)?

| | Learning | Work |
|---|---|---|
| **Doing** | tutorial | how-to |
| **Understanding** | explanation | reference |

This grid is the compass. Point it at a whole document or at one sentence, and consult it whenever
the kind of document is in doubt.

The mode then sets each column below:

| Mode | Voice | Title and opening | Body | Keep out |
|---|---|---|---|---|
| **Tutorial** | Commands, with "we" as the subject. A stuck reader is a defect in the tutorial, not in the reader. | The artifact the reader ends with, such as "a webhook receiver that answers on port 8080", not a list of topics. | Concrete steps, each followed by what the reader should now observe: a 200 response, a green check, a new file in the folder, so a mismatch shows at the step that caused it. | Background and theory: at most one clause plus a link to the explanation page; a detour mid-lesson loses the reader. |
| **How-to** | Commands to a competent reader. | The task as the reader would say it: "How to rotate the signing key", not "Signing key rotation". | Only the steps to a result someone needs, with branches where choices exist ("if you need x, do y"). | Teaching, and tours of what the system can do. |
| **Reference** | Neutral and certain. | The structure of the documented thing, so a reader can move between the code and the page. | Every option, limit, error, and fact, generated from the source code when it can be, to keep it accurate. | Instructions, persuasion, opinion, and hedging. |
| **Explanation** | Yours: the only mode where an opinion belongs. | A title that still reads correctly with "About" in front of it. | One bounded topic that makes sense without the product open: design decisions, constraints, history, and alternatives considered. | Material belonging to the other three modes. |

**One mode per document.** A tutorial carries no reference table, a reference page walks no one
through anything, and a how-to argues no position. Split the material into separate documents and
link them.

## Check that a person could have written it

Run these three checks over a finished draft:

| Check | A failing draft | The repair |
|---|---|---|
| Is each claim as concrete as the facts allow? | "Caching can cause problems." | Name the case: "A stale cache serves last week's prices." |
| Where the mode allows a view, does the text reach one? | An explanation that sets advantages beside disadvantages and stops. | Say which way the trade-off comes out, and why. Reference pages stay neutral. |
| Do the sentence lengths differ? | Paragraph after paragraph of equally short sentences. | Keep short sentences for a point that should land; let a sentence run longer when a fact needs its condition or consequence beside it. Below the load caps, split by thought, not length: a sentence with two thoughts splits in two, and a long sentence with one stays whole. |

## Write the sentences

The address, load, and ambiguity layers apply to every sentence at once, so they share one file:
[`reference/sentence-rules.md`](reference/sentence-rules.md). Read it while drafting, not after.
It holds the load rules in full: the hard 20-word cap on instruction sentences, simple verb forms,
and the paragraph limits.

## A worked example

The names below are placeholders; a real document would use the actual command and flag names, per
the third rule above.

Before:

> Restarting workers only reloads the config file(s) when the --watch/--poll flag is set. If a
> worker crashes during the reload, it is restarted by the supervisor and it keeps the old settings.

After:

> To make a restarted worker reload its config files, pass `--watch`, `--poll`, or both. Without
> either flag, the worker keeps the settings it read at startup. If a worker crashes during a
> reload, the supervisor restarts that worker. The restarted worker runs with its previous settings.

The table follows the Before text from its first word to its last:

| Before | After | What changed |
|---|---|---|
| "Restarting workers" | "a restarted worker" | "Restarting" could name the act or describe the workers; the "-ing" word is gone (load). |
| "only reloads ... when" | "To make ... reload ..., pass" and "Without either flag" | "Only" sat beside the verb instead of the condition it limits. The goal now opens the sentence, and the no-flag case gets a sentence of its own (ambiguity, address). |
| "the config file(s)" | "its config files" | No "(s)" plural (ambiguity). |
| "the --watch/--poll flag" | "`--watch`, `--poll`, or both" | The slash is spelled out, and the flags are in code font (ambiguity, address). |
| "it is restarted by the supervisor" | "the supervisor restarts that worker" | The actor does the action (address), and the noun replaces "it" (ambiguity). |
| "it keeps the old settings" | "The restarted worker runs with its previous settings." | The second "it" could mean the worker or the supervisor; the noun is repeated, in a sentence of its own (ambiguity, load). |

## After writing

- **Read it once, at speed, as someone new to the system.** Every rule above serves this test: a
  reader with no context gets the point on the first pass. A sentence you had to read twice fails
  it, and so does one that reads as generated, however many rules it satisfies. If applying a rule
  left a sentence harder to read, revert that edit, then repair the sentence another way or keep
  the earlier wording.
- **Run the project's prose linter.** When the repository configures one (a Vale, markdownlint, or
  textlint config), run it on the files you wrote, fix what it reports in them, and report the
  command and its result.
- **Check for AI-writing tells.** Invoke `/ai-slop:audit` on the files you wrote via the Skill tool
  when it is available in the session; it reports filler, stacked hedging, negative parallelism,
  and promotional tone by line. When it is not available, report that the AI-tell check did not
  run.
- **Swapped out a figurative noun that ai-slop's catalog lacks?** With `/ai-slop:audit` among the
  available skills, end the reply with a candidate line for `rule-abstract-metaphor-jargon` giving
  the noun, its sentence, and your literal replacement. Only a person who accepts the candidate
  changes the catalog. Without ai-slop, the replacement in the draft is enough.
- **Repeated the same prose in another file. Even a second occurrence, or a recap of an SSOT that
  already exists?** Invoke `/docs-hygiene:extract-ssot` via the Skill tool. A new shared home
  still waits for the third occurrence; below that it remedies the repetition in place.
- **The draft is over-long rather than misshapen?** Invoke `/docs-hygiene:compress` via the Skill
  tool; it trims flavor behind a semantic-diff guard instead of rewriting.
- **Writing markdown an agent will load instead?** That is `/docs-hygiene:write-for-agents`.

## What this skill does NOT do

- **Does not impose a style guide.** The consuming project's declared standard wins; the bundled
  set is a fallback, and the output states which one was applied.
- **Does not audit existing prose.** Structure and derivability belong to the `docs-hygiene` audit
  siblings; AI-writing tells belong to `ai-slop:audit`. This skill fires at the writing moment only.
  Reshaping existing prose so a scanning reader gets the point is `/writing:be-concise` when the
  `writing` plugin is installed; without it, say the draft already exists and offer a re-read
  against the standard you resolved, not a rewrite.
- **Does not write agent-consumed markdown**. CLAUDE.md or AGENTS.md content, rules files, and
  agent-loaded reference docs are `docs-hygiene:write-for-agents`.
- **Does not touch commit messages or PR bodies.** `source-control:commit`'s subject-convention
  ladder and the marketplace's PR-body-sections convention own their shape, and the markdown-prose
  regime already excludes them. The wording inside a PR body is `/writing:be-concise` when the
  `writing` plugin is installed; without it, keep the required shape and leave the wording to the
  author. AI-writing tells in a commit message or PR body are `/ai-slop:audit commit` and
  `/ai-slop:audit pr-body`.
- **Does not cover product UI strings.** Button labels, empty states, and error toasts are product
  copy, not documentation; they follow your product's own copy guidelines. AI-writing tells in
  them are `/ai-slop:audit copy <source files>`.
- **Does not author skills**: a SKILL.md is `playbooks:skill-authoring` and `skill-quality:check`
  territory.
- **Does not claim to be the standards it names.** Each layer is our selection from a published
  standard; see the source records below.

## Gotchas

- **Falling back because no `STYLE.md` sat in the root.** Style rules also live in contributor
  guides, docs READMEs, and prose-linter configs. Look in all of them before reaching for the
  bundled set.
- **Rewording a passage the edit did not touch.** It costs a reviewer a diff read for nothing and
  gives the codebase two names for one thing. Change what the edit is about.
- **Flattening explanation into reference.** Explanation is the one mode that permits a view;
  stripping its opinions into a neutral list of trade-offs ruins a good design document. If it
  answers "why", give your verdict.
- **Treating the mode as a whole-document decision only.** A tutorial carrying one reference table
  is still a mixed document. The compass applies to the paragraph in front of you.

## Source records

The four bundled layers are our selections from published standards, each with a record (our
decision, a pointer, an as-of date, a recheck trigger) in
[`reference/sources.md`](reference/sources.md). Read it before citing a layer as the standard: the
STE layer is a principles subset, and a document written to it is not thereby STE-conformant.
