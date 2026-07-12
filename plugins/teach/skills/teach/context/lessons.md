# Lessons and Reference

The two per-concept teaching artifacts. A **lesson** delivers learning; a **reference** preserves it. Both live colocated in the concept slice per [SKILL.md](../SKILL.md) "Workspace layout".

## Lesson — the ephemeral teaching unit

`concepts/<concept>/lesson.md`. The primary unit of teaching: ONE tightly-scoped thing, tied to the mission, in the user's zone of proximal development, completable quickly for a tangible win.

- **One thing only.** If it needs "and", split into two concepts. Teaching ONE thing keeps the lesson in the ZPD and the slice tight.
- **Ephemeral.** Lessons are rarely revisited — the teaching moment, not the keepsake. Low rot risk; regenerable.
- **Knowledge first, then practice.** Teach the minimum knowledge the skill needs, then drive practice via a tight feedback loop (per the Skills layer in SKILL.md).
- **Inline citations.** Link each non-obvious / load-bearing claim to its `RESOURCES.md` entry or external source — trust, a go-deeper path, AND the rot re-verify anchor. Cite claims that carry risk, not every sentence.
- **Close with a follow-up reminder.** The agent is the user's teacher — end the lesson inviting questions on anything unclear.

### Lesson file format

```markdown
# Lesson: {one tightly-scoped thing}

**Concept:** {what this teaches}  **Mission link:** {how it serves MISSION.md}

## Teach
{minimum knowledge, with inline citations to RESOURCES.md / sources}

## Practice
{tight feedback-loop task — retrieval, kata, bug-hunt, etc. per context/exercises.md}

## Go deeper
{citations + "ask me follow-ups on anything unclear"}
```

## Reference — the durable cheat-sheet

`concepts/<concept>/reference.md`. The compressed essence the user returns to: syntax cards, algorithms, sequences, formulas. Revisited — so it is the **rot-relevant** artifact.

- **Store understanding + citations, NOT frozen external facts.** A reference that freezes a library API or a current "best practice" guarantees rot. Capture the user's compressed mental model with inline citations to the authoritative source; the volatile facts stay by-reference.
- **Staleness is lazy + judgment-driven.** No freshness frontmatter. On revisit, treat as unverified and check age × domain-velocity per SKILL.md "Staleness"; re-fetch the citation if stale before teaching from it.
- **Compressed + scannable.** A reference the user must read top-to-bottom is not a reference. Tight definitions, tables, cards.

## Reuse-first scaffolds

Before authoring a new lesson shell, check the workspace `assets/` directory (if present) for existing markdown scaffolds (prompt shells, exercise stubs). Copy and adapt — prefer reuse over regenerate.

## HTML and markdown

Both lesson and reference default to `.md` — the durable teaching record (lesson, reference, learning-records) stays markdown, the diffable source of truth. Reach for HTML only where it pays: a visual/spatial *Teach* section, or an interactive *Practice* section where the learner edits a config / query / snippet and copies the result back into chat for grading. Most lessons stay markdown.

**Producing the HTML:** if `/frontend-design:frontend-design` is installed, delegate the visual design to it; otherwise generate a plain, self-contained single-file page inline. Constraints in either case:

- **Ephemeral placement.** Teach HTML is session output, not a tracked artifact. Write it to the workspace under `${CLAUDE_PLUGIN_DATA}/<project-slug>/<topic>/concepts/<concept>/` (or OS temp), and open it from `file://`.
- **Self-contained, no remote fetch.** Vendor all CSS/JS inline so the page opens straight from disk with no network dependency.
- **No secret leakage.** A codebase-mode lesson embedding a repo snippet must use synthetic data for exemplars; never bake a real secret value into the HTML — show a masked presence indicator if the existence of a secret must be conveyed.

## Codebase mode

Codebase lessons re-Read live repo files at teach-time — never teach from a cached lesson (the repo is the durable artifact, self-freshening). Codebase references cite the **convention** (the dependency-direction rule, the error-handling idiom, the dispatch mechanism), never a specific instance, so they survive a refactor of the underlying files.
