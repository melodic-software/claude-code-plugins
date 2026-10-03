#!/usr/bin/env bash
# Behavioral tests for scripts/build-view.mjs: the post-mortem view builds through
# the shared view builder, passes the interactive profile, keeps hostile data as
# text, and binds every key its template names. When a Chrome or Chromium binary
# is found (CHROME, google-chrome, chromium, or Playwright's headless shell) the
# page is also opened from file:// to prove the runtime renders it.
#
#   bash plugins/debugging/scripts/build-view.test.sh
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
import { copyFileSync, lstatSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const [dir, work, chrome] = process.argv.slice(2);
const env = { ...process.env, TMPDIR: work, TEMP: work, TMP: work };

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
const template = "../skills/debug/templates/post-mortem-view.html";
const data = {
  title: "Checkout times out for orders over 1000",
  loop: "A curl script posting a 1200 order to the dev server.",
  cause: "The pricing client retries without a bound.",
  fix: "Cap retries at three with backoff.",
  seam: "A client-level test with a stubbed slow upstream.",
  prevention: "A retry budget in the shared HTTP client.",
  hypotheses: [
    { verdict: "CONFIRMED", claim: "Unbounded retry in the pricing client.", prediction: "Capping retries ends the timeout.", evidence: "The loop passes in 2 seconds after the cap." },
    { verdict: "RULED OUT", claim: "A slow database query.", prediction: "The query plan shows a scan.", evidence: "The plan uses the index." },
  ],
};
const hostileData = {
  title: hostile,
  loop: hostile,
  cause: hostile,
  fix: hostile,
  seam: hostile,
  prevention: hostile,
  hypotheses: [{ verdict: hostile, claim: hostile, prediction: hostile, evidence: hostile }],
};

const build = (input) =>
  spawnSync("node", [`${dir}/build-view.mjs`], { input: typeof input === "string" ? input : JSON.stringify(input), encoding: "utf8", env });
const verify = (path) => spawnSync("node", [`${dir}/../lib/view-builder.mjs`, "--check", path], { encoding: "utf8" });
const dump = (path) =>
  spawnSync(chrome, ["--headless", "--no-sandbox", "--disable-gpu", "--dump-dom", pathToFileURL(path).href], { encoding: "utf8", timeout: 60000 }).stdout ?? "";

// Keys the template binds, so a typo in the template or fixture cannot pass silently.
const keysOf = (html, attr) => [...html.matchAll(new RegExp(`${attr}="([a-z0-9-]+)"`, "g"))].map((m) => m[1]);
const has = (scope, key) => scope !== null && typeof scope === "object" && Object.hasOwn(scope, key);

const html = readFileSync(`${dir}/${template}`, "utf8");
const good = build(data);
check("builds under the temp directory", good.status === 0 && good.stdout.trim().startsWith(work), good.stderr);
const path = `${work}/good.html`;
copyFileSync(good.stdout.trim(), path);
check("the page passes the interactive profile", verify(path).status === 0, verify(path).stdout);
check("the template carries no script of its own", !/<script/i.test(html));

const items = data[keysOf(html, "data-rv-each")[0]];
const bound = keysOf(html, "data-rv-text").filter((key) => key !== "item");
check("every key the template binds is in the fixture", bound.every((key) => has(data, key) || items.every((row) => has(row, key))));

const bad = build(hostileData);
const badPath = `${work}/bad.html`;
copyFileSync(bad.stdout.trim(), badPath);
check("hostile data builds and passes the profile", bad.status === 0 && verify(badPath).status === 0, bad.stderr);
const badPage = readFileSync(badPath, "utf8");
check("hostile data stays inside the JSON block", !badPage.includes("<img src=x") && !badPage.includes("<svg onload"));

if (chrome) {
  const shown = dump(path);
  check("browser renders from file://", shown.includes('class="rv-ready"'), shown.slice(0, 160));
  check("browser rows carry builder ids", shown.includes('id="hypotheses-2"'));
  const shownBad = dump(badPath);
  check("browser keeps hostile data as text", shownBad.includes('class="rv-ready"') && !/<img|<svg/i.test(shownBad) && shownBad.includes("&lt;img src=x"));
} else {
  console.log("SKIP: browser check, no Chrome or Chromium found (set CHROME to run it)");
}

check("stdin that is not JSON exits 2", build("{not json").status === 2);
check("an argument exits 2", spawnSync("node", [`${dir}/build-view.mjs`, "extra"], { input: "{}", encoding: "utf8", env }).status === 2);
check("data that is not an object exits 1", build("null").status === 1);
check("data missing its fields exits 1", build({}).status === 1);
check("a row with a wrongly typed field exits 1", build({ ...data, hypotheses: [{ ...data.hypotheses[0], evidence: ["x"] }] }).status === 1);
check("a list that is not a list exits 1", build({ ...data, hypotheses: {} }).status === 1);

const outDir = `${work}/debugging-views`;
check("the output directory is private", (statSync(outDir).mode & 0o077) === 0 || process.platform === "win32");
check("an output path that is a symlink is replaced, not followed", (() => {
  const target = `${work}/symlink-target.html`;
  writeFileSync(target, "untouched");
  const link = `${outDir}/post-mortem.html`;
  rmSync(link, { force: true });
  symlinkSync(target, link);
  const built = build(data);
  return built.status === 0 && readFileSync(target, "utf8") === "untouched" && !lstatSync(link).isSymbolicLink();
})());

process.exit(failed ? 1 : 0);
NODE
