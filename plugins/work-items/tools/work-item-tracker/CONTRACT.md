# Work-item tracker seam — contract

Provider-neutral CLI contract for work-item tracker operations. Skills and scripts call the
core dispatcher (`work-item-tracker.sh`) only; the bound provider adapter executes the
operation. The seam ships bundled with the `work-items` plugin and resolves plugin-dir
canonical with a project-root fallback (see "Adapter resolution"). Direction locked by ADR 0022.

## Prerequisites

- `jq` on PATH (all providers). Missing → exit `3` with an actionable message.
- `gh` ≥ 2.94 on PATH when the bound provider is `github` (native sub-issue/dependency
  flags: `--parent`, `--blocked-by`, `--add-blocked-by`). Missing or too old → exit `3`
  naming the minimum. The dispatcher gates on both binaries before dispatch.

## Setup (binding file)

The repo binds exactly ONE active provider via `.work-item-tracker.json` at the repo root
(tracked — which tracker a repo uses is repo-scoped):

```json
{
  "schema_version": "1.0",
  "provider": "github",
  "config": {
    "lease_ttl_hours": 24
  }
}
```

- Discovery: climb from CWD toward the filesystem root; first match wins. Env override
  `WORK_ITEM_TRACKER_BINDING=<path>` (tests, conformance).
- Owner/repo are NEVER recorded in the binding — derived at runtime from the working
  directory's git remote (`gh repo view --json owner,name`). Verbs that need a repo
  context accept an explicit `--repo <owner>/<repo>` override (conformance, cross-repo
  tooling).
- No binding found → exit `3` and stderr points here; the seam runs no inline wizard. The
  `work-items` plugin's setup skill (`/work-items:setup`) seeds this file — provider + non-secret
  config — as the once-per-repo binding step.
- All defaults are externalized to `config` — nothing numeric is baked into scripts.
  `config.lease_ttl_hours` (lease TTL, hours) is REQUIRED; a binding without it is
  invalid (exit `3`).
- `config.storage_dir` is REQUIRED when `provider` is `local-markdown` (no baked default).

## Verbs (core public surface)

```text
work-item-tracker.sh create-item --title <t> [--body <b>] [--labels a,b] [--type <name>] [--parent <id>] [--blocked-by <id>[,<id>]] [--repo <o>/<r>]
work-item-tracker.sh get-item <id>
work-item-tracker.sh claim <id> [--ttl-hours <n>] [--session-id <s>]
work-item-tracker.sh renew-lease <id> --lease-comment-id <n>
work-item-tracker.sh reclaim <id>
work-item-tracker.sh link-blocks <id> --blocked-by <id>
work-item-tracker.sh add-sub-item <id> --parent <id>
work-item-tracker.sh list-frontier [--autonomous] [--repo <o>/<r>]
work-item-tracker.sh capabilities
```

`list-frontier` is a CORE-side derivation (no provider has a native counterpart): it calls
the adapter's `list-items` and filters `state == open` AND `blocked_by_count == 0` AND no
assignee. With `--autonomous`, items labeled `needs-human` are additionally excluded —
the filter runs core-side over the labels `list-items` already returns; provider search
syntax never leaves the adapter.

## Adapter contract

Adapters live at `adapters/<provider>/` as verb-per-script (`<verb>.sh`) plus a
`capabilities.json` manifest. Adapter verb set = core public set **minus `list-frontier`
plus `list-items`**:

```text
adapters/<provider>/list-items.sh [--state open|closed|all] [--repo <o>/<r>]
```

- `list-items` returns RAW candidates (state, assignees, labels, open-blocker count) and
  MUST have explicit pagination semantics: fetch up to the `limits.list_items_max`
  declared in its `capabilities.json` (never a client default — `gh` truncates at 30
  silently). Exceeding the ceiling is a documented truncation, not an error.
- An adapter MAY keep shared helpers (e.g. `common.sh`); only `<verb>.sh` files named in
  the manifest are contract surface.
- A verb declared `false` in the manifest exits `6` with a clear stderr message when
  invoked — degradation is explicit, never silent.

## Adapter resolution

The seam ships bundled with the `work-items` plugin and also runs from a consumer-vendored copy.
Two independent resolutions, deliberately opposite:

- **Seam code** (dispatcher, `lib/`, this contract): **plugin-dir canonical, project-root fallback.**
  A caller resolves `work-item-tracker.sh` from `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/` when
  that exists, else `${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/` — so a consuming repo runs the
  plugin's engine by default and a vendored copy still works.
- **Adapters** (`adapters/<provider>/`): **consumer-local-first, plugin-bundled fallback; first match
  wins.** For the bound `<provider>`, the dispatcher searches
  `${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/adapters/<provider>/` first, then its own bundled
  `adapters/<provider>/`. A consuming repo can thus add a provider the plugin does not ship, or shadow
  a bundled adapter with a local copy it owns fully — without forking the plugin. `WIT_ADAPTERS_DIR`
  overrides the search with a single explicit adapter root (tests, conformance).

The binding (`.work-item-tracker.json`) and any consumer-local adapters live in the consuming repo
(`${CLAUDE_PROJECT_DIR}`); the bundled engine and adapters live in the plugin (`${CLAUDE_PLUGIN_ROOT}`),
which is read-only and replaced on plugin update — no seam state is written there.

## JSON output contract

- Every emitted JSON object (including every JSON Lines line, if streamed) carries
  `"schema_version": "<MAJOR.MINOR>"` — current `"1.0"`. Minor bumps are
  additive/ignorable; major bumps are breaking.
- stdout carries JSON only; diagnostics go to stderr. stdout MUST NOT contain a carriage
  return (core strips CR from captured adapter output; conformance asserts).

Normalized item object:

```json
{
  "schema_version": "1.0",
  "id": "github:owner/repo#123",
  "title": "…",
  "state": "open",
  "assignees": ["login"],
  "labels": ["name"],
  "type": "Task",
  "blocked_by_count": 0,
  "parent_id": null,
  "url": "https://…"
}
```

- `state` is normalized lowercase: `open` | `closed`.
- `type` is the native issue-type NAME (the type axis — org-defined `Task`/`Bug`/
  `Feature`), or `null` when the item has none. On GitHub it is the native Issue Type
  (`create-item --type` sets it; requires push access — silently dropped otherwise);
  the `local-markdown` adapter has no native-type registry, so `--type` is stored and
  echoed verbatim (an offline-parity scalar). Additive field: items predating it read
  as `null`.
- `blocked_by_count` counts **open** blockers only. (Tier-0 verified 2026-07-12:
  GitHub's `blockedBy.totalCount` keeps counting CLOSED blockers, which would break
  frontier graduation — the adapter counts `state == "OPEN"` nodes.)
- `parent_id` is a fully-qualified ID or `null`. Bulk `list-items` rows MAY carry
  `parent_id: null` when the provider's list surface omits parent data (GitHub's does);
  `get-item` is authoritative for parent linkage.

Envelopes: `list-items` and `list-frontier` emit `{"schema_version":"1.0","items":[…]}`.

Per-verb result objects:

| Verb | Result fields (beyond `schema_version`) |
|---|---|
| `create-item` | normalized item object |
| `get-item` | normalized item object |
| `claim` | `id, holder, acquired_at, renewed_at, ttl_hours, lease_comment_id, session_id` |
| `renew-lease` | same as `claim` (with bumped `renewed_at`) |
| `reclaim` | `id, reclaimed` (bool), `reason` |
| `link-blocks` | `id, blocked_by, linked: true` |
| `add-sub-item` | `id, parent_id, linked: true` |
| `capabilities` | manifest object (see below) |

## ID grammar

`<provider>:<owner>/<repo>#<number>` — e.g. `github:acme/webapp#1335`.
Fully qualified, opaque to core, parsed only by the adapter. Bare `#123` is NEVER
persisted in any durable artifact.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | ok |
| `1` | internal / unexpected |
| `2` | usage (bad args, unknown verb, malformed ID) |
| `3` | binding/config missing or invalid; missing prerequisite binary (first-run signal) |
| `4` | auth |
| `5` | not found |
| `6` | capability-unsupported (declared `false` in manifest) |
| `7` | conflict / precondition (claim race, provider ceiling hit) |
| `8` | provider unavailable (network, rate limit) |

## Lease protocol

Claim = **assignee (authenticated human user) + lease record**. The lease is a dedicated
issue comment with a machine marker:

```text
<!-- work-item-lease v1 {"schema_version":"1.0","holder":"<gh login>","acquired_at":"<ISO>","renewed_at":"<ISO>","ttl_hours":24,"session_id":"<opt>"} -->
```

- Created at claim; **edited in place** at renew (`renewed_at` bump); superseded at
  reclaim/back-off by adding `"superseded_at":"<ISO>"` to the JSON.
- A lease is **live** when it has no `superseded_at` and `renewed_at + ttl_hours` is in
  the future. `ttl_hours` defaults from binding `config.lease_ttl_hours`.
- `session_id` is diagnostic metadata only — optional and collision-prone; a
  missing/duplicate `session_id` still counts as a competing lease.
- The **lease handle** (`lease_comment_id`, emitted by `claim`/`renew-lease`) is
  provider-specific: the GitHub adapter uses the lease comment's own id (external,
  not stored in the JSON); the local-markdown adapter has no external ids, so it
  embeds a store-global `lease_comment_id` field in the marker JSON. `renew-lease`
  addresses a lease by this handle either way.

Claim sequence (race-safe, same-identity aware):

1. Assign the authenticated user (`--add-assignee "@me"` — always the session identity,
   never the bot).
2. Re-read assignees. Any OTHER login present → back off: unassign self, exit `7`.
3. Post the lease comment; capture its comment ID (comment identity, not `session_id`,
   discriminates same-login sessions).
4. Re-read all lease comments. If an EARLIER live lease exists that is not our own
   comment, the foreign lease wins → supersede own comment, exit `7`. (Assignee is left
   in place on a same-login race — it belongs to the winner.)
5. Emit the claim object.

Reclaim (idempotent, run at session start — no scheduled sweep): when the latest lease is
expired, check activity (non-lease comments since `renewed_at`; open cross-referenced
PRs via the issue timeline). Activity → renew the lease in place, `reclaimed: false`.
No activity → clear assignees, supersede the lease, append an explanatory comment,
`reclaimed: true`. A live lease is never reclaimed. Branch-push activity signals are not
implemented (deferred; comments + PR cross-references carry the check).

## Containers and state

Two axes, one item model: a **container** is an ordinary item carrying the `work-map`
label (a navigable graph root — wayfind maps, decompose breakdowns); **state** is the
provider's native open/closed. Containers are never claimable by workers (no
`agent-ready`); frontier machinery is label-agnostic and simply never surfaces items that
are assigned or blocked.

## Capabilities manifest

```json
{
  "schema_version": "1.0",
  "provider": "github",
  "verbs": { "create-item": true },
  "features": { "cross_repo_edges": true, "sub_items": true, "leases": true },
  "limits": { "sub_items_per_parent": 100, "sub_item_depth": 8, "dependencies_per_type": 50, "list_items_max": 1000 }
}
```

Provider ceilings surface as exit `7` with the ceiling named on stderr when hit at
runtime (e.g. GitHub: 100 sub-issues/parent, 8 nesting levels, 50 dependencies/type).

## Identity routing (GitHub adapter)

Tracker WRITES (item create, lease comments, reclaim notes) route through an optional bot wrapper
(`gh-bot.sh`) when the consuming repo provides one, and fall back to bare `gh` when it is absent. The
shipped adapter resolves the wrapper relative to its own location (`…/github-auth/gh-bot.sh` beside the
seam tree): a plugin install bundles no wrapper, so writes use bare `gh` (plugin-lift portability); a
repo that wants bot-attributed writes provides the wrapper at that path in its own tree. CLAIMS always
assign the authenticated human user via bare `gh` (`@me` must resolve to the session identity, not the
bot). Reads are bare `gh`.

## local-markdown adapter

The `local-markdown` adapter is the conformance reference implementation and a
degraded-offline surface — it is **NEVER a coordination surface**. It touches no
network tool (`gh`, `curl`); the conformance suite runs it in CI, offline.

- **Storage.** One markdown file per item at `<storage_dir>/<number>.md`
  (`config.storage_dir`, required — no baked default). Item numbers are a
  single-writer monotonic counter (max existing file number + 1). Frontmatter carries
  `id`/`title`/`state`/`assignees`/`labels`/`parent` as one-line JSON values
  (YAML-flow-compatible, robust to special characters). Dependency edges are
  structured `Blocked by: <id>` body lines; `blocked_by_count` counts only blockers
  whose file exists and is `open`. The lease is the same inline marker used
  everywhere (see "Lease protocol"), appended to the item file.
- **Identity.** No authenticated provider user exists offline, so `claim` records the
  holder from `git config user.name` (falling back to `$USER`, then `local`) and
  writes it to `assignees`.
- **Single namespace.** `cross_repo_edges` is `false`: one store is one logical
  namespace (default owner/repo `local/markdown`, overridable via `--repo` at
  create). Items address by number, so a blocker in another namespace is a text
  pointer only — never a resolvable edge.
- **Degradation (declared, never silent).** The manifest declares `reclaim: false`:
  reclaim's contract requires an activity check over coordination-surface signals
  (non-lease comments since `renewed_at`, open cross-referenced PRs) that a flat file
  store does not have. Invoking `reclaim` on this provider exits `6` with a stderr
  message (the core gates on the manifest before dispatch). This is the sole
  degradation; every other verb is fully supported.
- **Offline role activates only by manual binding switch** — the local-markdown
  provider is used when a repo's binding names it, never as an automatic fallback
  from a network failure of another provider.

## Conformance

`conformance/run-conformance.sh --binding <name>` runs the SAME abstract suite over any
adapter through the core CLI only: every verb, valid + invalid input, exit-code +
`schema_version` + JSON-shape assertions, claim-race back-off, CR-free stdout,
capability-gated skips (declared-unsupported verbs asserted to exit `6`). Bindings live
at `conformance/bindings/<name>.sh` and provide setup (clean-at-start), target context,
and teardown. The GitHub binding targets a throwaway sandbox repo and is on-demand; it is
never pointed at a coordination repo.
