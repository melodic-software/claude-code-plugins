#!/usr/bin/env bash
# Behavioral tests for the video-digest menu-view builder: hostile transcript,
# title, and URL text renders as inert text, and the page passes the shared
# validator.
#
#   bash plugins/knowledge/skills/video-digest/scripts/build-menu-view.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "build-menu-view: node not found on PATH" >&2
  exit 2
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node --input-type=module - "$SCRIPT_DIR" "$work" <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const dir = process.argv[2];
const work = process.argv[3];
const builderPath = `${dir}/build-menu-view.mjs`;
const { buildMenuPage } = await import(pathToFileURL(builderPath).href);
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
  video: hostile[1],
  url: hostile[6],
  items: [
    { category: hostile[2], priority: hostile[3], item: hostile[4], why: hostile[5] },
    { category: hostile[7], priority: "P1", item: hostile[0], why: hostile[1] },
  ],
  takeaways: [hostile[2], hostile[3]],
  questions: [hostile[4], hostile[5]],
};

const page = buildMenuPage(model);
const verdict = validateRenderedPage(page);
check("the builder is deterministic", page === buildMenuPage(model));
check("a hostile model still passes the validator", verdict.ok, verdict.failures.join(","));
check("no live script tag", !/<script[\s>]/i.test(page)); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check("no live img tag", !page.includes("<img"));
check("no href or event-handler attribute", !page.includes("href=") && !/\son[a-z]+=/i.test(page.replace(/>[^<]*</g, "><"))); // portability-ok: embedded node JavaScript regex, not a shell tool pattern
check(
  "every hostile string appears escaped",
  hostile.every((item) => page.includes(escapeHtml(item))),
);
check("backticks pass through as text", page.includes("`${alert(1)}`"));
check("an empty model still validates", validateRenderedPage(buildMenuPage({})).ok);
check(
  "a malformed model still validates",
  validateRenderedPage(buildMenuPage({ title: { a: 1 }, items: "x", takeaways: [1, null, { b: 2 }], questions: 7 })).ok,
);

const cli = spawnSync(process.execPath, [builderPath], { input: JSON.stringify(model), encoding: "utf8" });
check("the CLI emits the same page as the function", cli.status === 0 && cli.stdout === page, cli.stderr);
check("invalid JSON exits 2", spawnSync(process.execPath, [builderPath], { input: "{", encoding: "utf8" }).status === 2);
writeFileSync(`${work}/page.html`, page);
check("--check accepts a builder page", spawnSync(process.execPath, [builderPath, "--check", `${work}/page.html`]).status === 0);
writeFileSync(`${work}/hand.html`, `<!doctype html><html><head></head><body><h1>${hostile[0]}</h1></body></html>`);
check("--check flags a hand-written page", spawnSync(process.execPath, [builderPath, "--check", `${work}/hand.html`]).status === 1);

const source = readFileSync(builderPath, "utf8");
const pageFn = source.slice(source.indexOf("export function buildMenuPage"), source.indexOf("function fail"));
const stray = (pageFn.match(/\$\{[^}]+\}/g) ?? []).filter((item) => !/^\$\{(?:e\(|CSS|menuRows\(|numbered\()/.test(item));
check("the page template interpolates only escaped calls or built fragments", stray.length === 0, stray.join(" "));

const lane = readFileSync(`${dir}/../context/watch-pipeline.md`, "utf8");
check(
  "the lane routes the page through the builder",
  lane.includes("build-menu-view.mjs") && lane.includes("Do not hand-write the HTML"),
);

if (failed > 0) process.exit(1);
NODE

echo "build-menu-view: all cases passed"
