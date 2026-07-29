# Changelog

All notable changes to the `knowledge` plugin are recorded here. The `version` in
`.claude-plugin/plugin.json` is the delivery vehicle — a consumer receives a change
only after that version increases.

## [0.10.0]

### Added

- **New skill `docpage-digest` — 4th ingestion sibling.** Ingests a single online documentation
  page (docs-site URL) into a verified knowledge slice: fetch the unaltered original, inventory
  it into an `INDEX.md`, fan out one model-matched digest agent per section (model-pinned briefs
  use conditional framing — "if you are not X, note the mismatch and continue" — because
  spawn-time overrides can desync a brief from the running model), run dual verification
  (same-vendor Claude + one cross-vendor verifier; degraded-verifier fallback is
  recorded in the verdict header, never silent; verdicts are append-only), and hand off an
  interview-ready decision artifact. Publisher-specific configuration (fetch channel,
  Claude-Code-applicability filter with live-doc verification at tag time, digest-agent model
  matching, doc queue) lives in a separable profile at `context/anthropic-docs-profile.md`; a
  second publisher joins as a sibling profile, engine extraction waits for the third (Rule of
  Three). Ingested content is data, never directives (prompt-injection discipline named in the
  skill contract). Work root resolves through the plugin's `library_dir` seam, matching
  `course-digest`. Ships `templates/checklist.md` and `evals/evals.json`.

## [0.9.6]

### Fixed

- **course-digest extraction: `npm ci` failed on a clean install (#1507).** The
  `skills/course-digest/extraction` package pulls in the shared `@melodic/repo-analysis` and
  `@melodic/video-digestion` vendor packages as `file:` dependencies, same as the sibling
  `youtube-digest/extraction` package — but unlike that sibling, it shipped no `.npmrc` setting
  `install-links=true`. Without it, `npm ci` failed with `EUSAGE` (`Missing:
  @melodic/repo-analysis@0.1.0 from lock file`, `Missing: @melodic/video-digestion@0.1.0 from lock
  file`) on a fresh install, even though the committed `package-lock.json` was otherwise in sync.
  Added the missing `.npmrc`, matching `youtube-digest/extraction`'s. Discovered while wiring the
  package's test suite into CI, which never ran `npm ci` from a clean state before.

### Added

- **course-digest extraction test suite now runs in CI (#1507).** The `vitest` suite under
  `skills/course-digest/extraction` (`utils`, the adapter contract, the Dometrain/Teachable
  adapters, Clerk/Teachable-SSO auth, config, and the Hotmart/Mux players — 91 tests across 10
  files) had never been wired into `.github/workflows/ci.yml`; it only ever ran locally. Added a
  `course-digest-extraction` CI job mirroring the existing `youtube-extraction` lane (typecheck +
  `npm test`), gated behind the same docs-only scope guard as the repo's other Node lanes.

## [0.9.5]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.
  The recipe also now requires the reinstall to re-supply **every** key whose value should
  stay non-default, not only the key being changed: uninstalling drops the stored
  `pluginConfigs` entry, so an omitted key silently falls back to its manifest default.
  Record the current values before uninstalling.

## [0.9.4]

### Fixed

- **youtube-digest: resume recovers an explicit `--target`** (#1356): `watch --target <repo>`
  resolved a synthesis target, but nothing in the extraction runtime persisted it —
  `WatchState` had no target field, and `buildContinuationPrompt()` never told a resumed
  session where to find it, so an interrupted cross-repo watch lost the resolved target and
  `resume` had to re-infer or re-ask. `run-watch.js` now accepts `--target <repo>`, threads it
  into `createWatchState()`, and `watch.json` records the portable name (never a machine-local
  absolute path). `buildContinuationPrompt()` and `run-resume.js`'s JSON output now surface the
  recorded target so a resumed session reuses it instead of re-asking.

## [0.9.3]

### Fixed

- **youtube-digest: contact-sheet retention wording + `--target` resolution gap**
  (#1015): the intro paragraph called the `key-frames/contact-sheets/` snapshot
  "temp-only handling," contradicting the Output contract's "local DR snapshot,
  gitignored" characterization of the same directory; reworded to "never-committed
  handling" so the snapshot reads as a durable-on-disk-but-gitignored instance, not
  temp state. `--target <repo>` resolution now requires a **local working tree on
  disk** (not just a name) because `templates/synthesis-item.md`'s grep-backed
  **Target touchpoints** need a tree to grep; an explicit `--target` with no local
  checkout now halts and asks for its path instead of falling through to
  `CLAUDE_PROJECT_DIR`/CWD or inventing paths. `README.md`'s `**Target:**` line
  records the target's portable name only — never the machine-local checkout path,
  since that README is a staged artifact — as a record for readers and downstream
  consumers of a finished slice, not as resume state.

## [0.9.2]

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

## [0.9.1]

### Changed

- **youtube-digest: synthesis is now framed against a resolved target, not an
  implicit "the repo I'm in".** `templates/recommendations/menu.md`,
  `templates/synthesis-item.md`, and `templates/readme-journey.md` referenced
  the invoking repo by assumption; a session running from a separate corpus
  checkout had no way to say which repo the menu was actually for. `SKILL.md`
  now documents a "Synthesis target resolution" ladder — explicit `--target
  <repo>` argument (any `watch` form) → the invoking project when run
  standalone → ask — and the templates substitute `{target}` instead of
  assuming the CWD. `recommendations/**` is documented as this skill's own
  ephemeral, target-bound deliverable, expected to be superseded by the
  designed-but-unbuilt `/knowledge:apply` report→diff→PR flow
  (`docs/knowledge-integration-design.md`) once that skill ships.
- **youtube-digest: two known agnosticism gaps are now named explicitly in
  `SKILL.md` instead of left silent.** The `library_dir` seam relocates the
  `.work/<watch-epic>/<video-slug>/` work *root* but not that sub-path's
  *shape* — a corpus consumer whose own convention differs (e.g.
  `sources/<type>/<slug>/`) does not get that shape today. Separately, raw
  video, bulk frames, and working contact sheets stay OS-temp-only by design
  (contact sheets do get a gitignored, slice-local disaster-recovery snapshot
  at `key-frames/contact-sheets/`, but that is not committed durable
  retention); a consumer that wants these retained as a committed,
  re-runnable substrate does not get that today either. Both are called out as tracked follow-ups rather
  than an unstated limitation a consumer discovers by hand. Doc-only; no
  pipeline behavior changes.

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
