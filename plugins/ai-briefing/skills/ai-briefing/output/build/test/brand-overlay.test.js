import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
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

async function withProfile(overlay, body) {
  const root = await mkdtemp(path.join(tmpdir(), "ai-briefing-brand-"));
  const configDir = path.join(root, "profile");
  await mkdir(configDir);
  try {
    if (overlay !== null) {
      const source = typeof overlay === "string" ? overlay : JSON.stringify(overlay);
      await writeFile(path.join(configDir, "brand.json"), source, "utf-8");
    }
    return await body(configDir, root);
  } finally {
    await rm(root, { force: true, recursive: true });
  }
}

function resolve(configDir) {
  return resolveBrand({ defaultBrand: DEFAULT_BRAND, defaultTheme: DEFAULT_THEME, configDir });
}

test("absent profile brand.json returns copies of the neutral defaults", async () => {
  await withProfile(null, async (configDir) => {
    const { brand, theme } = await resolve(configDir);
    assert.deepEqual(brand, DEFAULT_BRAND);
    assert.deepEqual(theme, DEFAULT_THEME);
    assert.notEqual(brand, DEFAULT_BRAND);
    assert.notEqual(theme, DEFAULT_THEME);
  });
});

test("legacy brand.js profiles fail with an explicit migration message", async () => {
  await withProfile(null, async (configDir) => {
    await writeFile(
      path.join(configDir, "brand.js"),
      'export const brand = { org: "Legacy Engineering" };',
      "utf-8",
    );

    await assert.rejects(
      () => resolve(configDir),
      /Legacy profile branding.*Convert brand\.js to declarative brand\.json.*no longer supported/,
    );
  });
});

test("profile overlay wins per key and preserves unmentioned defaults", async () => {
  await withProfile(
    {
      brand: { org: "Example Engineering", tagline: "Useful briefings." },
      theme: { accent: "8080FF", pptFontHead: "Ubuntu" },
    },
    async (configDir) => {
      const { brand, theme } = await resolve(configDir);
      assert.equal(brand.org, "Example Engineering");
      assert.equal(brand.footerTemplate, DEFAULT_BRAND.footerTemplate);
      assert.equal(theme.accent, "8080FF");
      assert.equal(theme.bg, DEFAULT_THEME.bg);
    },
  );
});

test("relative logo paths resolve only to regular files inside the profile", async () => {
  await withProfile(
    { brand: { logoColor: "assets/logo.png" } },
    async (configDir) => {
      await mkdir(path.join(configDir, "assets"));
      await writeFile(path.join(configDir, "assets", "logo.png"), "image");
      const { brand } = await resolve(configDir);
      assert.equal(brand.logoColor, path.join(configDir, "assets", "logo.png"));
    },
  );
});

test("absolute, traversal, missing, and directory logo paths are rejected", async () => {
  for (const value of [path.resolve("absolute-logo.png"), "../outside.png", "missing.png", "assets"]) {
    await withProfile({ brand: { logoWhite: value } }, async (configDir, root) => {
      await mkdir(path.join(configDir, "assets"));
      await writeFile(path.join(root, "outside.png"), "outside");
      await assert.rejects(() => resolve(configDir));
    });
  }
});

test("a symlink cannot escape the profile directory", async (t) => {
  await withProfile({ brand: { logoWhite: "linked-logo.png" } }, async (configDir, root) => {
    const outside = path.join(root, "outside.png");
    await writeFile(outside, "outside");
    try {
      await symlink(outside, path.join(configDir, "linked-logo.png"), "file");
    } catch (error) {
      if (error.code === "EPERM") {
        t.skip("file symlinks require Windows Developer Mode or elevation");
        return;
      }
      throw error;
    }
    await assert.rejects(() => resolve(configDir), /inside the profile directory/);
  });
});

test("malformed JSON, unknown keys, invalid colors, and unsafe font strings are rejected", async () => {
  for (const overlay of [
    "{not-json",
    { executable: "no" },
    { brand: { unknown: "no" } },
    { theme: { accent: "not-a-hex-color" } },
    { theme: { htmlFontHead: "Arial; background: url(https://example.invalid)" } },
  ]) {
    await withProfile(overlay, async (configDir) => {
      await assert.rejects(() => resolve(configDir));
    });
  }
});
