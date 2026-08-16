# toolchain

A Claude Code plugin for **polyglot build/test/lint verification** — detect the
ecosystems a change touches and run the right build, test, and lint commands for
each, with the consuming project's own documented commands overriding portable
defaults. Three skills, one concern: mechanical verification of changed code.

| Skill | Role |
|---|---|
| `/toolchain:check` | Build + test + lint for changed files, auto-detecting the affected ecosystems from git status. Also the reference skill other plugins compose for ecosystem detection and command resolution. |
| `/toolchain:lint` | Lint + format checks only — faster than a build cycle; `--fix` is format-only, `--code-fix` runs semantic lint autofixes behind a confirmation / `--yes` gate. |
| `/toolchain:setup` | Configure the plugin for a repo: `check` (read-only, default) reports the effective configuration; `apply` interviews and writes the tracked config. Re-runnable. |

Each skill's `SKILL.md` is the authoritative contract for its behavior, flags, and
the ecosystem surface it currently covers — read it there rather than a
restatement here.

## Works in any repo

Command resolution follows the marketplace-wide ecosystem-commands convention
(`docs/conventions/ecosystem-commands/README.md`; schema `ecosystem.schema.json`):
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
