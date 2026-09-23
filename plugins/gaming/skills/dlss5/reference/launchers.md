# Launchers

Where the script finds each launcher's installed games, how it names the launcher of a game
directory, and which anti-cheat source covers each one. `-Verb discover` lists every discovered
game; `assess` prints `launcher`, `launcherSource` and `gameName`.

## Discovery

| Launcher | Install record the script reads | Not read |
|---|---|---|
| Steam | `HKCU\Software\Valve\Steam` `SteamPath`, then `steamapps\libraryfolders.vdf` (each library's `path`), then each library's `steamapps\appmanifest_<appid>.acf` (`name`, `installdir` under `steamapps\common`) | <!-- portability-ok: Windows paths, not a shell regex --> |
| Epic Games Launcher | `%ProgramData%\Epic\EpicGamesLauncher\Data\Manifests\*.item` JSON (`DisplayName`, `InstallLocation`), or the folder in `HKCU\Software\Epic Games\EOS` `ModSdkMetadataDir` when set; plus `%ProgramData%\Epic\UnrealEngineLauncher\LauncherInstalled.dat` (`InstallationList`) | <!-- portability-ok: Windows paths, not a shell regex --> |
| EA app | Folders under `%ProgramFiles%\EA Games` holding `__Installer\installerdata.xml` | The app's own install list (`IS` under `%ProgramData%\EA Desktop`) is AES-encrypted with a hardware-derived key, so an EA game in another library folder is found only by the marker when `assess` is pointed at it |
| Origin (legacy) | `%ProgramData%\Origin\LocalContent\**\*.mfst`, value `dipInstallPath` | |
| Battle.net | `HKLM` Uninstall entries (both registry views) whose `UninstallString` contains `Battle.net` and `--uid=`, giving `InstallLocation` and `DisplayName` | `product.db` (protobuf, and it also lists client components). The client writes no Uninstall entry for some games |
| GOG Galaxy | `HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\<id>` (`gameName`, `path`) | <!-- portability-ok: Windows registry path, not a shell regex --> |
| Ubisoft Connect | `HKLM\SOFTWARE\WOW6432Node\ubisoft\Launcher\Installs\<id>` and the 64-bit view, `InstallDir` (forward slashes) | <!-- portability-ok: Windows registry path, not a shell regex --> |
| Xbox app / Game Pass | Each fixed drive's `.GamingRoot` (magic `0x58424752`, a folder count, UTF-16 folder names), then each folder's subfolders holding `appxmanifest.xml` at their root or under `Content`; plus `<drive>\Program Files\ModifiableWindowsApps` | `.GamingRoot` is undocumented by Microsoft. When it is missing, malformed, or lists 255 or more folders, the script falls back to `<drive>\XboxGames` and says so |

Everything discovery could not read, and every record whose folder no longer exists, is listed in
`unchecked` by `discover` and in `discoveryGaps` by `assess`. A gap there can explain a launcher of `unknown`, such as a Battle.net
game with no Uninstall entry. It does not change the anti-cheat status, whose own `unchecked` list
names the anti-cheat sources that could not be read.

## Naming the launcher of a game directory

1. The deepest discovered install folder that contains the directory.
2. Otherwise a marker in the directory or an ancestor: `steamapps\common\<Game>` (Steam), <!-- portability-ok: Windows path, not a shell regex -->
   `.egstore` (Epic), `__Installer\installerdata.xml` (EA app), `goggame-*.info` (GOG Galaxy),
   `appxmanifest.xml` (Xbox app). A path under `WindowsApps` is Xbox app.
3. Otherwise `unknown`, named after the install folder. An unknown launcher is never assumed safe:
   its anti-cheat status is at best `unknown`.

## Anti-cheat source per launcher

| Launcher | Sources | Best case |
|---|---|---|
| Steam | On disk, Steam store page `anticheat_section`, AreWeAntiCheatYet by app id and name | `none-disclosed` |
| Battle.net | Always a signal (Blizzard EULA 1.C.i and 1.C.ii), plus on disk and AreWeAntiCheatYet | `signals` |
| Epic, EA app, Origin, GOG Galaxy, Ubisoft Connect, Xbox app, unknown | On disk, AreWeAntiCheatYet by name | `unknown` |

`reference/anticheat-posture.md` defines the statuses and the acknowledgement.

## Xbox app and Game Pass

- `apply` refuses a directory under `WindowsApps` before any write. Those are protected package
  folders, and a proxy DLL there is unverified.
- Everywhere else, `apply` first creates and deletes a probe file in the directory. A folder it
  cannot write refuses before the snapshot, so nothing is left half-installed.
- Game Pass installs under `XboxGames\<Title>\Content` have taken OptiScaler as a proxy DLL beside <!-- portability-ok: Windows path, not a shell regex -->
  the executable in the OptiScaler wiki's compatibility list, usually as `winmm.dll`. That list has
  per-title notes, not a general guarantee: not every Game Pass title accepts a proxy. Prefer
  `winmm.dll` when `freeProxies` lists it, and read the title's wiki row first.

## Verification record

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| Steam: `SteamPath`, `libraryfolders.vdf` `path`, `appmanifest_*.acf` `installdir` | https://github.com/erri120/GameFinder/blob/master/src/GameFinder.StoreHandlers.Steam/Services/SteamLocationFinder.cs, `.../Services/Parsers/LibraryFoldersManifestParser.cs`, `.../Services/Parsers/AppManifestParser.cs`; https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/SteamLibrary/Steam.cs | 2026-09-23 | Steam games missing from `discover` |
| Epic: `Manifests\*.item`, the `ModSdkMetadataDir` override, `LauncherInstalled.dat` | https://github.com/erri120/GameFinder/blob/master/src/GameFinder.StoreHandlers.EGS/EGSHandler.cs; https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/EpicLibrary/EpicLauncher.cs; https://github.com/derrod/legendary/blob/master/legendary/lfs/egl.py | 2026-09-23 | Epic games missing from `discover` |
| EA app: the encrypted `IS` list, per-game `__Installer\installerdata.xml` | https://github.com/erri120/GameFinder/blob/master/src/GameFinder.StoreHandlers.EADesktop/EADesktopHandler.cs; https://github.com/lutris/lutris/blob/master/lutris/services/ea_app.py | 2026-09-23 | An EA game under `%ProgramFiles%\EA Games` missing from `discover` |
| Origin: `LocalContent\**\*.mfst` `dipInstallPath` | https://github.com/erri120/GameFinder/blob/master/src/GameFinder.StoreHandlers.Origin/OriginHandler.cs | 2026-09-23 | Origin games missing from `discover` |
| Battle.net: Uninstall entries with `--uid=`; `product.db` as the fallback not read | https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/BattleNetLibrary/BattleNetLibrary.cs; https://github.com/lutris/lutris/blob/master/lutris/services/battlenet.py | 2026-09-23 | Battle.net games missing from `discover` |
| GOG: `GOG.com\Games\<id>` in the 32-bit view (`gameName`, `path`) <!-- portability-ok: Windows registry path, not a shell regex --> | https://github.com/erri120/GameFinder/blob/master/src/GameFinder.StoreHandlers.GOG/GOGHandler.cs; https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/GogLibrary/GogLibrary.cs | 2026-09-23 | GOG games missing from `discover` |
| Ubisoft: `ubisoft\Launcher\Installs\<id>` `InstallDir`, 32-bit view then 64-bit <!-- portability-ok: Windows registry path, not a shell regex --> | https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/UplayLibrary/UplayLibrary.cs (single codebase) | 2026-09-23 | Ubisoft games missing from `discover` |
| `.GamingRoot` format and the `appxmanifest.xml` layout | https://github.com/erri120/GameFinder/blob/master/src/GameFinder.StoreHandlers.Xbox/XboxHandler.cs (`ParseGamingRootFile`, `GetAppFolders`) | 2026-09-23 | `discover` reports a `.GamingRoot` parse failure on a real drive |
| `ModifiableWindowsApps` exists only for packages declaring `desktop6:MutablePackageDirectory` | https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-desktop6-mutablepackagedirectory | 2026-09-23 | The Learn page changes |
| Game Pass titles under `XboxGames` took a proxy DLL (`winmm.dll`; `d3d12.dll` for Forza Horizon 6) | https://github.com/optiscaler/OptiScaler/wiki/Compatibility-List (the Xbox and Game Pass rows) | 2026-09-23 | A Game Pass apply fails to load the proxy |
| `.egstore` (Epic) and `goggame-*.info` (GOG) folder markers | https://github.com/derrod/legendary/blob/master/legendary/core.py; https://github.com/lutris/lutris/blob/master/lutris/util/gog.py | 2026-09-23 | An Epic or GOG game reads as `unknown` |
