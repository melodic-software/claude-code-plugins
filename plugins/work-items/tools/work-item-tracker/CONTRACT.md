# Work-item tracker seam — contract

Provider-neutral CLI contract for work-item tracker operations. Skills and scripts call the
core dispatcher (`work-item-tracker.sh`) only; the bound provider adapter executes the
operation. The seam ships bundled with the `work-items` plugin and resolves plugin-dir
canonical with a project-root fallback (see "Adapter resolution"). Direction locked by
[ADR 0014](../../../../docs/adr/0014-resolve-seam-engine-plugin-canonical-and-adapters-consumer-first.md).

## Prerequisites

- `jq` on PATH (all providers). Missing → exit `3` with an actionable message.
- `gh` ≥ 2.94 on PATH when the bound provider is `github` (native sub-issue/dependency
  flags: `--parent`, `--blocked-by`, `--add-blocked-by`). Missing or too old → exit `3`
  naming the minimum. The dispatcher gates on both binaries before dispatch.
- `curl` on PATH when the bound provider is `jira` (Cloud REST v3 over HTTPS). The jira
  adapter gates on it at call time (exit `3`), not the dispatcher — minimal shared-code
  blast radius.

### Degradation without `gh` (cloud / MCP-only sessions)

Some execution environments have GitHub access but no `gh` binary — notably cloud sessions
whose GitHub surface is MCP tools (model-plane, not shell-plane). In such a session the
seam **cannot run the `github` adapter at all**, reads and writes alike: the dispatcher's
prerequisite gate exits `3` (the same first-run signal as a missing binding), and there is
deliberately no silent fallback to another provider (the binding names the coordination
surface; "Offline role activates only by manual binding switch" applies to degradation
too). Honest limitation, recorded 2026-08-17 (#2942): this repository's own spec board
(#2933) had to be published through MCP tools with blocking edges as body text, because
the publishing session had no `gh`.

Evaluated fallbacks, decided as follows:

- **REST fallback inside the `github` adapter (`curl`) — explicitly deferred.** It would
  duplicate `gh`'s auth, pagination, and endpoint surface inside the adapter, and would
  silently fork identity routing ("Identity routing (GitHub adapter)" — the bot-wrapper
  seam wraps `gh`, not raw HTTP). The native sub-issue/dependency surface is exactly what
  gates `gh ≥ 2.94`; re-deriving it over raw REST is a second implementation to keep
  conformant. Revisit if gh-less environments become a primary execution surface rather
  than an occasional one.
- **MCP tools as an adapter — rejected.** Adapters are shell verb-scripts; MCP tools are
  callable only by the model, so a shell seam cannot invoke them. A session with MCP-only
  GitHub access already has item CRUD through those tools directly — what it loses is the
  seam's value-add (leases, frontier derivation, normalization, conformance).

**Supported path — the backfill ritual.** A `gh`-less session that must publish anyway
(the #2933 case) publishes through whatever GitHub surface it has, and:

1. records every blocking edge as a structured body line — `Blocked by: <qualified id>`
   ("ID grammar"; bare `#123` is never persisted) — and parent linkage via the provider
   surface where it exists (MCP has native sub-issue support);
2. leaves one provenance comment on the container naming the edges awaiting native
   backfill;
3. the next session with `gh ≥ 2.94` replays the recorded edges through the seam
   (`link-blocks` / `add-sub-item`) and strikes the note.

Leases are NOT part of the ritual: a `gh`-less session must not simulate claims by
body-editing — claim/renew/reclaim stay seam-only, so an item worked this way is picked up
as unclaimed coordination (acceptable for a publish, wrong for contended work).

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
  invalid (exit `3`). Optional `config.lease_ttl_minutes` (0–59 additive minutes;
  default `0`) combines with `lease_ttl_hours` for sub-hour leases (#1034).
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
work-item-tracker.sh list-sub-items <parent-id> [--state open|closed|all]
work-item-tracker.sh list-frontier [--autonomous] [--parent <container-id>] [--repo <o>/<r>]
work-item-tracker.sh capabilities
```

`list-sub-items` enumerates a container's **direct** children as full normalized item objects
(same envelope as `list-items`), each carrying the container as its `parent_id`. It is a RAW
enumeration — closed children and nested-container children are kept (the closed-children
invariant check and sub-map traversal both need them); frontier filtering is the separate
core-side step below. The container is addressed by its qualified id, which carries the repo, so
there is no `--repo` flag. `--state` defaults to `all`.

`list-frontier` is a CORE-side derivation (no provider has a native counterpart): it calls
the adapter's `list-items` and filters `state == open` AND `blocked_by_count == 0` AND no
assignee AND not a container (a `work-map` item is never its own frontier item — see
"Containers and state"). With `--autonomous`, items labeled `needs-human` are additionally
excluded — the filter runs core-side over the labels `list-items` already returns; provider
search syntax never leaves the adapter. With `--parent <container-id>` the frontier is scoped
to one container: core reads the adapter's `list-sub-items` for that container instead of the
repo-global `list-items`, then applies the identical filter (so a nested sub-map among the
children is likewise excluded). `--parent` gates on the adapter's `list-sub-items` capability,
not `list-items`. `--repo` is incompatible with `--parent`: a container is addressed by its
qualified id, which already carries the repo, so `--repo` cannot re-target a container-scoped
frontier. Passing both is a usage error (exit `2`), not a silent drop.

## Adapter contract

Adapters live at `adapters/<provider>/` as verb-per-script (`<verb>.sh`) plus a
`capabilities.json` manifest. Adapter verb set = core public set **minus `list-frontier`
plus `list-items`** (`list-sub-items` is both a core and an adapter verb — it has a native
counterpart, unlike the core-derived `list-frontier`):

```text
adapters/<provider>/list-items.sh [--state open|closed|all] [--repo <o>/<r>]
adapters/<provider>/list-sub-items.sh <parent-id> [--state open|closed|all]
```

- `list-items` returns RAW candidates (state, assignees, labels, open-blocker count) and
  MUST have explicit pagination semantics: fetch up to the `limits.list_items_max`
  declared in its `capabilities.json` (never a client default — `gh` truncates at 30
  silently). Exceeding the ceiling is a documented truncation, not an error.
- `list-sub-items` returns the RAW children of `<parent-id>` in the same `{items:[…]}`
  envelope, each item's `parent_id` set to the container. Where a provider's list surface
  omits parent linkage (GitHub's does — see "JSON output contract"), the adapter resolves
  children through the provider's native sub-item link (GitHub's `subIssues`) and intersects
  with `list-items` output; its truncation bound is therefore `list-items`' own
  (`limits.list_items_max`), safe while `sub_items_per_parent <= list_items_max`. A child in
  another repo is out of scope for this repo-keyed intersect (documented truncation, not an
  error). A parent with no children returns an empty `items` array, never an error.
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

Envelopes: `list-items`, `list-sub-items`, and `list-frontier` emit
`{"schema_version":"1.0","items":[…]}`.

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
| `list-sub-items` | `{items:[…]}` envelope of normalized item objects (each `parent_id` = the container) |
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

This table covers only codes the **script itself** returns. A harness-level denial of the Bash
tool call that would have invoked the script (e.g. an auto-mode risk classifier refusing the
invocation before the process starts) produces no exit code at all — the script never runs.
Callers that branch on exit code (Step 0's reclaim loop is the current example — see
`skills/work/SKILL.md` "Step 0") MUST treat that case separately from any code in this table, not
coerce it into one. See work-loop finding #1381.

## Lease protocol

Claim = **assignee (authenticated human user) + lease record**. The lease is a dedicated
issue comment with a machine marker:

```text
<!-- work-item-lease v1 {"schema_version":"1.0","holder":"<gh login>","acquired_at":"<ISO>","renewed_at":"<ISO>","ttl_hours":24,"session_id":"<opt>"} -->
```

- Created at claim; **edited in place** at renew (`renewed_at` bump); superseded at
  reclaim/back-off by adding `"superseded_at":"<ISO>"` to the JSON.
- A lease is **live** when it has no `superseded_at` and `renewed_at + ttl_hours×3600 +
  (ttl_minutes×60)` is in the future. `ttl_hours` defaults from binding
  `config.lease_ttl_hours`; `ttl_minutes` defaults to `0` and may be set per claim via
  `--ttl-minutes` or binding `config.lease_ttl_minutes`.
- `renew-lease` renews **only a live lease**. A lease that is still the active
  (non-superseded) lease but already **expired** — `renewed_at + ttl_hours` elapsed with
  no back-off yet — is refused (exit `7`), never revived: a delayed holder must not undo a
  TTL-based handoff. Recovery from an expired lease is a fresh claim/reclaim, not a renew.
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
No activity → unassign **only the expired lease's `holder`** (a co-assignee added by a
human or a concurrent claimer is left in place — removing it would strip a live claim and
leave the frontier treating the item as unassigned), supersede the lease, append an
explanatory comment, `reclaimed: true`. Ownership is **revalidated immediately before the
mutation** — the activity round-trips open a window in which a concurrent claimer can renew
or supersede the lease; if the active lease is no longer this one, or is now live, reclaim
intends a no-op (`reclaimed: false`). That revalidation is **intent, not a guarantee**: it
narrows the TOCTOU window but cannot close it — GitHub's issue-comment PATCH documents no
If-Match / CAS, so a concurrent writer can still win the race and a reclaim can still mutate
after a stale revalidation. Do not treat the check as CAS. A live lease is never the
*intended* reclaim target.
Branch-push activity signals are not implemented (deferred; comments + PR cross-references
carry the check). Long-running workers therefore **renew mid-flight** (`renew-lease` on the
claim's `lease_comment_id`) rather than relying on push activity (`/work-items:work` Step 5).

- **Clock skew.** Liveness compares provider timestamps (`renewed_at` in the marker) to the
  local clock (`date -u`). Assume the two are close enough for the configured TTL;
  sub-hour `ttl_minutes` make skew more visible.
- **ttl-0.** A claim with `ttl_hours: 0` and `ttl_minutes: 0` is born expired. Conformance
  relies on that; do not treat it as a live lease.
- **Comment-id monotonicity.** Same-login race arbitration treats an earlier numeric lease
  handle as the winner. GitHub lists issue comments by ascending ID by default; adapters
  MUST emit ordered unique numeric `lease_comment_id` handles.

## Containers and state

Two axes, one item model: a **container** is an ordinary item carrying the `work-map`
label (a navigable graph root — wayfind maps, decompose breakdowns); **state** is the
provider's native open/closed. Containers are never claimable by workers (no
`agent-ready`), so **a container is never its own frontier item**: `list-frontier` excludes
any item carrying the container label, unconditionally (global and `--parent`-scoped alike).
The container label is a named constant (`WIT_CONTAINER_LABEL`, default `work-map`) matching
this contract term; making it a per-repo remap (a consumer wanting a different marker) is
deferred to the `config.role_labels` convention (label-taxonomy.md "Canonical roles"), keyed
off that same first request — not a parallel binding key. Read one container's children with
`list-sub-items <container>`; read the workable frontier within one container with
`list-frontier --parent <container>`. Aside from that exclusion the frontier is
label-agnostic and simply never surfaces items that are assigned or blocked.

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

### Contract-version handshake

Adapters resolve consumer-local first ("Adapter resolution"), so a consumer-owned,
shadowing, or generated adapter can legitimately be built against a different contract
revision than the engine dispatching to it. The dispatcher therefore performs a
**directional tolerant-reader handshake** before every dispatch: it compares the manifest's
declared `schema_version` to the core's contract version (`WIT_SCHEMA_VERSION`,
`lib/json.sh`). Skew behavior, both directions:

| Manifest vs core | Behavior |
|---|---|
| no valid `schema_version` (MAJOR.MINOR) | refuse: exit `3`, stderr says the manifest cannot handshake — consumer/generated adapters MUST declare one |
| newer MAJOR | refuse: exit `3`, stderr names both versions — "update the `work-items` plugin" |
| older MAJOR | refuse: exit `3`, stderr names both versions — "update or regenerate the adapter" |
| same MAJOR, newer MINOR | proceed with a stderr notice: minors are additive, so the core (a tolerant reader) ignores fields it does not know; updating the plugin consumes them |
| same MAJOR, MINOR ≤ core | proceed silently: additive fields introduced after the adapter's revision are optional by definition, so an older adapter simply omits them |

Major skew is a **configuration error, not a degradation**: exit `3` is the same
first-run/setup signal as a missing binding, pointing at the mismatched pair rather than
failing later inside a verb with a shape error. The conformance suite asserts both refusal
directions and the newer-minor notice against a synthetic skewed manifest, and every real
conformance case exercises the passing handshake.

## Identity routing (GitHub adapter)

Tracker WRITES (item create, lease comments, reclaim notes) route through an optional bot wrapper
(`gh-bot.sh`) when a wrapper is found, and fall back to bare `gh` when neither location has one.
Resolution is consumer-local-first, plugin-bundled fallback — mirroring "Adapter resolution": the
adapter checks `${CLAUDE_PROJECT_DIR}/tools/github-auth/gh-bot.sh` first, independent of where the
adapter itself resolved from (so a shadowed consumer-local adapter still finds the consumer's wrapper),
then falls back to `…/github-auth/gh-bot.sh` bundled beside the seam tree. A plugin install ships no
wrapper at either path, so writes use bare `gh` by default (plugin-lift portability); a repo that wants
bot-attributed writes provides the wrapper at its own project root, with zero vendoring. CLAIMS always
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
  degradation; every other verb is fully supported. Because no reclaim clears an
  abandoned claim, `list-items` compensates offline: an item whose lease has expired
  is reported with an empty `assignees` (its effective post-expiry assignment), so
  the core frontier returns it to selection. `get-item` still reports the stored
  assignee, keeping the raw claim record inspectable.
- **Offline role activates only by manual binding switch** — the local-markdown
  provider is used when a repo's binding names it, never as an automatic fallback
  from a network failure of another provider.

### Branch, worktree, and lease confinement

The store is working-tree files (`<storage_dir>/<number>.md`). Visibility is
therefore confined to the tree that holds those files. Untracked or uncommitted
item files are **not** branch-isolated in the same worktree: `git switch`
normally carries them onto the new branch (and a nonconflicting uncommitted
lease edit can likewise follow). Invisibility holds for sibling worktrees that
do not share those store files, and for committed store files on other branches
until those commits are merged. `wit_next_number` is the max existing file
number + 1 with no file lock, so two diverged branches (or two writers against
one store) can both mint the same next number.

A relative `config.storage_dir` roots against the **binding file's directory**,
not the caller's CWD (`lib/binding.sh`). Distinct worktrees that climb to the
same binding therefore share one store when `storage_dir` is relative. Distinct
worktrees that each carry their own copy of the binding and store — the
`/work-items:work` skill's worker-worktree model — each have a divergent copy:
an uncommitted lease is invisible to a sibling worktree; a committed lease is a
lease-churn commit on that worktree's branch. A shared **absolute**
`storage_dir` across worktrees is one store, so concurrent create/claim races
on numbers and the lease marker.

Claim identity is `git config user.name`, then `$USER`, then `local`. The same
git user in two worktrees looks like the same holder. The lease handle is a
store-global `lease_comment_id` in the marker JSON (not a GitHub comment id).
The manifest declares `reclaim: false`; invoking `reclaim` exits `6`. On
expiry, `list-items` reports empty `assignees` (effective post-expiry
assignment) while `get-item` still shows the stored assignee.

This confinement is why multi-session / multi-machine work needs a
tracker-published spec on a coordination provider — a `work-map` container lane
(see "Containers and state"). local-markdown is never that surface.

## jira adapter

The `jira` adapter binds a Jira Cloud project set behind the seam. It is **read/resolve-only
by default** (issue #379 hard constraint): `get-item`, `list-items`, and `capabilities` are
supported; `create-item`, `claim`, `renew-lease`, `reclaim`, `link-blocks`, `add-sub-item`,
and `list-sub-items` are declared `false` in the manifest and exit `6` at the core capability
gate — **no code path creates, claims, or mutates a Jira ticket by default.** Consequently
`/work-items:work`, `track start`, and `list-frontier --parent` (which needs `list-sub-items`)
cannot operate on a Jira binding until writes are explicitly enabled — an accepted gap; branch/
PR `SW2-*` linkage and the opt-in-write mechanism are sequenced follow-ups.

- **API.** Jira Cloud REST v3 over HTTPS via `curl`. Reads use `GET /rest/api/3/issue/{key}`
  and enhanced JQL search `POST /rest/api/3/search/jql` (token pagination via `nextPageToken`
  up to `limits.list_items_max`). ID grammar: `jira:<site>/<PROJECTKEY>#<number>` maps to the
  native key `PROJECTKEY-number` (e.g. `jira:acme.atlassian.net/SW2#12345` ⇄ `SW2-12345`);
  `owner` is the Cloud host, `repo` the project key, `number` the issue number.
- **Auth.** Basic auth — Atlassian account email + API token (passwords are deprecated). The
  token is read from the env var **named** by `config.jira.auth_env` (never stored in the
  tracked binding) and passed to curl via a stdin config (`-K -`) so it never appears in argv.
  Missing/empty token env var → exit `4`. `auth_env` must be a valid shell identifier
  (`[A-Za-z_][A-Za-z0-9_]*`), validated at config load (exit `3`) since it is dereferenced.
  Tokens expire (1-year default since Dec 2024) — the adapter treats rotation as a normal
  lifecycle event (a clear exit-`4` surface, re-bind in setup).
- **Credential-egress guard.** `site` is the host the Basic-auth token is sent to, and the
  binding is tracked (PR-modifiable). It is validated at config load (exit `3`) to be a **bare
  hostname** — no scheme, path, `@` userinfo, port, or control characters, so a binding cannot
  smuggle URL structure that redirects the credential — and to be an Atlassian Cloud host
  (`*.atlassian.net`) **unless** the binding sets `config.jira.allow_custom_domain: true` to
  explicitly accept a custom-domain tenant (deny-by-default on credential egress).
- **Binding config.** Jira has no `gh repo view` equivalent to derive scope at runtime, so
  `config.jira` is required (a binding missing `site`, non-empty `project_keys[]`, `auth_email`,
  or `auth_env` → exit `3`):

  ```json
  {
    "schema_version": "1.0",
    "provider": "jira",
    "config": {
      "lease_ttl_hours": 24,
      "jira": {
        "site": "company.atlassian.net",
        "project_keys": ["SW2", "ABC"],
        "auth_email": "ci@company.com",
        "auth_env": "JIRA_API_TOKEN",
        "blocked_by_link_type": "Blocks",
        "done_category_keys": ["done", "completed"]
      }
    }
  }
  ```

  `list-items`/`list-frontier` build JQL scope from `project_keys`; `--repo <site>/<PROJECTKEY>`
  narrows to one project (site must match the bound site, and the project must be one of the
  declared `project_keys`). `project_keys` is both the read scope and the authorization
  boundary: **every read is confined to the declared projects.** `get-item` refuses an id whose
  project is not in `project_keys`, and `--repo` may only narrow within them — never widen to an
  undeclared project the token can otherwise see (exit `2` on an out-of-scope project).
  `blocked_by_link_type` (default
  `"Blocks"`; when overridden it must be a non-empty string — an empty/non-string value matches
  no issuelink and would silently zero `blocked_by_count`, exit `3`) and `done_category_keys`
  (default `["done","completed"]`; a present value must be a non-empty array, exit `3`) are the
  override seams
  for two facts deferred to a live-instance pass: the authoritative blocker link type and the
  exact `statusCategory` key for the "Done" category (the official spec's own example disagrees
  with real instances — both known keys are defaulted so the adapter is independent of that
  deferred fact).
- **Read-path normalization** (CONTRACT.md "JSON output contract"): `state` — `statusCategory`
  key in `done_category_keys` → `closed`, else `open`; `assignees` — the single `assignee`'s
  `accountId` as a one-element array (empty when unassigned); `labels` — Jira `labels[]`
  verbatim (canonical role labels ride as ordinary labels; `list-frontier --autonomous` filters
  them core-side); `type` — issue-type name; `blocked_by_count` — **open** inward
  `blocked_by_link_type` links only (parity with the GitHub adapter's open-only count; the
  linked issue's status is inlined in `issuelinks`, so no second round-trip); `parent_id` — from
  `fields.parent` (subtask→parent universally, story→epic where the instance uses the unified
  parent field rather than the legacy Epic-Link custom field — a documented best-effort
  limitation deferred with the sub-item link-type question); `url` — `https://<site>/browse/<KEY>`.
- **Never a bot surface.** Reads carry the token owner's identity; project Browse permission
  governs visibility. There is no lease/claim machinery (writes are off), so `features.leases`
  and `features.sub_items` are `false`.

## Conformance

`conformance/run-conformance.sh --binding <name>` runs the SAME abstract suite over any
adapter through the core CLI only: every verb, valid + invalid input, exit-code +
`schema_version` + JSON-shape assertions, claim-race back-off, CR-free stdout,
capability-gated skips (declared-unsupported verbs asserted to exit `6`). Bindings live
at `conformance/bindings/<name>.sh` and provide setup (clean-at-start), target context,
and teardown. The GitHub binding targets a throwaway sandbox repo and is on-demand; it is
never pointed at a coordination repo. The `local-markdown` and `jira` bindings run offline
in CI: local-markdown against a temp store, and jira because its consume-only manifest means
every suite-exercised path is pre-network (capabilities cats the manifest, write verbs +
`list-sub-items` exit `6` at the gate, and no read verb is seeded since `create-item` is
`false`) — both are additionally re-run under a `gh`/`curl`-blocking PATH shim to prove they
touch no network tool. The jira read verbs are covered offline by the adapter's own
`*.test.sh` with a mocked curl; a live-Jira conformance pass is deferred to the work-laptop
pass that settles the exact `statusCategory` "done" key and blocker link type.
