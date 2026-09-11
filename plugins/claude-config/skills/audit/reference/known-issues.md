# Known GitHub Issues Affecting Settings

Curated [anthropics/claude-code](https://github.com/anthropics/claude-code) issues that commonly
affect project configuration, each paired with the settings-side workaround it drives. This file
tracks **broadly-applicable issues only** and is refreshed through plugin updates. Check live
open/closed status during Phase 3.2 rather than trusting a recorded state here; when no route to
GitHub works in a session, the report states the issue as unverified since its `Last verified`
date, so the reader knows how old the recorded state is.

## Issues with common settings workarounds

| Issue | Settings impact | Common workaround | Last verified |
| --- | --- | --- | --- |
| [#8961](https://github.com/anthropics/claude-code/issues/8961) | Deny rules in `settings.local.json` silently ignored | Place all deny rules in `settings.json` (project-level) | 2026-08-05 |
| [#36808](https://github.com/anthropics/claude-code/issues/36808) | npx is a `.cmd` on Windows; spawn without shell fails | Wrap npx-based MCP servers in a Node.js launcher script | 2026-08-05 |
| [#23869](https://github.com/anthropics/claude-code/issues/23869) | Permission auto-save wrote `:*` prefix rules; closed as not planned | None. `:*` and the space form are equivalent | 2026-08-05 |
| [#15562](https://github.com/anthropics/claude-code/issues/15562) | No `"shell": true` support in `.mcp.json` | Node.js launcher script | 2026-08-05 |
| [#11731](https://github.com/anthropics/claude-code/issues/11731) | npx MCP servers fail on Windows | Node.js launcher script | 2026-08-05 |
| [#1254](https://github.com/anthropics/claude-code/issues/1254) | MCP `env` block may strip `process.env` | A launcher that merges rather than replaces the environment | 2026-08-05 |
| [#27247](https://github.com/anthropics/claude-code/issues/27247) | `enabledPlugins` in `settings.local.json` ignored when absent from `settings.json` | Keep an `enabledPlugins` key in project `settings.json` | 2026-08-05 |
| [#14353](https://github.com/anthropics/claude-code/issues/14353) | MCP tool calls serialized unless `readOnlyHint: true` | None. Performance, not correctness | 2026-08-05 |

## Resolved, verify the fix persists

| Issue | Settings impact | What to verify | Last verified |
| --- | --- | --- | --- |
| [#6699](https://github.com/anthropics/claude-code/issues/6699) | Deny permissions not enforced | Deny rules in `settings.json` work correctly | 2026-08-05 |
| [#11795](https://github.com/anthropics/claude-code/issues/11795) | `$schema` not documented in official docs | `$schema` field works without `/doctor` warnings | 2026-08-05 |
| [#37634](https://github.com/anthropics/claude-code/issues/37634) | Bash resolves to WSL on Windows native installer | Node.js-based launchers are unaffected | 2026-08-05 |

## When this file changes

Rows are added or retired through plugin releases when an upstream issue starts (or stops) affecting
typical project configuration, and the `Last verified` date moves whenever a release re-checks a row
against the live issue. A consuming repo that carries its own issue-driven workarounds records them
in its own conventions; Phase 3.2 checks both.
