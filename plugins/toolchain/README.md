# toolchain

A Claude Code plugin for **polyglot build/test/lint verification**. Detect the
ecosystems a change touches and run the right build, test, and lint commands for
each, with the consuming project's own documented commands overriding portable
defaults. Five skills: four for mechanical verification of changed code, and
`/toolchain:ratchet`, which holds a count at a checked-in CI ceiling.

| Skill | Role |
|---|---|
| `/toolchain:check` | Build + test + lint for changed files, auto-detecting the affected ecosystems from git status. Also the reference skill other plugins compose for ecosystem detection and command resolution. |
| `/toolchain:check-prerequisites` | Read-only report of whether the tools the plugin declares in `prerequisites.json` resolve. Installs nothing. |
| `/toolchain:lint` | Lint + format checks only. Faster than a build cycle; `--fix` is format-only, `--code-fix` runs semantic lint autofixes behind a confirmation / `--yes` gate. |
| `/toolchain:ratchet [<counter, rule or claim>]` | Holds a count with a checked-in CI ceiling: a lint rule's violations, a suppression count, a verified performance counter, or a telemetry count. A zero count turns the rule on with no ceiling; a non-zero one is recorded at its measured value in the ceilings file CI already checks (`.performance/ratchets.json` when CI calls `ratchet.py check` with no `--file`), or in a new `.ratchets.json`, with a check step inside the required job and a same-PR or scheduled tightening plan. Counters only, never durations. It writes proposed files uncommitted and never merges. |
| `/toolchain:setup` | Configure the plugin for a repo: `check` (read-only, default) reports the effective configuration; `apply` interviews and writes the tracked config. Re-runnable. |

Each skill's `SKILL.md` is the authoritative contract for its behavior, flags, and
the ecosystem surface it currently covers. Read it there rather than a
restatement here.

## Works in any repo

Command resolution follows the marketplace-wide ecosystem-commands convention
(`docs/contracts/ecosystem-commands/README.md`; schema `ecosystem.schema.json`):
your repo's tracked `.claude/ecosystems/<ecosystem>.yaml` files are authoritative
when present, and the plugin's bundled portable defaults are the last resort.
Testing structure and commit conventions still come from your own `CLAUDE.md` and
rules. All command tables and per-ecosystem context ship inside the plugin via
`${CLAUDE_PLUGIN_ROOT}`; state and artifacts go to your project's own tree.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install toolchain@melodic-software
```

## Configuration

Ecosystem command surfaces live in tracked `.claude/ecosystems/*.yaml` files;
`/toolchain:setup apply` interviews for and persists them (`/toolchain:setup check`
reports the effective configuration). This plugin declares no userConfig options.

## License

MIT (SPDX-License-Identifier: MIT).
