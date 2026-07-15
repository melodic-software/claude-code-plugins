---
name: setup
description: "Scaffold or reconfigure an ai-briefing profile and optionally install the deterministic HTML/PDF/PPTX build toolchain. Use when: 'set up ai-briefing', 'configure ai-briefing', 'add an ai-briefing profile', or 'ai-briefing setup'. Idempotent — safe to re-run."
argument-hint: "[--profile <name>] [--with-build-deps]"
user-invocable: true
disable-model-invocation: true
---

## Variables

Arguments: `$ARGUMENTS`
Configured active profile: `${user_config.active_profile}`

## Purpose

Scaffold a repository-owned briefing profile and, only when explicitly requested, install
the optional deterministic presentation build toolchain. The plugin is repository- and
organization-agnostic; consumers supply their own authorized sources, audience lens, and
branding.

## Profile contents

Files at `.claude/ai-briefing/` form the default profile. Each
`.claude/ai-briefing/<name>/` directory is a named profile overlay.

| Artifact | Purpose |
|---|---|
| `sources.md` | Approved RSS/Atom feeds, official release pages, GitHub repositories, and user-supplied URLs. |
| `brand.json` (optional) | Declarative organization name, tagline, local logo assets, and theme tokens. |
| `audience.md` (optional) | Stack/audience lens used for impact annotations. |

Tracked profile configuration belongs in the consuming repository. Never write it into
`${CLAUDE_PLUGIN_DATA}`, which is reserved for machine-local state and generated artifacts.

## Task

1. **Resolve the profile.** Parse `--profile <name>` from `$ARGUMENTS`; otherwise use the
   rendered `${user_config.active_profile}` value when non-empty, then ask only if profile
   selection remains ambiguous, defaulting to the root `default` profile. A per-run
   `--profile` argument wins. Do not ask the consumer to export an environment variable.
   Require a 1-63 character lowercase-kebab slug and reject reserved Windows device names.

2. **Scaffold authorized sources.** Create the profile directory when absent. If
   `sources.md` does not exist, create it with short sections for official vendor feeds,
   GitHub repositories/releases, reputable secondary sources, and user-supplied URLs. Leave
   an existing file unchanged. Do not seed X handles, navigate X, scrape following graphs,
   or install an X API provider. Note the current X access restriction and link the
   authoritative terms: <https://x.com/en/tos>.

3. **Offer optional overlays.** Offer `audience.md` and declarative `brand.json`, creating only
   the files the consumer requests. Keep local logo assets beside `brand.json`. Recommend a project
   ignore convention such as `.claude/ai-briefing/**/*.local.*` for personal overlays while
   keeping shared profile files tracked.

4. **Install the optional build toolchain only with `--with-build-deps`.** Parse the flag
   before invoking a shell and never interpolate raw arguments into a command. When absent,
   skip this step without changing an existing runtime. When present, build and validate a
   temporary locked runtime first, then replace the current runtime with same-filesystem
   renames. A dependency, browser-install, or launch failure must leave the working runtime
   untouched. The plugin cache is read-only, and Node ESM does not use `NODE_PATH` for
   bare-package resolution.

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

     cp -R "${CLAUDE_PLUGIN_ROOT}/skills/ai-briefing/output/build/." "$STAGE"
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
   on their platform prerequisites. Current supported targets are Windows 11+/Server 2019+,
   macOS 14+, Debian 12/13, and Ubuntu 22.04/24.04/26.04 on x86-64 or arm64, using the latest
   Node.js 22.x, 24.x, or 26.x with npm. The launch probe runs before the runtime swap. See
   <https://playwright.dev/docs/intro#system-requirements>.

5. **Confirm.** Report the profile path, whether `sources.md` was created or preserved,
   which optional overlays were created, and whether build dependencies were installed or
   intentionally skipped. Point the consumer to `/ai-briefing:ai-briefing`.

## This skill does not

- Run a briefing.
- Write curated configuration into `${CLAUDE_PLUGIN_DATA}`.
- Automate X/Twitter access or configure an X API provider.
- Install the optional build tree unless `--with-build-deps` is present.
