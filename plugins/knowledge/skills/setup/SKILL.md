---
description: "Verify the knowledge artifact-root configuration and extraction prerequisites, or provision the video-pipeline dependencies. Use when: 'set up knowledge', 'configure knowledge', 'is knowledge ready', or 'where do knowledge artifacts land'. Actions: check (read-only verification, default) | apply (resolve what check found) | apply install-deps (provision the extraction node deps + Chromium)."
argument-hint: "check | apply [install-deps]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Bring the knowledge plugin to a working state: confirm the effective `library_dir` against this
repository's artifact convention, and verify (or provision) the extraction pipelines'
prerequisites. `library_dir` is a personal `userConfig` option. Claude Code prompts for it when
the plugin is enabled, stores non-sensitive options in user settings, and ignores project/local
`pluginConfigs` entries on current releases.

Official contract: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

Check-centric per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves what `check` found, and the extraction-dependency provisioning is a
distinct opt-in subaction. The `library_dir` option is Claude-Code-owned; this skill never
writes it, only reports and routes.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then the
`library_dir` guidance; `apply install-deps` additionally provisions the extraction dependencies
below. All actions are non-interactive when the action is given, never prompt.

## `check` (read-only)

Report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not edit settings, write
config, or install anything.

1. **`library_dir` vs repository convention.** Read the rendered `${user_config.library_dir}`
   value (default `.` = repository root). Inspect the consumer's `CLAUDE.md`, `AGENTS.md`,
   `.claude/rules`, and existing artifact directories for a declared knowledge/artifact
   convention, the team source of truth. Do not infer `library_dir` from `.claude/topic-docs.yaml`
   or its `memory_dir`: topic-docs governs lifecycle working documents, while `library_dir` owns the
   knowledge corpus. Mapping both to `.work` would nest the YouTube pipeline's own
   `.work/<watch-epic>/...` layout as `.work/.work/...`. PASS when the personal value matches the
   convention (or the portable `.` default with no distinct convention). FAIL on a mismatch
   (remediation: Claude Code's plugin configuration prompt for `knowledge`) or a machine-absolute
   path (not portable for repository work).
2. **Extraction node deps**. INFO. Probe whether
   `${CLAUDE_PLUGIN_DATA}/node_modules/@melodic/video-digestion` exists (the video-digest and
   course-digest pipelines share it). Missing is INFO, not FAIL: each ingest skill self-provisions
   on first run, and `apply install-deps` pre-provisions. Remediation: `apply install-deps`.
3. **Playwright Chromium**. INFO. Probe whether the browsers path
   (`PLAYWRIGHT_BROWSERS_PATH`, else `${CLAUDE_PLUGIN_DATA}/ms-playwright`) holds a `chromium-*`
   or `chromium_headless_shell-*` build (course-digest frame capture). Missing is INFO with
   remediation `apply install-deps`.
4. **OS-level media tools**. INFO. Probe `yt-dlp --version` (youtube acquisition), `ffmpeg
   -version` (frame extraction — watch/course actions), and `magick -version` (ImageMagick 7,
   contact sheets. Watch/course actions). Each absence is INFO with the platform install command
   from the ingest skill's Prerequisites; this skill never installs system packages. `book-distill`
   (PDF) needs none of these.

## `apply` (idempotent)

Run `check`, then resolve each finding. Re-running after everything passes changes nothing and
reports "already configured".

1. **`library_dir` mismatch. Guidance only.** `library_dir` is a personal `userConfig` scalar;
   never hand-edit `pluginConfigs` or write Claude Code settings. Direct the user to
   `/plugin configure knowledge` (interactive, any time). Headless: rerun the install with the new
   value. `claude plugin install knowledge@<marketplace> -s <scope> --config library_dir=<value>`.
   Against an already-installed plugin it prints `already installed` **and still writes the value**
Verified on Claude Code 2.1.240 (a non-sensitive option at `user` scope: a non-default value
   written to an installed plugin, then restored). The short-circuit is about the install, not the
   config write. Re-verify before relying on it outside those conditions, a `sensitive` option, or
   `project`/`local` scope, were not covered. Do **not** uninstall to reconfigure: uninstalling
   drops this plugin's entire stored `pluginConfigs` entry, resetting every option in the README's
   Options reference table to its manifest default, which can break extraction on a machine that
   needed non-default acquisition or `yt-dlp` values. `-s` defaults to `user`, so pass the scope
   `claude plugin list` reports for this plugin, and run from that project's directory for a
   `project`/`local` scope, or the write lands at a scope that does not load.
   The rendered value is injected at skill load,
   so a change takes effect in a fresh session. Report the observed value and defer verification
   to that fresh session; do not claim a change this session.
   For a root outside the project and home directories, recommend the portable value forms from the
   README's option table (`~` prefix or `${NAME}` / `%NAME%` env-var reference) instead of a literal
   machine path, which guardrail hardcoded-path checks rightly block.
2. **`apply install-deps`. Provision the extraction dependencies.** Only with this subaction, run
   both idempotent provisioners (each installs the vendored node dependencies into
   `${CLAUDE_PLUGIN_DATA}`, and course-digest additionally provisions Chromium into
   `${CLAUDE_PLUGIN_DATA}/ms-playwright`):

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/setup-deps.mjs"
   node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/setup-deps.mjs"
   ```

   A stored fingerprint gates reinstalls, so re-running is safe and cheap. After provisioning,
   re-run the `check` node-deps and Chromium probes and report their actual results, never claim
   provisioned on the script exit codes alone.
3. **OS-level media tools. Guidance only.** For a missing `yt-dlp`, `ffmpeg`, or ImageMagick 7,
   give the platform install command from the ingest skill's Prerequisites. This skill never
   installs system packages.
4. **Confirm.** Report the observed `library_dir`, the repository convention and any mismatch, and
   whether extraction dependencies were provisioned or intentionally skipped. Note that
   `/knowledge:book-distill` writes to its explicitly named target skill rather than this seam.

## Output

Report the observed personal value, the repository convention, any mismatch, the state of each
prerequisite, and the exact next action (`/plugin configure knowledge` for `library_dir`,
or `apply install-deps` for provisioning). A `library_dir` change takes effect in a fresh session,
not this one. Do not claim it this session.

## Boundaries

- Do not run an ingestion pipeline. Provisioning dependencies is not the same as running one.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Do not invent organization-specific paths or environment-variable prefixes.
