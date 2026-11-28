import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { applyBranding } from "../lib/html-branding.mjs";
import { resolveBranding } from "../lib/view-settings.mjs";
process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN = join(HERE, "..");
const TOKENS = readFileSync(join(PLUGIN, "reference", "html-tokens.css"), "utf8");
const CHROME = readFileSync(join(PLUGIN, "reference", "html-chrome.html"), "utf8");
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

const clarifyPage = () => [
  "<!doctype html>",
  '<html lang="en"><head><meta charset="utf-8"><title>Decision table</title>',
  "<style>",
  "  @media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }",
  "  body { background: var(--bg); color: var(--fg); font-family: var(--sans); }",
  "  a:focus-visible, button:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }",
  CHROME_RULES,
  "</style></head><body>",
  `<div class="rv-bar">${TOGGLE}</div>`,
  "<h1>Decision table</h1>",
  "<table><tr><th>#</th><th>Item</th><th>Recommendation</th></tr><tr><td>1</td><td>Q1</td><td>Option A</td></tr></table>",
  COMMENT,
  "</body></html>",
].join("\n");

const VALID_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" role="img" aria-label="Acme"><circle cx="12" cy="12" r="10" fill="#0F766E"/></svg>';

describe("adhd branded decision table rendering", () => {
  test("with no branding set, inlines reference/html-tokens.css and keeps toggle, comment box and bar unchanged", () => {
    const home = makeTemp("adhd-home-");
    const branding = resolveBranding({}, { userHome: home });
    const out = applyBranding(clarifyPage(), { tokensCss: TOKENS, branding });
    assert.equal((out.match(/<style>/g) ?? []).length, 1);
    assert.ok(out.includes("--ivory: #FAF9F5;"));
    assert.equal(out.includes("rv-brand"), false);
    assert.ok(out.includes(TOGGLE));
    assert.ok(out.includes(COMMENT));
    assert.ok(out.includes(CHROME_RULES));
  });

  test("applies branding override in the one style element and shows the logo in .rv-bar while keeping toggle, comment box and floor", () => {
    const dir = makeTemp("adhd-repo-");
    const home = makeTemp("adhd-home-");
    execFileSync("git", ["-C", dir, "init", "-q", "-b", "main"]);
    mkdirSync(join(dir, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(dir, "docs/conventions/rendered-views.yaml"),
      [
        "branding:",
        "  palette:",
        "    light:",
        '      accent: "#1D4ED8"',
        '      link: "#1E40AF"',
        "    dark:",
        '      accent: "#93C5FD"',
        "  type:",
        '    serif: "Georgia, serif"',
        "  logo:",
        `    svg: ${JSON.stringify(VALID_SVG)}`,
        '    label: "Acme Clarify"',
        "",
      ].join("\n"),
    );
    const pageIn = join(dir, "clarify.html");
    const pageOut = join(dir, "clarify-out.html");
    writeFileSync(pageIn, clarifyPage());
    const run = spawnSync(process.execPath, [CLI, "--in", pageIn, "--out", pageOut], {
      encoding: "utf8",
      env: { ...process.env, HOME: home, USERPROFILE: home, CLAUDE_PROJECT_DIR: dir },
    });
    assert.equal(run.status, 0, run.stderr);
    const html = readFileSync(pageOut, "utf8");
    assert.equal((html.match(/<style>/g) ?? []).length, 1);
    assert.ok(html.includes("--ivory: #FAF9F5;"));
    assert.ok(html.includes("--accent: #1D4ED8;"));
    assert.ok(html.includes("--link: #1E40AF;"));
    assert.ok(html.includes("--serif: Georgia, serif;"));
    assert.ok(html.includes(":root[data-theme=dark] { --accent: #93C5FD; }"));
    assert.ok(html.includes(`<div class="rv-bar"><div class="rv-brand">${VALID_SVG}<span class="rv-brand-label">Acme Clarify</span></div>${TOGGLE}</div>`));
    assert.ok(html.includes(COMMENT));
    assert.ok(html.includes(CHROME_RULES));
    assert.ok(html.includes("prefers-reduced-motion: reduce"));
    assert.ok(html.includes("outline: 3px solid var(--focus)"));
  });
});
