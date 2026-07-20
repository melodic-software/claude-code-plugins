# testing

A Claude Code plugin for the **test stage** of a disciplined dev workflow — plan
what needs testing, author tests at the right level, verify the running app
end-to-end, and diagnose failures to root cause. Four skills, one concern: proving
behavior with tests.

| Skill | What it does |
|---|---|
| `/testing:plan` | Coverage-gap analysis — classify changed files by required test type, identify gaps, prioritize by regression risk. |
| `/testing:write` | Test authoring discipline — vertical-slice TDD, test-type selection, naming, placement, fixture patterns, four-pillars assessment. |
| `/testing:run-e2e` | Live app verification — start the app via the project's orchestrator, drive UI/API flows with token-efficient browser automation, capture evidence; includes a non-UI smoke-test playbook (MCP stdio handshake, shell/PowerShell surfaces). |
| `/testing:diagnose` | Failing-test diagnosis — failure classification, root-cause analysis (never retry blindly), then the reproduce → isolate → fix → retest → regression loop. |

## Works in any repo

- **Reads your conventions, assumes none.** Test frameworks, project locations,
  naming, fixture patterns, and the e2e-orchestrator configuration come from your own
  project's `CLAUDE.md` / rules and existing test projects; the skills infer from what
  exists when nothing is documented.
- **Cross-plugin refs degrade gracefully.** Test invocation defers to the `toolchain`
  plugin's `/toolchain:check` when installed and to the project's own test command
  otherwise; TDD design questions route to `/tdd:principles`, browser mechanics to
  `/playwright:playwright`, outcome sign-off to `/verification:confirm`, and the
  implement loop to `/implementation:implement` — each used when installed and
  substituted with inline guidance or a manual handoff when absent. No step blocks on a
  missing plugin.
- **Self-contained.** Test-type tables, the E2E evidence contract, the non-UI
  smoke-test playbook, and diagnosis loops ship inside the plugin and are referenced
  via `${CLAUDE_PLUGIN_ROOT}`.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install testing@melodic-software
```

## Configuration

Test structure and conventions come from your own project's `CLAUDE.md` and rules.
This plugin declares no userConfig options.

## License

MIT (SPDX-License-Identifier: MIT).
