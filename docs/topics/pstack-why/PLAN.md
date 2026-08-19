# pstack-why — `/discovery:trace-intent`

Lane 1 of the cursor/plugins pstack port. Upstream: `pstack/skills/why/SKILL.md` (MIT), clone
pinned at `60c641e4fad674784b30abcf9f8915dea39df38d`.

## Brief

### TLDR

Add `/discovery:trace-intent` — a fourth `discovery` skill that reconstructs **why a thing was
built the way it was**, from evidence that lives outside the repository, and reports what it could
not find as a first-class result. Reauthored from the upstream `why` skill, not forked.

### Goal

Close the one gap in this plugin's own framing. `explore` answers *what IS*, `research` answers
*what SHOULD BE*; nothing answers *what WAS, and why*. Every investigation skill in the fleet
returns state — what exists, what drifted, what will break. None returns reconstructed intent.

Success is a cited, confidence-calibrated account of the forces that produced a design, in which a
gap is reported rather than papered over with a plausible story.

### Constraints

1. **Evidence substrate is outside the repo.** This is the boundary against `explore`, whose
   dimension 2 already owns git history — *"who changed it, when, why"* — with a dedicated `git`
   mode. `trace-intent` takes tickets, review discussion, long-form design docs, and (where wired)
   incident and telemetry records. It delegates repo-local git archaeology to `/discovery:explore
   git` rather than reimplementing `git log` / `git blame`, and inherits explore's
   do-not-archaeologize-unprompted guard.

2. **Intent-confidence is its own axis.** Five tiers — Direct / Supported / Inferred / Speculative /
   Unknown — measuring inferential distance from intent. It is NOT research's Tier 0-3
   source-authority ladder, and reusing that ladder is a defect: `artifact-shape.md:149-157` says
   pointing a non-external run at the research header "launders 'I grepped a filename' into the same
   field a fetched primary source would occupy", which is why `explore` has its own
   `verified: read | grep | inferred`. Two further reasons: `discipline.md:222` accepts only
   HIGH-confidence claims and makes MEDIUM/LOW a Gap, which would outlaw this skill's own hedged
   deliverable; and Tier 3 is a promotable rung, which would soften an absolute exclusion into
   weak-but-admissible. The tier doubles as the output-section router.

3. **Code shape is never intent evidence.** It leaves the ladder entirely — recorded as a Gap, never
   as a low rung. "Handles the null case because it checks for null" is mechanics, not motivation.

4. **Three live evidence categories, none guaranteed.** Source control, long-form docs, issue
   tracker — each presence-gated, because every `discovery` skill guards its git precompute
   (`2>/dev/null || echo "unknown"`) and `topic-docs/README.md:415` states the no-project-root path
   "is not a rare path". Beyond those three, a documented provider-adapter extension seam. The four
   upstream categories with no representation in this marketplace (team chat, infra observability,
   error tracking, product analytics) are not shipped as permanent constant-gap investigators.

5. **Provider-neutral by review discipline, not by gate.** The tracker and forge token classes in
   `scripts/skill-portability-tokens.txt:137,154` are commented out pending issue #416, so a green
   `check-skill-portability.sh` run is NOT evidence of neutrality. Category names are surface
   classes; vendors appear only as illustrative examples. Upstream's vendor-named playbooks
   (`linear.md`, `notion.md`, `datadog.md`, `sentry.md`, `slack.md`, `databricks.md`) invert to
   category-named files.

6. **The tracker seam is invoked, never imported.** `PLUGIN-PHILOSOPHY.md:22` forbids importing a
   sibling plugin's files; `grep -rln "work-item-tracker.sh" plugins/` returns only `work-items/**`.
   Use a namespaced skill invocation with gate-plus-fallback — precedent
   `code-tidying:batch-simplify/SKILL.md:176`.

7. **One purpose-built agent, not a seven-way fan-out.** `explore` runs six dimensions inside one
   `discovery:explorer`; `research` runs its phases inside one `discovery:researcher` — both behind
   a preload-liveness sentinel and a parent-side acceptance gate
   (`discovery/scripts/check-dispatch-artifact.sh`). Follow that architecture.

8. **Fresh-eyes declaration required.** Confidence-calibrated synthesis is the self-grade class
   `PLUGIN-PHILOSOPHY.md:657` names verbatim ("a synthesis step grading its own lock"). Siblings
   answer it by dispatching a verifier and returning `verification: pending`. Check 21 WARNs
   without a Form-1 declaration in the skill's own files.

9. **The findings artifact is private, not a public lifecycle kind.** Registering a third artifact
   in `docs/PLUGIN-ARTIFACT-PROTOCOL.md` triggers byte-identical copies across five plugins plus a
   protocol version bump, for an artifact with no downstream consumer today. Declare it explicitly
   private so it is not mistaken for sanctioned scratch. Return a bounded summary plus a pointer —
   never full inline synthesis, which inverts the stated purpose of both siblings.

10. **The edit to `discipline:reason-dont-recite` is additive only.** It carries the literal quoted
    trigger `'why is it this way'`. Removing or rephrasing it hard-FAILs `skill-quality` check 3 —
    the trigger-MOVE carve-out iterates same-plugin siblings only (`check-skill.sh:377`), so a
    cross-plugin move reads as a dropped trigger. Append a disambiguating clause; change nothing
    existing. A clause that merely narrows its own trigger surface needs no gate; one that *routes*
    to `trace-intent` is a cross-plugin reference and takes the guarded gate-plus-fallback form.

11. **Do not pre-register the leaf name.** `check-skill-leaf-names.sh:186` FAILs a registered leaf
    carried by fewer than two plugins. `trace-intent` is unique; no registry entry.

### Acceptance criteria

Binary, checkable.

1. `plugins/discovery/skills/trace-intent/SKILL.md` exists, declares no frontmatter `name`, carries
   `metadata.workflow-stage` from the `scripts/cheatsheet-config.mjs` enum and a
   `metadata.summary` of <= 100 codepoints.
2. Its `description` carries single-quoted `Use when:` trigger phrases and a `Skip when:` clause
   naming `/discipline:reason-dont-recite` and `/discovery:explore`.
3. The five intent-confidence tiers appear with a stated mapping to output sections, and the skill
   states that code-shape inference is recorded as a Gap rather than placed on the ladder.
4. A Sources Consulted coverage map is specified, one line per category including those that
   returned nothing, in the form
   `- <category>: <what was searched>. <found | no relevant results | skipped, reason>.`
5. Exactly two skip reasons are permitted, and "probably irrelevant" is explicitly rejected.
6. No vendor name appears as a category identifier; any vendor named is an illustrative example.
7. `plugins/discovery/skills/trace-intent/evals/evals.json` exists, validates against
   `plugins/skill-quality/reference/evals.schema.json`, and covers trigger/routing, happy path,
   one refusal/guardrail, and one anti-pattern.
8. A Form-1 fresh-eyes declaration is present in the skill's own files.
9. `plugins/discipline/skills/reason-dont-recite/SKILL.md` retains every existing single-quoted
   trigger verbatim; the only change is an appended clause.
10. `docs/upstream/cursor-pstack.md` exists in the shape of `docs/upstream/mattpocock-skills.md`.
11. Both `discovery` and `discipline` carry manifest version bumps with matching CHANGELOG entries.
12. `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md` regenerated, not hand-edited.
13. These pass: `scripts/check-changed-skills.sh origin/main`, `scripts/validate-plugins.sh`,
    `scripts/check-changelog-parity.sh --check-bump origin/main`,
    `scripts/check-skill-leaf-names.sh --check`, `scripts/check-skill-portability.sh origin/main`.

### Captured assumptions

- **A1.** Users will reach this with phrasings like "why was this built this way", "what were they
  thinking", "design rationale", "why did we pick X over Y". Untested against real usage; the evals
  are where it gets checked.
- **A2.** The four unshipped categories are worth an extension seam rather than omission. If nobody
  ever wires an adapter, the seam is dead weight and should be removed at the next audit.
- **A3.** The private-artifact call assumes no near-term consumer. If the `teach` lane or `planning`
  later needs to read it, that decision reopens and pays the five-plugin protocol cost then.

### Out of scope

- A `how` skill. Upstream pairs `why` with `how` for runtime mechanism; we have no equivalent and
  are not building one in this lane.
- Application-telemetry integration of any kind. `claude-ops:observability` reads Claude Code's own
  telemetry and is not a substrate for this.
- Retrofitting the intent-confidence axis onto any existing skill.
- Activating the staged tracker/forge portability token classes (issue #416).

### Deferred questions

- **Q12** — should the four unshipped categories ship as documented adapter *stubs* or as prose
  describing the seam only? Arbiter: `/planning:plan`. Turns on whether a stub is discoverable
  enough to be useful without being dead code.
- **Q13** — `metadata.workflow-stage` value. No stage in the enum cleanly fits historical
  archaeology; `explore`, `research`, and `anytime` are all defensible. Arbiter: `/planning:plan`,
  after reading how the sibling discovery skills are staged.

## Plan

*Not yet written. `/planning:plan` fills this section.*
