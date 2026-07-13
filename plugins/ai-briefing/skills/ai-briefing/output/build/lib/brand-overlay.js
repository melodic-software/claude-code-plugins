// Resolve the active profile's brand.js overlay over the engine's neutral
// default. The emitter reads a single concrete brand (deck `meta` fields) +
// `theme`; a consumer profile supplies a `brand.js` beside its logo assets to
// override org name, tagline, logos, and theme tokens per key.
//
// Contract:
//   - Absent profile brand.js  -> neutral default returned unchanged (the
//     common unprofiled case; the seed dir ships no overlay).
//   - Present-but-malformed     -> the import error propagates. A profile that
//     exists but cannot load is a real fault, not a silent fall-through.
//   - Profile logo paths are relative to the profile brand.js (e.g.
//     `assets/logo.png`). They are resolved to ABSOLUTE here so the downstream
//     build scripts' `path.resolve(buildDir, meta.logo*)` returns them
//     unchanged (path.resolve keeps a trailing absolute segment).
//
// The overlay is loaded via a `data:` URL rather than a file URL so its ESM
// `export const` parses regardless of the consumer project's package scope: a
// profile brand.js sits under the consumer's `.claude/ai-briefing/`, where the
// nearest package.json is the consumer's — an explicit `"type":"commonjs"`
// there makes a file-URL import throw `SyntaxError`, and a typeless one prints a
// MODULE_TYPELESS_PACKAGE_JSON perf warning on every build. A `data:` module is
// always ESM. The trade-off: a data: module cannot resolve relative `import`s,
// so brand.js must stay a pure-data overlay (org/tagline/logo strings + theme
// tokens) — which the documented contract already requires.

import fs from "node:fs";
import path from "node:path";

const LOGO_KEYS = ["logoColor", "logoWhite"];

export async function resolveBrand({ defaultBrand, defaultTheme, configDir }) {
  const overlayPath = path.join(configDir, "brand.js");
  if (!fs.existsSync(overlayPath)) {
    return { brand: { ...defaultBrand }, theme: { ...defaultTheme } };
  }

  const source = fs.readFileSync(overlayPath, "utf-8");
  const dataUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`;
  const overlay = await import(dataUrl);
  const brand = { ...defaultBrand, ...(overlay.brand ?? {}) };
  const theme = { ...defaultTheme, ...(overlay.theme ?? {}) };

  // Only the profile-supplied logos anchor to configDir; the neutral default's
  // logos are empty and provider logos stay relative to the build dir.
  for (const key of LOGO_KEYS) {
    const value = overlay.brand?.[key];
    if (value && !path.isAbsolute(value)) {
      brand[key] = path.resolve(configDir, value);
    }
  }

  return { brand, theme };
}
