---
description: "Report (check, the default) or resolve (apply) the knowledge plugin's library_dir against the repository's artifact convention and its extraction prerequisites; apply install-deps provisions the extraction node deps and Chromium."
argument-hint: "[check|apply] [install-deps]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Bring the knowledge plugin to a working state: confirm the effective `library_dir` against this
repository's artifact convention, and verify (or provision) the extraction pipelines'
prerequisites. `library_dir` is a personal `userConfig` option that Claude Code prompts for and
stores; this skill reports where the effective value came from and never writes it.

- **Pointer**: when deciding where a `library_dir` value is stored and which settings scopes are
  read for it, fetch
  <https://code.claude.com/docs/en/plugins/manifest-reference#where-values-are-stored> and
  <https://code.claude.com/docs/en/settings-reference#pluginconfigs> live; the option contract is
  <https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration>.

Check-centric per the uniform setup contract (`docs/plugin-philosophy.md`
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
   convention, the team source of truth. Do not infer `library_dir` from the lifecycle
   `memory_dir`: the memory root holds lifecycle working documents, while `library_dir` owns the
   knowledge corpus. Mapping both to `.work` would nest the video-digest pipeline's own
   `.work/<watch-epic>/...` layout as `.work/.work/...`. PASS when the personal value matches the
   convention (or the portable `.` default with no distinct convention). FAIL on a mismatch
   (remediation: Claude Code's plugin configuration prompt for `knowledge`) or a machine-absolute
   path (not portable for repository work).
2. **`upstream_records_dir`**. INFO. Report the directory `/knowledge:absorb-upstream` writes to
   and its layer: `upstream_records_dir` in `<home>/knowledge.yaml` (`<home>` from the pointer
   region of `AGENTS.md` or `CLAUDE.md`, else `docs/conventions`), else the default
   `docs/upstream`, under the root rule and value rules of
   `${CLAUDE_PLUGIN_ROOT}/reference/config.md`. An invalid value is a FAIL naming the file, key and
   value (remediation: edit the team file by hand; `apply` does not write it).
3. **Extraction node deps**. INFO. Probe whether
   `${CLAUDE_PLUGIN_DATA}/node_modules/@melodic/video-digestion` exists (the video-digest and
   course-digest pipelines share it). Missing is INFO, not FAIL: each ingest skill self-provisions
   on first run, and `apply install-deps` pre-provisions. Remediation: `apply install-deps`.
4. **Playwright Chromium**. INFO. Probe whether the browsers path
   (`PLAYWRIGHT_BROWSERS_PATH`, else `${CLAUDE_PLUGIN_DATA}/ms-playwright`) holds a `chromium-*`
   or `chromium_headless_shell-*` build (course-digest frame capture). Missing is INFO with
   remediation `apply install-deps`.
5. **OS-level media tools**. INFO. Probe `yt-dlp --version` (video acquisition), `ffmpeg
   -version` (frame extraction, watch/course actions), and `magick -version` (ImageMagick 7,
   contact sheets. Watch/course actions). Each absence is INFO with the platform install command
   from the ingest skill's Prerequisites; this skill never installs system packages. `distill`
   (PDF) needs none of these.

## `apply` (idempotent)

Run `check`, then resolve each finding. Re-running after everything passes changes nothing and
reports "already configured".

1. **`library_dir` mismatch. Guidance only.** `library_dir` is a personal `userConfig` scalar;
   never hand-edit `pluginConfigs` or write Claude Code settings. Reconfigure `library_dir`
   through Claude Code's native flow, interactively with
   `/plugin configure knowledge@<marketplace>` or by a headless route, as the marketplace's
   plugin-reconfiguration convention gives them in
   [§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
   (it owns the verified-version record). Apply the scope and failure-signal caveats in its
   [§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
   Read both sections and print what they give, the fallback route, its behavior on an
   already-installed plugin and the scope to pass included, rather than only naming them, and
   leave out the verified-version record.
   Never uninstall to reconfigure; that section links what an uninstall deletes. Afterwards rerun
   `check` in a **fresh session**, since a same-session `check` can still show the old value, and
   report the observed effective value, never an unobserved change.

   - **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
     when a saved value applies, fetch
     [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
     live.

   For where `${user_config.*}` resolves, see
   [Plugin manifest reference: Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value).
   For a root outside the project and home directories, recommend the portable value forms from the
   README's option table (`~` prefix or `${NAME}` / `%NAME%` env-var reference) instead of a literal
   machine path, which guardrail hardcoded-path checks rightly block.
2. **`apply install-deps`. Provision the extraction dependencies.** Only with this subaction, run
   the shared idempotent provisioner once per extraction package (each run installs that
   package's vendored node dependencies into `${CLAUDE_PLUGIN_DATA}`, and the course-digest run
   additionally provisions Chromium into `${CLAUDE_PLUGIN_DATA}/ms-playwright`):

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/vendor/node-launcher/setup-deps.mjs" --data-dir "${CLAUDE_PLUGIN_DATA}" --package "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction"
   node "${CLAUDE_PLUGIN_ROOT}/vendor/node-launcher/setup-deps.mjs" --data-dir "${CLAUDE_PLUGIN_DATA}" --package "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction"
   ```

   A stored fingerprint gates reinstalls, so re-running is safe and cheap. After provisioning,
   re-run the `check` node-deps and Chromium probes and report their actual results, never claim
   provisioned on the script exit codes alone.
3. **Invalid `upstream_records_dir`. Guidance only.** Name the file, key and value and the valid
   forms from `${CLAUDE_PLUGIN_ROOT}/reference/config.md`; never write the team file.
4. **OS-level media tools. Guidance only.** For a missing `yt-dlp`, `ffmpeg`, or ImageMagick 7,
   give the platform install command from the ingest skill's Prerequisites. This skill never
   installs system packages.
5. **Confirm.** Report the observed `library_dir`, the repository convention and any mismatch, and
   whether extraction dependencies were provisioned or intentionally skipped. Note that
   `/knowledge:distill` writes to its explicitly named target skill rather than this setting.

## Output

Report the observed personal value, the repository convention, any mismatch, the state of each
prerequisite, and the exact next action (`/plugin configure knowledge` for `library_dir`,
or `apply install-deps` for provisioning). A `library_dir` change takes effect in a fresh session,
not this one. Do not claim it this session.

## Boundaries

- Do not run an ingestion pipeline. Provisioning dependencies is not the same as running one.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Do not invent organization-specific paths or environment-variable prefixes.
