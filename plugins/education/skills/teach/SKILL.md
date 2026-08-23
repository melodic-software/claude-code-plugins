---
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

Teach a user interactively across multiple sessions. Not by lecturing, but by coaching through the Knowledge-Skills-Wisdom progression grounded in the user's real goals. Maintains persistent learning state so each session builds on prior understanding.

**Use when:** user asks to learn across sessions (`teach me`, `study session`, `help me learn`, `onboard me to`). **Skip when:** one-off inline question (answer directly); task-context codebase investigation (use the project's own code-exploration tooling); extracting book knowledge to a reference file (`/knowledge:book-distill` when installed).

Two modes share pedagogy but differ in source material:

- **`topic`**. General subject learning. Resources come from external high-trust sources (books, courses, docs, communities).
- **`codebase`**. Repo-grounded learning. Resources come from the consuming repo's own code, docs, ADRs, conventions, discovered at teach-time (see "Codebase mode").

**Workspace layout** (where persistent learning state lives): see "Workspace layout" below. The single source of truth every action resolves paths against. Informed by ZPD/K-S-W pedagogy research.

## Workspace layout

Learning state is the user's own study material. User documents, not machine internals. Every workspace lives at `<workspace-root>/<project-slug>/<mode>/<topic>/`, where `<workspace-root>` resolves per "Workspace root resolution" below (topic mode defaults to the OS Documents folder's `Claude Learning/` home where one is eligible; codebase mode defaults to `${CLAUDE_PLUGIN_DATA}`); no root ever pollutes the consuming repo unless the project itself declares one:

```text
<workspace-root>/<project-slug>/<mode>/<topic>/
├── MISSION.md               WHY the user is learning this — goal, success criteria, constraints (workspace-global)
├── GLOSSARY.md              durable terminology SSOT — add only when the user demonstrates understanding (global)
├── RESOURCES.md             curated high-trust sources (knowledge + wisdom communities) (global)
├── NOTES.md                 teaching preferences + working notes — how the user wants to be taught (global)
├── assets/                  shared lesson components — lesson.css + answer-shuffling quiz.js, spliced into HTML lessons (context/lessons.md "Assets library")
├── learning-records/        cross-cutting ZPD log — ADR-style insight records (append-only)
│   ├── 0001-<slug>.md
│   └── 0002-<slug>.md
└── concepts/                per-concept slices
    └── <concept-slug>/      ONE tightly-scoped thing — things that change together, together
        ├── lesson.html      the teaching unit — pedagogically ephemeral (rarely revisited, regenerable), NOT the topic-docs ephemeral tier; `lesson.md` where the host can't render HTML (ONE lesson file per concept — format decision + replacement rules: context/lessons.md)
        ├── reference.md     durable compressed cheat-sheet (revisited; the rot-relevant artifact)
        └── exercise.md      colocated practice (optional)
```

Path resolution rules every action MUST follow:

- **`<project-slug>`**. **canonicalize the project path FIRST**, then derive BOTH the basename-slug and the hash from that one canonical path, so a project opened via a symlink and via its real path map to the same workspace (otherwise the alias basename would still split it. `alias-<hash>` vs `realname-<hash>`). Canonical path: `realpath "${CLAUDE_PROJECT_DIR}" 2>/dev/null || readlink -f "${CLAUDE_PROJECT_DIR}" 2>/dev/null || printf '%s' "${CLAUDE_PROJECT_DIR}"` (e.g. macOS repos under `/private/var/…`). And when the project is a **linked git worktree**, hoist to the main repository first: if `git rev-parse --git-common-dir` names a `.git` outside the project, the directory holding it is the canonical path, so all worktrees of one repo share one workspace. Then `<project-slug>` = the **basename of the canonical path** slugified to lowercase alphanumerics and hyphens, then `-` plus the first 8 hex chars of `printf '%s' "<canonical-path>" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8` (the fallback covers stock macOS). The hash discriminator is required because the basename alone collides when two clones share a directory name. Both `topic` and `codebase` workspaces are scoped under `<project-slug>`. Topic learning becomes associated with the project you launched from. `scripts/list-workspaces.sh` implements this derivation (including the worktree hoist, and a compat scan that lists pre-hoist per-worktree slugs labeled `(legacy worktree slug)`); this bullet stays normative for it.
- **`<mode>`**. Literally `topic` or `codebase`, matching the action that created the workspace. This level keeps the two modes independent: `/education:teach topic auth-flow` and `/education:teach codebase auth-flow` in the same project resolve to separate workspaces (`.../topic/auth-flow/` vs `.../codebase/auth-flow/`) instead of one seeding over the other's `MISSION.md` / `RESOURCES.md`.
- **`<topic>`** and **`<concept>`**. Content-named kebab slugs (lowercase alphanumerics and hyphens only; strip `/`, `\`, `..`), NOT sequence-numbered. A deictic subject ("this repo") is first resolved to a stable content name per the Smart default rules. Never slug the deixis itself. `"Domain-Driven Design"` → `domain-driven-design`; `"Rust Ownership"` → `rust-ownership`. **Record the exact raw subject/concept name** (`MISSION.md`'s `# Mission: {Topic}` title for a topic; for a concept, the lesson's `**Concept:**` line in `lesson.md` or its `<meta name="concept" content="…">` in `lesson.html`. The lesson carries the raw name in whichever of the two formats it is written, so the guard below never depends on the extension) so it is the source of truth for collision checks. **Guard against slug collisions**. Distinct subjects can normalize to the same slug (`C++` and `C#` → `c`; `Node.js` and `Node JS` → `node-js`), which would silently share one workspace. Before creating a workspace whose slug directory already exists, read that existing workspace's recorded raw name; if it names a DIFFERENT subject, append `-` plus the first 4 hex chars of `printf '%s' '<raw-name>' | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-4` to the new slug, keeping per-subject state isolated while leaving non-colliding slugs readable.
- **`learning-records/NNNN-<slug>.md`** keeps `NNNN-` numbering (sanctioned ADR-style append-only log). Scan the directory for the highest existing `NNNN` and increment.
- `${CLAUDE_PLUGIN_DATA}` is created automatically the first time it is referenced and persists across plugin updates, so workspaces survive between sessions. A user-chosen root (Documents home, configured root) gets its `Claude Learning/`-style home created only at first workspace creation there, the platform Documents directory itself is NEVER created by this skill.

Lessons default to interactive, self-contained `lesson.html` where the learner's host can render it; on headless hosts, and where interactivity pays nothing, the lesson is `lesson.md` (one lesson file per concept, never both. The platform-aware format decision, identity/meta, and replacement rules live in [context/lessons.md](context/lessons.md)). The durable trio. `reference.md`, learning records, `GLOSSARY.md`. Stays markdown, the diffable source of truth; `exercise.md` stays markdown too, and only the workspace-less `primer` renders to a temp path.

## Workspace root resolution

### Effective configuration (substituted at load)

The value below substitutes from this plugin's stored configuration when this skill loads. A surviving literal `${user_config.…}` placeholder means the key is unset. Apply its documented unset behavior, and never paste the raw placeholder into a shell command (the probe script also filters it defensively).

| Key | Value | Unset behavior |
| --- | --- | --- |
| `workspace_root` | `${user_config.workspace_root}` | unset → continue down the ladder (rungs 3–5). Value grammar per the `knowledge.library_dir` precedent: absolute, `~`-home-relative, or `${NAME}`/`%NAME%` env refs; a relative value resolves against the project. A value inside the consuming repo is refused (rung-1 project declaration is the only path to a committed root). |

### The ladder

Resolve `<workspace-root>` by the first rung that answers. Cross-root semantics: for a given `<project-slug>/<mode>/<topic>`, the ladder-highest root wins; duplicates found at lower roots are surfaced to the user, never merged.

1. **Project declaration**. A `teach workspace root: <path>` declaration in the consuming project's CLAUDE.md or rules files (the repo's config-cascade convention). The only rung that may name a path inside the consuming repo. An explicit team choice that commits personal learning state. **The declared value is UNTRUSTED input** (a third-party repo's author controls it, not the person learning): it must satisfy the same value grammar as rung 2. A plain path (absolute, `~`-home-relative, `${NAME}`/`%NAME%` env refs, or project-relative), nothing else. REFUSE. Loudly, falling to the next rung. Any value containing shell metacharacters, command or variable substitution syntax (`$(`, backticks, `;`, `|`, `&`, `<`, `>`, quotes, newlines), or that is not parseable as a single path. Never execute, expand, or eval a declared value.
2. **`workspace_root` userConfig**. The table above; surfaced and validated by `/education:setup`.

**Resolved roots are inert data, from every rung.** Pass a resolved root to `list-workspaces.sh`, the assets splice, and the open-lesson command as a literal argv argument only. Never interpolated into a hand-composed shell string where substitution could fire, and never as part of a command name. This applies to every place a `<workspace-root>`-derived path appears in this skill and its context docs.
3. **Ask-once (`topic` mode only)**. First TOPIC workspace creation with rungs 1–2 unset in an interactive session: ask ONCE where learning state should live, offering the rung-4 default. A `codebase` workspace never triggers this rung and its creation never offers a Documents root. Codebase state leaves plugin-data only via explicit rung 1–2 configuration (see Mode split). Persist the answer in the pointer file `${CLAUDE_PLUGIN_DATA}/workspace-root` (never a `pluginConfigs` write), and recommend making it durable via the native `workspace_root` userConfig (`/education:setup`). The pointer file is a **machine-local cache only**: before asking, adopt without asking an existing `Claude Learning/` home at the rung-4 location or an existing workspace tree at a configured root. It also records the migration-offer outcome (below). Non-interactive/headless sessions skip this rung silently; when plugin-data is unavailable, fall through silently rather than erroring.
4. **OS Documents default. `topic` mode only.** Resolve mechanically with `bash "${CLAUDE_PLUGIN_ROOT}/skills/teach/scripts/list-workspaces.sh" --default-root`: the platform Documents directory (Windows Documents known folder resolved native-side and converted per the marketplace `docs/conventions/windows-path-emit/` convention. OneDrive-redirected and space-bearing paths handled, fail-loud; macOS `~/Documents`; Linux `xdg-user-dir DOCUMENTS`) qualifies ONLY when it already exists AND is not `$HOME` itself (unconfigured `xdg-user-dir` echoes `$HOME`), and the home inside it is the properly-cased `Claude Learning/` (English name; localize only if the user asks). Exit 1 from `--default-root` = no eligible default → rung 5.
5. **`${CLAUDE_PLUGIN_DATA}` fallback**. Headless/unset/no-Documents hosts, and the compat home where every pre-ladder workspace already lives.

**Mode split:** the Documents default applies to `topic` workspaces only; **`codebase` workspaces stay under `${CLAUDE_PLUGIN_DATA}` by default**. Documents roots are commonly cloud-synced (OneDrive/iCloud), and codebase lessons embed repo snippets that must not silently leave the machine for a private repo, a codebase workspace lands at a user-chosen root only via explicit rung 1–2 configuration.

**Migration and compat:** plugin-data workspaces stay readable forever. Rung 5 is always scanned. When an interactive session resolves a higher root while plugin-data workspaces exist, offer a ONE-TIME migration (move the tree); record the outcome either way in the rung-3 pointer file and never re-offer. Never force-migrate; if compat ever cannot stay scan-only, stop and ask the user.

**Root hazards (documented, not silent):** cloud-synced roots. Machine-scoped slugs mean the same repo on two machines gets sibling workspaces in one synced root (no illusory continuity), and sync conflicts can collide on `learning-records/NNNN`; gitignored in-repo roots fragment across worktrees; temp roots die with the session; committed roots put personal learning state in a shared repo (explicit rung-1 team choice only).

## Pre-computed Context

Gather with one Bash call (worktree-isolated agents refuse `$`-expansion in pre-compute blocks; #1687. And `${user_config.*}` tokens must NEVER appear on this line: a surviving literal is a bash `bad substitution` that kills the whole call before any fallback):

- Plugin-data workspaces, `bash "${CLAUDE_PLUGIN_ROOT}/skills/teach/scripts/list-workspaces.sh" "${CLAUDE_PROJECT_DIR}" "${CLAUDE_PLUGIN_DATA}" 2>/dev/null || echo "none"`

Treat failure as `"none"` and continue. This probe covers rung 5 only. After resolving the ladder in the body, re-invoke the script as an ordinary Bash call with every resolved root as an argument, ladder-highest first, `list-workspaces.sh "${CLAUDE_PROJECT_DIR}" <root>...`, and distinguish its exits: **exit 2 = probe broken** (usage error / all roots filtered as unset) → glob the resolved roots manually before creating any workspace; a printed `none` with exit 0 = genuinely no workspaces.

## Action Router

Parse `$ARGUMENTS`: first token = action, remainder = args. If empty or ambiguous, detect from conversation.

| Action | Purpose | Detail |
|--------|---------|--------|
| `topic <subject>` | Start or resume learning a general subject | Creates workspace, runs mission interview if new |
| `codebase <topic>` | Learn a repo-grounded concept; the argument is the workspace `<topic>` (its own `concepts/` slices are smaller units inside it) | Creates workspace, grounds in actual discovered files |
| `mission` | Review or update learning mission | [context/mission.md](context/mission.md) |
| `glossary` | Review or update compressed terminology | [context/glossary.md](context/glossary.md) |
| `resources` | Manage curated learning sources | [context/resources.md](context/resources.md) |
| `explain <concept>` | Teach one tightly-scoped thing (a lesson) | Writes the concept's single lesson file (`lesson.html`/`lesson.md` per [context/lessons.md](context/lessons.md)). Pedagogically ephemeral but durable machine state on disk; distill a durable `reference.md` alongside |
| `primer <domain>` | Single-session domain primer. NO workspace | See "Primer action" below |
| `exercise` | Colocated practice for a concept | Writes `concepts/<concept>/exercise.md`; design per [context/exercises.md](context/exercises.md) |
| `assess` | Check understanding, update learning records | [context/assessment.md](context/assessment.md) |
| `resume` | Resume a workspace from prior session | Reads workspace state, picks up where left off |
| `status` | Show learning progress across all workspaces | Lists workspaces + latest learning records |

**Smart default:** if the user provides a subject without an action, detect mode:

- Subject names a concept in the consuming repo (a module, a framework the repo uses, an internal library or abstraction the repo defines) → `codebase`
- Subject is the whole repo or deictic. "this repo", "this codebase", "onboard me here" → `codebase`, and derive a **stable content name** rather than slugging the deixis: repo basename + a scope word (raw name `"<repo-basename> overview"` → slug `<repo-basename>-overview`), recorded as the raw subject name so two runs of the same request resolve to one workspace
- Otherwise → `topic`

## Primer action

`primer <domain>` is the single-session middle tier between an inline answer and a full `topic` workspace: the user needs enough of an unfamiliar domain's vocabulary and quality criteria to prompt well NOW ("teach me color grading so I can direct the work"), not a multi-session curriculum. Purpose: turn a vague request into a precise spec by teaching what the terms of art are and what GOOD looks like.

- **No workspace**. No `<topic>` directory, mission interview, glossary, or learning records. Output is the session conversation plus an optional self-contained HTML vocabulary ladder (vague term → precise spec, with copy-out) per "Lessons and Reference" HTML routing.
- **Shape**. Intake the user's starting point (one question), then build the vocabulary ladder: core terms, the quality axes experts judge by, worked good-vs-bad examples, and a closing "how to ask for what you want" prompt template.
- **Ground per Knowledge layer**. Primary sources this turn, never parametric recall.
- **Escalate**. If the user wants depth or practice, offer `/education:teach topic <domain>` (full workspace).

## Resume, Status, and workspace resolution

`resume` and `status` operate over the workspaces under `<workspace-root>/<project-slug>/<mode>/<topic>/` for EVERY root the ladder resolves (both modes; one body re-invocation of `list-workspaces.sh` with all roots, see "Pre-computed Context"):

- **`resume [<topic>]`**. With a topic argument, resolve that workspace directly (disambiguating by `<mode>` if the same topic exists in both) and follow "Resume (subsequent sessions)". With no argument, list the workspaces sorted by most-recently-modified (git or filesystem mtime of the workspace files) and ask the user which to resume. Never silently pick one when more than one exists.
- **`status`**. For each workspace, show its mode, topic, the count of `learning-records/`, the current frontier concept, the last-touched date, and a **due-for-review flag**. From filename + mtime heuristics plus ONE cheap metadata probe: exclude superseded records via a status-line grep (`grep -l 'superseded by' learning-records/*.md`. Matches the `Status:` frontmatter line without loading bodies into context), since a superseded record is not part of the active floor and would otherwise emit false due-for-review flags. One line per workspace; no full file bodies loaded. The per-concept due-for-review detail loads only on `resume` of that workspace.
- **`explain <concept>` / `exercise` need an active workspace.** They write into `concepts/<concept>/` under a topic workspace. If exactly one workspace exists, use it; if several exist, ask which; if none exists, ask whether to start one (`topic` / `codebase`) before writing, never invent a workspace silently.

## Pedagogy. Three Layers

Every teaching session progresses through Knowledge → Skills → Wisdom. Don't skip layers; don't rush. Each layer has different teaching moves. The knowledge/skills balance varies by topic. Theory-heavy subjects (theoretical physics) lean knowledge; practice-heavy ones (yoga, a framework) lean skills. Calibrate lesson design to the topic.

### Fluency vs storage strength

Optimize for **storage strength**, long-term retention, not **fluency**, in-the-moment recall that gives "an illusory sense of mastery" (upstream teach-skill terms; the research literature, Bjork, names the pair storage strength vs *retrieval* strength). Storage strength is built by **desirable difficulty**: retrieval practice (recall from memory before re-showing), spacing (distributing practice over time), and interleaving (mixing related topics in practice. **skills practice only**, never knowledge presentation). The asymmetry that governs lesson design: **for acquiring knowledge, difficulty is the enemy**. It eats the working memory understanding needs, so explanations stay clear and scaffolded; **for skill acquisition, difficulty is the tool**. Effortful retrieval is what builds storage strength, so practice stays effortful. Quiz design inherits this: answer options carry equal length and formatting weight so presentation never leaks the answer (see [context/exercises.md](context/exercises.md)).

### Knowledge (declarative. What is it?)

- Provide clear explanations with examples and counterexamples
- Ground per "Research grounding" below. Never parametric recall at any tier. A claim that drives a lesson is verified against a source fetched or a file Read THIS turn, not recalled from training data; the ladder decides *which* fetch, never *whether*
- Use retrieval practice: ask the user to restate in their own words
- Add to `GLOSSARY.md` only when the user demonstrates understanding

### Research grounding

Grounding is graduated, pick the cheapest tier that grounds the claim:

- **Tier 0. Already-verified sources, no dispatch.** Repo files Read this turn (codebase mode) and `RESOURCES.md` citations already verified satisfy grounding for narrow or slow-domain claims. Escalate to tier 1 when a claim is contested, broad, or fast-domain (library APIs, framework syntax, tooling).
- **Tier 1. Per-lesson research (default for fresh external claims).** Invoke `/discovery:research` via the Skill tool when installed; fallback chain when absent: inline fetch of the authoritative source, `/context7:lookup` via the Skill tool (if installed) for library docs, `/firecrawl:firecrawl` via the Skill tool (if installed) when fetches are blocked. Terminating at built-in WebSearch/WebFetch. Cap: roughly one research dispatch per session unless the subject shifts, batch open questions into one dispatch.
- **Tier 2. Workspace seeding / broad subjects.** Invoke `/discovery:research-deep` via the Skill tool (if installed), or use dynamic workflows, to seed `RESOURCES.md` when a workspace opens on a broad subject.
- **Tier 3. Huge-subject corpus.** Invoke `/knowledge:map-corpus` via the Skill tool plus its digest skills (if installed) to build a corpus map; `RESOURCES.md` points at the produced slices.

Adjacent intake and sources, each invoked via the Skill tool and each only if installed: `/discovery:blindspot` when the learner doesn't know what they don't know (unknown-territory intake before the mission interview); `/dometrain:grounding` for course-grounded claims; `/x:read` when a resource lives in an X post or thread.

### Skills (procedural. How to do it?)

- Emphasize deliberate practice: small tasks focused on 1-2 skills at a time
- Couple explanation with application: explain → simple use → novel use → integrated use
- For `codebase` mode: exercises use actual repo patterns (write a handler, add a test, implement the repo's own domain primitive)
- Use error-driven learning: present buggy code, ask the user to diagnose
- Tight feedback loops, immediate feedback on each attempt

### Wisdom (judgment. When and why?)

- Ask about tradeoffs: "You chose X; what are the pros/cons vs Y?"
- Present multiple solutions, ask the user to choose and justify
- Connect to mission: "How does this apply to what you're building?"
- Prompt transfer: "Where else could this pattern apply?"
- Metacognitive reflection: "What tripped you up? What pattern did you learn?"
- For `codebase` mode: connect to the repo's ADRs, architecture decisions, design philosophy
- **Delegate to community.** Wisdom comes from real-world interaction outside the learning environment. Something an AI tutor structurally cannot provide. When a question requires wisdom, attempt to answer but also find relevant communities (subreddits, Discord servers, local meetups, courses, open-source projects) where the user can test skills in practice. Record community preferences in `RESOURCES.md`. Respect opt-outs. If the user declines community participation, don't re-suggest

## Lessons and Reference

The unit of teaching is a **lesson**. One tightly-scoped thing tied to the mission, completable quickly for a tangible win, in the user's zone of proximal development. Lessons are ephemeral in the **pedagogical** sense only. Rarely revisited and regenerable. Never in the topic-docs sense: a lesson is a member of its concept slice and stays in machine state. Alongside, distill the durable **reference**. The compressed cheat-sheet the user returns to. Authoring format, the platform-aware HTML-first default, the assets splice, reuse-first scaffolds, inline citations: [context/lessons.md](context/lessons.md).

Concept diagrams: `/visualization:visualize` when installed; otherwise native mermaid blocks (markdown fences, or `<pre class="mermaid">` where a host renders HTML) cover most structural diagrams. In-lesson charts follow the `dataviz` skill's constraints when that skill is present.

## Zone of Proximal Development

Teach just beyond current understanding, challenging but achievable. Scaffold and fade:

1. **Check current level**. Read learning records, ask what they already know
2. **Calibrate difficulty**. Not too easy (bored), not too hard (frustrated)
3. **Scaffold levels** (fade as competence grows):
   - Orientation, restate in simpler terms, break into sub-steps
   - Heuristic hints, guiding questions ("What data structure gives O(1) lookup?")
   - Pointing hints, highlight relevant concept or code section
   - Partial solution, show snippet with blanks
   - Full solution + explanation, last resort, always ask the user to explain back
4. **Track and adapt**. Update learning records when understanding demonstrated

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

1. Run the mission interview. WHY are they learning this? What's the concrete goal? What does success look like? **Harvest first:** extract every field the opening message already answers, confirm those in one restatement, and ask only the questions still open. Never re-ask what the user already said. The interview crystallizes the raw subject name the slug + collision guard depend on, which is why it comes BEFORE creation
2. Create the workspace per "Workspace layout", at the root "Workspace root resolution" gives
3. Write `MISSION.md` with the answers
4. Seed `NOTES.md` from the interview's constraints and teaching-preference answers; do NOT create `GLOSSARY.md` yet. It starts with the first demonstrated term (deferral per [context/glossary.md](context/glossary.md))
5. Seed `RESOURCES.md`. For `topic` mode, find high-trust sources; for `codebase` mode, discover and list relevant repo files/docs per "Codebase mode"
6. Assess the starting point. What do they already know? Record it as the first learning record via the `learning-records/` scan-and-increment rule, format per [context/assessment.md](context/assessment.md)
7. Begin teaching from their zone of proximal development

### Resume (subsequent sessions)

1. Read `MISSION.md`, know WHY and the success criteria
2. Read `GLOSSARY.md`, know what terms are established
3. Read `NOTES.md`, recall teaching preferences
4. Scan `learning-records/` for the latest entries, know the current frontier
5. **Surface due-for-review concepts**. Weigh each floor concept's latest record age against the domain's velocity (see "Staleness"); list what is due for spaced retrieval practice BEFORE advancing the frontier, and open with a quick retrieval question on one due concept when any exist (spacing is how storage strength gets built. See "Fluency vs storage strength")
6. Pick the next concept from the zone of proximal development; open its `concepts/<concept>/` slice
7. Before re-teaching an existing concept, run the Staleness check (see "Staleness")

### Session Close

- Summarize what was learned
- Prompt reflection: "What's the key takeaway? What was hardest?"
- Update `GLOSSARY.md` if new terms demonstrated
- Write a learning record for demonstrated understanding, `/education:quiz-me` quiz results (same-plugin sibling) count as record evidence
- Suggest the next session's focus

## Codebase Mode

`codebase` mode grounds learning in the consuming repo, discovered at teach-time. Never in baked assumptions about any particular project's layout. Discover the repo, then teach from what you find:

1. **Read the repo's own guidance.** Climb from `${CLAUDE_PROJECT_DIR}` for the nearest `CLAUDE.md` / `AGENTS.md`; read `README.md`; look for `docs/`, architecture-decision records (commonly `docs/adr/`, `docs/decisions/`), and convention/rules files (`.claude/rules/`, `.cursor/rules/`, a `CONTRIBUTING` file). These state how the project intends its code to be understood. When a guidance file is empty, boilerplate, or contradicts its siblings, flag that to the user, fall back to the next source (README → docs → the code itself), and record the discrepancy in `RESOURCES.md`, never treat an empty file as guidance and never silently pick a side of a contradiction.
2. **Survey the structure.** Inspect the top-level layout (`src/`, `apps/`, `libs/`, `packages/`, tests) and identify languages/frameworks from manifest files present (`package.json`, `*.csproj`/`*.sln`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, …). Locate the files that actually embody the concept the user wants to learn.
3. **Persist what you discover.** Record the located files/docs into the workspace `RESOURCES.md` "Repo Sources" so later sessions don't re-derive the structure. Infer once, persist, reuse. If discovery cannot find a grounding for the concept, ask the user to point you at the relevant area rather than guessing.
4. **Ground EVERYTHING in files Read this turn (Tier 0).** Never teach a codebase lesson from a cached lesson, re-Read the live files; the repo is the durable artifact, self-freshening.
5. **Cite the convention, not the instance.** Durable codebase references capture the pattern (dependency direction, an error-handling idiom, a dispatch mechanism), not a specific file's current contents, so they survive a refactor.

Use the repo's actual code as examples. Create exercises against real patterns. Connect to the repo's ADRs for "why it's done this way."

## Staleness

Learning artifacts persist for months; durable teaching content (references, glossary) can rot. Handle rot by **lazy verify-on-revisit**, not stored metadata:

- **No freshness frontmatter.** Don't record a `verified:` date (git owns it) or a `volatility:` tag (frozen judgment that itself rots).
- **Staleness = age × velocity judgment.** At revisit, weigh the artifact's age against the domain's velocity. Fast (library APIs, framework syntax, AI tooling) vs slow (math, music theory, established architecture). Use domain-velocity intuition to decide *whether* to re-verify, never *what* the current fact is.
- **Treat durable artifacts as unverified on revisit.** A reference/glossary entry from a prior session is unverified synthesis until re-grounded this turn. If stale relative to age × velocity, re-fetch the inline citation, update, THEN teach.
- **Durable references store understanding + citations, not frozen facts.** A reference that freezes an external fact guarantees rot; instead capture the user's compressed mental model with inline citations to the authoritative source, so volatile facts stay by-reference (the citation is the re-verify target).

## What This Skill Does NOT Do

- **Does not write production code**. Teaches understanding, not implementation. Use the project's own implementation workflow for code changes
- **Does not replace `/knowledge:book-distill`**. That extracts book knowledge into skill reference files; `/education:teach` delivers knowledge interactively to the user
- **Does not do task-context codebase investigation**. That's for the project's code-exploration tooling; `/education:teach codebase` is structured learning for understanding
- **Does not auto-invoke**. `disable-model-invocation: true`. The user initiates learning sessions
