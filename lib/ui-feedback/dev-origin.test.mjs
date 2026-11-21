import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { canonicalOrigin } from "./dev-origin.mjs";

const CLI = fileURLToPath(new URL("./dev-origin.mjs", import.meta.url));

test("a canonical http or https origin is kept as given", () => {
  for (const origin of ["http://localhost:5173", "http://127.0.0.1:3000", "https://app.test"]) {
    assert.equal(canonicalOrigin(origin), origin);
  }
});

test("an input that differs from its canonical origin is refused", () => {
  const cases = {
    "http://localhost:80": "http://localhost",
    "https://app.test:443": "https://app.test",
    "http://LOCALHOST:5173": "http://localhost:5173",
    "http://localhost:5173/": "http://localhost:5173",
    "http://localhost:5173/shipments": "http://localhost:5173",
    "http://user@localhost:5173": "http://localhost:5173",
    "http://localhost:5173?x=1": "http://localhost:5173",
  };
  for (const [input, canonical] of Object.entries(cases)) {
    assert.throws(() => canonicalOrigin(input), (err) => err.message.includes(`pass ${canonical}`), input);
  }
});

test("a non-URL or a scheme with no http origin is refused", () => {
  for (const input of ["localhost:5173", "", "file:///tmp/a.html", "null", "data:text/html,x", "ws://localhost:5173"]) {
    assert.throws(() => canonicalOrigin(input), input);
  }
});

test("a host a CSP source cannot name is refused, so no quote or semicolon reaches the host page", () => {
  for (const input of ['http://a"onload="alert(1)', "http://a;b", "http://[::1]:8080", "http://a'b"]) {
    assert.equal(new URL(input).origin, input, `${input} is its own origin, so only the host rule refuses it`);
    assert.throws(() => canonicalOrigin(input), /CSP frame-src cannot name/, input);
  }
});

test("the command prints a canonical origin and exits 2 on any other input", () => {
  const ok = spawnSync(process.execPath, [CLI, "http://localhost:5173"], { encoding: "utf8" });
  assert.equal(ok.status, 0);
  assert.equal(ok.stdout, "http://localhost:5173\n");
  const bad = spawnSync(process.execPath, [CLI, "http://localhost:80"], { encoding: "utf8" });
  assert.equal(bad.status, 2);
  assert.equal(bad.stdout, "");
  assert.match(bad.stderr, /pass http:\/\/localhost$/m);
});
