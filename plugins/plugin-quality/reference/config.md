# plugin-quality — consumer configuration

The `audit` skill's configuration surface: `.claude/plugin-quality.md`, layered per the consuming
marketplace's config-cascade convention. All layers are optional — zero config is a fully working
state (conservative dispatch, inference-or-ask sink).

## Layers and merge semantics

Three layers, resolved in this order (a later layer refines an earlier one):

| Order | Layer | Path |
|---|---|---|
| 1 | user-global | `~/.claude/plugin-quality.md` |
| 2 | team (tracked) | `${CLAUDE_PROJECT_DIR}/.claude/plugin-quality.md` |
| 3 | local overlay (gitignored) | `${CLAUDE_PROJECT_DIR}/.claude/plugin-quality.local.md` |

**Merge form: per-key override (declared here per the cascade convention).** The keys below are
scalars and closed mappings, where concatenation is meaningless — a later layer replaces an
earlier layer's value key by key; a key absent from a later layer keeps the earlier value;
wholesale replacement is forbidden. Repo-map entries merge per plugin name (a later layer's entry
for plugin X wins for X only).

All three layers absent → fall through to the sink ladder's inference rung.

## File format

Markdown with a fenced YAML block (human-readable, shell-greppable):

```markdown
# plugin-quality config

​```yaml
sink: gh-issues            # gh-issues | markdown-dir | local-fallback
markdown_dir: ~/somewhere  # required when sink: markdown-dir
zone_behavior: default     # default | always-conservative
repo_map:
  some-plugin: some-org/some-repo
​```
```

## Keys

| Key | Values | Meaning |
|---|---|---|
| `sink` | `gh-issues` (default) \| `markdown-dir` \| `local-fallback` | Where step 6 emits the work item. |
| `markdown_dir` | absolute path (may use `~`) | `markdown-dir` sink target directory. The emitted item uses the markdown-item schema below. |
| `zone_behavior` | `default` \| `always-conservative` | `always-conservative` forces the unknown/dumb row regardless of a fresh smart snapshot (for operators who never want inline handling). It can only tighten, never loosen: zones and criteria route *dispatch*, and no value here can skip the fresh-subagent steps or the emit confirm gate. |
| `repo_map` | mapping `plugin-name: owner/repo` | Overrides sink-ladder rung 2's registration inference for named plugins (e.g. a plugin whose marketplace registration points at a monorepo mirror). |

## Sink resolution ladder (step 6 of the audit)

First hit wins:

1. **Tracked config** — the merged `sink` value from the layers above.
2. **Infer** — the audited plugin's marketplace registration (its `source`/repo in the installed
   marketplace metadata, overridable per plugin via `repo_map`) names the target repo; propose it.
3. **Ask + offer persist** — no config, no inference: ask the user, offer to write the choice to
   the tracked config layer they pick.
4. **Local fallback** — no `gh`, no repo, or the user declines: write the markdown item next to
   the evidence packet and report its path.

Every `gh issue create` — whatever rung resolved the target — passes the unconditional
draft+confirm egress gate (full draft + target repo + ACTING `gh` account), owned by the audit
skill. This file documents the ladder; the gate lives in the skill.

When the `work-items` plugin is installed, the audit offers its seam (`create-item` via the
tracker CLI) as the emit vehicle for rungs 1–3 — never by hand-writing files into another
plugin's storage format (see reconciliation below).

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

Body sections: **Summary**, **Findings** (each with evidence + doc citations), **Suggested
remediations** (cheapest first), **Evidence packet** (path), **Audit contract** (locked scope +
assumptions). Claim protocol for consumers of such a directory: set `status: claimed` +
`claimed_by` + `claimed_at`; a claim older than `lease_ttl_hours` may be reclaimed.

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
