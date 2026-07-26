---
name: setup
description: "Verify or configure an ai-briefing profile and, only when explicitly requested, install the deterministic HTML/PDF/PPTX build toolchain. Use when: 'set up ai-briefing', 'configure ai-briefing', 'add an ai-briefing profile', 'is ai-briefing working', or 'ai-briefing setup'. Actions: check (read-only verification, default) | apply (scaffold the profile) | apply install-build-deps (also install the build toolchain). Idempotent — safe to re-run."
argument-hint: "check | apply [install-build-deps] [--profile <name>]"
user-invocable: true
disable-model-invocation: true
---

## Variables

Arguments: `$ARGUMENTS`
Configured active profile: `${user_config.active_profile}`

## Purpose

Bring a repository-owned briefing profile to a working state and, only when explicitly
requested, install the optional deterministic presentation build toolchain. The plugin is
repository- and organization-agnostic; consumers supply their own authorized sources,
audience lens, and branding.

Check-centric per the uniform contract: `check` inspects and reports, `apply` scaffolds the
profile, and the build-toolchain install is a distinct opt-in subaction rather than fused
behind a flag. Tracked profile configuration belongs in the consuming repository — never in
`${CLAUDE_PLUGIN_DATA}`, which is reserved for machine-local state and generated artifacts.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
scaffolds; `apply install-build-deps` additionally authorizes the build-toolchain install
below. `--profile <name>` selects the profile for either action and wins over the configured
active profile. All actions are non-interactive when the profile is unambiguous — never
prompt when the action and profile are given.

## Profile contents

Files at `.claude/ai-briefing/` form the default profile. Each
`.claude/ai-briefing/<name>/` directory is a named profile overlay.

| Artifact | Purpose |
|---|---|
| `sources.md` | Approved RSS/Atom feeds, official release pages, GitHub repositories, and user-supplied URLs. |
| `brand.json` (optional) | Declarative organization name, tagline, local logo assets, and theme tokens. |
| `audience.md` (optional) | Stack/audience lens used for impact annotations. |

## `check` (read-only)

Resolve the profile, then probe its state and the build toolchain and report a
PASS/FAIL/INFO table with one remediation line per FAIL. Do not create, modify, or install
anything.

1. **Resolve the profile.** Parse `--profile <name>` from `$ARGUMENTS`; otherwise use the
   rendered `${user_config.active_profile}` value when non-empty, else the root `default`
   profile. A per-run `--profile` wins. Require a 1-63 character lowercase-kebab slug and
   reject reserved Windows device names. Report the resolved profile path, which of the three
   sources supplied it, and — when the resolved value came from `${user_config.active_profile}` or
   the configured value is wrong for this repository — the reconfiguration route:
   - **Interactive, any time:** `/plugin configure ai-briefing`. This is the only surface that
     changes the stored value; this skill never writes `pluginConfigs`.
   - **Headless:** `claude plugin install ... --config active_profile=<name>` seeds the value on a
     *fresh install only* and is ignored once the plugin is installed, so reconfiguring headlessly
     means `claude plugin uninstall ai-briefing` then `claude plugin install
     ai-briefing@<marketplace> --config active_profile=<name>`.
   - **Neither, for a one-off:** a per-run `--profile <name>` selects a different profile without
     touching stored config.
2. **`sources.md`** — FAIL if the resolved profile has no `sources.md`: `/ai-briefing:generate`
   has no authorized sources to collect from. Remediation: `apply`.
3. **Optional overlays** — INFO: report whether `audience.md` and declarative `brand.json`
   exist; their absence is expected and never a FAIL.
4. **Build toolchain** — INFO unless the consumer intends `--format html`/`--format slides`.
   Report whether the locked runtime at `${CLAUDE_PLUGIN_DATA}/runtime/build` exists and its
   `.version` matches the plugin's `plugin.json` version (a mismatch means a rebuild is due).
   Read-only: never launch a browser here. Missing or stale is INFO with remediation
   `apply install-build-deps`, because the toolchain is opt-in — markdown output needs none
   of it.
5. **Build preflight** — INFO: report `node --version`, `npm --version`, and the OS family
   against Playwright's current supported environment matrix. The README's matrix is a dated
   snapshot (verified against
   [Playwright system requirements](https://playwright.dev/docs/intro#system-requirements));
   the linked page is authoritative — re-check it before installing.

## `apply` (idempotent)

Run `check`, then scaffold the resolved profile. Re-running after everything passes changes
nothing and reports "already configured".

1. **Scaffold authorized sources.** Create the profile directory when absent. If `sources.md`
   does not exist, create it with short sections for official vendor feeds, GitHub
   repositories/releases, reputable secondary sources, and user-supplied URLs. Leave an
   existing file unchanged. Do not seed X handles, navigate X, scrape following graphs, or
   install an X API provider. Note the current X access restriction and link the
   authoritative terms: <https://x.com/en/tos>.
2. **Offer optional overlays.** Offer `audience.md` and declarative `brand.json`, creating only
   the files the consumer requests. Keep local logo assets beside `brand.json`. Recommend a
   project ignore convention such as `.claude/ai-briefing/**/*.local.*` for personal overlays
   while keeping shared profile files tracked.
3. **`apply install-build-deps` — install the optional build toolchain.** Parse the subaction
   before invoking a shell and never interpolate raw arguments into a command. Without it,
   skip this step and change no existing runtime. With it, build and validate a temporary
   locked runtime first, then replace the current runtime with same-filesystem renames. A
   dependency, browser-install, or launch failure must leave the working runtime untouched.
   The plugin cache is read-only, and Node ESM does not use `NODE_PATH` for bare-package
   resolution.

   ```bash
   command -v node >/dev/null 2>&1 || {
     echo "ai-briefing setup requires Node.js" >&2
     exit 1
   }
   command -v npm >/dev/null 2>&1 || {
     echo "ai-briefing setup requires npm" >&2
     exit 1
   }
   NODE_MAJOR=$(node -p "Number(process.versions.node.split('.')[0])")
   case "$NODE_MAJOR" in
     22|24|26) ;;
     *) echo "ai-briefing setup requires the latest Node.js 22.x, 24.x, or 26.x" >&2; exit 1 ;;
   esac
   PLATFORM=$(uname -s)
   case "$PLATFORM" in
     Linux|Darwin|MINGW*|MSYS*|CYGWIN*) ;;
     *) echo "ai-briefing setup does not support platform: $PLATFORM" >&2; exit 1 ;;
   esac

   VER=$(node -p "require('${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json').version")
   RT="${CLAUDE_PLUGIN_DATA}/runtime"
   CURRENT="$RT/build"

   if [ "$(cat "$CURRENT/.version" 2>/dev/null)" != "$VER" ]; then
     mkdir -p "$RT"
     STAGE=$(mktemp -d "$RT/.build-stage.XXXXXX")
     BACKUP="$RT/.build-backup.$$"
     cleanup() { rm -rf "$STAGE"; }
     trap cleanup EXIT INT TERM

     cp -R "${CLAUDE_PLUGIN_ROOT}/skills/generate/output/build/." "$STAGE"
     if ! (
       cd "$STAGE" &&
       npm ci --no-fund --no-audit &&
       case "$(uname -s)" in
         Linux*) npx playwright install --with-deps --only-shell chromium ;;
         *)      npx playwright install --only-shell chromium ;;
       esac &&
       node --input-type=module -e \
         "import { chromium } from 'playwright'; const b = await chromium.launch(); await b.close();" &&
       printf '%s' "$VER" > .version
     ); then
       echo "ai-briefing build setup failed; preserved the existing runtime" >&2
       exit 1
     fi

     rm -rf "$BACKUP"
     if [ -d "$CURRENT" ] && ! mv "$CURRENT" "$BACKUP"; then
       echo "ai-briefing could not preserve the existing runtime; refusing to replace it" >&2
       exit 1
     fi
     if mv "$STAGE" "$CURRENT"; then
       STAGE=""
       rm -rf "$BACKUP"
       trap - EXIT INT TERM
     else
       if [ -d "$BACKUP" ]; then mv "$BACKUP" "$CURRENT"; fi
       exit 1
     fi
   fi
   ```

   `npm ci` uses the committed lockfile and fails on dependency drift. Playwright is retained
   only to render and inspect generated local HTML/PDF artifacts; it must not be used as a
   collection browser. On Linux, Playwright's documented `--with-deps` path installs required
   operating-system packages. Other supported platforms install the browser shell and rely
   on their platform prerequisites. Supported OS and Node targets are whatever
   [Playwright's system requirements](https://playwright.dev/docs/intro#system-requirements)
   currently list (the README's matrix is a dated snapshot of that page — the link is
   authoritative). The launch probe runs before the runtime swap.

   After the install, re-run the `check` build-toolchain probe and report its actual result —
   never claim the toolchain is ready on the swap's exit code alone.

4. **Confirm.** Report the profile path, whether `sources.md` was created or preserved, which
   optional overlays were created, and whether build dependencies were installed or
   intentionally skipped. Point the consumer to `/ai-briefing:generate`.

## This skill does not

- Run a briefing.
- Write curated configuration into `${CLAUDE_PLUGIN_DATA}`.
- Automate X/Twitter access or configure an X API provider.
- Install the optional build tree unless `apply install-build-deps` is invoked.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
