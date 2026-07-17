# Discovery guide

Skill is not a static checklist. Every run, orchestrator performs a short **discovery pass** to notice new host subsystems and propose coverage. Without this, the skill rots — workstations accumulate tools, SDKs, containers over time, and a check catalog frozen in month 1 becomes meaningless by month 12.

Describes what discovery does, what counts as "straightforward" vs "needs approval", how the skill modifies its own catalog, and directions to consider per OS.

## What discovery does each run

1. **Inventory OS-specific subsystems.** Run a short set of read-only probes (see OS-specific sections below) to list installed subsystems, package managers, container engines, IDE generations, etc.
2. **Diff against the catalog.** Compare inventory to `catalog/checks.jsonc` entries for this OS. Identify subsystems with no corresponding check.
3. **Propose 1–3 new checks.** Cap at three per run to avoid floods. Prioritize: (a) subsystems with a trend angle (disk usage, version skew), (b) security-relevant subsystems (cert expiry, TPM/BitLocker), (c) noisy-in-event-log subsystems not covered.
4. **Classify each proposal.** Straightforward vs needs approval (see next section).
5. **Implement straightforward proposals immediately.** Write the new check script, add a catalog entry; check runs next week. No human in the loop.
6. **Queue non-straightforward proposals in `TODO.md`.** Human approval required.
7. **Surface both kinds** in the report under "Newly discovered checks" with rationale.

## Straightforward vs. needs approval

A proposal is **straightforward** when *all* of these hold:

- **Read-only.** Only calls cmdlets/CLIs inspecting state. No writes, no service restarts, no temp file generation beyond PowerShell's normal pipeline handling.
- **No new permissions.** Runs fine non-elevated, or clearly degrades to `UNKNOWN` with `needs_admin: true` without prompting.
- **No new egress.** Either no network calls, or only to URLs already on the egress allowlist (Microsoft Update, winget sources, CISA KEV).
- **No parsing risk.** If check depends on vendor CLI output, either CLI emits structured JSON or the parser is trivial. "Fragile regex against English prose" does not qualify.
- **Narrow scope.** One metric, one category. Don't pack five unrelated signals into one check.
- **Schema-compliant.** Emits the `CheckResult` schema from `output-schema.md`.

Anything else — new egress, required elevation, complex parsing, proposed remediations, writes of any kind — lands in `TODO.md`. Human approves by editing the checkbox in `TODO.md` to `[x]`; next run picks it up and moves the entry into the catalog.

## How the skill modifies itself

**Adding a check:**

1. Create `scripts/<os>/checks/Test-<Thing>.ps1`. Use an existing check as template. Emit via `Write-HealthResult.ps1`.
2. Append to `catalog/checks.jsonc` with `added_on: <run_id_date>`, `crash_count: 0`, `identical_streak: 0`.
3. Note the addition in this run's report under "Newly discovered checks" with one-line rationale.

**Deprecating a check** (never silent removal):

1. Set `"deprecated": true`, `"deprecation_reason": "..."`, `"deprecated_on": "<run_id_date>"` on the catalog entry.
2. Leave the script file in place — catalog entry is source of truth for what runs.
3. Surface the deprecation in the report once; subsequent runs skip the entry.

**Proposing removal** of a deprecated check:

- After **3 consecutive crashes** (`crash_count: 3`), propose removal in `TODO.md`. Human decides whether to delete script + catalog entry or keep for investigation.

**Proposing demotion** of a chronically quiet check:

- After **4 consecutive identical outputs** (`identical_streak: 4`), propose in `TODO.md` that the check move to monthly cadence. Cadence changes never applied automatically — only the human redefines "how often."

**Never** rewrite `state/history.jsonl`. If historical data was wrong, add a correction entry; don't mutate old lines.

## Candidate directions per OS

Discovery dimensions to probe. Not all apply on every host — the point is to notice *which apply* and propose coverage.

### Windows

Seed the inventory pass with these dimensions. For each, discovery determines presence via a read-only probe and, if present-but-not-in-catalog, considers a check proposal.

- **Hyper-V and WSL distros.** Presence: `Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online` (needs admin — probe gracefully), `wsl --list --verbose`. Proposed check: per-distro update status (`wsl -d <distro> -- cat /etc/os-release` + vendor EOL lookup if allowlisted).
- **Docker Desktop image disk usage.** Presence: `docker --version`. Proposed check: `docker system df --format json` → flag WARN if images + volumes exceed a user-set threshold (default 50 GB).
- **Dev-tool version skew.** Presence: VS via `Get-ItemProperty HKLM:\SOFTWARE\Microsoft\VisualStudio\Setup\*`, VS Code via `code --version` if on PATH, SSMS via registry, Rider via `%LOCALAPPDATA%\JetBrains\Toolbox\apps`, .NET SDKs via `dotnet --list-sdks`, Node via `fnm ls` or `node --version`. Proposed checks: per-tool "behind latest LTS by ≥N minor versions" severity.
- **Domain secure channel.** Presence: `(Get-WmiObject Win32_ComputerSystem).PartOfDomain`. Proposed check: `Test-ComputerSecureChannel` — WARN on false.
- **TPM + BitLocker.** Presence: `Get-Tpm` (needs admin). Proposed check: TPM present/enabled/owned; BitLocker volume status. Needs admin → UNKNOWN path required.
- **Vendor health CLIs.** Presence: Dell Command Update (`dcu-cli.exe`), Lenovo System Update (`TVSU_Launcher.exe`), HP Image Assistant, Surface UEFI (`Microsoft.Surface.IT.Toolkit`). Proposed check: last known vendor health status, firmware update availability. Often needs admin.
- **SDK / runtime EOL.** Presence: `dotnet --list-sdks`, `node --version`, `python --version`. Proposed check: is this LTS, when does support end (local EOL table shipped with skill).
- **Expiring user certs.** Presence: `Get-ChildItem Cert:\CurrentUser\My`. Proposed check: WARN on any cert within 30 days of expiry, CRIT within 7.
- **Windows Terminal profile drift.** Presence: `settings.json` at `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\`. Proposed check: parse last-modified, surface if updated outside a known window (low priority — INFO at best).
- **Package manager health.** `winget source list` — WARN if sources are disabled; `choco --version` if Chocolatey is installed.

### macOS (scaffolded only)

When `references/macos/NOT_IMPLEMENTED.md` is replaced, seed the inventory pass with:

- Homebrew (`brew outdated`, `brew doctor`), Mac App Store (`mas outdated`), System Preferences update pending, FileVault status, Keychain cert expiry, Xcode command-line tools version, Gatekeeper/SIP status, `softwareupdate --list`, pmset battery, smartctl/`system_profiler SPSerialATADataType` for disk health, `log show --predicate 'eventMessage contains "panic"'` for kernel panics, Docker Desktop disk usage, Homebrew cask version skew.

### Linux (scaffolded only)

When `references/linux/NOT_IMPLEMENTED.md` is replaced, seed the inventory pass with:

- Package manager state (`apt list --upgradable`, `dnf check-update`, `pacman -Qu`), `unattended-upgrades` status, systemd unit failures (`systemctl --failed`), `journalctl -p 3 -xb` for boot-time errors, SMART via `smartctl`, `df` for filesystem usage, LUKS/dm-crypt status, `shadow` file age, kernel version vs distro current, `snap refresh --list` / `flatpak remote-ls --updates`, container engine disk usage (docker/podman), certificate expiry in `/etc/ssl/certs` + user trust store.

## What discovery is *not*

- Not a license to install things. Discovery inspects; never runs `winget install`, `brew install`, `apt install`.
- Not a generalized "security scanner." Skill covers a narrow posture (pending security updates, Defender signatures, CISA KEV apps) — does not replicate a vulnerability scanner.
- Not a replacement for operational monitoring. Machine-health looks at weekly trends on one workstation, not real-time telemetry across a fleet.
- Not a silent force. Every self-modification appears in the week's report; no change is invisible to the human.
