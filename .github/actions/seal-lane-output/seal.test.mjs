import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { CHUNK, parsePublicKey, sealBundle } from "./seal.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ACTION = readFileSync(path.join(HERE, "action.yml"), "utf8");

// The seal step's env, from action.yml: each `NAME: ${{ inputs.x }}` takes input x.
function stepEnv(inputs) {
  const env = {};
  for (const [, name, input] of ACTION.matchAll(/^ {8}([A-Z_0-9]+): \$\{\{ inputs\.([\w-]+) \}\}$/gm)) {
    const fallback = new RegExp(`^  ${input}:\\n(?:    .*\\n)*?    default: "([^"]*)"`, "m").exec(ACTION)?.[1] ?? "";
    env[name] = inputs[input] ?? fallback;
  }
  return env;
}

function tempDir(t) {
  const dir = mkdtempSync(path.join(tmpdir(), "seal-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function publicLine() {
  const raw = crypto.generateKeyPairSync("x25519").publicKey.export({ format: "der", type: "spki" }).subarray(-32);
  return `x25519 ${crypto.createHash("sha256").update(raw).digest("hex").slice(0, 16)} ${raw.toString("base64")}\n`;
}

function runSeal(t, dir, inputs) {
  const output = path.join(dir, "github-output");
  writeFileSync(output, "");
  const result = spawnSync(process.execPath, [path.join(HERE, "seal.mjs")], {
    env: { PATH: process.env.PATH, GITHUB_OUTPUT: output, GITHUB_WORKSPACE: dir, GITHUB_RUN_ID: "42", ...stepEnv(inputs) },
    encoding: "utf8",
  });
  const outputs = Object.fromEntries(readFileSync(output, "utf8").split("\n").filter(Boolean).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
  return { ...result, outputs };
}

test("the placeholder key, and any malformed key line, fails the step and seals nothing", (t) => {
  const dir = tempDir(t);
  writeFileSync(path.join(dir, "reply.txt"), "hello\n");
  const good = publicLine();
  const [, id, key] = good.trim().split(" ");
  const lines = {
    placeholder: "PLACEHOLDER: owner runs keygen; see .github/actions/open-lane-output/README.md\n",
    empty: "",
    "a key id that is not the key's": `x25519 ${"0".repeat(16)} ${key}\n`,
    "a short key": `x25519 ${id} ${key.slice(4)}\n`,
    "another algorithm": `ed25519 ${id} ${key}\n`,
    "two lines": `${good}${good}`,
  };
  for (const [name, line] of Object.entries(lines)) {
    writeFileSync(path.join(dir, "key.pub"), line);
    const result = runSeal(t, dir, { "public-key-file": "key.pub", payloads: "reply.txt=reply.txt", "job-id": "run" });
    assert.equal(result.status, 1, name);
    assert.match(result.stdout, /^::error::seal-lane-output: /, name);
    assert.deepEqual(result.outputs, {}, name);
  }
  const missing = runSeal(t, dir, { "public-key-file": "absent.pub", payloads: "reply.txt=reply.txt", "job-id": "run" });
  assert.equal(missing.status, 1);
});

test("a present payload seals into chunks one environment variable holds; absent and linked payloads are skipped", (t) => {
  const dir = tempDir(t);
  writeFileSync(path.join(dir, "key.pub"), publicLine());
  writeFileSync(path.join(dir, "patch.diff"), crypto.randomBytes(262144));
  symlinkSync("/etc/hostname", path.join(dir, "link.txt"));
  const result = runSeal(t, dir, { "public-key-file": "key.pub", payloads: "patch.diff=patch.diff\nmissing.txt=nope.txt\nlink.txt=link.txt\n", "job-id": "run" });
  assert.equal(result.status, 0, result.stdout);
  assert.equal(result.stdout, "", "nothing reaches the log");
  const length = Number(result.outputs["sealed-length"]);
  assert.equal(Object.keys(result.outputs).length, 1 + Math.ceil(length / CHUNK));
  for (const [name, value] of Object.entries(result.outputs)) assert.ok(`${name}=${value}`.length < 131072, name);
  // Only the patch: one record, its name, then its ciphertext, which is not the plaintext.
  const bundle = Buffer.from(Object.keys(result.outputs).filter((k) => k !== "sealed-length").map((k) => result.outputs[k]).join(""), "base64");
  assert.equal(bundle.subarray(1, 1 + bundle[0]).toString(), "patch.diff");
  assert.equal(bundle.length, 1 + 10 + 4 + 53 + 262144 + 16);
  // No payload present: no output at all.
  const none = runSeal(t, dir, { "public-key-file": "key.pub", payloads: "missing.txt=nope.txt", "job-id": "run" });
  assert.equal(none.status, 0);
  assert.deepEqual(none.outputs, {});
});

test("a bundle over the chunks the caller carries fails the step", (t) => {
  const dir = tempDir(t);
  writeFileSync(path.join(dir, "key.pub"), publicLine());
  writeFileSync(path.join(dir, "patch.diff"), crypto.randomBytes(CHUNK));
  const result = runSeal(t, dir, { "public-key-file": "key.pub", payloads: "patch.diff=patch.diff", "job-id": "run", "max-chunks": "1" });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /take 2 chunks, over the 1 the caller carries/);
});

test("a bad payload name, a repeated name or a bad job id fails the step", (t) => {
  const dir = tempDir(t);
  writeFileSync(path.join(dir, "key.pub"), publicLine());
  writeFileSync(path.join(dir, "a.txt"), "a");
  for (const [payloads, jobId] of [["../a.txt=a.txt", "run"], ["A.txt=a.txt", "run"], ["a.txt=a.txt\na.txt=a.txt", "run"], ["a.txt=a.txt", "run job"], ["a.txt=a.txt", ""]]) {
    assert.equal(runSeal(t, dir, { "public-key-file": "key.pub", payloads, "job-id": jobId }).status, 1, `${payloads} ${jobId}`);
  }
});

test("each seal takes a fresh ephemeral key and a fresh nonce", () => {
  const recipient = parsePublicKey(publicLine());
  const one = sealBundle(recipient, [["a.txt", Buffer.from("same")]], "42", "run");
  const two = sealBundle(recipient, [["a.txt", Buffer.from("same")]], "42", "run");
  const header = (bundle) => bundle.subarray(1 + 5 + 4, 1 + 5 + 4 + 53);
  assert.notDeepEqual(header(one).subarray(9, 41), header(two).subarray(9, 41), "ephemeral public key");
  assert.notDeepEqual(header(one).subarray(41), header(two).subarray(41), "nonce");
  assert.equal(header(one)[0], 1, "version");
  assert.equal(header(one).subarray(1, 9).toString("hex"), recipient.keyId);
});

// The read runner's run job carries each payload at most at its cap and seals
// them all into the chunks its outputs map (pr-run-activity-read.yml's carry
// and seal steps). A review-threads skill's replies, a dependency-review
// skill's verdict and an issue run's outcome files are never carried
// together, so each run's payloads at their caps, with incompressible bytes,
// still fit: the real sealer, at the caps and chunk count read from that file.
test("the read runner's payloads, each at its cap, seal into the chunks its run job carries", (t) => {
  const workflow = readFileSync(path.join(HERE, "../../workflows/pr-run-activity-read.yml"), "utf8");
  const caps = Object.fromEntries([...workflow.matchAll(/^ +carry [a-z-]+ "\$[A-Z_]+(?:\/[a-z.-]+)?" ([a-z.-]+) ([0-9]+)$/gm)].map((m) => [m[1], Number(m[2])]));
  assert.deepEqual(caps, {
    "reply.txt": 16384,
    "act-turns.json": 32768,
    "patch.diff": 262144,
    "replies.jsonl": 49152,
    "dependency-verdict.json": 49152,
    "work-outcome.json": 49152,
    "lane.json": 4096,
  });
  // One of the two, never both: an if/elif in the carry step.
  assert.match(workflow, /\n +if \[ -n "\$REPLIES_FILE" \]; then\n +carry replies [^\n]+\n +elif \[ -n "\$VERDICT_FILE" \]; then\n +carry dependency-verdict [^\n]+\n +fi\n/);
  const seal = /- name: Seal the reply, run fields and patch for the scan job\n[\s\S]*?payloads: \|\n((?: {12}.*\n)+) {10}job-id: run\n {10}max-chunks: ([0-9]+)\n/.exec(workflow);
  assert.ok(seal, "the seal step");
  const names = seal[1].trim().split("\n").map((line) => line.trim().split("=")[0]);
  assert.deepEqual(names.toSorted(), Object.keys(caps).toSorted(), "every carried payload is sealed");
  const dir = tempDir(t);
  writeFileSync(path.join(dir, "key.pub"), publicLine());
  for (const [name, cap] of Object.entries(caps)) writeFileSync(path.join(dir, name), crypto.randomBytes(cap));
  const sealOf = (payloads) =>
    runSeal(t, dir, {
      "public-key-file": "key.pub",
      payloads: payloads.map((name) => `${name}=${name}`).join("\n"),
      "job-id": "run",
      "max-chunks": seal[2],
    });
  const shared = ["reply.txt", "act-turns.json", "patch.diff"];
  for (const exclusive of [["replies.jsonl"], ["dependency-verdict.json"], ["work-outcome.json", "lane.json"]]) {
    const result = sealOf([...shared, ...exclusive]);
    assert.equal(result.status, 0, `${exclusive}: ${result.stdout}`);
    assert.ok(Number(result.outputs["sealed-length"]) <= Number(seal[2]) * CHUNK, exclusive);
    assert.equal(Object.keys(result.outputs).length, 1 + Math.ceil(Number(result.outputs["sealed-length"]) / CHUNK), exclusive);
  }
  // The caps sit near the seal's limit: both exclusive payloads together do not fit.
  assert.equal(sealOf(names).status, 1, "replies and a verdict together would not fit");
});
