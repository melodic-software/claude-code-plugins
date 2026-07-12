# knowledge

A Claude Code plugin that ingests external knowledge into durable, synthesized
artifacts. Its first shipped pipeline distills a technical book (PDF or EPUB) into
concept-organized, author-attributed **skill reference files**; a re-runnable
`setup` action settles where synthesized artifacts land in the consuming repo.

## Skills

| Skill | Invoke | What it does |
|---|---|---|
| `book-distill` | `/knowledge:book-distill` | Turns a technical book (PDF/EPUB) into concept-organized, author-attributed skill reference files through a structured, multi-session read-write pipeline, updating the target skill's routing table. |
| `setup` | `/knowledge:setup` | Interviews the consumer and persists the `library_dir` config (idempotent — re-run to reconfigure). |

## What book-distill produces

- **Concept-organized reference files** (60-160 lines each), named by what they
  teach rather than by chapter number, with the author attributed in section
  headers.
- **Routing-table and quick-decision-guide updates** to the target skill's
  `SKILL.md`, so the skill loads the right reference file for a given developer
  question at query time.
- **Multi-author merges** — where two books cover the same concept, their
  content is consolidated into a shared file.

You name the target skill when you invoke `/knowledge:book-distill`, so output
lands somewhere you chose (`${CLAUDE_PROJECT_DIR}/.claude/skills/<target>/`) —
either an existing skill it extends or a new one it creates. Cross-session state
(the file plan, page map, and a checklist) persists under `${CLAUDE_PLUGIN_DATA}`,
which survives plugin updates.

## Usage caution — copyright

This plugin is a neutral tool; **you own the rights decision** for everything you
distill with it. A condensed distillation of a copyrighted book is a
**derivative work** (17 U.S.C. §§ 101, 106) — the copyright holder's exclusive
rights include preparing and distributing derivatives — so distilled outputs
carry **redistribution risk**. Keeping a private distillation for your own study
is a different act from publishing, committing, or sharing one; fair use is a
defense raised after the fact, not a safe harbor you can assume in advance.
Publish, commit, or redistribute a distilled output only once you have satisfied
yourself that doing so is lawful for that book. This is a caution, not legal
advice.

The distilled output is written into a skill that Claude later **auto-loads as
model context** — so review it before you commit or share it: treat the source
book as untrusted input and confirm the distillation reflects the book rather than
any instructions injected through its text.

## Requirements

- A PDF or EPUB you have the right to read. PDF works natively with Claude
  Code's Read tool; EPUB requires unzipping and text extraction first.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install knowledge@melodic-software
```

Migrating from the standalone `book-distill` plugin? Nothing to do — the
marketplace's `renames` map migrates `book-distill@melodic-software` to
`knowledge@melodic-software` automatically on your next session; the skill is now
invoked as `/knowledge:book-distill`.

One exception: an **in-progress multi-session distillation** stores its resume
checklist under the plugin's `${CLAUDE_PLUGIN_DATA}` directory, which is keyed by
plugin id and is **not** migrated by `renames` (that map rewrites `enabledPlugins`
and `pluginConfigs`, not plugin data). If you have a distillation in flight, copy
your old `book-distill` plugin-data directory to the new `knowledge` one before
resuming so the resume pointer survives.

## Configuration

One option, prompted at enable time (or set any time with `/knowledge:setup`):

| Option | Type | Default | Purpose |
|---|---|---|---|
| `library_dir` | directory | `.` (repo root) | Project-relative directory where the plugin's ingestion pipelines land synthesized artifacts. `book-distill` is unaffected — it writes to the target skill you name at invocation — so today this is a reserved seam. A working-notes or artifacts convention declared in your own project's `CLAUDE.md` or rules takes precedence. |

`book-distill` itself writes to a **target skill** you name at invocation, so it
needs no configuration to run; `library_dir` is the shared artifact-landing seam
the plugin's ingestion pipelines resolve through.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
