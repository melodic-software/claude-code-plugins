// test-scope: lib/cdn-pins/package.json lib/cdn-pins/package-lock.json lib/cdn-pins/pins.json lib/cdn-pins/fixtures/fake-fetch.mjs .github/actions/resolve-config/patch-rules.json .github/scripts/apply-patch/cdn-paths.mjs
// test-scope: plugins/architecture/scripts/deepening-report.mjs plugins/architecture/scripts/deepening-report.test.mjs plugins/architecture/skills/improve/research/deepening/html-report.md plugins/architecture/evals/deepening-report-on-chrome-with-counts/samples/csp-pins-mermaid.json plugins/architecture/evals/deepening-report-on-chrome-with-counts/samples/csp-pins-tailwind.json
/**
 * sync.mjs against a small tree written here, with fetch answered from memory
 * so the expected hashes are computed from known bytes, and the repository's
 * own tree under `check`, which is the CI check that a view's URL or hash
 * matches package.json.
 */
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { cdnPaths } from "../../.github/scripts/apply-patch/cdn-paths.mjs";
import { tempDir } from "../test-tmp.mjs";
import { check, main, sync } from "./sync.mjs";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SCRIPT = fileURLToPath(new URL("./sync.mjs", import.meta.url));
const FAKE_FETCH = fileURLToPath(new URL("./fixtures/fake-fetch.mjs", import.meta.url));
const CDN = "https://cdn.jsdelivr.net/npm/";
const sri = (body) => `sha256-${createHash("sha256").update(body).digest("base64")}`;
const BODIES = {
  [`${CDN}mermaid@1.0.0/dist/m.js`]: "mermaid one",
  [`${CDN}mermaid@1.1.0/dist/m.js`]: "mermaid one point one",
  [`${CDN}mermaid@1.3.0/dist/m.js`]: "mermaid new 5",
  [`${CDN}@scope/tw@2.0.0/dist/t.js`]: "tailwind two",
};
const fakeFetch = async (url) => {
  const body = BODIES[url];
  return body === undefined ? { ok: false, status: 404 } : { ok: true, status: 200, arrayBuffer: async () => Buffer.from(body) };
};

const VIEW = (m, t) =>
  [
    `const M = "${CDN}mermaid@${m.v}/dist/m.js";`,
    `const M_SRI = "${m.sri}";`,
    `const T = "${CDN}@scope/tw@${t.v}/dist/t.js"; // integrity ${t.sri}`,
    "",
  ].join("\n");
const esc = (text) => text.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
const TEST = (m) => `assert.match(page, /${esc(`${CDN}mermaid@${m.v}/dist/m.js" integrity="${m.sri}`)}/);\n`;
const PROSE = (m, t) => `Loads \`mermaid\` ${m.v} and \`@scope/tw\` ${t.v}. Hashes: Mermaid \`${m.sri}\`, Tailwind \`${t.sri}\`. CSP: ${CDN}mermaid@${m.v}/dist/m.js ${CDN}@scope/tw@${t.v}/dist/t.js\n`;
const SAMPLE = (m) => `{"pass": "script-src ${CDN}mermaid@${m.v}/dist/m.js"}\n`;

const M1 = { v: "1.0.0", sri: sri("mermaid one") };
const M11 = { v: "1.1.0", sri: sri("mermaid one point one") };
const T2 = { v: "2.0.0", sri: sri("tailwind two") };
const M_PLAIN = { v: "1.0.0", sri: sri("mermaid old 5") };
const M13 = { v: "1.3.0", sri: sri("mermaid new 5") };

function tree(manifestMermaid = "1.0.0", m = M1) {
  const root = tempDir("cdn-pins-");
  const write = (path, text) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  };
  write("lib/cdn-pins/package.json", JSON.stringify({ dependencies: { mermaid: manifestMermaid, "@scope/tw": "2.0.0" } }));
  write(
    "lib/cdn-pins/pins.json",
    `${JSON.stringify(
      {
        cdn: CDN,
        packages: {
          mermaid: { version: "1.0.0", file: "dist/m.js", integrity: m.sri },
          "@scope/tw": { version: "2.0.0", file: "dist/t.js", integrity: T2.sri },
        },
        targets: [
          { path: "view.mjs", packages: ["mermaid", "@scope/tw"], integrity: true },
          { path: "view.test.mjs", packages: ["mermaid"], integrity: true },
          { path: "view.md", packages: ["mermaid", "@scope/tw"], integrity: true, prose: true },
          { path: "sample.json", packages: ["mermaid"], integrity: false },
        ],
      },
      null,
      2,
    )}\n`,
  );
  write("view.mjs", VIEW(m, T2));
  write("view.test.mjs", TEST(m));
  write("view.md", PROSE(m, T2));
  write("sample.json", SAMPLE(m));
  return root;
}
const read = (root, path) => readFileSync(join(root, path), "utf8");
const FILES = ["view.mjs", "view.test.mjs", "view.md", "sample.json", "lib/cdn-pins/pins.json"];
const snapshot = (root) => Object.fromEntries(FILES.map((path) => [path, read(root, path)]));

test("sync on a tree that already matches package.json changes no file", async () => {
  const root = tree();
  const before = snapshot(root);
  assert.deepEqual(check(root), []);
  assert.deepEqual(await sync(root, { fetchImpl: fakeFetch }), []);
  assert.deepEqual(snapshot(root), before);
});

test("a version bump in package.json fails check until sync rewrites every URL, hash and CSP source", async () => {
  const root = tree("1.1.0");
  assert.match(check(root).join("\n"), /package\.json pins mermaid 1\.1\.0 but the views carry 1\.0\.0/);
  const changed = await sync(root, { fetchImpl: fakeFetch });
  assert.deepEqual(changed.sort(), [...FILES].sort());
  assert.equal(read(root, "view.mjs"), VIEW(M11, T2));
  assert.equal(read(root, "view.test.mjs"), TEST(M11));
  assert.equal(read(root, "view.md"), PROSE(M11, T2));
  assert.equal(read(root, "sample.json"), SAMPLE(M11));
  assert.deepEqual(JSON.parse(read(root, "lib/cdn-pins/pins.json")).packages.mermaid, { version: "1.1.0", file: "dist/m.js", integrity: M11.sri });
  assert.deepEqual(check(root), []);
});

test("a recorded hash with no + or / is rewritten escaped inside a regular expression and plain elsewhere", async () => {
  assert.doesNotMatch(M_PLAIN.sri, /[+/]/);
  assert.match(M13.sri, /\+/);
  assert.match(M13.sri, /\//);
  const root = tree("1.3.0", M_PLAIN);
  assert.deepEqual(check(root), ["lib/cdn-pins/package.json pins mermaid 1.3.0 but the views carry 1.0.0; run node lib/cdn-pins/sync.mjs sync"]);
  await sync(root, { fetchImpl: fakeFetch });
  assert.equal(read(root, "view.test.mjs"), TEST(M13));
  assert.equal(read(root, "view.mjs"), VIEW(M13, T2));
  assert.equal(read(root, "view.md"), PROSE(M13, T2));
  assert.deepEqual(check(root), []);
});

test("check fails on a view whose hash or URL differs from the record, and names the file", () => {
  const root = tree();
  writeFileSync(join(root, "view.mjs"), VIEW({ ...M1, sri: sri("something else") }, T2));
  assert.deepEqual(check(root), [`view.mjs lacks mermaid's hash ${M1.sri}`]);
  const stale = tree();
  writeFileSync(join(stale, "sample.json"), SAMPLE({ v: "0.9.0" }));
  assert.deepEqual(check(stale), [`sample.json lacks ${CDN}mermaid@1.0.0/dist/m.js`, "sample.json names mermaid@0.9.0, not 1.0.0"]);
});

test("check fails on a regular expression whose hash is not the current one escaped", () => {
  const current = { v: "1.0.0", sri: M13.sri };
  const unescaped = tree("1.0.0", current);
  writeFileSync(join(unescaped, "view.test.mjs"), `assert.match(page, /${esc(`${CDN}mermaid@1.0.0/dist/m.js" integrity="`)}${M13.sri}/);\n`);
  assert.deepEqual(check(unescaped), [`view.test.mjs:1 has hash ${M13.sri} in a regular expression, not a current hash escaped`]);
  const older = sri("an older file");
  const stale = tree("1.0.0", current);
  writeFileSync(join(stale, "view.test.mjs"), `${TEST(current)}${TEST({ ...current, sri: older })}`);
  assert.deepEqual(check(stale), [`view.test.mjs:2 has hash ${esc(older)} in a regular expression, not a current hash escaped`]);
});

test("check fails on prose that names another version, or no longer names the current one", () => {
  const stale = tree();
  writeFileSync(join(stale, "view.md"), PROSE(M1, T2).replace("`mermaid` 1.0.0", "`mermaid` 0.9.0"));
  assert.deepEqual(check(stale), ['view.md lacks the prose "`mermaid` 1.0.0"', "view.md names `mermaid` 0.9.0, not 1.0.0"]);
  const reworded = tree();
  writeFileSync(join(reworded, "view.md"), PROSE(M1, T2).replace("`mermaid` 1.0.0", "Mermaid 1.0.0"));
  assert.deepEqual(check(reworded), ['view.md lacks the prose "`mermaid` 1.0.0"']);
  const prefixed = tree();
  writeFileSync(join(prefixed, "view.mjs"), `${VIEW(M1, T2)}// \`@scope/tw\` v1.9.0\n`);
  assert.deepEqual(check(prefixed), ["view.mjs names `@scope/tw` 1.9.0, not 2.0.0"]);
});

test("a range in package.json is refused, and a pinned file the CDN does not serve writes nothing", async () => {
  assert.throws(() => check(tree("^1.0.0")), /must pin mermaid at an exact version, not "\^1\.0\.0"/);
  const root = tree("1.2.0");
  const before = snapshot(root);
  await assert.rejects(sync(root, { fetchImpl: fakeFetch }), /mermaid@1\.2\.0\/dist\/m\.js answered 404/);
  assert.deepEqual(snapshot(root), before);
});

test("for apply-patch's content rule check returns a list of messages, empty on a synced tree, and for pr-unblock's container the sync command line rewrites every target", () => {
  const isMessages = (out) => Array.isArray(out) && out.every((line) => typeof line === "string");
  const synced = tree();
  assert.deepEqual(check(synced), []);
  const stale = tree("1.1.0");
  const before = check(stale);
  assert.ok(isMessages(before) && before.length > 0, JSON.stringify(before));
  const out = execFileSync(process.execPath, ["--import", FAKE_FETCH, SCRIPT, "sync", stale], {
    encoding: "utf8",
    env: { ...process.env, CDN_PINS_FAKE_FETCH: JSON.stringify(BODIES) },
  });
  for (const path of FILES) assert.match(out, new RegExp(`cdn-pins: wrote ${esc(path)}`), path);
  assert.equal(read(stale, "view.mjs"), VIEW(M11, T2));
  assert.equal(read(stale, "view.md"), PROSE(M11, T2));
  assert.deepEqual(check(stale), []);
  const repo = check(REPO);
  assert.ok(isMessages(repo), JSON.stringify(repo));
});

test("the sync command line exits 1 and writes nothing when the CDN does not serve the bumped file", () => {
  const root = tree("1.2.0");
  const before = snapshot(root);
  assert.throws(
    () => execFileSync(process.execPath, ["--import", FAKE_FETCH, SCRIPT, "sync", root], { encoding: "utf8", env: { ...process.env, CDN_PINS_FAKE_FETCH: JSON.stringify(BODIES) } }),
    (error) => error.status === 1 && /answered 404/.test(error.stdout),
  );
  assert.deepEqual(snapshot(root), before);
});

test("this repository's pins.json names no more files than the cdn-pins-sync row lets one patch change", () => {
  const rules = JSON.parse(readFileSync(join(REPO, ".github/actions/resolve-config/patch-rules.json"), "utf8"));
  const record = JSON.parse(read(REPO, "lib/cdn-pins/pins.json"));
  const paths = cdnPaths(record);
  assert.equal(paths.length, record.targets.length + 1);
  assert.ok(paths.length <= rules["cdn-pins-sync"]["max-files"], `${paths.length} paths over max-files ${rules["cdn-pins-sync"]["max-files"]}`);
});

test("this repository's rendered views carry the versions and hashes lib/cdn-pins names", async () => {
  const lines = [];
  assert.equal(await main(["check", REPO], { log: (line) => lines.push(line) }), 0, lines.join("\n"));
});
