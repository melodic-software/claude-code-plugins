import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { resolveBranding } from "./view-settings.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = join(HERE, "..");
const TOKENS_PATH = join(PLUGIN_ROOT, "reference/html-tokens.css");
const HOST_PATH = join(PLUGIN_ROOT, "notes-bridge/host.html");
const PIN_PATH = join(PLUGIN_ROOT, "notes-bridge/proto-pin.js");
const SWITCHER_PATH = join(PLUGIN_ROOT, "skills/explore-directions/assets/variant-switcher.html");

function withTempRepo(fn) {
  const root = mkdtempSync(join(tmpdir(), "prototype-branding-"));
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_SYSTEM: "/dev/null" };
  try {
    execFileSync("git", ["-C", root, "init", "-q"], { env });
    return fn(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("prototype carries reference/html-tokens.css with shipped light and dark tokens", () => {
  const tokens = readFileSync(TOKENS_PATH, "utf8");
  assert.match(tokens, /--ivory:\s*#FAF9F5;/);
  assert.match(tokens, /--slate:\s*#141413;/);
  assert.match(tokens, /--bg:\s*var\(--ivory\);/);
  assert.match(tokens, /color-scheme:\s*light;/);
  assert.match(tokens, /@media \(prefers-color-scheme: dark\)/);
  assert.match(tokens, /:root\[data-theme=dark\]/);
  assert.match(tokens, /color-scheme:\s*dark;/);
});

test("prototype view-settings.mjs resolves repo and userConfig branding overrides in precedence order", () => {
  withTempRepo((root) => {
    mkdirSync(join(root, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(root, "docs/conventions/rendered-views.yaml"),
      [
        "branding:",
        "  palette:",
        "    light:",
        '      bg: "#FFFFFF"',
        '      fg: "#141413"',
        '      muted: "#595959"',
        "    dark:",
        '      bg: "#111827"',
        '      fg: "#F9FAFB"',
        "  type:",
        '    sans: "Plus Jakarta Sans, system-ui, sans-serif"',
        "  logo:",
        '    svg: \'<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"/></svg>\'',
        '    label: "Proto Co"',
        "",
      ].join("\n"),
    );
    const userConfig = JSON.stringify({ palette: { light: { fg: "#000000" } }, type: { serif: "Georgia, serif" } });
    const branding = resolveBranding({ projectRoot: root, userConfig });
    assert.equal(branding.sources["palette.light.fg"], "team");
    assert.equal(branding.sources["type.serif"], "userConfig");
    assert.match(branding.css, /:root \{ --bg: #FFFFFF; --fg: #141413; --muted: #595959; --serif: Georgia, serif; --sans: Plus Jakarta Sans, system-ui, sans-serif; \}/);
    assert.match(branding.css, /:root\[data-theme=dark\] \{ --bg: #111827; --fg: #F9FAFB; \}/);
    assert.equal(branding.logo.kind, "svg");
    assert.equal(branding.logo.label, "Proto Co");
  });
});

test("below-floor contrast override is dropped back to shipped value with a notice", () => {
  withTempRepo((root) => {
    mkdirSync(join(root, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(root, "docs/conventions/rendered-views.yaml"),
      ["branding:", "  palette:", "    dark:", '      bg: "#141413"', '      fg: "#222220"', ""].join("\n"),
    );
    const branding = resolveBranding({ projectRoot: root });
    assert.equal(branding.palette.dark.fg, "#FAF9F5");
    assert.ok(branding.notices.some((n) => n.text.includes("fg") && n.text.includes("dark") && n.text.includes("4.5")));
    assert.doesNotMatch(branding.css, /#222220/i);
  });
});

test("prototype UI-feedback harness chrome stays apart on its neutral --uif-* palette", () => {
  const host = readFileSync(HOST_PATH, "utf8");
  const pin = readFileSync(PIN_PATH, "utf8");
  const switcher = readFileSync(SWITCHER_PATH, "utf8");
  assert.match(host, /--uif-accent:\s*#4433cc;/);
  assert.match(switcher, /--uif-accent:\s*#4433cc;/);
  assert.match(pin, /#4433cc/);
  assert.doesNotMatch(host, /data-rv-theme/);
});
