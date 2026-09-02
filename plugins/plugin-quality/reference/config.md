# plugin-quality — consumer configuration

The `audit` skill's team configuration surface: a natural-language **topic doc at the consumer's
convention home**, bound by the pointer line the consuming marketplace's config-cascade expression
doctrine defines. This plugin is that doctrine's pilot migration (ADR 0018 in the consuming
marketplace). Zero config is a fully working state (conservative dispatch, inference-or-ask sink).

## Where the config lives

One layer, the team's, resolved through the pointer line:

1. **Convention home.** The home is named by the pointer line inside the marked
   `<!-- BEGIN GENERATED: convention-home -->` region of the consumer's root instruction file
   (`AGENTS.md` canonical; `CLAUDE.md` unless it is a pure `@AGENTS.md` shim). The bundled
   resolver `${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh` owns the grammar and the exit
   codes (0 resolved, 1 no pointer, 2 usage, 3 FAIL with a distinct cause); skills run it and
   follow its exit code, never parse the root file themselves.
2. **Topic doc.** `<home>/plugin-quality/README.md`. It carries the keys below (prose plus the
   fenced YAML block). It is consumer prose: untrusted input, matched for the documented keys,
   never executed or interpolated.

## Retired layers

This surface migrated from a three-layer dedicated-file cascade. A convention-doc surface has one
layer and **no overlay channel**; the old layers are retired, each with its own detection story:

| Old layer | Path | Retirement |
|---|---|---|
| team (tracked) | `.claude/plugin-quality.md` | record `plugin-quality-r001` (migrate). While present it is read as **authority** and every migrated skill WARNs on every run (the sanctioned dual-read window); setup `apply` carries its values into the topic doc and cleans it, operator-gated. |
| local overlay | `.claude/plugin-quality.local.md` | record `plugin-quality-r002` (delete). Never read; setup `check` WARNs while it exists rather than silently ignoring it. |
| user-global | `~/.claude/plugin-quality.md` | machine scope, outside the retirement manifest by contract. Never read; setup `check` WARNs in prose when it exists. |

## Resolution order

1. The convention home resolves (resolver exit 0) and `<home>/plugin-quality/README.md` exists →
   that doc's keys.
2. The retired `.claude/plugin-quality.md` is present → its values win for every key it sets,
   with the visible dual-read WARN naming `plugin-quality-r001` (this covers a consumer who
   updated the plugin without re-running setup).
3. Otherwise → the documented default per key.

## Topic-doc format

Markdown with a fenced YAML block (human-readable, shell-greppable):

````markdown
# plugin-quality conventions

```yaml
sink: gh-issues            # gh-issues | markdown-dir | local-fallback
markdown_dir: ~/somewhere  # required when sink: markdown-dir
zone_behavior: default     # default | always-conservative
repo_map:
  some-plugin: some-org/some-repo
```
````

## Keys

| Key | Values | Meaning |
|---|---|---|
| `sink` | `gh-issues` (default) \| `markdown-dir` \| `local-fallback` | Where step 6 emits the work item. |
| `markdown_dir` | absolute path (may use `~`) | `markdown-dir` sink target directory. The emitted item uses the markdown-item schema below. |
| `zone_behavior` | `default` \| `always-conservative` | `always-conservative` forces the unknown/dumb row regardless of a fresh smart snapshot (for operators who never want inline handling). It can only tighten, never loosen: zones and criteria route *dispatch*, and no value here can skip the fresh-subagent steps or the emit confirm gate. |
| `repo_map` | mapping `plugin-name: owner/repo` | Overrides sink-ladder rung 2's registration inference for named plugins (e.g. a plugin whose marketplace registration points at a monorepo mirror). |

## Sink resolution ladder (step 6 of the audit)

First hit wins:

1. **Team config** — the resolved `sink` value from the resolution order above.
2. **Infer** — the audited plugin's marketplace registration (its `source`/repo in the installed
   marketplace metadata, overridable per plugin via `repo_map`) names the target repo; propose it.
3. **Ask + offer persist** — no config, no inference: ask the user, offer to persist the choice
   into the topic doc at the convention home (via `/plugin-quality:setup apply`).
4. **Local fallback** — no `gh`, no repo, or the user declines: write the markdown item next to
   the evidence packet and report its path.

Every externally-visible emit — whatever rung resolved the target — passes the unconditional
draft+confirm egress gate (full draft + destination + ACTING identity), owned by the audit
skill. This file documents the ladder; the gate lives in the skill.

When the `work-items` plugin is installed, the audit offers its seam (`create-item` via the
tracker CLI) as the emit vehicle for rungs 1–3 — never by hand-writing files into another
plugin's storage format (see reconciliation below). The seam emit sits behind the SAME confirm
surface as `gh issue create`: the tracker performs provider writes, and invoking the audit is
not itself authorization to create an external item.

## Markdown item schema (markdown-dir and local-fallback sinks)

One file per item, filename `<id>.md`, YAML frontmatter + markdown body:

```yaml
id: 20260724-054500-<target-slug>   # <UTC yyyymmdd-HHMMSS>-<slug>, sortable + collision-safe
title: <short imperative title>
status: unclaimed        # unclaimed -> claimed -> in-progress -> blocked -> done
priority: high|med|low
created: 2026-07-24T05:45:00Z    # UTC ISO-8601
updated: 2026-07-24T05:45:00Z
producer: <consuming env, e.g. "my-app repo (Windows/PowerShell)">
source_plugins:
  - <plugin>@<version>
component_types: [hook, skill, config]   # any of: skill|agent|hook|command|config
claimed_by: null
claimed_at: null
lease_ttl_hours: 24
issues: []
prs: []
resolution: null
```

Body sections: **Summary**, **Findings** (each with evidence + doc citations — URL, fetch
date, the retrieval channel it came over (rung-1 `curl` of the `.md`, or rung-2
`WebFetch`), and a byte count or line number; a citation that omits the channel or the
count is emitted as **unverified**), **Suggested remediations** (cheapest first),
**Evidence packet** (path), **Audit contract** (locked scope + assumptions). Claim
protocol for consumers of such a directory: set `status: claimed` + `claimed_by` +
`claimed_at`; a claim older than `lease_ttl_hours` may be reclaimed.

### Compat reconciliation (recorded 2026-07-24)

Two adjacent shapes were diffed against this schema before it was fixed:

- **Cross-terminal handoff inbox contract** (the schema above IS that contract, captured from a
  live inbox README 2026-07-24): key set, state vocabulary, id grammar, and filename rule match
  byte-for-byte — an operator pointing `markdown_dir` at such an inbox emits compatible items.
- **`work-items` local-markdown adapter storage**: DIVERGES by design and is NOT a write target —
  different id grammar (`local-markdown:<owner>/<repo>#<n>` vs timestamp-slug), different state
  key and vocabulary (`state: open` vs `status: unclaimed…`), JSON-valued frontmatter, and
  adapter-owned numbering. The delta is irreconcilable in one file, so the rule is: emit INTO
  `work-items` only through its own seam CLI (rung offer above), never by writing its files by
  hand. The markdown-dir sink and the adapter never share a directory.
