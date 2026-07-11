# docs-hygiene

A Claude Code plugin bundling five documentation-hygiene skills — one cohesive
capability: keeping a repository's tracked markdown lean, deduplicated, and
free of decayed references. Each skill is invocable on its own; together they
cover the flavor, noise, duplication, boundary, and rename axes of doc upkeep.

## The five skills

| Skill | What it does |
|---|---|
| `/docs-hygiene:compress` | Tightens markdown by dropping flavor (filler, hedging, articles) while preserving all content, behind a mandatory fresh-context semantic-diff audit that reverts any semantic loss. Supports an optional `caveman` plugin backend (`/caveman:compress`) with a built-in in-session fallback. |
| `/docs-hygiene:declutter` | Read-only classifier for five markdown noise shapes (historical citations, ghost refs to ephemeral working directories, "why this file exists" preambles, hard-coupled consumer lists, scope/loading meta-commentary) with tiered findings and per-shape treatment guidance. |
| `/docs-hygiene:extract-ssot` | Deduplicates content repeated across 3+ files into a single named source of truth and migrates call sites to cite it by heading — with refuse-fast verification gates (Rule of Three, Tier-0 evidence) so weak clusters are rejected instead of extracted. |
| `/docs-hygiene:encapsulation-audit` | Detects external citations reaching into skill-private surfaces inside `.claude/skills/<name>/` (private subdirectories, heading anchors, schema files) and routes each violation to a remediation path. Ships its own public-surface contract reference. |
| `/docs-hygiene:rename-references` | Sweeps stale references after renames — the forms plain token grep misses: slash-command tokens, relative paths from moved files, frontmatter chains and globs — via a 12-form pattern library with audit, half-rename detection, and apply modes. |

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install docs-hygiene@melodic-software
```

## How the skills adapt to your repo

The bundled defaults are repo-agnostic: detectors run against the repository
they are invoked in, output destinations default to conventional locations
(e.g. `.claude/rules/<topic>.md` for an extracted rule), and ephemeral-path
conventions default to a `.work/<slug>/` example. Refine any of these through
your own repository's `CLAUDE.md` / `.claude/rules` — the skills read the
consuming project's context; nothing requires editing the plugin.

## Configuration

This plugin has no `userConfig`. The bundled scripts are read-only detectors
and fact emitters with no network access; `compress` persists optional
snapshots under the plugin's own data directory.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
