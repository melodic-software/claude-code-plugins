# Claude Code changelog

> Release notes for Claude Code, including new features, improvements, and bug fixes by version.

This page is generated from the [CHANGELOG.md on GitHub](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md).

Run `claude --version` to check your installed version.

<Update label="2.1.263" description="September 6, 2026">
  * Bug fixes and reliability improvements
</Update>

<Update label="2.1.261" description="September 4, 2026">
  * Added an "Organization policy" line to `/status` and `claude doctor` that says why your organization's policy could not be loaded
  * Added `bashOutputMaxChars` and `taskOutputMaxChars` settings to raise how much command and background-task output Claude receives inline before it is saved to a file
  * Added `--append-subagent-system-prompt-file` to read the subagent system prompt from a file
  * Added `/skill-doctor` to show which loaded skills go unused and what they cost in context
  * Fixed typed or pasted characters occasionally landing out of order during fast input
  * [VSCode] Fixed the extension's diff view losing its scroll position on refresh
</Update>

<Update label="2.1.260" description="September 3, 2026">
  * Changing effort on a Fable 5.1 session no longer invalidates the prompt cache
  * `/reload-plugins` now runs in `-p` and SDK sessions
  * Removed the 60-minute cap on subagent background commands
  * Fixed `!` bash mode running inside the sandbox; it runs outside by design
</Update>

<Update label="2.1.259" description="September 2, 2026">
  * Added `--permission-prompts none` to deny, instead of prompting for, any call a permission prompt would have asked about
  * Added `claude plugin validate --json` for machine-readable per-file errors and warnings
  * Unparsable managed settings now refuse to start Claude Code and name the source
  * Skill frontmatter `model:` is honored interactively, scoped to the turn
  * [VSCode] Added a status-bar item for the active model
</Update>

<Update label="2.1.258" description="September 1, 2026">
  * Bug fixes and reliability improvements
</Update>

<Update label="2.1.257" description="August 31, 2026">
  * Read and Edit deny rules now cover redirect targets in Bash commands
  * `defaultMode` values `auto` and `bypassPermissions` are ignored in project scope
  * `strictPluginOnlyCustomization` accepts a per-surface array
  * Added `permissions.blockReadsOutsideWorkingDirectories`
  * `/doctor` warns about sandbox mask files left by a killed session
</Update>
