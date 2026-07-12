# Extensibility-contract smoke tests

These tests resolve behavior the official docs leave unspecified for the extensibility contract v2.1
(the "Extensibility contract v2.1 — the four seams" section of the [migration
playbook](MIGRATION-PLAYBOOK.md)). Each records the commands used and the observed result, so the
contract rests on verified behavior rather than inference.

Run 2026-07-12 against Claude Code 2.1.207 on Windows. Re-verify fresh before relying on a result —
see `CLAUDE.md` "Fresh-docs mandate". The rig was a throwaway `smoketest` plugin declaring five
`userConfig` options — a plain `string`, a `sensitive` `string`, a `directory`, a `file`, and a
`required` `string` — published through a throwaway local marketplace and installed into a scratch
consumer repo. All rig artifacts were removed after the run.

## Test A — `directory` / `file` userConfig type behavior

**Question.** Does the `directory` / `file` type drive a picker, validate the path, and what is a
relative path resolved against?

**Commands.**

`--config` is applied only on a fresh install (Test C), so uninstall before each run and read the
stored `pluginConfigs` after each:

```shell
# 1) existing relative paths
claude plugin uninstall smoketest@<marketplace> --scope local
claude plugin install smoketest@<marketplace> --scope local \
  --config req_key=hello --config some_dir=./realdir --config some_file=./realfile.txt
# then read ~/.claude/settings.json → pluginConfigs[smoketest@<marketplace>].options

# 2) non-existent relative paths (uninstall first, or --config short-circuits as a no-op)
claude plugin uninstall smoketest@<marketplace> --scope local
claude plugin install smoketest@<marketplace> --scope local \
  --config req_key=hello --config some_dir=./does_not_exist_dir --config some_file=./does_not_exist.txt
# then read ~/.claude/settings.json → options now show the non-existent paths, stored verbatim
```

**Result.**

- **No existence validation on the `--config` path.** A non-existent directory and file were accepted
  (exit 0) and stored. The `directory` / `file` type does not gate on the path resolving to anything.
- **Values are stored verbatim, not normalized to absolute.** A relative `./realdir` is stored as
  `./realdir`. Claude Code does not anchor it at store time; resolution is deferred to use time
  (relative to the consumer's working directory when `${user_config.KEY}` is substituted). A plugin
  that needs an absolute path resolves it itself.
- **Storage scope diverges from enable scope.** Installed `--scope local` — enablement was written to
  the consumer's `.claude/settings.local.json` — but the non-sensitive options landed in the **user**
  `~/.claude/settings.json` under `pluginConfigs[<plugin-id>].options`. The `sensitive` option was
  absent from settings entirely (it routes to secure storage).
- **The picker, if any, is not observable headless.** A `--config` install never renders UI; only the
  interactive `/plugin configure` flow would. The picker sub-question is recorded as
  not-headless-observable rather than guessed.

## Test B — does a skill-invoked Bash script inherit `CLAUDE_PLUGIN_OPTION_*`?

**Question.** The plugins reference states "All values are exported to plugin subprocesses as
`CLAUDE_PLUGIN_OPTION_<KEY>` environment variables." Does that reach a Bash command a skill tells
Claude to run, or does only text-substitution reach a skill?

**Commands.**

```shell
claude plugin install smoketest@<marketplace> --scope local \
  --config req_key=hello --config plain_key=world_plain --config secret_key=secret_shh
claude plugin list                                   # confirm smoketest enabled + loaded
# headless session from the consumer repo, plugin enabled, skill visible as /smoketest:smoketest
claude -p "run: env | grep CLAUDE_PLUGIN | sort" --allowedTools Bash
```

The `claude -p … --allowedTools Bash` form asks Claude to invoke its Bash tool, so the command runs in
Claude Code's own process environment — the same environment a skill-invoked script runs in, which is
what makes this a valid proxy for the skill case (a skill only makes the model *decide* to run bash;
the subprocess environment is identical).

**Result.**

- **A skill-invoked Bash-tool subprocess does NOT inherit `CLAUDE_PLUGIN_OPTION_*`.** With the plugin
  enabled and `plain_key` set, `env | grep CLAUDE_PLUGIN_OPTION_` returned nothing. The only plugin
  variable present was a single session-level `CLAUDE_PLUGIN_DATA`, and it pointed at an unrelated
  installed plugin's data directory, not the invoking plugin's. `${CLAUDE_PLUGIN_DATA}` resolves
  per-plugin only inside a plugin's own declared commands; in a general Bash-tool subprocess it carries
  one session default, so it is not a dependable per-plugin signal for a skill-spawned script either.
- **"Plugin subprocesses" means the plugin's own declared command subprocesses** — hooks, MCP servers,
  monitors, and `command`-type components — where a current plugin is defined and `${user_config.KEY}`
  also substitutes. It does not mean arbitrary Bash tool calls the model makes while a skill runs.
- **Authoring constraint.** A skill reads a **non-sensitive** userConfig value only through
  `${user_config.KEY}` text-substitution into its own Markdown — never from the environment of a script
  it spawns. A **sensitive** value is unreachable from a skill entirely: it is not substitutable into
  skill / agent content (spec) and is not in the subprocess environment, so only a hook / MCP / monitor
  command can consume it. Design a sensitive-value consumer as a hook or MCP server, not a skill.

## Test C — does `claude plugin install` prompt for userConfig non-interactively?

**Question.** On the headless / CI path, does a missing required option prompt or block?

**Commands.**

```shell
# required req_key unset, no --config, stdin closed
claude plugin install smoketest@<marketplace> --scope local </dev/null
```

**Result.**

- **Headless install never prompts and never blocks.** With the required option unset it still installed
  (exit 0) and printed an advisory: `5 userConfig options not yet set (1 required) — run /plugin
  configure smoketest@<marketplace> in Claude Code, or pass --config KEY=VALUE.`
- **The non-interactive configuration path is `--config KEY=VALUE`** on `claude plugin install`
  (repeatable, schema-validated, "stored via the same path as the interactive `/plugin configure`
  flow"). It applies **only on a fresh install** — `--config` is ignored once the plugin is already
  installed (the command short-circuits "already installed"). `claude plugin` has no `configure`
  subcommand (verified against `claude plugin --help` on 2.1.207; `/plugin configure` is an interactive
  slash command only), so reconfiguring headless requires uninstall then reinstall.
- **CI implication.** Seed every required option with `--config` at install time. A bare headless
  install leaves required options unset without failing, so the plugin would run unconfigured.
