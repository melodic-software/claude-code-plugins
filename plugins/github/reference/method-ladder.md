# Method ladder

The one mechanism every skill in this plugin uses to resolve **how** to read or (when explicitly
routed) change a GitHub admin-plane surface. The plugin ships no endpoint tables, no scope lists,
and no UI walk-throughs — the ladder resolves current mechanics at runtime, per invocation, from
live `gh` state and freshly fetched official GitHub docs.

## Rung 0 — Preflight

1. `gh` present? If not: stop with a concise message naming the missing prerequisite and the
   official install page (`https://cli.github.com`). Do not attempt raw REST calls without it.
2. `gh auth status` — confirm an authenticated session and note which account/host it is for.
   Never store, echo, or persist credentials.
3. **Credential-modality diagnosis** (when an area needs it): determine what kind of credential
   the session actually holds (OAuth login, classic PAT, fine-grained PAT, GitHub App) from
   `gh auth status` output and live probe results — not from an assumed capability table. Some
   admin surfaces accept only specific modalities; discover that from the fetched docs for the
   area, then verify against the live session.

## Rung 1 — `gh` native

Prefer a purpose-built `gh` subcommand when one covers the surface (`gh ruleset`, `gh repo`,
`gh org`, …). Discover availability at runtime (`gh help`, `gh <topic> --help`) rather than from
memory — the CLI grows.

## Rung 2 — `gh api` (REST)

When no native subcommand fits, call the REST API through the user's session with `gh api`.
Resolve the endpoint from the freshly fetched official docs for the area (REST hub:
`https://docs.github.com/en/rest`), never from recall.

**Read-only contract (bare invocations).** On any invocation without an explicit apply override,
requests must be incapable of writing:

- no `-f`/`-F`/`--field`/`--raw-field`/`--input` (these imply a POST body),
- no `--method`/`-X` with anything other than `GET`,
- no pagination or preview flag workaround that smuggles a body.

The contract is capability-based: "no `-X POST`" alone is NOT the guard — `gh api -f` implies
POST without ever naming a method.

## Rung 3 — `gh api graphql`

For surfaces only (or best) covered by GraphQL (GraphQL hub: `https://docs.github.com/en/graphql`).
Same read-only contract: bare invocations send `query` documents only — never a `mutation`
keyword in the body, and no field flags that build one.

## Rung 4 — UI-only detection

If the fetched docs for the area show the surface is settings-UI-only (no CLI, no API), say so
plainly. A browser-automation **offer** (never auto-fired, per-action user confirm) is the next
rung when a browser integration is present in the session; the offer mechanics live in a dedicated
reference shipped in a later phase. Absent that, fall through to rung 5.

## Rung 5 — Guided manual steps + deep link

Always available: walk the user through the change themselves, with a deep link to the exact
settings surface resolved from the fetched docs (never a from-memory URL), and the doc citation
alongside each step.

## Cross-cutting rules

### Fetch integrity (applies before grounding on any fetched page)

Before treating a fetched page as grounding, verify it is the expected canonical surface: right
domain (`docs.github.com` or the resolved official host), right topic, content actually answers
the question. A redirect to an unrelated page, a stub, an error page, or a blocked fetch is a
**failed** ground. On failure: say so, and refuse to present training-data recall as grounded —
either retry via the docs search on the live site, or report the area as unverifiable this run.
An explicitly-labeled unverified suggestion is permitted; blending recall into grounded findings
is not.

### 403/404 disambiguation (probe before attributing)

A 403/404 on an admin surface has at least four distinct causes. Never report one as another, and
never report any of them as "drift":

| Cause | How to distinguish |
|---|---|
| Plan/SKU gate | Fetched docs state the feature's plan requirement; probe a surface known-available on the current plan for contrast |
| Token scope missing | `gh auth status` scopes vs the scope the fetched doc names for the endpoint; `gh` often surfaces the needed scope in the error body |
| Credential modality | Same token class fails across the whole surface family while docs say another modality is required |
| Genuinely unset / absent | The read succeeds elsewhere in the same family and the docs confirm the resource is optional |

When the cause is a missing scope, recommend the `gh auth refresh` remediation **for the user to
run themselves** — never auto-run a re-consent.

### Honest degradation (plan/SKU and reach)

When a gate blocks an area: name the gate (plan, scope, modality, UI-only), report what was
reachable, and degrade to guidance-only for the rest. Do not guess values behind the gate, and do
not silently shrink the audit's claimed coverage.

### Org-scale scoping

- Default to **area-scoped** invocations; confirm with the user before an all-area sweep across an
  organization.
- Emit findings **incrementally per area** so partial progress survives interruption.
- On rate limiting (429 / secondary limits): stop cleanly and return honest partial results that
  name exactly which areas/repos were skipped.
