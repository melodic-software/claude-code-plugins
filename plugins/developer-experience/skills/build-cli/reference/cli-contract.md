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

Read the pointer, not this summary, before relying on a detail it carries.

| # | Rule | What a command must do | Count | Source (pointer) |
|---|---|---|---|---|
| 1 | Non-interactive | Never wait for input when stdin is not a terminal or a no-prompt switch is set. Every input can be given as an argument, flag or stdin; a missing one fails at once, naming the flag. | 4 | <https://clig.dev/#interactivity> and "Arguments and flags"; <https://learn.microsoft.com/en-us/dotnet/standard/commandline/design-guidance> ("Short-form aliases", `--interactive`); <https://cli.github.com/manual/gh_help_environment> (`GH_PROMPT_DISABLED`); <https://developer.hashicorp.com/terraform/cli/commands/plan> (`-input=false`). |
| 2 | Machine-readable output | Offers a structured mode (JSON) whose shape callers can rely on, beside the human default. | 3 | <https://clig.dev/#output>; <https://cli.github.com/manual/gh_help_formatting>; <https://learn.microsoft.com/en-us/cli/azure/format-output-azure-cli>. Related, not counted: <https://code.claude.com/docs/en/best-practices> ("Run non-interactive mode"). |
| 3 | Bounded output | Output an agent reads can be narrowed: filtering, field selection, paging or truncation, with defaults that keep it small. | 3 | <https://www.anthropic.com/engineering/writing-tools-for-agents> ("Optimizing tool responses for token efficiency"); <https://cli.github.com/manual/gh_help_formatting> (`--json` field list); <https://learn.microsoft.com/en-us/cli/azure/format-output-azure-cli> (`--query`). Related, not counted: <https://justin.poehnelt.com/posts/rewrite-your-cli-for-ai-agents/> (personal blog). |
| 4 | Exit codes | Exits 0 on success and non-zero on failure, with distinct, documented codes for the main failure modes. | 3 | <https://clig.dev/#the-basics>; <https://cli.github.com/manual/gh_help_exit-codes>; <https://developer.hashicorp.com/terraform/cli/commands/plan> (`-detailed-exitcode`). Related, not counted: <https://code.claude.com/docs/en/best-practices#give-claude-a-check-to-run>. |
| 5 | Help | Every command and subcommand answers `--help` with concise usage that leads with real examples. | 1 | <https://clig.dev/#help>. Related, not counted: <https://code.claude.com/docs/en/best-practices> ("Use CLI tools"). |
| 6 | Confirm bypass, dry-run | A command that changes state confirms before a dangerous change and has an explicit flag that skips the confirmation; without that flag, the default stays safe for a person. It should also offer a preview mode that reports what would change and changes nothing; only one community source makes the preview a must. | 1 | <https://clig.dev/#arguments-and-flags> (dangerous operations, `--force`, the dry-run guidance, which is a should). Community, not counted: <https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess> (vendor-hosted community article; `-WhatIf`, `-Confirm:$false`, `-Force`); <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md> (dry-run as a must). |
| 7 | Idempotence | Running a successful command again is a no-op or reports it is already done; where that is impossible, a re-run recovers from where a failed run stopped. | 2 | <https://clig.dev/#robustness-guidelines> ("Make it recoverable") and Philosophy "Robustness" (<https://clig.dev/#robustness-principle>); <https://github.com/ansible/ansible-documentation/blob/devel/docs/docsite/rst/dev_guide/developing_modules_best_practices.rst> (consistent final state). Community, not counted: <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md>. |
| 8 | Actionable errors | An error says what went wrong and what to do next, with the flag to pass or a correct example invocation; it fails fast instead of hanging, and a bare code or stack trace is never the whole message. | 2 | <https://clig.dev/#errors>; <https://www.anthropic.com/engineering/writing-tools-for-agents> ("Optimizing tool responses for token efficiency"). Community, not counted: <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md>. |
| 9 | Prompt-free auth | Authentication needs no prompt and no browser: the caller supplies the credential non-interactively, by the channels [Secrets](#secrets) allows. | 3 | Non-interactive auth: <https://cli.github.com/manual/gh_help_environment> (`GH_TOKEN`); <https://docs.docker.com/reference/cli/docker/login/> ("Provide a password using STDIN (--password-stdin)"); <https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-service-principal> (`az login --service-principal` with `--certificate`). The secret channel only, not counted for auth: <https://clig.dev/#arguments-and-flags>. |
| 10 | Interface as a contract | Commands, flags, environment variables and machine-readable output change additively; a breaking change is warned about in the tool before it lands. Human-formatted output may usually change. | 2 | <https://clig.dev/#future-proofing>; <https://kubernetes.io/docs/reference/using-api/deprecation-policy/> (Rule 6, warnings for deprecated CLI elements). Related, not counted: <https://learn.microsoft.com/en-us/dotnet/standard/commandline/design-guidance> (opening section, motivation only). |
| 11 | No inherited handles | A command that starts a long-running app or other child does not let it inherit the caller's stdin, stdout or stderr: redirect the three to null or a file, and detach it so the caller need not wait. A child holding the caller's pipe keeps a piped caller (a script, a CI step, an agent) waiting after the command itself has returned. On Windows, start a child given redirected streams with an explicit list of the handles it may inherit, naming only its null or file handles, and start a child given no redirected streams with inheritance off; read why from the Windows pointers in Sources. | 3 | <https://nodejs.org/api/child_process.html#optionsstdio> (`stdio`) and <https://nodejs.org/api/child_process.html#optionsdetached> (`detached`, `subprocess.unref()`); <https://docs.python.org/3/library/subprocess.html#frequently-used-arguments> (`stdin`, `stdout`, `stderr`, `DEVNULL`) and <https://docs.python.org/3/library/subprocess.html#popen-constructor> (`start_new_session`, `close_fds`); <https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw#parameters> (`bInheritHandles`) and <https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw#remarks> (`PROC_THREAD_ATTRIBUTE_HANDLE_LIST`), with <https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/ns-processthreadsapi-startupinfow#members> (`STARTF_USESTDHANDLES`). No page says a child holding the caller's pipe keeps a piped caller waiting; that consequence, and the Windows handle-list choice, are this plugin's application of these sections. |
| 12 | One document on `--json` stdout | A command that runs several sub-steps (a composite command) writes one JSON document to stdout under `--json` and sends every sub-step's own output, progress and logs to stderr. | 1 | <https://code.claude.com/docs/en/headless#background-tasks-at-exit> (where the progress line goes under `json` output) and <https://code.claude.com/docs/en/headless#get-structured-output>. The page covers Claude Code's own output only; the composite-command rule is this plugin's application of it. The stdout-and-stderr split in general is in [Options from a single source](#options-from-a-single-source). |
| 13 | Find the real process | A recorded pid may belong to a wrapper (a shell, a launcher) and not to the app. Before attaching to, signaling or waiting on the app, resolve the real app process (for example the wrapper's child) and confirm it is the app. | 2 | <https://docs.python.org/3/library/subprocess.html#subprocess.Popen.pid> (what the pid names under `shell=True`); <https://nodejs.org/api/child_process.html#subprocesskillsignal> (the example of killing the shell that started a process). |
| 14 | Reject bad input fast | Reject an unknown flag, a repeated step id, a malformed id, and an unknown app or environment name before any step runs, with a non-zero exit and a message naming the bad value and the valid ones. Do not ignore, pass through or guess. | 2 | <https://docs.python.org/3/library/argparse.html#invalid-arguments> and <https://docs.python.org/3/library/argparse.html#choices> (how `parse_args()` reports an unrecognized argument or an invalid choice), with <https://docs.python.org/3/library/argparse.html#argparse.ArgumentParser.parse_known_args> as the lenient form; <https://code.claude.com/docs/en/headless#basic-usage> (how Claude Code reports an invalid flag). Neither source covers repeated or malformed ids; that part is this plugin's application of the same fail-fast rule. |
| 15 | Name the override that wins | When a setting can come from a flag, an environment variable or a file, state which one the app actually honors and in what order, from the app's own documentation or code. Never assume an environment variable wins. | 1 | <https://code.claude.com/docs/en/settings#settings-precedence> (how environment variables and settings keys combine). The page documents Claude Code's own precedence only; the general rule is this plugin's application of it. |

## Secrets

A tool reads a secret from an environment variable or stdin (or a file the caller names), and a
secret is never a flag value: a flag value can leak through the process list and shell history.
This is the plugin's default rule; the conventions file's `Secrets` section wins when the team
recorded another.

- Never a flag value: <https://clig.dev/#arguments-and-flags>;
  <https://docs.docker.com/reference/cli/docker/login/> ("Provide a password using STDIN
  (--password-stdin)"). Two sources.
- Dissent on environment variables: the same guide advises against reading secrets from them
  (<https://clig.dev/#environment-variables>). The plugin default allows them; when the team's conventions forbid them, use stdin or
  a credential file.

## Options from a single source

Offer these as options with their attribution; never present one as a rule.

| Option | Source (pointer) |
|---|---|
| Data on stdout, messages (logs, progress, errors) on stderr | <https://clig.dev/#the-basics>. |
| Deeper help one level down, so a caller learns one subcommand at a time | <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md> (community skill). |
| Meaningful identifiers in output rather than opaque ones | <https://www.anthropic.com/engineering/writing-tools-for-agents> ("Returning meaningful context from your tools"). |
| A version field on machine-readable output: a minor bump for additive changes, a major bump for breaking ones | <https://developer.hashicorp.com/terraform/internals/json-format> (`format_version`). |
| A stated deprecation window before removing a command or flag | <https://kubernetes.io/docs/reference/using-api/deprecation-policy/> (Rule 5a). Its window is set for a large platform; no source sets one for a team script. |
| Prompting only when asked (an `--interactive` switch) instead of detecting a terminal | <https://learn.microsoft.com/en-us/dotnet/standard/commandline/design-guidance> ("Short-form aliases", `-i`/`--interactive`). |
