# Upstream watch

What `refetch` rechecks, and how. The known values live in the Upstream watch table of `LEDGER.md`
in the data directory; `refetch` diffs against that table and edits only the rows that changed,
updating each row's Checked date.

## Watch items

Every row is rechecked on each `refetch` run; the As of column is the last check that read it.

| Item | Known value | As of |
|---|---|---|
| Dagherbou fork | `v0.2.0-patch1`, prerelease, 2026-09-04; author on hiatus | 2026-09-22 |
| wilsjo2 fork | `v0.8.3` newest non-prerelease (2026-09-13); `v0.8.8` newest prerelease (2026-09-22) | 2026-09-22 |
| Runtime DLL `nvngx_dlssnr.dll` | 310.8.0.0, SHA-256 `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E`, NVIDIA-signed. A 310.8.2 is mentioned in wilsjo2's install notes, unverified | 2026-09-21 |
| GeForce driver | 616.92 WHQL, released 2026-09-09 | 2026-09-22 |
| Native DLSS 5 titles | NBA 2K27 and Onimusha: Way of the Sword, launched with driver 616.64 | 2026-09-20 |
| Upstream OptiScaler | Newest release `v0.9.4` (2026-07-18) has no Neural Rendering; merge PRs #1116 (Dagherbou) and #1158 (wilsjo2) open, unmerged | 2026-09-22 |

## Recheck commands

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
(Get-Item '<data-dir>\runtime\nvngx_dlssnr.dll').VersionInfo.FileVersion
```

Native DLSS 5 titles: read NVIDIA's GeForce news, `https://www.nvidia.com/en-us/geforce/news/`,
with WebFetch.

`gh` is needed only here. Without it, report the fork and upstream rows as unchecked, not
unchanged.

## What a change means

| Change | Consequence |
|---|---|
| New fork tag | Candidate for a new pin. A pin change is a plugin release (tag, asset and SHA-256 in the script and `reference/fork-comparison.md`), never an edit in the installed plugin |
| New runtime version | `apply` refuses it as unknown; an NVIDIA-signed copy passes only with `-AllowUnknownRuntime`, until a plugin release updates the known hash |
| New driver | Relaunch one modded game and confirm the `DLSS-NR cost` log lines before trusting the rest |
| New native DLSS 5 title | That title needs no mod. It is also a runtime source `/gaming:setup` can scan |
| Upstream merges Neural Rendering | Both forks become candidates for retirement in favor of a signed upstream build |
