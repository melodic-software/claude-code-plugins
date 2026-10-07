# Changelog

All notable changes to the `playwright` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.10.0] - 2026-10-07

### Changed

- **Sessions are closed by name, not with `kill-all`.** The quick start no longer runs `kill-all` before every flow, and the conventions, `reference/sessions.md` and the orchestrator recipe say why: `close-all` and `kill-all` reach every playwright-cli browser on the machine, so they would end other agents' sessions in parallel work. Both stay as the recovery for a stuck daemon.
- **`SKILL.md` no longer restates upstream default values.** The defaults section keeps the decision (accept the defaults, override per command) and points at the upstream README and `open --help` with an as-of date and a recheck trigger; the video-size levers stay in `reference/tracing-and-video.md`.

### Added

- `## Gotchas` in `SKILL.md`, each observed in the browser-tools benchmark of 2026-10-07: `fill` not leaving the field on validate-on-blur forms, refs refused after a re-render, clicks landing before hydration, short-lived toasts outrunning per-command startup, reading `console` for uncaught exceptions, and the missing `chrome` channel on Linux containers.
- `## Next` naming the typical successors, `/source-control:pull-request` and `/verification:confirm`.
- A contents list on every reference file over 100 lines, per the skill-authoring guidance on long reference files.
- `snapshot --boxes` for geometry questions in `reference/snapshots-and-refs.md`, and `generate-locator` in `reference/test-generation.md`, both present upstream in 0.1.22.

## [0.9.0] - 2026-10-06

### Changed

- `reference/tracing-and-video.md` covers reading a failed `@playwright/test` run from the terminal: the `npx playwright trace` loop (1.59+), the error context (1.60+), and when to use each trace, screenshot and video retention mode. A routing row in `SKILL.md` points there.
- Test generation treats the spec as the oracle and the app as the subject: every `expect` traces to a requirement, and an outcome only observed on the page is marked unconfirmed. The heal step reads the retained trace first, and when the feature is broken it marks the test `test.fail()` or `test.fixme()` with the reason instead of patching the expectation.

## [0.8.11] - 2026-10-04

### Changed

- The `update` action's finishing steps name the repo's release record (a version bump plus CHANGELOG entry, or a changelog fragment where the repo uses them) instead of a version bump.

## [0.8.10] - 2026-10-04

### Changed

- **Synced `@playwright/cli` vendor baseline to 0.1.22.** `reference/tracing-and-video.md` now
  documents `video-start --size/--fps/--cursor`, `video-chapter`, and `video-show-actions` with its
  opt-in `--highlight-style`/`--point-style`/`--title-style` (the target highlight no longer shows
  unless styled), and says to always pass `--size` because the default fits 800×800. Also added the
  emulation (`set-color-scheme` and siblings), WebMCP, and `find --filename` commands, the headless
  idle shutdown, and the `run-code` sandbox limits. Upstream:
  [playwright-cli v0.1.20 to v0.1.22](https://github.com/microsoft/playwright-cli/releases).
- **Declared `gh` as an optional prerequisite.** The vendored skill now shows attaching
  screenshots and videos to a pull request with `gh pr comment --attach`.
- **Upstream records in the new reference text state our decision plus a live pointer.** The
  `run-code` login example passes the password from the shell instead of `process.env`.

## [0.8.9] - 2026-10-04

### Changed

- **Shared `prerequisites` checker copies synced ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)); no change to this plugin's behavior.**

## [0.8.8] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.8.7] - 2026-10-03

### Changed

- `skills/playwright/scripts/update.test.sh` declares the files it reads without naming them in a `# test-scope:` header, so CI's test selection runs it when one of them changes. Nothing the plugin runs changed.

## [0.8.6] - 2026-10-03

### Changed

- Shared `prerequisites.sh`, `prerequisites.ps1` synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)); no change to this plugin's own behavior.

## [0.8.5] - 2026-10-03

### Changed

- `prerequisites.json` is converted to the schema `docs/conventions/prerequisites/` owns: a `requires` list whose entries carry `id`, `kind`, `need`, `for`, `detect`, `degrade`, `install` and `check`, in place of the retired `tools` list, and now declares `node`, which the shared checker needs ([#5840](https://github.com/melodic-software/claude-code-plugins/issues/5840)). The plugin now ships the shared checker, `lib/prerequisites.mjs` with its `lib/prerequisites.sh` and `lib/prerequisites.ps1` stubs, generated from the repository's canonical copy.

## [0.8.4] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.8.3] - 2026-10-02

### Fixed

- The `setup` `argument-hint` uses Claude Code's official bracket notation: it leads with its check
  action and keeps alternatives inside brackets with an unspaced `|`.

## [0.8.2] - 2026-09-30

### Fixed

- **The Windows foreground helper command in `windows-quirks.md` resolves.** It cited the script through the literal plugin-root token, which does not expand in a reference file. It now reads `<skill-dir>/scripts/force-chrome-foreground.ps1`, and `SKILL.md` gains a `## Spoke paths` section saying `<skill-dir>` is the skill's directory.

## [0.8.1] - 2026-09-30

### Changed

- Test-only: the suites remove their temporary directories on exit. No behavior change.

## [0.8.0] - 2026-09-29

### Added

- **`/playwright:check`, a model-invocable read-only check.** It runs the `playwright-cli` probes from `/playwright:setup check` and installs nothing, so Claude can run it when a prerequisites report lists `playwright-cli` as missing. `disable-model-invocation` is a whole-skill flag, which keeps `/playwright:setup` manual.

### Changed

- `prerequisites.json` points at `/playwright:check` instead of the human-only `/playwright:setup check`, and the README names the check.

## [0.7.3] - 2026-09-28

### Changed

- **Missing external tools surface to the session, with a model-invocable check (#4240).** A `prerequisite` notice latches once per session and keeps its install route on renewal. Format hooks probe at session start. `/claude-ops:prerequisites` reads each plugin's `prerequisites.json` and does not install.

## [0.7.2] - 2026-09-27

### Changed

- **`setup` probes `playwright-cli` at load time.** The `command -v playwright-cli` check runs as
  pre-computed context, so `check` reads the result instead of making a Bash call. The FAIL rules
  are unchanged, a policy-disabled injection falls back to the Bash probe, and any post-remediation
  re-check still probes live.

## [0.7.1] - 2026-09-25

### Changed

- Comment-only pass with /code-tidying:dissolve-comments: restating comments, history narration and ticket back-references removed from scripts and tests, over-budget rationale shortened. Every edit is certified comment-only by a token-level proof, so behavior is unchanged; the removed text is recorded in the commit bodies.

## [0.7.0] - 2026-09-23

### Changed

- `playwright` answers visual questions (layout, overlap, color, a chart against its data) by
  reading the screenshot file itself with one specific question, since the snapshot YAML carries
  no layout, and shares the file path as evidence rather than retyping what it shows.

## [0.6.13]

### Changed

- The four update.sh copies (boris, skill-authoring, playwright, firecrawl) now share one idiom: a single tr call strips quotes and carriage returns from metadata fields, require_tool no longer carries a redundant return, and the firecrawl sha fetch uses the same short-circuit shape as its siblings. The two test suites drop an unread fixture variable.

## [0.6.12]

### Changed

- The markdown-format hook uses the shared hook-utils git-tree and dirname helpers instead of local copies, its suite and the powershell-format suite route repeated invocations through shared runners, and the mcp-tools discover, mutation-testing suppression-lint, and playwright update scripts fold duplicated blocks into helpers, with identical output.

## [0.6.11]

### Changed

- Cite the marketplace `docs/` doctrine files by their lower-kebab names (`docs/plugin-philosophy.md`, `docs/migration-playbook.md`, and siblings); the files were renamed and the old uppercase paths no longer resolve.

## [0.6.10]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **The plugin's prose drops its em dashes.** Eleven surfaces were rewritten: this changelog, `skills/playwright/actions/update.md`, and nine `skills/playwright/reference/` documents. Wording only, with no change to any command, flag, selector, or recipe. Four headings lost a dashed separator and so changed anchor (`## Video basics`, `## Video hero scripts (via run-code)`, `## Advanced mocking via run-code`, and `## Raw mode: pipe into jq, diff, and similar`); nothing in the repository linked to any of them. Em dashes inside fenced examples are left alone, because there they are sample output rather than this repository's prose. The released sections corrected in place are 0.6.5, 0.6.2, 0.6.0, 0.5.0, 0.4.0, and 0.3.0: their wording changed, their facts did not.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md`, every `skills/*/SKILL.md`, and the `skills/playwright/actions/` and `skills/playwright/reference/` trees. The vendored upstream tree stays excluded, because it is reference material rather than this repository's own writing.

## [0.6.9]

### Changed

- **playwright:** the description names intent categories instead of ten quoted phrases;
  `reference/tracing-and-video.md` replaces the six-step capture checklist with the two mechanics
  the flow does not make obvious and gives the frame-size measurements a dated verification record
  with a recheck trigger; `reference/windows-quirks.md` drops the section rebutting third-party
  speculation about the Unix-socket daemon, with the socket-error recovery kept on the `kill-all`
  line in `reference/sessions.md`; the login examples in `reference/storage-and-auth.md`,
  `reference/running-code.md`, and `reference/test-generation.md` read the password from
  `E2E_TEST_PASSWORD` instead of a literal, matching the file's own security invariant.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1
  (docs/specs/prompt-audit-skills-2026-09.md).

## [0.6.8]

### Changed

- **Synced `@playwright/cli` vendor baseline to 0.1.19.** Added distilled `recording-start` /
  `recording-stop` to `reference/commands.md` (record a user-driven browser flow as Playwright
  code). Corrected the trace output directory in `reference/tracing-and-video.md` to
  `.playwright-cli/traces/`. Upstream: [playwright-cli v0.1.19](https://github.com/microsoft/playwright-cli/releases/tag/v0.1.19).

## [0.6.7]

### Changed

- **`setup`: normalized the probe-don't-recite directive and repaired residual grammar defects.**
  The directive had fractured under the same per-plugin de-slop campaign;
  `docs/PLUGIN-PHILOSOPHY.md` now owns the rule under a `runtime-grounded` clause, and the eighteen
  sites that campaign fractured carry one wording. Twenty setup skills assert the rule; the other
  two, `context-guard` and `rate-limit-guard`, state it about their own scripts in their own words
  and are left for a separate pass, so the fleet is not yet down to a single form. Whole-repo
  extract-ssot sweep.

## [0.6.6]

### Changed

- **Authoring-doctrine pass over `skills/playwright/reference/test-generation.md`, `skills/playwright/reference/tracing-and-video.md`.** Fixed pointers and cross-references that did not resolve. Every edit was verified against the file by an agent that did not propose it. Prose only; no behavior, contract, or trigger phrase changed.

## [0.6.5]

### Changed

- **Unsourced "27K vs 114K / roughly 4x" token figure removed** from README and the skill description/body. The number is not in upstream `@playwright/cli`'s docs (checked 2026-08-26), matching this changelog's 0.5.0 precedent of dropping unsourced performance figures. The qualitative claim (artifacts on disk, only paths in context) stands. From the repo-wide derivability/point-dont-copy audit (PR #3387).

## [0.6.4]

### Changed

- **Three reference pointers front-load their subject.** `storage-and-auth.md` closed on a bare
  `See [running-code.md]` with no leading term and no statement of what the reader gets, and two
  pointers in `commands.md` opened on the routing verb rather than the term a reader matches on.
  Docs-hygiene sweep, L7-write-for-agents.

## [0.6.3]

### Changed

- **Instruction-surface de-slop (#2891, playwright cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. Vendored `skills/playwright/vendor/SKILL.md` is left
  untouched: it is detector-excluded upstream baseline, not a rewrite target.

## [0.6.2]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).
- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose, as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.6.1]

### Changed

- Synced vendored `@playwright/cli` baseline metadata to upstream v0.1.18 via
  `skills/playwright/scripts/update.sh --apply`. Upstream skill content is
  byte-identical to v0.1.17; no distilled `reference/*.md` integration required.

## [0.6.0]

### Fixed

- **`setup`'s pointer to the Windows-quirks reference names the skill that owns it**
  (`skills/playwright/reference/windows-quirks.md`). Written bare, it read as a file under `setup/`.

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command. The
  slash-command picker then echoed that back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.0]

### Added

- `reference/tracing-and-video.md` gains a **Frame size (two levers, not one)**
  section documenting `playwright-cli video-start --size "<W>x<H>"`, which the
  skill had never mentioned. Video frame size is derived from the viewport at
  browser-context creation and fitted into an 800×800 box, so the previously
  canonical bare `video-start demo.webm` recorded at 800×450 regardless of
  viewport intent, and `resize` afterwards did not change it. A correct
  recording needs two matched levers: `PLAYWRIGHT_MCP_VIEWPORT_SIZE` prefixed
  on `open` for what the page renders at, and `--size` for the output frame.
  The section tabulates the measured outcome of each partial combination.
  Also notes that the config file's `saveVideo` block is whole-session
  auto-save, a different mechanism from on-demand `video-start`.

### Changed

- The canonical video example now carries both size levers, with a neutral
  illustrative resolution, and the capture checklist points at the new section.
- `SKILL.md`'s "Defaults (accept, don't override)" section gains an explicit
  video-recording exception. The `1280×720` viewport row stays, because it is
  the correct CLI default, and so does the "don't put `PLAYWRIGHT_MCP_*` in
  project settings" posture. What was missing was the documented carve-out that
  video needs a per-command viewport prefix on `open`. Skill frontmatter is
  untouched.

### Fixed

- "Known costs" no longer claims "1280×720 WebM is ~5 MB/minute". The CLI never
  emits 1280×720 by default, and the figure was unsourced. It appears in no
  upstream or official Playwright documentation. Replaced with a qualitative
  statement that size scales with frame area and on-screen motion, rather than
  re-anchoring an invented number to a different resolution.

## [0.4.0]

### Added

- Synced vendored upstream baseline from `@playwright/cli@0.1.13` to `0.1.17`
  and folded the genuine new commands/flags into the distilled reference
  files: `find` (context-search a snapshot without capturing it all),
  `--hires` screenshots, `--mobile`/`--device=` emulation, and Windows
  `&`-in-URL shell-escaping guidance, all in `reference/commands.md`;
  `video-show-actions`/`video-hide-actions` auto-annotated video overlays in
  `reference/tracing-and-video.md`; and a distilled summary of the (now-merged)
  spec-driven plan/generate/heal workflow in `reference/test-generation.md`.
  That summary is self-contained rather than pointing normal use at `vendor/`,
  which this skill's own SKILL.md reserves for drift-detection reading only.

## [0.3.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. The vendored Apache-2.0 upstream license reference (shipped
  in-plugin) is unchanged. No behavior change.

## [0.3.1]

### Changed

- Artifact-naming example in the tracing/video reference drops the tracker-shaped
  `issue-123` filename token and the hardcoded `docs/evidence/` directory for
  agnostic `<artifact-dir>/<descriptive-name>` placeholders, so the destination
  comes from the consumer's own project conventions rather than presuming
  GitHub-integer issue numbering and a mandated evidence-directory layout.

## [0.3.0]

### Added

- **Uniform-contract `setup` skill** (fleet conformance wave). `/playwright:setup check` reads
  the main skill and its `reference/` files as the single source of truth and probes the
  `playwright-cli` binary and browser resolvability (surfacing the `install-browser` step and
  sandbox-egress caveat from the plugin's own docs). `apply` is guidance-and-verify with
  exactly one write path: the explicitly invoked `apply install-cli`, which runs the global
  `npm install -g @playwright/cli` (stated before running) and re-probes the binary
  afterward. It points at `/playwright:playwright update` for the vendored-baseline flow
  rather than wrapping it.

## [0.2.1]

### Added

- This changelog (fleet conformance wave: every versioned plugin ships a
  Keep-a-Changelog file).

## [0.2.0]

First versioned release covered by this changelog; see the git history of
`plugins/playwright/` for earlier changes.
