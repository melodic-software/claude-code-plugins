# Changelog — ecosystem-commands convention

## 1.1.1 — 2026-07-25

Clarification, no schema shape change: the gate `trigger-globs` description now states explicitly
that it never selects an ecosystem under auto-targeting — it only narrows a run *within* an already-
affected ecosystem (matched against the full changed-file set) — and names the supported pattern for
a cross-ecosystem trigger (add the pattern to the ecosystem's own `globs`). Settled by decision on
melodic-software/claude-code-plugins#1339; ratifies the subordinate model `/toolchain:check` already
implements, no runtime behavior change.

## 1.1.0 — 2026-07-15

Additive: optional `tool-pin` key — pinned tool versions keyed by tool name. When present, resolvers
warn if the installed version drifts from the pin (a pin typically mirrors the repo's own CI pin);
inert when absent. Bundled portable defaults never set it — pins are consumer-specific.

## 1.0.0 — 2026-07-12

Initial contract (design gate melodic-software/medley#1390):

- Consumer surface: `.claude/ecosystems/<ecosystem>.yaml`, one file per ecosystem, filename stem =
  ecosystem identifier; `<ecosystem>.local.yaml` gitignored overlays; optional `~/.claude/ecosystems/`
  user-global; resolution user-global → team → local overlay, additive per key.
- Schema `ecosystem.schema.json`: required `globs`; optional `enabled`, `anchor`,
  `project-discovery`, `build-cmd`, `test-cmd`, `check-cmd`, `fix-cmd`, `opt-in`, `install-hint`,
  `gates[]`, `notes`. Command values are opaque shell strings; null = phase absent.
- Canonical-verb vs context-binding boundary: this contract owns the verb; hooks/CI own their
  bindings and cite the ecosystem file.
- Concern-named folder recorded as a seam-2 PRECEDENT-EXTENSION for multi-plugin-consumed config.
- Task-runner verb SSOT deferred with recorded revisit triggers; runner-pointer demotion path is a
  value swap by design.
