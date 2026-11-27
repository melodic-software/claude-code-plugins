#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment (node missing).
# test-scope: plugins/harness-ops/skills/observability/SKILL.md
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "build-dashboard: node not found on PATH" >&2
  exit 2
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node --input-type=module - "$SCRIPT_DIR" "$work" <<'NODE'
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const dir = process.argv[2];
const work = process.argv[3];
const builderPath = `${dir}/build-dashboard.mjs`;
const { buildDashboardPage } = await import(pathToFileURL(builderPath).href);
const { escapeHtml, validateRenderedPage } = await import(
  pathToFileURL(`${dir}/../../../lib/html-escape.mjs`).href
);

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
    failed += 1;
  }
};

const hostile = [
  "</script><img src=x onerror=alert(1)>",
  `"><script>alert(1)</script>`,
  `'><img src=x onerror=alert(1)>`,
  "`${alert(1)}`",
  `" onmouseover="alert(1)`,
  "</title><style>@import 'x'</style>",
  "javascript:alert(1)",
  "&lt;already",
];
const model = {
  title: hostile[0],
  scope: hostile[1],
  metrics: [
    { name: hostile[2], value: hostile[3], note: hostile[4] },
    { name: "tokens", value: "12", note: hostile[5] },
  ],
  tables: [
    { title: hostile[6], columns: [hostile[7], hostile[0]], rows: [[hostile[1], hostile[2]], [hostile[3]]] },
    { title: "hooks", columns: ["hook"], rows: [[hostile[4]], [hostile[5]]] },
  ],
  findings: [hostile[6], hostile[7]],
};

const page = buildDashboardPage(model);
const verdict = validateRenderedPage(page);
check("the builder is deterministic", page === buildDashboardPage(model));
check("a hostile model still passes the validator", verdict.ok, verdict.failures.join(","));
check("no live script tag", !/<script[\s>]/i.test(page)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("no live img tag", !page.includes("<img"));
check("no href or event-handler attribute", !page.includes("href=") && !/\son[a-z]+=/i.test(page.replace(/>[^<]*</g, "><"))); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check(
  "every hostile string appears escaped",
  hostile.every((item) => page.includes(escapeHtml(item))),
);
check("backticks pass through as text", page.includes("`${alert(1)}`"));
check("an empty model still validates", validateRenderedPage(buildDashboardPage({})).ok);
check(
  "a malformed model still validates",
  validateRenderedPage(
    buildDashboardPage({ title: { a: 1 }, metrics: "x", tables: [{ columns: 3, rows: ["x", [null]] }, 5], findings: 7 }),
  ).ok,
);

const cli = spawnSync(process.execPath, [builderPath], { input: JSON.stringify(model), encoding: "utf8" });
check("the CLI emits the same page as the function", cli.status === 0 && cli.stdout === page, cli.stderr);
check("invalid JSON exits 2", spawnSync(process.execPath, [builderPath], { input: "{", encoding: "utf8" }).status === 2);
writeFileSync(`${work}/page.html`, page);
check("--check accepts a builder page", spawnSync(process.execPath, [builderPath, "--check", `${work}/page.html`]).status === 0);
writeFileSync(`${work}/hand.html`, `<!doctype html><html><head></head><body><h1>${hostile[0]}</h1></body></html>`);
check("--check flags a hand-written page", spawnSync(process.execPath, [builderPath, "--check", `${work}/hand.html`]).status === 1);

const source = readFileSync(builderPath, "utf8");
const pageFn = source.slice(source.indexOf("function tableSection"), source.indexOf("function fail"));
const stray = (pageFn.match(/\$\{[^}]+\}/g) ?? []).filter(
  (item) => !/^\$\{(?:e\(|styleBlock|barHtml|metricRows\(|numbered\(|objects\(|columns\.map|row\.map|body)/.test(item),
);
check("the page template interpolates only escaped calls or built fragments", stray.length === 0, stray.join(" "));
check("build-dashboard defines no literal palette hex color", !/#[0-9a-fA-F]{3,8}(?![0-9a-fA-F])/.test(source));

const brandRepo = `${work}/brand-repo`;
const emptyHome = `${work}/empty-home`;
mkdirSync(`${brandRepo}/docs/conventions`, { recursive: true });
mkdirSync(`${brandRepo}/assets`, { recursive: true });
mkdirSync(emptyHome, { recursive: true });
spawnSync("git", ["init", "-q", brandRepo], { encoding: "utf8" });
writeFileSync(`${brandRepo}/assets/logo.png`, Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=", "base64"));
writeFileSync(`${brandRepo}/docs/conventions/rendered-views.yaml`, [
  "branding:",
  "  palette:",
  "    light:",
  '      bg: "#F8F4EC"',
  '      muted: "#595954"',
  '      link: "#1A4D8F"',
  '      fg: "#CCCCCC"',
  "  type:",
  '    sans: "IBM Plex Sans, sans-serif"',
  "  logo:",
  '    file: "assets/logo.png"',
  '    label: "Acme Ops"',
].join("\n") + "\n");
const brandEnv = { ...process.env, CLAUDE_PROJECT_DIR: brandRepo, HOME: emptyHome, USERPROFILE: emptyHome, CLAUDE_PLUGIN_OPTION_BRANDING: "" };
const brandedCli = spawnSync(process.execPath, [builderPath], { input: JSON.stringify(model), encoding: "utf8", env: brandEnv });
const brandedPage = brandedCli.stdout;
check("branded dashboard builds and validates", brandedCli.status === 0 && validateRenderedPage(brandedPage).ok, brandedCli.stderr);
check("branded dashboard emits contrast-floor notice on stderr", brandedCli.stderr.includes("notice:") && brandedCli.stderr.includes("fg"));
const brandedStyle = /<style>([^]*?)<\/style>/i.exec(brandedPage)?.[1] ?? "";
check("branded dashboard strips all leading token header comments", !brandedStyle.includes("GENERATED") && !brandedStyle.includes("Provenance:"));
check("branded dashboard applies tokens, overrides, raster logo slot and enforces floor",
  brandedPage.includes("--ivory: #FAF9F5;") &&
  brandedPage.includes("--bg: #F8F4EC;") &&
  !brandedPage.includes("--fg: #CCCCCC;") &&
  brandedPage.includes("--sans: IBM Plex Sans, sans-serif;") &&
  brandedPage.includes('class="rv-brand-mark rv-logo"') &&
  brandedPage.includes("Acme Ops") &&
  brandedPage.includes("outline: 3px solid var(--focus)"));
const optEnv = { ...process.env, CLAUDE_PROJECT_DIR: emptyHome, HOME: emptyHome, USERPROFILE: emptyHome, CLAUDE_PLUGIN_OPTION_BRANDING: "" };
const optCli = spawnSync(process.execPath, [builderPath, "--branding-option", '{"logo":{"label":"CLI Ops","svg":"<svg viewBox=\\"0 0 16 16\\" xmlns=\\"http://www.w3.org/2000/svg\\"><circle cx=\\"8\\" cy=\\"8\\" r=\\"6\\"/></svg>"}}'], { input: JSON.stringify(model), encoding: "utf8", env: optEnv });
check("--branding-option applies label and emits SVG omission notice on stderr",
  optCli.status === 0 && validateRenderedPage(optCli.stdout).ok && optCli.stdout.includes("CLI Ops") && optCli.stderr.includes("notice:") && optCli.stderr.includes("PNG or JPEG"), optCli.stderr);

const skill = readFileSync(`${dir}/../SKILL.md`, "utf8");
check(
  "the lane routes the page through the builder",
  skill.includes("build-dashboard.mjs") && skill.includes("Do not hand-write the HTML"),
);

if (failed > 0) process.exit(1);
NODE

echo "build-dashboard: all cases passed"
