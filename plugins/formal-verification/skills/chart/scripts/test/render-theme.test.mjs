import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { buildChartStyle } from "../render-theme.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = join(HERE, "../render-theme.mjs");
const THEME_PATH = join(HERE, "../../reference/render-theme.css");
const RENDER_DOC_PATH = join(HERE, "../../reference/render.md");
const TOKENS_PATH = join(HERE, "../../../../reference/html-tokens.css");

function withTempRepo(fn) {
  const root = mkdtempSync(join(tmpdir(), "fv-branding-"));
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_SYSTEM: "/dev/null" };
  try {
    execFileSync("git", ["-C", root, "init", "-q"], { env });
    return fn(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("render-theme.css derives --pele-* base tokens from html-tokens.css and matches root-SVG dark mode", () => {
  const theme = readFileSync(THEME_PATH, "utf8");
  assert.doesNotMatch(theme, /--pele-[a-z-]+\s*:\s*#[0-9a-fA-F]+/);
  assert.match(theme, /--pele-bg:\s*var\(--bg\);/);
  assert.match(theme, /--pele-fg:\s*var\(--fg\);/);
  assert.match(theme, /--pele-muted:\s*var\(--muted\);/);
  assert.match(theme, /--pele-surface:\s*var\(--panel\);/);
  assert.match(theme, /--pele-font:\s*var\(--sans\);/);
  assert.match(theme, /:is\(:root\.pele:not\(\[data-theme=light\]\), :root:not\(\[data-theme=light\]\) \.pele\)/);
  assert.match(theme, /:is\(:root\.pele\[data-theme=dark\], :root\[data-theme=dark\] \.pele\)/);
  assert.match(readFileSync(RENDER_DOC_PATH, "utf8"), /render-theme\.mjs/);
});

test("default chart style includes html-tokens.css shipped values and keeps categorical/verdict classes", () => {
  withTempRepo((root) => {
    const { css, branding } = buildChartStyle({ projectRoot: root });
    assert.equal(branding.css, "");
    assert.match(css, /--ivory:\s*#FAF9F5;/);
    assert.match(css, /--bg:\s*var\(--ivory\);/);
    assert.match(css, /--pele-bg:\s*var\(--bg\);/);
    assert.match(css, /\.pele \.breaks rect/);
    assert.ok(readFileSync(TOKENS_PATH, "utf8").includes("--bg: var(--ivory);"));
  });
});

test("CLI render-theme.mjs applies repo and userConfig branding overrides in order", () => {
  withTempRepo((root) => {
    mkdirSync(join(root, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(root, "docs/conventions/rendered-views.yaml"),
      [
        "branding:",
        "  palette:",
        "    light:",
        '      bg: "#FFFFFF"',
        '      fg: "#101828"',
        '      muted: "#595959"',
        "    dark:",
        '      bg: "#0B1220"',
        '      fg: "#F8FAFC"',
        "  type:",
        '    sans: "IBM Plex Sans, system-ui, sans-serif"',
        "",
      ].join("\n"),
    );
    const userOption = JSON.stringify({ palette: { light: { fg: "#000000" } }, type: { mono: "JetBrains Mono, monospace" } });
    const run = spawnSync("node", [SCRIPT_PATH, "--project-root", root, "--option", userOption], { encoding: "utf8" });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stderr, "");
    assert.match(run.stdout, /:root \{ --bg: #FFFFFF; --fg: #101828; --muted: #595959; --sans: IBM Plex Sans, system-ui, sans-serif; --mono: JetBrains Mono, monospace; \}/);
    assert.match(run.stdout, /:root\[data-theme=dark\] \{ --bg: #0B1220; --fg: #F8FAFC; \}/);
    assert.match(run.stdout, /--pele-bg:\s*var\(--bg\);/);
  });
});

test("CLI render-theme.mjs drops below-floor contrast overrides and reports notices on stderr", () => {
  withTempRepo((root) => {
    mkdirSync(join(root, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(root, "docs/conventions/rendered-views.yaml"),
      ["branding:", "  palette:", "    light:", '      bg: "#FAF9F5"', '      fg: "#EAE8E1"', ""].join("\n"),
    );
    const run = spawnSync("node", [SCRIPT_PATH, "--project-root", root], { encoding: "utf8" });
    assert.equal(run.status, 0);
    assert.doesNotMatch(run.stdout, /--fg:\s*#EAE8E1/i);
    assert.match(run.stderr, /notice:.*light fg:.*4\.5/);
  });
});
