---
name: setup
description: "Verify the knowledge artifact-root configuration and extraction prerequisites, or provision the video-pipeline dependencies. Use when: 'set up knowledge', 'configure knowledge', 'is knowledge ready', or 'where do knowledge artifacts land'. Actions: check (read-only verification, default) | apply (resolve what check found) | apply install-deps (provision the extraction node deps + Chromium)."
argument-hint: "check | apply [install-deps]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Bring the knowledge plugin to a working state: confirm the effective `library_dir` against this
repository's artifact convention, and verify (or provision) the extraction pipelines'
prerequisites. `library_dir` is a personal `userConfig` option — Claude Code prompts for it when
the plugin is enabled, stores non-sensitive options in user settings, and ignores project/local
`pluginConfigs` entries on current releases.

Official contract: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

Check-centric per the uniform contract: `check` inspects and reports, `apply` resolves what
`check` found, and the extraction-dependency provisioning is a distinct opt-in subaction. The
`library_dir` option is Claude-Code-owned; this skill never writes it, only reports and routes.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then the
`library_dir` guidance; `apply install-deps` additionally provisions the extraction dependencies
below. All actions are non-interactive when the action is given — never prompt.

## `check` (read-only)

Report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not edit settings, write
config, or install anything.

1. **`library_dir` vs repository convention.** Read the rendered `${user_config.library_dir}`
   value (default `.` = repository root). Inspect the consumer's `CLAUDE.md`, `AGENTS.md`,
   `.claude/rules`, and existing artifact directories for a declared knowledge/artifact
   convention — the team source of truth. Do not infer `library_dir` from `.claude/topic-docs.yaml`
   or its `memory_dir`: topic-docs governs lifecycle working documents, while `library_dir` owns the
   knowledge corpus. Mapping both to `.work` would nest the YouTube pipeline's own
   `.work/<watch-epic>/...` layout as `.work/.work/...`. PASS when the personal value matches the
   convention (or the portable `.` default with no distinct convention). FAIL on a mismatch
   (remediation: Claude Code's plugin configuration prompt for `knowledge`) or a machine-absolute
   path (not portable for repository work).
2. **Extraction node deps** — INFO. Probe whether
   `${CLAUDE_PLUGIN_DATA}/node_modules/@melodic/video-digestion` exists (the youtube-digest and
   course-digest pipelines share it). Missing is INFO, not FAIL: each ingest skill self-provisions
   on first run, and `apply install-deps` pre-provisions. Remediation: `apply install-deps`.
3. **Playwright Chromium** — INFO. Probe whether the browsers path
   (`PLAYWRIGHT_BROWSERS_PATH`, else `${CLAUDE_PLUGIN_DATA}/ms-playwright`) holds a `chromium-*`
   or `chromium_headless_shell-*` build (course-digest frame capture). Missing is INFO with
   remediation `apply install-deps`.
4. **OS-level media tools** — INFO. Probe `yt-dlp --version` (youtube acquisition), `ffmpeg
   -version` (frame extraction — watch/course actions), and `magick -version` (ImageMagick 7,
   contact sheets — watch/course actions). Each absence is INFO with the platform install command
   from the ingest skill's Prerequisites; this skill never installs system packages. `book-distill`
   (PDF) needs none of these.

## `apply` (idempotent)

Run `check`, then resolve each finding. Re-running after everything passes changes nothing and
reports "already configured".

1. **`library_dir` mismatch — guidance only.** `library_dir` is a personal `userConfig` scalar;
   never hand-edit `pluginConfigs` or write Claude Code settings. Direct the user to
   `/plugin configure knowledge` (interactive, any time). Headless: `--config` only applies on a
   fresh install (ignored once installed), so reconfigure via
   `claude plugin uninstall knowledge -s <scope>` then
   `claude plugin install knowledge@<marketplace> -s <scope> --config library_dir=<value>`. Both
   commands default to `-s user` — pass the scope `claude plugin list` reports for this plugin,
   and run from that project's directory for a `project`/`local` scope. Defaulting instead
   uninstalls a separate user-scope record while the effective install stays in place, so the
   reinstall lands at a scope that does not load. Uninstalling also drops the stored
   `pluginConfigs` entry, so the reinstall must re-supply **every** key whose value should stay
   non-default — passing only `library_dir` silently resets `max_concurrent_acquires`,
   `yt_dlp_cookies_file`, `yt_dlp_cookies_from_browser`, and `yt_dlp_js_runtimes` to their
   manifest defaults, which can break extraction on a machine that needed them. Record the current
   values before uninstalling; afterwards there is nothing left to read them from.
   The rendered value is injected at skill load,
   so a change takes effect in a fresh session — report the observed value and defer verification
   to that fresh session; do not claim a change this session.
   For a root outside the project and home directories, recommend the portable value forms from the
   README's option table (`~` prefix or `${NAME}` / `%NAME%` env-var reference) instead of a literal
   machine path, which guardrail hardcoded-path checks rightly block.
2. **`apply install-deps` — provision the extraction dependencies.** Only with this subaction, run
   both idempotent provisioners (each installs the vendored node dependencies into
   `${CLAUDE_PLUGIN_DATA}`, and course-digest additionally provisions Chromium into
   `${CLAUDE_PLUGIN_DATA}/ms-playwright`):

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/setup-deps.mjs"
   node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/setup-deps.mjs"
   ```

   A stored fingerprint gates reinstalls, so re-running is safe and cheap. After provisioning,
   re-run the `check` node-deps and Chromium probes and report their actual results — never claim
   provisioned on the script exit codes alone.
3. **OS-level media tools — guidance only.** For a missing `yt-dlp`, `ffmpeg`, or ImageMagick 7,
   give the platform install command from the ingest skill's Prerequisites. This skill never
   installs system packages.
4. **Confirm.** Report the observed `library_dir`, the repository convention and any mismatch, and
   whether extraction dependencies were provisioned or intentionally skipped. Note that
   `/knowledge:book-distill` writes to its explicitly named target skill rather than this seam.

## Output

Report the observed personal value, the repository convention, any mismatch, the state of each
prerequisite, and the exact next action (`/plugin configure knowledge` for `library_dir`,
or `apply install-deps` for provisioning). A `library_dir` change takes effect in a fresh session,
not this one — do not claim it this session.

## Boundaries

- Do not run an ingestion pipeline — provisioning dependencies is not the same as running one.
- Do not write Claude Code settings or `pluginConfigs`.
- Do not invent organization-specific paths or environment-variable prefixes.
