#!/usr/bin/env bash
# The checkup decision page builder: the interactive validator profile, hostile machine
# text, the hidden run choice, and row-id parity between the builder's id map and the
# ids the shared runtime assigns when the page loads in a headless browser.
# Machine-derived text is K2, so every string must reach the page only as escaped JSON data.
#
#   bash plugins/machine-health/tests/checkup-view.test.sh
#
# Set CHROME to pick the browser. Set CHECKUP_SCREENSHOTS to a folder to also save the
# built page in light and dark themes as PNG files there.
# Exit 0 clean, 1 findings, 2 environment (node or a Chrome or Chromium binary missing).
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "checkup-view: node not found on PATH" >&2
  exit 2
fi

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
unix() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s\n' "$1"; fi; }

chrome="${CHROME:-}"
if [[ -z "$chrome" ]]; then
  candidates=(google-chrome google-chrome-stable chromium chromium-browser
    "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-*/chrome-headless-shell)
  [[ -z "${PROGRAMFILES:-}" ]] || candidates+=("$(unix "$PROGRAMFILES")/Google/Chrome/Application/chrome.exe")
  [[ -z "${LOCALAPPDATA:-}" ]] || candidates+=("$(unix "$LOCALAPPDATA")"/ms-playwright/chromium_headless_shell-*/chrome-*/chrome-headless-shell.exe)
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      chrome="$candidate"
      break
    elif command -v "$candidate" >/dev/null 2>&1; then
      chrome="$(command -v "$candidate")"
      break
    fi
  done
fi
if [[ -z "$chrome" ]]; then
  echo "checkup-view: no Chrome or Chromium found (set CHROME); the row-id parity check cannot run" >&2
  exit 2
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node --input-type=module - "$(native "$PLUGIN_DIR")" "$(native "$work")" "$(native "$chrome")" "${CHECKUP_SCREENSHOTS:-}" <<'NODE'
import { mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const [plugin, work, chrome, shots] = process.argv.slice(2);
const builder = `${plugin}/skills/audit/scripts/build-checkup-view.mjs`;
const { validateView, buildView, ViewBuildError } = await import(pathToFileURL(`${plugin}/lib/view-builder.mjs`).href);
const { toCheckupData, withRunChoice } = await import(pathToFileURL(builder).href);
const template = readFileSync(`${plugin}/skills/audit/templates/checkup.html`, "utf8");

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail === undefined ? "" : ` - ${detail}`}`);
    failed += 1;
  }
};

const hostile = [
  "<script>globalThis.pwned = 1</script>",
  '<img src=x onerror="document.title=\'pwned\'">',
  "javascript:document.title='pwned'",
  "<svg onload=\"document.title='pwned'\"><script>1</script></svg>",
  '</script><script>document.title="pwned"</script>',
  '"><b>pwned</b>',
  "<!-- pwned",
];
const stamp = "2026-10-21T120000000Z";
const key = (n) => `ext:${String(n).padStart(16, "0")}`;
// A Defender exclusion value is withheld from the page, its data and the id map (check catalog).
const canary = "exclusion-canary-7f3a";
const canaryPath = "D:\\Hidden\\" + canary;
const exclusionKey = "exclusion:0011223344556677";
// Expected ids, worked out by hand from this fixture: checks sort worst first (CRIT, WARN,
// UNKNOWN, INFO, OK), then in input order, so disk is area 1, ext area 2, svc area 3,
// defender-exclusions area 4, ok area 5.
const latest = {
  run_id: "2026-10-21T07:00:00.0000000-05:00",
  hostname: hostile[0],
  elevated: false,
  checks: [
    {
      id: "browser-extensions", severity: "WARN", summary: hostile[1],
      detail: { items: [
        { key: key(1), severity: "WARN", muted: false, title: hostile[2], path: hostile[3] },
        { key: null, severity: "INFO", muted: false, title: hostile[4], unkeyed_reason: "id unread" },
        { key: key(3), severity: "INFO", muted: true, title: "already muted" },
        { key: "not a key", severity: "INFO", muted: false, title: hostile[5] },
        { key: key(5), severity: "INFO", muted: false, title: hostile[6] },
      ] },
    },
    { id: "services", severity: "INFO", summary: "fine", detail: { items: [{ key: key(6), severity: "INFO", muted: false, title: "svc" }] } },
    { id: "disk-space", severity: "CRIT", summary: hostile[3], detail: { free_pct: 3 } },
    {
      id: "defender-exclusions", severity: "INFO", summary: "1 exclusion",
      detail: { items: [
        { key: exclusionKey, severity: "INFO", muted: false, title: `path exclusion: ${canaryPath}`, exclusion_type: "path", value: canaryPath, expected: false },
      ] },
    },
    { id: "<bad id>", severity: "OK", summary: "ok", detail: { items: [{ key: key(7), severity: "OK", muted: false, title: "t" }] } },
  ],
};
const expectedRows = {
  "areas-2-items-1-mute-1": { action: "mute", check_id: "browser-extensions", finding_key: key(1), label: hostile[2] },
  "areas-2-items-5-mute-1": { action: "mute", check_id: "browser-extensions", finding_key: key(5), label: hostile[6] },
  "areas-3-items-1-mute-1": { action: "mute", check_id: "services", finding_key: key(6), label: "svc" },
  "areas-4-items-1-mute-1": { action: "mute", check_id: "defender-exclusions", finding_key: exclusionKey, label: "(exclusion value withheld) path" },
  "remediations-1": { action: "approve", remediation_id: "restart-stopped-service" },
  "remediations-2": { action: "approve", remediation_id: "clear-temp-files" },
};

// Pure data step.
const { data, rows } = toCheckupData(latest, ["restart-stopped-service", "clear-temp-files"], "health-x.md");
check("areas sort worst first", data.areas.map((a) => a.title).join(",") === "disk-space,browser-extensions,services,defender-exclusions,<bad id>", data.areas.map((a) => a.title));
check("the run row names the report it was given", data.run[0].report === "health-x.md", data.run[0].report);
check("an item whose key is not a FindingKey says it cannot be muted", data.areas[1].items[3].detail === "cannot be muted", data.areas[1].items[3].detail);
check("an exclusion item shows the withheld placeholder and no value",
  data.areas[3].items[0].title === "(exclusion value withheld) path" && !JSON.stringify(data.areas[3]).includes(canary), JSON.stringify(data.areas[3]));
check("a remediation shows its id and nothing else",
  JSON.stringify(data.remediations) === JSON.stringify([{ title: "restart-stopped-service" }, { title: "clear-temp-files" }]), JSON.stringify(data.remediations));
check("the id map offers a mute only for keyed, unmuted items of an id-shaped check", JSON.stringify(rows) === JSON.stringify(expectedRows), JSON.stringify(rows));
check("an item with no key carries no mute pick", data.areas[1].items[1].mute.length === 0 && data.areas[1].items[1].detail === "cannot be muted");
let threw = false;
try { toCheckupData({}, []); } catch { threw = true; }
check("latest.json with no checks array is refused", threw);

// The CLI build.
const latestPath = `${work}/latest.json`;
const views = `${work}/views`;
mkdirSync(views);
writeFileSync(latestPath, `﻿${JSON.stringify(latest)}`);
const args = ["--latest", latestPath, "--views-dir", views, "--run-stamp", stamp, "--remediations", "restart-stopped-service,clear-temp-files"];
const run = spawnSync("node", [builder, ...args], { encoding: "utf8", timeout: 60000 });
check("a page builds", run.status === 0, run.stderr);
check("the builder writes exactly the run's three files",
  readdirSync(views).sort().join(",") === [`checkup-${stamp}.html`, `checkup-${stamp}.ids.json`, `checkup-${stamp}.json`].join(","), readdirSync(views));
const page = readFileSync(`${views}/checkup-${stamp}.html`, "utf8");
const ids = JSON.parse(readFileSync(`${views}/checkup-${stamp}.ids.json`, "utf8"));
check("the id map names its format and run", ids.format === "checkup-ids/1" && ids.run_id === latest.run_id && /^[0-9a-f]{64}$/.test(ids.page_sha256));
check("the id map rows match the data step", JSON.stringify(ids.rows) === JSON.stringify(expectedRows));
check("the run row names the run's report", JSON.parse(readFileSync(`${views}/checkup-${stamp}.json`, "utf8")).run[0].report === `health-${stamp}.md`);
for (const suffix of [".html", ".json", ".ids.json"]) {
  check(`no exclusion value reaches checkup-${stamp}${suffix}`, !readFileSync(`${views}/checkup-${stamp}${suffix}`, "utf8").includes(canary));
}

// Interactive profile.
const result = validateView(page);
check("the built page passes the interactive profile", result.ok, result.failures);
check("a page with an extra script fails the profile", !validateView(page.replace("</main>", "<script>1</script></main>")).ok);
check("a page with an inline handler fails the profile", !validateView(page.replace("<main ", '<main onclick="x" ')).ok);

// Hostile text stays data.
const block = /<script type="application\/json" id="rv-data">[^]*?<\/script>/.exec(page)[0];
const outside = page.replace(block, "");
check("no hostile string reaches the markup outside the data block", !/pwned|onerror|javascript:|onload/.test(outside));
check("the page carries exactly two scripts", (page.match(/<script/g) ?? []).length === 2);
check("the data block holds no raw <", !block.slice(block.indexOf(">") + 1, -"</script>".length).includes("<"));

// The hidden run choice.
const lower = stamp.toLowerCase();
check("the builder accepts the inserted run select", page.includes(`<select data-rv-choice="run" hidden><option value="${lower}">`));
let refused = null;
try {
  buildView({ profile: "interactive", template: template.replace('value="run-stamp"', `value="${stamp}"`), data });
} catch (err) {
  refused = err;
}
check("the builder refuses a run value that is not an opaque token", refused instanceof ViewBuildError && refused.failures.includes("opaque:value"), refused?.message);
threw = false;
try { withRunChoice(template.replace('value="run-stamp"', ""), stamp); } catch { threw = true; }
check("a template without the run placeholder is refused", threw);
const badStamp = spawnSync("node", [builder, ...args.slice(0, 5), "../x", ...args.slice(6)], { encoding: "utf8", timeout: 60000 });
check("a malformed run stamp exits 2", badStamp.status === 2, badStamp.status);
check("an unknown flag exits 2", spawnSync("node", [builder, ...args, "--out", "x"], { encoding: "utf8", timeout: 60000 }).status === 2);
writeFileSync(`${work}/bad.json`, "not json");
check("latest.json that is not JSON exits 1",
  spawnSync("node", [builder, "--latest", `${work}/bad.json`, ...args.slice(2)], { encoding: "utf8", timeout: 60000 }).status === 1);

// Headless browser over the DevTools protocol.
const profile = `${work}/profile`;
const browser = spawn(chrome, ["--headless=new", "--no-sandbox", "--disable-gpu", "--no-first-run", "--remote-debugging-port=0", `--user-data-dir=${profile}`, "about:blank"], { stdio: "ignore" });
const deadline = Date.now() + 60000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const portFile = `${profile}/DevToolsActivePort`;
while (!existsSync(portFile) || readFileSync(portFile, "utf8").split("\n").length < 2) {
  if (Date.now() > deadline) {
    console.error("FAIL: the browser opened no DevTools port within 60 s");
    browser.kill();
    process.exit(1);
  }
  await sleep(200);
}
const port = readFileSync(portFile, "utf8").split("\n")[0].trim();
let targets = [];
while (!targets.some((t) => t.type === "page") && Date.now() < deadline) {
  targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  if (!targets.some((t) => t.type === "page")) await sleep(200);
}
const socket = new WebSocket(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
let seq = 0;
const pending = new Map();
socket.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (pending.has(msg.id)) {
    pending.get(msg.id)(msg);
    pending.delete(msg.id);
  }
};
const send = (method, params = {}) => new Promise((resolve) => {
  seq += 1;
  pending.set(seq, resolve);
  socket.send(JSON.stringify({ id: seq, method, params }));
});
const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result?.result?.value;

await send("Page.enable");
await send("Page.navigate", { url: pathToFileURL(`${views}/checkup-${stamp}.html`).href });
while (!(await evaluate("document.documentElement.classList.contains('rv-ready')")) && Date.now() < deadline) await sleep(200);
check("browser: the runtime runs under the page's policy from file://", await evaluate("document.documentElement.classList.contains('rv-ready')"));
const pickValues = await evaluate("[...document.querySelectorAll('input[data-rv-pick]')].map((p) => p.value)");
check("browser: runtime row ids equal the builder's id map rows",
  JSON.stringify([...pickValues].sort()) === JSON.stringify(Object.keys(ids.rows).sort()), JSON.stringify(pickValues));
check("browser: no hostile script or handler ran", (await evaluate("document.title + String(globalThis.pwned)")) === "Machine health checkupundefined");
check("browser: no remediation row carries an empty line",
  (await evaluate("[...document.querySelectorAll('[data-rv-each=\"remediations\"] > li')].every((li) => li.textContent.trim() !== '' && [...li.querySelectorAll('p, span, strong')].every((e) => e.textContent.trim() !== ''))")) === true);
check("browser: hostile markup stays text", (await evaluate("document.querySelectorAll('main img, main svg, main b').length")) === 0 &&
  (await evaluate("document.body.textContent.includes('<img src=x')")));

await evaluate(`(() => {
  document.querySelector('input[value="areas-2-items-1-mute-1"]').click();
  document.querySelector('input[value="remediations-2"]').click();
  document.getElementById('notes').value = 'expected on this host';
  document.querySelector('button[data-rv-copy]').click();
})()`);
await sleep(300);
const payload = await evaluate("document.querySelector('[data-rv-out]').textContent");
check("browser: the copied payload carries the picks, the lowercased run stamp and the note",
  payload === `checkup-picks\npicked: areas-2-items-1-mute-1 remediations-2\nrun: ${lower}\nnotes: expected on this host`, JSON.stringify(payload));

if (shots) {
  mkdirSync(shots, { recursive: true });
  await evaluate("document.querySelectorAll('details').forEach((d) => { d.open = true; })");
  for (const theme of ["light", "dark"]) {
    await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: theme }] });
    const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true });
    writeFileSync(`${shots}/checkup-${theme}.png`, Buffer.from(shot.result.data, "base64"));
    console.log(`saved: ${shots}/checkup-${theme}.png`);
  }
}

await send("Browser.close").catch(() => {});
socket.close();
browser.kill();

if (failed) {
  console.error(`${failed} check(s) failed`);
  process.exit(1);
}
console.log("all checkup-view checks passed");
NODE
