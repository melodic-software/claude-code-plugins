# PR-body required-sections convention

Owner doc for the `pr_body_required_sections` key: a configurable scaffold of `## <heading>`
sections a pull-request body must carry. This concern is designed for **more than one plugin** —
`source-control` drafts and pre-checks against it today; a future CI or `guardrails`-style
enforcement consumer validates an already-created PR body against the same key later — so its
ownership lives here at marketplace level, not inside `source-control`, per
[`docs/MIGRATION-PLAYBOOK.md`](../../MIGRATION-PLAYBOOK.md) "concern-named config consumed by >1
plugin". An owner doc lands before the second consumer adopts the key, not after.

## The key, and where it lives

`pr_body_required_sections` is one key on the consumer's tracked `.claude/source-control.md` (H2-per-key
markdown), resolved across the same three layers as every other key on that surface —
user-global, team-tracked, and a gitignored personal overlay — per
[`source-control/reference/config-resolution.md`](../../../plugins/source-control/reference/config-resolution.md).
That document owns the **resolution mechanics**: the value grammar, the three-layer read order, and
the per-key (whole-list) override semantics. This doc never restates them — it owns the concern's
*shape* and *rationale*, and points there for *how* a value resolves.

## Consumers

- **`source-control` drafting (today).** `/source-control:pull-request create` resolves the
  effective section list before assembling a PR body, builds one `## <heading>` scaffold per
  required section, and runs a pre-`gh pr create` gate that fails when an assembled body is missing
  a required section or leaves one empty — see
  [`skills/pull-request/reference/create.md`](../../../plugins/source-control/skills/pull-request/reference/create.md)
  §2.4.1 (assembly) and §2.4.2 (gate).
- **CI / enforcement (deferred).** A gate validating an *already-opened* PR body against the same
  team-tracked value — the enforcement half of the two-reads pattern the
  [commit-convention seam](../commit-convention/README.md) already establishes for the
  commit-subject / PR-title convention. No such consumer exists yet in this fleet; this doc reserves
  the seam so the second adopter reads the same key instead of inventing a parallel one.

## Portable default: `Summary` and `Test plan` only

When no layer sets `pr_body_required_sections`, the plugin's built-in scaffold requires exactly two
sections: `Summary` and `Test plan`. This is a deliberate **lane-1 default**
([`docs/PLUGIN-PHILOSOPHY.md`](../../PLUGIN-PHILOSOPHY.md) "Two-lane convention posture") — a
good-practice value that cannot conflict in any repo the plugin drops into, because it presumes
nothing about the consumer.

Research basis (GitHub's own PR-description guidance, Google's engineering-practices CL-description
doc, GitLab's dogfooded default merge-request template, and a cross-section of OSS project PR
templates, weighed against anti-heavy-template falsification cases): **what/why the change does,
plus evidence it was verified**, is the near-universal core of a reviewable PR description across
ecosystems and org sizes. A third common section — a linked-issue or "Related" reference — is
**not** part of the portable default: it presumes the consuming repo runs an issue tracker and links
PRs to it, which is an org-specific choice, not a property every repo shares. That choice belongs in
configuration, not in the plugin's shipped default.

**`## Related` is never dropped by the mechanism** — a consumer whose convention includes it
declares `Related` in its own `pr_body_required_sections` list (team-tracked, local overlay, or
user-global), the same as any other section name. The plugin ships no opinion on it either way.

## Resolution semantics

Layering, per-key override, and the value grammar are entirely owned by
[`config-resolution.md`](../../../plugins/source-control/reference/config-resolution.md) — this doc
does not restate them. Two points worth surfacing here because they are easy to get wrong when
reading only the mechanism doc:

- **A later layer's list replaces the earlier layer's list wholesale**, never merges element-wise.
  Declaring `pr_body_required_sections` in a personal overlay is not additive to the team file's
  list — it is the effective list for that operator, in full.
- **Order is presentation, not matching.** The gate (below) checks presence and non-empty content per
  heading; it does not require the assembled body's sections to appear in the configured list's
  order.

## The pre-create gate

`/source-control:pull-request create`'s §2.4.2 pre-`gh pr create` gate checks, for every section in
the resolved `pr_body_required_sections` list, that a `## <heading>` section exists in the assembled
body **and** its content is non-empty. On failure it names the exact missing or empty section and the
resolved config source (the winning layer's file path and the `pr_body_required_sections` key) —
never a bare "PR body invalid" — so the actor who never saw the convention learns where it lives on
first failure, not by asking someone.

This gate is orthogonal to, and does not replace, the existing closing-keyword / no-issue-marker
check on the same body (`Closes #N` or `No related issue:`) — that mechanism is unchanged by this
seam and documented at its own site in `create.md` §2.4.0/§2.4.2.

## Deferred: richer per-section schema

**V1 is a flat list of required heading names — nothing more.** The following are known,
deliberately deferred limitations, not oversights:

- **Conditional sections** — a section required only under a condition (e.g. a screenshots section
  required only for UI-affecting changes, or Kubernetes' `NONE`-sentinel release-note block) has no
  expression in a flat list.
- **Placeholder-content rejection** — the gate checks *non-empty*, not *non-placeholder-text*
  (`TBD`, `TODO`, a restated heading). A section satisfied by literally re-emitting the scaffold's
  own stub content is not currently caught beyond the empty case.
- **Minimum-content / structure rules** — no per-section length, format, or sub-structure
  requirement (e.g. "Test plan must contain at least one checklist item").

Trigger for revisiting: `melodic-software/standards#173` (PR convention policy-as-data — one policy
file, one validator, thin CI runners, plugin mechanism). That effort's first implementation PR is
the point at which this seam's schema and the eventual enforcement consumer converge on one shape,
rather than this plugin inventing a second policy format ahead of it.
