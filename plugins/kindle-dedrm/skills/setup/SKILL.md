---
name: setup
description: "Verify and provision the Kindle for PC 2.8.0 + Calibre DeDRM workflow (Windows only, personal-use, books you own). check probes prerequisites and current state read-only (Calibre, Python, pwsh, admin, Kindle version, firewall/ICACLS lock, downloads, plugins) via the plugin's own status script; apply runs the first-time provisioning walkthrough — the gated artifact download, install, firewall block, ICACLS lock, Calibre plugins, and keyfinder. Use when: 'set up Kindle DRM removal', 'is my DeDRM setup ready', 'provision kindle-dedrm', 'download DeDRM tools', 'check DeDRM prerequisites'. Re-runnable and safe."
argument-hint: "check | apply [download]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and provision the first-time DeDRM setup. `check` inspects prerequisites and current state
read-only; `apply` runs the provisioning walkthrough (the router skill's workflow reference), then re-runs `check`.
No argument or `check` runs the check; `apply` runs the check first, then provisioning; `apply download`
runs only the gated artifact-download subaction. This plugin has no repo- or consumer-scoped
configuration and no `userConfig` scalars/toggles — setup writes no Claude Code user settings, no
`pluginConfigs`, and nothing into the plugin cache or plugin data directory; it provisions the user's
machine (installs, firewall rule, ICACLS lock, extracted keys) and every mutation has a compensating
reversal under `/kindle-dedrm:manage cleanup`.

Scope and the hard safety rules are the router skill's: read
[`${CLAUDE_PLUGIN_ROOT}/skills/manage/SKILL.md`](${CLAUDE_PLUGIN_ROOT}/skills/manage/SKILL.md)
"Hard safety rules" before any `apply` — they apply here unchanged (never open Kindle with the firewall
down except during an active sync; never run the cached auto-update installer; never send keys or
extracted files off the machine).

## Interactivity

Much of provisioning is irreducibly interactive — the installer's UAC + EULA, the Amazon sign-in race
window, the Calibre plugin GUI loads, and the keyfinder VBS are actions on the user's machine the agent
physically cannot drive. `apply` keeps these as **user-action hand-offs** (hand the user the exact step,
wait for confirmation at each CHECKPOINT), not interview prompts — there are no configuration decisions
to interview for. The parts that genuinely automate — artifact download + SHA verification, the firewall
rule, the ICACLS lock — run non-interactively.

## `check` (read-only)

The status script
(`${CLAUDE_PLUGIN_ROOT}/skills/manage/scripts/status.sh`) is the source of truth for current
state — run it and read its JSON before reporting. Add the prerequisite probes the pre-flight table in
the workflow reference (`${CLAUDE_PLUGIN_ROOT}/skills/manage/references/workflow.md`)
requires. Report a PASS/FAIL/INFO table with one remediation per FAIL; modify
nothing, download nothing, extract nothing.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/manage/scripts/status.sh"
```

1. **Hard prerequisites** — FAIL when absent: Calibre installed (any recent version); Python 3.6+ on
   PATH and **not** the Windows Store `WindowsApps` stub; `pwsh` available; admin rights available.
   These are true prerequisites, not opt-in state.
2. **Kindle for PC version** — installed and **not** `2.8.0.70980` is FAIL (the user must uninstall it
   first — the skill never auto-uninstalls; see
   `${CLAUDE_PLUGIN_ROOT}/skills/manage/references/troubleshooting.md`). Absent is INFO (not
   yet provisioned — `apply` installs it). Exactly `2.8.0.70980` is PASS.
3. **Provisioning state** — firewall rule, ICACLS deny, `~/Tools/Kindle_Key_Finder`, and the three
   `~/Downloads` artifacts. Before first setup these are legitimately absent → INFO ("not yet
   provisioned; run `apply`"), not FAIL.
4. **Cached auto-update installer** — `status.sh`'s `cached_installer` present is FAIL: it is the
   auto-update payload that breaks key extraction; remediation is
   `${CLAUDE_PLUGIN_ROOT}/skills/manage/scripts/lock-updates.sh apply` /
   `${CLAUDE_PLUGIN_ROOT}/skills/manage/scripts/sync-finalize.sh delete-cache` (never run it).
5. **Calibre plugins and books** — INFO: report `calibre_plugins` (KFX Input, DeDRM, `dedrm.json`
   presence) and the `books` synced/converted counts. Report the key store `dedrm.json` presence-only —
   never print its contents (it holds extracted keys).

## `apply` (idempotent)

Run `check`, then provision. `apply` walks the full first-time sequence; `apply download` runs only the
gated download subaction. Every step's exact command, rationale, and verification live in
[`${CLAUDE_PLUGIN_ROOT}/skills/manage/references/workflow.md`](${CLAUDE_PLUGIN_ROOT}/skills/manage/references/workflow.md) — **follow
it there; do not restate it here** (that keeps the download flow's pinned-tag fallback and the
Key_Finder URL empty-match guard authoritative in one place). Pause at every CHECKPOINT for user
confirmation.

- **`apply download`** — Step 1 of the workflow reference: download the three artifacts to
  `~/Downloads` and SHA256-verify them against the versions reference
  (`${CLAUDE_PLUGIN_ROOT}/skills/manage/references/versions.md`). The DeDRM_tools tag resolves
  dynamically via the authenticated `gh` CLI and **falls back to the pinned tag in the versions
  reference** when `gh` is unavailable or returns nothing; the guard refuses to compose a URL with the
  placeholder still in place. The Key_Finder zip URL resolves from the tutorial article and **stops with
  the mirror-procedure pointer on an empty match**. On a SHA mismatch, stop and re-fetch.
- **Full `apply`** — Steps 1–9 of the workflow reference: download (as above) → extract → user runs
  the installer (UAC/EULA hand-off, CHECKPOINT) → sign-in race window (CHECKPOINT) → verify books on
  disk → firewall block (`${CLAUDE_PLUGIN_ROOT}/skills/manage/scripts/firewall.ps1 enable`) →
  delete cached installer + ICACLS deny
  (`${CLAUDE_PLUGIN_ROOT}/skills/manage/scripts/lock-updates.sh apply`) → Calibre plugin loads
  (GUI hand-off, CHECKPOINT) → run keyfinder (VBS hand-off, CHECKPOINT) → verify EPUBs.
- **Verify after each remediation** — after each automated mutation re-run the relevant `status.sh`
  probe (firewall rule enabled, ICACLS `LOCK OK`, downloads `3/3`, Kindle version `2.8.0.70980`) and
  report its actual result; never claim a step succeeded on a command's exit code alone.

Re-running `apply` when `check` already passes changes nothing new — the download, extraction, firewall,
and lock steps are idempotent — and reports "already provisioned".

## What this skill does NOT do

- Run `sync`, `update`, `cleanup`, or `status` — those stay on the router skill
  (`/kindle-dedrm:manage`); `check` here is the read-only state report, `apply` is first-time provisioning.
- Write Claude Code user settings, `pluginConfigs`, the plugin cache, or the plugin data directory.
- Send any script, key, or extracted file off the user's machine — personal-use scope only.
- Auto-uninstall a wrong Kindle for PC version or run the cached auto-update installer.
