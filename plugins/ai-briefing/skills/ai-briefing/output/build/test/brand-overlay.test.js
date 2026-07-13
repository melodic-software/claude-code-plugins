import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { resolveBrand } from "../lib/brand-overlay.js";

const DEFAULT_BRAND = {
  org: "AI Briefing",
  tagline: "AI industry news, aggregated and ranked.",
  logoColor: "",
  logoWhite: "",
  footerTemplate: "{org} · AI Meeting #{meeting_n} · {date}",
};

const DEFAULT_THEME = { bg: "0F1424", accent: "6E8BFF", pptFontHead: "Arial" };

/** Run `body(configDir)` against a throwaway profile dir containing `brand.js`
 *  (when `overlaySource` is non-null), then clean it up. */
async function withProfile(overlaySource, body) {
  const dir = await mkdtemp(path.join(tmpdir(), "ai-briefing-brand-"));
  try {
    if (overlaySource !== null) {
      await writeFile(path.join(dir, "brand.js"), overlaySource, "utf-8");
    }
    return await body(dir);
  } finally {
    await rm(dir, { force: true, recursive: true });
  }
}

test("absent profile brand.js returns the neutral default unchanged", async () => {
  await withProfile(null, async (configDir) => {
    const { brand, theme } = await resolveBrand({
      defaultBrand: DEFAULT_BRAND,
      defaultTheme: DEFAULT_THEME,
      configDir,
    });
    assert.equal(brand.org, "AI Briefing");
    assert.equal(brand.logoColor, "");
    assert.deepEqual(theme, DEFAULT_THEME);
    // A copy, not the shared default object.
    assert.notEqual(brand, DEFAULT_BRAND);
    assert.notEqual(theme, DEFAULT_THEME);
  });
});

test("profile overlay wins per key over the default for brand and theme", async () => {
  const overlay = `
    export const brand = { org: "SETWorks Engineering", tagline: "Empowering agencies." };
    export const theme = { accent: "8080FF", pptFontHead: "Ubuntu" };
  `;
  await withProfile(overlay, async (configDir) => {
    const { brand, theme } = await resolveBrand({
      defaultBrand: DEFAULT_BRAND,
      defaultTheme: DEFAULT_THEME,
      configDir,
    });
    assert.equal(brand.org, "SETWorks Engineering");
    assert.equal(brand.tagline, "Empowering agencies.");
    // Unmentioned key falls through to the default.
    assert.equal(brand.footerTemplate, DEFAULT_BRAND.footerTemplate);
    assert.equal(theme.accent, "8080FF");
    assert.equal(theme.pptFontHead, "Ubuntu");
    assert.equal(theme.bg, "0F1424");
  });
});

test("relative profile logo paths resolve to absolute against the profile dir", async () => {
  const overlay = `
    export const brand = {
      org: "SETWorks Engineering",
      logoColor: "assets/setworks-logo-color.png",
      logoWhite: "assets/setworks-logo-white.png",
    };
  `;
  await withProfile(overlay, async (configDir) => {
    const { brand } = await resolveBrand({
      defaultBrand: DEFAULT_BRAND,
      defaultTheme: DEFAULT_THEME,
      configDir,
    });
    assert.ok(path.isAbsolute(brand.logoColor));
    assert.ok(path.isAbsolute(brand.logoWhite));
    assert.equal(brand.logoColor, path.resolve(configDir, "assets/setworks-logo-color.png"));
    // Downstream build scripts resolve against the build dir; an absolute path
    // survives path.resolve unchanged — the whole point of anchoring here.
    assert.equal(path.resolve("/some/build/dir", brand.logoColor), brand.logoColor);
  });
});

test("an already-absolute profile logo path is left untouched", async () => {
  const abs = path.join(path.sep, "opt", "brand", "logo.png");
  const overlay = `export const brand = { logoWhite: ${JSON.stringify(abs)} };`;
  await withProfile(overlay, async (configDir) => {
    const { brand } = await resolveBrand({
      defaultBrand: DEFAULT_BRAND,
      defaultTheme: DEFAULT_THEME,
      configDir,
    });
    assert.equal(brand.logoWhite, abs);
  });
});

test("a present-but-malformed profile brand.js surfaces the error (no silent fallback)", async () => {
  const overlay = "export const brand = { this is not valid javascript";
  await withProfile(overlay, async (configDir) => {
    await assert.rejects(() =>
      resolveBrand({ defaultBrand: DEFAULT_BRAND, defaultTheme: DEFAULT_THEME, configDir }),
    );
  });
});
