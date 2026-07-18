# Role topology

Normative contract for the repository roles an autonomy adoption spans. Contract text — here
and in every sibling contract document — names roles only; the mapping from each role to an
adopting org's real repository lives in that org's binding instance document (see
`binding-seam.md`).

## Roles

| Role | Owns |
|---|---|
| capability-distribution home | The distributable capabilities and their contract documents — this plugin's own home. |
| CI-orchestration home | Reusable pipeline execution logic: event handlers, emission steps, verification lanes. |
| settings-as-code home | Declarative platform settings: labels, permissions, runner-policy admission, repository configuration. |
| org-policy home | Org-wide policy and conventions, including the org's binding instance document. |
| runner-execution home | The autonomous-runner execution substrate. **Unborn**: this role is created only when the runner charter's build trigger fires; until then no repository holds it. |

## Adapter split rule

A signal adapter (an event or schedule that starts governed autonomous work) splits by role:

- **Handler logic** — the executable steps a pipeline runs — lands in the CI-orchestration home.
- **Enabling settings** — labels, permissions, admission policy that let the handler fire —
  land in the settings-as-code home. Admission-policy changes are reviewed contract changes,
  never silent edits.

## Composition stance

This plugin composes existing capability seams rather than duplicating them:

- the work-item queue, lease, and dispatch seam;
- deterministic guardrail hooks;
- verification gates;
- session observability.

A capability here that near-duplicates a capability an adopting deployment already has is a
defect: compose the seam, or route a change to the seam's own home. Orchestration that
composes existing capabilities is the sanctioned model.
