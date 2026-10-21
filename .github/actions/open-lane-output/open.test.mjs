import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { parsePublicKey, sealBundle } from "../seal-lane-output/seal.mjs";
import { generate } from "./keygen.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ACTION = readFileSync(path.join(HERE, "action.yml"), "utf8");
const CHUNK = 98304;
const CAPS = "reply.txt=16384\nact-turns.json=32768\npatch.diff=262144";

// The decode step's env, from action.yml: each `NAME: ${{ inputs.x }}` takes input x.
function stepEnv(inputs) {
  const env = {};
  for (const [, name, input] of ACTION.matchAll(/^ {8}([A-Z_0-9]+): \$\{\{ inputs\.([\w-]+) \}\}$/gm)) env[name] = inputs[input] ?? "";
  return env;
}

function keyPair() {
  const { publicLine, privateText } = generate();
  return { publicLine, privateText, keyId: publicLine.split(" ")[1], recipient: parsePublicKey(publicLine) };
}

function sealedInputs(recipient, payloads, { runId = "42", jobId = "run", bundle } = {}) {
  const text = (bundle ?? sealBundle(recipient, payloads, runId, jobId)).toString("base64");
  const inputs = { "sealed-length": String(text.length) };
  for (let i = 0; i * CHUNK < text.length; i++) inputs[`sealed-${i + 1}`] = text.slice(i * CHUNK, (i + 1) * CHUNK);
  return inputs;
}

// Runs open.mjs as the composite step does; returns its exit, log, output and env files, and the files it wrote.
function runOpen(t, inputs, { runId = "42", runAttempt = "1" } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), "open-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const output = path.join(dir, "github-output");
  const envFile = path.join(dir, "github-env");
  writeFileSync(output, "");
  writeFileSync(envFile, "");
  const directory = path.join(dir, "out");
  const result = spawnSync(process.execPath, [path.join(HERE, "open.mjs")], {
    env: {
      PATH: process.env.PATH,
      GITHUB_OUTPUT: output,
      GITHUB_ENV: envFile,
      GITHUB_RUN_ID: runId,
      GITHUB_RUN_ATTEMPT: runAttempt,
      ...stepEnv({ "job-id": "run", "max-bytes": CAPS, directory, ...inputs }),
    },
    encoding: "utf8",
  });
  const files = existsSync(directory) ? Object.fromEntries(readdirSync(directory).map((name) => [name, readFileSync(path.join(directory, name))])) : {};
  return { status: result.status, log: result.stdout + result.stderr, output: readFileSync(output, "utf8"), env: readFileSync(envFile, "utf8"), files };
}

const REPLY = Buffer.from("lint-shell: fixed\nnon-ASCII: é中\n");
const PATCH = crypto.randomBytes(262144);

test("round trip: what seal-lane-output seals opens to the same bytes, file per payload name", (t) => {
  const { recipient, privateText, keyId } = keyPair();
  const sealed = sealedInputs(recipient, [["reply.txt", REPLY], ["patch.diff", PATCH], ["act-turns.json", Buffer.alloc(0)]]);
  const opened = runOpen(t, { ...sealed, "private-key": privateText, "expected-key-ids": `ffffffffffffffff\n${keyId}` });
  assert.equal(opened.status, 0, opened.log);
  assert.deepEqual(opened.files, { "act-turns.json": Buffer.alloc(0), "patch.diff": PATCH, "reply.txt": REPLY });
  assert.equal(opened.output, "opened=reply.txt patch.diff act-turns.json\n");
});

test("plaintext never reaches the log, an output or GITHUB_ENV, and nothing is masked", (t) => {
  const { recipient, privateText, keyId } = keyPair();
  const marker = "PLAINTEXT-MARKER-7f3a";
  const sealed = sealedInputs(recipient, [["reply.txt", Buffer.from(`${marker}\n`)]]);
  for (const key of [privateText, keyPair().privateText]) {
    const run = runOpen(t, { ...sealed, "private-key": key, "expected-key-ids": keyId });
    for (const text of [run.log, run.output, run.env]) {
      assert.doesNotMatch(text, new RegExp(marker));
      assert.doesNotMatch(text, /add-mask/);
      assert.ok(!text.includes(privateText), "the private key never appears");
    }
  }
});

test("a record re-read at another run attempt of the same run opens: re-running a failed job works", (t) => {
  const { recipient, privateText, keyId } = keyPair();
  const sealed = sealedInputs(recipient, [["reply.txt", REPLY]]);
  const run = runOpen(t, { ...sealed, "private-key": privateText, "expected-key-ids": keyId }, { runAttempt: "2" });
  assert.equal(run.status, 0, run.log);
  assert.deepEqual(run.files, { "reply.txt": REPLY });
});

function assertClosed(run, name) {
  assert.equal(run.status, 1, name);
  assert.match(run.log, /^::error::sealed-mismatch: .*nothing is opened$/m, name);
  assert.doesNotMatch(run.log, /rotate/, name);
  assert.deepEqual(run.files, {}, `${name}: nothing is written`);
  assert.equal(run.output, "", name);
}

test("a wrong key, a tampered tag or body, a truncated bundle, an unknown key id or a bad version fails closed without rotation", (t) => {
  const { recipient, privateText, keyId } = keyPair();
  const bundle = sealBundle(recipient, [["reply.txt", REPLY], ["patch.diff", PATCH]], "42", "run");
  const flip = (at) => {
    const copy = Buffer.from(bundle);
    copy[at] ^= 1;
    return copy;
  };
  const replyEnd = 1 + 9 + 4 + 53 + REPLY.length + 16;
  const other = keyPair();
  const cases = {
    "another private key": [bundle, other.privateText, keyId],
    "another private key, its key id expected": [bundle, other.privateText, `${keyId} ${other.keyId}`],
    "a tampered tag": [flip(replyEnd - 1), privateText, keyId],
    "a tampered ciphertext": [flip(1 + 9 + 4 + 53), privateText, keyId],
    "a tampered ephemeral key": [flip(1 + 9 + 4 + 10), privateText, keyId],
    "a truncated bundle": [bundle.subarray(0, bundle.length - 1), privateText, keyId],
    "a bundle cut inside a header": [bundle.subarray(0, 30), privateText, keyId],
    "an unknown key id": [bundle, privateText, "0123456789abcdef"],
    "a bad version": [flip(1 + 9 + 4), privateText, keyId],
  };
  for (const [name, [sealed, key, expected]] of Object.entries(cases)) {
    assertClosed(runOpen(t, { ...sealedInputs(null, null, { bundle: sealed }), "private-key": key, "expected-key-ids": expected }), name);
  }
});

test("a record from another run, another producing job or under another payload name fails closed", (t) => {
  const { recipient, privateText, keyId } = keyPair();
  const open = (inputs, options) => runOpen(t, { ...inputs, "private-key": privateText, "expected-key-ids": keyId }, options);
  assertClosed(open(sealedInputs(recipient, [["reply.txt", REPLY]], { runId: "41" })), "another run id");
  assertClosed(open(sealedInputs(recipient, [["reply.txt", REPLY]], { jobId: "scan" })), "another job id");
  // The reply's record relabelled as the patch: the name is in the AAD and the key.
  const bundle = sealBundle(recipient, [["reply.txt", REPLY]], "42", "run");
  const swapped = Buffer.concat([Buffer.from([10]), Buffer.from("patch.diff"), bundle.subarray(1 + 9)]);
  assertClosed(open(sealedInputs(null, null, { bundle: swapped })), "a swapped payload name");
  // Two records traded between names.
  const pair = sealBundle(recipient, [["reply.txt", Buffer.from("aa")], ["patch.diff", Buffer.from("bb")]], "42", "run");
  const recordAt = (at) => pair.subarray(at + 1 + pair[at] + 4, at + 1 + pair[at] + 4 + pair.readUInt32BE(at + 1 + pair[at]));
  const second = 1 + 9 + 4 + recordAt(0).length;
  const frame = (name, record) => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(record.length);
    return Buffer.concat([Buffer.from([name.length]), Buffer.from(name), length, record]);
  };
  const traded = Buffer.concat([frame("reply.txt", recordAt(second)), frame("patch.diff", recordAt(0))]);
  assertClosed(open(sealedInputs(null, null, { bundle: traded })), "records traded between names");
});

test("a chunk the runner withheld fails with the rotation line, and nothing is written", (t) => {
  const { recipient, privateText, keyId } = keyPair();
  const sealed = sealedInputs(recipient, [["patch.diff", crypto.randomBytes(200000)]]);
  assert.equal(sealed["sealed-4"], undefined, "200000 bytes fill three chunks");
  for (const withheld of ["sealed-1", "sealed-3"]) {
    const run = runOpen(t, { ...sealed, [withheld]: "", "private-key": privateText, "expected-key-ids": keyId });
    assert.equal(run.status, 1);
    assert.match(run.log, /^::error::output-withheld: .*nothing is opened%0Arotate this credential$/m, withheld);
    assert.deepEqual(run.files, {});
  }
});

test("a payload over its cap, a name the caller does not take, or a chunk of the wrong length fails closed", (t) => {
  const { recipient, privateText, keyId } = keyPair();
  const open = (sealed) => runOpen(t, { ...sealed, "private-key": privateText, "expected-key-ids": keyId });
  const over = open(sealedInputs(recipient, [["reply.txt", Buffer.alloc(16385)]]));
  assert.equal(over.status, 1);
  assert.match(over.log, /^::error::too-large: the reply.txt is 16385 bytes, over its 16384-byte cap; nothing is opened$/m);
  assert.deepEqual(over.files, {});
  assertClosed(open(sealedInputs(recipient, [["other.txt", REPLY]])), "an unlisted name");
  const sealed = sealedInputs(recipient, [["reply.txt", REPLY]]);
  assertClosed(open({ ...sealed, "sealed-1": sealed["sealed-1"].slice(0, -4) }), "a short chunk");
  assertClosed(open({ ...sealed, "sealed-length": String(Number(sealed["sealed-length"]) + 4) }), "a long length");
  assertClosed(open({ ...sealed, "sealed-2": "AAAA" }), "an extra chunk");
});

test("an empty or malformed key fails first, with one fixed message naming no key material, even with nothing sealed", (t) => {
  const { recipient, keyId, privateText } = keyPair();
  const sealed = sealedInputs(recipient, [["reply.txt", REPLY]]);
  const ed25519 = crypto.generateKeyPairSync("ed25519").privateKey.export({ format: "der", type: "pkcs8" }).toString("base64");
  const keys = { empty: "", blank: "  \n", "not base64": "not a key!", "truncated DER": privateText.slice(0, 20), "another curve": ed25519 };
  for (const [name, key] of Object.entries(keys)) {
    for (const inputs of [sealed, {}]) {
      const run = runOpen(t, { ...inputs, "private-key": key, "expected-key-ids": keyId });
      assert.equal(run.status, 1, name);
      assert.equal(run.log, "::error::no-key: the private key is missing or malformed; no payload opened\n", name);
      assert.deepEqual(run.files, {}, name);
      assert.equal(run.output, "", name);
    }
  }
});

test("nothing sealed opens to an empty directory; a bad expected key id fails", (t) => {
  const { privateText } = keyPair();
  const run = runOpen(t, { "private-key": privateText, "expected-key-ids": "0123456789abcdef" });
  assert.equal(run.status, 0, run.log);
  assert.equal(run.output, "opened=\n");
  assert.equal(runOpen(t, { "private-key": privateText, "expected-key-ids": "PLACEHOLDER:" }).status, 1);
});

test("oversize ciphertext is refused on its size alone, after the key check and before any base64 decode", (t) => {
  const { privateText, keyId } = keyPair();
  const open = (inputs) => runOpen(t, { ...inputs, "private-key": privateText, "expected-key-ids": keyId });
  const cases = {
    "a chunk over 98304 characters": { "sealed-length": "98305", "sealed-1": "A".repeat(98305) },
    "a length over six chunks": { "sealed-length": String(6 * CHUNK + 4), "sealed-1": "A".repeat(CHUNK) },
    "a length of eleven digits": { "sealed-length": "99999999999", "sealed-1": "AAAA" },
    // Not base64 at all: a decode first would refuse it as a mismatch instead.
    "an oversize chunk that is not base64": { "sealed-length": "100000", "sealed-1": "!".repeat(CHUNK + 1) },
  };
  for (const [name, inputs] of Object.entries(cases)) {
    const run = open(inputs);
    assert.equal(run.status, 1, name);
    assert.match(run.log, /^::error::too-large: the sealed input is over 589824 characters or 98304 a chunk; nothing is opened$/m, name);
    assert.deepEqual(run.files, {}, name);
  }
});

test("after the size cap, the GCM tag and then the AAD are checked: each fails closed, and the authentic record opens", (t) => {
  const { recipient, privateText, keyId } = keyPair();
  const open = (bundle, runId = "42") => runOpen(t, { ...sealedInputs(null, null, { bundle }), "private-key": privateText, "expected-key-ids": keyId }, { runId });
  const bundle = sealBundle(recipient, [["reply.txt", REPLY]], "42", "run");
  assert.equal(open(bundle).status, 0, "the authentic record opens");
  const tag = Buffer.from(bundle);
  tag[tag.length - 1] ^= 1;
  assertClosed(open(tag), "a tampered tag");
  // An intact tag over another AAD: the run id the opener binds differs.
  assertClosed(open(bundle, "43"), "another AAD");
});

test("action.yml reads inputs.private-key in one step's env only, and uses no action", () => {
  assert.equal(ACTION.match(/inputs\.private-key/g).length, 1);
  assert.match(ACTION, /^ {8}PRIVATE_KEY: \$\{\{ inputs\.private-key \}\}$/m);
  const run = ACTION.slice(ACTION.indexOf("      run:"));
  assert.doesNotMatch(run, /\$\{\{/, "no expression in the run body");
  assert.equal((ACTION.match(/^ {4}- name:/gm) ?? []).length, 1, "one step");
  assert.doesNotMatch(ACTION, /^\s*uses:/m);
});

test("keygen writes the private key only to the named descriptor and prints the public key line", async () => {
  const child = spawn(process.execPath, [path.join(HERE, "keygen.mjs"), "--private-key-fd", "3"], { stdio: ["ignore", "pipe", "pipe", "pipe"] });
  const read = (stream) => new Promise((resolve) => {
    const parts = [];
    stream.on("data", (part) => parts.push(part));
    stream.on("end", () => resolve(Buffer.concat(parts).toString()));
  });
  const [stdout, stderr, privateText, status] = await Promise.all([read(child.stdout), read(child.stderr), read(child.stdio[3]), new Promise((resolve) => child.on("close", resolve))]);
  assert.equal(status, 0, stderr);
  assert.match(stdout, /^x25519 [0-9a-f]{16} [A-Za-z0-9+/]{43}=\n$/);
  assert.ok(!stdout.includes(privateText) && !stderr.includes(privateText));
  // The pair matches: what seals to the printed line opens with the piped key.
  const { openBundle, parsePrivateKey } = await import("./open.mjs");
  const recipient = parsePublicKey(stdout);
  const opened = openBundle(parsePrivateKey(privateText), [recipient.keyId], new Map([["a.txt", 10]]), sealBundle(recipient, [["a.txt", Buffer.from("x")]], "1", "run"), "1", "run");
  assert.deepEqual(opened.get("a.txt"), Buffer.from("x"));
});

test("keygen refuses stdout, stderr, a closed descriptor and a missing flag, generating nothing", () => {
  for (const args of [["--private-key-fd", "1"], ["--private-key-fd", "2"], ["--private-key-fd", "9"], []]) {
    const result = spawnSync(process.execPath, [path.join(HERE, "keygen.mjs"), ...args], { encoding: "utf8" });
    assert.equal(result.status, 2, args.join(" "));
    assert.equal(result.stdout, "", args.join(" "));
  }
});
