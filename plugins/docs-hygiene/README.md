# docs-hygiene

A Claude Code plugin bundling six documentation-hygiene skills — one cohesive
capability: keeping a repository's tracked markdown lean, deduplicated, and
free of decayed references. Each skill is invocable on its own; together they
cover the flavor, noise, duplication, boundary, rename, and worth axes of doc
upkeep.

## The six skills

| Skill | What it does |
|---|---|
| `/docs-hygiene:compress` | Tightens markdown by dropping flavor (filler, hedging, articles) while preserving all content, behind a mandatory fresh-context semantic-diff audit that reverts any semantic loss. Supports an optional `caveman` plugin backend (`/caveman:compress`) with a built-in in-session fallback. |
| `/docs-hygiene:audit-noise` | Read-only classifier for five markdown noise shapes (historical citations, ghost refs to ephemeral working directories, "why this file exists" preambles, hard-coupled consumer lists, scope/loading meta-commentary) with tiered findings and per-shape treatment guidance. |
| `/docs-hygiene:extract-ssot` | Deduplicates content repeated across 3+ files into a single named source of truth and migrates call sites to cite it by heading — with refuse-fast verification gates (Rule of Three, Tier-0 evidence) so weak clusters are rejected instead of extracted. |
| `/docs-hygiene:audit-encapsulation` | Detects external citations reaching into skill-private surfaces inside `.claude/skills/<name>/` (private subdirectories, heading anchors, schema files) and routes each violation to a remediation path. Ships its own public-surface contract reference. |
| `/docs-hygiene:rename-references` | Sweeps stale references after renames — the forms plain token grep misses: slash-command tokens, relative paths from moved files, frontmatter chains and globs — via a 12-form pattern library with audit, half-rename detection, and apply modes. |
| `/docs-hygiene:audit-derivability` | Read-only, document-level worth classifier: could a fresh agent re-derive this whole document from the code, config, and structure? Weighs derivability, re-derivation cost, drift risk, and fact ownership into a verdict (delete, convert-to-pointer, keep-as-derivation-cache, keep-owns-facts), splits it by audience, and confirms load-bearing deletions with a fresh-context spot-test. Where the other five trim *inside* a doc, this decides whether the doc should exist. |

## Requirements

- **Bash + git + jq** — ambient skill mechanics (Git Bash on native Windows;
  the skills' scripts strip CRLF and avoid Windows-hostile constructs).
- **`markdownlint-cli2`** — **required by `/docs-hygiene:compress`**, whose
  post-edit lint pass is the mandatory ship gate. It must be on `PATH` or
  installed in the consuming repo (`node_modules/.bin/markdownlint-cli2`);
  when absent, `compress` stops at the entry point with that remediation
  instead of shipping unverified output. The other five skills do not use it.
- **`caveman` plugin** (optional) — a compression backend for `compress`;
  absent, an in-session fallback applies and every verification gate still
  runs.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install docs-hygiene@melodic-software
```

## How the skills adapt to your repo

The bundled defaults are repo-agnostic: detectors run against the repository
they are invoked in, output destinations default to conventional locations
(e.g. `.claude/rules/<topic>.md` for an extracted rule), and ephemeral-path
detection follows the marketplace topic-docs convention (memory slices under
`.work/<slug>/`, branch-pruned contract slices under `docs/topics/<slug>/`,
retired `.claude/notes/`). Refine any of these through
your own repository's `CLAUDE.md` / `.claude/rules` — the skills read the
consuming project's context; nothing requires editing the plugin.

## Configuration

This plugin has no `userConfig`. The bundled scripts are read-only detectors
and fact emitters with no network access; `compress` persists optional
snapshots under the plugin's own data directory.

## License

MIT (SPDX-License-Identifier: MIT).
