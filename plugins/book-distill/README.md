# book-distill

A Claude Code plugin that turns a technical book (PDF or EPUB) into
concept-organized, author-attributed **skill reference files** through a
structured, multi-session read-write pipeline. It is a neutral generator: it
applies a distillation method to whatever book you point it at.

Invoke it with `/book-distill:book-distill` and give it a source path and a
target skill name.

## What it produces

- **Concept-organized reference files** (60-160 lines each), named by what they
  teach rather than by chapter number, with the author attributed in section
  headers.
- **Routing-table and quick-decision-guide updates** to the target skill's
  `SKILL.md`, so the skill loads the right reference file for a given developer
  question at query time.
- **Multi-author merges** — where two books cover the same concept, their
  content is consolidated into a shared file.

Output lands in a **target skill** inside your project (`.claude/skills/<target>/`) —
either an existing skill it extends or a new one it creates. You name the target
when you invoke the tool, so you always know where the output goes.

## How it works

A book is distilled over several sessions (~3 chapters each) using a strict
**read-one-chapter, write-its-file-immediately** loop — the interleave is what
keeps each file focused. Cross-session progress (the file plan, page map, and a
checklist) is tracked in a progress file under `${CLAUDE_PLUGIN_DATA}`, which
survives plugin updates, and a continuation prompt generated at each session end
tells the next session exactly where to resume. See the skill body for the full
five-phase method.

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

## Requirements

- A PDF or EPUB you have the right to read. PDF works natively with Claude
  Code's Read tool; EPUB requires unzipping and text extraction first.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install book-distill@melodic-software
```

## Configuration

This plugin has no `userConfig`. The two things it needs are supplied when you
invoke it — the **source path** and the **target skill name** — and its
cross-session state persists automatically under `${CLAUDE_PLUGIN_DATA}`. There
is nothing to configure and nothing to edit in the plugin itself.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
