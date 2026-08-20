# pstack-blast-radius — `/review:quality-gate downstream`

Lane 2 of the cursor/plugins pstack port. Upstream: `pstack/skills/blast-radius/SKILL.md` (MIT),
clone pinned at `60c641e4`.

## Brief

### TLDR

Add a `downstream` mode to `review:quality-gate` that looks for what a change breaks **outside its
own diff**. Ship the scope; drop most of upstream's mechanics, which this marketplace already owns.

### Goal

Close one genuine hole: the entire review lane is diff-scoped and nothing in it looks outward.
Verified by reading, not assumed — `architecture-guardian.md:22` stops at mapping which layer each
*changed* file belongs to and never enumerates consumers of a changed contract; `code-reviewer.md`
and `doc-drift-detector.md` carry no caller/ripple/downstream item at all; `review:fanout` fans
across surfaces all diffing the same merge-base; `verification:confirm` Stage 2 matches
requirements↔implementation, which is inward; `mutation-testing:audit` is `git diff`-scoped by
construction. `planning:devils-advocate` Round 3 does have a literal "Blast radius: What else is
affected" step, but its own guard says it "reviews plans, not code" and it runs pre-implementation.

The only statement of the move anywhere in the fleet is one bullet in an on-demand playbook chapter
(`playbooks/fable-5/context/verification.md`, adversarial self-review: *"Walk every caller of the
thing you changed that you did not modify, because contract changes break at the call sites you were
not looking at"*) — doctrine loaded on demand, not a review surface with a findings artifact.

### Constraints

1. **Report-only, and execution is a named handoff.** `quality-gate/SKILL.md:117-118` states it does
   not run builds or tests and does not write code. That caps this mode below upstream's top two
   proof rungs, and the resolution is to route rather than to smuggle: the deliverable "the cheapest
   test that would catch this" hands off to `/testing:write` and `/mutation-testing:audit`. That is
   *stronger* than upstream, because mutation-testing re-runs the mutant — the agent that wrote the
   test cannot grade itself into a pass.

2. **No new evidence vocabulary. Do not touch `severity.md`.** Findings carry the existing severity
   and confidence axes unchanged. `plugins/review/context/severity.md` §Vocabulary explicitly closes
   the term: *"In this plugin, 'axis' means one of the two above — severity or confidence… Three
   incompatible senses of 'axis' were live across this plugin's docs before this note."* The plugin
   already faced this exact question and answered it the other way — `context/spec.md:27-31` adds a
   finding-class dimension and says *"Deliberately not 'axis': in this plugin that word is reserved
   for severity and confidence."* A third axis would also be a cross-plugin convention change:
   `PLUGIN-PHILOSOPHY.md:496` names that file the fleet owner, `docs/conventions/detector-findings/`
   builds "the four producer-owned fields" on it, and `check-detector-findings-crosswalk.sh` gates it.

3. **The unverified-claim floor is cited, not reinvented.** A claim resting on an unrun check states
   *"assessed, not verified because Y"*, citing `playbooks/fable-5/context/verification.md:96` as
   owner. Eight evidence ladders already exist in this fleet; a ninth would be exactly the defect
   `discipline:reuse-or-replace` names — *"leaving the established way in place and quietly adding a
   divergent way alongside it."* The port's own charter argues against the bottom rung anyway: *"A
   rung that is cheapest to fill when the evidence is worst is a rung that will be filled."*

4. **An unverified safety fact cannot clear a concern.** It lands in the confirmed-risk table, never
   the cleared table. This is the enforcement the upstream motto needs and the first draft lacked.

5. **The single-fact move is a probe, not the report's structure.** Ask it first — "is there one fact
   this rests on? then go verify that one thing" — but enumerate risks regardless, and annotate which
   collapsed. As a *spine* it structurally excludes secondary risks on any change with several
   independent ones, and this marketplace models change risk as multi-dimensional:
   `autonomy/reference/guardrails/work-classes.md:9` names four risk properties, and
   `devils-advocate` Round 4 sweeps ten operational categories precisely *because* assumption-driven
   rounds miss traps.

6. **Carry the "blast radius" trigger phrases; name the mode `downstream`.**
   `MIGRATION-PLAYBOOK.md:47-50` — trigger phrases are behavior, not marketing copy. Suppressing the
   noun cedes it to `planning:plan`, which advertises "blast-radius assessment" in its always-loaded
   description. `impact` was rejected as generic: it is already prose-loaded in four always-listed
   descriptions and the nearest neighbour, `docs-hygiene:rename-references audit blast`, is itself
   described as "impact analysis".

7. **Negative routing stated in three directions** — `/planning:plan` and
   `/planning:devils-advocate` (pre-implementation, on a plan), and
   `/docs-hygiene:rename-references audit blast` (rename-scoped and mechanical).

8. **No `arena` reference.** No such skill exists here (verified: `ls -d plugins/*/skills/arena` is
   empty; the only textual hits are "arena rock" in a genre taxonomy). Rungs 4-5 route to installed
   siblings instead, presence-gated per `docs/conventions/seam-phrasing/`.

### Acceptance criteria

1. `plugins/review/skills/quality-gate/context/downstream.md` exists and states the outward-looking
   procedure, the cleared-vs-confirmed split, and the test handoff.
2. `quality-gate`'s `description` gains `downstream` in its mode list **and** carries quoted
   blast-radius trigger phrases; every pre-existing quoted trigger survives byte-identically.
3. The Step 0 routing table and `argument-hint` both carry `downstream`.
4. `plugins/review/context/severity.md` is **unchanged** — `git diff --quiet` on it.
5. No new tier/rung/ladder vocabulary anywhere in the mode file; the unverified floor cites
   `fable-5/context/verification.md` rather than restating it.
6. The mode file states that an unverified safety fact cannot appear in the cleared list.
7. Negative routing against all three incumbents appears in the mode file.
8. `plugins/review/evals/evals.json` (or the skill's evals) gains a routing case for `downstream`.
9. `plugins/review/README.md`'s prose mode list includes it.
10. `review` manifest version bumped with a matching CHANGELOG entry.
11. `docs/upstream/cursor-pstack.md` gains the lane-2 row **and** records the rejected mechanics in
    "Not adopted": the proof ladder, the one-fact spine as spine, and the `arena` routing.
12. Gates pass: `check-changed-skills`, `validate-plugins`, all four `check-changelog-parity` modes,
    `check-skill-leaf-names`, `check-skill-portability`.

### Captured assumptions

- **A1.** The beyond-the-diff hole is real and worth a mode. Both validators agreed the *scope*
  survives even though the *mechanics* do not; validator B stated OMIT would also be defensible if
  the maintainer disagrees that the hole matters. The user chose to ship.
- **A2.** `downstream` reads better than `consumers` to someone scanning the mode list. Untested.

### Out of scope

- Any edit to `plugins/review/context/severity.md`.
- Any new confidence, proof, or evidence vocabulary.
- A standalone `verification:impact` skill.
- Fixing `quality-gate`'s description over-claim (*"delegates to the matching reviewer"* is already
  false against its own mode list, since `criteria` dispatches nothing) — noted, not this lane's job.

## Plan

Small change: one new context file plus registration edits. No phases warranted beyond the sequence
below; blast radius LOW (one plugin, additive, no shared-convention file touched).

1. Write `context/downstream.md`.
2. Register: `description`, `argument-hint`, Step 0 routing table, Step 0.5 pre-flight.
3. `README.md` prose list, evals routing case, version bump, CHANGELOG.
4. Provenance row + "Not adopted" entries.
5. Gate sweep, commit, push.

**Sanity Check:**

- `git diff --quiet origin/main -- plugins/review/context/severity.md` exits 0 (constraint 2 held)
- `grep -ciE 'rung|ladder|proof.level' plugins/review/skills/quality-gate/context/downstream.md`
  returns 0 (constraint 3 held)
- `grep -c 'blast radius' plugins/review/skills/quality-gate/SKILL.md` returns >= 1 (constraint 6)
- `scripts/check-changed-skills.sh origin/main` exits 0 with all pre-existing triggers preserved
