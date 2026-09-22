# Fork comparison

Two OptiScaler forks carry the DLSS 5 Neural Rendering pass. Upstream OptiScaler has not merged it
(`reference/upstream-watch.md`). The script pins one release of each, and `-Build` picks between
them.

## Pinned releases

| | `dagherbou` (default) | `wilsjo2` |
|---|---|---|
| Repo | `Dagherbou/OptiScaler_DLSSNR` | `wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass` |
| Tag | `v0.2.0-patch1` | `v0.8.3` |
| Prerelease | **Yes** | No |
| Asset | `OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip` | `OptiScaler-NR-v0.8.3.zip` |
| URL | `https://github.com/Dagherbou/OptiScaler_DLSSNR/releases/download/v0.2.0-patch1/OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip` | `https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases/download/v0.8.3/OptiScaler-NR-v0.8.3.zip` |
| SHA-256 | `5DB547216FA8A7DBD8AB0A193DA1E3BCE0EA4BD71F91189AFA4ED2EDE8BB9561` | `3F2D26FB136D964A394BF50896D082156173153A2A55B88E1995277B4DABE3C8` |
| Hash attestation | **Local copy only.** The release publishes no checksum, so the pin is the hash of a copy downloaded and used on the proving-ground machine | **Upstream.** Matches the release's own `OptiScaler-NR-v0.8.3.zip.sha256` sidecar byte for byte |
| Extracted into `builds\` | `OptiScaler.dll`, `OptiScaler.ini`, `OptiScaler\`, `Licenses\`, `nvngx.dll_dlssnr.dll` | `OptiScaler.dll`, `OptiScaler.ini`, `OptiScaler\`, `Licenses\` |
| Runtime forwarder | Ships `nvngx.dll_dlssnr.dll`, because the runtime refuses callers whose path lacks `nvngx.dll` | None since v0.8.1; dispatches through the installed NGX driver |
| `OptiScaler.dll` signed | No | No |

`provision` downloads the asset by that URL, refuses it on a hash mismatch, and extracts only the
listed entries. It never extracts `setup_windows.bat`, `setup_linux.sh`, the README family,
`docs\`, `tests\`, `images\`, `LICENSE`, `SHA256SUMS.txt`, or the zero-byte
`!! EXTRACT ALL FILES TO GAME FOLDER !!` marker, so `builds\` never holds the interactive installer.

**The Dagherbou pin is a prerelease.** GitHub's "Latest release" and `releases/latest` skip it and
resolve to `v0.2.0-dlssnr`, an older release carrying `OptiScaler-DLSSNR-v0.2.0.zip`. That asset
lacks the Onimusha fix. Any tooling that resolves "latest" gets the wrong build; take the pinned
asset by name.

## Why Dagherbou is the default

- It is live-verified: applied with this plugin's script and confirmed running (`DLSS-NR cost` log
  lines) in Cyberpunk 2077 and Dying Light: The Beast on an RTX 5090 with driver 616.92.
- It is frozen, so its footprint is fully known: the runtime writes are audited in
  `reference/reversal-matrix.md`.
- DLSS 5 Swapper pins this exact asset by URL and SHA-256, which makes it the most exercised single
  build.

Against it:

- The author announced a hiatus on 2026-09-05 (Discussion #28). No commit has landed since, and the
  open issues get no answers.
- Issue #43: a regression introduced by patch1 on the Vulkan interop path (0.1.1.5 works, patch1
  crashes on save load). It does not bind DX12 titles, and it will not be fixed.

## When to use wilsjo2

It is the maintained line: rebased onto current OptiScaler, releasing near daily, and the author of
the open upstream merge PR. Switch when a Dagherbou bug bites a title, or when a title needs a fix
only wilsjo2 carries. The research verifier ranked wilsjo2 `v0.8.3` first on maintenance grounds;
the user chose Dagherbou for its live verification, and the choice stays open.

Against it: almost every tag is a prerelease with self-declared limits ("no new full game-session
validation ... is claimed"). Profiles (from v0.8.5) add a new runtime write,
`OptiScalerProfiles\`, which `remove` handles as a byproduct.

To switch a game: `remove`, then provision the other build with
`-Verb provision -Build wilsjo2` (same `-DataDir`), then `apply -Build wilsjo2`.

## Packages not to use

| Package | Why |
|---|---|
| `ShyVortex/dlss-unlocked` tag `v0.2.0-patch2` | Not a Dagherbou release: a repackaging of patch1 by a downstream packager. Its package also ships registry override scripts |
| `NODIX-TECH/DLSS-5-MANAGER` | 451 MB obfuscated release, payload not in source, phones home with a machine GUID hash |
| `DLSS5-Universal` repos, dlss5.net, dlss5mod.com, dlss5swapper.org | Byte-identical repos created within seconds across unrelated accounts: lookalike bait |
| Any bundle that includes `nvngx_dlssnr.dll` | The runtime is NVIDIA's; a bundled copy has undisclosed origin. The plugin takes it only from the sources `/gaming:setup` documents |

## Verification record

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| `v0.2.0-patch1` is Dagherbou's newest release and is a prerelease | `gh api repos/Dagherbou/OptiScaler_DLSSNR/releases` | 2026-09-22 | A new Dagherbou tag |
| `v0.8.3` is wilsjo2's newest non-prerelease; prereleases run to `v0.8.8` | `gh api repos/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases` | 2026-09-22 | wilsjo2 marks a newer tag non-prerelease |
| Both pinned hashes | `Get-FileHash` over the downloaded assets; the wilsjo2 `.sha256` sidecar | 2026-09-21 | `provision` reports a hash mismatch |
| Neither fork's `OptiScaler.dll` is signed; upstream v0.9.4 is SignPath-signed | `Get-AuthenticodeSignature` over the extracted files | 2026-09-20 | Either fork ships a signed build |
