import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { applyBranding, stripTokenComment } from "../lib/html-branding.mjs";
import { resolveBranding } from "../lib/view-settings.mjs";
process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN = join(HERE, "..");
const TOKENS = readFileSync(join(PLUGIN, "reference", "html-tokens.css"), "utf8");
const CHROME = readFileSync(join(PLUGIN, "reference", "html-chrome.html"), "utf8");
const LOOP = readFileSync(join(PLUGIN, "reference", "html-loop-closure.html"), "utf8");
const CLI = join(PLUGIN, "lib", "html-branding.mjs");

const dirs = [];
process.on("exit", () => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
const makeTemp = (prefix) => {
  const d = mkdtempSync(join(tmpdir(), prefix));
  dirs.push(d);
  return d;
};

const extract = (text, re) => re.exec(text)?.[0] ?? "";
const CHROME_RULES = extract(CHROME, /\/\* rv-chrome:begin \*\/[\s\S]*?\/\* rv-chrome:end \*\//);
const TOGGLE = extract(CHROME, /<div class="rv-theme"[\s\S]*?<\/div>/);
const COMMENT = extract(CHROME, /<section class="rv-comment"[\s\S]*?<\/section>/);

const basePage = () => [
  "<!doctype html>",
  '<html lang="en"><head><meta charset="utf-8"><title>Visualization</title>',
  "<style>",
  "  @media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }",
  "  body { background: var(--bg); color: var(--fg); font-family: var(--sans); }",
  "  a:focus-visible, button:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }",
  CHROME_RULES,
  "</style></head><body>",
  `<div class="rv-bar">${TOGGLE}</div>`,
  "<h1>Chart</h1>",
  COMMENT,
  "</body></html>",
].join("\n");

const PNG_BYTES = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52]);
const VALID_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" role="img" aria-label="Acme"><rect width="20" height="20" x="2" y="2" fill="#1D4ED8"/></svg>';

describe("visualization token layer and html-loop-closure.html", () => {
  test("html-loop-closure.html opens its style element with reference/html-tokens.css and defines no literal hex outside it", () => {
    const style = /<style>\n([\s\S]*?)<\/style>/.exec(LOOP)?.[1];
    assert.ok(style, "html-loop-closure.html must have a <style> element");
    const tokenRules = stripTokenComment(TOKENS);
    const flat = (s) => s.replace(/^[ \t]+/gm, "").trim();
    assert.ok(flat(style).startsWith(flat(tokenRules)), "html-loop-closure.html must open with reference/html-tokens.css rules");
    const afterTokens = flat(style).slice(flat(tokenRules).length);
    assert.doesNotMatch(afterTokens, /#[0-9A-Fa-f]{3,8}\b/, "no literal hex palette value outside the token layer");
  });
});

describe("visualization branded page rendering", () => {
  test("with no branding set, inlines the token layer with zero overrides and leaves chrome bar unchanged", () => {
    const home = makeTemp("viz-home-");
    const branding = resolveBranding({}, { userHome: home });
    const out = applyBranding(basePage(), { tokensCss: TOKENS, branding });
    assert.equal((out.match(/<style>/g) ?? []).length, 1);
    assert.ok(out.includes("--ivory: #FAF9F5;"));
    assert.equal(out.includes("rv-brand"), false);
    assert.ok(out.includes(TOGGLE));
    assert.ok(out.includes(COMMENT));
    assert.ok(out.includes(CHROME_RULES));
  });

  test("applies palette, type, SVG logo and label overrides while preserving toggle, comment box and accessibility floor", () => {
    const home = makeTemp("viz-home-");
    const branding = resolveBranding(
      {
        userConfig: JSON.stringify({
          palette: { light: { accent: "#1D4ED8", link: "#1E40AF" }, dark: { accent: "#60A5FA" } },
          type: { sans: "Inter, system-ui, sans-serif" },
          logo: { svg: VALID_SVG, label: "Acme" },
        }),
      },
      { userHome: home },
    );
    assert.deepEqual(branding.notices, []);
    const out = applyBranding(basePage(), { tokensCss: TOKENS, branding });
    assert.equal((out.match(/<style>/g) ?? []).length, 1);
    assert.ok(out.includes("--accent: #1D4ED8;"));
    assert.ok(out.includes("--link: #1E40AF;"));
    assert.ok(out.includes("--sans: Inter, system-ui, sans-serif;"));
    assert.ok(out.includes(":root[data-theme=dark] { --accent: #60A5FA; }"));
    assert.ok(out.includes(`<div class="rv-bar"><div class="rv-brand">${VALID_SVG}<span class="rv-brand-label">Acme</span></div>${TOGGLE}</div>`));
    assert.ok(out.includes(COMMENT));
    assert.ok(out.includes(CHROME_RULES));
    assert.ok(out.includes("prefers-reduced-motion: reduce"));
    assert.ok(out.includes("outline: 3px solid var(--focus)"));
  });

  test("CLI resolves repository team branding with PNG logo and writes one self-contained page", () => {
    const dir = makeTemp("viz-repo-");
    const home = makeTemp("viz-home-");
    execFileSync("git", ["-C", dir, "init", "-q", "-b", "main"]);
    mkdirSync(join(dir, "docs/conventions"), { recursive: true });
    mkdirSync(join(dir, "docs/brand"), { recursive: true });
    writeFileSync(join(dir, "docs/brand/logo.png"), PNG_BYTES);
    writeFileSync(
      join(dir, "docs/conventions/rendered-views.yaml"),
      ['branding:', '  palette:', '    light:', '      accent: "#0F766E"', '  logo:', '    file: "docs/brand/logo.png"', '    label: "Acme Viz"', ''].join("\n"),
    );
    const pageIn = join(dir, "in.html");
    const pageOut = join(dir, "out.html");
    writeFileSync(pageIn, basePage());
    const run = spawnSync(process.execPath, [CLI, "--in", pageIn, "--out", pageOut], {
      encoding: "utf8",
      env: { ...process.env, HOME: home, USERPROFILE: home, CLAUDE_PROJECT_DIR: dir },
    });
    assert.equal(run.status, 0, run.stderr);
    const html = readFileSync(pageOut, "utf8");
    assert.ok(html.includes("--accent: #0F766E;"));
    assert.ok(html.includes(`.rv-logo { background-image: url(data:image/png;base64,${PNG_BYTES.toString("base64")}); }`));
    assert.ok(html.includes('<span class="rv-brand-mark rv-logo" role="img" aria-label="Acme Viz"></span>'));
    assert.ok(html.includes(TOGGLE));
    assert.ok(html.includes(COMMENT));
  });
});
