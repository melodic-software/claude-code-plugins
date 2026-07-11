# Lane: self-update

The recursive lane — tidy operating on its own plugin files. **Maintainer-facing:** valid ONLY in a working-tree checkout of this plugin (the marketplace clone, or a directory loaded via `--plugin-dir`), never against an installed marketplace copy — consumers receive updates through `/plugin marketplace update`. **This lane is permanently manual-merge.** The risk profile is unique: a bad change here can disable the safety mechanisms that protect every other lane. Read the EXTRA HARD list at the start of every run.

## Scope

```text
skills/tidy/SKILL.md
skills/tidy/lanes/**.md
skills/tidy/templates/**.md
skills/tidy/reference/**.md
skills/batch-simplify/**.md
```

(Paths relative to the plugin root of the working-tree checkout.)

## Watch-for patterns

Restricted to the safest tidyings only — no behavioral grammar changes, no exclusion-list edits, no Action Router edits:

- **Beck #5 — Reading Order** — within SKILL.md body sections, fix flow issues (e.g., "Gotchas" placed before "Workflow" — Workflow should come first)
- **Beck #14 — Explaining Comments** — add a one-line clarifier where a watch-for pattern's intent is non-obvious. Only ADD; never remove existing explanatory text
- **Beck #15 — Delete Redundant Comments** — remove paragraphs that restate the section heading
- **Typo fixes** — straightforward typo corrections in prose. Not in frontmatter (HARD-EXCLUDED), not in code-shaped content (CLI commands, glob patterns)
- **P-2 — Stale cross-reference repair** — references to files that have moved within the plugin

## Lane-specific extra exclusions (SELF-UPDATE EXTRA HARD)

In addition to global HARD/SOFT, this lane has an extra-HARD list that gates ALL its modifications. Read `reference/exclusions.md` SELF-UPDATE EXTRA HARD section in full before any edit.

Summary of what this lane CANNOT modify, even though the files are technically in scope:

- **All skill frontmatter** — every field, across both skills' SKILL.md files
- **The HARD/SOFT exclusion lists themselves** in `reference/exclusions.md` — the safety net cannot tidy itself
- **The Action Router section** of `SKILL.md` — the argument grammar is a contract with users
- **The Workflow phase list** — phase names and order are part of the contract; renumbering or renaming changes behavior
- **The Lane catalog + lane-resolution sections** — the `.claude/tidy-lanes/` consumer contract is a published interface
- **Lane scope globs** — every lane file's `## Scope` block
- **Watch-for tidying lists** — the lane files' `## Watch-for patterns` blocks
- **`reference/scope-budget.md` numbers** — the 200/8 target and 400/15 cap came from research; changing them needs research, not a tidy

If during a self-update run you find drift in any of the EXTRA HARD areas: **clean exit, NO PR, report what was found to the user.** The user reviews and decides.

## Verification commands

```bash
npx markdownlint-cli2 <changed .md files>
bash skills/tidy/scripts/open-pr-count.test.sh    # if the script changed (it shouldn't in this lane)
```

## Conventional Commits type

`chore(tidy):`. Example title: `chore(tidy): self-update — fix typos in lane file headers`.

## Preferred research sources

- **Anthropic skill-authoring best-practices guide** (`platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices`)
- **Kent Beck, *Tidy First?*** — when a candidate's structural-vs-behavioral classification is uncertain
