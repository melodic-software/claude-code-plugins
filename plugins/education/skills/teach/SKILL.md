---
name: teach
description: "Interactive multi-session learning coach for general topics or repo-grounded concepts; also a single-session domain primer (primer action). Use when: 'teach me', 'study session', 'help me learn', 'onboard me to', 'learn this codebase'. Coaches through the Knowledge-Skills-Wisdom progression with persistent per-topic learning state. Not for one-off inline questions (answer directly)."
argument-hint: "<action> [args] (e.g., /education:teach topic rust-ownership, /education:teach codebase auth-flow, /education:teach primer color-grading)"
user-invocable: true
disable-model-invocation: true
shell: bash
metadata:
  workflow-stage: anytime
  summary: Multi-session learning coach for general topics or repo-grounded concepts
---

## Purpose

Teach a user interactively across multiple sessions — not by lecturing, but by coaching through the Knowledge-Skills-Wisdom progression grounded in the user's real goals. Maintains persistent learning state so each session builds on prior understanding.

**Use when:** user asks to learn across sessions (`teach me`, `study session`, `help me learn`, `onboard me to`). **Skip when:** one-off inline question (answer directly); task-context codebase investigation (use the project's own code-exploration tooling); extracting book knowledge to a reference file (`/knowledge:book-distill` when installed).

Two modes share pedagogy but differ in source material:

- **`topic`** — general subject learning. Resources come from external high-trust sources (books, courses, docs, communities).
- **`codebase`** — repo-grounded learning. Resources come from the consuming repo's own code, docs, ADRs, conventions, discovered at teach-time (see "Codebase mode").

**Workspace layout** (where persistent learning state lives): see "Workspace layout" below — the single source of truth every action resolves paths against. Informed by ZPD/K-S-W pedagogy research.

## Workspace layout

All persistent learning state lives under the plugin's own per-plugin data directory, which survives plugin updates and does not pollute the consuming repo:

```text
${CLAUDE_PLUGIN_DATA}/<project-slug>/<mode>/<topic>/
├── MISSION.md               WHY the user is learning this — goal, success criteria, constraints (workspace-global)
├── GLOSSARY.md              durable terminology SSOT — add only when the user demonstrates understanding (global)
├── RESOURCES.md             curated high-trust sources (knowledge + wisdom communities) (global)
├── NOTES.md                 teaching preferences + working notes — how the user wants to be taught (global)
├── learning-records/        cross-cutting ZPD log — ADR-style insight records (append-only)
│   ├── 0001-<slug>.md
│   └── 0002-<slug>.md
└── concepts/                per-concept slices
    └── <concept-slug>/      ONE tightly-scoped thing — things that change together, together
        ├── lesson.md        the teaching unit — pedagogically ephemeral (rarely revisited, regenerable), NOT the topic-docs ephemeral tier; `lesson.html` instead when rendered as HTML, never both
        ├── reference.md     durable compressed cheat-sheet (revisited; the rot-relevant artifact)
        └── exercise.md      colocated practice (optional)
```

Path resolution rules every action MUST follow:

- **`<project-slug>`** — **canonicalize the project path FIRST**, then derive BOTH the basename-slug and the hash from that one canonical path, so a project opened via a symlink and via its real path map to the same workspace (otherwise the alias basename would still split it — `alias-<hash>` vs `realname-<hash>`). Canonical path: `realpath "${CLAUDE_PROJECT_DIR}" 2>/dev/null || readlink -f "${CLAUDE_PROJECT_DIR}" 2>/dev/null || printf '%s' "${CLAUDE_PROJECT_DIR}"` (e.g. macOS repos under `/private/var/…`). Then `<project-slug>` = the **basename of the canonical path** slugified to lowercase alphanumerics and hyphens, then `-` plus the first 8 hex chars of `printf '%s' "<canonical-path>" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8` (the fallback covers stock macOS). The hash discriminator is required because the basename alone collides when two clones or worktrees share a directory name. Both `topic` and `codebase` workspaces are scoped under `<project-slug>` — topic learning becomes associated with the project you launched from.
- **`<mode>`** — literally `topic` or `codebase`, matching the action that created the workspace. This level keeps the two modes independent: `/education:teach topic auth-flow` and `/education:teach codebase auth-flow` in the same project resolve to separate workspaces (`.../topic/auth-flow/` vs `.../codebase/auth-flow/`) instead of one seeding over the other's `MISSION.md` / `RESOURCES.md`.
- **`<topic>`** and **`<concept>`** — content-named kebab slugs (lowercase alphanumerics and hyphens only; strip `/`, `\`, `..`), NOT sequence-numbered. `"Domain-Driven Design"` → `domain-driven-design`; `"Rust Ownership"` → `rust-ownership`. **Record the exact raw subject/concept name** (`MISSION.md`'s `# Mission: {Topic}` title for a topic; the lesson's `**Concept:**` line for a concept) so it is the source of truth for collision checks. **Guard against slug collisions** — distinct subjects can normalize to the same slug (`C++` and `C#` → `c`; `Node.js` and `Node JS` → `node-js`), which would silently share one workspace. Before creating a workspace whose slug directory already exists, read that existing workspace's recorded raw name; if it names a DIFFERENT subject, append `-` plus the first 4 hex chars of `printf '%s' '<raw-name>' | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-4` to the new slug, keeping per-subject state isolated while leaving non-colliding slugs readable.
- **`learning-records/NNNN-<slug>.md`** keeps `NNNN-` numbering (sanctioned ADR-style append-only log). Scan the directory for the highest existing `NNNN` and increment.
- `${CLAUDE_PLUGIN_DATA}` is created automatically the first time it is referenced and persists across plugin updates, so workspaces survive between sessions.

`lesson` / `reference` / `exercise` default to `.md` — the durable teaching record stays markdown, the diffable source of truth. A lesson may be `lesson.html` instead where it pays, replacing `lesson.md` rather than joining it (one lesson file per concept, never both); it is a member of the concept slice either way, and only the workspace-less `primer` renders to a temp path. Placement, the replacement rule, and constraints: "Lessons and Reference".

## Pre-computed Context

Existing workspaces (current project only): !`p="$(realpath "${CLAUDE_PROJECT_DIR}" 2>/dev/null || readlink -f "${CLAUDE_PROJECT_DIR}" 2>/dev/null || printf '%s' "${CLAUDE_PROJECT_DIR}")"; b="$(basename "$p" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"; h="$(printf '%s' "$p" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"; ls -d "${CLAUDE_PLUGIN_DATA}/$b-$h"/*/*/ 2>/dev/null | head -20 || echo "none"`

## Action Router

Parse `$ARGUMENTS`: first token = action, remainder = args. If empty or ambiguous, detect from conversation.

| Action | Purpose | Detail |
|--------|---------|--------|
| `topic <subject>` | Start or resume learning a general subject | Creates workspace, runs mission interview if new |
| `codebase <concept>` | Learn a concept grounded in the consuming repo's code | Creates workspace, grounds in actual discovered files |
| `mission` | Review or update learning mission | [context/mission.md](context/mission.md) |
| `glossary` | Review or update compressed terminology | [context/glossary.md](context/glossary.md) |
| `resources` | Manage curated learning sources | [context/resources.md](context/resources.md) |
| `explain <concept>` | Teach one tightly-scoped thing (a lesson) | Writes `concepts/<concept>/lesson.md` — or `lesson.html`, never both — pedagogically ephemeral but durable machine state on disk; distill a durable `reference.md` alongside — see [context/lessons.md](context/lessons.md) |
| `primer <domain>` | Single-session domain primer — NO workspace | See "Primer action" below |
| `exercise` | Colocated practice for a concept | Writes `concepts/<concept>/exercise.md`; design per [context/exercises.md](context/exercises.md) |
| `assess` | Check understanding, update learning records | [context/assessment.md](context/assessment.md) |
| `resume` | Resume a workspace from prior session | Reads workspace state, picks up where left off |
| `status` | Show learning progress across all workspaces | Lists workspaces + latest learning records |

**Smart default:** if the user provides a subject without an action, detect mode:

- Subject names a concept in the consuming repo (a module, a framework the repo uses, an internal library or abstraction the repo defines) → `codebase`
- Otherwise → `topic`

## Primer action

`primer <domain>` is the single-session middle tier between an inline answer and a full `topic` workspace: the user needs enough of an unfamiliar domain's vocabulary and quality criteria to prompt well NOW ("teach me color grading so I can direct the work"), not a multi-session curriculum. Purpose: turn a vague request into a precise spec by teaching what the terms of art are and what GOOD looks like.

- **No workspace** — no `<topic>` directory, mission interview, glossary, or learning records. Output is the session conversation plus an optional self-contained HTML vocabulary ladder (vague term → precise spec, with copy-out) per "Lessons and Reference" HTML routing.
- **Shape** — intake the user's starting point (one question), then build the vocabulary ladder: core terms, the quality axes experts judge by, worked good-vs-bad examples, and a closing "how to ask for what you want" prompt template.
- **Ground per Knowledge layer** — primary sources this turn, never parametric recall.
- **Escalate** — if the user wants depth or practice, offer `/education:teach topic <domain>` (full workspace).

## Resume, Status, and workspace resolution

`resume` and `status` operate over the workspaces under `${CLAUDE_PLUGIN_DATA}/<project-slug>/<mode>/<topic>/` (both modes):

- **`resume [<topic>]`** — with a topic argument, resolve that workspace directly (disambiguating by `<mode>` if the same topic exists in both) and follow "Resume (subsequent sessions)". With no argument, list the workspaces sorted by most-recently-modified (git or filesystem mtime of the workspace files) and ask the user which to resume — never silently pick one when more than one exists.
- **`status`** — for each workspace, show its mode, topic, the count of `learning-records/`, the current frontier concept (from the latest records), and the last-touched date (mtime). One line per workspace; no file bodies loaded.
- **`explain <concept>` / `exercise` need an active workspace.** They write into `concepts/<concept>/` under a topic workspace. If exactly one workspace exists, use it; if several exist, ask which; if none exists, ask whether to start one (`topic` / `codebase`) before writing — never invent a workspace silently.

## Pedagogy — Three Layers

Every teaching session progresses through Knowledge → Skills → Wisdom. Don't skip layers; don't rush. Each layer has different teaching moves. The knowledge/skills balance varies by topic — theory-heavy subjects (theoretical physics) lean knowledge; practice-heavy ones (yoga, a framework) lean skills. Calibrate lesson design to the topic.

### Knowledge (declarative — what is it?)

- Provide clear explanations with examples and counterexamples
- Ground in primary sources — never parametric recall. A claim that drives a lesson is verified against a source fetched or a file Read THIS turn, not recalled from training data
- For `topic` mode: fetch from `RESOURCES.md` entries, the project's research tooling if available, or documentation-lookup MCP servers / official docs
- For `codebase` mode: Read actual source files, ADRs, convention docs, tests discovered per "Codebase mode"
- Use retrieval practice: ask the user to restate in their own words
- Add to `GLOSSARY.md` only when the user demonstrates understanding

### Skills (procedural — how to do it?)

- Emphasize deliberate practice: small tasks focused on 1-2 skills at a time
- Couple explanation with application: explain → simple use → novel use → integrated use
- For `codebase` mode: exercises use actual repo patterns (write a handler, add a test, implement the repo's own domain primitive)
- Use error-driven learning: present buggy code, ask the user to diagnose
- Tight feedback loops — immediate feedback on each attempt

### Wisdom (judgment — when and why?)

- Ask about tradeoffs: "You chose X; what are the pros/cons vs Y?"
- Present multiple solutions, ask the user to choose and justify
- Connect to mission: "How does this apply to what you're building?"
- Prompt transfer: "Where else could this pattern apply?"
- Metacognitive reflection: "What tripped you up? What pattern did you learn?"
- For `codebase` mode: connect to the repo's ADRs, architecture decisions, design philosophy
- **Delegate to community.** Wisdom comes from real-world interaction outside the learning environment — something an AI tutor structurally cannot provide. When a question requires wisdom, attempt to answer but also find relevant communities (subreddits, Discord servers, local meetups, courses, open-source projects) where the user can test skills in practice. Record community preferences in `RESOURCES.md`. Respect opt-outs — if the user declines community participation, don't re-suggest

## Lessons and Reference

The unit of teaching is a **lesson** — one tightly-scoped thing tied to the mission, completable quickly for a tangible win, in the user's zone of proximal development. Lessons are ephemeral in the **pedagogical** sense only — rarely revisited and regenerable — never in the topic-docs sense: a lesson is a member of its concept slice and stays in machine state. Alongside, distill the durable **reference** — the compressed cheat-sheet the user returns to. Authoring format, reuse-first scaffolds, HTML placement, inline citations: [context/lessons.md](context/lessons.md).

## Zone of Proximal Development

Teach just beyond current understanding — challenging but achievable. Scaffold and fade:

1. **Check current level** — read learning records, ask what they already know
2. **Calibrate difficulty** — not too easy (bored), not too hard (frustrated)
3. **Scaffold levels** (fade as competence grows):
   - Orientation — restate in simpler terms, break into sub-steps
   - Heuristic hints — guiding questions ("What data structure gives O(1) lookup?")
   - Pointing hints — highlight relevant concept or code section
   - Partial solution — show snippet with blanks
   - Full solution + explanation — last resort, always ask the user to explain back
4. **Track and adapt** — update learning records when understanding demonstrated

## Teaching Dialog

Coach through a depth-first, one-question-at-a-time dialog:

- Ask ONE question at a time
- Wait for the answer (silence = wait, not assume)
- Restate what's understood + what's still open
- Apply the relevant teaching move to the answer
- Surface the next choice point

**Coach posture, not lecturer posture.** Questions before answers. "What do you think happens here?" before explaining what happens. The user's understanding is the goal, not coverage.

## Session Flow

### New Workspace (first invocation)

1. Create the workspace per "Workspace layout"
2. Run the mission interview — WHY are they learning this? What's the concrete goal? What does success look like?
3. Write `MISSION.md` with the answers
4. Seed `RESOURCES.md` — for `topic` mode, find high-trust sources; for `codebase` mode, discover and list relevant repo files/docs per "Codebase mode"
5. Assess the starting point — what do they already know? Record as `learning-records/0001-prior-knowledge.md`
6. Begin teaching from their zone of proximal development

### Resume (subsequent sessions)

1. Read `MISSION.md` — know WHY and the success criteria
2. Read `GLOSSARY.md` — know what terms are established
3. Read `NOTES.md` — recall teaching preferences
4. Scan `learning-records/` for the latest entries — know the current frontier
5. Pick the next concept from the zone of proximal development; open its `concepts/<concept>/` slice
6. Before re-teaching an existing concept, run the Staleness check (see "Staleness")

### Session Close

- Summarize what was learned
- Prompt reflection: "What's the key takeaway? What was hardest?"
- Update `GLOSSARY.md` if new terms demonstrated
- Write a learning record for demonstrated understanding
- Suggest the next session's focus

## Codebase Mode

`codebase` mode grounds learning in the consuming repo, discovered at teach-time — never in baked assumptions about any particular project's layout. Discover the repo, then teach from what you find:

1. **Read the repo's own guidance.** Climb from `${CLAUDE_PROJECT_DIR}` for the nearest `CLAUDE.md` / `AGENTS.md`; read `README.md`; look for `docs/`, architecture-decision records (commonly `docs/adr/`, `docs/decisions/`), and convention/rules files (`.claude/rules/`, `.cursor/rules/`, a `CONTRIBUTING` file). These state how the project intends its code to be understood.
2. **Survey the structure.** Inspect the top-level layout (`src/`, `apps/`, `libs/`, `packages/`, tests) and identify languages/frameworks from manifest files present (`package.json`, `*.csproj`/`*.sln`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, …). Locate the files that actually embody the concept the user wants to learn.
3. **Persist what you discover.** Record the located files/docs into the workspace `RESOURCES.md` "Repo Sources" so later sessions don't re-derive the structure — infer once, persist, reuse. If discovery cannot find a grounding for the concept, ask the user to point you at the relevant area rather than guessing.
4. **Ground EVERYTHING in files Read this turn (Tier 0).** Never teach a codebase lesson from a cached lesson — re-Read the live files; the repo is the durable artifact, self-freshening.
5. **Cite the convention, not the instance.** Durable codebase references capture the pattern (dependency direction, an error-handling idiom, a dispatch mechanism), not a specific file's current contents — so they survive a refactor.

Use the repo's actual code as examples. Create exercises against real patterns. Connect to the repo's ADRs for "why it's done this way."

## Staleness

Learning artifacts persist for months; durable teaching content (references, glossary) can rot. Handle rot by **lazy verify-on-revisit**, not stored metadata:

- **No freshness frontmatter.** Don't record a `verified:` date (git owns it) or a `volatility:` tag (frozen judgment that itself rots).
- **Staleness = age × velocity judgment.** At revisit, weigh the artifact's age against the domain's velocity — fast (library APIs, framework syntax, AI tooling) vs slow (math, music theory, established architecture). Use domain-velocity intuition to decide *whether* to re-verify, never *what* the current fact is.
- **Treat durable artifacts as unverified on revisit.** A reference/glossary entry from a prior session is unverified synthesis until re-grounded this turn. If stale relative to age × velocity, re-fetch the inline citation, update, THEN teach.
- **Durable references store understanding + citations, not frozen facts.** A reference that freezes an external fact guarantees rot; instead capture the user's compressed mental model with inline citations to the authoritative source, so volatile facts stay by-reference (the citation is the re-verify target).

## What This Skill Does NOT Do

- **Does not write production code** — teaches understanding, not implementation. Use the project's own implementation workflow for code changes
- **Does not replace `/knowledge:book-distill`** — that extracts book knowledge into skill reference files; `/education:teach` delivers knowledge interactively to the user
- **Does not do task-context codebase investigation** — that's for the project's code-exploration tooling; `/education:teach codebase` is structured learning for understanding
- **Does not auto-invoke** — `disable-model-invocation: true`. The user initiates learning sessions
