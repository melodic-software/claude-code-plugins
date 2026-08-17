# /planning:interview Checklist — teach-skill-comparison

Mode: `me` (user asked "/interview me first"). Domain: **general** (comparison/discussion, no build surface yet — may graduate to engineering if the discussion yields improvement work).

## Steps

- [x] Step 1: Survey — located our teach skill (plugins/education/skills/teach/, 10 files ~794 lines), cloned mattpocock/skills (read-only, /workspace/mattpocock/skills), his teach skill is 6 files ~284 lines (SKILL.md, 4 FORMAT specs, agents/openai.yaml)
- [ ] Step 1.5: Auto-detect — SKIPPED (`me` forced)
- [ ] Step 2: Frontier-rounds loop
- [ ] Step 3: Stop condition + register gate + confirmation
- [ ] Step 4: Persist shared-understanding summary (general session — no Brief unless it graduates to engineering)
- [ ] Step 5: Deliver + optional handoff (brainstorm/work-items if improvements harvested)

## Open-question register

- Q1 | answered | round 1 | End goal | Best general-purpose teach skill for any repo/subject. Audit: (a) his ideas we haven't adopted, (b) our adoptions that could improve or align closer, each divergence RATIONALIZED against our plugin philosophy / migration playbook / standards (user-machine-repo agnosticism, extensibility via CLAUDE.md/rules/userConfig)
- Q2 | open | round 1 | Deliverable surface: chat discussion vs written comparison artifact? | (user's "just in the chat" remark was about the TEACH skill's learner outputs, not this deliverable — still open)
- Q3 | open | round 1 | Dogfood runs: run ours live with the sample prompt; simulate Matt's for symmetry? | (mid-turn msg endorses dogfooding ours; symmetry unconfirmed)
- Q4 | open | round 1 | Research depth: files only, or also Matt's published writing on skill design? | (internal reading expanded per user: PLUGIN-PHILOSOPHY, MIGRATION-PLAYBOOK, standards — done; external rationale research unconfirmed)
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

## Decision tree (`me` mode)

- [ ] End goal / disposition of findings (Q1)
- [ ] Deliverable surface (Q2)
- [ ] Dogfooding scope + symmetry (Q3)
- [ ] Research depth (Q4)
- [ ] Comparison lenses / priority axes (Q5)
- [ ] (blocked by Q1) Follow-up routing: brainstorm → work items → implement, if harvesting

## Session-shorthand glossary

- **dogfood run** — actually invoking our /education:teach on this repo with the user's sample prompt, as experiential evidence for the comparison
- **format specs** — Matt's four *-FORMAT.md files (MISSION, GLOSSARY, LEARNING-RECORD, RESOURCES) defining his on-disk state shapes
