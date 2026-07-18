# autonomy

Governed autonomous agent operation. This plugin is the capability-distribution home for the
AI-adoption-ladder contract set: it ships the tool-agnostic contracts an adopting org binds to
its own repositories, tools, and policies, plus a guided-setup skill that discovers the org's
state and records that binding.

## Shipped capability (0.2.0)

- **Topology contracts** (`reference/`): role topology for the repositories an adoption spans,
  the binding-seam shape that maps contract roles to an org's real instances, and the
  wiring-vs-advisor principle governing how setup lands changes.
- **Telemetry contract** (`reference/telemetry.md`): standards-pinned OTLP from every execution
  context, the `autonomy.work_item.url` join attribute, one causal tree by context propagation,
  sink classes with a zero-cost file-artifact default — plus the setup telemetry slice, its
  snippet templates, and the emission-conformance check.
- **Guided setup** (`/autonomy:setup`): discovery-first interview of the adopting org's state —
  role homes, substrate availability, budget posture — writing a schema-versioned binding under
  `.claude/autonomy/` as reviewable changes. Never assumes any particular org or repo shape.

## Roadmap (deferred, trigger-gated)

Each capability below lands with its own work package; none ships before its contracts are
locked (no step-skipping — trust before scale).

| Capability | Trigger |
|---|---|
| Return-accounting convention + capture slice | Return-accounting work package build lands. |
| Trigger/dispatch adapters | Trigger-layer work package build lands. |
| Guardrail matrix + sandbox-ladder binding | Guardrails work package build lands. |
| Standing-routine catalog + v1 definitions | Routines work package build lands. |
| Runner charter execution pack | The runner build trigger fires (charter's own conditions). |

## Trigger register (plugin-scoped)

| Trigger | Action |
|---|---|
| Role vocabulary changes in `reference/role-topology.md` | Update the org-policy home's binding instance doc to the new vocabulary version. |
| A second plugin consumes `.claude/autonomy/` config | Graduate the binding schema to a versioned concern contract per the marketplace's concern-named-folder convention. |

## Configuration

Setup writes tracked config to `.claude/autonomy/` in the consuming repo (concern-named — the
config outlives any plugin restructure). Personal overlays follow the marketplace overlay
convention: `.claude/autonomy/**/*.local.*` stays gitignored; layers resolve per the
binding-seam ladder — user-global → org binding (when pointed) → project → local overlay —
additively.
