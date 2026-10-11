# Changelog

All notable changes to the `display-redaction` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-11

### Added

- A mod that masks email addresses and secret-shaped text (`sk-` keys, `ghp_`/`github_pat_`
  tokens, `xox*` Slack tokens, `AKIA` AWS key IDs, JWTs, PEM private-key blocks) in what Claude
  Code draws: replies, prompts, tool calls and output, command output, question prompts and info
  notices. It masks the screen only.
- The `extra_patterns` option for your own patterns.
- `/display-redaction on` and `/display-redaction off` for the current session.
