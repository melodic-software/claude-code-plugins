# Security Policy

This marketplace distributes plugins — skills, hooks, and agents — that run code on a consumer's machine and
can wire Claude Code to external systems. Security reports about a published plugin, the marketplace catalog, or
this repository's own tooling are all in scope.

## Reporting a Vulnerability

Please do **not** report security vulnerabilities through public GitHub issues, discussions, or pull requests.

Report them privately through GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability):

1. Open the **Security** tab of this repository.
2. Click **Report a vulnerability** and complete the advisory form.

If private reporting is not available, email **<security@melodicsoftware.com>** instead.

Please include enough detail to reproduce and assess the issue: the affected plugin and version (from its
`plugin.json`), the impact, and reproduction steps. If the report concerns a plugin that executes code (a hook)
or connects to a remote MCP server, note the specific command, endpoint, or data flow involved. We will
acknowledge your report and keep you informed as we investigate and address it.

## Supported Versions

Fixes are applied to the latest released version of each plugin on the default branch; consumers receive them by
updating the marketplace (a plugin delivers a change only on a `version` bump in its `plugin.json`). Older plugin
versions are not maintained.
