---
description: "Verify that markdownlint-cli2, the lint gate /docs-hygiene:compress requires, resolves and runs for this repository, and validate the compress_articles setting: the userConfig value and the repository's docs/conventions/docs-hygiene.yaml; write that file after confirmation. Use when: 'set up docs-hygiene', 'is docs-hygiene ready', 'compress stopped because markdownlint-cli2 is missing', 'set compress_articles for this repo', or before the first compress run. Actions: check (read-only, default), apply (writes docs/conventions/docs-hygiene.yaml only). Installs nothing. Re-runnable and safe."
argument-hint: "[check|apply] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Purpose

Setup for `/docs-hygiene:compress`. It has two parts:

- **The one external prerequisite**, `markdownlint-cli2`, which `compress` runs as its post-edit
  ship gate and stops without. `check` resolves the binary, runs it, and reports the remediation.
  Installing is the operator's.
- **The `compress_articles` setting**, which decides whether `compress` may remove `a`, `an` and
  `the`. It has two homes: the plugin's native `userConfig` option, which Claude Code prompts for
  and stores, and which this skill reads but never writes; and one tracked consumer file,
  `docs/conventions/docs-hygiene.yaml`, the repository layer (keys, values and layers:
  [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md);
  schema: `${CLAUDE_PLUGIN_ROOT}/schemas/docs-hygiene.schema.json`). A value set in the file wins
  over the user's `userConfig` value.

Action routing: no argument or `check` runs the check; `apply` runs the check, then writes the
repository file and nothing else. With complete `<key>=<value>` arguments nothing asks a question;
the one confirmation is a diff to an existing file (`apply` step 4).

Official contract for `userConfig`: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

## `check` (read-only)

Report a PASS/INFO/WARN/FAIL table with one remediation line per FAIL. Modify nothing.

1. **Resolve `markdownlint-cli2`** the way `compress` does: first `command -v markdownlint-cli2`
   (on `PATH`), then `node_modules/.bin/markdownlint-cli2` under the repository root. Report which
   one resolved. FAIL when neither does.
2. **Run it.** Execute the resolved binary with `--version`. A shim can resolve and still be broken
   (a missing Node interpreter, a dangling target), so resolution without a clean exit is FAIL, with
   the error text in the remediation line.
3. **Repository settings.** Run `"${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --check` from the
   project root and report each line it prints under its own INFO, PASS or WARN prefix: INFO when
   `docs/conventions/docs-hygiene.yaml` is absent; a WARN for each problem in the file (a value
   outside the key's list, a key set twice, an empty or null value, a map or list where one string
   belongs, a key the schema does not list, or a line that does not parse), quoting the file, key
   and value; then one line per schema key: `PASS <key>: <value>` or `PASS <key>: (unset)`, or
   `WARN <key>: dropped ...` when the file's value for that key is invalid or the file does not
   parse. A key the schema does not list gets its own WARN and leaves the other keys' values in
   force, the same way `/docs-hygiene:compress` reads them. An invalid value never stops
   `/docs-hygiene:compress`, which names it and drops that layer, so these rows are WARNs. `apply`
   fixes only a value that is outside the list, empty or null, and leaves an unknown key's line as
   written; every other WARN needs a hand edit first.
4. **Effective `compress_articles`.** Read the rendered `${user_config.compress_articles}`; a
   literal unexpanded token means unset. Do not inspect or edit `settings.json`,
   `settings.local.json`, managed settings or `pluginConfigs`. Resolve as `compress` does
   (`${CLAUDE_PLUGIN_ROOT}/reference/config.md`), highest layer first, and state the value and the
   layer that supplied it:
   1. Step 3 printed `PASS compress_articles: <value>` with `keep` or `cut`: the file's value.
   2. Step 3 printed `WARN compress_articles: dropped`: the file layer is dropped, and no valid
      layer sits above it, so the value is `keep` (default). Never use the `userConfig` value in
      its place.
   3. Otherwise (no file, or the key unset in it): the `userConfig` value when it is `keep` or `cut`.
      Any other `userConfig` value is named (`userConfig`, `compress_articles`, the value) and
      dropped, and the value is `keep` (default).
   4. Otherwise `keep` (default).

Remediation for a `markdownlint-cli2` FAIL: install it explicitly, `npm install --save-dev
markdownlint-cli2` in the repository or a global install, then rerun `check`. Without it
`/docs-hygiene:compress` stops at its entry point before touching a file. No other skill in this
plugin needs the binary.

To change the `userConfig` value, reconfigure through Claude Code's native flow per the
plugin-reconfiguration convention
(<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
which owns the verified-version record): `/plugin configure docs-hygiene@<marketplace>`
interactively, or headless `claude plugin install docs-hygiene@<marketplace> -s <scope> --config
compress_articles=<value>`. Never uninstall to reconfigure. Rendered values are injected at skill
load, so rerun `check` in a fresh session after a change. To set the value for the whole
repository instead, use `apply`.

## `apply` (writes `docs/conventions/docs-hygiene.yaml` only)

1. Run `check` and show its table.
2. **Resolve the value.** With a complete `compress_articles=<value>` argument, use it. Otherwise
   ask, recommendation first: `keep`, the default, for docs people read; `cut` only when the team
   wants the shortest text and its readers are agents. Never invent a key the schema does not list.
3. **Write.** One call:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" compress_articles=keep
   ```

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
5. **Verify.** Re-run `check` and report the value from its table, not from the write. Then
   `git check-ignore -v docs/conventions/docs-hygiene.yaml` reports no match (a match means the
   team never receives the file: say so, and leave `.gitignore` to the operator), and
   `git ls-files --error-unmatch docs/conventions/docs-hygiene.yaml` exits 0. Non-zero right after
   a fresh write means "written but untracked: commit it to share with the team", never success.

## Next

`/docs-hygiene:compress`

## Gotchas

- **A missing binary is not a lint failure.** `compress` never ships unverified output, so absence
  stops it; `check` is how to see why before that happens.
- **Never install on the operator's behalf.** This skill runs no `npm`, no `npx`, and no download.
- **`apply` does not fix a missing binary.** It writes only the settings file.

## What this skill does NOT do

- Run `markdownlint-cli2` over repository files. The only execution is the `--version` liveness probe.
- Check the consuming repository's markdownlint configuration. Which rules a repository adopts is its
  own decision.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
