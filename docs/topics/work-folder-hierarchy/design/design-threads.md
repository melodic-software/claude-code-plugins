# Design threads — topic-docs v3 interface

Input contract: the locked Brief (PR #3552 description, pre-prune SHA
`dd9752484`; epic #3554). Statuses: resolved | directional | deferred.
Threads T1 and T5 carry Design-It-Twice sketches per the Brief's mandate.
All nine threads RESOLVED 2026-09-01 under the session goal directive
(recommended options locked; fresh-context verifier validation required
before implementation builds on them — verdict recorded at the end).

## T1 — INDEX.md frontmatter schema (design-it-twice) — status: resolved (Sketch A)

The Brief locks: frontmatter is the single home for child order + slice
status, preserved across regeneration. Contested: the key shape.

**Sketch A — minimal, list-as-order (recommended):**

```yaml
---
slice: identity-migration
abstract: "One-line abstract of this slice — the parent index mirrors it verbatim"
status: active        # active | parked | done
children:             # ordered; this list IS the curated order
  - current-state
  - target-design
---
```

The `abstract` key is this slice's single-home one-liner: the PARENT's
generated body mirrors it verbatim (T3's source for a child that is
itself a slice; an index-less leaf's abstract comes from its sole
artifact's header instead). The `children` list doubles as ordering and
as the parity baseline under the child-slice predicate defined in T5: a
child-slice directory on disk absent from the list (or vice versa) is an
orphan the gate flags. No other per-child metadata here; per-child facts
stay at the child (single-home).

**Sketch B — rich child rows:**

```yaml
children:
  - slug: current-state
    kind: slice
    status: done
  - slug: target-design
    kind: slice
    status: active
---
```

Carries per-child status/kind at the parent. Rejected-leaning: duplicates
facts whose home is the child (violates single-home; every child edit
ripples to the parent frontmatter, exactly the maintenance tax the
research warned about).

**Sketch C — no frontmatter, sibling `slice.yaml`:**

State fully outside the index; INDEX.md becomes 100% generated. Cleanest
regen story, but two files where one serves, and the read-first binding
would need to name two files. Rejected-leaning.

## T2 — marker syntax + regen contract — status: resolved

`<!-- INDEX:BEGIN generated -->` / `<!-- INDEX:END generated -->` fencing
the body. The regen script rewrites only between markers, fails loudly
(exit 2) when markers are missing or duplicated, and never touches
frontmatter. Hand-edits inside the fence are lost by design; the markers
say so on their own line. Only the orchestrating session invokes regen.

## T3 — child-header mini-schema (what regen parses) — status: resolved

Generalize the existing sidecar-header precedent: every indexable artifact
opens with a YAML header carrying at minimum `abstract:` (one line,
plain-quoted). A child slice's abstract is its own INDEX.md frontmatter
`abstract`; an index-less leaf's abstract is its sole artifact's header
abstract. The mini-schema (keys, quoting rules, what counts as the sole
artifact) is versioned in the contract README, parsed by the shared lib
script only — plugins never hand-parse it. Existing EXPLORE/RESEARCH
headers already conform.

## T4 — size-cap behavior — status: resolved (option a — fail with decompose hint)

Brief: ~25KB expectation. Contested: what the regen script DOES at the cap.
Options: (a) fail with a decompose hint — the cap is a signal the slice
needs child slices, never silently truncate (recommended; matches the
cross-vendor cap semantics where overflow routes to detail files);
(b) warn and write anyway; (c) truncate abstracts progressively (rejected:
silent information loss in the navigation surface).

## T5 — dispatch-gate candidate rule (design-it-twice) — status: resolved (Sketch A)

**Sketch A — exact assignment, no scan (recommended):** the gate takes the
exact slice path the parent assigned (it already resolves one pre-dispatch)
and grades only that path. The collision escape stops being a scan radius:
on collision the PARENT assigns the sub-slice before dispatch and passes
that path. The entire ambiguity class (two candidate indexes → exit 2)
disappears because the gate never searches. Orphan parity joins as
`--check-children`: compare the graded slice's frontmatter `children` list
against on-disk CHILD-SLICE directories, both directions, exit 1 on
mismatch. **Child-slice predicate (deterministic, content-derived):** a
subdirectory counts as a child slice iff its root contains `INDEX.md` or
any reserved UPPERCASE index artifact (`EXPLORE.md`, `RESEARCH.md`,
`INTENT.md`, `PLAN.md`, `PRD.md`, `SOURCES.md`); every other
subdirectory (`design/`, `baselines/`, `scratch/`, `verification/`,
`resources/`, `claims/`, and anything else) is slice-interior under the
interior-freedom clause and exempt from parity. This keeps the two-way
check from false-orphaning sanctioned noun folders and existing layouts.

**Sketch B — retained scan, tightened:** keep root-plus-one scanning but
require the payload pointer to disambiguate when two candidates exist.
Preserves today's worker-side collision autonomy; keeps the ambiguity
failure mode alive and adds a payload-trust dependency the gate was built
to avoid. Rejected-leaning.

## T6 — seam boundaries wording — status: resolved

Knowledge `library_dir` keeps its root; inside it the same slice shape and
INDEX.md rules apply (shape unification). docpage-digest's `INDEX.md` is
renamed `SOURCES.md` (captured assumption) with resume/parity references
updated in the same wave. Interior-freedom clause: "slice-shape rules
govern where a slice sits and which names are reserved inside it; they
never govern slice-interior files beyond those reservations."

## T7 — lanes' reserved concern home — status: resolved (lanes/ reserved name)

Add `lanes/` to the reserved first-level concern names; `lanes.json` and
lane prompt files move inside it. This sanctions an in-repo, session-local
home; the durable cross-machine home remains an acknowledged open need
(out of this wave, per lanes' own SKILL.md note).

## T8 — depth-proof worktree carry — status: resolved

Replace the depth-enumerated globs with reserved-name-keyed recursive
patterns (gitignore syntax; both the native copy and worktree-create.sh's
`git ls-files --exclude-from` reimplementation honor `**`):

```text
.work/.gitignore
.work/**/INDEX.md
.work/**/EXPLORE.md
.work/**/EXPLORE-*.md
.work/**/RESEARCH.md
.work/**/RESEARCH-*.md
.work/**/INTENT.md
.work/**/INTENT-*.md
.work/**/*-checklist.md
```

This is the last recipe migration consumers ever need: new depths require
no pattern change. Baselines and raw scratch stay uncarried (machine-bound).

## T9 — read-first binding placement — status: resolved

The contract README owns one normative paragraph ("a consumer entering a
slice reads INDEX.md first; in an index-less leaf, the sole artifact is the
entry point"); bindings and artifact-protocol copies cite it rather than
restating (single-home). Agent definitions that navigate .work reference
the binding in their preloaded bodies via their existing topic-docs
pointers — no new per-agent restatement.

## Dependency order

T1 blocks T3 (header keys) and T5's `--check-children` (parity baseline).
T4 is independent. T6/T7/T8/T9 are independent of each other; all feed the
flip PR. The lib regen script (substrate PR) needs T1-T4 resolved; the
gate rework (substrate PR) needs T5.
