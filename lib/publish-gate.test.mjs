// The shared publish gate: an explicit layer publishes an artifact, otherwise only a
// PUBLIC (or repository-free) source with nothing credential-shaped does. A hosted
// page always runs every check, explicit or not.
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const GATE = join(dirname(fileURLToPath(import.meta.url)), "publish-gate.mjs");
const { DESTINATION, OPT_IN, findMachine, findSecret, publishGate, trustedMedium } = await import(GATE);

const clean = "# Talk\n\nMerge queues stopped flaky main builds.\n";
const key = `${"gh"}p_${"a".repeat(36)}`;

// Samples are assembled at run time so this file holds no credential-shaped literal.
// Shapes: R2 keys are a 32-hex access key id and a 64-hex secret
// (developers.cloudflare.com/r2/api/tokens/); Cloudflare's scannable tokens are
// cfk_, cfut_ or cfat_, 40 alphanumerics and an 8-hex checksum
// (developers.cloudflare.com/fundamentals/api/get-started/token-formats); an Azure
// client secret carries Q~ after its fourth character.
const hex = (n) => "0123456789abcdef".repeat(8).slice(0, n);
const stamp = `<!-- rv-gen:view-builder-interactive sha256:${hex(64)} -->`;
const credentials = [
  ["R2 key pair", `r2 ${hex(32)} ${hex(64)}`],
  ["R2 key pair", `"accessKeyId": "${hex(32)}"`],
  ["R2 key pair", `secretAccessKey=${hex(64)}`],
  ["Azure client secret", `secret abc8${"Q~"}${"a".repeat(34)}`],
  ["Cloudflare API token", `${"cfut"}_${"A1".repeat(20)}${hex(8)}`],
  ["Cloudflare API token", `${"cfat"}_${"b2".repeat(20)}${hex(8)}`],
  ["Cloudflare API token", `${"cfk"}_${"c3".repeat(20)}${hex(8)}`],
  ["upload token", `${"pgup"}_${"Zz9-".repeat(10)}`],
];
const machines = [
  ["home path", "/home/alice/src/app.js"],
  ["home path", "/Users/alice/Desktop/notes.md"],
  ["home path", "C:\\Users\\alice\\repo"],
  ["home path", "C:\\\\Users\\\\alice"],
  ["home path", "/mnt/c/Users/alice/repo"],
  ["home path", "cat /root/.bashrc"],
  ["WSL path", "\\\\wsl.localhost\\Ubuntu"],
  ["scratchpad slug", "projects/-home-alice-worktrees-app/x.jsonl"],
  ["fleet hostname", "ssh melo-desk-001"],
  ["fleet hostname", "on melo-lap-002 today"],
  ["private hostname", "build.local"],
  ["private hostname", "db.internal:5432"],
  ["private hostname", "nas.lan"],
];

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
  test("a machine path does not keep an artifact local", () => {
    assert.equal(publishGate({ explicit: false, visibility: "PUBLIC", text: "/home/alice/x" }).medium, "artifact");
  });
  test("findSecret reports a label and line, never the match", () => {
    assert.deepEqual(findSecret(`a\n${key}`), ["GitHub token", 2]);
    assert.equal(findSecret('password = "${PASSWORD}"'), null);
  });
});

describe("credential patterns", () => {
  for (const [label, line] of credentials) {
    test(`a ${label} sample is caught on its line`, () => {
      assert.deepEqual(findSecret(`clean\n${line}`), [label, 2]);
    });
  }
  test("the builder stamp's sha256 is not an R2 secret, even beside a 32-hex token", () => {
    assert.equal(findSecret(`${stamp}\n${hex(32)} ${stamp}`), null);
  });
  test("one 64-hex digest alone is not a key pair", () => {
    assert.equal(findSecret(`sha256 ${hex(64)}`), null);
  });
});

describe("machine patterns", () => {
  for (const [label, line] of machines) {
    test(`${JSON.stringify(line)} is a ${label}`, () => {
      assert.deepEqual(findMachine(`clean\n${line}`), [label, 2]);
    });
  }
  for (const line of ["/home/", "src/root/x.js", "https://example.com/Users", "localhost", "example.com", "melo-desk-1"]) {
    test(`${JSON.stringify(line)} is not a machine path or hostname`, () => {
      assert.equal(findMachine(line), null);
    });
  }
});

describe("hosted", () => {
  const hosted = (over) =>
    publishGate({ explicit: false, visibility: "PUBLIC", text: `${stamp}\n${clean}`, medium: "hosted", ...over });
  test("a public, clean, stamped page goes to the public host", () => {
    assert.deepEqual(hosted({}), {
      medium: "hosted",
      destination: "public",
      reason: "public repository and nothing credential-, path- or host-shaped in the content",
    });
    assert.equal(hosted({ visibility: "NONE" }).destination, "public");
  });
  for (const explicit of [false, true]) {
    for (const visibility of ["PRIVATE", "INTERNAL", "UNKNOWN", "", "bogus"]) {
      test(`explicit=${explicit} and a ${visibility || "missing"} repository go private`, () => {
        const result = hosted({ explicit, visibility });
        assert.equal(result.medium, "hosted");
        assert.equal(result.destination, "private");
        assert.match(result.reason, /not PUBLIC/);
      });
    }
    test(`explicit=${explicit} and a credential refuse the host, naming only label and line`, () => {
      const result = hosted({ explicit, text: `${clean}${key}\n`, subject: "page" });
      assert.deepEqual(result, { medium: "file", reason: "page line 4 looks like a GitHub token; a hosted page is refused" });
    });
    test(`explicit=${explicit} and a machine path go private`, () => {
      const result = hosted({ explicit, text: `${clean}/home/alice/x\n` });
      assert.deepEqual(result, { medium: "hosted", destination: "private", reason: "content line 4 names a home path" });
    });
  }
  test("a private request stays private and nothing raises it", () => {
    assert.equal(hosted({ requested: "private" }).destination, "private");
    assert.equal(hosted({ requested: "bogus" }).destination, "private");
  });
  test("a credential refuses even a private request", () => {
    assert.equal(hosted({ requested: "private", text: key }).medium, "file");
  });
});

describe("trustedMedium", () => {
  const home = mkdtempSync(join(tmpdir(), "gate-home-"));
  after(() => rmSync(home, { recursive: true, force: true }));
  test("hosted counts from the argument, the option and the user file, like artifact", () => {
    assert.equal(trustedMedium({ argument: "hosted", home, project: null }).medium, "hosted");
    assert.equal(trustedMedium({ option: "hosted", home, project: null }).medium, "hosted");
    mkdirSync(join(home, ".claude"), { recursive: true });
    writeFileSync(join(home, ".claude", "rendered-views.md"), "medium: hosted\n");
    assert.equal(trustedMedium({ home, project: null }).medium, "hosted");
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
  test("--medium hosted runs the hosted checks, explicit or not", () => {
    assert.equal(JSON.parse(run(["public", "--medium", "hosted"]).stdout).destination, "public");
    assert.equal(JSON.parse(run(["private", "--explicit", "--medium", "hosted"]).stdout).destination, "private");
    assert.equal(JSON.parse(run(["public", "--medium", "hosted", "--visibility", "private"]).stdout).destination, "private");
    assert.equal(JSON.parse(run(["public", "--explicit", "--medium", "hosted"], key).stdout).medium, "file");
  });
  test("refuses a missing visibility or an unknown flag", () => {
    assert.equal(run([]).status, 2);
    assert.equal(run(["--explicit"]).status, 2);
    assert.equal(run(["PUBLIC", "--force"]).status, 2);
    assert.equal(run(["PUBLIC", "--subject"]).status, 2);
    assert.equal(run(["PUBLIC", "--medium", "file"]).status, 2);
    assert.equal(run(["PUBLIC", "--visibility", "public"]).status, 2);
    assert.equal(run(["PUBLIC", "--medium", "hosted", "--visibility", "open"]).status, 2);
  });
});
