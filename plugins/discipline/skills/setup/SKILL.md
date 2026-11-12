---
description: "Validate the discipline plugin's configuration (the posture-batch override, do-your-research's fan-out verification depth, lever_scope and docs/conventions/discipline.yaml), explain how to change the personal options through Claude Code's plugin configuration prompt, and write the repository file after confirmation. Use when: 'set up discipline', 'configure discipline', 'discipline setup', 'is discipline configured', 'what's in my posture batch', 'what's my deep-research depth', 'set lever_scope for this repo', or the user wants to adjust which correctors the batch runs, how deeply the research fan-out verifies, or when a repeated change gets a lever. Actions: check (read-only, default), apply (writes docs/conventions/discipline.yaml only)."
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
plugin's personal options are native `userConfig`: three `sweep-all` batch-override
options (`batch_exclude` / `batch_promote` / `batch_demote`), the verification-depth
default of `do-your-research`'s fan-out tier (`research_deep_verification`) and
`lever_scope`. They are personal options, held in user settings, and this skill
reads only their rendered values (`check` step 1). How Claude Code collects and
stores them, and which settings files it reads them from, are read live
from [plugin manifest reference: where values are stored](https://code.claude.com/docs/en/plugins/manifest-reference#where-values-are-stored).

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
   above (the three `batch_*` override options, `research_deep_verification` and
   `lever_scope`). Do not inspect or edit `settings.json`, `settings.local.json`,
   managed settings, or `pluginConfigs` directly.
2. **Empty or unexpanded is unset.** Treat BOTH an empty value AND a surviving
   literal `${user_config.…}` placeholder as unset (the key's own default applies);
   never read the literal token as a value. Substitution is documented at
   [plugin manifest reference: reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value),
   which does not say what an unset option renders.
3. For each set batch option, split on commas and report the parsed corrector names,
   and the net effect: `batch_exclude` drops those correctors from the batch,
   `batch_promote` runs those situational correctors every session, `batch_demote`
   gates those core correctors on relevance. With all three unset, report that the
   batch runs the tiers exactly as the correctors declare them.
4. **Validate the batch names against what is installed.** Glob the sibling corrector
   directories under this plugin's `skills/` and, for each name in an override, report:
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
   the default depth of `do-your-research`'s fan-out tier. Report the effective value: `tiered`
   (fan subagents out only over load-bearing items) or `full` (subagent-verify every
   item). An unset value, a surviving literal placeholder, OR any unrecognized string
   (not exactly `tiered` or `full`) all resolve to the `tiered` default. Report an
   unrecognized value as a WARN (typo; remediation: fix it via the plugin
   configuration prompt) that still falls back to tiered, never a hard failure. Note
   that an invocation argument to `do-your-research` (`tiered` or `full`) overrides this default per
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
   fork subagents, so report whether fork mode is on in this kind of
   session. Read the defaults, the version floor and the override variable live from the
   section the Pointer below names, and report what it states.
   - **Pointer**: when reporting whether fork mode is on, fetch
     <https://code.claude.com/docs/en/sub-agents#turn-fork-mode-on-or-off> live.

   `sweep-all` preflights this itself and degrades when the fan-out cannot inherit; that runbook owns the behavior; report the prerequisite here only so an unavailable
   fan-out reads as expected rather than as a misconfiguration, and do not restate what
   the degraded pass does.
8. To change or clear any personal option, direct the user to Claude Code's native flow,
   interactively with `/plugin configure discipline@<marketplace>` or by a headless route, as the
   marketplace's plugin-reconfiguration convention gives them in
   [§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
   (it owns the verified-version record). Apply the scope and failure-signal caveats in its
   [§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
   Read both sections and print what they give, the fallback route, its behavior on an
   already-installed plugin and the scope to pass included, rather than only naming them, and
   leave out the verified-version record.
   Never uninstall to reconfigure; that section links what an uninstall deletes. Claude Code owns
   persistence: this skill never writes user settings or `pluginConfigs`, and never hand-edits any
   `pluginConfigs` key.

   - **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
     when a saved value applies, fetch
     [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
     live.
9. Tell the user to rerun `check` after reconfiguration **in a fresh session**, and report the
   OBSERVED effective values from that fresh run, never an unobserved change. Substitution of the
   rendered `${user_config.*}` values is documented at
   [plugin manifest reference: reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value),
   which does not say when skill content is re-rendered.

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

   Pass a key the operator accepts at the plugin default as `--default <key>` instead of
   `<key>=<value>`, so a later change to that default reaches it; `<key>=<value>` records the
   team's choice, which the script never changes. The script also records `written_against` and
   `provenance:`, so a file with no record, or one written against another plugin version, shows a
   diff even when no value changes.

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
   When the convention-home offer prints below the diff, ask about it too (the next step) before
   any re-run, since `--yes` writes both.
5. **The convention-home offer.** When the repository's `AGENTS.md` or `CLAUDE.md` binds no
   convention home, the script prints an offer: with the operator's confirmation it adds a
   convention-home pointer region to that instruction file (creating `AGENTS.md` when neither
   exists or `CLAUDE.md` only imports it) and the personal override ignore line
   `docs/conventions/**/*.local.*` to `.gitignore`, the only files `apply` writes outside
   `docs/conventions/`. It prints the offer at the end of an exit 0 run and below the diff of an
   exit 3 run, so show the operator stdout on exit 0 too. Ask whether to add the region and the
   ignore line. Only on an explicit yes, re-run the same call with `--yes`, which also writes any
   diff shown with it. On a no, run `"${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --decline`
   alone: it records the decline in the instruction file, and the next run does not offer again.
   To write a shown diff without the region, run `--decline` first, then the same call with
   `--yes`. When the instruction file or `.gitignore` is a symlink or hard link the script will
   not write through, it prints a one-line refusal in place of the offer, with the same exit
   code: show it, and do not re-run with `--yes`, which that refusal stops with exit 1. A refused
   instruction file refuses `--decline` too, so the operator fixes the link or adds the region by
   hand.
6. **Verify.** Re-run `check` and report the value from its report, not from the write.
   Then the tracked-file pair: `git check-ignore -v docs/conventions/discipline.yaml`
   reports no match (a match means the team never receives the file: say so, and leave
   `.gitignore` to the operator), and `git ls-files --error-unmatch
   docs/conventions/discipline.yaml` exits 0. Non-zero right after a fresh write means
   "written but untracked: commit it to share with the team", never success.

## Next

`/discipline:sweep-all` to run the posture batch with the reported override, or
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
