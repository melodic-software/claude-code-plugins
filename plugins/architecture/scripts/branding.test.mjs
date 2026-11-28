import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { stripTokenComment } from "../lib/html-branding.mjs";
import { validateView } from "../lib/view-builder.mjs";
import { parseDeepening, renderDeepening, validateDeepeningPage } from "./deepening-report.mjs";
process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN = join(HERE, "..");
const TOKENS = readFileSync(join(PLUGIN, "reference", "html-tokens.css"), "utf8");
const MAP_TEMPLATE = readFileSync(join(PLUGIN, "templates", "map-view.html"), "utf8");
const DEEPENING_SOURCE = readFileSync(join(PLUGIN, "scripts", "deepening-report.mjs"), "utf8");
const BUILD_VIEW = join(PLUGIN, "scripts", "build-view.mjs");
const DEEPENING_FIXTURE = join(PLUGIN, "scripts", "testdata", "deepening-candidates.json");

const PNG_1X1 = Buffer.from(
  "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082",
  "hex",
);
const WOFF2_STUB = Buffer.concat([Buffer.from("wOF2"), Buffer.alloc(16, 0x41)]);

const flat = (css) => css.replace(/\r\n?/g, "\n").replace(/^[ \t]+/gm, "").trim();

const MAP_RECORD = {
  schema_version: 1,
  result: "ok",
  nodes: [{ id: "A", name: "Service A", kind: "project" }],
  edges: [],
};

function runGit(cwd, args) {
  const res = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8" });
  if (res.status !== 0) throw new Error(`git ${args.join(" ")} failed: ${res.stderr}`);
}

function makeBrandedRepo(yamlBody, assets = {}) {
  const dir = mkdtempSync(join(tmpdir(), "arch-brand-"));
  runGit(dir, ["init", "-q", "-b", "main"]);
  runGit(dir, ["config", "user.email", "test@example.com"]);
  runGit(dir, ["config", "user.name", "Test"]);
  mkdirSync(join(dir, "docs", "conventions"), { recursive: true });
  writeFileSync(join(dir, "docs", "conventions", "rendered-views.yaml"), yamlBody);
  for (const [rel, content] of Object.entries(assets)) {
    const abs = join(dir, rel);
    mkdirSync(dirname(abs), { recursive: true });
    writeFileSync(abs, content);
  }
  runGit(dir, ["add", "."]);
  runGit(dir, ["-c", "commit.gpgsign=false", "commit", "-q", "-m", "seed"]);
  return dir;
}

describe("architecture token layer compliance", () => {
  test("map-view.html defines no literal hex colors and receives reference/html-tokens.css at build time", () => {
    const style = /<style>([\s\S]*?)<\/style>/i.exec(MAP_TEMPLATE)?.[1] ?? "";
    assert.ok(style.length > 0);
    assert.doesNotMatch(style, /#[0-9A-Fa-f]{3,8}\b/, "no literal hex colors in map-view.html");
    assert.match(MAP_TEMPLATE, /data-rv-theme="system"/);
    assert.match(MAP_TEMPLATE, /class="rv-bar"/);
  });

  test("deepening-report.mjs REPORT_STYLE defines no literal hex colors outside the chrome token layer", () => {
    const reportStyle = /const REPORT_STYLE = `([\s\S]*?)`;/.exec(DEEPENING_SOURCE)?.[1] ?? "";
    assert.ok(reportStyle.length > 0);
    assert.doesNotMatch(reportStyle, /#[0-9A-Fa-f]{3,8}\b/, "REPORT_STYLE must use shared CSS custom properties");
  });
});

describe("architecture branded page builds", () => {
  test("with no branding set, map-view and deepening render defaults unchanged with toggle and valid profile", () => {
    const work = mkdtempSync(join(tmpdir(), "arch-default-"));
    try {
      const mapRecord = join(work, "map.json");
      writeFileSync(mapRecord, JSON.stringify(MAP_RECORD));
      const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work };

      const mapBuilt = spawnSync("node", [BUILD_VIEW, "dependencies", "--record", mapRecord], {
        cwd: work,
        encoding: "utf8",
        env,
      });
      assert.equal(mapBuilt.status, 0, mapBuilt.stderr);
      const mapHtml = readFileSync(mapBuilt.stdout.trim(), "utf8");
      assert.equal(validateView(mapHtml).ok, true);
      const builtStyle = /<style>([\s\S]*?)<\/style>/i.exec(mapHtml)?.[1] ?? "";
      assert.ok(flat(builtStyle).startsWith(flat(stripTokenComment(TOKENS))), "built map-view must open <style> with html-tokens.css");
      assert.match(mapHtml, /data-rv-theme="system"/);
      assert.doesNotMatch(mapHtml, /class="rv-brand"/);

      const deepBuilt = spawnSync("node", [BUILD_VIEW, "deepening", "--record", DEEPENING_FIXTURE], {
        cwd: work,
        encoding: "utf8",
        env,
      });
      assert.equal(deepBuilt.status, 0, deepBuilt.stderr);
      const deepHtml = readFileSync(deepBuilt.stdout.trim(), "utf8");
      assert.equal(validateDeepeningPage(deepHtml).ok, true);
      assert.match(deepHtml, /data-rv-theme="system"/);
      assert.doesNotMatch(deepHtml, /class="rv-brand"/);
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });

  test("applies team palette, type, font, PNG logo and label overrides to both map-view and deepening report", () => {
    const dir = makeBrandedRepo(
      [
        "branding:",
        "  palette:",
        "    light:",
        "      bg: '#F7F8FA'",
        "      fg: '#101828'",
        "      muted: '#475467'",
        "      link: '#1D4ED8'",
        "      focus: '#1D4ED8'",
        "      accent: '#1D4ED8'",
        "    dark:",
        "      accent: '#60A5FA'",
        "  type:",
        "    serif: \"'Brand Serif', Georgia, serif\"",
        "    fonts:",
        "      - family: Brand Serif",
        "        file: assets/brand.woff2",
        "        weight: '600'",
        "  logo:",
        "    file: assets/mark.png",
        "    label: Northwind Architecture",
        "",
      ].join("\n"),
      {
        "assets/mark.png": PNG_1X1,
        "assets/brand.woff2": WOFF2_STUB,
      },
    );
    const outTmp = mkdtempSync(join(tmpdir(), "arch-branded-out-"));
    try {
      const mapRecord = join(outTmp, "map.json");
      writeFileSync(mapRecord, JSON.stringify(MAP_RECORD));
      const env = { ...process.env, TMPDIR: outTmp, TEMP: outTmp, TMP: outTmp };

      const mapBuilt = spawnSync("node", [BUILD_VIEW, "dependencies", "--record", mapRecord], {
        cwd: dir,
        encoding: "utf8",
        env,
      });
      assert.equal(mapBuilt.status, 0, mapBuilt.stderr);
      const mapHtml = readFileSync(mapBuilt.stdout.trim(), "utf8");
      assert.deepEqual(validateView(mapHtml), { ok: true, failures: [] });
      assert.match(mapHtml, /--bg: #F7F8FA;/);
      assert.match(mapHtml, /--serif: 'Brand Serif', Georgia, serif;/);
      assert.match(mapHtml, /@font-face \{ font-family: 'Brand Serif'; font-style: normal; font-weight: 600; src: url\(data:font\/woff2;base64,/);
      assert.match(mapHtml, /\.rv-logo \{ background-image: url\(data:image\/png;base64,/);
      assert.match(mapHtml, /<div class="rv-bar"><div class="rv-brand"><span class="rv-brand-mark rv-logo"/);
      assert.match(mapHtml, /Northwind Architecture/);
      assert.match(mapHtml, /data-rv-theme="system"/);
      assert.match(mapHtml, /prefers-reduced-motion: reduce/);

      const deepBuilt = spawnSync("node", [BUILD_VIEW, "deepening", "--record", DEEPENING_FIXTURE], {
        cwd: dir,
        encoding: "utf8",
        env,
      });
      assert.equal(deepBuilt.status, 0, deepBuilt.stderr);
      const deepHtml = readFileSync(deepBuilt.stdout.trim(), "utf8");
      assert.deepEqual(validateDeepeningPage(deepHtml), { ok: true, failures: [] });
      assert.match(deepHtml, /font-src data:/);
      assert.match(deepHtml, /--bg: #F7F8FA;/);
      assert.match(deepHtml, /@font-face \{ font-family: 'Brand Serif'; font-style: normal; font-weight: 600; src: url\(data:font\/woff2;base64,/);
      assert.match(deepHtml, /\.rv-logo \{ background-image: url\(data:image\/png;base64,/);
      assert.match(deepHtml, /<div class="rv-bar"><div class="rv-brand"><span class="rv-brand-mark rv-logo"/);
      assert.match(deepHtml, /Northwind Architecture/);
      assert.match(deepHtml, /data-rv-theme="system"/);
      assert.match(deepHtml, /prefers-reduced-motion: reduce/);
      assert.match(deepHtml, /:focus-visible/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
      rmSync(outTmp, { recursive: true, force: true });
    }
  });

  test("enforces contrast floor with stderr notice and reads userConfig.branding via CLAUDE_CONFIG_DIR when --branding-option is omitted", () => {
    const work = mkdtempSync(join(tmpdir(), "arch-floor-"));
    try {
      const cfgDir = join(work, "claude-cfg");
      mkdirSync(cfgDir, { recursive: true });
      const brandingJson = JSON.stringify({
        palette: { light: { bg: "#FFFFFF", fg: "#CCCCCC", accent: "#1D4ED8" } },
        logo: { label: "ConfigDir Brand" },
      });
      writeFileSync(
        join(cfgDir, "settings.json"),
        JSON.stringify({
          pluginConfigs: {
            "architecture@melodic-software": { options: { branding: brandingJson } },
          },
        }),
      );
      const mapRecord = join(work, "map.json");
      writeFileSync(mapRecord, JSON.stringify(MAP_RECORD));
      const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work, CLAUDE_CONFIG_DIR: cfgDir };

      const mapBuilt = spawnSync("node", [BUILD_VIEW, "dependencies", "--record", mapRecord], {
        cwd: work,
        encoding: "utf8",
        env,
      });
      assert.equal(mapBuilt.status, 0, mapBuilt.stderr);
      const mapHtml = readFileSync(mapBuilt.stdout.trim(), "utf8");
      assert.deepEqual(validateView(mapHtml), { ok: true, failures: [] });
      assert.match(mapHtml, /ConfigDir Brand/);
      assert.match(mapHtml, /--accent: #1D4ED8;/);
      assert.doesNotMatch(mapHtml, /--fg: #CCCCCC;/);
      assert.match(mapBuilt.stderr, /notice:.*contrast/i);

      const deepBuilt = spawnSync("node", [BUILD_VIEW, "deepening", "--record", DEEPENING_FIXTURE], {
        cwd: work,
        encoding: "utf8",
        env,
      });
      assert.equal(deepBuilt.status, 0, deepBuilt.stderr);
      const deepHtml = readFileSync(deepBuilt.stdout.trim(), "utf8");
      assert.deepEqual(validateDeepeningPage(deepHtml), { ok: true, failures: [] });
      assert.match(deepHtml, /ConfigDir Brand/);
      assert.match(deepHtml, /--accent: #1D4ED8;/);
      assert.doesNotMatch(deepHtml, /--fg: #CCCCCC;/);
      assert.match(deepBuilt.stderr, /notice:.*contrast/i);
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });

  test("inline SVG logo passes validateDeepeningPage and validateView via --branding-option, while hostile CSS still fails", () => {
    const work = mkdtempSync(join(tmpdir(), "arch-svg-"));
    try {
      const brandingOption = JSON.stringify({
        logo: {
          svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" aria-label="Acme"><rect width="16" height="16" fill="currentColor"/></svg>',
          label: "Acme",
        },
      });
      const mapRecord = join(work, "map.json");
      writeFileSync(mapRecord, JSON.stringify(MAP_RECORD));
      const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work };

      const mapBuilt = spawnSync("node", [BUILD_VIEW, "landscape", "--record", mapRecord, "--branding-option", brandingOption], {
        cwd: work,
        encoding: "utf8",
        env,
      });
      assert.equal(mapBuilt.status, 0, mapBuilt.stderr);
      const mapHtml = readFileSync(mapBuilt.stdout.trim(), "utf8");
      assert.deepEqual(validateView(mapHtml), { ok: true, failures: [] });
      assert.match(mapHtml, /<div class="rv-brand"><svg /);

      const deepBuilt = spawnSync("node", [BUILD_VIEW, "deepening", "--record", DEEPENING_FIXTURE, "--branding-option", brandingOption], {
        cwd: work,
        encoding: "utf8",
        env,
      });
      assert.equal(deepBuilt.status, 0, deepBuilt.stderr);
      const deepHtml = readFileSync(deepBuilt.stdout.trim(), "utf8");
      assert.deepEqual(validateDeepeningPage(deepHtml), { ok: true, failures: [] });
      assert.match(deepHtml, /<div class="rv-brand"><svg /);

      const badCss = deepHtml.replace("</style>", "\nbody { background: url(https://evil.example/a.png); }\n</style>");
      assert.equal(validateDeepeningPage(badCss).ok, false);

      const rawLtCss = deepHtml.replace("</style>", "\n/* < */\n</style>");
      assert.equal(validateDeepeningPage(rawLtCss).ok, false);

      const smuggledComment = deepHtml.replace("</body>", "<!-- <style> --><b>ok</b></style> --></body>");
      assert.equal(validateDeepeningPage(smuggledComment).ok, false);

      const abruptComment = deepHtml.replace("</body>", "<!--><img src=x onerror=alert(1)>--></body>");
      assert.equal(validateDeepeningPage(abruptComment).ok, false);

      const bangCloseComment = deepHtml.replace("</body>", "<!-- a --!><img src=x onerror=alert(1)> --></body>");
      assert.equal(validateDeepeningPage(bangCloseComment).ok, false);

      const badXmlns = deepHtml.replace('xmlns="http://www.w3.org/2000/svg"', 'xmlns="http://evil.example/svg"');
      assert.equal(validateDeepeningPage(badXmlns).ok, false);
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });

  test("renderDeepening without branding keeps validateDeepeningPage passing with no logo slot", () => {
    const parsed = parseDeepening(JSON.parse(readFileSync(DEEPENING_FIXTURE, "utf8")));
    const html = renderDeepening(parsed);
    assert.deepEqual(validateDeepeningPage(html), { ok: true, failures: [] });
    assert.doesNotMatch(html, /class="rv-brand"/);
  });

  test("validateDeepeningPage accepts resolver SVG aria-* attributes while rejecting aria-describedby on non-SVG elements", () => {
    const work = mkdtempSync(join(tmpdir(), "arch-svg-aria-"));
    try {
      const brandingOption = JSON.stringify({
        logo: {
          svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" aria-describedby="logo-desc" aria-labelledby="logo-title logo-desc"><desc id="logo-desc">Company logo</desc><rect width="16" height="16" fill="currentColor"/></svg>',
          label: "Acme",
        },
      });
      const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work };
      const deepBuilt = spawnSync("node", [BUILD_VIEW, "deepening", "--record", DEEPENING_FIXTURE, "--branding-option", brandingOption], {
        cwd: work,
        encoding: "utf8",
        env,
      });
      assert.equal(deepBuilt.status, 0, deepBuilt.stderr);
      const deepHtml = readFileSync(deepBuilt.stdout.trim(), "utf8");
      assert.deepEqual(validateDeepeningPage(deepHtml), { ok: true, failures: [] });
      assert.match(deepHtml, /aria-describedby="logo-desc"/);

      const nonSvgAria = deepHtml.replace('<div class="rv-bar">', '<div class="rv-bar" aria-describedby="logo-desc">');
      const checked = validateDeepeningPage(nonSvgAria);
      assert.equal(checked.ok, false);
      assert.ok(checked.failures.includes("attr:aria-describedby"));
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });

  test("branding labels and SVG logos containing {{ build cleanly in interactive map-view", () => {
    const work = mkdtempSync(join(tmpdir(), "arch-braces-"));
    try {
      const mapRecord = join(work, "map.json");
      writeFileSync(mapRecord, JSON.stringify(MAP_RECORD));
      const brandingOption = JSON.stringify({
        logo: {
          svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" aria-label="{{ Acme }}"><rect width="16" height="16" fill="currentColor"/></svg>',
          label: "{{ Acme }}",
        },
      });
      const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work };
      const mapBuilt = spawnSync("node", [BUILD_VIEW, "dependencies", "--record", mapRecord, "--branding-option", brandingOption], {
        cwd: work,
        encoding: "utf8",
        env,
      });
      assert.equal(mapBuilt.status, 0, mapBuilt.stderr);
      const mapHtml = readFileSync(mapBuilt.stdout.trim(), "utf8");
      assert.deepEqual(validateView(mapHtml), { ok: true, failures: [] });
      const labelHtml = /<span class="rv-brand-label">([\s\S]*?)<\/span>(?=<\/div>)/.exec(mapHtml)?.[1] ?? "";
      assert.equal(labelHtml.replace(/<[^>]+>/g, ""), "{{ Acme }}");

      const envBuilt = spawnSync(
        "node",
        [BUILD_VIEW, "dependencies", "--record", mapRecord, "--branding-option", "${user_config.branding}"],
        {
          cwd: work,
          encoding: "utf8",
          env: { ...env, CLAUDE_PLUGIN_OPTION_BRANDING: JSON.stringify({ logo: { label: "Env Brand" } }) },
        },
      );
      assert.equal(envBuilt.status, 0, envBuilt.stderr);
      const envHtml = readFileSync(envBuilt.stdout.trim(), "utf8");
      assert.deepEqual(validateView(envHtml), { ok: true, failures: [] });
      assert.match(envHtml, /Env Brand/);
      assert.equal(envBuilt.stderr, "");
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });
});
