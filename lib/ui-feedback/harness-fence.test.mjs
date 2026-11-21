import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { createServer } from "node:http";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { fenceHeaders, harnessFence } from "./harness-fence.mjs";

const CLI = fileURLToPath(new URL("./harness-fence.mjs", import.meta.url));
const BRIDGE = "http://localhost:41234";
const PAGE = '<!doctype html><html><head><meta charset="utf-8"><title>Shipments</title></head><body><main></main></body></html>';

async function served(fence, page) {
  const server = createServer((req, res) => {
    fence(req, res, () => {
      res.setHeader("Content-Type", "text/html");
      res.end(page);
    });
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  try {
    const res = await fetch(`http://127.0.0.1:${server.address().port}/shipments`);
    return { csp: res.headers.get("content-security-policy"), body: await res.text() };
  } finally {
    await new Promise((done) => server.close(done));
  }
}

test("the dev server sends frame-ancestors for the bridge origin as a response header", async () => {
  const { csp } = await served(harnessFence(BRIDGE), PAGE);
  assert.equal(csp, `frame-ancestors ${BRIDGE}`);
});

test("the fence adds no meta CSP tag to the page it serves", async () => {
  const { body } = await served(harnessFence(BRIDGE), PAGE);
  assert.equal(body, PAGE);
  assert.doesNotMatch(body, /http-equiv\s*=\s*["']?content-security-policy/i);
});

test("a bridge origin that is not canonical, or that could add a directive, is refused", () => {
  for (const bad of ["http://localhost:80", "http://localhost:41234/", "http://a;script-src", "http://[::1]:41234", "*", "'self'"]) {
    assert.throws(() => fenceHeaders(bad), bad);
    assert.throws(() => harnessFence(bad), bad);
  }
});

test("the command prints the header line and exits 2 on any other input", () => {
  const ok = spawnSync(process.execPath, [CLI, BRIDGE], { encoding: "utf8" });
  assert.equal(ok.status, 0);
  assert.equal(ok.stdout, `Content-Security-Policy: frame-ancestors ${BRIDGE}\n`);
  const bad = spawnSync(process.execPath, [CLI, "http://localhost:80"], { encoding: "utf8" });
  assert.equal(bad.status, 2);
  assert.equal(bad.stdout, "");
  assert.match(bad.stderr, /^harness-fence: .*pass http:\/\/localhost$/m);
});
