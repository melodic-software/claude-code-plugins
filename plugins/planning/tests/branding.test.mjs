import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { stripTokenComment } from "../lib/html-branding.mjs";
import { validateView } from "../lib/view-builder.mjs";
process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN = join(HERE, "..");
const TOKENS = readFileSync(join(PLUGIN, "reference", "html-tokens.css"), "utf8");
const BUILD_VIEW = join(PLUGIN, "scripts", "build-view.mjs");
const PLAN_FIXTURE = readFileSync(join(PLUGIN, "scripts", "testdata", "plan-record.md"), "utf8");
const DESIGN_FIXTURE = [
  "# Plan: Cache",
  "",
  "## Design",
  "",
  "Gate: PASS.",
  "",
  "### Module layout",
  "",
  "| Module | Owns |",
  "",
  "## Plan",
  "",
].join("\n");
const BRAINSTORM_FIXTURE = JSON.stringify({
  title: "Onboarding drop-off",
  problem: "Users leave during onboarding.",
  candidates: [
    {
      effort: "small",
      name: "Shorten the form",
      what: "Drop two fields.",
      where: "web/onboarding/form.tsx",
      impact: "Fewer abandoned forms.",
    },
  ],
});

const TEMPLATES = [
  ["plan", join(PLUGIN, "skills", "plan", "templates", "plan-view.html"), PLAN_FIXTURE],
  ["brainstorm", join(PLUGIN, "skills", "brainstorm", "templates", "brainstorm-view.html"), BRAINSTORM_FIXTURE],
  ["design", join(PLUGIN, "skills", "design", "templates", "design-view.html"), DESIGN_FIXTURE],
];

const PNG_1X1 = Buffer.from(
  "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082",
  "hex",
);
const WOFF2_STUB = Buffer.concat([Buffer.from("wOF2"), Buffer.alloc(16, 0x41)]);

const flat = (css) => css.replace(/\r\n?/g, "\n").replace(/^[ \t]+/gm, "").trim();

function runGit(cwd, args) {
  const res = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8" });
  if (res.status !== 0) throw new Error(`git ${args.join(" ")} failed: ${res.stderr}`);
}

function makeBrandedRepo(yamlBody, assets = {}) {
  const dir = mkdtempSync(join(tmpdir(), "plan-brand-"));
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

describe("planning token layer compliance", () => {
  test("all three view templates open with reference/html-tokens.css verbatim and define no literal hex outside it", () => {
    const tokens = stripTokenComment(TOKENS);
    for (const [kind, templatePath] of TEMPLATES) {
      const html = readFileSync(templatePath, "utf8");
      const style = /<style>([\s\S]*?)<\/style>/i.exec(html)?.[1] ?? "";
      assert.ok(flat(style).startsWith(flat(tokens)), `${kind}: must open <style> with html-tokens.css`);
      const rest = flat(style).slice(flat(tokens).length);
      assert.doesNotMatch(rest, /#[0-9A-Fa-f]{3,8}\b/, `${kind}: no literal hex outside token layer`);
      assert.match(html, /data-rv-theme="system"/);
      assert.match(html, /class="rv-comment"/);
      assert.doesNotMatch(html, /data-accent|data-palette|accent picker|palette picker/i);
    }
  });
});

describe("planning branded view builds", () => {
  test("with no branding set, all three views render defaults cleanly with toggle, comment box, and no brand slot", () => {
    const work = mkdtempSync(join(tmpdir(), "plan-default-"));
    try {
      const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work };
      for (const [kind, , input] of TEMPLATES) {
        const res = spawnSync("node", [BUILD_VIEW, kind], { cwd: work, input, encoding: "utf8", env });
        assert.equal(res.status, 0, `${kind}: ${res.stderr}`);
        const html = readFileSync(res.stdout.trim(), "utf8");
        assert.deepEqual(validateView(html), { ok: true, failures: [] }, `${kind} should validate`);
        assert.match(html, /data-rv-theme="system"/);
        assert.match(html, /class="rv-comment"/);
        assert.doesNotMatch(html, /class="rv-brand"/);
      }
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });

  test("applies team palette, type, font, PNG logo and label overrides across plan, brainstorm and design", () => {
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
        "    label: Northwind Planning",
        "",
      ].join("\n"),
      {
        "assets/mark.png": PNG_1X1,
        "assets/brand.woff2": WOFF2_STUB,
      },
    );
    const outTmp = mkdtempSync(join(tmpdir(), "plan-branded-out-"));
    try {
      const env = { ...process.env, TMPDIR: outTmp, TEMP: outTmp, TMP: outTmp };
      for (const [kind, , input] of TEMPLATES) {
        const res = spawnSync("node", [BUILD_VIEW, kind], { cwd: dir, input, encoding: "utf8", env });
        assert.equal(res.status, 0, `${kind}: ${res.stderr}`);
        const html = readFileSync(res.stdout.trim(), "utf8");
        assert.deepEqual(validateView(html), { ok: true, failures: [] }, `${kind} should validate`);
        assert.match(html, /--bg: #F7F8FA;/);
        assert.match(html, /--serif: 'Brand Serif', Georgia, serif;/);
        assert.match(html, /@font-face \{ font-family: 'Brand Serif'; font-style: normal; font-weight: 600; src: url\(data:font\/woff2;base64,/);
        assert.match(html, /\.rv-logo \{ background-image: url\(data:image\/png;base64,/);
        assert.match(html, /<div class="rv-bar"><div class="rv-brand"><span class="rv-brand-mark rv-logo"/);
        assert.match(html, /Northwind Planning/);
        assert.match(html, /data-rv-theme="system"/);
        assert.match(html, /class="rv-comment"/);
        assert.match(html, /prefers-reduced-motion: reduce/);
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
      rmSync(outTmp, { recursive: true, force: true });
    }
  });

  test("enforces contrast floor and supports inline SVG logo via --branding-option", () => {
    const work = mkdtempSync(join(tmpdir(), "plan-svg-"));
    try {
      const option = JSON.stringify({
        palette: {
          light: { bg: "#FFFFFF", fg: "#F5F5F5" },
        },
        logo: {
          svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" aria-label="Acme"><rect width="16" height="16" fill="currentColor"/></svg>',
          label: "Acme",
        },
      });
      const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work };
      const res = spawnSync("node", [BUILD_VIEW, "plan", "--branding-option", option], {
        cwd: work,
        input: PLAN_FIXTURE,
        encoding: "utf8",
        env,
      });
      assert.equal(res.status, 0, res.stderr);
      const html = readFileSync(res.stdout.trim(), "utf8");
      assert.deepEqual(validateView(html), { ok: true, failures: [] });
      assert.match(html, /<div class="rv-brand"><svg /);
      assert.doesNotMatch(html, /--fg: #F5F5F5;/);
      assert.match(res.stderr, /contrast/i);
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });

  test("reads userConfig.branding via CLAUDE_CONFIG_DIR/settings.json when --branding-option is omitted", () => {
    const work = mkdtempSync(join(tmpdir(), "plan-cfgdir-"));
    try {
      const cfgDir = join(work, "claude-cfg");
      mkdirSync(cfgDir, { recursive: true });
      const brandingJson = JSON.stringify({
        palette: { light: { accent: "#1D4ED8" } },
        logo: { label: "ConfigDir Planning" },
      });
      writeFileSync(
        join(cfgDir, "settings.json"),
        JSON.stringify({
          pluginConfigs: {
            "planning@melodic-software": { options: { branding: brandingJson } },
          },
        }),
      );
      const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work, CLAUDE_CONFIG_DIR: cfgDir };
      const res = spawnSync("node", [BUILD_VIEW, "plan"], {
        cwd: work,
        input: PLAN_FIXTURE,
        encoding: "utf8",
        env,
      });
      assert.equal(res.status, 0, res.stderr);
      const html = readFileSync(res.stdout.trim(), "utf8");
      assert.deepEqual(validateView(html), { ok: true, failures: [] });
      assert.match(html, /--accent: #1D4ED8;/);
      assert.match(html, /ConfigDir Planning/);
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });
});
