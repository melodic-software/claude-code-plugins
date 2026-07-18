# machine-health — developer notes

Implements the `machine-health` Claude Code skill. `SKILL.md` is the runtime entry point Claude reads; this file is for humans maintaining the skill.

## What's here

```
machine-health/
├── SKILL.md                       # runtime entry; seam resolution + OS routing + procedure
├── README.md                      # this file
├── TODO.md                        # approval policy documentation (holds no state)
├── catalog/
│   ├── checks.jsonc               # OS-tagged, versioned check registry (read-only at runtime)
│   └── cisa-kev.json              # seed stub; live cache refreshes under %LOCALAPPDATA%
├── references/
│   ├── shared/                    # OS-agnostic semantics (severity, schema, report, discovery, philosophy, overlay)
│   ├── windows/                   # Windows-specific check catalog + remediation policy
│   ├── macos/NOT_IMPLEMENTED.md   # porting stub
│   └── linux/NOT_IMPLEMENTED.md   # porting stub
├── scripts/
│   ├── windows/                   # orchestrator, checks, remediations, lib helpers
│   ├── macos/NOT_IMPLEMENTED.md   # porting stub
│   └── linux/NOT_IMPLEMENTED.md   # porting stub
└── tests/                         # Pester 5.7+ suite (Windows-only) + runner
```

## Separation of semantics from implementation

- `references/shared/` — *what* health means: severity levels, result schema, report template, discovery procedure, remediation philosophy, catalog-overlay semantics.
- `references/<os>/` — *how* to detect it on that OS: cmdlets, registry paths, service models, thresholds.
- `scripts/<os>/` — executable implementation emitting the shared schema.

Adding a new OS should be "populate two folders," not "refactor the skill." If a change feels OS-agnostic but lives under `references/windows/`, it likely belongs in `references/shared/`.

## Dual-invocation scripts

Every check script runs two ways:

- **By Claude** — emits a single JSON object on stdout conforming to the check-result schema (`references/shared/output-schema.md`).
- **By a human** — pass `-Human` for readable output. Use `Write-Host` in that mode so structured emitters still work over pipelines.

Human-mode output is the on-ramp for debugging a misbehaving check; keep it readable.

## Stateless checks, stateful orchestrator

- **Checks** take a current reading and return it. They do not read `history.jsonl` directly; the orchestrator hands them a slice over stdin.
- **Orchestrator** (`Invoke-MachineHealthCheck.ps1`) owns: state-root resolution, catalog + overlay merge, history loading, trend computation, severity adjustment, timeouts, remediation sequencing, report rendering, and `state/history.jsonl` append.

Keeps individual checks small, trend logic in one place.

## Running manually

From a clone of this marketplace repository:

```powershell
# Dry run into a scratch folder (safe — no remediations, no user-profile pollution)
& "plugins\machine-health\skills\audit\scripts\windows\Invoke-MachineHealthCheck.ps1" `
    -OutputBase "$env:TEMP\machine-health-scratch" -RunMode first-run -DryRun
```

Without `-StateBase`, state and logs land under the output base (or `CLAUDE_PLUGIN_DATA` when that
environment variable is set). A single check can run in isolation:

```powershell
& "plugins\machine-health\skills\audit\scripts\windows\checks\Test-DiskHealth.ps1" -Human
```

## Extending the skill

1. New Windows check (shipped): write `scripts/windows/checks/Test-<Thing>.ps1` emitting the shared schema, add an entry to `catalog/checks.jsonc` with `os: ["windows"]`, document thresholds in `references/windows/check-catalog.md`, and bump the plugin version.
2. Machine-local custom check (consumer-side): see `references/shared/catalog-overlay.md` — script under the state base, entry in `checks.local.jsonc`, no plugin change.
3. New remediation: write `scripts/windows/remediations/<Verb>-<Noun>.ps1`, add it to the authorization list in `references/windows/remediation-policy.md`, and wire dispatch in the orchestrator. Remediations always default to not approved.
4. New OS: replace the matching `NOT_IMPLEMENTED.md` with a populated folder. Consult `references/shared/discovery-guide.md` for the porting checklist.

## Guardrails codified in the skill

See `SKILL.md` § Guardrails. Briefly: 15m total, 90s per check, no interactive prompts, no retries, first-run dry mode, admin never assumed, egress allowlist, no `Invoke-Expression` on external data, never write into the plugin install directory.
