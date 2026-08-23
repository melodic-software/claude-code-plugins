# Routing out — the neighbouring questions this audit does not answer

Read this when a candidate raises something that is *not* a placement question, and you need to know
where it goes and what to do when the owning plugin is not installed.

Placement is one question about an instruction. "Is it still needed?", "is it duplicated?", "is it
too long?" and "should this file exist?" are four others, each owned elsewhere. Bending this rubric
to answer them produces a finding nobody can act on, because the remedy lives in a different tool.

## The routes

Each is **presence-gated**: invoke the named skill via the Skill tool when its plugin is installed;
otherwise keep the observation in the report as a plain note naming what the operator would need,
and do not judge it against the placement rubric instead.

| The candidate actually raises | Route to | Fallback when the plugin is absent |
|---|---|---|
| Does the current model still need this instruction? | `claude-config:audit-instructions` | Note it as a model-era-fit question, unjudged |
| Is the memory layer healthy — size, index integrity, conflicts? | `claude-memory:audit` | Note the symptom and the file it appeared in |
| Should this whole document exist at all? | `docs-hygiene:audit-derivability` | Note that the file, not the section, is the unit in question |
| Is this file structured well for disclosure generally? | `docs-hygiene:audit-progressive-disclosure` | Note the structural smell |
| Is this content repeated across several files? | `docs-hygiene:extract-ssot` | Name the copies; do not pick a winner |
| Is this prose too long or too noisy? | `docs-hygiene:compress` | Note it; never rewrite while relocating |

## Two rules that keep routing honest

**Route, do not absorb.** A candidate routed out is reported *as routed*. It is not silently
dropped, and it is not quietly re-classified as a placement finding because the sibling plugin
happened to be unavailable. An operator reading the report should be able to see that the question
was recognized and where it went.

**Route once, and keep the placement finding if there is one.** These are not exclusive. A section
can be both misplaced *and* duplicated across three documents. Routing the duplication question does
not cancel the placement proposal — report both and let the operator sequence them. Collapsing them
loses whichever one you decided was secondary.

## Why the boundary sits here

Those audits ask whether a piece of content is *good*, *needed*, or *duplicated*. This one asks only
where it should **live** — and owns the capability none of them has: the validated move, including
glob derivation and the index that keeps the result reachable afterwards.

The two ladder rungs this plugin deliberately reports rather than executes — content a linter should
enforce, and content that should become a skill — follow the same logic. Building the replacement
mechanism is separate work, and deleting an instruction before its replacement exists removes the
only thing enforcing it.
