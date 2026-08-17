# /planning:interview Checklist — teach-skill-comparison

Mode: `me` (user asked "/interview me first"). Domain: **general** (comparison/discussion, no build surface yet — may graduate to engineering if the discussion yields improvement work).

## Steps

- [x] Step 1: Survey — located our teach skill (plugins/education/skills/teach/, 10 files ~794 lines), cloned mattpocock/skills (read-only, /workspace/mattpocock/skills), his teach skill is 6 files ~284 lines (SKILL.md, 4 FORMAT specs, agents/openai.yaml)
- [x] Step 1.5: Auto-detect — SKIPPED (`me` forced)
- [x] Step 2: Frontier-rounds loop — round 1 (Q1–Q5) fully resolved across three replies
- [x] Step 3: Stop condition — register gate clean (`registered=5 open=0 ... status=clean`); frontier empty; user confirmed direction piecewise across replies (final restate delivered with next-steps message)
- [x] Step 4: Persisted `shared-understanding.md` (general session — no Brief)
- [x] Step 5: Delivered; handoff = research dispatched (background), comparison doc + discussion + dogfood next; brainstorm/work-items deferred until harvest

## Decision tree (`me` mode) — resolved

- [x] End goal (Q1) — best general-purpose teach skill; two-way rationalized audit
- [x] Deliverable surface (Q2) — chat + persisted document
- [x] Dogfooding (Q3) — yes; before/after sequencing per Claude judgment; reload evidence: live-tree skill loading
- [x] Research depth (Q4) — targeted external pass, dispatched
- [x] Comparison lenses (Q5) — all
- [x] Follow-up routing — discussion → harvest list → user-gated brainstorm/work-items

## Open-question register

- Q1 | answered | round 1 | End goal | Best general-purpose teach skill for any repo/subject. Audit: (a) his ideas we haven't adopted, (b) our adoptions that could improve or align closer, each divergence RATIONALIZED against our plugin philosophy / migration playbook / standards (user-machine-repo agnosticism, extensibility via CLAUDE.md/rules/userConfig)
- Q2 | answered | round 1 | Deliverable surface | Chat discussion + persisted comparison document
- Q3 | answered | round 1 | Dogfood runs | Yes; sequencing (before/after skill changes) delegated to Claude's judgment, contingent on whether edited skills reload in-session (fact to resolve)
- Q4 | answered | round 1 | Research depth | Yes — targeted pass on Matt's published skill-design rationale
- Q5 | answered | round 1 | Comparison lenses | ALL lenses: pedagogy, state design, authoring philosophy, scope

## User stances recorded (discussion inputs, not open questions)

- Learning state: user-specific by DEFAULT (not team-shared); team sharing via Claude artifacts feature when enabled/available; repo-committed as a third convention-driven flavor — surfaces are "different flavors," convention-selectable
- Likes Matt's default: interactive HTML lesson artifact with quizzes = "a good experience... a good default" (verified real: his lessons are self-contained HTML in ./lessons/ with an ./assets/ component library; ours default to markdown, HTML only "where it pays")
- Extensibility for downstream consumers must be configurable: CLAUDE.md, agents, project rules, global user rules, or skill userConfig
- Alignment required with: docs/PLUGIN-PHILOSOPHY.md, docs/MIGRATION-PLAYBOOK.md, melodic-software/standards way of thinking

## Findings so far (pre-discussion)

- PROVENANCE DISCREPANCY: user says "we adopted it and migrated from his skill," but docs/upstream/mattpocock-skills.md lists `teach` under "Not adopted" ("education plugin covers") and the v1.2 map row 22 classifies it CONVERGENT → education:explain/quiz-me. Yet our workspace shape (MISSION.md/GLOSSARY.md/RESOURCES.md/NOTES.md/learning-records/NNNN-slug) and our context/mission|glossary|resources docs are near-verbatim his FORMAT specs. Provenance record looks wrong/stale regardless of which memory is right.
- His distinctives we lack: fluency-vs-storage strength + desirable difficulty (spacing, interleaving, retrieval as named doctrine), HTML-first beautiful lessons ("think Tufte"), ./assets/ reusable component library (shared stylesheet first), numbered lessons 0001-*.html, equal-length quiz answers rule, open-lesson-via-CLI, cwd-as-workspace, Codex agents/openai.yaml sidecar
- Our distinctives he lacks: codebase mode, primer action, per-concept slices w/ durable reference.md split, staleness/rot doctrine, assessment doctrine + ZPD floor/frontier calculation, exercises taxonomy, collision-guarded plugin-data workspace + listing script + tests, evals suite, resume/status actions, glossary re-verify rule, codebase-mode repo-sources persistence

## Session-shorthand glossary

- **dogfood run** — actually invoking our /education:teach on this repo with the user's sample prompt, as experiential evidence for the comparison
- **format specs** — Matt's four *-FORMAT.md files (MISSION, GLOSSARY, LEARNING-RECORD, RESOURCES) defining his on-disk state shapes
