# docs-hygiene

A Claude Code plugin bundling documentation-hygiene skills. One cohesive
capability: keeping a repository's tracked markdown lean, deduplicated, and
free of decayed references. Each skill is invocable on its own; together they
cover the flavor, noise, duplication, boundary, rename, worth, loading,
and authoring axes of doc upkeep.

## The skills

| Skill | What it does |
|---|---|
| `/docs-hygiene:compress` | Tightens markdown by dropping flavor (filler, hedging, articles) while preserving all content, behind a mandatory fresh-context semantic-diff audit that reverts any semantic loss. Supports an optional `caveman` plugin backend (`/caveman:compress`) with a built-in in-session fallback. |
| `/docs-hygiene:audit-noise` | Read-only classifier for nine markdown noise shapes (historical citations, ghost refs to ephemeral working directories, "why this file exists" preambles, hard-coupled consumer lists, scope/loading meta-commentary, plan/changeset references, conversational antecedents, tracker/PR back-references, prohibitions with no positive alternative) with tiered findings and per-shape treatment guidance. `--persist-findings` routes the negation findings to the `review:fanout` fix relay. |
| `/docs-hygiene:extract-ssot` | Deduplicates repeated content into a single named source of truth and migrates call sites to cite it by heading. Reports duplication at every multiplicity in three labelled buckets: a lone recap of an existing SSOT, a drifting pair with no declared owner, and a cluster that meets the Rule of Three. Refuse-fast verification gates reserve *creating* a new artifact for three or more instances; below that the skill offers only non-abstracting remedies. |
| `/docs-hygiene:audit-encapsulation` | Detects external citations reaching into skill-private surfaces inside `.claude/skills/<name>/` (private subdirectories, heading anchors, schema files) and routes each violation to a remediation path. Ships its own public-surface contract reference. |
| `/docs-hygiene:rename-references` | Sweeps stale references after renames, the forms plain token grep misses: slash-command tokens, relative paths from moved files, frontmatter chains and globs, via a 12-form pattern library with audit, half-rename detection, and apply modes. |
| `/docs-hygiene:audit-derivability` | Read-only, document-level worth classifier: could a fresh agent re-derive this whole document from the code, config, and structure? Weighs derivability, re-derivation cost, drift risk, and fact ownership into a verdict (delete, convert-to-pointer, keep-as-derivation-cache, keep-owns-facts), splits it by audience, and confirms load-bearing deletions with a fresh-context spot-test. Where the other five trim *inside* a doc, this decides whether the doc should exist. |
| `/docs-hygiene:audit-progressive-disclosure` | Read-only progressive-disclosure classifier: grades agent-facing instruction markdown against a three-tier load-cost model (always-loaded / invocation-loaded / on-demand) and emits seven finding shapes in two lanes. Split opportunities (oversize, mixed-concerns, tier-mismatch) and hub/spoke structure defects (blind-pointer, orphan-spoke, deep-nesting, missing-toc), with tiered treatment guidance. Thresholds are advisory and Anthropic-prescribed; a deterministic `detect.sh` emits the facts, the judgment layer adjudicates. |
| `/docs-hygiene:write-for-agents` | The write-side complement to the audit skills: authoring-time doctrine that fires while agent-consumed markdown is being written (CLAUDE.md/AGENTS.md content, rules files, agent-loaded reference docs, pointer lines, doc-plus-pointer extractions). Two-loads budgeting, branch-covering pointers, steps-vs-reference separation, observable completion criteria, split-by-sequence, positive-form prompting, with a verified auto-read surface reference and a trigger-reliability eval suite. |
| `/docs-hygiene:setup` | Check-centric setup for the plugin's one consumer surface, `.claude/docs-hygiene.json`, which the file-name skills read: `check` resolves all three layers, names the layer behind every key, and verifies that the casing regex compiles, each tier names a known form, each generated file's regenerator resolves, the team layer is tracked, and the overlay is ignored; `apply` writes the team layer per key, idempotently. |
| `/docs-hygiene:audit-file-names` | Read-only inventory of a tree's file names against the configured casing rule: proposes a legal name per offender, finds every reference to each one, classifies each site by shape and by the tier its file belongs to, refuses any plan that would create a case-only path collision, and writes the rename plan the realign stage consumes. Renames nothing and edits nothing. |
| `/docs-hygiene:realign-file-names` | Executes that plan one file at a time, behind one human acceptance each: `git mv`, then only the reference shapes the citing file's tier allows, then the declared regenerator for any generated record. Refuses a blanket yes, a range, a glob, and `all`. Frozen and ambiguous sites are listed and left alone. Never commits and never bumps a version. |
| `/docs-hygiene:generate-file-name-gate` | Emits the check that enforces the rule: a standalone bash checker plus its own suite, with the rule, roots, and exemptions inlined from the resolved configuration, carrying no run-time dependency on this plugin. `--rule` also writes the path-scoped rule file. A rule alone cannot enforce a naming convention, because it loads when a covered file is read, never when one is created. |
| `/docs-hygiene:write-for-humans` | The other half of the write-side pair: authoring-time doctrine for prose a **person** reads. End-user READMEs, RFCs, design docs, release notes, tutorials, how-to guides, reference pages, explanations. Resolves the consuming project's own declared style guide first and reaches for a bundled default set only as the fallback: Diátaxis document modes, Google developer style, ASD-STE100 instruction rules, and Global English disambiguation. The plugin therefore never silently imposes a house style. Ships the mode picker, a rhythm section against machine-cadence prose, one sentence-rules spoke, drift-stamped source records, and a seven-item self-check. |

## Requirements

- **Bash + git + jq**. Ambient skill mechanics (Git Bash on native Windows;
  the skills' scripts strip CRLF and avoid Windows-hostile constructs).
- **`markdownlint-cli2`**. **Required by `/docs-hygiene:compress`**, whose
  post-edit lint pass is the mandatory ship gate. It must be on `PATH` or
  installed in the consuming repo (`node_modules/.bin/markdownlint-cli2`);
  when absent, `compress` stops at the entry point with that remediation
  instead of shipping unverified output. `compress` is the only skill that gates
  its entry point on it; `extract-ssot` names it as one option for its ship-gate
  lint step, and no other skill calls it.
- **`caveman` plugin** (optional), a compression backend for `compress`;
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
your own repository's `CLAUDE.md` / `.claude/rules`, the skills read the
consuming project's context; nothing requires editing the plugin.

## Configuration

This plugin has no `userConfig`. Its detector and fact-emitter scripts are
read-only and make no network call; `compress` persists optional snapshots under
the plugin's own data directory.

The file-name skills read one consumer surface, `.claude/docs-hygiene.json`,
layered as user-global, team (tracked), and a gitignored personal overlay. All
three absent is a valid state: every key has a bundled default, and the defaults
are this marketplace's own values. `/docs-hygiene:setup check` verifies the
resolved document and names the layer that supplied each key, and
`/docs-hygiene:setup apply` writes the team layer and nothing else, never the
consumer's `.gitignore`. Keys, defaults, merge classes, and the policy floor are
documented in [`reference/config.md`](reference/config.md). Every other skill
here is zero-config and reads nothing from that file.

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
