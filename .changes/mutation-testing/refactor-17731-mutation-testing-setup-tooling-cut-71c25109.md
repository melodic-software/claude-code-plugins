---
bump: patch
---

### Changed

- **`/mutation-testing:setup` resolves the mutation tool and the test command from your repository.** `check` probe 1 and `apply` steps 2 and 6 read the configured `tool` first, then follow the plugin's new copy of the ecosystem-resolution steps (`reference/ecosystem-resolution.md`), in place of the bundled manifest list, the per-ecosystem tool pick and the per-runner `test-command` examples; with nothing resolved, `apply` proposes `tool: manual`. The Maven, Gradle and per-project `dotnet test` runner notes in probes 3 and 4 are gone; `dotnet test {tests}` stays as the form the audit's script drives. The config template's `test-command` comment drops its pytest, vitest and Maven examples ([#17731](https://github.com/melodic-software/claude-code-plugins/issues/17731)).
- **The `principles` tooling page no longer maps an ecosystem to a tool.** `tooling.md`'s Established tools table is keyed by tool alone, with the diff-scoping, write-regime and metric-name columns the audit reads; the "Selecting a tool" section, the Shell, Terraform and SQL examples and the `lib/hook-utils.test.sh` worked example are cut.
