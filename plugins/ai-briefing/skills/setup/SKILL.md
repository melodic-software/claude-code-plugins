---
name: setup
description: "Scaffold or reconfigure an ai-briefing profile and install the engine's runtime dependencies. Use when: 'set up ai-briefing', 'configure ai-briefing', 'add an ai-briefing profile', 'ai-briefing setup', or before the first /ai-briefing:ai-briefing run in a repo. Idempotent — safe to re-run to reconfigure."
argument-hint: "[--profile <name>] [--with-build-deps]"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Purpose

`ai-briefing` is a generic engine: it ships a neutral default brand and a small **seed** follow-list of public vendor accounts, but the curated inputs and branding for a given audience live in a **profile** in the consuming project. This action interviews the consumer, scaffolds that profile (the "profiled folder" seam), and installs the runtime dependencies the engine needs. It is **idempotent** — re-run it to reconfigure.

## What it configures

The profiled-folder seam. Files at `.claude/ai-briefing/` are the **default profile**; each `.claude/ai-briefing/<name>/` subfolder is a **named profile** overlaying the default per key.

| Artifact | Path | Purpose |
|---|---|---|
| `following-list.json` | `.claude/ai-briefing/[<name>/]` | Curated X/Twitter handles in `scan_priority` buckets. Seeded from the bundled neutral list; tailor it, or run `/ai-briefing:ai-briefing --refresh-following` to scrape your own following graph. |
| `brand.js` (optional) | same | Overlay of org name, tagline, logo asset paths, and theme tokens. Absent → the neutral default brand. |
| `audience.md` (optional) | same | A tech-stack lens that turns on the per-item `impact` tag (see `../ai-briefing/references/audience-defaults.md`). Absent → no impact tag. |

Never write curated config into `${CLAUDE_PLUGIN_DATA}` — that is machine-local run state (seen-items, generated decks), keyed per profile, and is created automatically on first run.

## Task

1. **Resolve the profile name.** Parse `--profile <name>` from `$ARGUMENTS`; otherwise ask, defaulting to the root **default** profile (a single-audience consumer never needs a named subfolder — the root files *are* the default profile). If more than one profile will exist, remind the consumer to set the `active_profile` plugin option or pass `--profile <name>` per run, and to export `AI_BRIEFING_PROFILE=<name>` for the runner/build scripts.

2. **Scaffold the follow-list.** Target dir is `${CLAUDE_PROJECT_DIR}/.claude/ai-briefing/` for the default profile, or `.../<name>/` for a named one. If `following-list.json` is absent there, copy the bundled seed as a starting point; if present, leave it (offer to refresh via the runner). Create the dir as needed.

   ```bash
   SEED="${CLAUDE_PLUGIN_ROOT}/skills/ai-briefing/seed/following-list.json"
   DEST="${CLAUDE_PROJECT_DIR}/.claude/ai-briefing"      # append /<name> for a named profile
   mkdir -p "$DEST"
   [ -f "$DEST/following-list.json" ] || cp "$SEED" "$DEST/following-list.json"
   ```

   Recommend the consumer add `.claude/ai-briefing/**/*.local.*` to their `.gitignore` for personal overlays while keeping team config tracked.

3. **Offer branding + stack lens (optional).** If the consumer wants their own deck branding, scaffold a `brand.js` overlay (org, tagline, logo asset paths, theme) in the profile dir; drop logo assets beside it. If they want the `impact` tag, scaffold `audience.md` describing their stack. Both are optional — skip cleanly when declined.

4. **Stage the runtime and install dependencies (idempotent).** The plugin cache is read-only, and the scripts are Node ESM — which resolves bare imports (`zod`) by walking `node_modules` up from the script file, and does **not** honor `NODE_PATH`. So a persisted `node_modules` beside the read-only scripts is unreachable. Instead, **copy the runnable tree into `${CLAUDE_PLUGIN_DATA}` and install `node_modules` as a sibling there**, then run the scripts from that copy so the standard ESM walk finds the deps. Re-stage when the plugin version changes (the data dir survives updates, so a stale copy would otherwise linger).

   ```bash
   VER=$(node -p "require('${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json').version")
   RT="${CLAUDE_PLUGIN_DATA}/runtime"

   # Runner tree (zod) — required for any briefing run.
   if [ "$(cat "$RT/scripts/.version" 2>/dev/null)" != "$VER" ]; then
     rm -rf "$RT/scripts" "$RT/seed"
     mkdir -p "$RT"
     cp -R "${CLAUDE_PLUGIN_ROOT}/skills/ai-briefing/scripts" "$RT/scripts"
     cp -R "${CLAUDE_PLUGIN_ROOT}/skills/ai-briefing/seed"    "$RT/seed"
     ( cd "$RT/scripts" && npm install --omit=dev --no-fund --no-audit ) && printf '%s' "$VER" > "$RT/scripts/.version"
   fi

   # Build tree (playwright, pptxgenjs, …) — only for --format slides|html. Heavier (~120 MB with the browser).
   if [ "$(cat "$RT/build/.version" 2>/dev/null)" != "$VER" ]; then
     rm -rf "$RT/build"
     cp -R "${CLAUDE_PLUGIN_ROOT}/skills/ai-briefing/output/build" "$RT/build"
     ( cd "$RT/build" && npm install --no-fund --no-audit && npx playwright install chromium --only-shell ) && printf '%s' "$VER" > "$RT/build/.version"
   fi
   ```

   Then invoke the runner and build scripts **from the staged copy** so `zod` resolves via the sibling `node_modules` — e.g. `node "${CLAUDE_PLUGIN_DATA}/runtime/scripts/per-profile-runner.js" …` and `node "${CLAUDE_PLUGIN_DATA}/runtime/build/run.js"`. The scripts' own relative imports (`./lib/*`) and the bundled `seed/` / build `assets/` resolve inside the copy; run state and generated decks still write to `${CLAUDE_PLUGIN_DATA}/<profile>/` via the env-driven path seam. Re-running setup after a plugin update re-stages both trees.

5. **Confirm.** Report the profile path, whether the follow-list was seeded or left intact, which optional overlays were created, and which dependency sets were installed. Point the consumer at `/ai-briefing:ai-briefing` to run their first briefing.

## What this skill does NOT do

- Does not run a briefing — that is `/ai-briefing:ai-briefing`.
- Does not write curated config into `${CLAUDE_PLUGIN_DATA}` (machine state only).
- Does not scrape your following graph — the runner's `--refresh-following` does that.
