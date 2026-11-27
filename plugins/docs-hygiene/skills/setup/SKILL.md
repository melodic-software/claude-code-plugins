---
description: "Validate the /docs-hygiene:compress settings for this repository: the compress_articles userConfig value and the repository's docs/conventions/docs-hygiene.yaml; write that file after confirmation. Use when: 'set up docs-hygiene', 'is docs-hygiene ready', 'set compress_articles for this repo', or before the first compress run. Actions: check (read-only, default), apply (writes docs/conventions/docs-hygiene.yaml only). Installs nothing. Re-runnable and safe."
argument-hint: "[check|apply] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Purpose

Setup for `/docs-hygiene:compress`: the **`compress_articles` setting**, which decides whether
`compress` may remove `a`, `an` and `the`. It has two homes: the plugin's native `userConfig`
option, which Claude Code prompts for and stores, and which this skill reads but never writes; and
one tracked consumer file, `docs/conventions/docs-hygiene.yaml`, the repository layer (keys, values
and layers: [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md);
schema: `${CLAUDE_PLUGIN_ROOT}/schemas/docs-hygiene.schema.json`). A value set in the file wins
over the user's `userConfig` value.

Action routing: no argument or `check` runs the check; `apply` runs the check, then writes the
repository file and nothing else. With complete `<key>=<value>` arguments nothing asks a question;
the one confirmation is a diff to an existing file (`apply` step 4).

Official contract for `userConfig`: <https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration>.

## `check` (read-only)

Report a PASS/INFO/WARN table. Modify nothing.

1. **Repository settings.** Run `"${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --check` from the
   project root and report each line it prints under its own INFO, PASS or WARN prefix: INFO when
   `docs/conventions/docs-hygiene.yaml` is absent, with no other line; otherwise a WARN for each
   problem in the file (a value outside the key's list, a key set twice, an empty or null value, a
   map or list where one string belongs, a key the schema does not list, or a line that does not
   parse), quoting the file, key and value; then one line per schema key: `PASS <key>: <value>` or `PASS <key>: (unset)`, or
   `WARN <key>: dropped ...` when the file's value for that key is invalid or the file does not
   parse. A key the schema does not list gets its own WARN and leaves the other keys' values in
   force, the same way `/docs-hygiene:compress` reads them. An invalid value never stops
   `/docs-hygiene:compress`, which names it and drops that layer, so these rows are WARNs. `apply`
   fixes only a value that is outside the list, empty or null, and leaves an unknown key's line as
   written; every other WARN needs a hand edit first.
2. **Effective `compress_articles`.** Read the rendered `${user_config.compress_articles}`; a
   literal unexpanded token means unset. Do not inspect or edit `settings.json`,
   `settings.local.json`, managed settings or `pluginConfigs`. Resolve as `compress` does
   (`${CLAUDE_PLUGIN_ROOT}/reference/config.md`), highest layer first, and state the value and the
   layer that supplied it:
   1. Step 1 printed `PASS compress_articles: <value>` with `keep` or `cut`: the file's value.
   2. Step 1 printed `WARN compress_articles: dropped`: the file layer is dropped, and no valid
      layer sits above it, so the value is `keep` (default). Never use the `userConfig` value in
      its place.
   3. Otherwise (no file, or the key unset in it): the `userConfig` value when it is `keep` or `cut`.
      Any other `userConfig` value is named (`userConfig`, `compress_articles`, the value) and
      dropped, and the value is `keep` (default).
   4. Otherwise `keep` (default).

To change the `userConfig` value of `compress_articles`, reconfigure through Claude Code's native
flow, interactively with `/plugin configure docs-hygiene@<marketplace>` or by a headless route, as
the marketplace's plugin-reconfiguration convention gives them in
[§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
(it owns the verified-version record). Apply the scope and failure-signal caveats in its
[§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
Read both sections and print what they give, the fallback route, its behavior on an
already-installed plugin and the scope to pass included, rather than only naming them, and
leave out the verified-version record.
Never uninstall to reconfigure; that section links what an uninstall deletes. This skill never
writes user settings or `pluginConfigs`. Afterwards rerun `check` in a **fresh session**, since a
same-session `check` can still show the old value, and report the observed effective value, never
an unobserved change.

- **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
  when a saved value applies, fetch
  [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
  live.

To set the value for the whole repository instead, use `apply`.

## `apply` (writes `docs/conventions/docs-hygiene.yaml` only)

1. Run `check` and show its table.
2. **Resolve the value.** With a complete `compress_articles=<value>` argument, use it. Otherwise
   ask, recommendation first: `keep`, the default, for docs people read; `cut` only when the team
   wants the shortest text and its readers are agents. Never invent a key the schema does not list.
3. **Write.** One call:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" compress_articles=keep
   ```

   Pass a key the operator accepts at the plugin default as `--default <key>` instead of
   `<key>=<value>`, so a later change to that default reaches it; `<key>=<value>` records the
   team's choice, which the script never changes. The script also records `written_against` and
   `provenance:`, so a file with no record, or one written against another plugin version, shows a
   diff even when no value changes.

   The script writes only the keys named on the command line and keeps every other line of an
   existing file. It validates the existing file first, and over it fixes only a value that is
   outside the key's list, empty or null. It refuses with one line, exits 1 and leaves the file
   untouched when a command-line key is outside the schema or given twice, a command-line value is
   outside the key's list, or the existing file sets a key twice (`key : v` counts as `key: v`),
   holds a map or list in any form, holds an empty quoted string, names a key the schema does not
   list twice or with a map or list, does not parse, or mixes CRLF and LF line endings (a file
   written with CRLF throughout is updated in place and keeps CRLF). Any other unknown key is
   named in one warning and its line kept as written. It writes only
   `<git toplevel>/docs/conventions/docs-hygiene.yaml`: it resolves a symlinked root first, then
   refuses a root that is `$HOME` or an ancestor of it (where `compress` does not read the file),
   a symlinked `docs`, `docs/conventions` or target, a directory that resolves outside the
   repository, and a target with more than one hard link, and checks the path again before each
   directory it creates and before the write, which goes to a new temp file beside the target and
   is renamed over it. A missing file is created. A value already in place prints
   `already configured` and writes nothing.
4. **An existing file that would change** exits 3 and prints a unified diff without writing. Show
   the operator that diff and ask whether to write it. Only on an explicit yes, re-run the same
   call with `--yes`; on anything else, stop with the file unchanged.
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
6. **Verify.** Re-run `check` and report the value from its table, not from the write. Then
   `git check-ignore -v docs/conventions/docs-hygiene.yaml` reports no match (a match means the
   team never receives the file: say so, and leave `.gitignore` to the operator), and
   `git ls-files --error-unmatch docs/conventions/docs-hygiene.yaml` exits 0. Non-zero right after
   a fresh write means "written but untracked: commit it to share with the team", never success.

## Next

`/docs-hygiene:compress`

## Gotchas

- **Never install on the operator's behalf.** This skill runs no `npm`, no `npx`, and no download.

## What this skill does NOT do

- Resolve or run the repository's markdown linter. `/docs-hygiene:compress` resolves it from the
  repository at run time.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
