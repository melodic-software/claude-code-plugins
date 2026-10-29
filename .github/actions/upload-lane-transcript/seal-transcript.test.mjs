import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

import { generate } from "../open-lane-output/keygen.mjs";
import { openRecord, parsePrivateKey } from "../open-lane-output/open.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ACTION = readFileSync(path.join(HERE, "action.yml"), "utf8");
const MARKER = "plaintext-marker-7f3c";
const TRANSCRIPT = JSON.stringify([{ type: "assistant", message: { content: [{ type: "text", text: MARKER }] } }]);

// The seal step's env, from action.yml: each `NAME: ${{ inputs.x }}` takes input x.
function stepEnv(inputs) {
  const env = {};
  for (const [, name, input] of ACTION.matchAll(/^ {8}([A-Z_0-9]+): \$\{\{ inputs\.([\w-]+) \}\}$/gm)) env[name] = inputs[input] ?? "";
  return env;
}

function workDir(t) {
  const dir = tempDir("lane-transcript-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function run(dir, inputs) {
  const output = path.join(dir, "github-output");
  writeFileSync(output, "");
  const result = spawnSync(process.execPath, [path.join(HERE, "seal-transcript.mjs")], {
    env: { PATH: process.env.PATH, GITHUB_OUTPUT: output, RUNNER_TEMP: dir, GITHUB_RUN_ID: "42", ...stepEnv(inputs) },
    encoding: "utf8",
  });
  const outputs = Object.fromEntries(readFileSync(output, "utf8").split("\n").filter(Boolean).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
  return { ...result, outputs };
}

const sealedFiles = (dir) => (existsSync(path.join(dir, "lane-transcript")) ? readdirSync(path.join(dir, "lane-transcript"), { recursive: true }) : []);

function openSealed(file, privateText, keyId, { runId = "42", jobId = "refine-issue" } = {}) {
  return gunzipSync(openRecord(parsePrivateKey(privateText), [keyId], "transcript.json.gz", readFileSync(file), runId, jobId)).toString("utf8");
}

test("a transcript seals to the public key and opens, gunzipped, to the same bytes with the private key", (t) => {
  const dir = workDir(t);
  const { publicLine, privateText } = generate();
  const keyId = publicLine.split(" ")[1];
  writeFileSync(path.join(dir, "execution.json"), TRANSCRIPT);
  const result = run(dir, { "public-key": publicLine, "execution-file": path.join(dir, "execution.json"), "job-id": "refine-issue" });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.ok(result.outputs.file.startsWith(path.join(dir, "lane-transcript")), result.outputs.file);
  const sealed = readFileSync(result.outputs.file);
  assert.equal(sealed.includes(Buffer.from(MARKER)), false, "no plaintext in the sealed file");
  assert.notDeepEqual([...sealed.subarray(0, 2)], [0x1f, 0x8b], "the file is not the bare gzip");
  assert.equal(openSealed(result.outputs.file, privateText, keyId), TRANSCRIPT);
  assert.doesNotMatch(result.stdout + result.stderr, new RegExp(MARKER));
});

test("the record opens only for its own key, run and job", (t) => {
  const dir = workDir(t);
  const { publicLine, privateText } = generate();
  const keyId = publicLine.split(" ")[1];
  const other = generate();
  writeFileSync(path.join(dir, "execution.json"), TRANSCRIPT);
  const { outputs } = run(dir, { "public-key": publicLine, "execution-file": path.join(dir, "execution.json"), "job-id": "refine-issue" });
  assert.throws(() => openSealed(outputs.file, privateText, keyId, { runId: "43" }), /does not open/);
  assert.throws(() => openSealed(outputs.file, privateText, keyId, { jobId: "judge-a1" }), /does not open/);
  assert.throws(() => openSealed(outputs.file, other.privateText, keyId), /sealed to a key other/);
});

test("with the key variable unset the step passes, writes a notice and seals nothing", (t) => {
  const dir = workDir(t);
  writeFileSync(path.join(dir, "execution.json"), TRANSCRIPT);
  const result = run(dir, { "public-key": "", "execution-file": path.join(dir, "execution.json"), "job-id": "refine-issue" });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^::notice::.*LANE_TRANSCRIPT_PUBLIC_KEY/m);
  assert.deepEqual(result.outputs, {});
  assert.deepEqual(sealedFiles(dir), []);
});

test("a malformed key fails the step and seals nothing, even with no transcript", (t) => {
  const dir = workDir(t);
  writeFileSync(path.join(dir, "execution.json"), TRANSCRIPT);
  const [, id, key] = generate().publicLine.trim().split(" ");
  for (const [bad, file] of [
    ["x25519 0000000000000000 REPLACE_WITH_PUBLIC_KEY", "execution.json"],
    [`x25519 ${id.replace(/^./, id[0] === "0" ? "1" : "0")} ${key}`, "execution.json"],
    ["-----BEGIN PUBLIC KEY-----", ""],
  ]) {
    const result = run(dir, { "public-key": bad, "execution-file": file && path.join(dir, file), "job-id": "refine-issue" });
    assert.equal(result.status, 1, bad);
    assert.match(result.stdout, /^::error::upload-lane-transcript: /m, bad);
    assert.deepEqual(result.outputs, {}, bad);
    assert.deepEqual(sealedFiles(dir), [], bad);
  }
});

test("a missing, empty or linked transcript seals nothing; a bad job id fails", (t) => {
  const dir = workDir(t);
  const { publicLine } = generate();
  writeFileSync(path.join(dir, "empty.json"), "");
  writeFileSync(path.join(dir, "execution.json"), TRANSCRIPT);
  symlinkSync(path.join(dir, "execution.json"), path.join(dir, "linked.json"));
  for (const file of ["", path.join(dir, "absent.json"), path.join(dir, "empty.json"), path.join(dir, "linked.json")]) {
    const result = run(dir, { "public-key": publicLine, "execution-file": file, "job-id": "refine-issue" });
    assert.equal(result.status, 0, file);
    assert.deepEqual(result.outputs, {}, file);
  }
  assert.deepEqual(sealedFiles(dir), []);
  for (const jobId of ["", "1st", "has space", "a.b"]) {
    const result = run(dir, { "public-key": publicLine, "execution-file": path.join(dir, "execution.json"), "job-id": jobId });
    assert.equal(result.status, 1, jobId);
    assert.deepEqual(sealedFiles(dir), [], jobId);
  }
});

test("the upload keeps only the sealed file, for 7 days, named by job and attempt", () => {
  const upload = ACTION.slice(ACTION.indexOf("uses: actions/upload-artifact@"));
  assert.match(ACTION, /if: steps\.seal\.outputs\.file != ''\n\s+uses: actions\/upload-artifact@[0-9a-f]{40} /);
  assert.match(upload, /^ {8}name: lane-transcript-\$\{\{ inputs\.job-id \}\}-\$\{\{ github\.run_attempt \}\}$/m);
  assert.match(upload, /^ {8}path: \$\{\{ steps\.seal\.outputs\.file \}\}$/m);
  // The issue's retention: 7 days (cant-fail-ok: the issue's stated contract).
  assert.match(upload, /^ {8}retention-days: 7$/m);
  assert.match(upload, /^ {8}overwrite: false$/m);
});
