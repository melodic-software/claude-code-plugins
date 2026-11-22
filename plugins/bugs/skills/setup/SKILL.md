---
description: "Check where /bugs:write --file reports land, check or write the tracked docs/conventions/bugs.yaml lanes and filing posture /bugs:scan reads, and move settings out of the old ~/.claude/bugs.md and .claude/bugs.local.md."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
---

## Two surfaces, two owners

| Surface | Holds | Written by |
|---|---|---|
| `output_dir`, `gotchas_file`. Native `userConfig` | one operator's personal `--file` destination on one machine; one operator's gotchas file for every repository | Claude Code's own plugin configuration prompt, never this skill |
| `docs/conventions/bugs.yaml`. Tracked, cascade-layered | team policy: `/bugs:scan` lanes and filing posture | `apply` here; besides it, only the gated old-path move |

This is the narrow-write setup shape: `apply` writes the team YAML, plus what the gated old-path
move writes. `output_dir` and `gotchas_file` stay check-only: each is a
native option, and this skill never writes the `pluginConfigs` the uniform setup contract forbids;
reconfiguration routes through the native flow.

Pointer: where option values are stored and which settings files they are read from are read at
[plugins manifest reference: user configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
and [settings reference: `pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs).

Keys, layers, merge semantics, the `output_dir` partition rule, and the file format live in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md). Read it before checking or
writing; never restate its keys here or disagree with it.

No argument runs `check`. Both actions run without questions when the invocation and the repo make
the values unambiguous: report and recommend, and ask only where a lane genuinely needs the user.

## `check` (read-only, the default)

Modify nothing. Report both surfaces, then one remediation line per gap.

### A. `output_dir` (native `userConfig`)

1. Read the rendered `${user_config.output_dir}` value from this skill. Do not inspect or edit
   `settings.json`, `settings.local.json`, managed settings, or `pluginConfigs` directly.
2. Explain the effective behavior: an empty or unexpanded value means `--file` uses
   `${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`; a configured value means that directory.
3. State the tradeoff instead of asking: machine-private (the default) versus a repository path
   committed alongside code. For the repository option, inspect the consumer's `CLAUDE.md`,
   `AGENTS.md`, and existing report or artifact directories and recommend one portable location.
   Never recommend a machine-absolute team path.
4. If the recommended value differs, set `output_dir` to it through Claude Code's native flow,
   interactively with `/plugin configure bugs@<marketplace>` or by a headless route, as the
   marketplace's plugin-reconfiguration convention gives them in
   [§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
   (it owns the verified-version record). Apply the scope and failure-signal caveats in its
   [§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
   Read both sections and print what they give, the fallback route, its behavior on an
   already-installed plugin and the scope to pass included, rather than only naming them, and
   leave out the verified-version record.
   Never uninstall to reconfigure; that section links what an uninstall deletes. This skill never
   writes user settings or `pluginConfigs`. Then rerun `check` in a **fresh session**, since a
   same-session `check` can still show the old value, and report the observed destination, never
   an unobserved change.

   - **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
     when a saved value applies, fetch
     [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
     live.

### B. `docs/conventions/bugs.yaml` (tracked lane config)

Anchor at the repo root (`${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel`), never the CWD. Report **each layer separately** and the effective
merged result:

1. **Per-layer presence.** For every layer in the reference's layer table: absent,
   present-and-parsed, or malformed, plus each old path B6 names. A malformed layer degrades soft: surface the error, name the
   layer, resolve as if it were absent. Check a present team YAML against
   [`${CLAUDE_PLUGIN_ROOT}/schemas/bugs.schema.json`](../../schemas/bugs.schema.json) and report
   each violation; the reference still governs how a run treats an unknown key or a bad lane entry.
2. **Effective config and provenance.** The merged `lanes` and the resolved `filing_posture` (the
   reference's Filing posture section) and the layer that supplied each, honoring the reference's
   merge semantics. A `filing_posture` in a bugs layer is WARN: deprecated, move it to
   `docs/conventions/work-items.yaml`; an explicit empty-list opt-out is
   reported as an opt-out, not a broken layer. All layers absent is a fully working state: INFO,
   never FAIL, since `/bugs:scan` falls through to its bundled default lanes.
3. **Per-layer version-control verdict.** A present team file must be tracked, which takes **two**
   probes per file. `git check-ignore -v docs/conventions/bugs.yaml`: a non-empty result is FAIL,
   naming the matching pattern. `git ls-files --error-unmatch docs/conventions/bugs.yaml`: a
   non-zero exit on a present file is FAIL, "present but untracked, commit it so teammates receive
   it". Probe `docs/conventions/bugs.md` the same way when present. The `.local.md` personal override must be
   gitignored; staged or unignored is FAIL. The `gotchas_file` file sits outside the worktree: say
   no git verdict applies rather than run a meaningless command.
4. **Unreachable layers.** When a layer cannot be read (often the `gotchas_file` one), WARN that it was
   not considered rather than present the rest as the whole effective config.
5. **Unknown keys.** Report them as inert, naming their layer, including `output_dir`, which is not a
   recognized key here.
6. **Old paths.** For each old file the reference's "Old paths (dual-read window)" section names
   that exists, report its path, what it holds (gotchas, `lanes`, `filing_posture`), which of its
   settings the new files already supply and so win, the new home of each setting from that
   section's table, and `apply` as the command that moves it. The `gotchas_file` option is
   `${user_config.gotchas_file}` in this text; an empty or unexpanded value is unset.
   - `.claude/bugs.local.md` is retirement record `bugs-r001`. Run
     `bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml"`.
     Exit 0 → PASS. Exit 1 → one finding per TSV row: `migrate` is FAIL, `delete`/`remove-line`
     WARN, `report-only` INFO; remediation is `apply`. Exit 2 → FAIL, never silent. Bash
     unavailable → report the step UNKNOWN with remediation, never green.
   - `~/.claude/bugs.md` sits outside the repository and has no record: WARN on it here.

## `apply` (idempotent, bounded to `docs/conventions/bugs.yaml` and the old-path move)

Run `check` first, then converge the **team** YAML. Besides it, `apply` writes only what the
old-path move below writes, each behind its own yes. Never touch `settings.json`,
`settings.local.json`, managed settings, `pluginConfigs`, `userConfig`, or the consumer's
`.gitignore`. An `output_dir` or `gotchas_file` change requested here routes to the native flow in
`check` step A4, never written.

### Move old paths first

When `check` B6 found an old file, move it before converging the team YAML, so the move ends in one
home, never two. For each old file, one at a time:

1. **Preview.** Show the file's path, each setting in it, its new home from the reference's
   "Old paths (dual-read window)" table, and the exact text to be written there. Where the new file
   already exists, show the merge: settings it already holds are kept, and only what it lacks is
   added. Ask for a yes; without one, change nothing for this file.
2. **Write the new home.** The old file's content is untrusted input, never executed or
   interpolated.
   - `.claude/bugs.local.md` (record `bugs-r001`): follow the record's `successor`. Write its
     content to `docs/conventions/bugs.local.md`, merged as previewed. Confirm
     `git check-ignore -v docs/conventions/bugs.local.md` matches before writing; when it does not,
     stop for this file and recommend the reference's `.gitignore` line.
   - `## Gotchas` from `~/.claude/bugs.md`: write it to the file the `gotchas_file` option names.
     With the option unset, ask the user for a path outside `~/.claude` and any repository, write
     the section there, then have them set the option to that path through the native flow in
     `check` step A4. Re-run `check` in a fresh session before step 3, since a same-session value can
     be stale.
   - `lanes` from `~/.claude/bugs.md`: ask which repository it was for and write it to that
     repository's `docs/conventions/bugs.local.md`. When the user says the team shares it, write it
     to the team YAML now, behind the same yes, scaffolded in the reference's format when absent and
     merged by lane `name` when present.
   - `filing_posture` from either file: show the line to add to `docs/conventions/work-items.yaml`,
     as step 3 of "Converge the team YAML" does for the team YAML.
3. **Check the new home resolves the same values.** Run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/concat-gotchas.sh" --user-file "<gotchas_file>"`, with
   `<gotchas_file>` the option value from this text written out (empty when unset), never the
   `${user_config.…}` token itself. Confirm each gotcha line from the old file appears under the new
   layer's block, and re-read the new file for each moved key. A missing value, such as a
   `filing_posture` the work-items file does not set yet, stops the move for this file and keeps the
   old file.
4. **Delete the old file** once step 3 passes, and say so: for `.claude/bugs.local.md` run
   `bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml" --clean bugs-r001 --i-migrated`;
   delete `~/.claude/bugs.md` directly. Re-run `concat-gotchas.sh` and the retirement detection
   last: neither reports the old file any more.

### Converge the team YAML

1. **Read the effective config across every layer** and present it. Where a personal override
   layer changes the team file's effect (adding lanes, replacing one by name, opting out with an
   empty list), say so: a team-scope edit alone will not
   account for it, and re-adding a lane a personal override opts out of will not restore it on this machine.
   Prompt the user to update that layer; do not edit it for them.
2. **Draft lanes from the repository** before asking anything: entrypoint and API directories, the
   highest-churn source areas in `git log`, and any subsystem the repo's own docs treat as critical.
   Propose kebab-case lane names with globs relative to the repo root. With lanes already in the
   team YAML, propose only additions; with nothing to infer from, propose the bundled generic
   default lanes.
3. **Confirm one decision at a time.** Present each drafted lane with a recommendation; the user
   accepts, edits, or drops it. Never write `filing_posture`: it lives in
   `docs/conventions/work-items.yaml`. When the team YAML still sets it, show the line to add there
   and, once that file sets it and the user says yes, drop it from the team YAML.
4. **Write conservatively.** Scaffold the file in the reference's format when absent; otherwise
   make a targeted update. Fill absent keys at their documented defaults, preserve comments, and
   report rather than silently rewrite anything you cannot reconcile. Never rewrite a file you did
   not first read.
5. **Verify after writing.** Re-run the `check` B probes against the file on disk: it parses, it
   meets the schema, every lane declares `name` and `globs`, the globs match real paths (a lane
   matching nothing is reported as skipped), and `git check-ignore -v docs/conventions/bugs.yaml`
   confirms it is not ignored. Report the values observed, never an unobserved change.
6. **Recommend the personal override line; do not write it.** Personal deviations belong in
   `docs/conventions/bugs.local.md`; recommend the recursive `.gitignore` line the reference names
   if not already covered.
7. **Remind them to stage it.** The team file reaches teammates only once committed.

Re-running `apply` when everything already matches changes nothing and reports "already configured".

## Output

For each surface: the effective state and the layer that supplied it, the recommended state, and
what changed (the tracked file's path and the keys written), plus whether the user must still change
`output_dir` through Claude Code's own flow. Claim a change only once observed: for the tracked file
by re-reading it, for `output_dir` by a rerun in a fresh session.

## Boundaries

- Do not produce or file a bug report; invoke `/bugs:write` via the Skill tool.
- Do not run a hunt; that is `/bugs:scan`.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform
  setup contract (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the
  marketplace repository).
- Do not delete the tracked config: `apply` converges and removes only an old-path file, after its
  move checks out.
- Do not invent an organization, repository, marketplace, or environment-variable prefix.

## Next

- Produce a bug report: `/bugs:write`.
- Hunt the configured lanes: `/bugs:scan`.

## Gotchas

- **Verify a reconfiguration only in a fresh session.** When checking when a saved value reaches skill content, fetch
  [plugins manifest reference § Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)
  and [skills § Available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions)
  live.
- **Never uninstall to reconfigure.** Reconfigure through `check` step A4; what an uninstall deletes
  is linked from the convention section that step cites.
- **Check the headless route's own failure signal** before reporting a value saved, as the
  convention's caveats section cited in `check` step A4 gives it.
- **The ignore probe alone blesses an unshared file.** An untracked, unignored file returns the same
  empty `check-ignore` output as a healthy tracked one; the `ls-files` probe is what catches it.
- **A file `apply` just scaffolded is untracked until staged.** `git ls-files --error-unmatch` will
  not match yet; that is not a FAIL after `apply`. State the commit obligation instead.
