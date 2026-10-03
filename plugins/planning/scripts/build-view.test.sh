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
import { copyFileSync, readFileSync } from "node:fs";
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
if (!chrome) {
  console.log("SKIP: browser check, no Chrome or Chromium found (set CHROME to run it)");
}

check("an unknown view kind exits 2", build("deck", {}).status === 2);
check("stdin that is not JSON exits 2", build("plan", "{not json").status === 2);
check("data that is not an object exits 1", build("plan", "null").status === 1);

process.exit(failed ? 1 : 0);
NODE
