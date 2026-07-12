# Changelog — ecosystem-commands convention

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
