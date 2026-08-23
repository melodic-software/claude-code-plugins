# Changelog

All notable changes to the `education` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.2]

### Fixed

- **`setup` skill:** the headless reconfiguration route no longer prescribes `claude plugin
  uninstall` + reinstall. That instruction rested on an unversioned claim that `claude plugin
  install --config` is ignored once a plugin is installed, and following it dropped the plugin's
  whole stored `pluginConfigs` entry, resetting every declared option to its manifest default.
  On Claude Code 2.1.240 a plain `claude plugin install … --config` against an already-installed
  plugin prints `already installed` and still writes the value, so that is now the documented
  route — stamped with the CLI version it was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). This skill is
  check-only — it has no `apply` action — and `check` still closes by telling the reader to
  rerun it in a fresh session and report the observed value, never asserting an unobserved
  change.
- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

## [0.8.1]

### Changed

- **`teach`: the whole research-grounding ladder names the Skill tool (#3002).** Tier 1's
  `/discovery:research` and its `/context7:lookup` / `/firecrawl:firecrawl` fallback rungs, tier 2's
  `/discovery:research-deep`, tier 3's `/knowledge:map-corpus`, and the adjacent intake/sources
  line (`/discovery:blindspot`, `/dometrain:grounding`, `/x:read`) now all say "via the Skill
  tool" — applying the rule to one rung of a ladder and not the rest was the defect. Tier 1 also
  lost a mid-sentence lowercase "invoke" left by the first pass. `context/lessons.md`'s visual-design
  delegation to `/frontend-design:frontend-design` carries the phrasing too: the rubric's
  `disable-model-invocation: true` exemption is keyed on the TARGET, and `teach` being `true`
  itself says nothing about what it may reach.
  Wording only — the tier order, presence gates, and the terminal WebSearch rung are unchanged.
  `education:setup` references are left as prose: it is `disable-model-invocation: true`, so the
  rubric's invocation-reach invariant keeps it human-only.

## [0.8.0]

### Added

- **`teach`: build a diagram up rather than opening with the finished one, and stop a lesson
  degenerating into a reference dump.** Two rules absorbed from an upstream cursor/plugins skill
  (`docs/upstream/cursor-pstack.md`, the `teach` section) into the lesson contract.

  For anything with three or more moving parts, the lesson draws a short series where each picture
  redraws the last and adds exactly one part, so the learner watches the system assemble — to teach
  A→B→C, draw A→B, then redraw and add C, then redraw and add the return edge. Three small growing
  diagrams beat one crowded one, and the series is the opposite of a wall: each step is small and
  carries one idea. A single all-at-once diagram, especially one saved for the end, is a reference.
  Verified absent fleet-wide before landing.

  The second rule names the failure the first one prevents in prose: enumerating the functions,
  constants, or fields a thing has produces something shaped like a lesson that teaches nothing. Say
  what problem each part solves and how it works; if the draft reads like a changelog it belongs in
  the concept's `reference.md`.

  Both landed in `context/lessons.md` rather than in `visualization:visualize` or
  `education:explain`, which an adversarial audit of the plan showed were both wrong homes.
  `visualize` declares itself a form-and-medium router that "is not a craft teacher" and does not do
  comprehension work, and the build-up rule is comprehension-driven by upstream's own words. And
  `explain` is an ELI5 altitude drop that never lists functions in the first place, whereas the
  Teach/Practice/Go-deeper lesson unit is exactly what can degenerate into one.

## [0.7.1]

### Changed

- **Explicit `disable-model-invocation` on `explain` and `quiz-me` (#2968).** Both skills now state the
  invocation mode the harness already applied for an absent key (`false`), so the choice is
  auditable and gated by `skill-quality:check` check 24. No behavior change. Rubric:
  `docs/conventions/invocation-mode/README.md`.

## [0.7.0]

Two consumer-visible default changes (lesson format, topic-workspace location) — the
`teach-skill-comparison` topic audit (PR #2958 carries the full Brief and plan) is the design record.

### Changed

- **Learning workspaces are classified as user documents, not machine state — a deliberate,
  documented deviation from the plugin philosophy's plugin-data default.** A learning workspace
  is the user's own long-lived study material (mission, glossary, lessons, references): it should
  be visible, portable, and survive plugin removal the way documents do, not live in an opaque
  machine-state directory. `teach` therefore resolves a workspace-root ladder — project
  declaration → `workspace_root` userConfig → one-time ask → the OS Documents folder's
  `Claude Learning/` home → `${CLAUDE_PLUGIN_DATA}` — and topic-mode workspaces default to the
  Documents home where one is eligible. **Codebase-mode workspaces stay under plugin data by
  default**: their lessons embed repo snippets, and Documents roots are commonly cloud-synced
  (OneDrive/iCloud), so repo-derived state must not silently leave the machine for a private
  repo — privacy beats visibility there. Existing plugin-data workspaces stay readable forever
  (the ladder always scans that root); migration is a one-time offer, never forced.
- **Lessons default to interactive, self-contained HTML where the learner's host can render
  it** (headless/SSH/remote/cloud hosts keep markdown; so do lessons where interactivity pays
  nothing). The durable trio — `reference.md`, learning records, `GLOSSARY.md` — stays
  markdown. Lesson HTML embeds shared assets by a scripted splice from the workspace `assets/`
  library (stylesheet + answer-shuffling quiz component), never re-emitted per lesson; in-page
  quizzes end in a copy-out result block graded in conversation, recorded as learning-record
  evidence — the page never self-certifies.
- **Mission interview runs BEFORE workspace creation** (it crystallizes the raw subject name
  the slug and collision guard need) and harvests fields the opening message already answers;
  whole-repo/deictic subjects route to codebase mode under a stable derived content name.
- **codebase action argument renamed `<concept>` → `<topic>`** with the concepts-are-smaller-
  units mapping stated.

### Added

- **Storage-strength pedagogy** (from the upstream teach skill, re-adopted): fluency-vs-storage
  distinction, desirable-difficulty triad (retrieval practice, spacing, interleaving — skills
  practice only), the knowledge/skills difficulty asymmetry, and the equal-length quiz-answer
  rule.
- **Graduated research-grounding ladder** for lesson claims: tier 0 no-dispatch (repo files
  Read this turn, verified RESOURCES.md citations) → tier 1 `/discovery:research` with
  inline-fetch fallbacks → tier 2 seeding via `/discovery:research-deep` → tier 3
  `/knowledge:map-corpus` + digests — every cross-plugin name presence-gated; roughly one
  research dispatch per session; parametric recall banned at every tier.
- **Spaced review**: `resume` surfaces due-for-review floor concepts (record age × domain
  velocity) before advancing the frontier; `status` adds a due-for-review flag from
  filename/mtime heuristics only.
- **Open-lesson affordance** (permission-gated `open`/`xdg-open`/`start`; skipped on
  remote/web hosts) and a presence-gated publish-as-artifact flavor.
- **`workspace_root` userConfig** for teach, mirroring the `knowledge.library_dir` value
  grammar; surfaced by `/education:setup`.
- **`list-workspaces.sh` multi-root scan + `--default-root`** (OS Documents resolution with the
  exists-and-not-`$HOME` guard), linked-worktree slug hoisting via `git rev-parse
  --git-common-dir` with legacy per-worktree slugs still scanned and labeled; regression suite
  extended to 29 checks.
- **Five new teach evals** (research-tier selection, root-ladder resolution, platform-aware
  lesson format, due-for-review surfacing, deictic routing); eval 1 amended to the root-ladder
  expectation.

## [0.6.4]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.6.3]

### Added

- **`/education:setup` check-only setup skill** for `quiz_policy` and `report_library_dir`
  userConfig verification (#988).

## [0.6.2]

### Fixed

- **education:teach loads under worktree isolation (#1687).** Workspace listing moved out of the pre-compute block into a body Bash call.

## [0.6.1]

### Fixed

- **education:teach loads under worktree isolation (#1687).** Workspace listing moved out of
  the pre-compute block into a body Bash call so `${CLAUDE_PROJECT_DIR}` / `${CLAUDE_PLUGIN_DATA}`
  expansions no longer refuse at skill load.

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.5]

### Added

- **`quiz-me`: report narrative sections get a length calibration.** The report contract densely
  specified self-containment, answer-key embedding, and retention slugging but carried no length
  guidance for the four free-form narrative sections — the most padding-prone genre (explanatory
  narrative for a human reader) in a retained, growing library. The contract now carries it:
  match each section's length to what the change needs; no filler, redundant summaries, or
  boilerplate.

## [0.5.4]

### Fixed

- `/education:teach` failed to load entirely when invoked from a worktree-isolated agent.
  Its `## Pre-computed Context` line derived the workspace slug inline, and the harness
  composes a skill's pre-compute commands into a shell invocation the worktree-isolation
  Bash guard checks: the guard refuses any genuine `$`-expansion, and the line carried
  `$p` / `$b` / `$h` locals plus `$(realpath …)`, `$(basename …)` and `$(printf … sha256sum …)`
  substitutions. The derivation now lives in a bundled
  `skills/teach/scripts/list-workspaces.sh`, invoked with plugin variables only
  (`${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}`), which the
  harness substitutes into literal paths before any shell sees them — so the composed
  command contains no `$` for the guard to refuse, while the script file uses `$` freely.
  SKILL.md's "Workspace layout" section remains normative for the slug derivation and now
  names the script as its implementation. Refs #1687.
- The teach pre-compute probe reported **nothing at all** for a project with no
  workspaces, instead of the `none` its own fallback intended. `ls -d … 2>/dev/null |
  head -20 || echo "none"` binds `||` to the pipeline, whose status is `head`'s, and `head`
  exits 0 even when `ls` matched nothing — so the fallback was unreachable and the skill
  loaded with an empty value that reads the same as a broken probe. The bundled script now
  prints `none` on a no-match; the invoking line keeps its own `|| echo "none"` for the
  distinct case of the script itself being unavailable.

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
