/**
 * sync.mjs against a small tree written here, with fetch answered from memory
 * so the expected hashes are computed from known bytes, and the repository's
 * own tree under `check`, which is the CI check that a view's URL or hash
 * matches package.json.
 */
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../test-tmp.mjs";
import { check, main, sync } from "./sync.mjs";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const CDN = "https://cdn.jsdelivr.net/npm/";
const sri = (body) => `sha256-${createHash("sha256").update(body).digest("base64")}`;
const BODIES = {
  [`${CDN}mermaid@1.0.0/dist/m.js`]: "mermaid one",
  [`${CDN}mermaid@1.1.0/dist/m.js`]: "mermaid one point one",
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
const TEST = (m) => `assert.match(page, /${`${CDN}mermaid@${m.v}/dist/m.js" integrity="${m.sri}`.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}/);\n`;
const PROSE = (m, t) => `Loads \`mermaid\` ${m.v} and \`@scope/tw\` ${t.v}. Hashes: Mermaid \`${m.sri}\`, Tailwind \`${t.sri}\`. CSP: ${CDN}mermaid@${m.v}/dist/m.js ${CDN}@scope/tw@${t.v}/dist/t.js\n`;
const SAMPLE = (m) => `{"pass": "script-src ${CDN}mermaid@${m.v}/dist/m.js"}\n`;

const M1 = { v: "1.0.0", sri: sri("mermaid one") };
const M11 = { v: "1.1.0", sri: sri("mermaid one point one") };
const T2 = { v: "2.0.0", sri: sri("tailwind two") };

function tree(manifestMermaid = "1.0.0") {
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
          mermaid: { version: "1.0.0", file: "dist/m.js", integrity: M1.sri },
          "@scope/tw": { version: "2.0.0", file: "dist/t.js", integrity: T2.sri },
        },
        targets: [
          { path: "view.mjs", packages: ["mermaid", "@scope/tw"], integrity: true },
          { path: "view.test.mjs", packages: ["mermaid"], integrity: true },
          { path: "view.md", packages: ["mermaid", "@scope/tw"], integrity: true },
          { path: "sample.json", packages: ["mermaid"], integrity: false },
        ],
      },
      null,
      2,
    )}\n`,
  );
  write("view.mjs", VIEW(M1, T2));
  write("view.test.mjs", TEST(M1));
  write("view.md", PROSE(M1, T2));
  write("sample.json", SAMPLE(M1));
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

test("check fails on a view whose hash or URL differs from the record, and names the file", () => {
  const root = tree();
  writeFileSync(join(root, "view.mjs"), VIEW({ ...M1, sri: sri("something else") }, T2));
  assert.deepEqual(check(root), [`view.mjs lacks mermaid's hash ${M1.sri}`]);
  const stale = tree();
  writeFileSync(join(stale, "sample.json"), SAMPLE({ v: "0.9.0" }));
  assert.deepEqual(check(stale), [`sample.json lacks ${CDN}mermaid@1.0.0/dist/m.js`, "sample.json names mermaid@0.9.0, not 1.0.0"]);
});

test("a range in package.json is refused, and a pinned file the CDN does not serve writes nothing", async () => {
  assert.throws(() => check(tree("^1.0.0")), /must pin mermaid at an exact version, not "\^1\.0\.0"/);
  const root = tree("1.2.0");
  const before = snapshot(root);
  await assert.rejects(sync(root, { fetchImpl: fakeFetch }), /mermaid@1\.2\.0\/dist\/m\.js answered 404/);
  assert.deepEqual(snapshot(root), before);
});

test("this repository's rendered views carry the versions and hashes lib/cdn-pins names", async () => {
  const lines = [];
  assert.equal(await main(["check", REPO], { log: (line) => lines.push(line) }), 0, lines.join("\n"));
});
