# Changelog

All notable changes to the `display-redaction` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-10-17

### Fixed

- The generated plugin options section of the README no longer claims which setup route most people prefer.

## [0.1.0] - 2026-10-11

### Added

- A mod that masks email addresses and secret-shaped text (`sk-` keys, `ghp_`/`gho_`/`ghu_`/
  `ghs_`/`ghr_`/`github_pat_` tokens, `xox*` Slack tokens, `AKIA` AWS key IDs, JWTs, PEM and PGP
  private-key blocks) in what Claude Code draws: replies, prompts, tool calls and output, command
  output, question prompts and info notices, including a match right after a terminal color code.
  It masks the screen only, and a hook that fails draws the row's text as `[hidden]`.
- The `mask_style` option: `block`, the default, draws each match in replies, prompts and command
  output as a solid bar that shows the value on hover, as the hide-email mod in Anthropic's "Mods
  in Claude Code" video does; `text` draws `[hidden]`, which tool rows always use.
- `block` uses the video's exact colors only where the terminal advertises full color
  (`COLORTERM` is `truecolor` or `24bit`), and theme colors otherwise.
- The `extra_patterns` option for your own patterns; a pattern that could backtrack too long is
  skipped, and each runs over bounded windows of the text.
- `/display-redaction on` and `/display-redaction off` for the current session.
