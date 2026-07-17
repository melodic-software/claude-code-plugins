---
name: point-dont-copy
description: "Re-anchor pointer-over-copy discipline, then audit the work in flight for copied content, internal-name coupling, and closed capability lists, and correct by pointing at the living source. Use when: 'point don't copy', 'you copied that', 'don't duplicate the docs', 'cite instead of paste', 'link don't restate', 'you enumerated the tools', 'that couples to internal names', 'this will drift', or at conversation start on documentation work."
user-invocable: true
disable-model-invocation: false
---

# Point, don't copy

A drift corrector for pointer-over-copy discipline. The method —
re-anchor, audit the work in flight, correct forward, report, and the tone
that firing this is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to duplication discipline.

## The discipline this re-anchors

Point at the living source; do not copy what it owns. This doctrine is
already owned by convention docs — re-anchor THEM, do not restate their
content here. Resolve the source of truth per the method doc's ladder:

- **Facts you own (in-repo).** Your organization's reference-don't-duplicate
  convention — every fact has one source of truth; consumers cite it by a
  stable anchor rather than restate it; literal versus semantic duplication;
  the describe / use / expose roles a file plays toward a fact.
- **Facts an upstream owns (external).** Your organization's
  documentation-and-citations convention — cite the upstream and fetch it at
  read time; do not recap upstream-owned catalogs, schemas, flag
  inventories, or defaults into tracked files; place the citation at the
  sentence that defers to it; a stored external value needs a recheck
  trigger.

Read those where they live. When a consuming project declares none of them,
re-anchor the portable baseline: provide a link or citation to the living
source and never restate the facts it owns — **a reworded paraphrase drifts
exactly as a verbatim copy does**, because both are a second copy that goes
stale when the source moves.

### This skill's own pins — beyond what the conventions state

- **Threshold two, not three.** The reference-don't-duplicate smell signals
  fire at "three or more" occurrences; this skill pins the trigger at **two**
  — the second copy is already duplication to resolve by pointing, not
  something to tolerate until a third appears. A deliberate, tighter
  refinement (and a candidate change to that convention). Weigh a genuine
  case for local divergence on its merits, but the default at two copies is
  to consolidate to one source and point at it.
- **Point at public contracts, not internals.** Reference the stable public
  contract — a tool's invocation surface, the command and its arguments —
  never the internal script or file names behind it, which are rename blast
  radius that breaks every citation the moment they move. (The conventions
  cover citing stable anchors; this names the specific trap of citing an
  internal name where the public contract exists.)
- **No capability enumeration.** Phrase your OWN duties open-ended, not just
  upstream-owned inventories. A closed list of what something can do goes
  stale as the surface evolves; name current mechanisms only as
  clearly-marked examples — "mechanisms such as X and Y (examples, not a
  fixed list)" — never as the definition.

### What is NOT a copy

Owning a fact is not copying it. A config genuinely adapted for this repo, a
constraint this project itself pins, a one-shot dated research deliverable,
and an error string empirically observed in this environment are content
THIS project authors and owns — they follow the conventions' "describe" and
"empirical findings / operator recipes the repo records" carve-outs, not the
copy prohibition. Do not flatten them into pointers.

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
