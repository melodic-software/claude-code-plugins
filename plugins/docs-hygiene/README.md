# docs-hygiene

A Claude Code plugin bundling documentation-hygiene skills — one cohesive
capability: keeping a repository's tracked markdown lean, deduplicated, and
free of decayed references. Each skill is invocable on its own; together they
cover the flavor, noise, duplication, boundary, rename, worth, loading,
and authoring axes of doc upkeep.

## The skills

| Skill | What it does |
|---|---|
| `/docs-hygiene:compress` | Tightens markdown by dropping flavor (filler, hedging, articles) while preserving all content, behind a mandatory fresh-context semantic-diff audit that reverts any semantic loss. Supports an optional `caveman` plugin backend (`/caveman:compress`) with a built-in in-session fallback. |
| `/docs-hygiene:audit-noise` | Read-only classifier for eight markdown noise shapes (historical citations, ghost refs to ephemeral working directories, "why this file exists" preambles, hard-coupled consumer lists, scope/loading meta-commentary, plan/changeset references, conversational antecedents, tracker/PR back-references) with tiered findings and per-shape treatment guidance. |
| `/docs-hygiene:extract-ssot` | Deduplicates content repeated across 3+ files into a single named source of truth and migrates call sites to cite it by heading — with refuse-fast verification gates (Rule of Three, Tier-0 evidence) so weak clusters are rejected instead of extracted. |
| `/docs-hygiene:audit-encapsulation` | Detects external citations reaching into skill-private surfaces inside `.claude/skills/<name>/` (private subdirectories, heading anchors, schema files) and routes each violation to a remediation path. Ships its own public-surface contract reference. |
| `/docs-hygiene:rename-references` | Sweeps stale references after renames — the forms plain token grep misses: slash-command tokens, relative paths from moved files, frontmatter chains and globs — via a 12-form pattern library with audit, half-rename detection, and apply modes. |
| `/docs-hygiene:audit-derivability` | Read-only, document-level worth classifier: could a fresh agent re-derive this whole document from the code, config, and structure? Weighs derivability, re-derivation cost, drift risk, and fact ownership into a verdict (delete, convert-to-pointer, keep-as-derivation-cache, keep-owns-facts), splits it by audience, and confirms load-bearing deletions with a fresh-context spot-test. Where the other five trim *inside* a doc, this decides whether the doc should exist. |
| `/docs-hygiene:audit-progressive-disclosure` | Read-only progressive-disclosure classifier: grades agent-facing instruction markdown against a three-tier load-cost model (always-loaded / invocation-loaded / on-demand) and emits seven finding shapes in two lanes — split opportunities (oversize, mixed-concerns, tier-mismatch) and hub/spoke structure defects (blind-pointer, orphan-spoke, deep-nesting, missing-toc) — with tiered treatment guidance. Thresholds are advisory and Anthropic-prescribed; a deterministic `detect.sh` emits the facts, the judgment layer adjudicates. |
| `/docs-hygiene:write-for-agents` | The write-side complement to the audit skills: authoring-time doctrine that fires while agent-consumed markdown is being written (CLAUDE.md/AGENTS.md content, rules files, agent-loaded reference docs, pointer lines, doc-plus-pointer extractions) — two-loads budgeting, branch-covering pointers, steps-vs-reference separation, observable completion criteria, split-by-sequence, positive-form prompting — with a verified auto-read surface reference and a trigger-reliability eval suite. |
| `/docs-hygiene:write-for-humans` | The other half of the write-side pair: authoring-time doctrine for prose a **person** reads — end-user READMEs, RFCs, design docs, release notes, tutorials, how-to guides, reference pages, explanations. Resolves the consuming project's own declared style guide first and reaches for a bundled default set only as the fallback (Diátaxis document modes, Google developer style, ASD-STE100 instruction rules, Global English disambiguation), so the plugin never silently imposes a house style. Ships the mode picker, a rhythm section against machine-cadence prose, one sentence-rules spoke, drift-stamped source records, and a seven-item self-check. |

## Requirements

- **Bash + git + jq** — ambient skill mechanics (Git Bash on native Windows;
  the skills' scripts strip CRLF and avoid Windows-hostile constructs).
- **`markdownlint-cli2`** — **required by `/docs-hygiene:compress`**, whose
  post-edit lint pass is the mandatory ship gate. It must be on `PATH` or
  installed in the consuming repo (`node_modules/.bin/markdownlint-cli2`);
  when absent, `compress` stops at the entry point with that remediation
  instead of shipping unverified output. `compress` is the only skill that gates
  its entry point on it; `extract-ssot` names it as one option for its ship-gate
  lint step, and no other skill calls it.
- **`caveman` plugin** (optional) — a compression backend for `compress`;
  absent, an in-session fallback applies and every verification gate still
  runs.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install docs-hygiene@melodic-software
```

## How the skills adapt to your repo

Bare invocations with no target share a confirmation-gated clean-tree /
no-scope fallback (`context/clean-tree-fallback.md`): offer a corpus run with
prescribed defaults, never auto-start, and no-op on decline or silence.

<!-- markdown-discipline-ignore -->
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
