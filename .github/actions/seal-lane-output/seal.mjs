// Seal named payload files to an X25519 public key as one bundle, cut into
// fixed-size base64 chunks that each fit one environment variable. Each
// payload gets its own ephemeral key and random nonce; the key comes from
// HKDF-SHA256 over the shared secret, and AES-256-GCM binds the header, the
// payload name, the run id and the producing job id, so a record moved to
// another name, job or run does not open. README.md states the format.
import crypto from "node:crypto";
import { appendFileSync, lstatSync, readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export const VERSION = 1;
export const CHUNK = 98304;
export const MAX_CHUNKS = 6;
export const NAME = /^[a-z0-9]+([._-][a-z0-9]+)*$/;
export const JOB_ID = /^[A-Za-z_][A-Za-z0-9_-]{0,99}$/;
export const RUN_ID = /^[1-9][0-9]{0,19}$/;
const KEY_LINE = /^x25519 ([0-9a-f]{16}) ([A-Za-z0-9+/]{43}=)$/;
const SPKI_PREFIX = Buffer.from("302a300506032b656e032100", "hex");

export class SealError extends Error {}

export const keyIdOf = (raw) => crypto.createHash("sha256").update(raw).digest("hex").slice(0, 16);

// The public key file: one line, `x25519 <key id> <base64 raw key>`, where the
// key id is the first 16 hex digits of the raw key's SHA-256.
export function parsePublicKey(text) {
  const match = KEY_LINE.exec(String(text).trim());
  const raw = match && Buffer.from(match[2], "base64");
  if (!match || raw.length !== 32 || keyIdOf(raw) !== match[1]) {
    throw new SealError("the public key file holds no x25519 key line with a matching key id (is it still a placeholder?)");
  }
  return { keyId: match[1], raw, key: crypto.createPublicKey({ key: Buffer.concat([SPKI_PREFIX, raw]), format: "der", type: "spki" }) };
}

export const rawPublicKey = (key) => key.export({ format: "der", type: "spki" }).subarray(-32);

export function context(name, runId, jobId) {
  if (!NAME.test(name)) throw new SealError(`the payload name ${JSON.stringify(name)} is not a lower-case file name`);
  if (!RUN_ID.test(String(runId))) throw new SealError("GITHUB_RUN_ID is not a run id");
  if (!JOB_ID.test(jobId)) throw new SealError("the job-id input is not a job key");
  return Buffer.from(`lane-output/v${VERSION}\0${name}\0${runId}\0${jobId}`);
}

// One record: version (1) | key id (8) | ephemeral public key (32) | nonce (12) | ciphertext | tag (16).
export function sealRecord(recipient, name, data, runId, jobId) {
  const bound = context(name, runId, jobId);
  const ephemeral = crypto.generateKeyPairSync("x25519");
  const epk = rawPublicKey(ephemeral.publicKey);
  const nonce = crypto.randomBytes(12);
  const header = Buffer.concat([Buffer.from([VERSION]), Buffer.from(recipient.keyId, "hex"), epk, nonce]);
  const shared = crypto.diffieHellman({ privateKey: ephemeral.privateKey, publicKey: recipient.key });
  const key = Buffer.from(crypto.hkdfSync("sha256", shared, Buffer.concat([epk, recipient.raw]), Buffer.concat([bound, Buffer.from([0]), header]), 32));
  const cipher = crypto.createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.concat([header, bound]));
  return Buffer.concat([header, cipher.update(data), cipher.final(), cipher.getAuthTag()]);
}

// The bundle: per payload, name length (1) | name | record length (4, big-endian) | record.
export function sealBundle(recipient, payloads, runId, jobId) {
  const parts = [];
  for (const [name, data] of payloads) {
    const record = sealRecord(recipient, name, data, runId, jobId);
    const length = Buffer.alloc(4);
    length.writeUInt32BE(record.length);
    parts.push(Buffer.from([name.length]), Buffer.from(name), length, record);
  }
  return Buffer.concat(parts);
}

// `name=path` lines; a missing path or a symbolic link is an absent payload.
export function readPayloads(text, cwd) {
  const payloads = [];
  const seen = new Set();
  for (const line of String(text).split("\n").map((l) => l.trim()).filter(Boolean)) {
    const at = line.indexOf("=");
    const name = at > 0 ? line.slice(0, at) : "";
    if (!NAME.test(name) || seen.has(name)) throw new SealError(`the payloads line ${JSON.stringify(line)} is not a new name=path pair`);
    seen.add(name);
    const file = path.resolve(cwd, line.slice(at + 1));
    let stat;
    try {
      stat = lstatSync(file);
    } catch {
      continue;
    }
    if (stat.isFile()) payloads.push([name, readFileSync(file)]);
  }
  return payloads;
}

export function chunks(bundle, maxChunks) {
  const text = bundle.toString("base64");
  const count = Math.ceil(text.length / CHUNK);
  if (count > maxChunks) throw new SealError(`the sealed payloads take ${count} chunks, over the ${maxChunks} the caller carries`);
  return { length: text.length, parts: Array.from({ length: count }, (_, i) => text.slice(i * CHUNK, (i + 1) * CHUNK)) };
}

export function main(env = process.env) {
  const maxChunks = Number(env.MAX_CHUNKS || MAX_CHUNKS);
  if (!Number.isInteger(maxChunks) || maxChunks < 1 || maxChunks > MAX_CHUNKS) throw new SealError(`max-chunks must be 1 to ${MAX_CHUNKS}`);
  const cwd = env.GITHUB_WORKSPACE || process.cwd();
  let keyText;
  try {
    keyText = readFileSync(path.resolve(cwd, env.PUBLIC_KEY_FILE ?? ""), "utf8");
  } catch {
    throw new SealError("the public key file cannot be read");
  }
  const recipient = parsePublicKey(keyText);
  const payloads = readPayloads(env.PAYLOADS ?? "", cwd);
  const lines = [];
  if (payloads.length > 0) {
    const { length, parts } = chunks(sealBundle(recipient, payloads, env.GITHUB_RUN_ID, env.JOB_ID ?? ""), maxChunks);
    lines.push(`sealed-length=${length}`, ...parts.map((part, i) => `sealed-${i + 1}=${part}`));
  }
  if (lines.length > 0) appendFileSync(env.GITHUB_OUTPUT, `${lines.join("\n")}\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stdout.write(`::error::seal-lane-output: ${error instanceof SealError ? error.message : `the payloads could not be sealed (${error.name})`}\n`);
    process.exit(1);
  }
}
