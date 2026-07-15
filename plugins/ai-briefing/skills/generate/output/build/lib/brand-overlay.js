// Resolve a declarative, schema-validated brand.json profile overlay over the
// engine's neutral defaults. Profile data is never executed as JavaScript.

import fs from "node:fs";
import path from "node:path";
import { z } from "zod";

const LOGO_KEYS = ["logoColor", "logoWhite"];
const COLOR_KEYS = [
  "bg",
  "bgAccent",
  "bgCard",
  "brandIndigo",
  "brandRed",
  "accent",
  "accent2",
  "accent3",
  "text",
  "textMuted",
  "divider",
];

const brandSchema = z
  .object({
    org: z.string().min(1).max(120).optional(),
    tagline: z.string().max(240).optional(),
    logoColor: z.string().min(1).max(260).optional(),
    logoWhite: z.string().min(1).max(260).optional(),
    footerTemplate: z.string().min(1).max(240).optional(),
  })
  .strict();

const fontSchema = z
  .string()
  .min(1)
  .max(200)
  .regex(/^[A-Za-z0-9 ',._-]+$/, "font stacks may contain only portable font-family characters");
const themeShape = Object.fromEntries(
  COLOR_KEYS.map((key) => [key, z.string().regex(/^[0-9A-Fa-f]{6}$/).optional()]),
);
for (const key of ["pptFontHead", "pptFontBody", "htmlFontHead", "htmlFontBody"]) {
  themeShape[key] = fontSchema.optional();
}
const themeSchema = z.object(themeShape).strict();
const overlaySchema = z
  .object({
    brand: brandSchema.optional(),
    theme: themeSchema.optional(),
  })
  .strict();

function resolveLogo(configDir, value) {
  if (!value) return value;
  if (path.isAbsolute(value) || /^[A-Za-z]:/.test(value)) {
    throw new Error("brand.json logo paths must be relative to the profile directory");
  }

  const realConfigDir = fs.realpathSync(configDir);
  const candidate = path.resolve(realConfigDir, value);
  const realCandidate = fs.realpathSync(candidate);
  const relative = path.relative(realConfigDir, realCandidate);
  if (
    relative === ".." ||
    relative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relative)
  ) {
    throw new Error("brand.json logo paths must remain inside the profile directory");
  }
  if (!fs.statSync(realCandidate).isFile()) {
    throw new Error("brand.json logo paths must identify regular files");
  }
  return realCandidate;
}

export async function resolveBrand({ defaultBrand, defaultTheme, configDir }) {
  const overlayPath = path.join(configDir, "brand.json");
  if (!fs.existsSync(overlayPath)) {
    const legacyOverlayPath = path.join(configDir, "brand.js");
    if (fs.existsSync(legacyOverlayPath)) {
      throw new Error(
        `Legacy profile branding found at ${legacyOverlayPath}. Convert brand.js to declarative brand.json before building; executable profile overlays are no longer supported.`,
      );
    }
    return { brand: { ...defaultBrand }, theme: { ...defaultTheme } };
  }

  const overlay = overlaySchema.parse(JSON.parse(fs.readFileSync(overlayPath, "utf-8")));
  const brand = { ...defaultBrand, ...(overlay.brand ?? {}) };
  const theme = { ...defaultTheme, ...(overlay.theme ?? {}) };

  for (const key of LOGO_KEYS) {
    if (overlay.brand?.[key]) brand[key] = resolveLogo(configDir, overlay.brand[key]);
  }

  return { brand, theme };
}
