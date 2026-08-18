# improvement — consumer configuration

The single home for the `improvement` plugin's config-key contract. The surface is
`.claude/improvement.md`, layered per the marketplace's config-cascade convention. It is read by
`/improvement:find` — Tier 2 evidence-source resolution, plus the hotspot recipe's churn window
and exclusion patterns — and verified/written by `/improvement:setup`. All layers are optional:
**zero config is a fully working state**. Tier 0 repo-native evidence needs nothing declared, and
an absent Tier 2 declaration is a recorded evidence gap in the finder's report, never an error.

## Layers and resolution order

Three layers, resolved in this order — a later layer refines an earlier one:

| Order | Layer | Path | Version control |
|---|---|---|---|
| 1 | user-global | `~/.claude/improvement.md` | outside the worktree — no git verdict applies |
| 2 | team (tracked) | `${CLAUDE_PROJECT_DIR}/.claude/improvement.md` | must be tracked — it is the only layer teammates receive |
| 3 | local overlay | `${CLAUDE_PROJECT_DIR}/.claude/improvement.local.md` | must be gitignored, never staged |

Resolution anchors at the repo root — `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel` — never at the CWD. Every layer that exists is read and merged;
reading one layer and stopping is not resolution. A malformed layer degrades soft: surface the
error, name the layer, resolve as if that layer were absent. Unknown keys are inert. Whenever the
effective config is surfaced to a human, report which layer supplied each value.

## Merge semantics

Declared here per the cascade convention: **per-key override, with two declared list
refinements.**

- **Scalar keys** (`churn_window`, `churn_exclude_defaults`) — a later layer replaces the value
  key by key; a key absent from a later layer keeps the earlier layer's value.
- **`churn_exclude`** — entries **union** across layers, and with the bundled defaults unless
  `churn_exclude_defaults: false`. A later layer adds patterns; it never silently drops an
  earlier layer's.
- **`evidence_sources`** — merges **per source name**: a later layer's entry for source X
  replaces X only. A later layer declaring a source name with an empty body is an explicit
  opt-out that removes the inherited source (reported as removed, not broken).

Wholesale replacement of an earlier layer is forbidden.

## File format

Markdown with a fenced YAML block (human-readable, shell-greppable). Prose outside the block is
the consumer's own commentary and is not parsed.

````markdown
# improvement config

```yaml
churn_window: "90 days ago"
churn_exclude:
  - '(^|/)generated/'
  - '\.designer\.cs$'
churn_exclude_defaults: true
evidence_sources:
  app-telemetry:
    mcp_server: my-observability-mcp
    kind: metrics
    scope: production web tier
    hints: start with request failure rate and p95 latency
```
````

## Keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `churn_window` | string accepted by `git log --since` | `"90 days ago"` | The hotspot recipe's change-frequency window — its main tuning knob. The recipe's history-depth gate still applies: a window the history does not cover shrinks or downgrades to an evidence gap regardless of this value. |
| `churn_exclude` | list of ERE patterns | `[]` | Extra patterns matched against paths from `git log --name-only` and excluded from churn counting. Unioned across layers and with the bundled defaults. |
| `churn_exclude_defaults` | boolean (`true` \| `false` — bare `on`/`off` is the YAML 1.1 coercion footgun and is not accepted) | `true` | `false` drops the bundled default exclusions (lockfiles, generated/minified artifacts, vendored trees — the ERE in the hotspot recipe), leaving only declared patterns. |
| `evidence_sources` | mapping of named source declarations | `{}` | Tier 2 application-telemetry declarations, one entry per source (sub-keys below). Empty or absent means Tier 2 is an evidence gap. |

### `evidence_sources.<name>` sub-keys

| Sub-key | Required | Values | Meaning |
|---|---|---|---|
| `mcp_server` | yes | MCP server name | The server as named in the consumer's own MCP configuration. The plugin declares which server carries telemetry; it never ships, installs, or configures one, and never hardcodes a vendor. |
| `kind` | no | `metrics` \| `logs` \| `errors` \| `traces` \| `events` | What class of evidence the source yields — guides which scan dimensions consume it. |
| `scope` | no | prose | What product surface the source covers (e.g. "production web tier"). |
| `hints` | no | prose | Where to start: key queries, dashboards, or tables worth reading first. |

At find-time every declared source is probed presence-gated: when the named MCP server is not
available in the session, that source becomes a recorded evidence-gap line for the run — never a
hard error, and never a fabricated reading.

## Consumer `.gitignore`

One recursive line covers the overlay here and every other cascade surface:

```gitignore
.claude/**/*.local.*
```

`/improvement:setup` recommends this line; no plugin writes the consumer's `.gitignore`.
