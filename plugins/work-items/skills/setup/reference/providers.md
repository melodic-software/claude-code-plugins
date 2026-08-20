# Provider comparison

The full bundled-provider detail behind step 2 of the provider-binding interview in `SKILL.md`.
Read it when choosing or re-binding a provider; the skill's own list is the summary.

The seam's contract for each is `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`, and
each adapter carries its own README beside it.

## `github` — RECOMMENDED

Coordination over GitHub Issues via the ambient `gh` CLI. Full verb parity: reads, writes, the
claim/renew/reclaim lease protocol, native sub-items, and dependency edges. Needs no provider
config beyond the lease TTL.

**Verifying it at bind time.** Confirm `gh` is installed — the seam hard-errors at call time when
`gh` ≥ 2.94 is absent — then confirm the checkout itself resolves:

```sh
gh repo view --json owner,name
```

That is the same derivation the adapter's repo-scope resolution makes for every repo-scoped verb.
Report the `owner/repo` it returns. **That one call is the operative test, and it subsumes
authentication**: it fails unauthenticated even against a public repository, so succeeding proves
`gh` is authenticated for the host this checkout uses.

`gh auth status` is **not** the test. It is an account fact, not a repository one — a local-only or
non-GitHub checkout passes it and still has no repository for the seam to address — and it tests
every account on every known host, exiting 1 if any has an issue (`gh auth status --help`), so an
unrelated stale credential would condemn a good checkout. Run it to explain a failure, never to
gate the choice.

## `local-markdown`

The offline reference provider: one markdown file per item. **Never a coordination surface.** The
store is working-tree files, so items, leases, and ids are branch- and worktree-confined —
multi-session work needs a tracker-published spec on a coordination provider instead.

Requires `config.storage_dir` (no baked default; e.g. `.work-items`). See CONTRACT.md
"local-markdown adapter" and `adapters/local-markdown/README.md`.

## `jira`

Read/resolve-only against a Jira Cloud project set. **Consume-only**: no ticket creation, claim, or
mutation — write verbs exit `6`. Selecting it does not enable `/work-items:work` or `track start`
(both need writes) — an accepted gap.

Requires `config.jira` (`site`, non-empty `project_keys[]`, `auth_email`, `auth_env`) and `curl`.
The API token is referenced by env-var name only, never stored. Binding shape and the deferred
live-instance facts are CONTRACT.md's "jira adapter".

## `gitea`

Gitea / Forgejo — self-hostable and free, so it is the no-paid-tool option for solo developers.
Reads and creates issues and writes blocked-by dependency edges, including across repositories.

**No leases and no sub-items.** Gitea's issue has no parent field at all, and whether it arbitrates
concurrent assignment could not be settled without a live instance — so
`claim`/`renew-lease`/`reclaim`/`add-sub-item`/`list-sub-items` exit `6`. Practically: `/work-items:work`
cannot claim on it, and it is not a multi-agent coordination surface.

Requires `config.gitea` (`host`, non-empty `scopes[]` of `owner/repo`, `auth_env`) and `curl`;
the token is referenced by env-var name only, never stored. Optional `page_size`, `host_suffix`,
`allow_custom_domain`. See `adapters/gitea/README.md` for its provider notes and recorded
deferrals — **including that no live-instance conformance pass has been run**.

## Another provider

Supply the adapter consumer-local at
`${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/adapters/<provider>/`.
The seam resolves consumer-local adapters ahead of the bundled set, so a repo can add an unshipped
provider — or shadow a bundled one — without forking the plugin. Set `provider` to its name in the
binding.

`/work-items:onboard-adapter` (if installed) generates one: interview, live-instance exploration, a
hardened security skeleton, an honest capability manifest, and the conformance binding — rather
than starting from a blank file.

## Config keys by provider

| Key | Required for | Meaning |
|---|---|---|
| `lease_ttl_hours` | every provider | Claim-lease lifetime in hours. RECOMMENDED `24`. |
| `storage_dir` | `local-markdown` | The item-store directory. |
| `jira` | `jira` | `site` (Cloud host), non-empty `project_keys[]`, `auth_email`, `auth_env` (env-var NAME holding the token). Optional `blocked_by_link_type` / `done_category_keys` override the deferred live-instance defaults. |
| `gitea` | `gitea` | `host` (bare hostname), non-empty `scopes[]` (each `owner/repo` — the declared read scope **and** the authorization boundary), `auth_env`. Optional `page_size` (default 50 — lower it if the instance sets `api.MAX_RESPONSE_ITEMS` below that), `host_suffix` (your own egress pin; Gitea is self-hosted, so there is no vendor-domain default), `allow_custom_domain`. |

For any token: interview for the env-var **name**, and probe that the token resolves in-env at bind
time — never store it. Per the operator secret-binding classification, a token's durable home is
the OS-native credential store, with the env var as the CI/headless fallback, never a plaintext
file.

**Secrets never go in the binding file** — it is tracked in git. A provider needing an API token
references it by env-var name (or the repo's secret-store convention) from inside its adapter,
never as a literal. `github` needs none (ambient `gh`); `jira` and `gitea` reference theirs by
`auth_env` name.
