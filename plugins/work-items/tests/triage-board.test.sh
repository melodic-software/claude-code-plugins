#!/usr/bin/env bash
# The triage board builder: grouping, the validator profile, and hostile tracker text.
# Item text is K2, so every string must reach the page only as escaped JSON data. When a
# Chrome or Chromium binary is found the page is also opened from file:// and read back.
#
#   bash plugins/work-items/tests/triage-board.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
BUILDER="$PLUGIN_DIR/skills/triage/scripts/build-board.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "triage-board: node not found on PATH" >&2
  exit 2
fi

chrome="${CHROME:-}"
if [[ -z "$chrome" ]]; then
  for candidate in google-chrome google-chrome-stable chromium chromium-browser \
    "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-*/chrome-headless-shell; do
    if [[ -x "$candidate" ]] || command -v "$candidate" >/dev/null 2>&1; then
      chrome="$candidate"
      break
    fi
  done
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node --input-type=module - "$BUILDER" "$PLUGIN_DIR" "$work" "$chrome" <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const [builder, plugin, work, chrome] = process.argv.slice(2);
const { validateView } = await import(pathToFileURL(`${plugin}/lib/view-builder.mjs`).href);

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail === undefined ? "" : ` - ${detail}`}`);
    failed += 1;
  }
};
const build = (input, out = `${work}/board.html`) =>
  spawnSync("node", [builder, "--out", out], { input: typeof input === "string" ? input : JSON.stringify(input), encoding: "utf8" });

const hostile = [
  "<script>globalThis.pwned = 1</script>",
  '<img src=x onerror="document.title=\'pwned\'">',
  "javascript:document.title='pwned'",
  "<svg onload=\"document.title='pwned'\"><script>1</script></svg>",
  '</script><script>document.title="pwned"</script>',
  '"><b>pwned</b>',
  "{{#each x}}{{.}}{{/each}}",
];
const items = hostile.map((text, i) => ({
  number: i + 1,
  kind: hostile[(i + 1) % hostile.length],
  title: text,
  state: i % 2 ? "raw" : hostile[(i + 2) % hostile.length],
  labels: [hostile[(i + 3) % hostile.length], "needs-triage"],
  blockedBy: i === 0 ? [] : i === 1 ? ["javascript:1", 5] : [3],
}));

// Grouping.
const run = build({ repo: "o/r", generated: "2026-10-03", items: items.slice(0, 3) });
check("a board builds", run.status === 0, run.stderr);
const page = readFileSync(`${work}/board.html`, "utf8");
const data = JSON.parse(/<script type="application\/json" id="rv-data">([^]*?)<\/script>/.exec(page)[1]);
const rows = (groups, key) => groups.flatMap((g) => g[key]);
check("every item appears once per state", rows(data.bystate, "srows").length === 3);
check("an item appears under each of its blockers, or unblocked", rows(data.byblocker, "brows").length === 4 && data.byblocker.some((g) => g.name === "unblocked"));
check("an item appears under each of its labels", rows(data.bylabel, "lrows").length === 6);
check("a non-integer blocker number becomes ?", data.byblocker.some((g) => g.name === "#?"));
check("groups sort by size, then name", data.bylabel[0].name === "needs-triage" && data.bylabel[0].count === 3);
build({ items: [{ number: 1, title: "t" }] });
const bare = JSON.parse(/id="rv-data">([^]*?)<\/script>/.exec(readFileSync(`${work}/board.html`, "utf8"))[1]);
check("an item with no labels and no state groups as no label, untriaged", bare.bylabel[0].name === "no label" && bare.bystate[0].name === "untriaged");
check("an item whose blockers were not read is neither blocked nor unblocked", bare.byblocker[0].name === "blockers not read");
const wontDo = build({ items: [{ number: 62, title: "t", state: "blocked by won't-do", blockedBy: [58] }, { number: 61, title: "u", state: "unlabeled" }] });
const wontDoPage = readFileSync(`${work}/board.html`, "utf8");
const wontDoData = JSON.parse(/id="rv-data">([^]*?)<\/script>/.exec(wontDoPage)[1]);
check("the blocked-by-won't-do bucket groups as its own state", wontDo.status === 0 && wontDoData.bystate.some((g) => g.name === "blocked by won't-do" && g.srows[0].ref === "#62"), wontDo.stderr);
check("a board with the won't-do bucket passes the interactive profile", validateView(wontDoPage).ok, validateView(wontDoPage).failures);
check(
  "the act list holds every item in input order, ref and title only",
  JSON.stringify(data.items) === JSON.stringify(items.slice(0, 3).map((item, i) => ({ ref: `#${i + 1}`, title: item.title }))),
);

// Claude-interactive build.
const connected = spawnSync("node", [builder, "--out", `${work}/bridged.html`, "--connect", "http://127.0.0.1:8765"], { input: JSON.stringify({ items }), encoding: "utf8" });
const bridgedPage = connected.status === 0 ? readFileSync(`${work}/bridged.html`, "utf8") : "";
check("--connect builds a page that passes the interactive profile", connected.status === 0 && validateView(bridgedPage).ok, connected.stderr);
check("--connect names the origin in connect-src", bridgedPage.includes("connect-src http://127.0.0.1:8765\">"));
const offOrigin = spawnSync("node", [builder, "--out", `${work}/x.html`, "--connect", "https://evil.example"], { input: "{}", encoding: "utf8" });
check("--connect to a non-loopback origin exits 1", offOrigin.status === 1, offOrigin.status);
check("an unknown flag exits 2", spawnSync("node", [builder, "--out", `${work}/x.html`, "--open", "x"], { input: "{}", encoding: "utf8" }).status === 2);

// Hostile tracker text.
const evil = build({ repo: hostile[0], generated: hostile[1], title: hostile[3], items });
check("hostile items build", evil.status === 0, evil.stderr);
const evilPage = readFileSync(`${work}/board.html`, "utf8");
const block = /<script type="application\/json" id="rv-data">[^]*?<\/script>/.exec(evilPage)[0];
const outside = evilPage.replace(block, "");
check("the built page passes the interactive profile", validateView(evilPage).ok, validateView(evilPage).failures);
check("no hostile string reaches the markup outside the data block", !/pwned|onerror|javascript:|alert|onload/.test(outside));
check("the page carries exactly two scripts", (evilPage.match(/<script/g) ?? []).length === 2);
check("the data block holds the hostile text as JSON", JSON.parse(/id="rv-data">([^]*?)<\/script>/.exec(evilPage)[1]).bystate.length > 0);

// Failure exits.
check("input that is not JSON exits 1", build("not json").status === 1);
check("a --connect with no value exits 2", spawnSync("node", [builder, "--out", `${work}/x.html`, "--connect"], { input: "{}", encoding: "utf8" }).status === 2);
check("no --out exits 2", spawnSync("node", [builder], { input: "{}", encoding: "utf8" }).status === 2);
check("an empty board still builds", build({}).status === 0);

// Browser.
if (!chrome) {
  console.log("SKIP: browser check, no Chrome or Chromium found (set CHROME to run it)");
} else {
  build({ repo: hostile[0], generated: hostile[1], title: hostile[3], items });
  const file = `${work}/board.html`;
  const dom = spawnSync(chrome, ["--headless", "--no-sandbox", "--disable-gpu", "--dump-dom", pathToFileURL(file).href], {
    encoding: "utf8",
    timeout: 60000,
  }).stdout ?? "";
  check("browser: the runtime runs under the page's policy from file://", dom.includes('class="rv-ready"'), dom.slice(0, 200));
  check("browser: rows render with builder ids", dom.includes('id="bystate-1-srows-1"') && dom.includes('id="bylabel-1-lrows-1"'));
  check("browser: no hostile script or handler ran", !/<title>pwned|<html[^>]*pwned/.test(dom));
  check("browser: hostile markup stays text", !/<img|<svg onload|<b>pwned/i.test(dom) && dom.includes("&lt;img src=x"));
  check("browser: act rows carry builder ids as their pick values", dom.includes('id="items-1"') && dom.includes('value="items-7"'));
  check("browser: with no session the board says so and stays usable", dom.includes("No session is connected."));
}

if (failed) {
  console.error(`${failed} check(s) failed`);
  process.exit(1);
}
console.log("all triage-board checks passed");
NODE
