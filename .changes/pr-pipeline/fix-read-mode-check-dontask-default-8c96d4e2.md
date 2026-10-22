---
bump: patch
---

### Fixed

- The read runner's permission-mode check accepts a leg whose CLI reports `default` when `dontAsk` was asked for, so read-runner skills such as fix-ci no longer fail after their model leg ([#8964](https://github.com/melodic-software/claude-code-plugins/pull/8964)). The launcher's `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` forces the CLI into `default`, and the launcher always passes `--permission-prompts none`, under which Claude Code denies every call no rule allows ([CLI reference](https://code.claude.com/docs/en/cli-reference)). Every other mismatch still fails, and a test fails any launcher pin not yet checked to pass that flag.
