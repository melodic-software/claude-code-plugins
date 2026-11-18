# The CLI contract

Read before planning a new or changed command, and before a review. A command or script meets
every rule below, unless the conventions file records a team rule that says otherwise. Each row's
Count column gives the number of independent authoritative sources behind that rule; a pointer
marked related or community is context and is not counted, and a count of 0 marks a rule this
plugin holds without a counted source. The options after the table are one
source's guidance, offered with their attribution, not required.

## Contents

- [Rules](#rules)
- [Secrets](#secrets)
- [Options from a single source](#options-from-a-single-source)

## Rules

Read the pointer, not this summary, before relying on a detail it carries.

| # | Rule | What a command must do | Count | Source (pointer) |
|---|---|---|---|---|
| 1 | Non-interactive | Never wait for input when stdin is not a terminal or a no-prompt switch is set. Every input can be given as an argument, flag or stdin; a missing one fails at once, naming the flag. | 1 | <https://clig.dev/#interactivity> and "Arguments and flags". |
| 2 | Machine-readable output | Offers a structured mode (JSON) whose shape callers can rely on, beside the human default. | 1 | <https://clig.dev/#output>. Related, not counted: <https://code.claude.com/docs/en/best-practices> ("Run non-interactive mode"). |
| 3 | Bounded output | Output an agent reads can be narrowed: filtering, field selection, paging or truncation, with defaults that keep it small. | 1 | <https://www.anthropic.com/engineering/writing-tools-for-agents> ("Optimizing tool responses for token efficiency"). Related, not counted: <https://justin.poehnelt.com/posts/rewrite-your-cli-for-ai-agents/> (personal blog). |
| 4 | Exit codes | Exits 0 on success and non-zero on failure, with distinct, documented codes for the main failure modes. | 1 | <https://clig.dev/#the-basics>. Related, not counted: <https://code.claude.com/docs/en/best-practices#give-claude-a-check-to-run>. |
| 5 | Help | Every command and subcommand answers `--help` with concise usage that leads with real examples. | 1 | <https://clig.dev/#help>. Related, not counted: <https://code.claude.com/docs/en/best-practices> ("Use CLI tools"). |
| 6 | Confirm bypass, dry-run | A command that changes state confirms before a dangerous change and has an explicit flag that skips the confirmation; without that flag, the default stays safe for a person. It should also offer a preview mode that reports what would change and changes nothing; only one community source makes the preview a must. | 1 | <https://clig.dev/#arguments-and-flags> (dangerous operations, `--force`, the dry-run guidance, which is a should). Community, not counted: <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md> (dry-run as a must). |
| 7 | Idempotence | Running a successful command again is a no-op or reports it is already done; where that is impossible, a re-run recovers from where a failed run stopped. | 1 | <https://clig.dev/#robustness-guidelines> ("Make it recoverable") and Philosophy "Robustness" (<https://clig.dev/#robustness-principle>). Community, not counted: <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md>. |
| 8 | Actionable errors | An error says what went wrong and what to do next, with the flag to pass or a correct example invocation; it fails fast instead of hanging, and a bare code or stack trace is never the whole message. | 2 | <https://clig.dev/#errors>; <https://www.anthropic.com/engineering/writing-tools-for-agents> ("Optimizing tool responses for token efficiency"). Community, not counted: <https://github.com/cursor/plugins/blob/main/cli-for-agent/skills/cli-for-agents/SKILL.md>. |
| 9 | Prompt-free auth | Authentication needs no prompt and no browser: the caller supplies the credential non-interactively, by the channels [Secrets](#secrets) allows. | 0 | No counted source for prompt-free auth; the rule is this plugin's own. The secret channel only, not counted for auth: <https://clig.dev/#arguments-and-flags>. |
| 10 | Interface as a contract | Commands, flags, environment variables and machine-readable output change additively; a breaking change is warned about in the tool before it lands. Human-formatted output may usually change. | 1 | <https://clig.dev/#future-proofing>. |
| 11 | No inherited handles | A command that starts a long-running app or other child does not let it inherit the caller's stdin, stdout or stderr: redirect the three to null or a file, and detach it so the caller need not wait. A child holding the caller's pipe keeps a piped caller (a script, a CI step, an agent) waiting after the command itself has returned. On Windows, start a child given redirected streams with an explicit list of the handles it may inherit, naming only its null or file handles, and start a child given no redirected streams with inheritance off. | 0 | No counted source; the rule, its consequence for a piped caller and the Windows handle-list choice are this plugin's own. |
| 12 | One document on `--json` stdout | A command that runs several sub-steps (a composite command) writes one JSON document to stdout under `--json` and sends every sub-step's own output, progress and logs to stderr. | 1 | <https://code.claude.com/docs/en/headless#background-tasks-at-exit> (where the progress line goes under `json` output) and <https://code.claude.com/docs/en/headless#get-structured-output>. The page covers Claude Code's own output only; the composite-command rule is this plugin's application of it. The stdout-and-stderr split in general is in [Options from a single source](#options-from-a-single-source). |
| 13 | Find the real process | A recorded pid may belong to a wrapper (a shell, a launcher) and not to the app. Before attaching to, signaling or waiting on the app, resolve the real app process (for example the wrapper's child) and confirm it is the app. | 0 | No counted source; the rule is this plugin's own. |
| 14 | Reject bad input fast | Reject an unknown flag, a repeated step id, a malformed id, and an unknown app or environment name before any step runs, with a non-zero exit and a message naming the bad value and the valid ones. Do not ignore, pass through or guess. | 1 | <https://code.claude.com/docs/en/headless#basic-usage> (how Claude Code reports an invalid flag). The page covers Claude Code's own flags only; the rule for other bad input, repeated and malformed ids included, is this plugin's application of the same fail-fast behavior. |
| 15 | Name the override that wins | When a setting can come from a flag, an environment variable or a file, state which one the app actually honors and in what order, from the app's own documentation or code. Never assume an environment variable wins. | 1 | <https://code.claude.com/docs/en/settings#settings-precedence> (how environment variables and settings keys combine). The page documents Claude Code's own precedence only; the general rule is this plugin's application of it. |

## Secrets

A tool reads a secret from an environment variable or stdin (or a file the caller names), and a
secret is never a flag value: a flag value can leak through the process list and shell history.
This is the plugin's default rule; the conventions file's `Secrets` section wins when the team
recorded another.

- Never a flag value: <https://clig.dev/#arguments-and-flags>. One source.
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
