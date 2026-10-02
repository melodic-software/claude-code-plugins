# docs-naming

A Claude Code plugin that plans, applies, and enforces a file-name casing rule
across a tracked tree. One concern: the names of files, and the references that
break when a name changes. The post-rename sweep for a rename someone already
made is `/docs-hygiene:rename-references`, the sibling in the `docs-hygiene`
plugin.

## The skills

| Skill | What it does |
|---|---|
| `/docs-naming:setup` | Check-centric setup for the plugin's one consumer surface, `.claude/docs-naming.json`: `check` resolves all three layers, names the layer behind every key, and verifies that the casing regex compiles, each tier names a known form, each generated file's regenerator resolves, the team layer is tracked, and the overlay is ignored; `apply` writes the team layer per key, idempotently. |
| `/docs-naming:audit-file-names` | Read-only inventory of a tree's file names against the configured casing rule: proposes a legal name per offender, finds every reference to each one, classifies each site by shape and by the tier its file belongs to, refuses any plan that would create a case-only path collision, and writes the rename plan the realign stage consumes. Renames nothing and edits nothing. |
| `/docs-naming:realign-file-names` | Executes that plan one file at a time, behind one human acceptance each: `git mv`, then only the reference shapes the citing file's tier allows, then the declared regenerator for any generated record. Refuses a blanket yes, a range, a glob, and `all`. Frozen and ambiguous sites are listed and left alone. Never commits and never bumps a version. |
| `/docs-naming:generate-file-name-gate` | Emits the check that enforces the rule: a standalone bash checker plus its own suite, with the rule, roots, and exemptions inlined from the resolved configuration, carrying no run-time dependency on this plugin. `--rule` also writes the path-scoped rule file. A rule alone cannot enforce a naming convention, because it loads when a covered file is read, never when one is created. |

## Requirements

- **Bash + git + jq**. Ambient skill mechanics (Git Bash on native Windows;
  the skills' scripts strip CRLF and avoid Windows-hostile constructs). `jq`
  reads the configuration layers; `/docs-naming:setup check` reports a missing
  one as FAIL.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install docs-naming@melodic-software
```

## Configuration

The skills read one consumer surface, `.claude/docs-naming.json`, layered as
user-global, team (tracked), and a gitignored personal overlay
(`.claude/docs-naming.local.json`). All three absent is a valid state: every key
has a bundled default, and the defaults are this marketplace's own values.
`/docs-naming:setup check` verifies the resolved document and names the layer
that supplied each key, and `/docs-naming:setup apply` writes the team layer and
nothing else, never the consumer's `.gitignore`. Keys, defaults, merge classes,
and the policy floor are documented in [`reference/config.md`](reference/config.md).

For one release a layer that is absent under that name and present under the
retired `docs-hygiene` name (`.claude/docs-hygiene.json`) is read from there,
with a warning from the resolver and a WARN row from `/docs-naming:setup check`;
the new name wins when both exist. Rename the file to retire the warning.

## Renames are gated per file

`realign-file-names` accepts one file at a time. The findings artifact does not
declare `type: review-findings`, because that type is auto-applicable by
construction and every rename here moves a tracked file behind one human
acceptance. The artifact contract is
[`context/file-name-findings.md`](context/file-name-findings.md).

## Renaming files: what the plugin does not do for you

`audit-file-names` plans, `realign-file-names` applies one acceptance at a time,
and `generate-file-name-gate` emits the check that keeps the tree from drifting
back. Three things stay with the operator on purpose:

- **The version bump and the changelog entry.** A renamed file inside a
  versioned unit usually needs both, and the shape of each is the consuming
  project's release convention. The realign never edits either.
- **The commit.** The realign leaves the working tree uncommitted so the diff
  gets read before it is recorded. A rename sweep is exactly the change that
  deserves that.
- **Wiring the emitted gate.** The emitter names the CI step, the registry row,
  and the decision record it does not write, and writes none of them.

**Cross-platform verification.** The case-only `git mv` path cannot be observed
on a case-sensitive filesystem, so it is exercised on Windows by this
repository's `test-windows` CI lane, which runs the bundled suites. macOS is
unverified; the scripts avoid the constructs that differ there (no `${x,,}`, no
`sed -i`, existence asked of the git index rather than the filesystem), but no
runner covers it.

## License

MIT (SPDX-License-Identifier: MIT).
