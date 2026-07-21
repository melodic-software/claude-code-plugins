# Changelog

All notable changes to the `knowledge` plugin are recorded here. The `version` in
`.claude-plugin/plugin.json` is the delivery vehicle — a consumer receives a change
only after that version increases.

## [0.9.1]

### Fixed

- **youtube-digest extraction: deterministic dev installs** (#905): `npm ci` in
  `skills/youtube-digest/extraction` failed from a clean checkout — the committed
  lockfile pins the shared `vendor/` packages as packed installs (the mode
  `setup-deps.mjs` uses via `--install-links`), while a plain `npm install`
  resolved them as symlinks, skipped their dependencies (`imghash`), and rewrote
  the lockfile into the mismatched link shape. A committed `.npmrc`
  (`install-links=true`) pins the packed mode for every install command, so dev
  installs match the runtime path and the lockfile stays stable. CI gains a
  `youtube-extraction` lane (clean `npm ci` + typecheck + vitest) so this drift
  class can no longer go latent.

## [0.9.0]

### Added

- **`library_dir` portable value forms** (#798): the seam now accepts a leading `~`
  (home-relative) and environment-variable references `${NAME}` / `%NAME%` (e.g.
  `${KNOWLEDGE_CORPUS_DIR}`) alongside the existing relative and absolute literals, so a
  machine-varying corpus root (a non-home drive, a per-machine checkout) never requires a
  literal machine-specific path in stored configuration — the form guardrail hardcoded-path
  checks block. The youtube-digest launcher (`run.mjs`) expands both forms in `--work-root`
  (`expandPathValue` in `lib/run-args.js`), failing loud on an unset variable or a
  non-absolute expansion; literal values pass through unchanged (back-compat). The
  youtube-digest artifact-landing contract, README option table, plugin manifest option
  description, and setup mismatch guidance document the forms. Env-var indirection was
  chosen over a ghq-derived scheme, which would couple the seam to ghq presence; a ghq user
  points the variable at the ghq-derived path instead.

## [0.8.4]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.8.3]

### Fixed

- **youtube-digest: resolved a self-contradiction in `SKILL.md` about `.work/`
  commit behavior.** The video-slug carve-out prose claimed the `.work/` root
  "self-ignores (a `.gitignore` containing `*`) and is never committed" — an
  unimplemented statement (no code writes a root `*` ignore) that directly
  contradicted the Output contract, where ~35 slice artifacts are marked
  `Staged: yes`. The prose now states the committed reality: slice artifacts are
  the durable substrate, staged and committed per the Output contract *when the
  resolved work root is not itself gitignored*, with the contact-sheet JPGs held
  out of git in every case by the per-directory `.gitignore` (`*.jpg`) that
  `snapshot-bootstrap.js` writes. It also surfaces the precondition the old text
  elided: a co-resident topic-docs convention self-ignores the shared repo-root
  `.work/` (default `memory_dir`), leaving slices local until the work root is
  relocated (e.g. a non-default `library_dir`). Doc-only; no pipeline behavior
  changes.

## [0.8.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.8.1]

### Changed

- **youtube-digest: the `variation-matrix-backlog.json` manual smoke-test log is
  demoted out of `evals/fixtures/`.** It is a tracking backlog of candidate videos
  across footage variations (status notes, blocked-caption records), not an
  input→expected-output graded fixture — no eval `files[]` entry or test consumed
  it. Moved to the skill's `reference/`; `SKILL.md` and vendor `TUNING.md` prose now
  point at the new path, and its grandfather line is removed from
  `scripts/orphaned-fixtures-baseline.txt`.

## [0.8.0]

### Changed

- **Setup adopts the uniform `check` / `apply` contract and covers the extraction
  prerequisites.** The read-only `check` (default) verifies `library_dir` against the
  repository's artifact convention and probes the shared node dependencies, Playwright
  Chromium, and the OS-level media tools (`yt-dlp`, `ffmpeg`, ImageMagick 7) as
  PASS/FAIL/INFO. `apply` routes `library_dir` changes through Claude Code's plugin
  configuration prompt (never hand-editing `pluginConfigs`); `apply install-deps` runs the
  youtube-digest and course-digest `setup-deps.mjs` provisioners — the same idempotent
  scripts the ingest skills already run — pulling the prerequisite/provisioning surface onto
  the setup contract. The personal env-channel scalars are unchanged.

## [0.7.1]

### Changed

- README declares the shell mechanics with their Windows path (Git Bash
  bundles the `sha256sum` that `book-distill` runs on every distillation) and
  the EPUB branch's `unzip` requirement (not bundled with Git Bash) —
  cross-platform declaration wave. PDF-only use needs neither extra install.

## [0.7.0]

### Changed

- **`youtube-digest` yt-dlp / throttle scalars migrated to personal `userConfig`.** Four
  options — `yt_dlp_js_runtimes` (string, default `node`; `off` omits `--js-runtimes`),
  `yt_dlp_cookies_file` (string, path to a Netscape cookies.txt), `yt_dlp_cookies_from_browser`
  (string, e.g. `chrome`/`firefox`/`edge`), and `max_concurrent_acquires` (number, default 1,
  1–3) — are now configured through Claude Code's plugin-configuration prompt and wired into the
  extraction pipeline as leading `run.mjs` flags (`--js-runtimes`, `--cookies-file`,
  `--cookies-from-browser`, `--max-concurrent-acquires`), exactly as `library_dir` wires
  `--work-root`. The launcher translates each flag into the environment variable the extraction
  child already reads.
- **BREAKING: the `YOUTUBE_YT_DLP_JS_RUNTIMES`, `YOUTUBE_YT_DLP_COOKIES_FILE`,
  `YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER`, and `YOUTUBE_MAX_CONCURRENT_ACQUIRES` shell env vars are
  no longer a documented consumer channel.** Configure the four options above instead. The env
  vars remain only as the internal launcher-to-child interface `run.mjs` sets from those options;
  setting them by hand in your shell is no longer supported. Zero-config behavior is unchanged —
  unset options contribute no flag and the pipeline keeps its built-in defaults.

### Notes

- **Course-platform credentials deliberately remain shell env vars.** `COURSE_*` / `TEACHABLE_*`
  are excluded from this migration: a `sensitive: true` userConfig option still persists as
  plaintext in `~/.claude/.credentials.json` on Windows, so those secrets stay in shell env until
  keychain-backed sensitive storage lands there (documented at the course-digest auth-env site).

## [0.6.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.6.0]

### Changed

- **BREAKING: `youtube` skill renamed to `youtube-digest`.** Invoke as
  `/knowledge:youtube-digest` (previously `/knowledge:youtube`). Sibling skills follow a
  source+operation grammar (`book-distill`, `course-digest`); the platform noun alone named
  the source but not the operation. Triggers are unchanged — "youtube", "watch this YouTube
  video", and youtube.com/youtu.be URLs still route to the skill. In-flight watch slices are
  unaffected (`.work/<watch-epic>/...` layout is unchanged); resume with
  `/knowledge:youtube-digest resume <video-slug>`.

## [0.5.6]

### Added

- Revisit condition in the README recording when the bundled `youtube` skill would
  graduate into a standalone plugin (once its vendored `video-digestion` package is
  independently distributable).

## [0.5.5]

### Fixed

- **Lossless WebVTT transcript extraction.** Cue cleanup still strips complete WebVTT tags in one
  linear pass, but now preserves an unmatched literal less-than tail instead of truncating the rest
  of programming, mathematics, or other tolerant transcript text.

## [0.5.4]

### Fixed

- **Current Claude Code configuration contract.** Setup now treats `library_dir` as a personal
  `userConfig` option, validates it against the consuming repository's artifact convention, and
  routes changes through Claude Code's configuration prompt instead of editing unsupported
  project/local `pluginConfigs` entries.
- **Repository and transcript input hardening.** GitHub repository URLs now require an exact,
  credential-free GitHub HTTPS or SSH shape before canonical clone arguments are constructed;
  clone option parsing is terminated explicitly; and WebVTT/entity cleanup uses bounded,
  single-pass transformations that cannot turn nested malformed input into active markup.

## [0.5.3]

### Changed

- **Aligned with the marketplace topic-docs convention** (`docs/conventions/topic-docs/`).
  Setup's convention inference now points at the `.claude/topic-docs.yaml` concern file and
  the `.work/` memory tier (the retired `.claude/notes/` location is no signal — the contract
  is a clean break), and the youtube/course-digest skills carry the contract's **formal carve-out**
  note (the work root resolves through this plugin's `library_dir` seam, not the concern file's
  `memory_dir`; slug conformance is form-only; nested `<epic>/<slug>/` sub-slices are
  sanctioned), linking the convention by its canonical URL. The youtube slice-lane rationale
  now records that the `verification/` lane name matches the convention's canon. Docs-only —
  no paths or behavior change; the `library_dir` seam is untouched.

## [0.5.2]

### Fixed

- **YouTube extraction — crash/incorrect-output paths on normal use.** Recovery
  (`--recover`/`resume`) now accepts an auto-caption-only `*-orig.vtt` instead of
  throwing `Missing mp4/vtt/info.json`; `watch.json` + tempSession are persisted
  before the long extraction phase so an interrupt there stays recoverable;
  exact cue/densification anchor timestamps survive the second dedup pass instead
  of being replaced by fabricated ordinals; harvested GitHub deep links are cloned
  from the canonical `https://github.com/<owner>/<repo>` URL rather than the
  un-cloneable deep link; the documented `companion` Phase 0b marker is accepted;
  recovery is no longer advertised when the acquisition `workDir` is gone;
  `--skip-research` is persisted so resume doesn't re-route into research;
  marking the terminal `synthesis` phase sets `watch.status` to `complete` so the
  blocking checklist is enforced; `resume` advertises the on-disk continuation-prompt
  path; the research gate requires a `research-agenda.md`; and contact-sheet snapshots
  write a local `.gitignore` so the JPG binaries can't be committed.
- **YouTube extraction — hardening.** Deck/attachment fetches stream to disk under a
  500 MB cap (byte-counted, not just `content-length`) instead of buffering the whole
  attacker-controlled response; the acquire throttle gained an optional overall
  `timeoutMs` and heartbeats a held slot's mtime so a long download isn't misclassified
  as stale and reclaimed; clone paths sanitize Windows-reserved characters; acquisition
  forces `--no-playlist`; and a passing key-frame quality-audit row now requires a
  substantive evidence note (an omitted note no longer bypasses the gate).

## [0.5.1]

### Changed

- **Vendored shared libraries deduplicated to one plugin-wide copy.** `@melodic/repo-analysis`
  and `@melodic/video-digestion` were vendored separately under both
  `skills/youtube/extraction/vendor/` and `skills/course-digest/extraction/vendor/`. They now
  live once at the plugin root (`vendor/`); each skill's `extraction/package.json` links it via
  `file:../../../vendor/*` and each `setup-deps.mjs` fingerprints the shared tree. Runtime install
  into `${CLAUDE_PLUGIN_DATA}` is unchanged. Internal restructure — no consumer-facing behavior
  change; the version bump delivers the moved source (and the new install fingerprint) to consumers.

## [0.5.0]

### Added

- **`course-digest` skill** (`/knowledge:course-digest`) — extract and synthesize
  online video courses (Dometrain, Teachable) into repo-applicable recommendations:
  browser-automation transcript + frame extraction, code-companion analysis, and
  multi-modal synthesis. Actions: full pipeline, `extract`, `analyze`, `status`,
  `resume`, `continue`.
- Bundled `extraction/` node pipeline for the course-digest skill, with the two
  shared libraries (`@melodic/repo-analysis`, `@melodic/video-digestion`) vendored
  under `extraction/vendor/`. Dependencies install into `${CLAUDE_PLUGIN_DATA}` via
  `skills/course-digest/extraction/setup-deps.mjs`, which also provisions Playwright's
  Chromium into `${CLAUDE_PLUGIN_DATA}/ms-playwright` (idempotent; re-run after a
  plugin update). ffmpeg and ImageMagick remain OS-level installs the skill's
  Prerequisites section documents.

### Changed

- **Credential model** — course-platform login uses the user's own shell env vars
  (`COURSE_*`/`TEACHABLE_*`, prefix driven by `platformConfig.authEnvPrefix`) with an
  interactive manual-login fallback. Session cookies persist under
  `${CLAUDE_PLUGIN_DATA}/auth/<platform>.auth-state.json` (out of the consumer repo),
  keyed per platform.

### Notes

- The course-digest pipeline is ESM and shares the youtube skill's launcher shape
  (`run.mjs` ESM resolve hook so bundled deps resolve from `${CLAUDE_PLUGIN_DATA}`);
  `run.mjs` additionally pins `PLAYWRIGHT_BROWSERS_PATH` to the data directory so the
  browser binary resolves regardless of cwd.
- Manual login (`node:readline` + headed browser) may not function under headless
  plugin execution; env-var + cookie-reuse carry the skill regardless.
- `repo-analysis` and `video-digestion` are now vendored by both the youtube and
  course-digest skills. Deduplication of the two copies is tracked separately.

## [0.4.0]

### Changed

- **`youtube` skill now honors the `library_dir` seam.** The invoking skill wires a
  non-default `library_dir` into the extraction pipeline by passing
  `run.mjs --work-root <dir>`, which the launcher translates into the
  `YOUTUBE_WORK_ROOT` environment variable the scripts already read — so watch,
  transcript, and queue artifacts land under the configured directory instead of
  always at the consuming repo root. Agent-written slice artifacts (the queue table,
  its claim stubs, and every Output-contract deliverable) anchor to the same resolved
  root, so a non-default `library_dir` never splits a slice across two directories. The default (`.`) path is unchanged: no flag,
  `resolveWorkRoot()` keeps its `CLAUDE_PROJECT_DIR` → `process.cwd()` fallback. A
  double-quoted CLI arg was chosen over an inline `YOUTUBE_WORK_ROOT=… node` prefix
  because the latter is bash-only and fails under PowerShell.
- **`setup` Output** now states that `library_dir` governs where youtube artifacts
  land, restoring the stronger wording softened while the seam was unwired
  (`book-distill` remains the documented exception).

## [0.3.0]

### Changed

- **`setup` skill** — retrofit `library_dir` precedence resolution and portability
  hardening so synthesized artifacts land at the configured library directory in the
  consuming repo.

## [0.2.0]

### Added

- **`youtube` skill** (`/knowledge:youtube`) — watch a single public YouTube video
  (transcript + visual frames), harvest reference links, drive external research,
  and synthesize a prioritized repo-applicability menu. Actions: `watch`, `queue`,
  `transcript`, `resume`.
- Bundled `extraction/` node pipeline for the youtube skill. Its dependencies are
  installed into `${CLAUDE_PLUGIN_DATA}` on first use via
  `skills/youtube/extraction/setup-deps.mjs` (idempotent; re-run after a plugin
  update). Media binaries (`yt-dlp`, `ffmpeg`, ImageMagick) remain OS-level installs
  the skill's Prerequisites section documents.

### Notes

- The youtube pipeline is ESM. Its entry points run through
  `skills/youtube/extraction/run.mjs`, which injects an ESM resolve hook so bundled
  dependencies resolve from `${CLAUDE_PLUGIN_DATA}` (NODE_PATH is CommonJS-only and
  does not apply).

## [0.1.1]

- Prior baseline: `book-distill` and `setup` skills.
