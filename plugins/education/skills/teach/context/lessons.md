# Lessons and Reference

The two per-concept teaching artifacts. A **lesson** delivers learning; a **reference** preserves it. Both live colocated in the concept slice per [SKILL.md](../SKILL.md) "Workspace layout".

## Lesson — the ephemeral teaching unit

`concepts/<concept>/lesson.html` — or `lesson.md`, never both, per "Lesson format — HTML-first, platform-aware" below. The primary unit of teaching: ONE tightly-scoped thing, tied to the mission, in the user's zone of proximal development, completable quickly for a tangible win.

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

Before authoring a new lesson, read the workspace `assets/` directory (if present): markdown scaffolds (prompt shells, exercise stubs) to copy and adapt, and the shared HTML assets (stylesheet, quiz component) to splice per "Assets library" below. Prefer reuse over regenerate — and when a lesson invents a piece a future lesson could reuse, extract it into `assets/`.

## Lesson format — HTML-first, platform-aware

The format decision, made once per lesson:

1. **Can the learner's host render HTML?** On headless/SSH/remote/cloud hosts with no local browser (signals: `$SSH_CONNECTION` set, Linux with neither `$DISPLAY` nor `$WAYLAND_DISPLAY`, a cloud/web sandbox), HTML is dead weight — the lesson defaults to `lesson.md`, readable in terminal and chat. The open-lesson affordance shares this host check.
2. **Host can render → default is interactive, self-contained `lesson.html`**: in-page quiz blocks (via the `assets/` quiz component), anchor links for deep-linking sections, visual/spatial *Teach* layouts, worked *Practice* examples the learner manipulates. A lesson where interactivity pays nothing (a short prose-only explainer) stays markdown — a documented exception, not the default.

**The durable trio stays markdown** — `reference.md`, learning records, and `GLOSSARY.md` are the diffable source of truth; the HTML default applies to lessons only.

An HTML lesson keeps the markdown format's spine — Teach → Practice → Go deeper, one tightly-scoped thing, inline citations, the follow-up close — with *Teach* and *Practice* carrying the interactivity: a quiz block after each Teach chunk, editable snippets whose results the learner reports back in chat. If `/frontend-design:frontend-design` is installed, delegate the visual design to it; otherwise generate a plain, self-contained single-file page inline. Constraints in either case:

- **One lesson file per concept — `lesson.md` or `lesson.html`, never both.** HTML *replaces* the markdown sibling rather than joining it, and `lesson.html` is the canonical name when the lesson is HTML. Re-rendering a concept in the other format deletes the file it supersedes, so a resumed session never has to decide which of two lessons is current. Every surface naming `lesson.md` — SKILL.md "Workspace layout", the `explain` action row, this file — means the concept's lesson file, whichever of the two extensions it carries; `reference.md` and `exercise.md` are unaffected and stay markdown.
- **`lesson.html` MUST carry `<meta name="concept" content="<raw concept name>">`.** The slug-collision guard in SKILL.md "Path resolution rules" reads the lesson's recorded raw name to decide whether an existing slug directory belongs to a different concept, and `lesson.md` carries that name in its `**Concept:**` line. An HTML lesson replaces that file, so without an equivalent marker the guard loses its only identity source and `C++` and `C#` — both normalizing to `c` — would silently share one slice. Emit the raw name unescaped-in-meaning (HTML-escape it, do not slugify it): it is the string the guard compares, not a display label.
- **Workspace HTML is workspace state, not ephemeral.** A concept's HTML *is* that concept's lesson artifact, so it lands in the concept slice beside `reference.md` — `<workspace-root>/<project-slug>/<mode>/<topic>/concepts/<concept>/`, the root resolved per SKILL.md "Workspace root resolution" — and opens from `file://`. One placement, not a choice between the workspace and OS temp. The slice is the durable unit SKILL.md "Workspace layout" defines — things that change together, together — and `resume` opens `concepts/<concept>/` to pick up a concept, so a lesson written to OS temp instead would leave that concept holding a reference and an exercise with its lesson missing. Against the marketplace topic-docs convention (`docs/conventions/topic-docs/` in the marketplace repo; non-repo consumers: <https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/topic-docs/README.md>) it is NEVER the ephemeral tier: at a plugin-data root it is the convention's machine-state tier, and at a user-chosen root it is user documents — the education plugin's documented classification deviation (see its CHANGELOG): the classification follows the slice the file is a member of, not a claim that anything re-reads it. Nothing here promises a later reader — lessons are rarely revisited, and a codebase lesson is never taught from cache. "Ephemeral" above describes a lesson **pedagogically** — rarely revisited, regenerable — never where it is stored.
- **Primer HTML is ephemeral-tier.** `primer` creates no workspace, so it has no `<mode>`/`<topic>`/`<concept>` to resolve, and its vocabulary ladder is read once and never again. Write it as **one file per run** through the platform's temp primitive, naming the temp root in the template (`mktemp -d "${TMPDIR:-/tmp}/primer-XXXXXX"` on Unix, then `primer.html` inside that directory — the `XXXXXX` placeholders must be trailing, because BSD `mktemp` on macOS substitutes only trailing Xs, so a `…-XXXXXX.html` template is not portable; naming the temp root is what reliably leaves the working directory. A user-scoped temp under `%LOCALAPPDATA%\Temp` on Windows), resolved deterministically — never branching on whether the harness injected a scratchpad path or set `CLAUDE_JOB_DIR`, and never the session scratchpad. Hand back the path and do **not** delete the file: the path is the delivery mechanism, so it must stay readable when the learner opens it.
- **Self-contained, no remote fetch.** Vendor all CSS/JS inline so the page opens straight from disk with no network dependency.
- **No secret leakage.** A codebase-mode lesson embedding a repo snippet must use synthetic data for exemplars; never bake a real secret value into the HTML — show a masked presence indicator if the existence of a secret must be conveyed.

## Assets library — spliced, never re-authored

The workspace `assets/` directory (SKILL.md "Workspace layout") holds the shared pieces every HTML lesson embeds:

- `lesson.css` — the shared stylesheet; created with the workspace's first HTML lesson.
- `quiz.js` — the quiz component (contract below); created with the first lesson carrying a quiz block.

**Splice is a MUST:** the coach authors only the lesson body; a bash splice step injects the asset files into the self-contained page. Assets never re-pass through model output after first authoring — re-emitting them per lesson burns tokens and drifts copies. To change shared look or behavior, edit the asset file once; already-written lessons pick it up only if regenerated (lessons are regenerable, rarely revisited).

Author the lesson with marker lines inside otherwise-empty tags —

```html
<style>
/* SPLICE:STYLE */
</style>
<script>
/* SPLICE:QUIZ */
</script>
```

— then assemble in place:

```bash
awk -v A="<workspace>/assets" '
  /\/\* SPLICE:STYLE \*\// { while ((getline l < (A "/lesson.css")) > 0) print l; close(A "/lesson.css"); next }
  /\/\* SPLICE:QUIZ \*\//  { while ((getline l < (A "/quiz.js"))   > 0) print l; close(A "/quiz.js");   next }
  { print }
' lesson.html > lesson.html.tmp && mv lesson.html.tmp lesson.html
```

Omit a marker (with its tag pair) when the lesson doesn't need that asset; the splice replaces only the markers present.

## Quiz component contract

`assets/quiz.js` renders multiple-choice quiz blocks with these invariants:

- **Answer shuffling.** Options are shuffled per question at render time, so the correct answer is never positionally detectable (no "always option C" tells). The equal-length answer rule ([context/exercises.md](exercises.md)) still applies — shuffling defeats *positional* detection only, and view-source can reveal the grading logic: a known limitation, not an integrity guarantee.
- **Result-return, never self-certification.** The quiz ends in a copy-out result block (concept, per-question selection, score) that the learner copies and pastes back into chat. The coach grades in conversation — probing wrong answers, confirming understanding — and records evidence in learning records. The page itself never certifies learning.

## Open-lesson affordance

After writing a lesson file (either format), offer to open it — one permission-gated command, reusing the host check from "Lesson format" above:

- **Remote/web/cloud/SSH hosts:** skip the offer entirely — opening is meaningless there; hand back the path instead.
- **macOS:** `open "<path>"`.
- **Linux with a display:** `xdg-open "<path>"` — when `xdg-open` is absent, degrade visibly: say so and hand back the path.
- **Windows (Git Bash):** `start "" "<path>"`, or `explorer.exe "<path>"`.

Offer, don't auto-open — the command runs only with the user's go-ahead.

## Artifact share (flavor)

When the session can publish Claude artifacts (the capability exists in the harness), offer to publish the lesson as a private artifact page for viewing on other devices. The workspace file stays the source of truth; the artifact is a rendering, re-published on change.

## Codebase mode

Codebase lessons re-Read live repo files at teach-time — never teach from a cached lesson (the repo is the durable artifact, self-freshening). Codebase references cite the **convention** (the dependency-direction rule, the error-handling idiom, the dispatch mechanism), never a specific instance, so they survive a refactor of the underlying files.
