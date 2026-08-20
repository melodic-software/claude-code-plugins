# Adapter spec

The single artifact between the interview and the generator. The interview fills it;
`scripts/generate-adapter.sh --spec <file>` consumes it and refuses it when it is
incoherent.

Everything here is validated before a byte is written. A refusal names the field and the
reason — read it as information about the spec, not an obstacle.

## Worked example

A self-hosted, forge-shaped provider with no lease support:

```json
{
  "spec_version": "1.0",
  "provider": "gitea",
  "display_name": "Gitea / Forgejo",
  "api": {
    "base_path": "/api/v1",
    "host_suffix": "",
    "auth_scheme": "token",
    "scope_pattern": "^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$",
    "sample_scope": "acme/webapp",
    "sample_host": "git.example.com",
    "auth_env_example": "WIT_GITEA_TOKEN"
  },
  "verbs": {
    "create-item": true, "get-item": true, "claim": false, "renew-lease": false,
    "reclaim": false, "link-blocks": true, "add-sub-item": false,
    "list-items": true, "list-sub-items": false, "capabilities": true
  },
  "features": {
    "cross_repo_edges": false, "sub_items": false, "leases": false, "labels": true
  },
  "limits": {
    "sub_items_per_parent": 0, "sub_item_depth": 0,
    "dependencies_per_type": 50, "list_items_max": 1000
  },
  "deferrals": [
    "The exact dependency link representation is read from one live blocked issue; until then blocked_by_count is derived from the documented shape."
  ]
}
```

## Fields

### Identity

| Field | Required | Rule |
|---|---|---|
| `spec_version` | yes | Exactly `"1.0"`. |
| `provider` | yes | `^[a-z][a-z0-9-]{0,31}$`. Becomes a directory name, a path segment, a shell function-name fragment, a jq key, and the prefix of every item ID this adapter emits. Constrained once here so nothing downstream has to escape it. **Permanent** — changing it later invalidates every persisted ID. |
| `display_name` | yes | Free text for comments and docs. |

### `api`

| Field | Required | Rule |
|---|---|---|
| `base_path` | no (default `""`) | Slash-led segments of `[A-Za-z0-9._~-]`, e.g. `/api/v1`. Prefixed to every request path. |
| `host_suffix` | no (default `""`) | Dot-led domain suffix the host is pinned to, e.g. `.atlassian.net`. **Empty means self-hosted** — no vendor domain exists to pin against, so there is no code-level pin; the consumer can still pin their own instance with `config.<provider>.host_suffix` in the binding. |
| `auth_scheme` | yes | `bearer` (`Authorization: Bearer <t>`), `token` (`Authorization: token <t>`), or `basic` (base64 of `<auth_user>:<t>`; adds a required `auth_user` binding key). |
| `scope_pattern` | no | Anchored regex the scope entries must match. Default `^[A-Za-z0-9][A-Za-z0-9._/-]*$`. **Must be anchored at both ends** — an unanchored pattern accepts a conforming *prefix* of a hostile value, which is the exact hole the guard exists to close. |
| `sample_scope` | yes | A representative scope. Seeds the generated fixtures, so it must satisfy `scope_pattern`. |
| `sample_host` | no | A representative host. Defaults to `example<host_suffix>`, or `tracker.example.com` when self-hosted. Must be a bare hostname and, where a suffix is pinned, must sit under it — otherwise the generated fixtures would fail the generated guards. |
| `sample_id` | no | A representative fully-qualified ID. Defaults from `sample_scope` when it already carries an `owner/repo` pair, else from host plus scope. Must satisfy the seam's grammar `<provider>:<owner>/<repo>#<n>` — **exactly two path segments** — and name this provider. Set it explicitly when neither default shape fits. |
| `auth_env_example` | no | Default `WIT_<PROVIDER>_TOKEN`. A valid environment-variable name; it is the *name* only, never a credential. |

### `verbs`

Every key of the adapter surface must be present and boolean — a missing key is refused
rather than defaulted, because an unlisted verb means the spec was written against a
different contract revision, and guessing produces a manifest that lies.

`create-item`, `get-item`, `claim`, `renew-lease`, `reclaim`, `link-blocks`,
`add-sub-item`, `list-items`, `list-sub-items`, `capabilities`.

`capabilities` must be `true`: the core reads the manifest to decide whether any other
verb is attempted at all.

A verb declared `true` gets a scaffold with a `PROVIDER MAPPING` block. A verb declared
`false` gets **no file** — the core's capability gate answers it with exit `6` before any
script would run, and shipping an inert file invites someone to fill it in without
flipping the manifest.

### `features` and `limits`

`features`: `cross_repo_edges`, `sub_items`, `leases`, `labels` — all booleans, all
required.

`limits`: `sub_items_per_parent`, `sub_item_depth`, `dependencies_per_type`,
`list_items_max` — all required. Each is a non-negative integer **or `null`**, and the
three values are distinct (`CONTRACT.md` "Capabilities manifest"):

- `n > 0` — the provider enforces this ceiling; hitting it is exit `7` with the ceiling
  named.
- `0` — the underlying capability is unsupported, matching the `verbs`/`features` entry
  that says so.
- `null` — supported, and the provider enforces **no** ceiling.

Reach for `null` rather than inventing a plausible number: `0` cannot say "unbounded"
without also reading as "none allowed", and a caller branching on the number would then
see a ceiling that does not exist. Gitea's issue dependencies are the worked case — it
rejects only duplicate and circular edges and caps nothing.

`list_items_max` is the total `list-items` must page up to; a client default here is how
a frontier ends up lying about what is available.

### `deferrals`

Array of strings. Each is a fact that could not be settled against a live instance. They
become a "Recorded deferrals" section in the generated README, and each should have a
matching config key with a documented default so the adapter is *independent* of the fact
rather than wrong about it.

## Coherence rules

The manifest is a promise the core routes on, so these are refusals, not warnings:

- The three lease verbs (`claim`, `renew-lease`, `reclaim`) and `features.leases` stand or
  fall together. A claim that cannot be renewed or reclaimed strands the item at TTL
  expiry.
- `add-sub-item` / `list-sub-items` require `features.sub_items`.
- `features.sub_items` and `limits.sub_items_per_parent` must agree: no ceiling on an
  unsupported capability, and no zero ceiling on a supported one.
- `verbs["list-items"]` and `limits.list_items_max` must agree.
- `link-blocks: true` needs a non-zero `dependencies_per_type`.

One note, not a refusal: `list-items: false` is coherent — the bundled `jira` adapter is
consume-only — but `list-frontier` can then never succeed, so no work-selection flow will
find anything. The generator says so on stderr.

## What the spec does *not* control

`schema_version` in the generated manifest. It is stamped from the **seam's** contract
version, read from `lib/json.sh`, never from the spec. An adapter that versioned itself
could be born already skewed from the engine that will dispatch it — see `CONTRACT.md`
"Contract-version handshake".
