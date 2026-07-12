# kindle-dedrm

A Claude Code plugin that manages the fragile, multi-tool workflow for
removing DRM from Kindle books **you own** so they are readable on non-Kindle
devices — Kindle for PC 2.8.0 pinned against auto-update, Calibre with the KFX
Input and DeDRM plugins, and the Kindle_Key_Finder tool. It captures the
lifecycle as discrete **reversible actions**, each state mutation paired with a
documented compensating reversal, and tracks every upstream source that drifts
independently.

Invoke it with `/kindle-dedrm:kindle-dedrm` and an optional action.

## ⚠️ Personal-use DRM removal — read first

This plugin exists to make **books you have purchased and own** readable on your
own devices. The legality of circumventing technological protection measures
varies by jurisdiction (in the U.S., see 17 U.S.C. § 1201 and the Librarian of
Congress's triennial exemptions); **you own the decision** for your own use.
The plugin never distributes anything: extracted keys, decrypted EPUBs, and the
scripts stay on your machine, and the hard safety rules forbid sending any of
them off-machine. It does not touch books you do not own — it only processes
content Kindle has already downloaded into your own `My Kindle Content` folder.
This is a caution, not legal advice.

## ⚠️ Private marketplace only — carve out before publishing

`melodic-software/claude-code-plugins` is a **private** marketplace. This plugin
is intentionally its own unit (not bundled into `knowledge`) because
plugin-level enablement is all-or-nothing and this carries a different risk
profile than the other knowledge tooling. **If this marketplace is ever made
public, carve this plugin out first** — remove its `marketplace.json` entry (or
relocate it to a separate private marketplace) so a personal-use DRM-removal
workflow is not published to a general audience.

## ⚠️ Windows only

Kindle for PC and the KFXKeyExtractor / KFXArchiver binaries are Windows-only
(hard-coded memory offsets). The scripts invoke PowerShell and rely on Windows
environment variables (`%LOCALAPPDATA%`, `%APPDATA%`, `%USERPROFILE%`) via Git
Bash. There is no macOS or Linux path — the skill states this and does not fake
support on other operating systems.

## Actions

| Action | What it does |
|---|---|
| (empty) / `status` | Probe current state and recommend the fitting action, or emit a diagnostic report |
| `setup` | First-time provisioning: download + install Kindle for PC 2.8.0, sign-in checkpoint, sync books, install Calibre plugins, run keyfinder, apply firewall block + ICACLS update lock |
| `sync` | Re-process books purchased after setup: disable firewall, sync in Kindle, delete any staged installer, re-enable firewall, re-run keyfinder |
| `update` | Drift check (no mutations) against captured upstream baselines — version pins, tutorial URLs, supported-version matrix |
| `cleanup` | Reverse every mutation with per-item confirmation. `--soft` keeps Kindle for PC + Calibre + Library; `--full` also offers to uninstall Kindle for PC and remove Calibre plugins |

Flags: `--dry-run` (preview sync), `--soft` / `--full` (cleanup depth).

Every mutation the plugin makes has an entry in the skill's reversal matrix, and
the user's decrypted Calibre Library is **never** auto-deleted — those are the
books the whole workflow exists to produce.

## How it works

The skill probes machine state on every invocation (`scripts/status.sh`, a
read-only JSON reporter) and routes to the matching action. The core hazard it
manages is Amazon's aggressive 2.9.x auto-update, which breaks key extraction: a
Windows Firewall rule plus an ICACLS deny on the update directory pin Kindle for
PC at 2.8.0, and `sync` opens a tightly-scoped window to fetch new books and
immediately re-locks. Upstream sources that drift independently (the pinned S3
installer URL, the Satsuoni DeDRM_tools fork, the rolling-date keyfinder zip, the
tutorial article) are tracked with captured baselines the `update` action diffs
against.

## Requirements

- **Windows** with Git Bash (for the `.sh` helpers) and PowerShell.
- **Calibre** installed, plus **Python 3.6+** on PATH (not the WindowsApps stub).
- **Admin rights** for the firewall + ICACLS lockdown steps.
- Books already purchased and downloaded through Kindle for PC.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install kindle-dedrm@melodic-software
```

## Configuration

This plugin has no `userConfig`. It is machine-scoped and single-user — every
path is derived at runtime from the operating system's own environment variables,
and there is nothing repo- or consumer-specific to configure. The `setup` action
is a provisioning walkthrough, not a config writer.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
