# Changelog

All notable changes to the `event-storming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.5]

### Changed

- **Repo-wide `/ai-slop:audit fix` pass (#3359).** The simulation-evaluation pushback
  criterion now excludes only facilitator-authored hot spots; persona disagreements
  the facilitator prompted for still count.
  The quoted participant testimonial in `big-picture-workshop.md` and the quoted
  definition in `design-level.md` are covered marker-free by the detector's
  quotation exemption (ai-slop 0.4.0); the glossary's "Fuzzy by design" sentence
  keeps its marker (its "in order to" is likely verbatim source wording sitting
  outside quote marks), and one literal statement about workshop information flow
  gained a marker after the extended source-gap phrase families landed.

## [0.6.4]

### Changed

- **Instruction-surface de-slop (#2891, event-storming cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. Quoted AskUserQuestion protocol and cited Brandolini
  Phase headings keep their original punctuation.

## [0.6.3]

### Changed

- **The two sibling routes name the Skill tool (#3002).** `methodology`'s "to *run* a workshop"
  route to `/event-storming:simulation` and `simulation`'s "for facilitation knowledge" route to
  `/event-storming:methodology`. The recommendation blockquote `methodology` prints for the user
  is left as-is — it is sample output, not an instruction to the model. The glossary-graduation
  delegations to `/domain-driven-design:curate-language` carry the phrasing too, in both places
  that state it: `methodology`'s `reference/glossary-and-tools.md` and `simulation`'s
  `reference/agentic-simulation.md`. Wording only.

## [0.6.2]

### Changed

- **Explicit `disable-model-invocation` on `methodology` and `simulation` (#2968).** Both skills now state the
  invocation mode the harness already applied for an absent key (`false`), so the choice is
  auditable and gated by `skill-quality:check` check 24. No behavior change. Rubric:
  `docs/conventions/invocation-mode/README.md`.

## [0.6.1]

### Fixed

- **Repaired Miro API sticky-note item link in `miro-integration.md` (#2137).** The URL fragment
  `create-sticky-note-item` 404'd; updated to `create-sticky-note-item-1` so installed consumers
  receive the fix after marketplace update.

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.6]

### Changed

- **The simulation session directory is now created by a secure temp primitive.**
  The agentic simulation reference previously left `{system_temp}` unbound and
  composed a predictable directory name from the session id. It now *creates*
  the directory with `mktemp -d "${TMPDIR:-/tmp}/eventstorming-session-XXXXXX"`
  on POSIX/Git Bash, and with `New-Item -ItemType Directory` under a
  `[System.IO.Path]::GetRandomFileName()` component in the per-user `$env:TEMP` on
  Windows PowerShell. On a multi-user POSIX host the unset-`TMPDIR` fallback is
  the shared world-readable `/tmp`, where a predictable name exposed the persona
  and session Markdown to every local user and allowed pre-creation of the path;
  the random component and `mkdtemp`'s mandated 0700 mode close both. The
  existing delete-vs-archive cleanup protocol is unchanged.

## [0.5.5]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.5.4]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/domain-driven-design:curate-language`); behavior unchanged.

## [0.5.3]

### Changed

- Simulation session teardown is phrased shell-agnostically at both sites
  (`rm -rf` on POSIX/Git Bash, `Remove-Item -Recurse -Force` on PowerShell)
  instead of an unconditional `rm -rf` with no Windows path — cross-platform
  declaration wave.

## [0.5.2]

### Changed

- Soft references to the moved vocabulary skill now invoke `/domain-driven-design:curate-language` (was `/planning:domain-modeling`). Version bumped so existing installs receive the retargeted references.

## [0.5.1]

### Changed

- Workshop and simulation glossary graduation now delegates to `/planning:domain-modeling` when that
  skill is available. The standalone fallback remains discovery-first and lazy, and the boundary is
  explicit: glossary maintenance consumes already-established contexts and never performs context
  discovery.

## [0.5.0]

### Added

- Workshop wrap-up points now offer resolved domain terms for graduation into the consumer repo's committed project glossary instead of leaving them session-scoped: one entry per term with a 1–2 sentence definition and a plain `Avoid:` line of rejected synonyms, project-context terms only, created lazily when the repo keeps no glossary (repo root, or per-context files plus a root map). When the `planning` plugin is installed, `/planning:design` owns the format. Landed at Big Picture Wrapping Up, Design-Level Wrap Up, the Ubiquitous Language notation and simulation capture points, and a canonical graduation section in the methodology glossary reference.

## [0.4.0]

### Added

- `--discover-bcs` eval + fixture for the offline/exported-board path: a completed Big Picture board's items supplied directly as an export (`evals/fixtures/big-picture-board-export.md`) run through Bounded Context Discovery mechanically, without requiring a Miro connection. Distinct from the existing board-URL scenario, which still requires Miro to read a live board.

## [0.3.0]

### Added

- `--design-level` deep dive now guards its prerequisite: when no prior Process Modeling board exists for the bounded context in `${CLAUDE_PLUGIN_DATA}/history.jsonl`, it surfaces the missing prerequisite and offers to run `--process-model` first instead of fabricating a process model or aggregates. Pinned by the new `design-level-missing-prerequisite` eval.

### Fixed

- Dangling bare "memory" references in the simulation skill's deep-dive and evaluation steps now use the `${CLAUDE_PLUGIN_DATA}/history.jsonl` run-state seam like every sibling reference.
