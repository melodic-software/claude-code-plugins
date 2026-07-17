---
name: point-dont-copy
description: "Re-anchor pointer-over-copy discipline, then audit the work in flight for copied content, internal-name coupling, and closed capability lists, and correct by pointing at the living source. Use when: 'point don't copy', 'you copied that', 'don't duplicate the docs', 'cite instead of paste', 'link don't restate', 'you enumerated the tools', 'that couples to internal names', 'this will drift', or at conversation start on documentation work."
user-invocable: true
disable-model-invocation: true
---

# Point, don't copy

A drift corrector for pointer-over-copy discipline. The method —
re-anchor, audit the work in flight, correct forward, report, and the tone
that firing this is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to duplication discipline.

## The discipline this re-anchors

Point at the living source; do not copy what it owns. Resolve the source
of truth per the method doc's ladder: if the consuming project states a
reference-don't-duplicate or progressive-disclosure convention in its own
`CLAUDE.md` / `.claude/rules/`, re-anchor THAT. Otherwise re-anchor this
portable baseline, in three parts.

### 1. Pointer over copy

Provide a link, citation, or reference to the living source; never restate
the facts that source owns. This holds for external, local, and cross-repo
content alike. **A reworded paraphrase drifts exactly as a verbatim copy
does** — both are a second copy of someone else's fact, and both go stale
when the source moves. The fix is a pointer, not better wording.

The line between pointing and copying:

| Fine — pointing or owning | Violation — copying |
|---|---|
| A bare link to the source | Verbatim quotes of a source's substance |
| An orientation clause (one line on what it is / where it lives) | Paraphrasing detail a source owns |
| Descriptive link text | Extracting a source's values into a table here |
| A config genuinely adapted for this repo | Copying a doc's config block verbatim |
| A constraint this project itself pins and owns | Hard-coded tool schemas or lists in a durable doc |
| A one-shot, point-in-time research deliverable | — |
| An error string empirically observed in this environment | — |

The right column restates facts another artifact owns and will drift from
it. The left column either points at the owner or is content THIS project
authors and owns — an adapted config, a self-set constraint, a dated
research snapshot, an observed error string. Owning a fact is not copying
it.

### 2. Point at public contracts, not internals

Reference the stable public contract, never a private internal. A tool's
public API is its invocation surface — the command and its arguments; the
names of the scripts and files behind it are rename blast radius that
breaks every citation the moment they move. Cite the front door.

### 3. No capability enumeration

Phrase duties open-ended. A closed list of what something can do goes stale
the moment the surface evolves. Name the current mechanisms only as
clearly-marked examples of a general duty — "mechanisms such as X and Y
(examples, not a fixed list)" — never as the definition.

### Threshold

Duplication starts at **two**. When the same content — a passage, a
literal, or a concept, verbatim or reworded — lives in two or more places,
that is duplication to resolve by pointing, not something to tolerate until
a third copy appears. Weigh a genuine case for local divergence on its
merits, but the default at two copies is to consolidate to one source and
point at it.

## Audit — what to look for

Name concrete, located findings (per the method doc's step 2):

- copied or paraphrased content — external, local, or cross-repo — that a
  named source already owns;
- extracted value tables or verbatim config blocks lifted from a source's
  docs;
- hard-coded tool schemas or capability lists in a durable doc;
- a reference to an internal script or file name where the public
  invocation contract would do;
- a closed enumeration of duties or mechanisms that will drift as the
  surface evolves;
- the same passage, literal, or concept appearing in two or more places.

Correct each forward now: replace the copy with a pointer to its owner,
swap an internal-name reference for the public contract, and reopen a
closed enumeration into a general duty with marked examples. Where content
is genuinely this project's own to hold (an adapted config, a self-pinned
constraint, a dated research deliverable), say so and leave it.

## What this skill does NOT do

- **Does not strip legitimate local content.** An adapted config, a
  self-owned constraint, a one-shot research snapshot, and an observed
  error string are not copies — do not flatten them into pointers.
- **Does not fabricate a violation.** A doc that already points rather than
  copies audits clean; say so.

## Gotchas

- The subtle case is the paraphrase — it reads as original prose but
  restates a fact another source owns. Judge by ownership, not by whether
  the words match.
- A pointer is only durable if it targets the public contract. Pointing at
  an internal name trades a copy-drift problem for a rename-drift one.
