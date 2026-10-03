#!/usr/bin/env bash
# Behavioral tests for scripts/build-view.mjs: every map kind builds through the
# shared view builder, passes the interactive profile, keeps hostile record text
# as data, and narrows to a closure under --from. When a Chrome or Chromium
# binary is found (CHROME, google-chrome, chromium, or Playwright's headless
# shell) the pages are also opened from file:// to prove the runtime renders them.
#
#   bash plugins/architecture/scripts/build-view.test.sh
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
const record = {
  schema_version: 1,
  generated_on: "2026-10-03",
  result: "ok",
  message: "",
  nodes: [
    { id: "A/A.csproj", name: "A", kind: "project" },
    { id: "B/B.csproj", name: "B", kind: "project" },
    { id: "C/C.csproj", name: "C", kind: "project" },
  ],
  edges: [
    { from: "A/A.csproj", to: "B/B.csproj", kind: "project", evidence: "A/A.csproj: <ProjectReference />" },
    { from: "B/B.csproj", to: "C/C.csproj", kind: "project", evidence: "B/B.csproj: <ProjectReference />" },
  ],
  cycles: [["B/B.csproj", "C/C.csproj"]],
  findings: [],
  actor: { name: "operator", role: "person" },
};
const hostileRecord = {
  schema_version: 1,
  result: hostile,
  nodes: [{ id: hostile, name: hostile }],
  edges: [{ from: hostile, to: hostile, evidence: hostile }],
};
const kinds = ["landscape", "containers", "components", "dependencies", "data", "events", "flow", "context", "deployment"];

const write = (name, data) => {
  const path = `${work}/${name}.json`;
  writeFileSync(path, typeof data === "string" ? data : JSON.stringify(data));
  return path;
};
const build = (kind, path, ...extra) => spawnSync("node", [`${dir}/build-view.mjs`, kind, "--record", path, ...extra], { encoding: "utf8", env });
const verify = (path) => spawnSync("node", [`${dir}/../lib/view-builder.mjs`, "--check", path], { encoding: "utf8" });
const dump = (path) =>
  spawnSync(chrome, ["--headless", "--no-sandbox", "--disable-gpu", "--dump-dom", pathToFileURL(path).href], { encoding: "utf8", timeout: 60000 }).stdout ?? "";
const dataOf = (path) => JSON.parse(/<script type="application\/json" id="rv-data">(.*?)<\/script>/s.exec(readFileSync(path, "utf8"))[1]);

const good = write("good", record);
const bad = write("bad", hostileRecord);
const template = readFileSync(`${dir}/../templates/map-view.html`, "utf8");
check("the template carries no script of its own", !/<script/i.test(template));

for (const kind of kinds) {
  const built = build(kind, good);
  check(`${kind}: builds under the temp directory`, built.status === 0 && built.stdout.trim().startsWith(work), built.stderr);
  const path = `${work}/${kind}-good.html`;
  copyFileSync(built.stdout.trim(), path);
  check(`${kind}: the page passes the interactive profile`, verify(path).status === 0, verify(path).stdout);
}

const page = `${work}/dependencies-good.html`;
const rows = dataOf(page).rows;
check("every array item becomes a row and the object becomes one", rows.length === 3 + 2 + 1 + 1, String(rows.length));
check("an edge row is named by its two ends", rows.some((row) => row.kind === "edges" && row.name === "A/A.csproj -> B/B.csproj"));
check("a scalar becomes a fact and an array a count", dataOf(page).facts.includes("result: ok") && dataOf(page).facts.includes("nodes: 3"));
check("every key the template binds is in the data", ["title", "facts", "rows"].every((key) => key in dataOf(page)) && rows.every((row) => ["kind", "name", "fields"].every((key) => key in row)));

const scoped = dataOf(copyAndPath(build("components", good, "--from", "B/B.csproj")));
function copyAndPath(result) {
  const path = `${work}/scoped.html`;
  copyFileSync(result.stdout.trim(), path);
  return path;
}
check("--from keeps the closure of that node", scoped.rows.map((row) => row.name).join("|") === "B/B.csproj|C/C.csproj|B/B.csproj -> C/C.csproj", JSON.stringify(scoped.rows.map((row) => row.name)));
check("--from names its scope in a fact", scoped.facts[0] === "scope: reachable from B/B.csproj");

const mixed = write("mixed", {
  schema_version: 1,
  nodes: [
    { id: "A", name: "A", kind: "project" },
    { id: "B", name: "B", kind: "project" },
    { id: "pkg:x", name: "x", kind: "package" },
    { id: "D", name: "D", kind: "project" },
  ],
  edges: [
    { from: "A", to: "B", kind: "project", status: "resolved" },
    { from: "A", to: "pkg:x", kind: "package", status: "resolved" },
    { from: "A", to: "D", kind: "project", status: "unresolved" },
  ],
});
const mixedScoped = dataOf(copyAndPath(build("components", mixed, "--from", "A")));
check("--from follows resolved project edges only", mixedScoped.rows.map((row) => row.name).join("|") === "A|B|A -> B", JSON.stringify(mixedScoped.rows.map((row) => row.name)));

const hostileBuilt = build("dependencies", bad);
check("hostile text builds and passes the profile", hostileBuilt.status === 0, hostileBuilt.stderr);
const badPath = `${work}/bad.html`;
copyFileSync(hostileBuilt.stdout.trim(), badPath);
check("hostile text passes the profile", verify(badPath).status === 0, verify(badPath).stdout);
const badPage = readFileSync(badPath, "utf8");
check("hostile text stays inside the JSON block", !badPage.includes("<img src=x") && !badPage.includes("<svg onload"));

if (chrome) {
  const shown = dump(page);
  check("browser renders from file://", shown.includes('class="rv-ready"'), shown.slice(0, 160));
  check("browser rows carry builder ids", shown.includes('id="rows-1"') && shown.includes('id="rows-7"'));
  check("browser shows a row's fields", shown.includes("evidence: A/A.csproj: &lt;ProjectReference /&gt;"));
  const shownBad = dump(badPath);
  check("browser keeps hostile text as text", shownBad.includes('class="rv-ready"') && !/<img|<svg/i.test(shownBad) && shownBad.includes("&lt;img src=x"));
} else {
  console.log("SKIP: browser check, no Chrome or Chromium found (set CHROME to run it)");
}

check("an unknown kind exits 2", build("deck", good).status === 2);
check("a missing --record exits 2", spawnSync("node", [`${dir}/build-view.mjs`, "flow"], { encoding: "utf8", env }).status === 2);
check("an unknown flag exits 2", build("flow", good, "--bogus", "x").status === 2);
check("a record that is not JSON exits 1", build("flow", write("notjson", "{not json")).status === 1);
check("a record without schema_version 1 exits 1", build("flow", write("v2", { schema_version: 2 })).status === 1);
check("--from naming no node exits 1", build("components", good, "--from", "nope").status === 1);
check("--from on a record without edges exits 1", build("components", write("noedges", { schema_version: 1, nodes: [] }), "--from", "x").status === 1);
check("a record path that does not exist exits 2", build("flow", `${work}/absent.json`).status === 2);

const outDir = `${work}/architecture-views`;
check("the output directory is private", (statSync(outDir).mode & 0o077) === 0 || process.platform === "win32");
check("an output path that is a symlink is replaced, not followed", (() => {
  const target = `${work}/symlink-target.html`;
  writeFileSync(target, "untouched");
  const link = `${outDir}/flow.html`;
  rmSync(link, { force: true });
  symlinkSync(target, link);
  const built = build("flow", good);
  return built.status === 0 && readFileSync(target, "utf8") === "untouched" && !lstatSync(link).isSymbolicLink();
})());

process.exit(failed ? 1 : 0);
NODE
