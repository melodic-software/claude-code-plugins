# toolchain

A Claude Code plugin for **polyglot build/test/lint verification** — detect the
ecosystems a change touches and run the right build, test, and lint commands for
each, with the consuming project's own documented commands overriding portable
defaults. Three skills, one concern: mechanical verification of changed code.

| Skill | What it does |
|---|---|
| `/toolchain:check` | Build + test + lint for changed files, auto-detecting affected ecosystems (.NET, Python, TypeScript, Bash, PowerShell, Markdown) from git status; resolves each ecosystem's commands through the shared four-rung ladder. Also the reference skill other plugins compose for ecosystem detection and command resolution. |
| `/toolchain:lint` | Lint + format checks only — faster than a build cycle, honors each tool's config-file opt-in, `--fix` mode where linters support it; also owns the `yaml` and `cross-cutting` lint surfaces. |
| `/toolchain:setup` | Configure the plugin for a repo — interview + infer + write the tracked `.claude/ecosystems/<ecosystem>.yaml` files that `/toolchain:check` and `/toolchain:lint` resolve first, and offer the tracked `.claude/topic-docs.yaml` concern file. Re-runnable. |

## Works in any repo

- **Consumer conventions win — via the ecosystem-commands seam.** `/toolchain:check`
  and `/toolchain:lint` resolve each ecosystem's build/test/lint commands through a
  four-rung ladder: your repo's tracked `.claude/ecosystems/<ecosystem>.yaml`
  (authoritative when present, additive over a `~/.claude/ecosystems/` user-global
  base and a `.local.yaml` overlay) → inference → ask → the plugin's bundled portable
  defaults. Run `/toolchain:setup` to write those files once. The command surface
  conforms to the marketplace-wide contract at
  `docs/conventions/ecosystem-commands/README.md` (schema: `ecosystem.schema.json`);
  testing structure and commit conventions still come from your own `CLAUDE.md` and
  rules.
- **Companion lifecycle plugins degrade gracefully.** `/toolchain:setup` offers the
  `.claude/topic-docs.yaml` concern file that the `implementation` and `verification`
  plugins resolve for artifact placement — offered independent of whether those
  plugins are installed today.
- **Self-contained.** All command tables, the resolution ladder, and per-ecosystem
  context ship inside the plugin and are referenced via `${CLAUDE_PLUGIN_ROOT}`; state
  and artifacts go to your project's own tree.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install toolchain@melodic-software
```

## Configuration

Ecosystem command surfaces live in tracked `.claude/ecosystems/*.yaml` files, and
artifact placement is governed by the tracked `.claude/topic-docs.yaml` concern file;
`/toolchain:setup` interviews for and persists both. This plugin declares no userConfig
options.

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
