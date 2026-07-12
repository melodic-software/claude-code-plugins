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

4. **Install runtime dependencies (idempotent).** Dependencies persist in `${CLAUDE_PLUGIN_DATA}` (the plugin cache is read-only). Always install the runner deps; install the heavier build deps only if the consumer wants HTML/PPTX decks.

   ```bash
   # Runner deps (zod) — required for any briefing run.
   D="${CLAUDE_PLUGIN_DATA}/deps/scripts"; S="${CLAUDE_PLUGIN_ROOT}/skills/ai-briefing/scripts"
   mkdir -p "$D"
   diff -q "$S/package.json" "$D/package.json" >/dev/null 2>&1 || \
     (cp "$S/package.json" "$S/package-lock.json" "$D/" && cd "$D" && npm install --omit=dev --no-fund --no-audit) || rm -f "$D/package.json"

   # Build deps (playwright, pptxgenjs, …) — only for --format slides|html. Heavier (~120 MB with the browser).
   B="${CLAUDE_PLUGIN_DATA}/deps/build"; BS="${CLAUDE_PLUGIN_ROOT}/skills/ai-briefing/output/build"
   mkdir -p "$B"
   diff -q "$BS/package.json" "$B/package.json" >/dev/null 2>&1 || \
     (cp "$BS/package.json" "$BS/package-lock.json" "$B/" && cd "$B" && npm install --no-fund --no-audit && npx playwright install chromium --only-shell) || rm -f "$B/package.json"
   ```

   The `diff` guard makes re-runs a no-op unless a plugin update changed a manifest. Because the runner and build scripts are invoked from the read-only plugin cache, run them with `NODE_PATH` pointed at the persisted modules — e.g. `NODE_PATH="${CLAUDE_PLUGIN_DATA}/deps/scripts/node_modules" node "${CLAUDE_PLUGIN_ROOT}/skills/ai-briefing/scripts/per-profile-runner.js" …` (bare imports like `zod` resolve via `NODE_PATH`; the scripts' own relative imports resolve inside the plugin).

5. **Confirm.** Report the profile path, whether the follow-list was seeded or left intact, which optional overlays were created, and which dependency sets were installed. Point the consumer at `/ai-briefing:ai-briefing` to run their first briefing.

## What this skill does NOT do

- Does not run a briefing — that is `/ai-briefing:ai-briefing`.
- Does not write curated config into `${CLAUDE_PLUGIN_DATA}` (machine state only).
- Does not scrape your following graph — the runner's `--refresh-following` does that.
