# Changelog

All notable changes to the `education` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.3]

### Fixed

- `/education:teach`'s optional HTML output no longer calls itself "ephemeral placement"
  while writing into persistent machine state, and no longer offers two placements for
  one artifact. The bullet in `skills/teach/context/lessons.md` allowed either the
  workspace concept slice **or** OS temp, which made placement non-deterministic, and its
  title collided with the marketplace topic-docs **ephemeral tier** — a tier a workspace
  artifact does not belong in. A concept's HTML *is* that concept's lesson artifact: the
  workspace is durable cross-session coaching state that `resume` reopens, so it is
  machine state, and the single placement is now the concept slice. "Ephemeral" in the
  eagerly-loaded `skills/teach/SKILL.md` surfaces as well as in this doc is pedagogical
  (rarely revisited, regenerable) and is now stated as such at each. The classification is justified by the slice
  the file belongs to — `resume` opens `concepts/<concept>/`, so a lesson rendered to
  temp would leave that concept holding a reference and an exercise with its lesson
  missing — and explicitly **not** by any claim that something re-reads the lesson;
  the Staleness check covers references and the glossary, never lessons.
  `skills/teach/SKILL.md` no longer calls the HTML "session output" either.
- The `primer` action's HTML vocabulary ladder had **no resolvable path**: it routed
  through the workspace placement above while creating no workspace, so there was no
  `<mode>`, `<topic>`, or `<concept>` to substitute. It is read once and never again, so
  it is now routed explicitly through the topic-docs ephemeral tier — one file per run
  via the platform's temp primitive, resolved deterministically, never the session
  scratchpad, and never deleted before the path is handed back. Its `mktemp` invocation
  names the temp root in the template, the one form that cannot land the file in the
  working directory, and takes the `-d` run-directory form with `primer.html` written
  inside it: BSD `mktemp` on macOS substitutes only **trailing** `XXXXXX`, so the
  `…-XXXXXX.html` file template this entry originally prescribed could not create the
  primer on macOS. See `docs/conventions/topic-docs/README.md` §"The ephemeral tier".
- An HTML lesson now has a **canonical filename and a replacement rule**. Allowing a
  lesson to be HTML left the name unspecified while the workspace schema and the
  `explain` action both named `concepts/<concept>/lesson.md`, so re-rendering a concept
  could leave a stale `lesson.md` beside an unnamed HTML file with nothing telling a
  resumed session which was current. The HTML lesson is `lesson.html`, it **replaces**
  `lesson.md` rather than joining it — one lesson file per concept, never both — and
  every surface that names the file now says so.
- **The slug-collision guard survives an HTML lesson.** Letting `lesson.html` replace
  `lesson.md` removed the guard's only identity source: `skills/teach/SKILL.md` "Path
  resolution rules" compares an existing slice's recorded raw concept name before reusing
  its slug directory, and that name lived solely in the Markdown `**Concept:**` line. With
  an HTML lesson there was no equivalent field, so `C++` and `C#` — both normalizing to
  `c` — could silently share one slice. `lesson.html` now MUST carry
  `<meta name="concept" content="<raw concept name>">`, and the rule names the marker per
  format rather than per file, so the guard no longer depends on the lesson's extension.

## [0.5.2]

### Changed

- `/education:explain` description gains a disjoint-trigger boundary vs the new
  `adhd:clarify`: `explain` changes ALTITUDE (plain words, lossy), `clarify`
  changes STRUCTURE (faithful restructure, no altitude loss). This keeps the two
  auto-firing skills from colliding on the shared "previous response" default
  target — routing is on intent, not overlapping phrases. All existing `explain`
  trigger keywords are preserved.

## [0.5.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.5.0]

### Added

- New `quiz-me` skill (`/education:quiz-me`) — a post-work comprehension
  check. After a change is complete it generates a self-contained HTML
  report of what was done (context, intuition, decisions) with a quiz at
  the bottom the user answers, verifying that the HUMAN absorbed the work
  rather than the artifact. Non-gating by default; the new `quiz_policy`
  userConfig (`off`, `on-request`, `always`, `above-threshold`) tunes how
  often a quiz is offered, never whether the merge is blocked. A
  `recall <query>` action answers "what did we do
  on <ticket>" from a retained report library first, git/tracker
  archaeology second. Reports are keyed on repo identity and stored under
  `${CLAUDE_PLUGIN_DATA}` (or the new `report_library_dir` userConfig),
  never in the consuming repo's tree.

### Changed

- The plugin now declares `userConfig` (`quiz_policy`,
  `report_library_dir`), both optional with defaults that preserve
  zero-config behavior. The README Configuration section documents them.

## [0.4.0]

### Added

- New `explain` skill (`/education:explain`) — a one-shot, plain-language
  sibling to the multi-session `teach` coach. It drops any concept, code,
  error, architecture, or the previous assistant response to genuinely plain
  words (concrete analogy, zero jargon), then layers altitude up only on
  request (high-school, then peer level). An empty argument targets the
  previous assistant response (anaphora), so "I don't get it" needs no topic
  named. Unlike `teach`, it auto-invokes on colloquial triggers, runs a Feynman
  gap check that surfaces an understanding gap instead of papering over it, and
  closes by offering `/education:teach topic <x>` for ongoing coaching.

## [0.3.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.3.1]

### Changed

- README Requirements now declare the skill's Bash + coreutils mechanics
  (`sha256sum`/`shasum`, `realpath`, `tr`, `sed`) with their Windows path
  (Git Bash bundles all of them), replacing the inaccurate "none beyond
  Claude Code" — cross-platform declaration wave.

## [0.3.0]

First versioned release covered by this changelog; see the git history of
`plugins/education/` for earlier changes.
