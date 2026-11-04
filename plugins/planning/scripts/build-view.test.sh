#!/usr/bin/env bash
# Behavioral tests for scripts/build-view.mjs: both views build through the
# shared view builder, pass the interactive profile, keep hostile data as text,
# and bind every key their template names. When a Chrome or Chromium binary is
# found (CHROME, google-chrome, chromium, or Playwright's headless shell) the
# pages are also opened from file:// to prove the runtime renders them.
#
#   bash plugins/planning/scripts/build-view.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "build-view: node not found on PATH" >&2
  exit 2
fi

chrome="${CHROME:-}"
if [[ -z "$chrome" ]]; then
  for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      chrome="$(command -v "$candidate")"
      break
    fi
  done
fi
if [[ -z "$chrome" ]]; then
  for candidate in "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-*/chrome-headless-shell; do
    [[ -x "$candidate" ]] && chrome="$candidate" && break
  done
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node --input-type=module - "$SCRIPT_DIR" "$work" "$chrome" <<'NODE'
import { chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const [dir, work, chrome] = process.argv.slice(2);
const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work };

// A data dir shaped like the one view-bridge ensure-running leaves: private, holding its session file.
const bridgeDir = (name, port = 8765) => {
  const path = `${work}/${name}`;
  mkdirSync(path, { mode: 0o700 });
  chmodSync(path, 0o700);
  writeFileSync(`${path}/.view-session.json`, JSON.stringify({ port, pid: 1 }));
  return path;
};

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
    failed += 1;
  }
};

const hostile = "</script><img src=x onerror=alert(1)><svg onload=alert(1)>\"'`${1}";
const fixtures = {
  plan: {
    template: "../skills/plan/templates/plan-view.html",
    data: {
      title: "Add caching to query handlers",
      goal: "Cache repeated query results.",
      blast: "MEDIUM",
      phases: [
        { status: "TODO", name: "Phase 1: Cache layer", what: "Add the cache.", needs: "none", criteria: ["Hit rate is logged.", "Tests pass."] },
        { status: "TODO", name: "Phase 2: Wire handlers", what: "Use the cache.", needs: "Phase 1", criteria: ["Handlers read through the cache."] },
      ],
    },
    hostile: {
      title: hostile,
      goal: hostile,
      blast: hostile,
      phases: [{ status: hostile, name: hostile, what: hostile, needs: hostile, criteria: [hostile] }],
    },
    ids: ["phases-2", "phases-1-criteria-2"],
  },
  brainstorm: {
    template: "../skills/brainstorm/templates/brainstorm-view.html",
    data: {
      title: "Onboarding drop-off",
      problem: "Users leave during onboarding.",
      candidates: [
        { effort: "small", name: "Shorten the form", what: "Drop two fields.", where: "web/onboarding/form.tsx", impact: "Fewer abandoned forms." },
        { effort: "large", name: "Guided setup", what: "Replace the form with steps.", where: "web/onboarding/", impact: "Higher activation." },
      ],
    },
    hostile: {
      title: hostile,
      problem: hostile,
      candidates: [{ effort: hostile, name: hostile, what: hostile, where: hostile, impact: hostile }],
    },
    ids: ["candidates-2"],
  },
};

const build = (kind, data) =>
  spawnSync("node", [`${dir}/build-view.mjs`, kind], { input: typeof data === "string" ? data : JSON.stringify(data), encoding: "utf8", env });
const verify = (path) => spawnSync("node", [`${dir}/../lib/view-builder.mjs`, "--check", path], { encoding: "utf8" });
const dump = (path) =>
  spawnSync(chrome, ["--headless", "--no-sandbox", "--disable-gpu", "--dump-dom", pathToFileURL(path).href], { encoding: "utf8", timeout: 60000 }).stdout ?? "";

// Keys the template binds, so a typo in a template or fixture cannot pass silently.
const keysOf = (html, attr) => [...html.matchAll(new RegExp(`${attr}="([a-z0-9-]+)"`, "g"))].map((m) => m[1]);
const has = (scope, key) => scope !== null && typeof scope === "object" && Object.hasOwn(scope, key);

for (const [kind, fixture] of Object.entries(fixtures)) {
  const html = readFileSync(`${dir}/${fixture.template}`, "utf8");
  const good = build(kind, fixture.data);
  check(`${kind}: builds under the temp directory`, good.status === 0 && good.stdout.trim().startsWith(work), good.stderr);
  const path = `${work}/${kind}-good.html`;
  copyFileSync(good.stdout.trim(), path);
  check(`${kind}: the page passes the interactive profile`, verify(path).status === 0, verify(path).stdout);
  check(`${kind}: the template carries no script of its own`, !/<script/i.test(html));

  const items = fixture.data[keysOf(html, "data-rv-each")[0]];
  const bound = keysOf(html, "data-rv-text").filter((key) => key !== "item");
  check(`${kind}: every key the template binds is in the fixture`, bound.every((key) => has(fixture.data, key) || items.every((row) => has(row, key))));

  const bad = build(kind, fixture.hostile);
  const badPath = `${work}/${kind}-bad.html`;
  copyFileSync(bad.stdout.trim(), badPath);
  check(`${kind}: hostile data builds and passes the profile`, bad.status === 0 && verify(badPath).status === 0, bad.stderr);
  const badPage = readFileSync(badPath, "utf8");
  check(`${kind}: hostile data stays inside the JSON block`, !badPage.includes("<img src=x") && !badPage.includes("<svg onload"));

  if (chrome) {
    const shown = dump(path);
    check(`${kind}: browser renders from file://`, shown.includes('class="rv-ready"'), shown.slice(0, 160));
    check(`${kind}: browser rows carry builder ids`, fixture.ids.every((id) => shown.includes(`id="${id}"`)));
    const shownBad = dump(badPath);
    check(`${kind}: browser keeps hostile data as text`, shownBad.includes('class="rv-ready"') && !/<img|<svg/i.test(shownBad) && shownBad.includes("&lt;img src=x"));
  }
}
// The design view reads a PLAN.md, not JSON: its Design section's subsections become rows.
{
  const record = ["# Plan: Cache", "", "## Design", "", "Gate: PASS.", "", "### Module layout", "", "| Module | Owns |", "", "### Contracts", "", `get(key) ${hostile}`, "", "## Plan", ""].join("\n");
  const built = build("design", record);
  const path = `${work}/design-good.html`;
  check("design: builds from a PLAN.md on stdin", built.status === 0, built.stderr);
  copyFileSync(built.stdout.trim(), path);
  check("design: the page passes the interactive profile", verify(path).status === 0, verify(path).stdout);
  check("design: hostile record text stays inside the JSON block", !readFileSync(path, "utf8").includes("<img src=x"));
  check("design: a record with no Design section exits 1", build("design", "# Plan\n\n## Plan\n").status === 1);
  if (chrome) {
    const shown = dump(path);
    check("design: browser renders from file://", shown.includes('class="rv-ready"'), shown.slice(0, 160));
    check("design: browser rows carry builder ids", ["sections-2", "sections-2-lines-1"].every((id) => shown.includes(`id="${id}"`)));
    check("design: browser keeps hostile record text as text", !/<img|<svg/i.test(shown) && shown.includes("&lt;img src=x"));
  }
}

// Every view carries the canonical chrome (the plugin's synced reference/html-chrome.html):
// its theme toggle, its comment box and its rv-chrome rules, compared line by line with
// leading whitespace dropped, and no other theme control.
{
  const chrome = readFileSync(`${dir}/../reference/html-chrome.html`, "utf8");
  const blocks = {
    toggle: /<div class="rv-theme"[^\n]*?<\/div>/,
    comment: /<section class="rv-comment".*?<\/section>/s,
    rules: /\/\* rv-chrome:begin \*\/.*?\/\* rv-chrome:end \*\//s,
  };
  const flat = (text) => (text ?? "").replace(/^[ \t]+/gm, "");
  const views = { ...Object.fromEntries(Object.entries(fixtures).map(([k, f]) => [k, f.template])), design: "../skills/design/templates/design-view.html" };
  for (const [name, re] of Object.entries(blocks)) {
    check(`chrome: the reference carries the ${name}`, re.test(chrome));
  }
  for (const [kind, template] of Object.entries(views)) {
    const html = readFileSync(`${dir}/${template}`, "utf8");
    for (const [name, re] of Object.entries(blocks)) {
      check(`${kind}: the template carries the chrome's ${name} verbatim`, flat(re.exec(html)?.[0]) === flat(re.exec(chrome)?.[0]));
    }
    check(`${kind}: the toggle opens on system`, /data-rv-theme="system" aria-pressed="true"/.test(html));
    check(`${kind}: no other theme control`, !/data-accent|data-palette|accent picker|palette picker/i.test(html));
  }
  const plan = readFileSync(`${dir}/${fixtures.plan.template}`, "utf8");
  const shows = keysOf(plan, "data-rv-shows");
  check("plan: every verdict option names an example block", shows.length === 3 && shows.every((key) => keysOf(plan, "data-rv-example").includes(key)));
}

for (const kind of Object.keys(fixtures)) {
  const html = readFileSync(`${dir}/${fixtures[kind].template}`, "utf8");
  check(`${kind}: the template carries the send control and the session replies`, ["data-rv-send=", "data-rv-session=", "data-rv-replies="].every((marker) => html.includes(marker)));
  if (chrome) {
    check(`${kind}: with no session the page says so and stays usable`, dump(`${work}/${kind}-good.html`).includes("No session is connected."));
  }

  // Claude-interactive build into a view-bridge data dir.
  const bridgedOut = `${bridgeDir(`${kind}-bridge`)}/page.html`;
  const bridged = spawnSync("node", [`${dir}/build-view.mjs`, kind, "--connect", "http://127.0.0.1:8765", "--out", bridgedOut], {
    input: JSON.stringify(fixtures[kind].data),
    encoding: "utf8",
    env,
  });
  check(`${kind} --connect --out writes the page there and it passes the profile`, bridged.status === 0 && bridged.stdout.trim() === bridgedOut && verify(bridgedOut).status === 0, bridged.stderr);
  check(`${kind} --connect names the origin in connect-src`, bridged.status === 0 && readFileSync(bridgedOut, "utf8").includes("connect-src http://127.0.0.1:8765\">"));
}
const flag = (...args) => spawnSync("node", [`${dir}/build-view.mjs`, "plan", ...args], { input: JSON.stringify(fixtures.plan.data), encoding: "utf8", env }).status;
check("--connect without --out exits 2", flag("--connect", "http://127.0.0.1:8765") === 2);
check("an unknown flag exits 2", flag("--open", "x") === 2);
check("--connect to a non-loopback origin exits 2", flag("--connect", "https://evil.example", "--out", `${bridgeDir("evil")}/page.html`) === 2);
{
  const origin = "http://127.0.0.1:8765";
  const plain = `${work}/not-a-bridge`;
  mkdirSync(plain, { mode: 0o700 });
  const open = bridgeDir("open-bridge");
  chmodSync(open, 0o755);
  const real = bridgeDir("real-bridge");
  symlinkSync(real, `${work}/linked-bridge`);
  const repo = `${work}/repo`;
  mkdirSync(`${repo}/.git`, { recursive: true });
  const tracked = `${repo}/views`;
  mkdirSync(tracked, { mode: 0o700 });
  writeFileSync(`${tracked}/.view-session.json`, '{"port": 8765, "pid": 1}');
  const refused = {
    "a dir with no session file": `${plain}/page.html`,
    "another port": `${bridgeDir("other-port", 9999)}/page.html`,
    "a group-readable dir": `${open}/page.html`,
    "a symlinked dir": `${work}/linked-bridge/page.html`,
    "a dir inside a working tree": `${tracked}/page.html`,
    "a file name other than page.html": `${bridgeDir("odd-name")}/x.html`,
  };
  for (const [label, out] of Object.entries(refused)) {
    check(`--out refused for ${label}`, flag("--connect", origin, "--out", out) === 2);
    check(`--out writes nothing for ${label}`, !existsSync(out));
  }
  const linkDir = bridgeDir("planted");
  const target = `${work}/link-target.md`;
  writeFileSync(target, "keep");
  symlinkSync(target, `${linkDir}/page.html`);
  check("a planted page.html link is replaced, never written through", flag("--connect", origin, "--out", `${linkDir}/page.html`) === 0 && readFileSync(target, "utf8") === "keep" && lstatSync(`${linkDir}/page.html`).isFile());
  const dirDir = bridgeDir("page-dir");
  mkdirSync(`${dirDir}/page.html`);
  check("a page.html that is a directory exits 2", flag("--connect", origin, "--out", `${dirDir}/page.html`) === 2 && lstatSync(`${dirDir}/page.html`).isDirectory());
  const modeOut = `${bridgeDir("mode")}/page.html`;
  flag("--connect", origin, "--out", modeOut);
  check("the page is created mode 0600", process.platform === "win32" || (statSync(modeOut).mode & 0o777) === 0o600);
}
if (!chrome) {
  console.log("SKIP: browser check, no Chrome or Chromium found (set CHROME to run it)");
}

check("an unknown view kind exits 2", build("deck", {}).status === 2);
check("stdin that is not JSON exits 2", build("plan", "{not json").status === 2);
check("data that is not an object exits 1", build("plan", "null").status === 1);
check("plan data missing its fields exits 1", build("plan", {}).status === 1);
check("brainstorm data missing its fields exits 1", build("brainstorm", {}).status === 1);
check("a row with a wrongly typed field exits 1", build("plan", { ...fixtures.plan.data, phases: [{ ...fixtures.plan.data.phases[0], criteria: "none" }] }).status === 1);
check("a list that is not a list exits 1", build("brainstorm", { ...fixtures.brainstorm.data, candidates: {} }).status === 1);

const outDir = `${work}/planning-views`;
check("the output directory is private", (statSync(outDir).mode & 0o077) === 0 || process.platform === "win32");
check("an output path that is a symlink is replaced, not followed", (() => {
  const target = `${work}/symlink-target.html`;
  writeFileSync(target, "untouched");
  const link = `${outDir}/plan.html`;
  rmSync(link, { force: true });
  symlinkSync(target, link);
  const built = build("plan", fixtures.plan.data);
  return built.status === 0 && readFileSync(target, "utf8") === "untouched" && !lstatSync(link).isSymbolicLink();
})());

process.exit(failed ? 1 : 0);
NODE
