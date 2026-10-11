---
description: "Validate the education plugin's configuration: the quiz, report-library and teach workspace-root userConfig values, and the repository's docs/conventions/education.yaml; write that file after confirmation. Use when: 'set up education', 'configure education', 'education setup', 'set explain_starting_rung for this repo', quiz offers feel wrong, report recall cannot find prior quizzes, or teach workspaces land somewhere unexpected. Actions: check (read-only, default), apply (writes docs/conventions/education.yaml only; userConfig changes route through Claude Code's plugin configuration prompt)."
argument-hint: "[check|apply] [<key>=<value> ...]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Confirm how `/education:quiz-me` offers comprehension checks, where generated quiz reports are
stored, where `/education:teach` roots its learning workspaces, and where `/education:explain`
starts. The plugin has two configuration surfaces:

- **Native `userConfig`**: `quiz_policy`, `report_library_dir`, `workspace_root` and
  `explain_starting_rung`. Claude Code prompts for them when the plugin is enabled and owns where
  they are stored. This skill reads their rendered values and never writes them.
- **One tracked consumer file**: `docs/conventions/education.yaml`, the repository layer for
  `explain_starting_rung` (keys, values and layers:
  [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md);
  schema: `${CLAUDE_PLUGIN_ROOT}/schemas/education.schema.json`). A value set there wins over the
  user's `userConfig` value.

Action routing: no argument or `check` runs the check; `apply` runs the check, then writes the
repository file and nothing else. Re-running either reads the current state again. With complete
`<key>=<value>` arguments, nothing asks a question; the one confirmation is a diff to an existing
file (`apply` step 4).

Official contract: <https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration>.

## `check` (read-only)

Report a PASS/INFO/WARN table. Write nothing.

1. Read the rendered `${user_config.quiz_policy}`, `${user_config.report_library_dir}`,
   `${user_config.workspace_root}` and `${user_config.explain_starting_rung}` values from this
   skill. Do not inspect or edit `settings.json`, `settings.local.json`, managed settings, or
   `pluginConfigs` directly. A literal unexpanded `${user_config.<key>}` means unset.
2. Explain the effective `quiz_policy`:
   - `off`, quiz-me never offers a post-work quiz;
   - `on-request` (default), offers only when asked;
   - `always`, offers after each completed change;
   - `above-threshold`, offers when the change is large;
   - any other value is treated as `on-request` at runtime.
3. Explain the effective report library root:
   - empty or unexpanded `report_library_dir`, reports live under the plugin's own persistent
     data directory;
   - configured directory outside the consuming project, reports and recall search that checkout;
   - configured directory that is `${CLAUDE_PROJECT_DIR}` or nested under it, quiz-me's
     repo-tree guard refuses it and falls back to `${CLAUDE_PLUGIN_DATA}` (same effective root
     as unset).
4. Explain the effective teach workspace root:
   - empty or unexpanded `workspace_root`. FIRST read the rung-3 pointer file
     `${CLAUDE_PLUGIN_DATA}/workspace-root`: when present and it names an existing directory,
     report THAT path as the effective topic-mode root (it persists a prior one-time ask, and
     also records the migration-offer outcome); when absent or invalid, report the documented
     ladder (project declaration → this setting → one-time ask → OS Documents `Claude Learning/`
     home for topic mode → plugin data); codebase-mode workspaces stay under plugin data by
     default either way (their lessons can embed private-repo snippets; Documents roots are
     often cloud-synced);
   - configured directory outside the consuming project, both modes root there;
   - configured directory that is `${CLAUDE_PROJECT_DIR}` or nested under it, teach's
     repo-tree guard refuses it (a committed root requires a declaration in the project's own
     CLAUDE.md or rules), falling back to the rest of the ladder.
5. **Repository settings.** Run
   `"${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" --check` from the project root and report each
   line it prints under its own INFO, PASS or WARN prefix: INFO when
   `docs/conventions/education.yaml` is absent (every key comes from `userConfig` or its default);
   PASS with each key's value when the file validates; WARN when it does not (a value outside the
   key's list, a key set twice, an empty or null value, a map or list where one string belongs, or a
   key the schema does not list), quoting the file, key and value. An invalid value never stops
   `/education:explain`, which names it and drops that layer, so the row is a WARN. `apply` fixes
   only a value that is outside the list, empty or null, and keeps an unknown key's line as
   written; every other WARN needs a hand edit first, and `apply` refuses the file until it gets
   one. Then state the effective `explain_starting_rung`: the file's value when valid, else the
   `userConfig` value when it is `plain` or `peer`, else `plain`, naming the layer that supplied it.
6. State the tradeoff instead of asking: machine-private plugin data (default) versus a dedicated
   corpus checkout for long-lived recall across machines. For a repository-backed library,
   inspect the consumer's artifact conventions and recommend one portable location. Never
   recommend a machine-absolute team path.
7. To change a `userConfig` value, reconfigure through Claude Code's native flow per the
   plugin-reconfiguration convention
   (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
   which owns the verified-version record): interactive `/plugin configure education@<marketplace>` any time;
   headless, rerun `claude plugin install education@<marketplace> -s <scope> --config quiz_policy=<value>`
   (repeatable per key). Against an already-installed plugin it prints `already installed` and still writes the
   value. Never uninstall to reconfigure: that drops the whole stored `pluginConfigs` entry, resetting every
   option to its manifest default. `-s` defaults to `user`; pass the scope `claude plugin list` reports, and run
   `project`/`local` writes from that project's directory, or the rerun adds a second install record at
   the scope passed and enables the plugin there; the value itself always lands in user settings.
   A rejected value prints a warning yet exits 0, so read the output. To set a value for the whole
   repository instead, use `apply`.
8. Tell the user to rerun `check` after a `userConfig` change in a **fresh session**, because rendered
   values are injected at skill load and a same-session rerun still reports the OLD values. Then report
   the observed effective settings.

## `apply` (writes `docs/conventions/education.yaml` only)

1. Run `check` and show its table.
2. **Resolve the values.** With complete `<key>=<value>` arguments, use them. Otherwise ask one key at
   a time, recommendation first, from the Keys table in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`
   (`explain_starting_rung`: `plain`, the default, unless the team's readers already know the
   domain and want `peer`). Never invent a key the schema does not list. A request to change
   `quiz_policy`, `report_library_dir` or `workspace_root` is not an `apply` key: route it through
   `check` step 7.
3. **Write.** One call with every value:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/setup-apply.mjs" explain_starting_rung=peer
   ```

   The script writes only the keys named on the command line and keeps every other line of an
   existing file. It validates the existing file first, and over it fixes only a value that is
   outside the key's list, empty or null. It refuses with one line, exits 1 and leaves the file
   untouched when a command-line key is outside the schema or given twice, a command-line value is
   outside the key's list, or the existing file sets a key twice (`key : v` counts as `key: v`),
   holds a map or list in any form (`[]`, `[peer]`, `{level: peer}` or an indented block), holds an
   empty quoted string, names a key the schema does not list twice or with a map or list, or does
   not parse. Any other unknown key is named in one warning and its line kept as written. It writes
   only `<git toplevel>/docs/conventions/education.yaml`: it resolves a symlinked root first, then
   refuses a root that is `$HOME` or an ancestor of it, a symlinked `docs`,
   `docs/conventions` or target, a `docs/conventions` that resolves outside the repository, and a
   target with more than one hard link, and checks the path again right before the write, which
   goes to a new temp file beside the target and is renamed over it. A directory or file in the way
   is a one-line refusal. A missing file is created. A value already in place prints
   `already configured` and writes nothing.
4. **An existing file that would change** exits 3 and prints a unified diff without writing. Show
   the operator that diff and ask whether to write it. Only on an explicit yes, re-run the same
   call with `--yes`; on anything else, stop with the file unchanged. A request to "set it" is not
   a yes to a diff the operator has not seen.
5. **Verify.** Re-run `check` and report the value from its table, not from the write. Then the
   tracked-file pair: `git check-ignore -v docs/conventions/education.yaml` reports no match (a
   match means the team never receives the file: say so, and leave `.gitignore` to the operator),
   and `git ls-files --error-unmatch docs/conventions/education.yaml` exits 0. Non-zero right after
   a fresh write means "written but untracked: commit it to share with the team", never success.

## Output

`check`: the effective `quiz_policy`, report-library root, teach workspace root and
`explain_starting_rung` with its supplying layer, the repository-file rows, and any recommended
changes with the route for each. `apply`: the table before and after, the diff when one was shown,
the written path, and whether the file is tracked. Do not claim a configuration change until a
rerun observes it.

## Next

`/education:explain`

## Boundaries

- Do not start a teach, explain, or quiz session; use `/education:teach`, `/education:explain`,
  or `/education:quiz-me`.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform
  setup contract (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the
  marketplace repository).
- Do not write any file other than `docs/conventions/education.yaml`, and do not commit it or edit
  the consumer's `.gitignore`.
- Do not invent an organization, repository, marketplace, or environment-variable prefix.
