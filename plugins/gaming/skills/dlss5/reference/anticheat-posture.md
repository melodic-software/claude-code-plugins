# Anti-cheat posture

`apply` refuses a game with any anti-cheat signal, or whose anti-cheat status is unknown, unless
the user acknowledges the risk by typing the game's name. The acknowledgement comes after the
router has shown every signal and every unchecked source and has run live research for reported
bans and blocks. Installing is then at the user's own risk. The plugin never disables, bypasses,
deletes or tampers with any anti-cheat, and never suggests doing so. It installs the mod beside the
anti-cheat, unchanged.

This file is the single source for the on-disk token list: `$AntiCheatTokens` in
`scripts/Invoke-Dlss5Mod.ps1` mirrors it, and the two change together.

## Why the risk is real

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

The research the router runs before asking reports which of the two users have hit for the title.

No anti-cheat vendor has published a whitelist for OptiScaler. ReShade's whitelisting rests on
signed, hash-identifiable releases, a path the unsigned forks cannot take. NVIDIA's signature on
`nvngx_dlssnr.dll` does not help: that file is a model the mod loads, not the injected code.
OptiScaler's own installation guide warns: "Do not use this mod with online games. It may trigger
anti-cheat software and cause bans!"

## Status

`assess` and `apply` compute one status from every source below.

| Status | Meaning | `apply` |
|---|---|---|
| `signals` | At least one source names anti-cheat | Refuses unless acknowledged |
| `unknown` | No source named one, but a source could not be read, or the launcher has no first-party disclosure | Refuses unless acknowledged |
| `none-disclosed` | Steam only: nothing on disk, an AreWeAntiCheatYet entry under the game's Steam app id whose `anticheats` list is empty, and a confirmed store page with no anti-cheat section | Proceeds with the normal per-game confirmation |

None of the three means "no anti-cheat". `none-disclosed` means no kernel-mode anti-cheat was
disclosed and no community record lists one. Every launcher other than Steam tops out at `unknown`.

## Acknowledgement

`apply -AcceptAntiCheatRisk '<game name>'` must match the `gameName` that `assess` printed. The
comparison ignores case, spaces, punctuation and the ™, ® and ’ glyphs, so a user can type the
name on a plain keyboard. `apply` also requires `-AntiCheatResearch` (the research summary) and at
least one `https://` URL in `-AntiCheatSources`. The acknowledgement is bound to what the user
reviewed: `-AntiCheatReviewId` carries `antiCheat.reviewId` from that `assess`, a hash of the
game (its folder, launcher and Steam app id), the status, the signals and the names of the sources
that could not be checked, and `apply` refuses when its own reread of the sources gives another id. A
missing, mismatched or stale acknowledgement, or one without research, refuses before any write.

The manifest records the typed name, the date, the research summary and its sources, the status,
every signal and unchecked source, the AreWeAntiCheatYet commit SHA, and the Steam store read. The
ledger row repeats them.

`-Force` lifts only the over-2000-files guard and has no effect on this gate. A different proxy
name is not a way past it either: the gate does not look at the proxy.

## Sources

| Source | What it says | What it cannot say |
|---|---|---|
| On-disk tokens (below) | A known anti-cheat file or folder sits in or near the game | Anything about server-side or launcher-delivered anti-cheat, which leave nothing to find |
| Steam store page, `anticheat_section` | The publisher disclosed anti-cheat. The script reads the page with Steam's age-gate cookies and records the `anticheat_name` entries | Valve requires the field only for client-side kernel-mode anti-cheat; for anything else it is optional. A missing section means no kernel anti-cheat was disclosed. An age gate, a failed fetch, or a page without the app name is `unknown` |
| AreWeAntiCheatYet `games.json` | A community record (MIT, contributions need "a reputable source") lists the title's anti-cheat in `anticheats`. Fetched live at every `assess` and `apply`, pinned to the commit SHA it read, matched by Steam app id or by normalized name | No entry is not a clean result. A name match can raise a signal, but a Steam game counts as recorded only under its own app id. The `status` field describes Linux and Proton support, not whether a game has anti-cheat, so it is ignored. A fetch failure is `unknown`, never clean |
| Battle.net launcher | Every Battle.net title is a signal, on the EULA text below | Nothing per title: the signal is the publisher's terms, not a detected anti-cheat |
| Epic, EA app, Origin, GOG Galaxy, Ubisoft Connect, Xbox app | No first-party per-game anti-cheat disclosure exists, so these titles are at best `unknown` | |

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Epic exposes no per-game anti-cheat field | `curl https://store-content-ipv4.ak.epicgames.com/api/en-US/content/products/fortnite` (an Easy Anti-Cheat title): HTTP 200 and no `anti-cheat` or `kernel` key. Checked on one title only | 2026-09-23 | Epic adds an anti-cheat field to its store pages or API |
| EA app, Origin, GOG Galaxy, Ubisoft Connect and Xbox app expose no per-game anti-cheat field | Absence of evidence: the launcher research on this date found none in their client data or store pages. EA publishes a count of Javelin titles (https://www.ea.com/news/ea-javelin-anticheat-2026-update), not a per-game field | 2026-09-23 | Any of them publishes a per-game anti-cheat disclosure |

Either row being wrong only makes the plugin stricter than it needs to be: a launcher with no source reads `unknown`, which asks for an acknowledgement.

EA's kernel-level EA Javelin Anticheat reaches the status through AreWeAntiCheatYet's `EA
anticheat` entries. EA publishes a count of protected titles, not a list, so the plugin keeps no
hard-coded Javelin list.

PCGamingWiki pages carry an "Anti-cheat" row, and the router links the title's page for the user to
read. The plugin never queries it from a script: its Cargo API refuses anonymous queries, and its
export route sits behind a Cloudflare challenge.

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| PCGamingWiki's anonymous Cargo query returns `permissiondenied`, and `Special:CargoExport` answers HTTP 403 with a Cloudflare challenge | `curl` of `https://www.pcgamingwiki.com/w/api.php?action=cargoquery&tables=Infobox_game...` (error text `permissiondenied`) and of `Special:CargoExport` (HTTP 403, `_cf_chl_opt` in the body) | 2026-09-23 | PCGamingWiki documents a public API, or a plain `curl` of either route returns data |

## Blizzard EULA

Battle.net titles are a signal because of the Blizzard End User License Agreement (revised March
21, 2024), section 1.C, "License Limitations". Under it, "You agree that you will not, in whole or
in part or under any circumstances, do the following:"

- **1.C.i.** "Derivative Works: Copy or reproduce (except as provided in Section 1.B.), translate,
  reverse engineer, derive source code from, modify, disassemble, decompile, or create derivative
  works based on or related to the Platform."
- **1.C.ii.** "Cheating: Create, use, offer, promote, advertise, make available and/or distribute
  the following or assist therein: cheats; i.e. methods not expressly authorized by Blizzard
  (whether accomplished using hardware, software, a combination thereof, or otherwise), influencing
  and/or facilitating gameplay, including exploits of any in-game bugs, and thereby granting you
  and/or any other user an advantage over other players not using such methods; bots; i.e. any code
  and/or software, not expressly authorized by Blizzard, that allows the automated control of a
  Game, or any other feature of the Platform, e.g. the automated control of a character in a Game;
  hacks; i.e. accessing or modifying the software of the Platform in any manner not expressly
  authorized by Blizzard; and/or any code and/or software, not expressly authorized by Blizzard,
  that can be used in connection with the Platform and/or any component or feature thereof which
  changes and/or facilitates the gameplay or other functionality;"

Source: `https://www.blizzard.com/en-us/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/blizzard-end-user-license-agreement`.
The same section says Blizzard "may suspend or revoke your license" on a violation. Show both items
in full when a Battle.net title is acknowledged; never quote 1.C.ii without its closing qualifier.

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
token added here must be added to `$AntiCheatTokens` in the same change. A wiki note such as
"requires disabling Battleye" records what other users did; the plugin never repeats it as advice.

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
  not scanned recursively, so a sibling game's anti-cheat in a shared library folder does not flag
  this one.

A folder in the scanned game tree that cannot be listed is reported under `unchecked`, so the
status is at best `unknown`. Anti-cheat installed deeper than that, or delivered by a launcher or
a server, leaves nothing the scan sees. That is why the web sources above are read too.

## Per-title records

| Title | Status | Basis | As of | Recheck trigger |
|---|---|---|---|---|
| Halloween: The Game | `signals`: kernel EAC | Steam anti-cheat section; `EasyAntiCheat/` on disk | 2026-09-20 | While EAC ships, every `assess` reports it |
| Ready or Not | No Steam anti-cheat section; nothing on disk | No Steam anti-cheat section; no `EasyAntiCheat/` or `BEService` on disk; VOID's FAQ: "We're currently looking into appropriate Anti-Cheat solutions". AreWeAntiCheatYet was not read at that date | 2026-09-20 | Any major game update: rerun `assess` |
| World of Warcraft | `signals`: Battle.net title | Blizzard EULA 1.C.i and 1.C.ii (above); AreWeAntiCheatYet lists Warden | 2026-09-23 | A EULA revision |
