---
description: "Onboard a work-item tracker this plugin does not bundle, by generating a consumer-owned adapter for the tracker seam: interview to lock the provider's shape, explore the consumer's real instance for the per-instance facts only it can settle, generate the adapter (hardened security skeleton, honest capability manifest, contract-fixed verb scaffolds, conformance binding) into the consuming repo, then verify. Use when: 'add support for <tracker>', 'onboard a tracker', 'write a work-item adapter', 'generate a tracker adapter', 'my tracker is not supported', 'use Gitea/Redmine/YouTrack/Azure DevOps/Phabricator with work-items', 'bring my own tracker', 'the seam has no adapter for my provider'. Skip when the provider is already bundled (github, local-markdown, jira) — bind it with '/work-items:setup' instead; skip for changing which provider a repo uses (also setup), and for fixing a bug in an existing adapter (ordinary implementation work)."
argument-hint: "[provider-name]"
user-invocable: true
# Model-invoked (fleet default); no exception class applies. Generation is gated by the
# interview and a dry-run read-back and never overwrites without --force, so it is not a
# timing-sensitive mutation; and "my tracker is not supported" is said by users who do not
# know this skill exists, which is exactly what model invocation is for.
disable-model-invocation: false
metadata:
  category: work-items
  summary: "Generate a consumer-owned work-item-tracker adapter for an unbundled provider, then verify it."
---

## Purpose

The tracker seam ships hardened adapters for the majors and cannot ship one for every
provider. This skill covers the tail: it walks a **consumer** from "my tracker is not
supported" to an adapter that lives in **their** repo, passes the seam's conformance
suite, and keeps working as the plugin evolves.

That is the point of the seam being consumer-configurable: adapters resolve
consumer-local-first (`CONTRACT.md` "Adapter resolution"), so an adapter generated here
needs no fork, no vendored engine, and no upstream PR.

**Not for**: a provider already bundled (`github`, `local-markdown`, `jira`) — bind those
with `/work-items:setup`, which also re-points a repo at a different provider. Not for
fixing an existing adapter (ordinary implementation work).

## The split

Deterministic work is scripted; judgement is not
(`/discipline:script-the-deterministic-work` if installed). Concretely:

| Judgement — you, in this flow | Mechanical — `scripts/generate-adapter.sh` |
|---|---|
| Which verbs the provider can honestly support | Emitting the manifest and the scaffolds for them |
| What the provider's fields *mean* | The security skeleton, arg parsing, exit codes, envelopes |
| What a live instance actually returns | Refusing an incoherent spec; stamping the seam's contract version |

The handoff between them is one artifact: **the adapter spec** (`reference/adapter-spec.md`).
The interview fills it; the generator consumes it. Everything the generator needs to be
deterministic is in that file, which is why the flow below is "reach a good spec, then run
one command".

## Step 1 — Interview

Lock the spec's fields before writing anything. Chain to `/planning:interview` (if
installed) when the answers are not already obvious; otherwise ask directly. Ask in this
order, because later answers depend on earlier ones:

1. **Provider identity.** The short name (lowercase, the directory and ID prefix) and the
   display name. The short name is permanent — it appears in every item ID this adapter
   ever produces.
2. **Transport and auth.** API base path; whether the credential is a bearer token, a
   `token`-scheme header, or HTTP Basic with an account identity. **Never ask for the
   credential itself** — only for the *name* of the environment variable that will hold
   it. If the user offers a token, stop and tell them not to paste it.
3. **Host posture.** Vendor-hosted (there is a domain to pin against, e.g.
   `.atlassian.net`) or self-hosted (there is not). This decides the default egress pin;
   see "Security posture" below.
4. **Scope shape.** What names a collection of items for this provider — `owner/repo`, a
   project key, a workspace slug — and the anchored character allowlist those names may
   use. That allowlist becomes a guard, so err toward strict.
5. **Verb coverage.** For each verb of the adapter surface, can the provider do it
   *natively and honestly*? Read `CONTRACT.md` "Verbs" and "Lease protocol" with the
   user's API docs open. A "we could fake it with comments" answer is a `false` plus a
   note — see "Honest manifests".
6. **Ceilings.** Sub-items per parent, nesting depth, dependencies per type, and the
   maximum page size `list-items` may request. A guessed ceiling is worse than a
   conservative one.
7. **Deferrals.** Anything that can only be settled against a live instance. Name them
   now; they become recorded deferrals with config overrides, not silent assumptions.

Write the answers to a spec file — `reference/adapter-spec.md` is the field reference and
carries a worked example.

## Step 2 — Explore the live instance

Some facts are not in the API docs, only in the user's actual instance. The bundled `jira`
adapter is the standing proof: its done-state category key and its blocker link-type name
could not be settled from the specification — the official example disagreed with real
instances — and both had to become config with defaults.

So: for each field the normalizer will read, have the **user** run a read-only probe
against their instance and paste the response shape. Typical probes: fetch one item and
read its state/type/assignee/label field names; fetch one item that is blocked and read
how the blocking edge is represented; list items and read the pagination envelope.

Two rules here:

- **The user runs the probes.** They hold the credential and the network path. Give them
  the exact command; do not ask them to hand over a token so you can run it.
- **What you cannot observe becomes a deferral, not a guess.** Add it to the spec's
  `deferrals` array and give the adapter a config key defaulting to the documented value,
  so the adapter is independent of the fact rather than wrong about it.

If no live instance is reachable at all, that is a legitimate state: generate against the
documented shapes, record every unobserved fact as a deferral, and say plainly in the
handoff that live conformance has not been run. Never report a suite you did not run.

## Step 3 — Generate

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/onboard-adapter/scripts/generate-adapter.sh" \
  --spec <spec.json> --dry-run
```

Read the dry-run file list back to the user, then re-run without `--dry-run`. Files land
in the consuming repo under `tools/work-item-tracker/` — the adapter beside its tests and
README, plus the conformance binding. Existing files are never overwritten without
`--force`, so a regeneration after the user has edited a mapping reports what it kept
instead of destroying it.

The generator **refuses** an incoherent spec rather than emitting a manifest that lies —
a verb declared without the feature it needs, a ceiling on a capability declared absent,
an unanchored scope pattern. Treat a refusal as information about the spec, and fix the
spec; do not work around it.

## Step 4 — Verify

In this order, because each step's failure means something different:

1. **The generated guards.** `bash tools/work-item-tracker/adapters/<p>/common.test.sh`
   — real and passing from the moment of generation. A failure here means the skeleton
   was edited, not that the provider mapping is incomplete.
2. **Fill the mappings, verb by verb.** Each generated verb script carries one
   `PROVIDER MAPPING` block and exits `1` until it is written. Write a mocked-transport
   test beside each (`WIT_<P>_CURL` is the injection point — copy the shape from the
   bundled `jira` adapter's `*.test.sh`) so the verb is covered offline.
3. **Conformance.** `run-conformance.sh --binding <p>`, which drives the same abstract
   suite over the adapter through the core CLI only. It needs a **throwaway** target;
   the generated binding refuses to run without one named explicitly. Never point it at
   a coordination instance — the suite creates, claims, and closes items.

Report what actually ran. If conformance was not run against a live instance, say so and
say why; the deferral belongs in the adapter README and in the work item, not in a
hopeful summary.

## Honest manifests

The capabilities manifest is what the core **routes on**: it decides whether a verb is
attempted at all, and callers branch on its features and limits without re-probing. So a
verb the provider cannot do gets `false`, and the core answers it with exit `6` — an
explicit, permanent degradation a caller can route around.

The failure mode to refuse is faking. A lease emulated with comments the provider does not
arbitrate is not a lease: it loses races silently, which is worse than not having one.
Declare `false`, record why, and let the frontier logic see the truth. Equally, never
leave an unwritten scaffold declared `true` — it exits `1` deliberately, not `6`, because
`6` would launder unfinished work as a provider limitation and let conformance pass over a
verb that does nothing.

## Security posture

The skeleton is **template-driven, not re-derived per provider**. It is generated already
carrying the guards the bundled `jira` adapter was hardened into, and the generated
`common.test.sh` proves them:

- Credential read from the env var *named by* the binding, never stored in the tracked
  file, and passed to curl through a stdin config so it never reaches `argv`.
- Host validated as a bare hostname; HTTPS enforced by curl itself; redirects not
  followed, so the `Authorization` header cannot be replayed to another host.
- Egress denied by default where a pin exists. Vendor-hosted providers get a code-level
  suffix pin. **Self-hosted providers have no vendor domain to pin against** — the
  generated README says so outright, and the binding's own `host_suffix` key is offered
  as the consumer's pin. State this to the user rather than implying the pin is there.
- Values reaching request paths matched against an anchored allowlist and refused when
  they do not conform, because a rejection is loud and an escaping bug is silent.

Do not weaken these when filling in a mapping. If a provider genuinely cannot work within
them, that is a finding to raise, not a guard to delete.

## Gotchas

- **The normalized item object has no `body` field.** It is `schema_version, id, title,
  state, assignees, labels, type, blocked_by_count, parent_id, url`. A mapping that plans
  to carry spec text through the seam is designing against a field that does not exist.
- **`blocked_by_count` counts OPEN blockers only.** Counting closed ones is the bug that
  keeps an item off the frontier forever. GitHub's own `totalCount` gets this wrong, which
  is why the bundled adapter counts open nodes itself.
- **IDs are fully qualified**, `<provider>:<owner>/<repo>#<n>` — exactly two path segments.
  A scope like `acme/webapp` fills both; a bare project key needs the host in front of it.
  A bare `#123` is never persisted anywhere.
- **`list-items` must paginate to the manifest's declared ceiling**, never a client
  default. A library that silently truncates makes the frontier lie about what is
  available.
- **The generated adapter does not need a vendored seam.** The dispatcher exports
  `WIT_SEAM_LIB_DIR`; a verb run directly without it exits `3` naming that variable —
  correct behavior, not a generation bug.
- **`list-items: false` is coherent but consequential** — `list-frontier` can then never
  succeed, so no work-selection flow finds anything. Legitimate for a consume-only
  adapter; say it out loud when it is chosen.

## Related

- `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` — the contract obeyed.
- `reference/adapter-spec.md` — spec fields, validation rules, worked example.
- `reference/live-exploration.md` — the probe checklist for step 2.
- `/work-items:setup` — binds the repo to a provider once the adapter exists.
