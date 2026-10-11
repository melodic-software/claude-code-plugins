---
description: "Validate the discipline plugin's configuration (the posture-batch overlay, do-your-research-deep's verification depth, lever_scope and docs/conventions/discipline.yaml), explain how to change the personal options through Claude Code's plugin configuration prompt, and write the repository file after confirmation. Use when: 'set up discipline', 'configure discipline', 'discipline setup', 'is discipline configured', 'what's in my posture batch', 'what's my deep-research depth', 'set lever_scope for this repo', or the user wants to adjust which correctors the batch runs, how deeply the research fan-out verifies, or when a repeated change gets a lever. Actions: check (read-only, default), apply (writes docs/conventions/discipline.yaml only)."
argument-hint: "[check|apply] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
---

## Variables

Batch exclude: `${user_config.batch_exclude}`
Batch promote: `${user_config.batch_promote}`
Batch demote: `${user_config.batch_demote}`
Deep-research verification depth: `${user_config.research_deep_verification}`
Lever scope: `${user_config.lever_scope}`

## Purpose

Report discipline's effective configuration and write its one repository file. The
plugin's personal options are native `userConfig`: three `sweep-all` batch-overlay
options (`batch_exclude` / `batch_promote` / `batch_demote`),
`do-your-research-deep`'s verification-depth default (`research_deep_verification`)
and `lever_scope`. Claude Code prompts for them when the plugin is enabled, stores
non-sensitive options in user settings, and ignores `pluginConfigs` entries in project
and local settings on current releases (>= 2.1.207).

The plugin owns one tracked consumer file, `docs/conventions/discipline.yaml`, the
repository layer of `lever_scope` (keys, values and layers:
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md);
schema: `${CLAUDE_PLUGIN_ROOT}/schemas/discipline.schema.json`). `check` reports it;
`apply` writes it and nothing else. Personal options are never written here: they
change through Claude Code's native flow (`check` step 8). Action routing: no argument
or `check` runs the check; `apply` runs the check, then writes. Re-running either reads
the current state again.

Official contract: <https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration>.

## `check` (read-only)

1. Read the five rendered `${user_config.…}` values from the Variables block
   above (the three `batch_*` overlay options, `research_deep_verification` and
   `lever_scope`). Do not inspect or edit `settings.json`, `settings.local.json`,
   managed settings, or `pluginConfigs` directly.
2. **Empty or unexpanded is unset.** An option the user never configured does not
   reliably render empty, the literal `${user_config.…}` token can survive (a
   zero-config or headless install). Treat BOTH an empty value AND a surviving
   literal placeholder as unset (the key's own default applies); never read the
   literal token as a value.
3. For each set batch option, split on commas and report the parsed corrector names,
   and the net effect: `batch_exclude` drops those correctors from the batch,
   `batch_promote` runs those situational correctors every session, `batch_demote`
   gates those core correctors on relevance. With all three unset, report that the
   batch runs the tiers exactly as the correctors declare them.
4. **Validate the batch names against what is installed.** Glob the sibling corrector
   directories under this plugin's `skills/` and, for each name in an overlay, report:
   - a name in `batch_exclude` or `batch_demote` that matches no installed corrector: FAIL (typo or removed corrector); remediation: fix via the plugin configuration
     prompt;
   - the same name in `batch_exclude` and in `batch_promote`/`batch_demote`: contradictory; report it;
   - **`batch_promote` is situational-only** (read `metadata.discipline-batch`):
     promote only situational names. A promote naming a `never`-tier or `core`
     corrector, or a name that matches no installed corrector, is a **visible
     warning** and is not promoted, never stays out of the batch, core stays
     core, unknown is ignored. Do not report these as successful promotes.
   - a `batch_demote` naming an already-situational corrector, a no-op; INFO.
5. **Report the deep-research verification depth.** `research_deep_verification` sets
   `do-your-research-deep`'s default depth. Report the effective value: `tiered`
   (fan subagents out only over load-bearing items) or `full` (subagent-verify every
   item). An unset value, a surviving literal placeholder, OR any unrecognized string
   (not exactly `tiered` or `full`) all resolve to the `tiered` default. Report an
   unrecognized value as a WARN (typo; remediation: fix it via the plugin
   configuration prompt) that still falls back to tiered, never a hard failure. Note
   that an invocation argument to `do-your-research-deep` overrides this default per
   invocation.
6. **Report `lever_scope`.** Run `"${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --check`
   from the project root and report each line it prints with its own INFO, PASS or
   WARN prefix: INFO when `docs/conventions/discipline.yaml` is absent, PASS with the
   value when the file validates, WARN for each problem when it does not (a value
   outside the key's list, a key set twice, an empty value or empty string, a map or
   list where one value belongs, a key outside the schema), quoting the file, key and
   value. A one-line refusal (an unsafe path, or a root that is `$HOME` or above it)
   is a WARN with that line. Then report the effective value by the layers in
   `${CLAUDE_PLUGIN_ROOT}/reference/config.md`: the file's valid value wins; a file
   that sets the key to an invalid value resolves `deterministic`, never the user's
   value; with no key in the file, a user value of `deterministic` or `non-trivial`
   applies, else `deterministic`. A user value outside the list is a WARN naming the
   option and the value. An invalid value
   never stops the lever check, which names it and drops that layer, so these rows
   are WARN, never FAIL; `apply` fixes the repository value.
7. **Full-batch prerequisite.** INFO: the batch's mid-session pass dispatches
   conversation-inheriting fork subagents. Fork mode is on by default in interactive sessions
   on Claude Code >= v2.1.232 (off by default in non-interactive `-p` and Agent SDK sessions;
   `CLAUDE_CODE_FORK_SUBAGENT` overrides either way:
   <https://code.claude.com/docs/en/sub-agents#fork-the-current-conversation>, re-checked 2026-08-26).
   `sweep-all` preflights this itself and degrades when the fan-out cannot inherit; that runbook owns the behavior; report the prerequisite here only so an unavailable
   fan-out reads as expected rather than as a misconfiguration, and do not restate what
   the degraded pass does.
8. To change or clear any personal option, direct the user to Claude Code's native flow, per the
   marketplace's plugin-reconfiguration convention, which owns the verified-version record
   (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>):
   interactive `/plugin configure discipline@<marketplace>` any time; headless, rerun
   `claude plugin install discipline@<marketplace> -s <scope> --config <key>=<value>` (repeatable
   per key). Against an already-installed plugin it prints `already installed` and still writes
   the value. Never uninstall to reconfigure: that drops the whole stored `pluginConfigs` entry,
   resetting every option to its manifest default. Pass the scope `claude plugin list` reports for
   this plugin (from the home directory pass `user`); the option value lands in user settings
   whatever `-s` says. Claude Code owns persistence. Do not hand-edit any `pluginConfigs` key.
9. Tell the user to rerun `check` after reconfiguration **in a fresh session**: the rendered
   `${user_config.*}` values are injected when this skill loads, so a same-session rerun still reports
   the OLD values. Report the OBSERVED effective values from that fresh run, never an unobserved change.

## `apply` (writes `docs/conventions/discipline.yaml` only)

1. Run `check` and show its report.
2. **Resolve the values.** With complete `<key>=<value>` arguments, use them. Otherwise ask
   one key at a time, recommendation first, from the Keys table in
   `${CLAUDE_PLUGIN_ROOT}/reference/config.md` (`lever_scope`: `deterministic`, the default,
   unless the team wants judgment-bearing repeated changes made with a codemod tool too).
   Never invent a key the schema does not list, and never write a personal option here.
3. **Write.** One call with every value:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" lever_scope=non-trivial
   ```

   The script checks each value against the schema and validates the whole resulting
   document before it writes; an invalid value or key exits 1 and writes nothing. It
   writes only `<git toplevel>/docs/conventions/discipline.yaml`, resolves a symlinked root
   first, then refuses a root that is `$HOME` or an ancestor of it, a symlinked `docs`,
   `docs/conventions` or target, a hard-linked target, or a `docs/conventions`
   that resolves outside the repository, checks the path again before each directory it
   creates and right before the write and the rename, and writes through a new temp file
   in the same directory. Every refusal is one line. A missing file is created; a value
   already in place prints `already configured` and writes nothing.
4. **An existing file that would change** exits 3 and prints a unified diff without
   writing. Show the operator that diff and ask whether to write it. Only on an explicit
   yes, re-run the same call with `--yes`; on anything else, stop with the file
   unchanged. A request to "set it" is not a yes to a diff the operator has not seen.
5. **Verify.** Re-run `check` and report the value from its report, not from the write.
   Then the tracked-file pair: `git check-ignore -v docs/conventions/discipline.yaml`
   reports no match (a match means the team never receives the file: say so, and leave
   `.gitignore` to the operator), and `git ls-files --error-unmatch
   docs/conventions/discipline.yaml` exits 0. Non-zero right after a fresh write means
   "written but untracked: commit it to share with the team", never success.

## Next

`/discipline:sweep-all` to run the posture batch with the reported overlay, or
`/discipline:script-the-deterministic-work` to apply the lever rule.

## Gotchas

- **`apply` writes one file.** It never writes the plugin cache, Claude Code user
  settings, or `pluginConfigs`, per the uniform setup contract (`docs/plugin-philosophy.md`
  "Setup is explicit and repeatable" in the marketplace repository). Personal options
  change only through the native `/plugin configure discipline@<marketplace>` flow.
- **Unexpanded token is not a value.** A surviving literal `${user_config.…}` means
  unset (the key's default applies). Parsing it as a corrector name, a depth or a lever
  scope is the failure this check exists to prevent.
- **The repository file reaches the team only once committed.** `apply` leaves it
  uncommitted on purpose, and the tracked-file pair says so.
