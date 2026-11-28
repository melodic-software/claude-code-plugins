import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { buildChartStyle, readConfiguredBranding } from "../render-theme.mjs";

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

test("render-theme.css preserves Pele default light/dark values and root-SVG dark mode", () => {
  const theme = readFileSync(THEME_PATH, "utf8");
  assert.match(theme, /--pele-bg:\s*#ffffff;/);
  assert.match(theme, /--pele-fg:\s*#1c1c1c;/);
  assert.match(theme, /--pele-muted:\s*#656565;/);
  assert.match(theme, /--pele-line:\s*#808080;/);
  assert.match(theme, /--pele-surface:\s*#fcfcfc;/);
  assert.match(theme, /--pele-surface-alt:\s*#f1f1f1;/);
  assert.match(theme, /--pele-border:\s*#c9c9c9;/);
  assert.match(theme, /--pele-bg:\s*#1f1f1f;/);
  assert.match(theme, /--pele-fg:\s*#f5f5f5;/);
  assert.match(theme, /--pele-muted:\s*#acacac;/);
  assert.match(theme, /--pele-line:\s*#939393;/);
  assert.match(theme, /--pele-surface:\s*#121212;/);
  assert.match(theme, /--pele-surface-alt:\s*#2c2c2c;/);
  assert.match(theme, /--pele-border:\s*#4e4e4e;/);
  assert.doesNotMatch(theme, /--pele-font:/);
  assert.match(theme, /:is\(:root\.pele:not\(\[data-theme=light\]\), :root:not\(\[data-theme=light\]\) \.pele\)/);
  assert.match(theme, /:is\(:root\.pele\[data-theme=dark\], :root\[data-theme=dark\] \.pele\)/);
  assert.match(readFileSync(RENDER_DOC_PATH, "utf8"), /render-theme\.mjs/);
});

test("default chart style keeps exact unbranded Pele light/dark palette without forcing --pele-font", () => {
  withTempRepo((root) => {
    const { css, branding } = buildChartStyle({ projectRoot: root });
    assert.equal(branding.css, "");
    assert.match(css, /--ivory:\s*#FAF9F5;/);
    assert.match(css, /--bg:\s*var\(--ivory\);/);
    assert.match(css, /\.pele \{\n  --pele-bg: #ffffff;\n  --pele-fg: #1c1c1c;\n  --pele-muted: #656565;\n  --pele-line: #808080;\n  --pele-surface: #fcfcfc;\n  --pele-surface-alt: #f1f1f1;\n  --pele-border: #c9c9c9;\n\}/);
    assert.match(css, /:is\(:root\.pele\[data-theme=dark\], :root\[data-theme=dark\] \.pele\) \{\n  --pele-bg: #1f1f1f;\n  --pele-fg: #f5f5f5;\n  --pele-muted: #acacac;\n  --pele-line: #939393;\n  --pele-surface: #121212;\n  --pele-surface-alt: #2c2c2c;\n  --pele-border: #4e4e4e;\n\}/);
    assert.doesNotMatch(css, /--pele-bg:\s*var\(--bg\)/);
    assert.doesNotMatch(css, /--pele-font:/);
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
    assert.match(run.stdout, /\.pele \{ --pele-bg: var\(--bg\); --pele-fg: var\(--fg\); --pele-muted: var\(--muted\); --pele-font: var\(--sans\); font-family: var\(--pele-font\); \}/);
    assert.match(run.stdout, /:is\(:root\.pele\[data-theme=dark\], :root\[data-theme=dark\] \.pele\) \{ --pele-bg: var\(--bg\); --pele-fg: var\(--fg\); \}/);
  });
});

test("CLI render-theme.mjs drops below-floor contrast overrides and reports notices on stderr", () => {
  withTempRepo((root) => {
    mkdirSync(join(root, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(root, "docs/conventions/rendered-views.yaml"),
      ["branding:", "  palette:", "    light:", '      bg: "#FAF9F5"', '      fg: "#EAE8E1"', ""].join("\n"),
    );
    const run = spawnSync("node", [SCRIPT_PATH, "--project-root", root], {
      encoding: "utf8",
      env: { ...process.env, CLAUDE_CONFIG_DIR: join(root, "empty-claude-config"), CLAUDE_PLUGIN_OPTION_BRANDING: "" },
    });
    assert.equal(run.status, 0);
    assert.doesNotMatch(run.stdout, /--fg:\s*#EAE8E1/i);
    assert.match(run.stderr, /notice:.*light fg:.*4\.5/);
  });
});

test("CLI render-theme.mjs reads userConfig.branding from Claude settings without env var or --option", () => {
  withTempRepo((root) => {
    const configDir = join(root, "claude-config");
    const cachedPluginRoot = join(configDir, "plugins", "cache", "test-mkt", "formal-verification", "1.0.0");
    mkdirSync(cachedPluginRoot, { recursive: true });
    const configured = JSON.stringify({
      palette: { light: { bg: "#FFFFFF", fg: "#101828", muted: "#595959" } },
      type: { sans: "IBM Plex Sans, system-ui, sans-serif" },
    });
    writeFileSync(
      join(configDir, "settings.json"),
      JSON.stringify({ pluginConfigs: { "formal-verification@test-mkt": { options: { branding: configured } } } }),
    );
    const cached = readConfiguredBranding({ pluginRoot: cachedPluginRoot, env: {}, managedFiles: [] });
    assert.equal(cached.value, configured);
    assert.deepEqual(cached.notices, []);

    const run = spawnSync("node", [SCRIPT_PATH, "--project-root", root], {
      encoding: "utf8",
      env: { ...process.env, CLAUDE_CONFIG_DIR: configDir, CLAUDE_PLUGIN_OPTION_BRANDING: "" },
    });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stderr, "");
    assert.match(run.stdout, /:root \{ --bg: #FFFFFF; --fg: #101828; --muted: #595959; --sans: IBM Plex Sans, system-ui, sans-serif; \}/);
  });
});
