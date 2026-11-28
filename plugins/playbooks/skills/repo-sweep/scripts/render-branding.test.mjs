import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { resolveBranding } from "../../../lib/view-settings.mjs";
import { applyBrandingToHtml, readConfiguredBranding } from "./apply-branding.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const RENDER_SH = join(HERE, "render.sh");
const CATALOG = join(HERE, "testdata/fixture.md");
const TEMPLATE_PATH = join(HERE, "../../../reference/repo-sweep-plan-page.html");
const TOKENS_PATH = join(HERE, "../../../reference/html-tokens.css");
const PNG_1X1 = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  "base64",
);

const RECS_TSV = [
  "dead-code\trun\tnever ran: a:x",
  "residue-dissolve\trerun\tversion changed: c:x 1.0 -> 1.1",
  "testing-audit\tnot-applicable\trepo has no tests",
  "tidy\trun\tnever ran: c:t",
  "prompt-audit\trerun-optional\tsame version ran: claude-api@builtin-2.1.283",
].join("\n") + "\n";

function withTempRepo(fn) {
  const root = mkdtempSync(join(tmpdir(), "playbooks-branding-"));
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_SYSTEM: "/dev/null" };
  try {
    execFileSync("git", ["-C", root, "init", "-q"], { env });
    return fn(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function renderPage(root, { brandingOption = "", configDir = join(root, "empty-claude-config"), pathOverride = null } = {}) {
  const recs = join(root, "recs.tsv");
  writeFileSync(recs, RECS_TSV);
  const env = {
    ...process.env,
    CLAUDE_PROJECT_DIR: root,
    CLAUDE_CONFIG_DIR: configDir,
    CLAUDE_PLUGIN_OPTION_BRANDING: brandingOption,
  };
  if (pathOverride !== null) env.PATH = pathOverride;
  return execFileSync("bash", [RENDER_SH, "--page", CATALOG, recs], { encoding: "utf8", env });
}

test("repo-sweep plan template defines no literal palette role or type-stack custom properties", () => {
  const tpl = readFileSync(TEMPLATE_PATH, "utf8");
  const style = tpl.slice(tpl.indexOf("<style>"), tpl.indexOf("</style>"));
  assert.doesNotMatch(style, /--(?:bg|fg|panel|muted|accent|link|focus|serif|sans|mono)\s*:/);
  assert.doesNotMatch(style, /#(?:FAF9F5|141413|D1CFC5)/i);
  assert.match(style, /background:\s*var\(--bg\)/);
  assert.match(style, /color:\s*var\(--fg\)/);
  assert.match(style, /font-family:\s*var\(--sans\)/);
  assert.match(style, /font-family:\s*var\(--mono\)/);
});

test("default render inlines html-tokens.css, omits .rv-brand, and preserves toggle, comment box, and floor", () => {
  withTempRepo((root) => {
    const html = renderPage(root);
    assert.match(html, /--ivory:\s*#FAF9F5;/);
    assert.match(html, /--bg:\s*var\(--ivory\);/);
    assert.match(html, /--fg:\s*var\(--slate\);/);
    assert.doesNotMatch(html, /class="rv-brand"/);
    assert.match(html, /<button type="button" data-rv-theme="system" aria-pressed="true">System<\/button>/);
    assert.match(html, /<button type="button" data-rv-theme="light" aria-pressed="false">Light<\/button>/);
    assert.match(html, /<button type="button" data-rv-theme="dark" aria-pressed="false">Dark<\/button>/);
    assert.match(html, /<textarea id="rv-comment-text" data-rv-note="comment"/);
    assert.match(html, /prefers-reduced-motion:\s*reduce/);
    assert.match(html, /:focus-visible[\s\S]*outline:\s*3px solid var\(--focus\)/);
  });
});

test("branding override applies palette, type, and inline SVG logo in .rv-bar while keeping toggle and comment box", () => {
  withTempRepo((root) => {
    mkdirSync(join(root, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(root, "docs/conventions/rendered-views.yaml"),
      [
        "branding:",
        "  palette:",
        "    light:",
        '      bg: "#FFFFFF"',
        '      fg: "#111111"',
        '      muted: "#595959"',
        "    dark:",
        '      bg: "#0F172A"',
        '      fg: "#F8FAFC"',
        "  type:",
        '    sans: "Inter, system-ui, sans-serif"',
        "  logo:",
        '    svg: \'<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"/></svg>\'',
        '    label: "Acme & Co"',
        "",
      ].join("\n"),
    );
    const html = renderPage(root);
    assert.match(html, /:root \{ --bg: #FFFFFF; --fg: #111111; --muted: #595959; --sans: Inter, system-ui, sans-serif; \}/);
    assert.match(html, /:root\[data-theme=dark\] \{ --bg: #0F172A; --fg: #F8FAFC; \}/);
    assert.match(html, /<div class="rv-bar"><div class="rv-brand"><svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"\/><\/svg><span class="rv-brand-label">Acme &amp; Co<\/span><\/div><div class="rv-theme"/);
    assert.match(html, /\.rv-brand \{ display: inline-flex;/);
    assert.match(html, /data-rv-theme="system"/);
    assert.match(html, /data-rv-note="comment"/);
  });
});

test("raster PNG logo renders .rv-brand-mark.rv-logo with base64 background-image", () => {
  withTempRepo((root) => {
    mkdirSync(join(root, "docs/conventions/assets"), { recursive: true });
    writeFileSync(join(root, "docs/conventions/assets/logo.png"), PNG_1X1);
    writeFileSync(
      join(root, "docs/conventions/rendered-views.yaml"),
      ["branding:", "  logo:", '    file: "docs/conventions/assets/logo.png"', '    label: "Brand Mark"', ""].join("\n"),
    );
    const html = renderPage(root);
    assert.match(html, /<span class="rv-brand-mark rv-logo" role="img" aria-label="Brand Mark"><\/span>/);
    assert.match(html, /\.rv-logo \{ background-image: url\(data:image\/png;base64,/);
  });
});

test("below-floor contrast override is dropped back to shipped value with a notice", () => {
  withTempRepo((root) => {
    mkdirSync(join(root, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(root, "docs/conventions/rendered-views.yaml"),
      ["branding:", "  palette:", "    light:", '      bg: "#FAF9F5"', '      fg: "#F5F4F0"', ""].join("\n"),
    );
    const branding = resolveBranding({ projectRoot: root });
    assert.equal(branding.palette.light.fg, "#141413");
    assert.ok(
      branding.notices.some((n) => n.text.includes("fg") && n.text.includes("light") && n.text.includes("4.5")),
      `expected contrast-floor notice, got: ${JSON.stringify(branding.notices)}`,
    );
    const html = applyBrandingToHtml(readFileSync(TEMPLATE_PATH, "utf8"), {
      tokensCss: readFileSync(TOKENS_PATH, "utf8"),
      branding,
    });
    assert.doesNotMatch(html, /--fg:\s*#F5F4F0/i);
    const cli = spawnSync("node", [join(HERE, "apply-branding.mjs"), "--project-root", root], {
      input: readFileSync(TEMPLATE_PATH, "utf8"),
      encoding: "utf8",
    });
    assert.equal(cli.status, 0);
    assert.match(cli.stderr, /notice:.*light fg:.*4\.5/);
    assert.doesNotMatch(cli.stdout, /--fg:\s*#F5F4F0/i);
  });
});

test("theme toggle handler pins data-theme on light/dark and removes it on system", () => {
  const tpl = readFileSync(TEMPLATE_PATH, "utf8");
  const scripts = [...tpl.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 1);
  const listeners = [];
  const attrs = new Map();
  const makeBtn = (choice) => {
    const bAttrs = new Map([["data-rv-theme", choice], ["aria-pressed", String(choice === "system")]]);
    return {
      getAttribute: (k) => bAttrs.get(k) ?? null,
      setAttribute: (k, v) => bAttrs.set(k, String(v)),
      closest: (sel) => (sel === "button[data-rv-theme]" ? true : null),
    };
  };
  const buttons = [makeBtn("system"), makeBtn("light"), makeBtn("dark")];
  for (const b of buttons) b.closest = (sel) => (sel === "button[data-rv-theme]" ? b : null);
  const elStub = () => ({ textContent: "", value: "", addEventListener: () => {}, appendChild: () => {}, select: () => {} });
  const elements = {
    "repo-sweep-data": { textContent: JSON.stringify({ playbook: "fixture", entries: [] }) },
    title: elStub(),
    groups: elStub(),
    line: elStub(),
    "copy-btn": elStub(),
  };
  const document = {
    documentElement: {
      setAttribute: (k, v) => attrs.set(k, v),
      removeAttribute: (k) => attrs.delete(k),
    },
    getElementById: (id) => elements[id],
    createElement: () => elStub(),
    querySelectorAll: (sel) => (sel === "button[data-rv-theme]" ? buttons : []),
    addEventListener: (ev, fn) => { if (ev === "click") listeners.push(fn); },
  };
  new Function("document", "navigator", scripts[0][1])(document, {});
  assert.equal(listeners.length, 1);

  listeners[0]({ target: buttons[2] });
  assert.equal(attrs.get("data-theme"), "dark");
  assert.equal(buttons[2].getAttribute("aria-pressed"), "true");
  assert.equal(buttons[0].getAttribute("aria-pressed"), "false");

  listeners[0]({ target: buttons[1] });
  assert.equal(attrs.get("data-theme"), "light");
  assert.equal(buttons[1].getAttribute("aria-pressed"), "true");

  listeners[0]({ target: buttons[0] });
  assert.equal(attrs.has("data-theme"), false);
  assert.equal(buttons[0].getAttribute("aria-pressed"), "true");
});

test("reads userConfig.branding from Claude settings without CLAUDE_PLUGIN_OPTION_BRANDING", () => {
  withTempRepo((root) => {
    const configDir = join(root, "claude-config");
    const cachedPluginRoot = join(configDir, "plugins", "cache", "test-mkt", "playbooks", "1.0.0");
    mkdirSync(cachedPluginRoot, { recursive: true });
    const configured = JSON.stringify({
      palette: { light: { bg: "#FFFFFF", fg: "#101828", muted: "#595959" } },
      type: { sans: "IBM Plex Sans, system-ui, sans-serif" },
    });
    writeFileSync(
      join(configDir, "settings.json"),
      JSON.stringify({ pluginConfigs: { "playbooks@test-mkt": { options: { branding: configured } } } }),
    );
    const cached = readConfiguredBranding({ pluginRoot: cachedPluginRoot, env: {}, managedFiles: [] });
    assert.equal(cached.value, configured);
    assert.deepEqual(cached.notices, []);

    const html = renderPage(root, { configDir });
    assert.match(html, /:root \{ --bg: #FFFFFF; --fg: #101828; --muted: #595959; --sans: IBM Plex Sans, system-ui, sans-serif; \}/);
  });
});

test("render.sh without node on PATH still inlines stripped html-tokens.css", () => {
  withTempRepo((root) => {
    const binDir = join(root, "bin-no-node");
    mkdirSync(binDir, { recursive: true });
    for (const tool of ["bash", "awk", "jq", "sed", "tr", "mktemp", "basename", "dirname", "grep", "rm", "cat"]) {
      const resolved = execFileSync("bash", ["-c", `command -v ${tool}`], { encoding: "utf8" }).trim();
      symlinkSync(resolved, join(binDir, tool));
    }
    const html = renderPage(root, { pathOverride: binDir });
    assert.match(html, /--ivory:\s*#FAF9F5;/);
    assert.match(html, /--bg:\s*var\(--ivory\);/);
    assert.match(html, /--fg:\s*var\(--slate\);/);
    assert.match(html, /\[data-theme=dark\]/);
    assert.doesNotMatch(html, /GENERATED/);
    assert.doesNotMatch(html, /Provenance:/);
    assert.match(html, /data-rv-theme="dark"/);
  });
});
