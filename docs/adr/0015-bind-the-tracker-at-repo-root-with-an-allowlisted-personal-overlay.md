# Bind the tracker at the repo root with an allowlisted personal overlay

- Status: accepted
- Date: 2026-08-18

## Context

The work-item tracker binding (`.work-item-tracker.json`) declares which provider
coordinates a repo's work items. Seam scrutiny (#2933, findings F1.1–F1.7, F3.8) surfaced
four structural questions the original shape had answered by accident rather than decision:
discovery climbed from CWD to the *filesystem root*, so a stray ancestor or home-directory
binding silently captured every repo beneath it — exactly what the config-cascade
convention forbids; three root-anchoring regimes coexisted in one seam (CWD climb for the
binding, `CLAUDE_PROJECT_DIR`-only for consumer-local adapters, `CLAUDE_PROJECT_DIR`-with-
git-fallback in skill snippets), so a bare shell could find the binding while silently
skipping a consumer-local adapter shadow; the tracked binding froze per-account values
(jira `auth_email`) into a team file; and the marketplace's config-cascade contract expects
surfaces to declare their layering, which this one never had. The design was settled by
interview on #2941 (2026-08-17); this ADR records it.

## Decision

- **Location stays the repo root, tracked.** `.work-item-tracker.json` remains at the repo
  root as the single team layer. Moving under `.claude/` + full cascade was rejected: a
  cross-plugin breaking migration (37 referencing files, including the autonomy plugin's
  hardcoded reader) plus the `.claude/` write-guard risk on unattended first-bind.
  Location-configurability was rejected as a bootstrap regress — a locator would be needed
  to find the config.
- **One personal layer: a gitignored overlay beside the team file.**
  `.work-item-tracker.local.json` merges **per-key over an allowlist, deny-by-default**:
  `config.lease_ttl_hours`, `config.lease_ttl_minutes` (TTL travels inside each lease
  record, so per-user is coherent), `config.jira.auth_email`, `config.jira.auth_env`,
  `config.linear.auth_env`, `config.gitea.auth_env` (auth identity is per-account on each
  of those adapters), and the self-describing `docs` pointer. Any other overlay key
  is a configuration error (exit 3, keys named), never a merge — `provider`,
  `role_labels`, `container_label`, `storage_dir`, and the jira scope/JQL keys are shared
  coordination state, and leases/labels/frontier live provider-side, so a personal
  provider override would fracture the team's coordination surface.
- **Deliberately NO user-global layer.** A `~/.claude/...` layer exists in the cascade
  contract to carry preferences across repos; every key this surface could safely carry
  per-user is already covered by the overlay, and a user-global rung would reopen the
  personal-provider trap by giving cross-repo defaults a place to live. Structural
  foreclosure over policy text.
- **One root anchor for everything.** All repo-relative resolution — binding read,
  consumer-local adapter dirs, the github adapter's bot-wrapper lookup — anchors at
  `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}`. The CWD climb is removed;
  nested per-subdirectory bindings are unsupported until requested (the seam's established
  demand-gated pattern). `WORK_ITEM_TRACKER_BINDING` remains a tests/conformance override.
- **Format stays JSON**, with an optional `docs` key as the self-describing pointer
  `/work-items:setup` writes by default. `jq` is the seam's hard prerequisite and the hot
  readers are shell + Node; YAML would cost a parser in three ecosystems to buy comments
  the `docs` key provides without one.
- **Gitignore ownership.** The marketplace's one-line `.claude/**/*.local.*` convention
  cannot cover a root-level overlay, so `/work-items:setup apply` appends the
  `.work-item-tracker.local.json` gitignore line itself, announced — a narrow, declared
  exception to "no plugin writes the consumer's `.gitignore`", accepted because a
  personal overlay reaching team history is the worse failure.

The config-cascade implementers table records this surface as a **declared** partial
cascade: team + overlay at the repo root, no user-global layer, precedent `standards`
(location outside `.claude/`).

## Consequences

Existing consumers keep working unchanged — the file neither moves nor changes shape, and
a repo without an overlay reads byte-identically to before. The behavioral change is
discovery: a binding that was only ever found via the ancestor climb (outside the repo
root) stops resolving, which is the F1.1 bug being fixed, not a regression. Conformance
and unit tests cover the overlay merge, the allowlist rejection, and the anchoring —
including the bare-shell consumer-local adapter case (F3.8).
