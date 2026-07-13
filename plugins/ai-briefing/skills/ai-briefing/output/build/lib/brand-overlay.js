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

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const LOGO_KEYS = ["logoColor", "logoWhite"];

export async function resolveBrand({ defaultBrand, defaultTheme, configDir }) {
  const overlayPath = path.join(configDir, "brand.js");
  if (!fs.existsSync(overlayPath)) {
    return { brand: { ...defaultBrand }, theme: { ...defaultTheme } };
  }

  const overlay = await import(pathToFileURL(overlayPath).href);
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
