---
description: "Report (check, the default) or resolve (apply) the knowledge plugin's library_dir against the repository's artifact convention and its extraction prerequisites; apply install-deps provisions the extraction node deps and Chromium."
argument-hint: "[check|apply] [install-deps]"
user-invocable: true
disable-model-invocation: true
---

Confirm the effective `library_dir` against this repository's artifact convention, and verify (or
provision) the extraction pipelines' prerequisites. `library_dir` is a personal `userConfig`
option Claude Code prompts for and stores; this skill reports where the effective value came from
and never writes it.

- **Pointer**: when deciding where a `library_dir` value is stored and which settings scopes are
  read for it, fetch
  <https://code.claude.com/docs/en/plugins/manifest-reference#where-values-are-stored> and
  <https://code.claude.com/docs/en/settings-reference#pluginconfigs> live; the option contract is
  <https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration>.
- **As of**: 2026-10-11
- **Recheck trigger**: either section changes where non-sensitive option values are stored or
  which settings scopes a `pluginConfigs` entry is read from.

Check-centric per the uniform setup contract (`docs/plugin-philosophy.md` "Setup is explicit and
repeatable" in the marketplace repository). Action routing: no argument or `check` runs the check; `apply` runs the check, then resolves its
findings; `apply install-deps` also provisions the extraction dependencies. Never prompt when the
action is given.

## `check` (read-only)

Report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not edit settings, write
config, or install anything.

1. **`library_dir` vs repository convention.** Read the rendered `${user_config.library_dir}`
   (default `.`, the repository root). Look for a declared knowledge or artifact convention in the
   consumer's `CLAUDE.md`, `AGENTS.md`, `.claude/rules` and existing artifact directories; that convention is the team source of
   truth. Do not infer `library_dir` from the lifecycle `memory_dir`: mapping both to `.work` nests the
   video-digest pipeline's `.work/<watch-epic>/...` layout as `.work/.work/...`. PASS when the
   value matches the convention, or is the `.` default with no distinct convention. FAIL on a
   mismatch (remediation: Claude Code's plugin configuration for `knowledge`) or a
   machine-absolute path (not portable).
2. **Extraction node deps.** INFO. Probe for
   `${CLAUDE_PLUGIN_DATA}/node_modules/@melodic/video-digestion` (shared by video-digest and
   course-digest). Missing is INFO, not FAIL, because each ingest skill self-provisions on first
   run. Remediation: `apply install-deps`.
3. **Playwright Chromium.** INFO. Probe whether `PLAYWRIGHT_BROWSERS_PATH`, else
   `${CLAUDE_PLUGIN_DATA}/ms-playwright`, holds a `chromium-*` or `chromium_headless_shell-*`
   build (course-digest frame capture). Remediation: `apply install-deps`.
4. **OS-level media tools.** INFO. Probe `yt-dlp --version` (video acquisition), `ffmpeg -version`
   (frame extraction, watch/course actions) and `magick -version` (ImageMagick 7, contact sheets,
   watch/course actions). Each absence is INFO with the platform install command from
   the ingest skill's Prerequisites. `book-distill` needs none of these.

## `apply` (idempotent)

Run `check`, then resolve each finding. When everything already passes, change nothing and report
"already configured".

1. **`library_dir` mismatch: guidance only.** Never hand-edit `pluginConfigs` or write Claude
   Code settings. Route the user to Claude Code's native flow per the
   [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md),
   which owns the verified-version record: interactive `/plugin configure knowledge@<marketplace>`,
   or headless `claude plugin install knowledge@<marketplace> -s <scope> --config library_dir=<value>`
   (repeatable per key; on an installed plugin it prints `already installed` and still writes the
   value).
   - Do **not** uninstall to reconfigure: that drops the whole stored `pluginConfigs` entry and
     resets every option to its manifest default.
   - Pass the scope `claude plugin list` reports (`-s` defaults to `user`), and for a
     `project`/`local` scope run from that project's directory, or the rerun adds a second install
     record at the scope passed and enables the plugin there. The value itself always lands in user settings.
   - A rejected value prints a warning yet exits 0, so read the output.
   - Rerun `check` in a **fresh session**: `${user_config.*}` is injected at skill load, so a
     same-session check still shows the old value. Report the observed value, never an unobserved
     change.
   - For a root outside the project and home directories, recommend the portable forms from the
     README's option table (`~` prefix or a `${NAME}` / `%NAME%` env-var reference), not a literal
     machine path, which hardcoded-path guardrails block.
2. **`apply install-deps`: provision the extraction dependencies.** Only with this subaction, run
   both idempotent provisioners (a stored fingerprint gates reinstalls, so re-running is cheap) (vendored node deps into `${CLAUDE_PLUGIN_DATA}`; course-digest
   also installs Chromium into `${CLAUDE_PLUGIN_DATA}/ms-playwright`):

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/setup-deps.mjs" --data-dir "${CLAUDE_PLUGIN_DATA}"
   node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/setup-deps.mjs" --data-dir "${CLAUDE_PLUGIN_DATA}"
   ```

   Then re-run the `check` node-deps and Chromium probes and report their results; never claim
   provisioned on exit codes alone.
3. **OS-level media tools: guidance only.** Give the platform install command from the ingest
   skill's Prerequisites. Never install system packages.
4. **Confirm.** Report the observed `library_dir`, the repository convention and any mismatch,
   and whether extraction dependencies were provisioned or skipped. `/knowledge:book-distill`
   writes to its named target skill, not to `library_dir`.

## Output

Report the observed value, the repository convention, any mismatch, each prerequisite's state,
and the exact next action (`/plugin configure knowledge` for `library_dir`, or
`apply install-deps`). A `library_dir` change takes effect in a fresh session; do not claim it in
this one.

## Boundaries

- Do not run an ingestion pipeline. Provisioning dependencies is not running one.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Do not invent organization-specific paths or environment-variable prefixes.
