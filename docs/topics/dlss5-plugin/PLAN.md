# PLAN: the `gaming` plugin and its `dlss5` router skill

## Brief

### Goal (verbatim from the handoff "Original goal")

**Goal (verbatim):**
"Is DLSS 5 avialable yet? I've seen people posting videos about it - real demos on real games..." (2026-09-20)

**Amended:** amended 2026-09-20: "Some people seem to have 'unlocked' it somehow and have applied it to other games... this is what I want to do"
amended 2026-09-20: "I want best visuals, best performance - we keep track of that, and store all this information, refetch periodically (possible skill candidate? idk) - maybe claude-code-plugins repo candidate in 'gaming' plugin (new) or 'dlss5' plugin (more specific)."
amended 2026-09-21: "Its gotta be generic, apply to any machine, user, organization, etc."

### Acceptance criteria (the handoff's Completion criteria)

Why: make the DLSS 5 Neural Rendering mod path (install, track, tune, remove, keep current)
generic and reusable as a Claude Code plugin instead of one machine's hand-run script.

- [ ] `gaming` plugin installs from the marketplace and `pwsh -NoProfile -File <plugin>/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1 -Verb selftest` exits 0
- [ ] `skill-quality:check plugins/gaming` reports PASS for every skill
- [ ] ledger, snapshots, manifests, and the runtime DLL live in the configured `data_dir` and survive `claude plugin uninstall gaming` (verify: uninstall, then the files still exist)
- [ ] the plugin is registered: `.claude-plugin/marketplace.json` entry (category personal, defaultEnabled false), `plugins/gaming/.claude-plugin/plugin.json`, README, CHANGELOG; CI catalog regeneration passes
- [ ] a draft PR is open from `feat/dlss5-plugin` (`gh pr view` shows draft)
- [x] proving ground: the mod is applied and verified live in Cyberpunk 2077 and Dying Light: The Beast (`OptiScaler.log` shows `DLSS-NR cost` lines, observed this session)

### Constraints (every one is [h1] in the handoff)

1. The proprietary NVIDIA runtime `nvngx_dlssnr.dll` (310.8.0.0, SHA-256
   `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E`) is never committed, never
   bundled, never placed under `${CLAUDE_PLUGIN_ROOT}`. The plugin names no source for it. It
   reaches `data_dir` only from a path the user configures, from a DLSS 5 title installed on the
   user's own machine, or from a `runtime_source` the user configures, and every copy passes the
   hash-or-signature gate. (Amended 2026-09-22 from "references it by configured path plus hash
   only"; approved by the user.)
2. `data_dir` default must NOT be `${CLAUDE_PLUGIN_DATA}`, which is deleted on
   `claude plugin uninstall` by default.
3. `apply` never overwrites an existing game file; it fails before copying on any destination
   collision. `remove` never deletes a file that is not in the manifest or the known byproduct
   list.
4. Proxy name for Cyberpunk 2077 is `dxgi.dll`, never `dbghelp.dll`.
5. Never install into a game with anti-cheat on disk.
6. `setup_windows.bat` from the mod zips is interactive and must never be invoked from a
   non-interactive shell; the plugin does the rename itself.
7. `[DlssNr] AutoCapture` must be set `false` before first launch.
8. `commands/` is prohibited (skills only); `docs/catalog.md` is CI-generated, never hand-edited;
   every PR opens as a draft.

### Scope boundary

In scope: the `plugins/gaming` plugin, its two skills, its script, its reference docs and evals,
its registration in the marketplace and the repo's enablement and cheatsheet surfaces, and a
draft PR. Out of scope: migrating the proving-ground state on this machine into `data_dir`,
launch-verifying the five unverified games, filling the ledger's FPS and visual columns, and
creating the weekly `refetch` routine via `/schedule`. Those are the handoff's remaining actions
6 and 7 and happen after merge.

### Pinned upstream literals

Phases 3, 4 and 5 all need these. They live here so each worker brief carries one copy and the
phases stay file-disjoint. Every row was read this session; nothing here is recalled.

| Literal | Value | How it was verified |
|---|---|---|
| Primary fork repo | `Dagherbou/OptiScaler_DLSSNR` | `gh api repos/Dagherbou/OptiScaler_DLSSNR/releases`, 2026-09-21 |
| Primary tag | `v0.2.0-patch1`, `prerelease: true` | same call. `v0.2.0-dlssnr` is a different, older release carrying `OptiScaler-DLSSNR-v0.2.0.zip`; do not confuse them |
| Primary asset | `OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip` | same call |
| Primary URL | `https://github.com/Dagherbou/OptiScaler_DLSSNR/releases/download/v0.2.0-patch1/OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip` | release-asset URL form for the tag and asset above |
| Primary SHA-256 | `5DB547216FA8A7DBD8AB0A193DA1E3BCE0EA4BD71F91189AFA4ED2EDE8BB9561` | `Get-FileHash -Algorithm SHA256` over the proving-ground copy at `C:\Users\KyleSexton\.work\dlss-5-availability\scratch-dagherbou\OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip`. The release publishes no checksum sidecar, so this hash is a local-copy attestation, not an upstream one, and `reference/fork-comparison.md` must say so |
| Fallback fork repo | `wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass` | `gh api repos/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases`, 2026-09-21 |
| Fallback tag | `v0.8.3`, `prerelease: false` (the newest non-prerelease; v0.8.4 through v0.8.7 are all prereleases) | same call |
| Fallback asset | `OptiScaler-NR-v0.8.3.zip` | same call |
| Fallback URL | `https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases/download/v0.8.3/OptiScaler-NR-v0.8.3.zip` | release-asset URL form |
| Fallback SHA-256 | `3F2D26FB136D964A394BF50896D082156173153A2A55B88E1995277B4DABE3C8` | `Get-FileHash` over the local copy, and it matches the release's own `OptiScaler-NR-v0.8.3.zip.sha256` sidecar byte for byte, so this one is upstream-attested |
| Runtime DLL | `nvngx_dlssnr.dll`, 310.8.0.0, SHA-256 `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E` | constraint 1; the value the current script already carries as `$ModelHash` |
| Extract allow-list, dagherbou | `OptiScaler.dll`, `OptiScaler.ini`, `OptiScaler\`, `Licenses\`, `nvngx.dll_dlssnr.dll` | the `$Builds.dagherbou.Files` array at `.work/dlss5/tool/game-mod.ps1:19` |
| Extract allow-list, wilsjo2 | `OptiScaler.dll`, `OptiScaler.ini`, `OptiScaler\`, `Licenses\` | the `$Builds.wilsjo2.Files` array, same file |
| Never extracted, either fork | `setup_windows.bat`, `setup_linux.sh`, `READ ME - DLSS Neural Rendering.txt`, `README.md`, `CONTRIBUTING.md`, `Config.md`, `Features.md`, `INSTALL-DLSSNR.md`, `Spoofing.md`, `LICENSE`, `SHA256SUMS.txt`, `docs\`, `tests\`, `images\`, and the zero-byte marker file named `!! EXTRACT ALL FILES TO GAME FOLDER !!` | directory listing of both extracted trees under `C:\Users\KyleSexton\.work\dlss-5-availability\scratch-*\extracted\` |

Neither zip contains `Remove_OptiScaler.bat`. `setup_windows.bat` generates it, which is a second
reason never to run that file: the removal script the plugin refuses to use does not otherwise
exist on disk.

## Standards grounding

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `AGENTS.md` | "Open a pull request as a draft"; the loaded-on-demand rules index | repo |
| `.claude/rules/skill-bodies-state-current-rules.md` | whole file: the four-part verification record for volatile specifics, and the `## Next` section shape. Covers `plugins/*/skills/**`, so it binds every SKILL.md and reference doc this plan writes | repo |
| `docs/plugin-philosophy.md` | `commands/` Prohibited (line 273); skill naming, "A skill name is an imperative verb phrase; the plugin namespace supplies the object" (118-119) with "Nouns are reserved for knowledge routers ... and lifecycle-object routers (`worktree`, `pull-request`)" (149); "A plugin requires a `setup` skill iff it has (a) a consumer-project configuration surface, (b) an external prerequisite ... or (c) non-trivial `userConfig`" (423-424); userConfig schema honesty (349-357); "Declare every required runtime, shell, CLI, service, credential, and platform constraint at the point of use and in the plugin README" (627); bundled-asset anchoring, full `${CLAUDE_PLUGIN_ROOT}/skills/<other-skill>/<path>` for a cross-skill citation and a bare relative path only for a skill's own files (398-404) | repo |
| `docs/conventions/invocation-mode/README.md` | "Model-invoked (`disable-model-invocation: false`) is the default ... The key is written explicitly on every skill" (18-19); "(ii) Setup skills ... are named `setup` and carry `disable-model-invocation: true`" (58-59); cross-skill chain phrasing names the Skill tool (78-80); the rejected-router verdict (157-166), which does not reach an action router inside one skill | repo |
| `docs/conventions/plugin-data-report-keying/README.md` | "The data directory is deleted automatically when you uninstall the plugin from the last scope where it is installed"; Rule 1, key every write by project identity | repo |
| `docs/extensibility-contract-smoke-tests.md` | Test B: "A skill-invoked Bash-tool subprocess does NOT inherit `CLAUDE_PLUGIN_OPTION_*`" and "A skill reads a non-sensitive userConfig value only through `${user_config.KEY}` text-substitution into its own Markdown, never from the environment of a script it spawns"; and on `${CLAUDE_PLUGIN_DATA}`: "in a general Bash-tool subprocess it carries one session default, so it is not a dependable per-plugin signal for a skill-spawned script either" | repo |
| `docs/conventions/windows-path-emit/README.md` | Rule 1 prefer a path the native side computes itself; Rule 2 convert an absolute path at the boundary, not at the source. Binds every Bash-to-pwsh handoff in the skill bodies | repo |
| `docs/catalog-taxonomy.md` | "\| `personal` \| The owner's personal-life tooling, outside the software-delivery lifecycle. \|" (line 59) | repo |
| `docs/conventions/pr-body-convention/README.md` | "When no layer sets `pr_body_required_sections`, the plugin's built-in scaffold requires exactly two sections: `Summary` and `Test plan`." (39-41) | repo |
| `docs/conventions/commit-convention/README.md` | the canonical Conventional Commits ERE the resolver owns, `^(feat\|fix\|docs\|style\|refactor\|perf\|test\|build\|ci\|chore\|revert)(\(.+\))?!?: .+` (36-38) | repo |
| `scripts/validate-plugin-contracts.mjs` lines 186-235 | the setup-skill contract: `disable-model-invocation: true`, `argument-hint` leading with `check`, backticked `check` and `apply` in the body, no marketplace name bound into setup content | repo |
| `scripts/check-plugin-catalog-enablement.sh` header | a catalogued plugin is covered when the fleet list enables it OR `.claude/settings.json` `enabledPlugins` carries an explicit `<name>@<marketplace>` key; keys must be in byte order; "A key set to `false` PASSES" | repo |
| `scripts/cheatsheet-config.mjs` | `EXCLUDED_PLUGINS`, with the comment "an in-scope skill must carry `workflow-stage` XOR appear here; the generator fails on silent omission" | repo |
| `scripts/sync-plugin-options-docs.py` | "The block between the markers below is GENERATED. Never hand-edit it"; `--check` fails on drift | repo |
| `plugins/kindle-dedrm/` | README's Windows-only and personal-use warning shape; `manage/SKILL.md` action-router table and Hard safety rules; `setup/SKILL.md` check/apply shape; `evals/evals.json` case shape | repo analogue |
| `plugins/machine-health/` | `plugin.json` `userConfig.report_dir` with no `default` field and a prose default in the description; `audit/SKILL.md:24` reading `${user_config.report_dir}` and falling back when the token is empty or still literal; `setup/SKILL.md` check/apply | repo analogue |

## Approach

Port the proven `game-mod.ps1` rather than rewrite it. It already holds the whole safety story:
the pre-write collision check, the model-DLL hash gate, the byproduct classification that makes
`remove` byte-exact, and a selftest that proves all three. Three things stop it from being
generic, and they are the substance of the port:

1. `StateDir` roots state at `$PSScriptRoot\state` and `$Model` at `$PSScriptRoot\runtime\`. Both
   become `-DataDir` and `-RuntimeDll` parameters. Nothing may be written under
   `${CLAUDE_PLUGIN_ROOT}`, which a plugin update replaces.
2. The `$Builds` table hardcodes `C:\Users\KyleSexton\.work\dlss-5-availability\scratch-*\extracted`
   as the fork source. That is a second machine-specific path the handoff does not name, and
   parameterizing `data_dir` alone does not fix it. Builds move to `<DataDir>\builds\<build>\`,
   provisioned by `setup apply`.
3. The script has no `assess`. The eligibility checks that kept the proving ground safe were run
   by hand.

The skill layer is thin by design. `Invoke-Dlss5Mod.ps1` does the deterministic on-disk work and
the SKILL.md does what a script cannot: the web lookups, the judgment calls, and the ledger
prose. That split is also what makes the plugin testable, because everything with a correctness
claim lives behind `-Verb selftest`.

Integration first. Phase 2 ends with `pwsh -NoProfile -File
plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1 -Verb selftest` exiting 0 from the
plugin path with no other arguments, which is acceptance criterion 1. Every later phase extends a
system already proven end to end.

TDD throughout the script phases: a selftest case is written and seen to fail before the
behavior it asserts exists.

## Plan

### Phase 1: Scaffold and register the plugin [DONE]

Sanity Check run 2026-09-22: all eleven commands exit 0 and the `jq` marketplace probe exits 0.
`generate-catalog.mjs` was run once to write the new catalog line (generator output, not a hand
edit).

Work items:

- [ ] Write `plugins/gaming/.claude-plugin/plugin.json`: name `gaming`, version `0.1.0`,
      `$schema` and `author` and `license` copied from the kindle-dedrm manifest's shape,
      description naming the DLSS 5 Neural Rendering scope and Windows-only, keywords including
      `windows`, `powershell`, `skill`.
- [ ] Declare `userConfig.data_dir` (type `directory`, title "Data directory", NO `default` field)
      and `userConfig.runtime_dll` (type `file`, title "DLSS 5 runtime DLL"). The prose default
      goes in the description, mirroring machine-health's `report_dir`: "Leave unset to use the
      default: Documents\Gaming under your user profile." `runtime_dll`'s description names the
      expected version 310.8.0.0 and SHA-256, and states the plugin names no source for it.
      Also declare `userConfig.runtime_source` (type `string`, title "DLSS 5 runtime source"): an
      `https://` URL or a local/UNC path to a copy the user controls. Its description states that
      the value is stored in plain text in `settings.json`, so it must not carry a credential (no
      query string); a private store is synced to a path by the user's own tooling. The plugin
      assumes no storage provider (amended 2026-09-22, user decision). None of the three is
      `required: true`, and none is `sensitive`: a sensitive option is unreachable from a skill
      (`docs/extensibility-contract-smoke-tests.md`, "A **sensitive** value is unreachable from a
      skill entirely").
- [ ] Write `plugins/gaming/README.md`: what the plugin is, the `/gaming:dlss5` invocation, a
      Windows-only section in the kindle-dedrm shape, a legal/scope section stating the plugin
      ships no NVIDIA binary and names no source for one: it uses a DLL the user configures by
      path, copies one out of a DLSS 5 title the user owns, or downloads one from a
      `runtime_source` the user configures, and the licence terms of that source are the user's
      responsibility, and the "How to set these" configuration routes copied from machine-health's README
      with `<marketplace>` as the placeholder.
- [ ] Run `python scripts/sync-plugin-options-docs.py` to generate the README's options block.
      Do not hand-write that table.
- [ ] Write `plugins/gaming/CHANGELOG.md` with a `## [0.1.0]` entry, Keep a Changelog header in
      the kindle-dedrm shape.
- [ ] Write both SKILL.md files with complete, contract-valid frontmatter and a minimal body, so
      the contract gates have something real to check from here on. Bodies are filled in Phases 4
      and 5. `dlss5`: `disable-model-invocation: false` written explicitly,
      `argument-hint: "[assess|apply|remove|status|tune|refetch] [<game-dir>]"`. `setup`:
      `disable-model-invocation: true`, `argument-hint: "check | apply"`, body containing
      backticked `check` and `apply`.
- [ ] Add the `.claude-plugin/marketplace.json` entry: `name` `gaming`, `source` `./plugins/gaming`,
      `category` `personal`, tags, `defaultEnabled: false`. Insert in the file's existing order.
- [ ] Add `"gaming@melodic-software": false` to `.claude/settings.json` `enabledPlugins`, between
      `fleet@melodic-software` and `playgrounds@melodic-software` (byte order). The gate's header
      states a `false` key passes and is a recorded decision; this plugin is Windows-only mod
      tooling that a cloud session must not install.
- [ ] Add `["gaming", "personal-domain plugin"]` to `EXCLUDED_PLUGINS` in
      `scripts/cheatsheet-config.mjs`, in the map's alphabetical order. Without it the cheatsheet
      generator fails on silent omission.
- [ ] Write `plugins/gaming/.gitignore` with `*.dll`, `*.zip`, `*.exe`, `state/`, `runtime/`,
      `builds/`. Nothing the plugin provisions or the user configures belongs in the tree, and the
      cheapest place to stop a proprietary binary reaching a commit is before it is ever
      stageable. `plugins/ai-briefing/.gitignore` is the existing precedent for a per-plugin
      ignore file.
- [ ] Append `plugins/gaming/README.md`, `plugins/gaming/CHANGELOG.md`,
      `plugins/gaming/skills/dlss5/SKILL.md` and `plugins/gaming/skills/setup/SKILL.md` to
      `scripts/em-dash-purged-paths.txt`. Read the file's own header first: it is an allowlist of
      surfaces already purged of em dashes, entries are added in the same pull request that purges
      the surface, and the two documented conditions must both hold. New files written em-dash-free
      satisfy them by construction.

| File | Action | What changes |
|---|---|---|
| `plugins/gaming/.claude-plugin/plugin.json` | Create | manifest with the three userConfig options |
| `plugins/gaming/.gitignore` | Create | binary and provisioned-state ignores |
| `plugins/gaming/README.md` | Create | Windows-only, legal scope, generated options block |
| `plugins/gaming/CHANGELOG.md` | Create | `## [0.1.0]` |
| `plugins/gaming/skills/dlss5/SKILL.md` | Create | frontmatter plus minimal body |
| `plugins/gaming/skills/setup/SKILL.md` | Create | frontmatter plus minimal body |
| `.claude-plugin/marketplace.json` | Modify | one entry added |
| `.claude/settings.json` | Modify | one `enabledPlugins` key added |
| `scripts/cheatsheet-config.mjs` | Modify | one `EXCLUDED_PLUGINS` entry added |
| `scripts/em-dash-purged-paths.txt` | Modify | four paths appended |

**Sanity Check:** each of these exits 0:
`bash scripts/check-plugin-manifest-presence.sh`;
`bash scripts/check-plugin-catalog-enablement.sh`;
`bash scripts/check-changelog-parity.sh --check`;
`node scripts/validate-plugin-contracts.mjs`;
`node scripts/generate-catalog.mjs --check`;
`node scripts/generate-cheatsheet.mjs --check`;
`python3 scripts/sync-plugin-options-docs.py --check`;
`python3 scripts/check-manifest-duplicate-keys.py`;
`bash scripts/check-purged-em-dashes.sh`;
`bash scripts/check-skill-leaf-names.sh --check`;
`bash scripts/validate-plugins.sh`.
And `jq -e '.plugins[]|select(.name=="gaming" and .category=="personal" and .defaultEnabled==false)' .claude-plugin/marketplace.json`
exits 0, which pins the three marketplace fields a `grep -c` on the category alone cannot.

### Phase 2: Port the script with data-dir and DLL parameterization [DONE]

Sanity Check run 2026-09-22: selftest `SELFTEST OK`, exit 0; `KyleSexton` grep exit 1; no
`PSScriptRoot` line names `state` or `runtime`; no directory created under `scripts/`. A
fresh-context verifier passed all 14 criteria on dbbf46624; its MEDIUM rollback finding is fixed
in the Phase 3 commit. Deviations: `DEVIATIONS.md`.

TDD: every assertion below is added to `Do-Selftest` and seen to fail before the change that
makes it pass.

Work items:

- [ ] Copy `.work/dlss5/tool/game-mod.ps1` to
      `plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1`.
- [ ] Add parameters `-DataDir` and `-RuntimeDll`, resolved by one helper in this order: treat the
      value as unset when it is empty or still begins with the literal `${user_config.`; otherwise
      take it, expand any environment references, resolve it to an absolute path against the
      process working directory when it is relative, and `.TrimEnd('\')` the result. The
      relative-path branch is not defensive padding: `docs/extensibility-contract-smoke-tests.md`
      records that a `directory` option is "stored verbatim, not normalized to absolute", that a
      relative `./realdir` stays `./realdir`, and that "a plugin that needs an absolute path
      resolves it itself". `DataDir` defaults to
      `[Environment]::GetFolderPath('MyDocuments')` joined with `Gaming`, which follows a OneDrive
      Known Folder Move where a hardcoded `$env:USERPROFILE\Documents` does not. `RuntimeDll`
      defaults to `<DataDir>\runtime\nvngx_dlssnr.dll`. The literal-token branch is what
      machine-health's audit skill does at `SKILL.md:24` and exists because an unset option
      substitutes as its own token.
- [ ] `StateDir` roots at `<DataDir>\state\<GameKey>`; `$Model` becomes the resolved
      `-RuntimeDll`. `$ModelHash` stays a script constant.
- [ ] Add `-RuntimeSource`, read through the same unset rule (empty or a literal
      `${user_config.` prefix means unset) but not path-resolved when it starts with `https://`.
      Refuse a URL with any query string: signed-URL credentials live there, and the value sits
      in plain-text settings and on a command line the transcript records. Nothing in Phase 2 uses
      the value; Phase 3's `provision -Runtime` does.
- [ ] Widen `GameKey` to `<existing prefix>_<first 8 hex of the SHA-256 of the lowercased full
      path>`, KEEPING the existing prefix rule at `game-mod.ps1:37` (the segment after
      `steamapps\common\` when present, the leaf name otherwise). The suffix makes the key
      injective over directories; the prefix keeps `Cyberpunk_2077_3f9a1c08` readable where a bare
      `x64_3f9a1c08` is not, and a state directory a human cannot identify is a state directory a
      human will not clean up. Today two non-Steam installs both ending in `Win64`, and one game
      whose launcher and renderer live in two exe directories, collide onto one state directory and
      the second `apply` reads the first game's snapshot. Record the resolved `gameDir` in both
      `snapshot.json` and `manifest.json`, and refuse any verb whose resolved directory does not
      match the recorded one.
- [ ] Replace both `$Builds` `Src` values with `<DataDir>\builds\<build>`. Delete every
      `C:\Users\KyleSexton` literal.
- [ ] Anti-cheat refusal inside `Do-Apply` itself, not only in `assess`. Scan from the GAME ROOT,
      not the exe directory: take the `steamapps\common\<X>` segment when the path matches it,
      otherwise walk up to four ancestors, and stop at the drive root. `EasyAntiCheat\` sits beside
      the game root while the exe is typically two or three levels down under `bin\x64` or
      `Binaries\Win64`, so a scan rooted at the exe directory finds nothing on exactly the games
      constraint 5 exists for. Token list lives in `reference/anticheat-posture.md`, which Phase 4
      writes as its single source, and the script matches it. No `-Force` bypass.
- [ ] `Do-Apply` refuses before any write when the target holds no `*.exe`, and refuses when it
      holds more than 2000 files unless `-Force` is passed. Both catch the same mistake, a user
      passing a game root or a library root instead of the exe directory, and a wrong-directory
      apply is the failure mode that scatters DLLs where `remove` will never look. [EXEC-SHAPE] The
      2000 threshold is judgment, not a measured figure; it is a `-Force`-overridable warning, not
      a hard wall.
- [ ] `Do-Apply` auto-runs the snapshot when `snapshot.json` is absent, and does so only AFTER
      every refusal gate above has passed, so a refused apply leaves no state directory behind.
- [ ] Rollback. `Do-Apply` writes `<StateDir>\pending.json` listing its intended destinations
      before the first `Copy-Item`, appends each destination as it lands, and a `try`/`catch`
      around the copy loop deletes exactly what it copied and rethrows. `remove` and `status` treat
      a leftover `pending.json` as a manifest, so a crash mid-copy is recoverable rather than a
      half-modded folder with no record. Delete `pending.json` on success, when the real manifest
      is written.
- [ ] Runtime-DLL gate. Keep the known-good hash check against `$ModelHash`
      (`E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E`, 310.8.0.0) and add an
      Authenticode check: `Get-AuthenticodeSignature` status `Valid`, subject containing
      `CN=NVIDIA Corporation`, and `FileVersion` at or above 310.8.0.0. A known hash passes. An
      unknown hash with a valid NVIDIA signature is REFUSED unless `-AllowUnknownRuntime` is
      passed, and when it is, the observed hash is recorded in the manifest. Anything else is
      refused outright. Without this the hash constant pins the plugin to one driver generation and
      every user on a newer runtime is blocked or, worse, edits the constant. [EXEC-SHAPE]
- [ ] Byproduct classification gets a single source. Add `OptiScaler.asi` to `IsByproduct`
      (`game-mod.ps1:54-55` lists only `OptiScaler.log`, `dlssnr-capture\*` and
      `OptiScalerProfiles\*`), and make the function's entries exactly the rows of
      `reference/reversal-matrix.md`, which Phase 4 writes. `.work/dlss5/research/tool-currency/RESEARCH-cleanliness.md:83`
      records `OptiScaler.asi` among the files the fork's own removal script deletes, so today the
      plugin's `remove` leaves it behind and `status` reports it as `unknown` forever. One selftest
      case per matrix row.
- [ ] `remove -Finish` drops the manifest when the only files left are unknown leftovers, listing
      them in the output first. Without it a folder the user cleaned by hand keeps a manifest that
      `status` will contradict for good.
- [ ] Drop `snapshot` from the `-Verb` `ValidateSet`. `apply` auto-snapshots, so the verb is now a
      way for a user to overwrite a good snapshot with a post-install tree and make `remove`
      restore the modded state. If it is kept for debugging, it must refuse when a manifest exists.
- [ ] Rewrite `Do-Selftest` to run with no arguments other than `-Verb selftest`: it creates its
      own temporary `DataDir` and temporary runtime DLL, so it never writes under
      `${CLAUDE_PLUGIN_ROOT}` or the user's real `data_dir`.
- [ ] New selftest cases: default `DataDir` used when the parameter is empty; default used when
      the parameter is the literal `${user_config.data_dir}`; a RELATIVE `-DataDir` value resolves
      to an absolute path and state lands there; a trailing-backslash value is trimmed; state lands
      under the passed `DataDir` and nowhere under `$PSScriptRoot`; two fixture directories both
      named `Win64` get distinct `GameKey` values; a verb run against a directory whose path does
      not match the recorded `gameDir` refuses; `apply` into a fixture with `EasyAntiCheat\` three
      levels ABOVE the exe directory throws and copies nothing; `apply` into a directory with no
      `*.exe` refuses; `apply` whose copy loop throws midway leaves the tree byte-identical and no
      `pending.json` orphan the next `status` cannot explain; an unknown-hash runtime refuses
      without `-AllowUnknownRuntime`; one case per `reversal-matrix.md` row; `apply` with no prior
      snapshot snapshots first and succeeds.

| File | Action | What changes |
|---|---|---|
| `plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1` | Create | the ported, parameterized script |

**Sanity Check:** `pwsh -NoProfile -File plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1 -Verb selftest` prints `SELFTEST OK` and exits 0;
`grep -rn 'KyleSexton' plugins/gaming` returns nothing (exit 1);
`grep -rn 'PSScriptRoot' plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1` returns no line containing `state` or `runtime`;
`git status --porcelain plugins/gaming/skills/dlss5/scripts` shows no `state/` or `runtime/` directory created by the selftest run.

### Phase 3: The `assess` and `provision` verbs [DONE]

Sanity Check run 2026-09-22: selftest exit 0 with the three named PASS lines; the fixture `assess`
returns `refused`. A fresh-context verifier passed all 8 criteria on 8c4c0e97d; its MEDIUM finding
(a bad `runtime_source` blocked every verb) and three LOW findings are fixed in the follow-up
commit. Deviations: `DEVIATIONS.md`.

Both are new verbs on the file Phase 2 just created, both read the pinned literals table above,
and both are main-session work, so they share a phase rather than splitting the same file across
two.

`assess` scope is deliberately minimal: on-disk facts only. The web lookups (Steam store page
anti-cheat drawer, OptiScaler wiki compatibility) belong to the SKILL.md, which has WebFetch.
Steam's `appinfo.vdf` is a binary format and is not parsed here; the app id comes from the text
`steamapps\appmanifest_*.acf`.

`provision` exists because download, hash-verify and extract are correctness-bearing work, and in
the draft they lived in SKILL.md prose, outside the only boundary this plan can actually test. A
skill body cannot be asserted on; a verb under `-Verb selftest` can.

TDD: fixture-backed selftest cases first.

Work items:

- [ ] Add `assess` to the `-Verb` `ValidateSet` and a `Do-Assess` that returns the shape recorded
      in `design/design-resolution.md`, writing nothing.
- [ ] Probes: the exe directory exists and holds at least one `*.exe`; `nvngx_dlss*.dll` files
      present with their `VersionInfo.FileVersion`; a DX12 signal (`d3d12*.dll` or a
      `*/Binaries/Win64` Unreal layout) reported as a fact, not a verdict; anti-cheat files, scanned
      from the game root exactly as `Do-Apply` scans; proxy-name collisions for `dxgi.dll`,
      `dbghelp.dll`, `winmm.dll`, `version.dll`; the Steam app id from the parent
      `steamapps\appmanifest_*.acf`.
- [ ] The anti-cheat token set is whatever `reference/anticheat-posture.md` lists, and the script
      carries that list once, shared by `assess` and `Do-Apply`. Seed it with the tokens the
      research corpus actually names: `EasyAntiCheat`, `EasyAntiCheat_EOS`, `BattlEye`,
      `BEService`, and `ACE` (the nProtect and Tencent family), all read out of
      `.work/dlss5/research/multiplayer-anticheat/`. [EXEC-SHAPE] Phase 4 may add
      `EasyAntiCheat_Setup.exe`, `GameGuard` and `Vanguard` to the same list; those three are
      judgment from general anti-cheat knowledge, appear nowhere in the research corpus, and the
      reference doc must label them as such rather than implying a source it does not have.
- [ ] Verdict rule: `refused` when any anti-cheat token is present. Otherwise `eligible` with
      `"requiresWebCheck": true` when a free proxy name exists, because on-disk absence is not
      absence: a title can ship server-side or launcher-delivered anti-cheat with nothing in the
      install tree, and the Steam store page's `anticheat_section` is the only cheap source that
      sees it. The flag clears only when the SKILL.md has read that section. Otherwise `unknown`
      with the collisions listed.
- [ ] Add `provision` to the `ValidateSet`. It takes `-Build`, downloads the pinned asset by its
      direct release URL from the table above (no `gh` dependency, so an unauthenticated machine
      can still provision), verifies the SHA-256 against the pinned value and DELETES the download
      on mismatch, then extracts ONLY the build's allow-list entries into `<DataDir>\builds\<build>\`.
      `setup_windows.bat`, `setup_linux.sh`, `docs\`, `tests\`, `images\`, the README family and the
      marker file are never written to `builds\`. Constraint 6 says that batch file must never be
      invoked from a non-interactive shell, and the cheapest way to honour that is for it never to
      reach the disk the plugin manages.
- [ ] `provision` writes `<DataDir>\builds\<build>\.provisioned.json` recording the tag, asset,
      URL, verified hash and timestamp. That marker is what lets `setup check` tell a
      never-provisioned `builds\` (INFO) from a provisioned-then-emptied one (FAIL).
- [ ] Add `provision -Runtime`, which places the runtime DLL at `<DataDir>\runtime\nvngx_dlssnr.dll`
      and stops at the first source that passes the Phase 2 runtime gate (known hash, or valid
      `CN=NVIDIA Corporation` signature at or above 310.8.0.0 plus `-AllowUnknownRuntime`):
      1. The configured `-RuntimeDll`, or a DLL already at the default path: gate it, copy nothing.
      2. Local scan (Option A). Enumerate Steam library roots from
         `<SteamPath>\steamapps\libraryfolders.vdf` (text VDF; `SteamPath` from
         `HKCU:\Software\Valve\Steam`) and search each `steamapps\common\` with
         `Get-ChildItem -Recurse -Filter nvngx_dlssnr.dll`. Recursive, not depth-capped: NBA 2K27
         keeps it at `data\streamline\` and Unreal titles keep DLSS deeper than depth 6 (handoff
         findings). The scan only reads game folders; it copies out, never in. Among candidates
         that pass the gate, prefer the pinned hash, then the highest `FileVersion`. The verb takes
         `-ScanRoots` so the selftest injects a fixture instead of reading the registry. Epic and
         Xbox library discovery is judgment-level scope: add it when a user reports a DLSS 5 title
         installed there.
      3. `-RuntimeSource`. A local or UNC path is copied. A plain `https://` URL is fetched with
         `Invoke-WebRequest`. No provider-specific client (amended 2026-09-22: an earlier draft
         special-cased Azure blob hosts through `az`; the user ruled that coupling out). The download goes to a temp file, is gated, and is deleted on
         refusal. The download step is factored separately, as for fork zips, so the selftest
         drives gate-and-place over a local file.
      4. Nothing passes: exit non-zero and print the three remedies (set `runtime_dll`, install a
         DLSS 5 title, set `runtime_source`), naming each candidate found and why it was refused.
      `provision -Runtime` writes `<DataDir>\runtime\.provisioned.json` recording which source won,
      the source path or URL, the hash, and the timestamp.
- [ ] New selftest cases for `provision -Runtime`: a text file at a fixture
      `steamapps\common\X\data\streamline\nvngx_dlssnr.dll` is FOUND by the scan and REFUSED by the
      gate, and nothing lands in `runtime\`; a `-RuntimeSource` URL with a query string is refused before
      any fetch; empty scan roots with no source exits non-zero and prints all three remedies. No
      network call and no registry read in the selftest.
- [ ] New selftest cases for `assess`: a fixture with `EasyAntiCheat\` returns `refused`; a fixture
      with a pre-existing `dxgi.dll` lists it as a collision and does not return `eligible` for that
      proxy; a clean fixture returns `eligible` with `requiresWebCheck` true; `assess` creates no
      `state\` directory. File version reads cannot be faked with text fixtures, so the DLSS probe
      is asserted on presence only.
- [ ] New selftest cases for `provision`: the verb is factored so the download step is separable
      from verify-and-extract, and the test drives verify-and-extract over a zip the test builds
      itself with `Compress-Archive`, holding both allow-list and forbidden entries. Correct hash
      extracts the allow-list and no forbidden entry; wrong hash throws, extracts nothing and
      leaves no partial file; `setup_windows.bat` is absent from the output tree;
      `.provisioned.json` parses and names the expected hash. No network call in the selftest.

| File | Action | What changes |
|---|---|---|
| `plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1` | Modify | `assess`, `provision` and `provision -Runtime`, and their selftest cases |

**Sanity Check:** `pwsh -NoProfile -File plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1 -Verb selftest` exits 0 and its output contains `PASS  assess refuses anti-cheat fixture`, `PASS  provision skips setup_windows.bat` and `PASS  runtime scan refuses unsigned candidate`;
and this sequence, which builds its own fixture so the check carries no placeholder, exits 0 and prints a verdict line naming `refused`. Run it through the PowerShell tool, or from Bash with the OUTER quotes single, never double: a `$g` or `$env:TEMP` inside a double-quoted Bash argument is expanded by Bash to the empty string before pwsh starts, and `-Verb assess` then runs against nothing. That is the same failure this plan's [EXEC-SHAPE] path-resolution decision exists to prevent, so the verification commands must not repeat it.

```powershell
$g = Join-Path $env:TEMP 'dlss5-assess-fixture\bin\x64'
New-Item -ItemType Directory -Force $g, (Join-Path $env:TEMP 'dlss5-assess-fixture\EasyAntiCheat') | Out-Null
Set-Content (Join-Path $g 'game.exe') 'x'
& 'plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1' -Verb assess $g
```

### Phase 4: The `dlss5` SKILL.md, reference docs, and evals [DONE]

Sanity Check run 2026-09-22: all commands pass except the `setup_windows.bat` grep, which flags
only the Phase 3 selftest fixture and its required PASS line (recorded plan-check conflict). A
fresh-context verifier passed all 10 Phase 4+5 criteria on ad00005ce; its findings are fixed in the
Phase 7 gate pass and the script follow-up.

Work items:

- [ ] Open `skills/dlss5/SKILL.md` with a "Resolving paths (do this first)" table in the exact
      shape of `plugins/machine-health/skills/audit/SKILL.md:18-24`: one row per option, each
      resolved MODEL-SIDE, so the command line the model then types carries literal resolved paths
      (`-DataDir "<data-dir>" -RuntimeDll "<runtime-dll>"`), never the `${user_config.*}` token
      itself. Writing `-DataDir "${user_config.data_dir}"` into a Bash command line is the bug: when
      the option is unset the token survives substitution verbatim and Bash reads `${user_config.data_dir}`
      as a parameter expansion with an invalid name, so the command dies with `bad substitution`
      before pwsh ever starts and the script's careful fallback never runs. The script-side
      literal-token branch from Phase 2 stays as defense in depth for the case where a caller does
      pass the token, but it is the second line, not the first.
- [ ] Apply the windows-path-emit rule at that boundary: pass Windows-form paths to pwsh, or let
      pwsh compute them, and never hand a Git Bash `/d/...` path across.
- [ ] An action-router table in the `kindle-dedrm:manage` shape (`skills/manage/SKILL.md:26-33`)
      with rows for assess, apply, remove, status, tune, refetch and an empty-argument auto-detect
      row. Two rules the precedent sets and this router must keep: the `apply` row runs `assess`
      first and stops on `refused` or on `eligible` with `requiresWebCheck` still true; and the
      auto-detect row may only RECOMMEND an action or run `status`, never run `apply` or `remove`,
      mirroring "Never commit to setup/sync/cleanup without user confirmation when ambiguous"
      (`skills/manage/SKILL.md:35`).
- [ ] A confirmation gate on `apply` and `remove`: echo the resolved absolute game directory, the
      build, the proxy name and the `assess` verdict, and require an explicit user confirmation
      before running the verb. These two actions write into folders the user paid for and the
      plugin did not create. `plugins/kindle-dedrm/skills/manage/SKILL.md:43` sets the precedent
      that each reversal is confirmed independently.
- [ ] A "Hard safety rules" section carrying constraints 1 and 3 through 7 verbatim in intent.
- [ ] Document `status` exit codes: 0 when every difference is either manifest-listed expected
      drift (`OptiScaler.ini`, which the fork's overlay rewrites on Save Settings) or a known
      byproduct; 1 only when a manifest file is Removed, or when a manifest file was modified, or
      when a non-manifest file changed. Without the split, every tuned game reports failure forever
      and the exit code stops meaning anything.
- [ ] Apply `.claude/rules/skill-bodies-state-current-rules.md`: every volatile specific the body
      restates (the DLL version and hash, both fork tags, the driver version, the anti-cheat
      status of any named game) carries the four-part verification record (claim, basis, as-of
      date, recheck trigger), and the file carries a `## Next` section naming `/gaming:setup`
      placed before `## Gotchas` or before the last H2.
- [ ] Write `skills/dlss5/reference/` from `.work/dlss5/research/`:
      `tuning-guide.md` (the Cyberpunk baseline: 3840x2160, DLSS Quality not Auto, Detail 1.0,
      Colour 1.0, Model resolution 100%, and the fork README's "1.0 is the model's picture"
      statement; sourced from the handoff's Decisions and `research/tool-currency/`),
      `reversal-matrix.md` (what `remove` deletes, what it keeps, and why the mod's own
      `Remove_OptiScaler.bat` is not used; sourced from `research/tool-currency/RESEARCH-cleanliness.md`).
      This file is the SINGLE SOURCE for byproduct classification: one row per pattern, and
      `IsByproduct` in the script matches its rows exactly, `OptiScaler.asi` included. A row added
      here without a matching selftest case is a gap, so the phase adds both together,
      `anticheat-posture.md`, which is the SINGLE SOURCE for the anti-cheat token list the script
      reads (sourced from `research/multiplayer-anticheat/RESEARCH-anticheat-posture.md` and
      `RESEARCH-verdicts.md`, with any token not found in those files labeled as judgment),
      `upstream-watch.md` (the four watch items and their recheck commands, sourced from the
      ledger's Upstream watch table and `research/tool-currency/RESEARCH-upstream.md`),
      `fork-comparison.md` (Dagherbou vs wilsjo2, sourced from
      `research/tool-currency/RESEARCH-fork-landscape.md` and `RESEARCH-post-release-issues.md`).
      It carries the pinned tag, asset, URL and SHA-256 for BOTH forks verbatim from the Brief's
      pinned-literals table, and states which hash is upstream-attested (wilsjo2, via its
      `.sha256` sidecar) and which is a local-copy attestation (Dagherbou, which publishes no
      checksum). It also records that the pinned Dagherbou release is a PRERELEASE, so any tooling
      that resolves "latest" will skip it.
- [ ] The `tune` action is SKILL.md prose over `reference/tuning-guide.md`, with no new script
      verb: the fork's in-game overlay is the actual tuning surface and it rewrites
      `OptiScaler.ini` itself, which `status` already reports as an expected modified manifest
      file.
- [ ] Write `skills/dlss5/evals/evals.json` in the kindle-dedrm shape: `skill_name` `dlss5`, one
      case per action for assess, apply refusal on anti-cheat, remove, status, and refetch, each
      with `prompt`, `expected_output`, `files`, `expectations`.
- [ ] A `## Gotchas` entry carrying the whole-tree rehash ceiling: `snapshot` and `status` hash
      every file in the exe directory, so on a large install both take minutes and `status` is not
      a command to run in a loop. Named as a known limitation rather than engineered around;
      incremental hashing by size and write time is the upgrade path if it bites.

| File | Action | What changes |
|---|---|---|
| `plugins/gaming/skills/dlss5/SKILL.md` | Modify | full router body |
| `plugins/gaming/skills/dlss5/reference/tuning-guide.md` | Create | tuning baseline |
| `plugins/gaming/skills/dlss5/reference/reversal-matrix.md` | Create | what remove touches |
| `plugins/gaming/skills/dlss5/reference/anticheat-posture.md` | Create | refusal policy and evidence |
| `plugins/gaming/skills/dlss5/reference/upstream-watch.md` | Create | watch items and recheck commands |
| `plugins/gaming/skills/dlss5/reference/fork-comparison.md` | Create | fork choice and its basis |
| `plugins/gaming/skills/dlss5/evals/evals.json` | Create | eval cases |

**Sanity Check:** `node scripts/validate-plugin-contracts.mjs` exits 0;
`grep -c 'as of' plugins/gaming/skills/dlss5/SKILL.md` returns at least 1 and
`grep -c '^## Next' plugins/gaming/skills/dlss5/SKILL.md` returns 1;
`grep -n 'disable-model-invocation: false' plugins/gaming/skills/dlss5/SKILL.md` matches;
`grep -rn 'setup_windows.bat' plugins/gaming | grep -viE 'never|do not|forbidden|refuse'` returns nothing (exit 1),
which is the mechanical form of "every mention forbids it" and needs no reader judgment;
`grep -n 'user_config' plugins/gaming/skills/dlss5/SKILL.md | grep -c 'pwsh'` returns 0, so no
`${user_config.*}` token sits on a shell command line;
`python3 -c "import json; json.load(open('plugins/gaming/skills/dlss5/evals/evals.json'))"` exits 0.

### Phase 5: The `setup` skill [DONE]

Sanity Check run 2026-09-22: all five commands pass; covered by the same fresh-context verifier.

Work items:

- [ ] Fill `skills/setup/SKILL.md` against the contract in `scripts/validate-plugin-contracts.mjs`
      lines 186-235: `disable-model-invocation: true`, `argument-hint` leading with `check`, the
      body documenting backticked `check` and backticked `apply`, and no marketplace name bound
      into any setup content (use `<marketplace>`).
- [ ] The same "Resolving paths (do this first)" table as the `dlss5` skill, resolved model-side,
      for the same reason. Setup is where a first-time user is most likely to have both options
      unset.
- [ ] `check` (read-only) probes: pwsh 7 present; an NVIDIA GPU and driver version via
      `nvidia-smi`; the resolved `data_dir` exists and is writable;
      `<DataDir>\runtime\nvngx_dlssnr.dll` or the configured `runtime_dll` present and
      hash-matching; `<DataDir>\builds\<build>\` populated. `gh` is probed as INFO only, not as a
      prerequisite: `provision` downloads by direct release URL and needs no GitHub credential, so
      `gh` is required by `refetch` alone and a machine without it can still complete setup and
      apply the mod.
- [ ] Resolve the `builds\` contradiction with the `.provisioned.json` marker Phase 3 writes: an
      empty `builds\<build>\` with no marker is INFO (never provisioned, run `apply`); an empty
      one WITH a marker is FAIL (provisioned then emptied, so something deleted it). Without the
      marker, `check` has to guess, and this plan's own earlier draft guessed both ways in two
      different sections.
- [ ] A missing or gate-failing runtime DLL is FAIL. `check` stays read-only, so it reports what
      `apply` would do: whether the local scan finds a candidate (named, with its gate result) and
      whether `runtime_source` is set. Remediation prose names the three remedies in `provision
      -Runtime`'s order and states that the plugin names no source of its own.
- [ ] The "Resolving paths" table carries a `runtime_source` row. Only `setup` resolves it; the
      `dlss5` skill never acquires the runtime, so its table keeps two rows.
- [ ] `check` also scans for ORPHANED state: `<DataDir>\state\*` directories whose recorded
      `gameDir` no longer exists, and, when the resolved `data_dir` differs from the one a previous
      run used, says so. A user who changes `data_dir` after applying leaves every manifest behind
      at the old root, so `status` and `remove` see a modded game with no state and the mod becomes
      unremovable by the plugin. `README.md` states plainly that changing `data_dir` after an apply
      is a MOVE of the directory, not a reconfiguration.
- [ ] `apply` creates the `data_dir` tree (`state`, `runtime`, `builds`, `cache`), seeds
      `LEDGER.md` from the template, calls `provision -Runtime` (passing the resolved
      `-RuntimeDll` and `-RuntimeSource`), then `provision` for the pinned build, then re-runs
      `check`. Provisioning logic is not restated in prose here; the verb owns it and the selftest
      covers it. `apply` never runs `setup_windows.bat` (repeat the prohibition in this body,
      because setup is the skill a user reaches for when a manual install tempts them) and never
      fetches the runtime DLL from any source but the three `provision -Runtime` names.
- [ ] `## Next` section naming `/gaming:dlss5 assess <game-dir>`.
- [ ] Write `skills/setup/evals/evals.json`: a check-is-read-only case (it reports a scan
      candidate without copying it), a missing-DLL-with-no-candidate-and-no-source-is-FAIL case,
      and an apply-is-idempotent case.
- [ ] Add `plugins/gaming/skills/setup/reference/ledger-template.md` holding the two ledger tables
      and their column prose, so `setup apply` has one source to seed from. It lives under the
      skill that consumes it, which keeps Phases 4 and 5 fully file-disjoint and avoids the
      cross-skill `${CLAUDE_PLUGIN_ROOT}/skills/<other-skill>/<path>` anchoring
      `docs/plugin-philosophy.md:398-404` would otherwise require.

| File | Action | What changes |
|---|---|---|
| `plugins/gaming/skills/setup/SKILL.md` | Modify | full check/apply body |
| `plugins/gaming/skills/setup/evals/evals.json` | Create | eval cases |
| `plugins/gaming/skills/setup/reference/ledger-template.md` | Create | ledger seed |

**Sanity Check:** `node scripts/validate-plugin-contracts.mjs` exits 0;
`grep -n 'argument-hint: "check' plugins/gaming/skills/setup/SKILL.md` matches;
`grep -n 'disable-model-invocation: true' plugins/gaming/skills/setup/SKILL.md` matches;
`grep -rn 'melodic-software' plugins/gaming/skills/setup/` returns nothing (exit 1);
`bash scripts/check-skill-leaf-names.sh --check` exits 0.

### Phase 6: The `refetch` verb and the upstream-watch loop [DONE]

Sanity Check run 2026-09-22: selftest `SELFTEST OK`, exit 0 (four refetch cases, including the
merge rule and a missing `gh`); the temp-dir `refetch` sequence parses. A live run returned the
fork tags, upstream `v0.9.4`, driver 616.92 and runtime 310.8.0.0. `refetch` also reads upstream
OptiScaler's latest release, a fifth item beyond the four the plan named.

Kept thin. The script fetches; the model writes the ledger.

Work items:

- [ ] Add `refetch` to the `ValidateSet`. It queries: both fork repos' releases via
      `gh api repos/<owner>/<repo>/releases --jq '.[].tag_name'`; the local driver via
      `nvidia-smi --query-gpu=driver_version --format=csv,noheader`; the local runtime DLL's
      `VersionInfo.FileVersion`. It writes `<DataDir>\cache\upstream.json` and prints the same
      object.
- [ ] Anything needing a web page (the NVIDIA driver page, the NVIDIA native DLSS 5 game list,
      each ledger game's Steam `anticheat_section`) stays in the SKILL.md as WebFetch steps. A
      pwsh HTML scraper is not built.
- [ ] Graceful degradation: a missing or unauthenticated `gh`, or an absent `nvidia-smi`, records
      that item as `"found": null, "error": "<reason>"` rather than failing the verb. Callers can
      still see the items that did resolve.
- [ ] The cache MERGES, it never overwrites wholesale. An item that fails to resolve keeps its
      previous `found` value and its previous `Checked` timestamp, and carries the new `error`
      alongside. A straight overwrite means one offline run erases every known version the ledger
      was diffed against, and the next online run then reports every item as changed.
- [ ] SKILL.md `refetch` action: run the verb, WebFetch the page-backed items, diff against the
      ledger's Upstream watch table, and Edit only the rows that changed, updating the `Checked`
      column. Report a no-change run as a no-change run.
- [ ] Selftest case: `refetch` with a temporary `DataDir` writes a parseable
      `cache\upstream.json` and exits 0 even when `gh` is unavailable.

| File | Action | What changes |
|---|---|---|
| `plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1` | Modify | `refetch` verb |
| `plugins/gaming/skills/dlss5/SKILL.md` | Modify | `refetch` action steps |
| `plugins/gaming/skills/dlss5/reference/upstream-watch.md` | Modify | recheck commands aligned with the verb |

**Sanity Check:** `pwsh -NoProfile -File plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1 -Verb selftest` exits 0;
and this sequence, which creates its own directory so the check carries no placeholder, exits 0.
Run it through the PowerShell tool, not as a double-quoted `pwsh -Command` argument from Bash, for
the reason given in Phase 3's Sanity Check.

```powershell
$d = Join-Path $env:TEMP 'dlss5-refetch-check'
New-Item -ItemType Directory -Force $d | Out-Null
& 'plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1' -Verb refetch -DataDir $d
Get-Content (Join-Path $d 'cache\upstream.json') -Raw | ConvertFrom-Json | Out-Null
```

### Phase 7: Repo gates, skill quality, catalog regeneration, installed-path proof [DONE]

Sanity Check run 2026-09-22: every gate exits 0 (`run-plugin-tests.sh` scoped to this plugin's
suite); `skill-quality:check` PASS for both skills. Installed-path proof, run with the user's go:
the worktree's marketplace is named `melodic-software`, the same as the user's registered remote
one, so a throwaway local-scope marketplace `gaming-test` served the HEAD tree instead.
`claude plugin install gaming@gaming-test --scope local` exited 0; the selftest from
`~/.claude/plugins/cache/gaming-test/gaming/0.1.0/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1` printed
`SELFTEST OK`; `claude plugin uninstall` exited 0 and a marker in `Documents\Gaming` plus the
runtime DLL survived. Cleanup: marketplace removed, cache copy and marker deleted, user
`settings.json`, `installed_plugins.json` and `known_marketplaces.json` byte-identical to pre-test
backups.

This phase also closes acceptance criteria 1 and 3, which no earlier phase reached: criterion 1
says the selftest runs from a MARKETPLACE-INSTALLED path, not from the worktree, and criterion 3
says `data_dir` files survive `claude plugin uninstall gaming`. A selftest that only ever ran from
`plugins/gaming/` proves the script works, not that the plugin installs.

Work items:

- [ ] Run the full local gate set and fix every finding. The list below is every gate `ci.yml`
      runs that a new plugin directory can trip; each was confirmed present and its invocation read
      from `.github/workflows/ci.yml` this session.
- [ ] Regenerate `docs/catalog.md` with `node scripts/generate-catalog.mjs`, then verify with
      `--check`. Never hand-edit it.
- [ ] Invoke `skill-quality:check plugins/gaming` via the Skill tool and fix every finding; it is
      a skill, not a shell script.
- [ ] Re-run `python3 scripts/sync-plugin-options-docs.py --check` after any manifest change.
- [ ] Install from the marketplace and prove the plugin works from its installed root:
      `claude plugin install gaming@melodic-software --scope local` (the marketplace `name` is
      `melodic-software`, read from `.claude-plugin/marketplace.json:3`). Pre-merge, the published
      marketplace has no `gaming` entry, so this needs a local-path marketplace registration of
      the worktree first (`claude plugin marketplace add <worktree path>`); confirm the exact form
      against the current Claude Code plugin docs before running, since the local registration
      may collide with the already-added remote `melodic-software` marketplace name. Then run the selftest
      from the INSTALLED path rather than the worktree path, and record the resolved
      `${CLAUDE_PLUGIN_ROOT}` used.
- [ ] Prove uninstall survival: create a marker file under the resolved `data_dir`, run
      `claude plugin uninstall gaming`, and assert the marker and any real `state\`, `runtime\`,
      `builds\` content still exist. This is the whole reason constraint 2 forbids
      `${CLAUDE_PLUGIN_DATA}`, and it has never been tested.

| File | Action | What changes |
|---|---|---|
| `docs/catalog.md` | Modify | regenerated, never hand-edited |
| `plugins/gaming/**` | Modify | gate findings fixed in place |

**Sanity Check:** each of these exits 0:
`node scripts/validate-plugin-contracts.mjs`;
`bash scripts/validate-plugins.sh`;
`node scripts/generate-catalog.mjs --check`;
`node scripts/generate-cheatsheet.mjs --check`;
`bash scripts/check-plugin-manifest-presence.sh`;
`bash scripts/check-plugin-catalog-enablement.sh`;
`bash scripts/check-changelog-parity.sh --check`;
`bash scripts/check-skill-leaf-names.sh --check`;
`bash scripts/check-skill-count-claims.sh --check`;
`bash scripts/check-orphaned-fixtures.sh --check`;
`bash scripts/check-purged-em-dashes.sh`;
`python3 scripts/sync-plugin-options-docs.py --check`;
`python3 scripts/check-manifest-duplicate-keys.py`;
`bash scripts/check-changed-skills.sh origin/main`;
`bash scripts/check-skill-portability.sh origin/main`;
`bash scripts/check-shell-portability.sh origin/main`;
`bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/gaming/skills/*/evals/evals.json`;
`bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/*/skills`;
`npx markdownlint-cli2 --config .markdownlint-cli2.jsonc "plugins/gaming/**/*.md"`;
`bash scripts/run-plugin-tests.sh`;
`pwsh -NoProfile -File plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1 -Verb selftest`.
And `skill-quality:check plugins/gaming` reports PASS for both skills.
And the installed-path proof, in order:
`claude plugin install gaming@melodic-software --scope local` exits 0;
`ls "$HOME/.claude/plugins/cache/melodic-software/gaming/0.1.0/skills/dlss5/scripts/"` lists
`Invoke-Dlss5Mod.ps1` (the cache layout is `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`,
read off an installed plugin on this machine; the version is the `0.1.0` Phase 1 puts in the
manifest). This `ls` is the precondition, not a formality: if `--scope local` installs somewhere
else, it fails loudly here and the implementer reports the real path rather than guessing;
`pwsh -NoProfile -File "$HOME/.claude/plugins/cache/melodic-software/gaming/0.1.0/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1" -Verb selftest`
prints `SELFTEST OK`, and the literal path used is recorded in the phase's verification note;
`claude plugin uninstall gaming` exits 0 and the `data_dir` marker file still exists.

Two of the gates above live under `plugins/skill-quality/scripts/`, NOT under `scripts/`.
`scripts/check-evals-quality.sh` and `scripts/check-listing-budget.sh` do not exist; `ci.yml:1245`
and `ci.yml:1261` invoke them from the plugin path. Running the wrong path is a silent skip.

### Phase 8: Commit and open the draft PR [TODO]

Work items:

- [ ] Stage surgically; never `git add -A`. The `.work/` tree is gitignored and must stay
      untracked. Before each commit, run the binary guard in the Sanity Check below. The
      `plugins/gaming/.gitignore` written in Phase 1 is the first line; the staged-set grep is the
      second, because a `git add -f` or an ignore file edited later bypasses the first.
- [ ] Commit in the repo's Conventional Commits form, the ERE the commit convention's resolver
      owns. Suggested boundaries following Tidy First (structural before behavioral): one
      `feat(gaming): scaffold the gaming plugin and register it` for Phase 1, one
      `feat(gaming): port the DLSS 5 mod script with configurable data dir` for Phases 2, 3 and 6,
      one `test(gaming): run the DLSS 5 selftest through the plugin test runner` for
      `Invoke-Dlss5Mod.test.sh`, which is a shell test and does not belong under a `docs:` subject,
      one `docs(gaming): add the dlss5 router skill, reference docs, and evals` for the rest of
      Phases 4 and 5, one `chore: regenerate the catalog for the gaming plugin` for Phase 7.
- [ ] Push `feat/dlss5-plugin` and open the PR with `gh pr create --draft`. AGENTS.md: "Open every
      pull request as a draft and flip it to ready when the work is done."
- [ ] PR body sections `## Summary` and `## Test plan`, which is what the pr-body convention's
      built-in scaffold requires when no layer sets `pr_body_required_sections`. The Test plan
      lists the gate commands from Phase 7 with their observed results.

| File | Action | What changes |
|---|---|---|
| (no file edits) | KEEP | git and gh operations only |

**Sanity Check:** `git diff --cached --name-only | grep -iE '\.(dll|zip|exe)$'` returns nothing
(exit 1), run before every commit in this phase, not once at the end;
`gh pr view --json isDraft --jq .isDraft` returns `true`;
`git status --porcelain` shows nothing under `.work/`;
`git log --oneline origin/main..HEAD` shows every subject matching
`^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+`.

## Test strategy

Three test boundaries, all of them existing surfaces except the first, which is extended:

1. **`Invoke-Dlss5Mod.ps1 -Verb selftest`** (existing, extended). The primary boundary. It drives
   the script's public verb surface against temporary fixture directories and asserts on
   observable file-system state, not on internals. It is the boundary acceptance criterion 1
   names, so it must run with no arguments beyond `-Verb selftest` and must leave nothing behind.
2. **`skills/*/evals/evals.json`** (new). The model-behavior boundary: does the skill route the
   right action, refuse the right game, and follow the reference doc rather than restating it.
   These are model-graded and are not run by this plan; `skill-quality:check validate-evals`
   lints their shape.
3. **The repo gate scripts** (existing). The contract boundary: manifest presence, catalog
   enablement, changelog parity, plugin contracts, skill leaf names, cheatsheet, options-doc
   freshness, eval quality, listing budget, markdown lint, shell and skill portability. Listed
   with exact commands in Phase 7.

**The CI gap, stated plainly.** No lane in this repository runs a `.ps1` file.
`.github/workflows/test-windows.yml` is the only Windows job and it runs the shell and python
filter groups only; its sole `pwsh` mentions are in a comment explaining that PowerShell logic is
tested through `lib/powershell/ps-command.sh` on Linux. `scripts/run-plugin-tests.sh:191`
discovers `plugins/**/*.test.sh` and nothing else. So the selftest that carries every correctness
claim in this plan would run on a developer's machine and never in CI.
Close it the cheap way: `plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.test.sh`, a shell
wrapper that runs `pwsh -NoProfile -File ... -Verb selftest` when `pwsh` is on PATH and prints a
SKIP otherwise. `run-plugin-tests.sh` then picks it up by discovery with no workflow change.
On the Linux runners it will SKIP, so it buys ordering and discoverability rather than coverage;
the coverage arrives whenever a Windows test lane exists. Check
`scripts/check-discriminating-test-skips.sh` and `scripts/check-silent-skips.sh` accept the skip
form before writing it, since both gates exist to catch exactly this shape.

**TDD.** Extend the selftest with the new cases for parameterization and `assess` BEFORE porting
the behavior. Concretely, in Phase 2 add the `DataDir`-default, literal-token, state-location and
anti-cheat-refusal assertions and run the selftest to see them FAIL against the copied-but-
unmodified script, then make them pass. In Phase 3 add the three `assess` fixture assertions and
see them fail against a script with no `assess` verb, then add the verb.

**What the selftest must cover after the port**, beyond the nine assertions it already carries:
default `DataDir` when the parameter is empty; default when the parameter is the unexpanded
`${user_config.data_dir}` token; state written under the passed `DataDir` and nowhere under
`$PSScriptRoot`; `apply` refusing an anti-cheat fixture with zero files copied; `apply`
auto-snapshotting when no snapshot exists; `assess` refusing an anti-cheat fixture, reporting a
`dxgi.dll` collision, passing a clean fixture, and writing no state; `refetch` producing parseable
JSON with `gh` unavailable.

**Edge cases already covered and that must not regress:** BOM and CRLF preservation through
`Edit-Ini`; section-aware ini editing that leaves `[Upscalers] Enabled` alone while setting
`[DlssNr] Enabled`; `[DlssNr] AutoCapture` set to `false`, which constraint 7 requires and which
the current script both writes (`game-mod.ps1:131`) and asserts (`game-mod.ps1:247`), so the port
must keep both halves; byproduct classification; re-apply refusal; destination-collision refusal
before any copy; byte-identical tree restoration after `remove`.

**Known limitation, carried not fixed:** `snapshot` and `status` hash every file in the exe
directory. A large install makes both slow enough that `status` is not a poll loop. Recorded in
the `dlss5` SKILL.md gotchas; incremental hashing keyed on size and last-write time is the upgrade
path if it ever matters.

**Not tested, deliberately:** anything requiring a real NVIDIA driver, a real game, or the
proprietary DLL. The selftest fabricates a fake model DLL and hashes it at fixture-build time, so
the hash gate is exercised without the real binary. File-version reads cannot be faked with text
fixtures, so `assess` asserts DLSS DLL presence only, not version parsing.

## Files affected

Twenty-four rows, so a checkbox inventory.

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/gaming/.claude-plugin/plugin.json` | CREATE | manifest, three userConfig options |
| [ ] `plugins/gaming/.gitignore` | CREATE | `*.dll`, `*.zip`, `*.exe`, `state/`, `runtime/`, `builds/` |
| [ ] `plugins/gaming/README.md` | CREATE | Windows-only, legal scope, generated options block |
| [ ] `plugins/gaming/CHANGELOG.md` | CREATE | `## [0.1.0]`, required by the parity gate |
| [ ] `plugins/gaming/skills/dlss5/SKILL.md` | CREATE | action router |
| [ ] `plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.ps1` | CREATE | the ported script |
| [ ] `plugins/gaming/skills/dlss5/reference/tuning-guide.md` | CREATE | tuning baseline |
| [ ] `plugins/gaming/skills/dlss5/reference/reversal-matrix.md` | CREATE | what remove touches |
| [ ] `plugins/gaming/skills/dlss5/reference/anticheat-posture.md` | CREATE | refusal policy |
| [ ] `plugins/gaming/skills/dlss5/reference/upstream-watch.md` | CREATE | watch items |
| [ ] `plugins/gaming/skills/dlss5/reference/fork-comparison.md` | CREATE | fork choice, both pinned hashes |
| [ ] `plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.test.sh` | CREATE | shell wrapper so `run-plugin-tests.sh` discovers the selftest |
| [ ] `plugins/gaming/skills/dlss5/evals/evals.json` | CREATE | router eval cases |
| [ ] `plugins/gaming/skills/setup/SKILL.md` | CREATE | check/apply |
| [ ] `plugins/gaming/skills/setup/reference/ledger-template.md` | CREATE | ledger seed, under the skill that seeds it |
| [ ] `plugins/gaming/skills/setup/evals/evals.json` | CREATE | setup eval cases |
| [ ] `.claude-plugin/marketplace.json` | MODIFY | one catalog entry |
| [ ] `.claude/settings.json` | MODIFY | one `enabledPlugins` key |
| [ ] `scripts/cheatsheet-config.mjs` | MODIFY | one `EXCLUDED_PLUGINS` entry |
| [ ] `scripts/em-dash-purged-paths.txt` | MODIFY | four `plugins/gaming/` paths appended |
| [ ] `docs/catalog.md` | MODIFY | regenerated by `generate-catalog.mjs`, never hand-edited |
| [ ] `.work/dlss5/tool/game-mod.ps1` | KEEP | the source to read; gitignored, not moved or deleted |
| [ ] `.work/dlss5/tool/LEDGER.md` | KEEP | the format reference; gitignored |
| [ ] `.work/dlss5/research/**` | KEEP | sourced from for `reference/`; gitignored, never committed |

Not touched and deliberately so: `plugins/kindle-dedrm/**` and `plugins/machine-health/**` are
read as analogues only. `scripts/skill-leaf-name-registry.txt` needs no edit: `setup *` at line 34
pre-authorizes the `setup` leaf for an open owner set, and `dlss5` collides with nothing.

## Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Plugin root `dlss5` or `optiscaler` instead of `gaming` | Settled in the handoff: too narrow and tied to one fork's name; NVIDIA is adding native DLSS 5 per game, so the mod path is short-lived while the namespace is not | Only if the user decides the plugin will never hold a second gaming capability |
| Five physical skill directories, one per verb | Settled in the handoff: the action-router precedent is `source-control:worktree` and `kindle-dedrm:manage`; five directories multiply the listing budget for one capability | If the actions stop sharing state and safety rules, so a router adds indirection rather than removing it |
| Read `CLAUDE_PLUGIN_OPTION_DATA_DIR` from the environment inside the script | `docs/extensibility-contract-smoke-tests.md` Test B proves a skill-invoked Bash-tool subprocess does not inherit those variables. The script would silently fall back to defaults and write state where the user did not ask | If a future harness release makes the export reach skill-spawned subprocesses and the smoke-test record is updated to say so |
| Store the ledger and DLL under `${CLAUDE_PLUGIN_DATA}` | Constraint 2: the directory is deleted on uninstall by default, and the same smoke test shows the token is not a dependable per-plugin signal in a Bash-tool subprocess anyway | Never, while uninstall deletes it by default |
| Use each fork's `Remove_OptiScaler.bat` for uninstall | Settled in the handoff: it leaves the DLL, the forwarder, `dlssnr-capture\` and the README behind | If a fork ships a removal that a manifest diff proves byte-exact |
| A bash wrapper so the skill can call one command on any OS | The work is Windows-inherent (Windows binaries, Windows game paths, `nvidia-smi`), and the machine-health precedent is a direct `pwsh -NoProfile -File` call | If a non-Windows DLSS path ever exists |
| Parse Steam's `appinfo.vdf` in pwsh for the anti-cheat section | Binary format, no stable parser, and the same fact is on the Steam store page the SKILL.md can WebFetch | If a maintained pwsh VDF parser becomes a dependency the repo already carries |
| A `tune` script verb that edits `OptiScaler.ini` | The fork's in-game overlay already rewrites that file on Save Settings, so a script-side editor would fight it. Prose over `reference/tuning-guide.md` is smaller and correct | If users need to pre-set ini values headlessly across many games at once |
| Keep fork build sources as configured absolute paths rather than `<DataDir>\builds\` | A third userConfig option for something `setup apply` can provision, and it reintroduces a machine-specific path into the manifest's `$Builds` table | If users need to point at a build tree they manage themselves, at which point add one `-BuildsDir` parameter rather than a per-fork option |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A user runs `apply` on an anti-cheat game without running `assess` | Med | High (account action) | The refusal lives inside `Do-Apply` with no `-Force` bypass, not only in `assess`. Phase 2 selftest case asserts it |
| The unexpanded `${user_config.data_dir}` token reaches a shell command line, where Bash reads it as an invalid parameter expansion and the command dies with `bad substitution` before pwsh starts | High (it is the unset case) | High (the skill is broken for every user who never set the option) | Primary mitigation is the "Resolving paths (do this first)" table in both SKILL.md bodies: the model resolves the option and types a literal path, so no token ever reaches a command line. The script's literal-token branch, with its selftest case, is the second line for a caller that passes the token anyway |
| The proprietary DLL is committed by an over-broad `git add` | Low | Critical (license exposure on a marketplace) | Surgical staging only, never `git add -A`; the DLL lives under `data_dir`, outside the repo; Phase 8 sanity check greps the staged set |
| A selftest run writes into `${CLAUDE_PLUGIN_ROOT}` or the user's real `data_dir` | Med | Med (a plugin update wipes it, or the user's state is polluted) | Selftest builds its own temporary `DataDir`; Phase 2 sanity check asserts `git status --porcelain` shows no new directory under the scripts path |
| `generate-catalog.mjs` or `generate-cheatsheet.mjs` has a requirement for a new plugin this plan did not find | Med | Low (a failing local gate, caught before PR) | Phase 1 runs both gates immediately after scaffolding, before any skill body exists, so the failure surfaces at its cheapest point |
| Fork releases move or are deleted, so `setup apply` cannot populate `builds\` | Med (one author announced a hiatus) | Med | `setup check` reads the `.provisioned.json` marker: empty and unmarked is INFO with the manual path, empty and marked is FAIL. `reference/fork-comparison.md` records both forks, both pinned tags and both SHA-256 values, so a deleted release is recognisable rather than merely missing |
| A mid-copy failure leaves a half-modded game folder with no manifest, so `remove` refuses to touch it | Low | High (user cannot undo the install with the tool that made it) | `pending.json` written before the first copy, a try/catch that deletes what it copied, and `remove`/`status` treating the file as a manifest. Selftest case asserts byte-identical restoration after an injected throw |
| Two game directories share one `GameKey`, so `apply` restores from the wrong snapshot | Low off Steam, Med for two-exe-dir games | High (damaged game files) | Path-hashed key, `gameDir` recorded in both records, and a refusal when the resolved directory does not match the recorded one |
| The pinned runtime hash blocks every user on a newer NVIDIA runtime, so they edit the constant | High over time | Med (the gate stops being a gate) | Authenticode check plus `-AllowUnknownRuntime`, with the observed hash recorded in the manifest. The escape is a flag, not a source edit |
| The selftest never runs in CI, so the port's safety assertions rot unnoticed | High (no `.ps1` lane exists today) | Med | Stated as a gap in the Test strategy rather than assumed away; the `*.test.sh` wrapper puts the suite in `run-plugin-tests.sh` discovery so it runs the moment a Windows test lane exists |
| The ported script drifts from the proving-ground original and breaks a live install | Low | High (damaged game files) | The port is a copy plus named edits, the selftest's byte-identical-restoration assertion is kept, and nothing in this plan touches the seven already-applied game folders |
| Volatile specifics in the SKILL.md go stale (DLL version, fork tags, driver) | High | Low | `.claude/rules/skill-bodies-state-current-rules.md` four-part verification records, plus the `refetch` action that exists to refresh them |

## Blast radius

Blast radius: MEDIUM. New plugin, 20+ files, isolated (defaultEnabled false, no hooks), but
apply/remove write into game folders and the plugin is a marketplace surface. Stress-test: run
(fresh-context devils-advocate), findings folded in.

## Stress-test summary

Two fresh-context reviews ran: a plan reviewer and a devils-advocate stress test. Every repo
citation in the draft held; two of the reviews' own citations did not and are corrected below.
The five findings that changed the plan's shape:

1. **The SKILL.md command line was a guaranteed crash when the option is unset.**
   `-DataDir "${user_config.data_dir}"` on a Bash command line is a `bad substitution`, so the
   script's literal-token fallback could never run. Fixed by resolving both options model-side in
   a "Resolving paths (do this first)" table, machine-health's shape, with the script branch kept
   as defense in depth.
2. **The anti-cheat scan looked in the wrong directory.** `EasyAntiCheat\` sits at the game root;
   the exe is two or three levels below it. Fixed: scan from the `steamapps\common\<X>` segment or
   up to four ancestors, with the token list owned by `reference/anticheat-posture.md`.
3. **`apply` had no rollback and `GameKey` collided.** A throw mid-copy left a half-modded folder
   with no record, and two non-Steam installs ending in `Win64` shared one state directory. Fixed
   with `pending.json` plus a try/catch, and a path-hashed key with a recorded `gameDir`.
4. **Download, hash-verify and extract lived in SKILL.md prose, outside the only testable
   boundary,** and the byproduct list omitted `OptiScaler.asi` so `remove` left it behind forever.
   Fixed with a `provision` script verb over a local zip fixture, and by making
   `reference/reversal-matrix.md` the single source `IsByproduct` matches row for row.
5. **Acceptance criteria 1 and 3 mapped to no phase, and no CI lane runs a `.ps1` file.** Fixed:
   Phase 7 now installs from the marketplace, runs the selftest from the installed root, and
   proves `data_dir` survives uninstall; a `*.test.sh` wrapper makes `run-plugin-tests.sh`
   discover the selftest, and the coverage gap is stated in the test strategy rather than papered
   over.

Two review claims did NOT hold against the sources and were corrected, not applied as written.
The Dagherbou asset is on tag `v0.2.0-patch1`, not `v0.2.0-dlssnr` (`gh api` read this session;
`v0.2.0-dlssnr` is an older release carrying a different asset), and `check-evals-quality.sh` and
`check-listing-budget.sh` live under `plugins/skill-quality/scripts/`, not `scripts/`.

## Execution shape

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | plugin.json, .gitignore, README, CHANGELOG, both SKILL.md, marketplace.json, settings.json, cheatsheet-config.mjs, em-dash-purged-paths.txt | 4 and 5 (both SKILL.md) |
| 2 | Invoke-Dlss5Mod.ps1 | 3, 6 |
| 3 | Invoke-Dlss5Mod.ps1 | 2, 6 |
| 4 | dlss5/SKILL.md, dlss5/reference/*, dlss5/evals/evals.json, dlss5/scripts/Invoke-Dlss5Mod.test.sh | 1, 6 (SKILL.md, upstream-watch.md) |
| 5 | setup/SKILL.md, setup/evals/evals.json, setup/reference/ledger-template.md | 1 |
| 6 | Invoke-Dlss5Mod.ps1, dlss5/SKILL.md, dlss5/reference/upstream-watch.md | 2, 3, 4 |
| 7 | docs/catalog.md, plugins/gaming/** | every phase |
| 8 | none (git and gh only) | none |

Phases 4 and 5 now share NO file. The ledger template moved under `skills/setup/reference/`, the
skill that seeds it, so the one overlap the earlier draft carried is gone rather than managed.

### Dependency graph

- Phase 1 gates everything: no other phase has a file to edit until the plugin directory exists.
- Phase 2 gates Phases 3 and 6: both add verbs to the script Phase 2 creates.
- Phase 2 gates Phase 4: the SKILL.md documents the script's actual parameter surface.
- Phase 4 and Phase 5 are fully file-disjoint. `ledger-template.md` lives under
  `skills/setup/reference/` and Phase 5 owns it outright.
- Both Wave B briefs carry the Brief's pinned-literals table verbatim. Phase 4's
  `fork-comparison.md` and Phase 5's `setup` body both quote the same tags, assets and hashes, and
  a literal copied twice from one table is the cheapest way to keep them equal without the two
  agents sharing a file.
- Phase 6 touches files Phase 4 writes, so it follows Phase 4 rather than running beside it.
- Phase 7 reads the whole tree and follows everything.
- Phase 8 follows Phase 7.
- Integration-first: among the phases not forced by a dependency, Phase 2 comes before Phases 4
  and 5 because it is the slice that proves acceptance criterion 1 end to end.

### Recommended shape

> Wave A (sequential): Phase 1 → Phase 2 → Phase 3
> Wave B (two parallel sub-agent workers, single message, after Wave A returns): Phase 4 and
> Phase 5. They share no file; the ledger template lives under `skills/setup/reference/`.
> Wave C (sequential after Wave B returns): Phase 6 → Phase 7 → Phase 8
> Cost note: two parallel agents in Wave B roughly double token usage for that wave against
> running the two phases back to back. The user picks consciously; the sequential fallback below
> costs only wall-clock.

### Scope-fencing tables

| Agent | Phase | ALLOWED files | LOC |
|---|---|---|---|
| A1 | 4 | `plugins/gaming/skills/dlss5/SKILL.md`, `plugins/gaming/skills/dlss5/reference/{tuning-guide,reversal-matrix,anticheat-posture,upstream-watch,fork-comparison}.md`, `plugins/gaming/skills/dlss5/evals/evals.json`, `plugins/gaming/skills/dlss5/scripts/Invoke-Dlss5Mod.test.sh` | ~650 |
| A2 | 5 | `plugins/gaming/skills/setup/SKILL.md`, `plugins/gaming/skills/setup/evals/evals.json`, `plugins/gaming/skills/setup/reference/ledger-template.md` | ~300 |

**Each agent FORBIDDEN:** any file outside its ALLOWED list; `PLAN.md` (main session edits status
only); the other agent's territory; `Invoke-Dlss5Mod.ps1`; `.claude-plugin/marketplace.json`;
`.claude/settings.json`; `scripts/**`; `docs/catalog.md`; staging, committing, or pushing.

**Each agent reports at end:** work items completed, per-criterion Sanity Check verdict, actual
LOC delta.

**Divergence escalation (copy into every worker brief verbatim):**

```text
DIVERGENCE ESCALATION (mandatory): if reality diverges from this brief, so
a precondition fails, a file/symbol named here is absent or different than
described, scope is blocked, or a design question arises mid-task, STOP.
Do not improvise, fix forward, or expand scope. Report to the orchestrator:
what you found, what the brief expected, and the exact state of your work
(files touched, edits applied / not applied). Await a revised brief.
```

### Sequential fallback

If a scope-fence violation, a concurrent-edit race, or a cannot-complete report arrives from
either Wave B agent, abort that agent and run Phase 4 → Phase 5 sequentially in the main session.
The other agent continues.

### Per-phase routing table

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | Touches three repo-wide files (marketplace, settings, cheatsheet config) whose insertion points need judgment; short |
| 2 | main-session | The safety-critical port; TDD loop with repeated selftest runs and judgment on every deviation from the original |
| 3 | main-session | New behavior on the same file Phase 2 just changed; fixture design needs judgment |
| 4 | sub-agent worker | Mechanical authoring over a settled outline, file-disjoint from Phase 5, high volume (six documents) |
| 5 | sub-agent worker | Mechanical authoring against an explicit contract (validate-plugin-contracts lines 186-235), file-disjoint from Phase 4 |
| 6 | main-session | Touches files both Wave B agents produced; needs the whole picture |
| 7 | main-session | Gate triage: each failure needs a judgment call on where the fix belongs |
| 8 | main-session | Commit boundaries and the PR body need the conversation's context; git operations stay with the user's session |

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| [EXEC-SHAPE] The plugin does not use `${CLAUDE_PLUGIN_DATA}` at all. The refetch cache lives at `<DataDir>\cache\upstream.json` | Phase 6 writes the cache under `data_dir`, not the plugin data directory. It also overrides the handoff's settled bullet "`${CLAUDE_PLUGIN_DATA}` only for cache" | `docs/extensibility-contract-smoke-tests.md` Test B: in a general Bash-tool subprocess `CLAUDE_PLUGIN_DATA` "carries one session default, so it is not a dependable per-plugin signal for a skill-spawned script either". A script that cannot reliably resolve the directory cannot use it, cache or not |
| [EXEC-SHAPE] userConfig reaches the script as `-DataDir` and `-RuntimeDll` command-line arguments, resolved MODEL-SIDE in a "Resolving paths (do this first)" table, never as a `${user_config.*}` token typed onto the command line, and never as `CLAUDE_PLUGIN_OPTION_*` environment reads | Phase 2 gives the script two parameters and a resolver; Phases 4 and 5 open each SKILL.md with the resolution table, and the pwsh line the model then types carries literal absolute paths. A reader diffing this against the earlier draft sees `-DataDir "${user_config.data_dir}"` replaced by `-DataDir "<resolved absolute path>"`. This contradicts the task brief's stated env-var fact and is flagged for override | `docs/extensibility-contract-smoke-tests.md` Test B: "A skill reads a non-sensitive userConfig value only through `${user_config.KEY}` text-substitution into its own Markdown, never from the environment of a script it spawns." The model-side half is `plugins/machine-health/skills/audit/SKILL.md:18-24`, a table that resolves each root before any command is composed. Writing the raw token into a Bash command line instead makes an unset option a `bad substitution` error, because Bash reads `${user_config.data_dir}` as a parameter expansion with an invalid name and aborts before pwsh runs |
| [EXEC-SHAPE] A `provision` script verb owns download, hash verification and allow-list extraction; SKILL.md prose owns none of it | Phase 3 adds the verb and its selftest cases over a locally built zip fixture; Phase 5's `setup apply` calls the verb instead of describing the steps. The earlier draft had these steps only as `setup` prose | Everything with a correctness claim in this plan lives behind `-Verb selftest`, which is the boundary acceptance criterion 1 names. A skill body cannot be asserted on. The extracted fork trees under `C:\Users\KyleSexton\.work\dlss-5-availability\scratch-*\extracted\` contain `setup_windows.bat`, `setup_linux.sh`, `docs\`, `tests\` and `images\`, so an allow-list is the difference between a clean `builds\` and one holding the interactive installer constraint 6 forbids |
| [EXEC-SHAPE] `provision` downloads by direct release-asset URL, so `gh` is not a prerequisite for setup or apply | Phase 3 uses the pinned URLs from the Brief's literals table; Phase 5's `check` demotes `gh` from a prerequisite to an INFO probe, reworded to say it is needed by `refetch` alone | A public release asset is reachable over plain HTTPS. Making a GitHub credential a precondition for installing a graphics mod is a dependency the work does not need, and `refetch` (`gh api .../releases`) is the only verb that actually calls the GitHub API |
| [EXEC-SHAPE] The anti-cheat scan runs from the game root, not the exe directory, and the token list is owned by `reference/anticheat-posture.md` | Phase 2 and Phase 3 share one scan helper that resolves the root from the `steamapps\common\<X>` segment or by walking up to four ancestors; Phase 4 writes the token list as that file's rows | `EasyAntiCheat\` is installed beside the game root while the executable typically sits under `bin\x64` or `Binaries\Win64`, so a scan rooted at the exe directory returns clean on precisely the titles constraint 5 exists to refuse. `EasyAntiCheat`, `EasyAntiCheat_EOS`, `BattlEye`, `BEService` and `ACE` are each named in `.work/dlss5/research/multiplayer-anticheat/`; any token beyond those is labeled judgment in the reference doc |
| [EXEC-SHAPE] `assess` returns `eligible` with `"requiresWebCheck": true` until the Steam `anticheat_section` has been read, and the router's `apply` row runs `assess` first and stops on `refused` or on an uncleared flag | Phase 3 adds the field to the verdict shape; Phase 4's router table makes `apply` conditional on it | On-disk absence is not absence: server-side and launcher-delivered anti-cheat leave nothing in the install tree. The research corpus names `anticheat_section` as the Steam store field that reports it, and the SKILL.md already has WebFetch |
| [EXEC-SHAPE] `apply` writes `pending.json` before the first copy and rolls back what it copied on any throw; `remove` and `status` treat a leftover `pending.json` as a manifest | Phase 2 work item plus a selftest case asserting a mid-copy throw leaves the tree byte-identical | The manifest is written only after every copy succeeds, so today a throw partway through leaves files in the game folder that no record names. `remove` then refuses to touch them (constraint 3 forbids deleting what is not in the manifest) and the user cannot undo the install with the tool that made it |
| [EXEC-SHAPE] `GameKey` keeps its existing prefix rule and gains an `_<8 hex of the path hash>` suffix, and `gameDir` is recorded in the snapshot and manifest and re-checked on every verb | Phase 2 extends the keying at `game-mod.ps1:37` rather than replacing it, so `Cyberpunk_2077` becomes `Cyberpunk_2077_3f9a1c08`; a selftest case asserts two fixtures both named `Win64` get different keys | The current key is the `steamapps\common\` segment or the leaf directory name. Off Steam, and for a game whose launcher and renderer live in two exe directories, two different folders map to one state directory, and the second `apply` reads the first game's snapshot. A restore from the wrong snapshot damages a game folder, which is the highest-impact failure this tool has. Keeping the prefix costs nothing and keeps the directory identifiable by a human reading `<DataDir>\state\` |
| [EXEC-SHAPE] `setup check` scans for orphaned state, and the README states that changing `data_dir` after an apply is a MOVE of the directory, not a reconfiguration | Phase 5 adds the scan (state directories whose recorded `gameDir` is gone, and a resolved `data_dir` differing from the one a previous run used) and the README sentence | Every manifest lives under `data_dir`. Change the option after applying and the manifests stay at the old root, so `status` and `remove` see a modded game with no state. Constraint 3 forbids `remove` from deleting a file the manifest does not name, so the mod becomes unremovable by the tool that installed it, and the user is left hand-deleting DLLs from a game folder |
| [EXEC-SHAPE] The four new `plugins/gaming/` markdown surfaces are added to `scripts/em-dash-purged-paths.txt` | Phase 1 appends README, CHANGELOG and both SKILL.md paths, after reading the file's own header to confirm the two documented conditions | That file's header states it is an allowlist of surfaces already purged of em dashes, that "ADDING AN ENTRY is the last step of purging a surface, in the same pull request that purges it", and that a path not on the list is merely unenforced. Files written em-dash-free satisfy both conditions by construction, so the only cost is four lines and the gain is that they cannot silently regress |
| [EXEC-SHAPE] `reference/reversal-matrix.md` is the single source for byproduct classification, and `IsByproduct` matches its rows exactly, `OptiScaler.asi` included | Phase 2 adds the pattern and one selftest case per row; Phase 4 writes the matrix as the source | `IsByproduct` at `game-mod.ps1:54-55` lists `OptiScaler.log`, `dlssnr-capture\*` and `OptiScalerProfiles\*` only. `.work/dlss5/research/tool-currency/RESEARCH-cleanliness.md:83` records `OptiScaler.asi` among the files the fork's own removal script deletes, so the plugin's `remove` leaves it behind and `status` reports it as `unknown` forever |
| [EXEC-SHAPE] `snapshot` is dropped from the `-Verb` `ValidateSet`, and `remove -Finish` drops a manifest whose only survivors are unknown leftovers | Phase 2 removes one `ValidateSet` entry and adds the `-Finish` path | With `apply` auto-snapshotting, a user-invoked `snapshot` can only overwrite a good pre-install snapshot with a post-install tree, after which `remove` restores the modded state as if it were pristine. The `-Finish` path is the matching escape for a folder the user cleaned by hand, which otherwise keeps a manifest `status` will contradict permanently |
| [EXEC-SHAPE] `builds\` emptiness is INFO before first provision and FAIL after, decided by a `.provisioned.json` marker | Phase 3 writes the marker; Phase 5's `check` reads it. This resolves a contradiction the earlier draft carried, where the Phase 5 body called it INFO and the Risks table called it FAIL | A check cannot distinguish never-provisioned from provisioned-then-emptied without a record, and the two states need opposite remediation prose. The marker also carries the verified hash, so `check` can report a build provisioned from an unexpected asset |
| [EXEC-SHAPE] The `-DataDir` resolver resolves relative paths to absolute and trims a trailing backslash | Phase 2 adds the branch plus two selftest cases | `docs/extensibility-contract-smoke-tests.md` records that option values are "stored verbatim, not normalized to absolute", that a relative `./realdir` stays `./realdir`, and that "a plugin that needs an absolute path resolves it itself". Without the branch, `data_dir` resolves against whatever working directory the subprocess inherited |
| [EXEC-SHAPE] The default `data_dir` is `[Environment]::GetFolderPath('MyDocuments')` joined with `Gaming`, while the README's prose default stays "Documents\Gaming under your user profile" | Phase 1's manifest description and Phase 2's resolver | `$env:USERPROFILE\Documents` is wrong on any machine where OneDrive Known Folder Move has redirected Documents, which is the default on a Microsoft-account Windows 11 install. The .NET call follows the redirect; the prose default stays readable because a user does not need the API name |
| [EXEC-SHAPE] `Do-Apply` refuses a directory with no `*.exe`, and refuses above 2000 files unless `-Force`; both gates run before the auto-snapshot | Phase 2 work item and two selftest cases | Passing a game root or a library root instead of the exe directory is the easy mistake, and a wrong-directory apply scatters DLLs where `remove` will never look. The 2000 figure is judgment, not measured, which is why it is a `-Force`-overridable warning rather than a hard wall |
| [EXEC-SHAPE] The runtime-DLL gate keeps the known-good hash and adds an Authenticode check; an unknown hash with a valid NVIDIA signature is refused unless `-AllowUnknownRuntime`, and the observed hash is then recorded in the manifest | Phase 2 work item plus a selftest case for the unknown-hash refusal | A single pinned hash binds the plugin to one driver generation. Every user on a newer `nvngx_dlssnr.dll` is either blocked or, more likely, edits the constant, which is the outcome the gate exists to prevent. Signature plus explicit opt-in keeps the default strict while leaving a path that does not involve editing the script |
| [EXEC-SHAPE] The runtime DLL is acquired by `provision -Runtime` in the order configured path, local scan of installed games, `runtime_source`; `runtime_source` is optional, non-sensitive, provider-neutral (a path or a plain `https://` URL), and refuses any URL with a query string | Phase 1 adds the third userConfig option; Phase 2 adds `-RuntimeSource`; Phase 3 adds the verb and three selftest cases; Phase 5's `check` reports what `apply` would find and `apply` calls the verb. Constraint 1 is reworded (approved 2026-09-22) | The goal amendment of 2026-09-21 ("it's gotta be generic, apply to any machine, user, organization") rules out a runtime reachable only by a hand-set path. The scan is zero-config wherever a native DLSS 5 title is installed, which is how this machine's copy was obtained (NBA 2K27, `data\streamline\`). `.work/azure-artifact-store/RESEARCH.md:148-150` proposed an `az` branch for Azure blob URLs; the user overruled it on 2026-09-22 ("I don't want the plugin to ship with a preconceived opinionated notion that it involves azure storage"), so private stores are synced to a path by the user's own tooling. `docs/extensibility-contract-smoke-tests.md:88` makes a sensitive option unreachable from a skill, so the value lands in plain `settings.json`, and a signed-URL query string there is a stored credential |
| [EXEC-SHAPE] The router puts an explicit confirmation gate on `apply` and `remove`, and the empty-argument auto-detect row may only recommend or run `status` | Phase 4's router table and a confirmation step before each of the two writing actions | `plugins/kindle-dedrm/skills/manage/SKILL.md:35` ("Never commit to setup/sync/cleanup without user confirmation when ambiguous") and `:43` ("Never recommend `--no-confirm` flags or batch-confirm cleanup") set the precedent for a router whose actions mutate state the user cares about. These two write into game folders the plugin did not create |
| [EXEC-SHAPE] `refetch` merges into the cache rather than overwriting it: an unresolved item keeps its prior `found` value and prior `Checked` timestamp and carries the new `error` beside them | Phase 6 work item and its selftest case | A wholesale overwrite means one run on a machine without `gh` erases every known version the ledger is diffed against, and the next successful run then reports every watch item as changed |
| [EXEC-SHAPE] `status` exits 0 for manifest-listed expected drift and 1 only for a removed manifest file, a modified manifest file, or a changed non-manifest file | Phase 4 documents the codes; the script implements them | The fork's overlay rewrites `OptiScaler.ini` on Save Settings, which the plan already records as expected. If that alone exits 1, every tuned game reports failure permanently and the exit code stops carrying information |
| [EXEC-SHAPE] `ledger-template.md` lives under `skills/setup/reference/`, not `skills/dlss5/reference/` | Phase 5 owns the file; the Phase 4 and Phase 5 overlap in the matrix disappears | `setup apply` is the only consumer. `docs/plugin-philosophy.md:398-404` requires a full `${CLAUDE_PLUGIN_ROOT}/skills/<other-skill>/<path>` anchor for a cross-skill citation and permits a bare relative path for a skill's own files, so colocating removes both the anchoring work item and the only file two parallel workers would have shared |
| [EXEC-SHAPE] `plugins/gaming/.gitignore` plus a staged-set binary grep before every commit | Phase 1 creates the ignore file; Phase 8's Sanity Check runs `git diff --cached --name-only \| grep -iE '\.(dll\|zip\|exe)$'` and expects no output | Constraint 1 makes a committed `nvngx_dlssnr.dll` a licensing incident on a public marketplace. `plugins/ai-briefing/.gitignore` is the existing per-plugin precedent. The grep is the second line because `git add -f` bypasses the first |
| [EXEC-SHAPE] A `*.test.sh` wrapper carries the pwsh selftest into `run-plugin-tests.sh` discovery, and the CI coverage gap is stated rather than closed | Phase 4 writes `Invoke-Dlss5Mod.test.sh`; the Test strategy names the gap | `.github/workflows/test-windows.yml` runs only the shell and python filter groups and mentions `pwsh` solely in a comment; `scripts/run-plugin-tests.sh:191` discovers `plugins/**/*.test.sh` and nothing else. The wrapper SKIPs on Linux, so it buys discoverability now and coverage whenever a Windows test lane exists. Claiming more than that would be the silent skip the repo's own gates exist to catch |
| [EXEC-SHAPE] The resolver treats a value that still begins with the literal `${user_config.` as unset and falls back to the default | Phase 2 adds that branch and two selftest cases for it | `plugins/machine-health/skills/audit/SKILL.md:24`: "if it is empty or still shows an unexpanded `${user_config.report_dir}` token (option unset), default to `$env:USERPROFILE\Documents\MachineHealth`" |
| [EXEC-SHAPE] The anti-cheat refusal is enforced inside `Do-Apply`, not only in `assess` | Phase 2 adds the guard and its selftest case; `assess` in Phase 3 keeps the fuller report | Constraint [h1] 5 says never install into an anti-cheat game. `assess` is skippable, `apply` is the path that copies files, so the guard belongs where every caller passes |
| [EXEC-SHAPE] `snapshot` is not a router action; `apply` auto-snapshots when no snapshot exists | Phase 2 folds it in; the Phase 4 router table has six rows, not seven. The row above goes further and drops the verb from the script's `ValidateSet` entirely | The handoff settles the action list as assess/apply/remove/status/tune/refetch, and the current script already refuses `apply` without a snapshot, so the only question is who runs it |
| [EXEC-SHAPE] `tune` is SKILL.md prose over `reference/tuning-guide.md`, with no script verb | Phase 4 writes the action as prose; no `Edit-Ini` entry point is exposed | The handoff's Side effects record: "Cyberpunk's `OptiScaler.ini` was rewritten by the overlay's Save Settings". The fork's overlay owns that file at runtime, so a script-side editor would be overwritten |
| [EXEC-SHAPE] `refetch` covers only what a shell can resolve (`gh api`, `nvidia-smi`, local file version) and writes JSON; the page-backed items stay WebFetch steps in the SKILL.md | Phase 6 stays thin; no HTML parsing is written in pwsh | The ledger's Upstream watch table already splits the items this way: two `gh api` commands, one `nvidia-smi`, one `Get-Item ... VersionInfo`, and two URLs |
| [EXEC-SHAPE] Ledger rows are written by the model with Edit, not by the script | Phases 4 and 6 put ledger writes in the SKILL.md; the script emits the facts | `.work/dlss5/tool/LEDGER.md`: "Filled by hand; `game-mod.ps1` writes the machine-readable half to `state\<GameKey>\manifest.json`" |
| [EXEC-SHAPE] `.claude/settings.json` gets `"gaming@melodic-software": false` | Phase 1 adds one key between `fleet@` and `playgrounds@` | `scripts/check-plugin-catalog-enablement.sh` header: "A key set to `false` PASSES. An explicit `false` is a recorded decision". The plugin is Windows-only and needs a proprietary local DLL, so a cloud session must not install it. `playgrounds@melodic-software` is the existing `false` precedent |
| [EXEC-SHAPE] `gaming` is added to `EXCLUDED_PLUGINS` in `scripts/cheatsheet-config.mjs` with the reason "personal-domain plugin" | Phase 1 adds one map entry, without which the cheatsheet gate fails | `scripts/cheatsheet-config.mjs`: "an in-scope skill must carry `workflow-stage` XOR appear here; the generator fails on silent omission". `kindle-dedrm`, `machine-health` and `songwriting` all carry that exact reason string |
| [EXEC-SHAPE] Phase 1 writes both SKILL.md files with valid frontmatter and a minimal body rather than leaving the skills directory empty | Phase 1's sanity check can run `validate-plugin-contracts.mjs` and the cheatsheet gate meaningfully; Phases 4 and 5 fill bodies | The contract gates key off `skills/setup/SKILL.md` existing (`validate-plugin-contracts.mjs:102`) and the cheatsheet generator walks skills. A skill-less plugin leaves both gates asserting nothing |
| [EXEC-SHAPE] Wave B runs Phases 4 and 5 as two parallel sub-agent workers | The routing table and scope fences above | The overlap matrix shows the two phases share no file once `reference/ledger-template.md` is assigned to Phase 5; both are authoring work against settled outlines |

## Open questions

- **[CONFIRMED 2026-09-22, recommendation accepted] Where fork builds live.** The handoff parameterizes
  `data_dir` and `runtime_dll` but says nothing about the fork zips, which are hardcoded to
  `C:\Users\KyleSexton\.work\dlss-5-availability\scratch-*\extracted` at lines 18 and 23 of the
  current script. The plan puts them at `<DataDir>\builds\<build>\`, provisioned by `setup apply`
  calling the new `provision` verb, which downloads the pinned asset by direct release URL and
  verifies SHA-256. That is a new contract surface, so it is a user-approval gate rather than a
  quiet decision. The alternative is a third userConfig option pointing at a build tree the user
  manages, which trades the provisioning work for a third path the user has to keep correct.
  Recommendation: keep `<DataDir>\builds\`.
- **[CONFIRMED 2026-09-22, recommendation accepted] `displayName` in the marketplace entry.** `kindle-dedrm`
  carries `"displayName": "Kindle DeDRM"`; `songwriting` and `machine-health` carry none. The plan
  omits it for `gaming`, because `gaming` already reads as a display name where `kindle-dedrm`
  does not. Confirm or override.
- **[CONFIRMED 2026-09-22, recommendation accepted] Unknown-but-signed runtime refused by default.** A
  `nvngx_dlssnr.dll` whose SHA-256 is not the pinned 310.8.0.0 value, but which carries a valid
  Authenticode signature from `CN=NVIDIA Corporation` and a `FileVersion` at or above 310.8.0.0,
  is REFUSED unless the user passes `-AllowUnknownRuntime`. The alternative is to accept a valid
  NVIDIA signature on its own and record the hash. Strict-by-default is the recommendation because
  the pinned hash is the one thing in this plan that was verified against a working install, and
  an opt-in flag is a cheap escape. Confirm or override.
- **[CONFIRMED 2026-09-22, recommendation accepted] Constraint 1 reworded for runtime acquisition.** The handoff's
  [h1] text says the plugin "references it by configured path plus hash only". `provision -Runtime`
  makes the plugin copy the DLL out of the user's own installed games and, when configured, fetch
  it from the user's own `runtime_source`. The protective intent is unchanged: never committed,
  never bundled, never under `${CLAUDE_PLUGIN_ROOT}`, no source named by the plugin, every copy
  gated. Recommendation: accept the reworded constraint 1 in the Brief.

The environment-variable premise is no longer an open question. The task brief's claim that values
reach scripts as `CLAUDE_PLUGIN_OPTION_*` environment variables is contradicted by
`docs/extensibility-contract-smoke-tests.md` Test B for the skill case, and
`sync-plugin-options-docs.py`'s docstring describes that column as "the environment variable each
hook reads it from" while this plugin has no hooks. It is recorded as a gate-passed [EXEC-SHAPE]
decision in the Decisions table, flagged there for override.
- Does `generate-catalog.mjs` require anything of a new plugin beyond the manifest and the
  marketplace entry? Phase 1 answers this empirically by running it before any skill body exists.
- The handoff's own open questions stay open and are out of this plan's scope: whether NR binds on
  games shipping DLSS 3.7, and whether `310.8.2` is a real newer runtime. Both are launch-time
  observations, not plan inputs.

## Handoff to implementation

### User-approval gates

Surface each of these for confirmation before executing past it:

1. The four `[CONFIRMED 2026-09-22, recommendation accepted]` items in Open questions, before Phase 2 begins.
   The builds location and the unknown-runtime posture both change the script's parameter surface,
   so they cannot wait for Phase 5.
1b. The marketplace install, selftest-from-installed-path and uninstall-survival steps in Phase 7
   change machine state outside the worktree: they install and then uninstall a plugin at
   `--scope local`. Surface them before running.
2. Any proposal to widen scope into the handoff's post-merge actions 6 and 7 (migrating the
   proving-ground state, launch verification, the `/schedule` routine). Those are out of scope by
   the Brief.
3. Before the first `git push`: confirm the staged set contains no `.work/` path and no binary.
4. Before flipping the PR out of draft. AGENTS.md wants the flip to be the deliberate act that
   asks for the review lanes; this plan's deliverable ends at the draft.

### Execution shape ([EXEC-SHAPE] tagged)

See the "Execution shape" section above for the wave shape, the scope-fencing tables, the
divergence-escalation clause, the sequential fallback, and the per-phase routing table. No phase
is promoted to its own topic: Phase 4 is the only one near the promotion trigger (six documents)
and it has no independent research need, since every reference doc is sourced from
`.work/dlss5/research/` which already exists.

### Mechanical work

- **Phase tags.** Advance `[TODO]` → `[DOING]` → `[DONE]` in this file as each phase completes.
  PLAN.md is edited by the main session only; no worker touches it.
- **Commit boundaries.** Five commits as listed in Phase 8, structural before behavioral.
- **Verification checkpoints.** Every phase's `**Sanity Check:**` bullet is run and its actual
  output recorded before the phase tag advances. A phase is not `[DONE]` on a command's exit code
  alone when the check names a grep; run the grep.
- **Sequential fallback.** If the Wave B parallel dispatch fails for any reason, run Phase 4 then
  Phase 5 in the main session. Nothing else in the plan changes.
- **Worktree.** All work happens in
  `D:\worktrees\melodic-software-claude-code-plugins-feat-dlss5-plugin` on branch
  `feat/dlss5-plugin`. Do not create a second worktree; the handoff records this one as claimed.
