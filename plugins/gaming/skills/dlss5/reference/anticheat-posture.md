# Anti-cheat posture

The mod is never installed into a game with anti-cheat. This file is the single source for the
on-disk token list: `$AntiCheatTokens` in `scripts/Invoke-Dlss5Mod.ps1` mirrors it, and the two
change together.

## Why refuse outright

The module that enters the game process is the fork's `OptiScaler.dll`, renamed to a Windows
system DLL name such as `dxgi.dll`. In both pinned forks that file is unsigned. An unsigned DLL
under a system DLL's name inside the game directory is the shape of a proxy injector, and a kernel
anti-cheat is built to find it.

Two outcomes get conflated and are not the same:

- **Blocked**: the game or its anti-cheat refuses to start with the DLL present. BattlEye's FAQ
  tells users to remove custom `d3d9.dll`, `dxgi.dll` and `dsound.dll` files when its service fails
  to start, and says blocked-file messages carry no ban risk.
- **Banned**: the account is flagged. Easy Anti-Cheat's support material says the publisher, not
  EAC, decides a suspension or ban once EAC flags an account.

No anti-cheat vendor has published a whitelist for OptiScaler. ReShade's whitelisting rests on
signed, hash-identifiable releases, a path the unsigned forks cannot take. NVIDIA's signature on
`nvngx_dlssnr.dll` does not help: that file is a model the mod loads, not the injected code.
OptiScaler's own README warns: "Do not use this mod with online games."

So the plugin refuses rather than weighing risk per title, and there is no `-Force` bypass.

## On-disk tokens

| Token | What it is | Source |
|---|---|---|
| `EasyAntiCheat` | Easy Anti-Cheat (Epic), kernel mode; its folder sits beside the game root | Steam store page for Halloween: The Game (`store.steampowered.com/app/3219630/`), "Uses Kernel Level Anti-Cheat, Easy Anti-Cheat"; local install `EasyAntiCheat/EasyAntiCheat_EOS_Setup.exe`. Research: `.work/dlss5/research/multiplayer-anticheat/RESEARCH-verdicts.md` (Halloween section), `RESEARCH-anticheat-posture.md` (Easy Anti-Cheat section) |
| `EasyAntiCheat_EOS` | The Epic Online Services variant of EAC; the Windows service and install folder name | Local `Win32_Service` `EasyAntiCheat_EOS` on a Halloween: The Game install. Research: `RESEARCH-anticheat-posture.md` (Easy Anti-Cheat section), `RESEARCH-verdicts.md` (Halloween section), `RESEARCH-evidence.md` evidence table |
| `BattlEye` | BattlEye, kernel mode; its install folder | `battleye.com/support/faq/` items 5, 6 and 11; OptiScaler wiki, GTA V Enhanced: "requires disabling Battleye". Research: `RESEARCH-anticheat-posture.md` (BattlEye section), `RESEARCH-mod-mechanics.md` (compatibility list) |
| `BEService` | BattlEye's service executable | Named as a probe target in the Ready or Not absence scan. Research: `RESEARCH-verdicts.md` (Ready or Not section), `RESEARCH-evidence.md` evidence table |
| `ACE` | Anti-Cheat Expert (Tencent) | OptiScaler wiki, Infinity Nikki: signed builds only; OptiScaler issue #848: ACE's `ACE-Setup64.exe` and `ACE-Service64.exe` crashed when a `dxgi.dll` proxy hooked them. Research: `RESEARCH-mod-mechanics.md` (compatibility list and anti-cheat processes sections) |

Research paths are relative to the repository that authored this plugin and are not shipped with
it. Every token above appears in that research; the list carries no token from judgment alone. A
token added here must be added to `$AntiCheatTokens` in the same change.

### Match rule

A file or directory matches when its name without extension equals a token, or starts with the
token followed by `_` or `-`. Matching is case-insensitive. So `EasyAntiCheat\`,
`EasyAntiCheat_EOS_Setup.exe`, `BEService_x64.exe` and ACE's `ACE-Setup64.exe` and
`ACE-Service64.exe` match, and `EOSSDK-Win64-Shipping.dll`, Epic's networking SDK, does not.

### Scan shape

`assess` and `apply` share one scan.

- Steam install (the path contains `steamapps\common\<Game>`): every item under <!-- portability-ok: Windows path, not a shell regex -->
  `steamapps\common\<Game>`, recursively, to depth 4. <!-- portability-ok: Windows path, not a shell regex -->
- Anywhere else: every item under the exe directory, recursively, to depth 4, plus the direct
  children of each of up to four parent directories, stopping above the drive root. The parents are
  not scanned recursively, so a sibling game's anti-cheat in a shared library folder does not refuse
  this one.

Anti-cheat installed deeper than that, or delivered by a launcher or a server, leaves nothing the
scan sees. That is why an `eligible` verdict carries `requiresWebCheck: true`.

## The Steam web check

Valve requires publishers to disclose kernel-level anti-cheat in the store page's anti-cheat
section. The SKILL.md reads it with curl and Steam's age-gate cookies, because WebFetch receives the
age gate on many titles and an age gate has no anti-cheat section to find. A present section
refuses. Only a confirmed store page with no section clears the check. A fetch that failed or
returned the age gate clears nothing.

## Per-title verdicts on record

| Title | Verdict | Basis | As of | Recheck trigger |
|---|---|---|---|---|
| Halloween: The Game | Refuse: kernel EAC | Steam anti-cheat section; `EasyAntiCheat/` on disk | 2026-09-20 | Never; refused while EAC ships |
| Ready or Not | No anti-cheat; eligible, provisionally | No Steam anti-cheat section; no `EasyAntiCheat/` or `BEService` on disk; VOID's FAQ: "We're currently looking into appropriate Anti-Cheat solutions" | 2026-09-20 | Any major game update: rerun `assess` and the Steam check |
| World of Warcraft | Do not install | No DLSS for the mod to intercept; Blizzard's Terms of Use prohibit unauthorized third-party code, and patch 11.1.7.61965 blocked a `dxgi.dll` proxy | 2026-09-20 | Never, unless WoW adds DLSS |
