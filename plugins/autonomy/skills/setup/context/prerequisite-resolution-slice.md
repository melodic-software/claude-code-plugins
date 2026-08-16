# Prerequisite-resolution slice

Extends `/autonomy:setup` per the skill's own extension model. Owns the
[routine prerequisite resolution](${CLAUDE_PLUGIN_ROOT}/reference/prerequisite-resolution.md)
question at setup time: which `v1` identities can run against this repository on each
declared scheduling surface, and why.

## Liveness

This slice's `check` is an **engine health-check** surface under
[`liveness-assertion`](../../../../../docs/conventions/liveness-assertion/README.md): it
invokes the deterministic resolver end-to-end and fails loud on internal failure. It never
reports "healthy" from configuration alone, and never invents a verdict-shaped fallback.

## `check` (read-only)

1. Resolve scheduling-surface ids from the existing binding (`triggers.surfaces` and
   `routines.surfaces` — merged; the slice never declares its own `surfaces` map).
2. For each surface, run
   [`scripts/resolve-prerequisites.mjs`](../scripts/resolve-prerequisites.mjs) against the
   project root.
3. Report per-identity verdicts (`supported` / `conditional` / `unsupported` / `unknown`)
   with per-signal provenance and any findings (declaration↔probe contradictions).
4. On a bare repo (no binding, no tracker, no CI), every identity reports
   `unsupported` or `unknown` — never an error.

Wrapper:
[`scripts/check-prerequisite-resolution.mjs`](../scripts/check-prerequisite-resolution.mjs).

## `apply` (interactive propose → ratify)

1. **Detect-diff-reconcile.** Run the same resolution as `check`. An existing
   `prerequisite_resolution` declaration is authoritative input: divergence from probe
   results is a **finding**, never a silent overwrite. A ran-negative probe caps a positive
   declaration (ADR 0011 Decision 2) — the identity stays `unsupported` while the finding
   is open.
2. **Prose-context pass (proposal only).** Read host instruction files (`CLAUDE.md`),
   secondary agent-instruction files (`AGENTS.md` — reaches a session only through a
   reference), and `README` for *proposed* declarations into **non-security keys only**.
   The deterministic resolver never parses prose; prose is never runtime authority.
3. **Human ratifies.** Interactive contexts present proposals one at a time. Non-interactive
   and forked contexts skip ask-and-persist rungs and report assumptions (topic-docs rule).
4. **Write additively.** On ratification, write the `prerequisite_resolution` section of
   `.claude/autonomy/binding.json`:
   - `schema_version`: `"1.0"`
   - `surface_refs`: existing scheduling-surface ids (references only — **no `surfaces` map**)
   - `declarations`: `{ surface, identity?, need?, state, rung }` entries
5. **Narrowing-only enablement.** An identity may be enabled in `routines.enabled` only when
   its verdict clears (`supported`, or `conditional` where the named conditions are accepted).
   `unsupported` / `unknown` route to the advisory path. The slice **prepares** any
   security-binding change (admission / classification) and **never writes** that surface.
6. **Org-rung entitlements.** Connector entitlements for `prod` / `product` / `org` / `ext`
   bind at the Org binding layer. The slice reports which prerequisites await the org rung
   and stops — it never auto-writes org-rung values into the repo-local binding.

Wrapper (non-interactive propose / optional `--ratify` for tests):
[`scripts/apply-prerequisite-resolution.mjs`](../scripts/apply-prerequisite-resolution.mjs).

## Binding section shape

```json
{
  "prerequisite_resolution": {
    "schema_version": "1.0",
    "surface_refs": ["ci-cron"],
    "declarations": [
      {
        "surface": "ci-cron",
        "identity": "issue-triage-sweep",
        "need": "tracker",
        "state": "present",
        "rung": "repo-local"
      }
    ]
  }
}
```

Absent-section tolerance holds. The section MUST NOT carry a `surfaces` map —
[`check-signal-envelope.mjs`](../scripts/check-signal-envelope.mjs) merges every section's
`surfaces` map and treats duplicates as ambiguous.
