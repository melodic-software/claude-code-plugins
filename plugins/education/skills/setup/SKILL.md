---
description: "Validate the education plugin's quiz and report-library configuration and explain how to change it through Claude Code's plugin configuration prompt. Use when: 'set up education', 'configure education', 'education setup', quiz offers feel wrong, or report recall cannot find prior quizzes. Actions: check (read-only verification, default and only action — this plugin's entire configuration is native userConfig, so there is nothing an apply could write)."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Confirm how `/education:quiz-me` offers comprehension checks and where generated quiz reports
are stored, without editing Claude Code settings. `quiz_policy` and `report_library_dir` are
native `userConfig` values. Claude Code prompts for them when the plugin is enabled and owns
persistence.

Check-only per the uniform setup contract's userConfig-only carve-out: this plugin's entire
configuration surface is native `userConfig`, so `check` (the default and only action) verifies
and reports, and reconfiguration routes through Claude Code's native flow — an `apply` here
would have nothing to write except the `pluginConfigs` setup must never touch. Non-interactive:
report and recommend; never block on a question.

Official contract: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

## `check` (read-only, the only action)

1. Read the rendered `${user_config.quiz_policy}` and `${user_config.report_library_dir}`
   values from this skill. Do not inspect or edit `settings.json`, `settings.local.json`,
   managed settings, or `pluginConfigs` directly.
2. Explain the effective `quiz_policy`:
   - `off` — quiz-me never offers a post-work quiz;
   - `on-request` (default) — offers only when asked;
   - `always` — offers after each completed change;
   - `above-threshold` — offers when the change is large;
   - any other value is treated as `on-request` at runtime.
3. Explain the effective report library root:
   - empty or unexpanded `report_library_dir` — reports live under the plugin's own persistent
     data directory;
   - configured directory outside the consuming project — reports and recall search that checkout;
   - configured directory that is `${CLAUDE_PROJECT_DIR}` or nested under it — quiz-me's
     repo-tree guard refuses it and falls back to `${CLAUDE_PLUGIN_DATA}` (same effective root
     as unset).
4. State the tradeoff instead of asking: machine-private plugin data (default) versus a dedicated
   corpus checkout for long-lived recall across machines. For a repository-backed library,
   inspect the consumer's artifact conventions and recommend one portable location. Never
   recommend a machine-absolute team path.
5. If a recommended value differs from the effective one, direct the user to Claude Code's plugin
   configuration prompt for `education` (interactive `/plugin configure education@<marketplace>` any time;
   headless, `--config` applies only on a fresh install — uninstall then reinstall to
   reconfigure). Claude Code owns persistence. Do not hand-edit any `pluginConfigs` key.
6. Tell the user to rerun `check` after reconfiguration — in a fresh session, since the rendered
   values are injected at load — then verify and report the effective settings.

## Output

Report the current effective `quiz_policy`, the effective report-library root, any recommended
changes, and whether the user must reconfigure through Claude Code. Do not claim a configuration
change until a rerun observes the new rendered values.

## Boundaries

- Do not start a teach, explain, or quiz session; use `/education:teach`, `/education:explain`,
  or `/education:quiz-me`.
- Do not write Claude Code settings.
- Do not invent an organization, repository, marketplace, or environment-variable prefix.
