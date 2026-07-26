# Changelog — ecosystem-commands convention

## 1.2.1 — 2026-07-25

Docs-only, no schema shape change: `examples/go.yaml` gains a clearly-commented illustrative gate
(`proto-gen-freshness`) demonstrating the `run-from: repo-root` shape added in 1.2.0 — no bundled
default or example repo needs it yet, so it is documentation, not a functioning gate. Its
`trigger-globs` (`*.proto`, `buf.gen.yaml`) are also added to the file's own `globs`, per the 1.1.1
reachability rule, so the worked example is actually reachable under auto-targeting rather than
silently unfired. Its freshness `cmd` pairs `git diff HEAD --exit-code` with
`git ls-files --others --exclude-standard`: a bare `git diff` compares only against the index (a
staged regeneration reports clean) and never reports untracked paths at all (a newly generated
output false-passes), so both forms are needed for the example to demonstrate a gate that actually
catches stale generated code. Deferred from melodic-software/claude-code-plugins#1361 via #1462 (a
documentation-depth finding from #1460's review): a worked `run-from: repo-root` example was still
missing.

## 1.2.0 — 2026-07-25

Additive: optional `gates[].run-from` key (`"ecosystem"` default | `"repo-root"`) — lets a gate
declared under a `project-discovery` ecosystem force a single run from `$REPO_ROOT` instead of
inheriting the ecosystem's per-project execution location. Closes the gap tracked in
melodic-software/claude-code-plugins#1361, deferred from #1020: a repo-wide gate (protobuf
generation, schema freshness) under `go`/`python`/`typescript` had no way to opt out of running once
per discovered project root. Omitting the key preserves current behavior exactly. Placeholder
semantics under `repo-root` are pinned in the same bump: `<files>` expands to the full
ecosystem-scoped changed-files set (not one project's subset), and `<project-dir>` is undefined — a
`cmd` using it under `repo-root` is a configuration error a resolver reports as a failure rather than
guessing an expansion.

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
