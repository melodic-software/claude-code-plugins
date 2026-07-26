# Changelog — ecosystem-commands convention

## 1.2.0 — 2026-07-25

Additive: optional `gates[].run-from` key (`"ecosystem"` default | `"repo-root"`) — lets a gate
declared under a `project-discovery` ecosystem force a single run from `$REPO_ROOT` instead of
inheriting the ecosystem's per-project execution location. Closes the gap tracked in
melodic-software/claude-code-plugins#1361, deferred from #1020: a repo-wide gate (protobuf
generation, schema freshness) under `go`/`python`/`typescript` had no way to opt out of running once
per discovered project root. Omitting the key preserves current behavior exactly.

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
