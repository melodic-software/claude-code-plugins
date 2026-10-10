# The CLI contract

Read before planning a new or changed command, and before a review. A command or script meets
every rule below, unless the conventions file records a team rule that says otherwise. Each row's
Count column gives the number of independent authoritative sources behind that rule; a pointer
marked related or community is context and is not counted. The options after the table are one
source's guidance, offered with their attribution, not required.

## Contents

- [Rules](#rules)
- [Secrets](#secrets)
- [Options from a single source](#options-from-a-single-source)

## Rules

Every source below was read on 2026-10-09. Read the pointer, not this summary, before relying on
a detail it carries.

| # | Rule | What a command must do | Count | Source (pointer, as-of, recheck trigger) |
|---|---|---|---|---|
| 1 | Non-interactive | Never wait for input when stdin is not a terminal or a no-prompt switch is set. Every input can be given as an argument, flag or stdin; a missing one fails at once, naming the flag. | 4 | <https://clig.dev/#interactivity> and "Arguments and flags"; <https://learn.microsoft.com/en-us/dotnet/standard/commandline/design-guidance> ("Short-form aliases", `--interactive`); <https://cli.github.com/manual/gh_help_environment> (`GH_PROMPT_DISABLED`); <https://developer.hashicorp.com/terraform/cli/commands/plan> (`-input=false`). As of 2026-10-09. Recheck: clig.dev's Interactivity section changes, or a cited CLI drops its no-prompt switch. |
| 2 | Machine-readable output | Offers a structured mode (JSON) whose shape callers can rely on, beside the human default. | 3 | <https://clig.dev/#output>; <https://cli.github.com/manual/gh_help_formatting>; <https://learn.microsoft.com/en-us/cli/azure/format-output-azure-cli>. Related, not counted: <https://code.claude.com/docs/en/best-practices> ("Run non-interactive mode"). As of 2026-10-09. Recheck: clig.dev's Output section changes. |
| 3 | Bounded output | Output an agent reads can be narrowed: filtering, field selection, paging or truncation, with defaults that keep it small. | 3 | <https://www.anthropic.com/engineering/writing-tools-for-agents> ("Optimizing tool responses for token efficiency"); <https://cli.github.com/manual/gh_help_formatting> (`--json` field list); <https://learn.microsoft.com/en-us/cli/azure/format-output-azure-cli> (`--query`). Related, not counted: <https://justin.poehnelt.com/posts/rewrite-your-cli-for-ai-agents/> (personal blog). As of 2026-10-09. Recheck: the agent-tools article is revised. |
| 4 | Exit codes | Exits 0 on success and non-zero on failure, with distinct, documented codes for the main failure modes. | 3 | <https://clig.dev/#the-basics>; <https://cli.github.com/manual/gh_help_exit-codes>; <https://developer.hashicorp.com/terraform/cli/commands/plan> (`-detailed-exitcode`). Related, not counted: <https://code.claude.com/docs/en/best-practices> ("Give Claude a way to verify its work"). As of 2026-10-09. Recheck: clig.dev's The Basics section changes. |
| 5 | Help | Every command and subcommand answers `--help` with concise usage that leads with real examples. | 1 | <https://clig.dev/#help>. Related, not counted: <https://code.claude.com/docs/en/best-practices> ("Use CLI tools"). As of 2026-10-09. Recheck: clig.dev's Help section changes. |
| 6 | Confirm bypass, dry-run | A command that changes state confirms before a dangerous change and has an explicit flag that skips the confirmation; without that flag, the default stays safe for a person. It should also offer a preview mode that reports what would change and changes nothing; only one community source makes the preview a must. | 1 | <https://clig.dev/#arguments-and-flags> (dangerous operations, `--force`, the dry-run guidance, which is a should). Community, not counted: <https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess> (vendor-hosted community article; `-WhatIf`, `-Confirm:$false`, `-Force`); <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md> (dry-run as a must). As of 2026-10-09. Recheck: clig.dev's dangerous-operation guidance changes. |
| 7 | Idempotence | Running a successful command again is a no-op or reports it is already done; where that is impossible, a re-run recovers from where a failed run stopped. | 2 | <https://clig.dev/#robustness-guidelines> ("Make it recoverable") and Philosophy "Robustness" (<https://clig.dev/#robustness>); <https://github.com/ansible/ansible-documentation/blob/devel/docs/docsite/rst/dev_guide/developing_modules_best_practices.rst> (consistent final state). Community, not counted: <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md>. As of 2026-10-09. Recheck: either clig.dev Robustness section or the module best-practices page changes. |
| 8 | Actionable errors | An error says what went wrong and what to do next, with the flag to pass or a correct example invocation; it fails fast instead of hanging, and a bare code or stack trace is never the whole message. | 2 | <https://clig.dev/#errors>; <https://www.anthropic.com/engineering/writing-tools-for-agents> ("Optimizing tool responses for token efficiency"). Community, not counted: <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md>. As of 2026-10-09. Recheck: clig.dev's Errors section changes. |
| 9 | Prompt-free auth | Authentication needs no prompt and no browser: the caller supplies the credential non-interactively, by the channels [Secrets](#secrets) allows. | 3 | Non-interactive auth: <https://cli.github.com/manual/gh_help_environment> (`GH_TOKEN`); <https://docs.docker.com/reference/cli/docker/login/> ("Provide a password using STDIN (--password-stdin)"); <https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-service-principal> (`az login --service-principal` with `--certificate`). The secret channel only, not counted for auth: <https://clig.dev/#arguments-and-flags>. As of 2026-10-09. Recheck: a cited CLI drops its non-interactive sign-in, or clig.dev changes its secrets guidance. |
| 10 | Interface as a contract | Commands, flags, environment variables and machine-readable output change additively; a breaking change is warned about in the tool before it lands. Human-formatted output may usually change. | 2 | <https://clig.dev/#future-proofing>; <https://kubernetes.io/docs/reference/using-api/deprecation-policy/> (Rule 6, warnings for deprecated CLI elements). Related, not counted: <https://learn.microsoft.com/en-us/dotnet/standard/commandline/design-guidance> (opening section, motivation only). As of 2026-10-09. Recheck: clig.dev's Future-proofing section changes. |

## Secrets

A tool reads a secret from an environment variable or stdin (or a file the caller names), and a
secret is never a flag value: a flag value can leak through the process list and shell history.
This is the plugin's default rule; the conventions file's `Secrets` section wins when the team
recorded another.

- Never a flag value: <https://clig.dev/#arguments-and-flags>;
  <https://docs.docker.com/reference/cli/docker/login/> ("Provide a password using STDIN
  (--password-stdin)"). Two sources, as of 2026-10-09. Recheck: clig.dev changes its secrets
  guidance, or Docker drops `--password-stdin`.
- Dissent on environment variables: the same guide advises against reading secrets from them
  (<https://clig.dev/#environment-variables>, as of 2026-10-09; recheck when that section
  changes). The plugin default allows them; when the team's conventions forbid them, use stdin or
  a credential file.

## Options from a single source

Offer these as options with their attribution; never present one as a rule.

| Option | Source (pointer, as-of, recheck trigger) |
|---|---|
| Data on stdout, messages (logs, progress, errors) on stderr | <https://clig.dev/#the-basics>. As of 2026-10-09. Recheck: that section changes. |
| Deeper help one level down, so a caller learns one subcommand at a time | <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md> (community skill). As of 2026-10-09. Recheck: that skill is revised. |
| Meaningful identifiers in output rather than opaque ones | <https://www.anthropic.com/engineering/writing-tools-for-agents> ("Returning meaningful context from your tools"). As of 2026-10-09. Recheck: the article is revised. |
| A version field on machine-readable output: a minor bump for additive changes, a major bump for breaking ones | <https://developer.hashicorp.com/terraform/internals/json-format> (`format_version`). As of 2026-10-09. Recheck: that page changes its versioning rules. |
| A stated deprecation window before removing a command or flag | <https://kubernetes.io/docs/reference/using-api/deprecation-policy/> (Rule 5a). As of 2026-10-09. Recheck: Rule 5a changes. Its window is set for a large platform; no source sets one for a team script. |
| Prompting only when asked (an `--interactive` switch) instead of detecting a terminal | <https://learn.microsoft.com/en-us/dotnet/standard/commandline/design-guidance> ("Short-form aliases", `-i`/`--interactive`). As of 2026-10-09. Recheck: that section changes. |
