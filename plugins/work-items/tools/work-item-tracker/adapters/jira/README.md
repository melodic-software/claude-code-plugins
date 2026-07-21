# Jira adapter — operations reference

Read/resolve-only surface for the `/work-items` skill against a Jira Cloud provider. The seam
contract (verbs, JSON shapes, exit codes, binding config, auth, normalization) is
[`../../CONTRACT.md`](../../CONTRACT.md) "jira adapter" — this file covers only the
jira-specific operational mechanics a skill needs and does not restate the contract.

**Consume-only.** By default this adapter reads; it never writes. Every coordination write verb
(create/claim/lease/link/sub-item) and `list-sub-items` are declared `false` in
`capabilities.json` and exit `6` at the core gate. A skill step that would create, claim, or
mutate a Jira ticket is unavailable on a Jira binding — by design (issue #379 hard constraint).
Enabling writes is a sequenced follow-up, not a local edit.

## Resolve item ID

Seam verbs (`get-item`) take a fully-qualified ID; a bare Jira key is not one. The mapping is
purely structural (no network call):

```text
SW2-12345   ⇄   jira:<site>/SW2#12345
```

Given a native key `PROJECTKEY-NUMBER` and the bound `config.jira.site`, the qualified ID is
`jira:<site>/<PROJECTKEY>#<NUMBER>`; `get-item` reconstructs the native key from the ID's
`repo` (project key) and `number` segments. A commit/branch reference like `SW2-12345` therefore
resolves to a seam item with no plugin-source edit — the read/resolve path issue #379 scopes to.
(Automatic branch/PR `SW2-*` linkage — rewriting the numeric branch regex and the `Closes #N`
injection — spans two plugins' source and is the sequenced follow-up, out of scope here.)

## List / frontier

`work-item-tracker.sh list-items` (and the core-derived `list-frontier`) scope a JQL query to the
binding's `config.jira.project_keys`; `--repo <site>/<PROJECTKEY>` narrows to one project (its
site must match the bound site, and the project must be one of the declared `project_keys` —
`--repo` narrows within the scope, it cannot widen to an undeclared project, exit `2` otherwise).
`project_keys` is the read/authorization boundary: `get-item` likewise refuses an id whose
project is outside it. `list-frontier` filters core-side to open, unassigned,
unblocked, non-container items (`--autonomous` additionally drops `needs-human`); Jira search
syntax never leaves the adapter. Pagination is by `nextPageToken` up to
`capabilities.json` `limits.list_items_max` (a documented truncation past the ceiling, not an
error). `list-frontier --parent` is unavailable (needs `list-sub-items`, which is off).

## View item

`work-item-tracker.sh get-item jira:<site>/<PROJECTKEY>#<N>` returns the normalized item object
(CONTRACT.md "JSON output contract"): `state`, `assignees`, `labels`, `type`, open-only
`blocked_by_count`, `parent_id`, `url`. `blocked_by_count` counts only **open** inward blockers
under the configured link type (`config.jira.blocked_by_link_type`, default `Blocks`).

## Auth & prerequisites

`curl` on PATH (gated at call time, exit `3`). Basic auth is the account email
(`config.jira.auth_email`) plus an API token read from the env var **named** by
`config.jira.auth_env` — never stored in the tracked binding, and never placed in argv (fed to
curl through a stdin config). An unset/empty token env var is exit `4`; tokens expire, so treat a
sudden `4` as a rotation signal and re-bind. Generate tokens at
`https://id.atlassian.com/manage/api-tokens`.

## Gotchas

- **Deferred live-instance facts.** The exact `statusCategory` key for "Done" and the
  authoritative blocker link type are instance-specific and confirmed on the work-laptop pass;
  until then the adapter uses `config.jira.done_category_keys` (default `["done","completed"]`,
  covering both known representations) and `blocked_by_link_type` (default `Blocks`). Override
  either in the binding once the live values are known.
- **Epic parenthood.** `parent_id` comes from `fields.parent` — universal for subtask→parent and
  for story→epic in instances using the unified parent field, but `null` where an instance still
  models epic membership via the legacy Epic-Link custom field (a best-effort limitation deferred
  with the sub-item link-type work).
- **Windows `\r`.** The core strips CR from captured adapter output; the adapter also strips CR
  from every HTTP body before parsing, so stdout stays CR-free.
