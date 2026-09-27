# Upstream watch

What `refetch` rechecks, and how. The known values live in the Upstream watch table of `LEDGER.md`
in the data directory; `refetch` diffs against that table and edits only the rows that changed,
updating each row's Checked date.

## Watch items

Every row is rechecked on each `refetch` run; the As of column is the last check that read it.

| Item | Known value | As of |
|---|---|---|
| Dagherbou fork | `v0.2.0-patch1`, prerelease, 2026-09-04; author on hiatus | 2026-09-22 |
| wilsjo2 fork | `v0.8.3` newest non-prerelease (2026-09-13), still the pin; `v0.8.91` newest prerelease (seen 2026-09-23). From `v0.8.5` each release ships one `OptiScaler-NR-<version>-SHA256SUMS.txt` instead of a per-zip `.sha256`. Issue #56 (DEVICE_HUNG, reported only on Onimusha) is open with no maintainer reply, and no release through `v0.8.91` claims a fix, so the pin does not move | 2026-09-23 |
| Runtime DLL `nvngx_dlssnr.dll` | 310.8.0.0, SHA-256 `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E`, NVIDIA-signed. A 310.8.2 is mentioned in wilsjo2's install notes, unverified | 2026-09-21 |
| GeForce driver | 616.92 WHQL, released 2026-09-09 | 2026-09-22 |
| Native DLSS 5 titles | NBA 2K27 and Onimusha: Way of the Sword, launched with driver 616.64 | 2026-09-20 |
| Upstream OptiScaler | Newest release `v0.9.4` (2026-07-18) has no Neural Rendering; merge PRs #1116 (Dagherbou) and #1158 (wilsjo2) open, unmerged | 2026-09-22 |

## Recheck commands

`-Verb refetch` runs the fork, upstream-release, driver and runtime checks below and merges the
result into `cache\upstream.json`. The commands are listed so each row can be rechecked by hand,
and for the two upstream pull requests, which `refetch` does not read.

```bash
# Dagherbou fork. Not releases/latest: it skips prereleases and returns v0.2.0-dlssnr.
gh api repos/Dagherbou/OptiScaler_DLSSNR/releases --jq '.[] | [.tag_name, .prerelease, .published_at] | @tsv'

# wilsjo2 fork
gh api repos/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases --jq '.[] | [.tag_name, .prerelease, .published_at] | @tsv'

# Upstream OptiScaler: newest release, and whether the merge PRs landed
gh api repos/optiscaler/OptiScaler/releases/latest --jq .tag_name
gh api repos/optiscaler/OptiScaler/pulls/1116 --jq '[.state, .merged] | @tsv'
gh api repos/optiscaler/OptiScaler/pulls/1158 --jq '[.state, .merged] | @tsv'

# Local driver; compare with https://www.nvidia.com/download/index.aspx
nvidia-smi --query-gpu=driver_version --format=csv,noheader
```

```powershell
# Runtime DLL version: the data directory's copy, and any installed DLSS 5 title's copy
# Numeric fields: FileVersion reads "310,8,0,0" on this DLL
$v = (Get-Item -LiteralPath '<data-dir>\runtime\nvngx_dlssnr.dll').VersionInfo; '{0}.{1}.{2}.{3}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart
```

Native DLSS 5 titles: read NVIDIA's GeForce news, `https://www.nvidia.com/en-us/geforce/news/`,
with WebFetch.

`gh` is needed only here. Without it, report the fork and upstream rows as unchecked, not
unchanged.

## What a change means

| Change | Consequence |
|---|---|
| New fork tag | Candidate for a new pin; follow Updating a pin below. A pin change is a plugin release, never an edit in the installed plugin |
| New runtime version | `apply` refuses it as unknown; an NVIDIA-signed copy passes only with `-AllowUnknownRuntime`, until a plugin release updates the known hash |
| New driver | Relaunch one modded game and confirm the `DLSS-NR cost` log lines before trusting the rest |
| New native DLSS 5 title | That title needs no mod. It is also a runtime source `/gaming:setup` can scan |
| Upstream merges Neural Rendering | Both forks become candidates for retirement in favor of a signed upstream build |

## Updating a pin

How a new fork release becomes the plugin's pin, and how each game moves to it.

1. **Detect.** `refetch` lists the new tag.
2. **Record.** An issue on this plugin's repository carries the release notes, the asset hash, and
   which games were tested live on it and with what result. A wilsjo2 release from `v0.8.5` on
   publishes its hashes in `OptiScaler-NR-<version>-SHA256SUMS.txt`; take the zip's line from it.
   Dagherbou publishes none, so its hash is a local-copy attestation.
3. **Pin.** A pull request moves the tag, asset, URL and SHA-256 in `$BuildPins` in the script and
   in `reference/fork-comparison.md`, re-verifies the `[DlssNr]` keys against the new
   `OptiScaler.ini` (`reference/presets.md`, Verification record), and updates the verification
   records.
4. **Roll out, one game at a time.**
   1. `capture` each game whose overlay tuning should survive: once the build is re-provisioned,
      `capture` and `reset` refuse on a game still on the old build.
   2. `claude plugin update` the plugin.
   3. `/gaming:setup apply` re-provisions the build. The build folder under the data directory
      changes only here, so a remove and apply before this step reinstalls the old build.
   4. For each game: `remove`, then `apply` with the same `-Build`, each with its own confirmation.

**A prerelease is never pinned without a live test**: at least one game applied from it, confirmed
running by its `DLSS-NR cost` log lines, recorded in the step 2 issue.

**Which games are behind.** Each game's manifest records `build`, `tag` and `buildSha256`. `status`
and `assess` compare them with the current pin for that build and report
`installed build is older than the current pin` for a game still on an old one; the tags compare
as versions. A newer tag (the plugin was rolled back) reads `newer than the current pin`, and the
same version under another hash reads `differs from the current pin`. A manifest written
before 0.5.0 has no tag, and reads `unknown, re-apply to record` until the game is removed and
applied again.
