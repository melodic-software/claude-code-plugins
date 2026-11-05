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
// A fence's info string holds no backtick, so the shape anchor drops them.
const hostilePlan = [
  `# ${hostile}`, "", "## Brief", "", "### Problem", "", `- ${hostile}`, "", "### Goal", "", hostile, "",
  "### Constraints", "", `- ${hostile}`, "", "### Acceptance criteria", "", `- AC1: ${hostile}`, "", "### Out-of-scope", "", `- ${hostile}`, "",
  "## Plan", "", "### Behavior", "", `- B1: ${hostile} (AC1)`, "", `Process criteria: ${hostile}`, "",
  "### Decisions made (gate-passed)", "", "| Decision | What it changes in the plan | Basis (evidence) | Source |", "|---|---|---|---|",
  `| ${hostile} | ${hostile} | ${hostile} | ${hostile} |`, "",
  `### Phase 1: ${hostile} [TODO]`, `**Satisfies:** ${hostile}`, `**Delivers:** ${hostile}`, "", hostile, "",
  `\`\`\`shape ${hostile.replaceAll("`", "")}`, hostile, "```", "", `- **Sanity Check:** ${hostile}`, "",
].join("\n");
const fixtures = {
  plan: {
    template: "../skills/plan/templates/plan-view.html",
    data: readFileSync(`${dir}/testdata/plan-record.md`, "utf8"),
    hostile: hostilePlan,
    ids: ["phases-2", "phases-1-criteria-2", "phases-1-shapes-1", "phases-2-criteria-1", "behaviors-2", "criteria-3", "decisions-2", "problem-2", "out-of-scope-1"],
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

const input = (data) => (typeof data === "string" ? data : JSON.stringify(data));
const build = (kind, data) => spawnSync("node", [`${dir}/build-view.mjs`, kind], { input: input(data), encoding: "utf8", env });
const dataOf = (page) => JSON.parse(/<script type="application\/json" id="rv-data">(.*?)<\/script>/s.exec(page)[1]);
const keysIn = (value) =>
  Array.isArray(value)
    ? value.flatMap(keysIn)
    : value !== null && typeof value === "object"
      ? Object.entries(value).flatMap(([key, inner]) => [key, ...keysIn(inner)])
      : [];
const verify = (path) => spawnSync("node", [`${dir}/../lib/view-builder.mjs`, "--check", path], { encoding: "utf8" });
const dump = (path) =>
  spawnSync(chrome, ["--headless", "--no-sandbox", "--disable-gpu", "--dump-dom", pathToFileURL(path).href], { encoding: "utf8", timeout: 60000 }).stdout ?? "";

// Keys the template binds, so a typo in a template or fixture cannot pass silently.
const keysOf = (html, attr) => [...html.matchAll(new RegExp(`${attr}="([a-z0-9-]+)"`, "g"))].map((m) => m[1]);

for (const [kind, fixture] of Object.entries(fixtures)) {
  const html = readFileSync(`${dir}/${fixture.template}`, "utf8");
  const good = build(kind, fixture.data);
  check(`${kind}: builds under the temp directory`, good.status === 0 && good.stdout.trim().startsWith(work), good.stderr);
  const path = `${work}/${kind}-good.html`;
  copyFileSync(good.stdout.trim(), path);
  check(`${kind}: the page passes the interactive profile`, verify(path).status === 0, verify(path).stdout);
  check(`${kind}: the template carries no script of its own`, !/<script/i.test(html));

  const keys = new Set(keysIn(dataOf(readFileSync(path, "utf8"))));
  const bound = ["data-rv-text", "data-rv-each", "data-rv-count"].flatMap((attr) => keysOf(html, attr)).filter((key) => key !== "item");
  check(`${kind}: every key the template binds is in the fixture's data`, bound.every((key) => keys.has(key)), bound.filter((key) => !keys.has(key)).join(", "));

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
// The plan view reads the whole PLAN.md and links to its sections by fixed fragments.
{
  const built = spawnSync("node", [`${dir}/build-view.mjs`, "plan", "--record", `${dir}/testdata/plan-record.md`], { encoding: "utf8", env });
  const lines = built.stdout.trim().split("\n");
  check("plan --record builds and prints one HTML path", built.status === 0 && lines.length === 1 && lines[0].endsWith(".html"), built.stderr);
  const data = dataOf(readFileSync(lines[0], "utf8"));
  check("plan: the record's parts reach the page", data.title === "Plan: Add caching to query handlers" && data.blast === "MEDIUM" && data.process === "AC3" && data.behaviors.length === 2 && data.criteria.length === 3 && data.decisions.length === 2 && data.problem.length === 2);
  check("plan: each phase carries its lines, checks and shapes", data.phases[0].satisfies === "AC1" && data.phases[0].delivers === "B1" && data.phases[0].criteria.length === 2 && data.phases[0].shapes[0]?.anchor === "src/orders/handler.py#get_order" && data.phases[1].criteria.length === 1 && data.phases[1].what.includes("## a heading inside a fence stays text"));
  const html = readFileSync(`${dir}/${fixtures.plan.template}`, "utf8");
  const sections = ["behaviors", "brief", "criteria", "decisions", "phases"];
  check("plan: the nav links each section by a literal fragment", sections.every((id) => html.includes(`href="#${id}"`) && html.includes(`id="${id}"`)));
  check("plan: a record with no ## Plan section exits 1", build("plan", "# Plan\n\n## Brief\n").status === 1);
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
    // The toggle only sets or clears data-theme on the root, so the view's own color
    // tokens must follow it, or Light and Dark change aria-pressed and not the page.
    const tokens = (block) => block !== undefined && /--bg:/.test(block) && /--fg:/.test(block);
    const base = /(?:^|\n)[ \t\n\r\f]*:root[ \t\n\r\f]*\{([^}]*)\}/.exec(html)?.[1];
    const pinned = /:root\[data-theme=dark\][ \t\n\r\f]*\{([^}]*)\}/.exec(html)?.[1];
    const guarded = /@media \(prefers-color-scheme: dark\)[ \t\n\r\f]*\{[ \t\n\r\f]*:root:not\(\[data-theme=light\]\)[ \t\n\r\f]*\{([^}]*)\}/.exec(html)?.[1];
    check(`${kind}: the base tokens define --bg and --fg in a light scheme`, tokens(base) && /color-scheme:[ \t\n\r\f]*light/.test(base));
    check(`${kind}: data-theme=dark pins the dark tokens`, tokens(pinned) && /color-scheme:[ \t\n\r\f]*dark/.test(pinned));
    check(`${kind}: the system dark tokens yield to data-theme=light`, tokens(guarded) && /color-scheme:[ \t\n\r\f]*dark/.test(guarded));
    check(`${kind}: every prefers-color-scheme dark block is guarded`, (html.match(/prefers-color-scheme:[ \t\n\r\f]*dark\)[ \t\n\r\f]*\{/g) ?? []).length === (html.match(/prefers-color-scheme:[ \t\n\r\f]*dark\)[ \t\n\r\f]*\{[ \t\n\r\f]*:root:not\(\[data-theme=light\]\)/g) ?? []).length);
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
    input: input(fixtures[kind].data),
    encoding: "utf8",
    env,
  });
  check(`${kind} --connect --out writes the page there and it passes the profile`, bridged.status === 0 && bridged.stdout.trim() === bridgedOut && verify(bridgedOut).status === 0, bridged.stderr);
  check(`${kind} --connect names the origin in connect-src`, bridged.status === 0 && readFileSync(bridgedOut, "utf8").includes("connect-src http://127.0.0.1:8765\">"));
}
const flag = (...args) => spawnSync("node", [`${dir}/build-view.mjs`, "plan", ...args], { input: fixtures.plan.data, encoding: "utf8", env }).status;
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
const notJson = build("brainstorm", "{not json");
check("brainstorm stdin that is not JSON exits 2 and says so", notJson.status === 2 && notJson.stderr.includes("the brainstorm record is not JSON"));
check("data that is not an object exits 1", build("brainstorm", "null").status === 1);
check("brainstorm data missing its fields exits 1", build("brainstorm", {}).status === 1);
check("a row with a wrongly typed field exits 1", build("brainstorm", { ...fixtures.brainstorm.data, candidates: [{ ...fixtures.brainstorm.data.candidates[0], effort: 3 }] }).status === 1);
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
