// The shared publish gate: an explicit layer publishes, otherwise only a PUBLIC
// (or repository-free) source with nothing credential-shaped does.
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const GATE = join(dirname(fileURLToPath(import.meta.url)), "publish-gate.mjs");
const { DESTINATION, OPT_IN, findSecret, publishGate } = await import(GATE);

const clean = "# Talk\n\nMerge queues stopped flaky main builds.\n";
const key = `${"gh"}p_${"a".repeat(36)}`;

describe("publishGate", () => {
  test("an explicit layer publishes whatever the source", () => {
    const result = publishGate({ explicit: true, visibility: "PRIVATE", text: key });
    assert.equal(result.medium, "artifact");
    assert.equal(result.destination, DESTINATION);
  });
  for (const visibility of ["PRIVATE", "INTERNAL", "UNKNOWN", "", "bogus"]) {
    test(`a ${visibility || "missing"} visibility stays local and names the opt-in`, () => {
      const result = publishGate({ explicit: false, visibility, text: clean });
      assert.equal(result.medium, "file");
      assert.match(result.reason, /not PUBLIC/);
      assert.equal(result.opt_in, OPT_IN);
    });
  }
  for (const visibility of ["PUBLIC", "NONE"]) {
    test(`a ${visibility} source with clean text publishes and names the destination`, () => {
      const result = publishGate({ explicit: false, visibility, text: clean });
      assert.equal(result.medium, "artifact");
      assert.equal(result.destination, DESTINATION);
    });
    test(`a ${visibility} source with a credential stays local without echoing it`, () => {
      const result = publishGate({ explicit: false, visibility, text: `${clean}${key}\n`, subject: "deck" });
      assert.equal(result.medium, "file");
      assert.match(result.reason, /^deck line 4 looks like a GitHub token$/);
      assert.ok(!JSON.stringify(result).includes(key));
    });
  }
  test("findSecret reports a label and line, never the match", () => {
    assert.deepEqual(findSecret(`a\n${key}`), ["GitHub token", 2]);
    assert.equal(findSecret('password = "${PASSWORD}"'), null);
  });
});

describe("CLI", () => {
  const run = (args, input = clean) => spawnSync(process.execPath, [GATE, ...args], { input, encoding: "utf8" });
  test("reads the text on stdin and upper-cases the visibility", () => {
    assert.equal(JSON.parse(run(["public"]).stdout).medium, "artifact");
    assert.equal(JSON.parse(run(["none"]).stdout).medium, "artifact");
    assert.equal(JSON.parse(run(["private"]).stdout).medium, "file");
    assert.equal(JSON.parse(run(["private", "--explicit"]).stdout).medium, "artifact");
    assert.match(JSON.parse(run(["public", "--subject", "deck"], key).stdout).reason, /^deck line 1/);
  });
  test("refuses a missing visibility or an unknown flag", () => {
    assert.equal(run([]).status, 2);
    assert.equal(run(["--explicit"]).status, 2);
    assert.equal(run(["PUBLIC", "--force"]).status, 2);
    assert.equal(run(["PUBLIC", "--subject"]).status, 2);
  });
});
