# Lint / static-analysis gaps

## Brief

### TLDR

Close the fleet's lint/static-analysis gaps with one epic in this repo (typos hook plugin, Go
coverage in both lanes, lychee-offline + pyright batch additions, .NET runtime guard,
hook-observability convention, bespoke-guard routing), plus two epics owned elsewhere
(setup-lifecycle convention here as its own design effort; standards adoption sweep +
ecosystem-declaration in `melodic-software/standards`).

### Goal

Local lanes catch what CI gates, so agents fix findings at edit time instead of burning
commit–push–CI round-trips. Every addition follows the plugin philosophy: consumer-config-driven,
zero shipped opinions, runtime detection over assumptions, advisory hooks that auto-fix silently
and surface only residual unfixables.

Epic sub-items (discuss-first honored — file only on explicit request; epic + sub-issues shape):

1. **typos hook plugin** — per-file autofix (`typos -w`), consumer `_typos.toml` ancestor walk-up,
   false-positive remediation via consumer allowlist entries (`extend-words` /
   `extend-identifiers` / `extend-ignore-re`), advisory residual-only context, hook-precision +
   hook-telemetry conventions.
2. **Go coverage, both lanes** — new `go` batch ecosystem default (golangci-lint v2, format,
   `go mod tidy`; govulncheck optional) and a Go format hook plugin. Formatter selection
   (gofmt / goimports / gofumpt / `golangci-lint fmt`) is an implementation-time field survey per
   the pick-for-the-problem discipline; criteria: official/authoritative, maintained,
   feature-fit. golangci-lint is batch-only by design (package-scope analysis, per its FAQ).
3. **lychee-offline** added to `cross-cutting.yaml` (on-disk link/anchor integrity; gating in CI,
   no network).
4. **pyright** added to `python.yaml` check-cmd (CI gates it; local batch was ruff-only).
5. **.NET batch guard** — `dotnet` ecosystem entry detects analyzer/`.editorconfig` configuration
   presence at runtime each run; skips with a visible notice when absent. No assumptions about
   consumer state; .NET stays batch-lane only.
6. **Hook-observability fleet convention** — every fleet hook emits `statusMessage` (during run),
   `systemMessage` (failure/notable action), and the hook-telemetry OTel envelope. Grounded in
   current official hooks docs at authoring time (no native user-visible hook UI exists as of
   2026-07-21; OTel events + author-emitted messages are the sanctioned surfaces). Optional
   sub-item: upstream feature request for a native verbose-hooks UI toggle.
7. **Bespoke CI guards** (comment-hygiene, exec-bit, machine-specific-paths,
   reference-integrity) — sub-issue routed to `ci-workflows`/`standards`: local lane must invoke
   the same owned source (pointer-not-copy), which needs a small distribution decision those
   repos own.

### Constraints

- Plugin philosophy governs: repo/user/machine/org-agnostic, two-lane convention posture,
  native-first, cross-platform (Windows/macOS/Linux), setup contract, graceful degradation.
- Lane rule (locked): fast (<~2s), per-file, auto-fixing, consumer-config-discovering tool =
  hook plugin; slow / repo-wide / package-scope tool = toolchain batch entry; both when both fit.
- Hooks auto-fix silently, never block, surface only residual unfixables (markdown-format
  pattern); hook-precision convention bounds false-positive noise.
- New plugins conform to the setup-lifecycle convention once that epic lands.

### Acceptance criteria

- Each epic sub-item lands as its own planned change with the normal pipeline
  (explore/research → plan → implement → review).
- typos + Go hook plugins pass the plugin contract gate and fleet conformance audit.
- Batch additions (go, lychee-offline, pyright, dotnet guard) are rung-4 defaults only —
  consumer `.claude/ecosystems/*.yaml` override ladder unchanged.
- Hook-observability convention documented as an owner doc (convention registry row) and adopted
  by every fleet hook; conformance audited.
- CI/local parity: gaps identified 2026-07-21 (Go toolchain, lychee-offline, pyright) have local
  coverage.

### Captured assumptions

- No work-machine tool-install restriction (winget/brew acceptable). User to correct if wrong.
- Single Go repo today (`ci-runner`); Go hook plugin justified by completeness preference
  (user choice) despite one consumer.

### Out of scope

- Standards distribution-model redesign — model is settled (ADR-0001, accepted 2026-07-10);
  dissatisfaction, if it persists after reading the ADR rationale, is an ADR-supersede
  discussion in `standards`.
- Consumer-config adoption gaps (ruff/pyright targets, dotnet-analysis to itinerary-planner /
  medley, TS/JS component admission, medley lychee) — standards epic below.
- Setup-lifecycle convention design — own epic below.

### Deferred questions

- YAML lint/format plugin — arbiter: USER-RESERVED. Trigger: a CI YAML gate lands in the fleet,
  or Biome ships YAML support (unshipped as of the 2026 roadmap). Facts: yamllint validate-only;
  yamlfmt autofixes but imposes defaults without consumer config.
- gitleaks per-edit hook — arbiter: USER-RESERVED. Trigger: a local leaked-secret incident.
  Facts: `dir` mode (detect/protect deprecated v8.19), entropy false-positive noise, no autofix.
- `dotnet format whitespace --folder` fast path — arbiter: USER-RESERVED. Whitespace-only today
  (bypasses MSBuild/restore; the only sub-2s path — full/style/analyzer modes pay project-load,
  ~1.3s minimum single file). Links: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-format,
  https://github.com/dotnet/format/issues/757. Trigger: an MSBuild-free style/analyzer path
  appears upstream.
- Upstream feature request for native verbose-hooks UI — arbiter: /planning:plan (optional
  sub-item of the observability convention).

### Related epics (owned elsewhere)

- **Setup-lifecycle convention** (this repo, own design session): verb set
  (`remove`/`reset`/`migrate` vs state-assessing `apply`), per-skill setup action vs plugin
  setup skill, philosophy-doc update, fleet conformance.
- **Standards adoption sweep + ecosystem-declaration enhancement**
  (`melodic-software/standards`): distribute existing components to missing targets; add a
  consumer ecosystem/language-declaration concept (absent today — targets are hand-curated
  manifest lists).

## Plan

(Empty — `/planning:plan` fills this per epic sub-item.)
