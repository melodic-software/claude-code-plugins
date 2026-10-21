// Open a bundle seal-lane-output made, with the recipient's X25519 private
// key, into files under a directory the caller names. Every record is checked
// and decrypted in memory before any file is written; a withheld chunk, a
// length or framing error, an unknown key id, a wrong key, a bad version or a
// failed GCM tag writes nothing. Plaintext reaches only those files: nothing
// here prints it, sets it as an output or masks anything derived from it.
import crypto from "node:crypto";
import { appendFileSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export const VERSION = 1;
export const CHUNK = 98304;
export const MAX_CHUNKS = 6;
const NAME = /^[a-z0-9]+([._-][a-z0-9]+)*$/;
const JOB_ID = /^[A-Za-z_][A-Za-z0-9_-]{0,99}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const KEY_ID = /^[0-9a-f]{16}$/;
const HEADER = 1 + 8 + 32 + 12;
const TAG = 16;
const SPKI_PREFIX = Buffer.from("302a300506032b656e032100", "hex");

// A refusal names a kind and never a value; `rotate` adds the rotation line.
export class OpenError extends Error {
  constructor(message, { rotate = false } = {}) {
    super(rotate ? `${message}\nrotate this credential` : message);
  }
}
const mismatch = (what) => new OpenError(`sealed-mismatch: ${what}; nothing is opened`);

const keyIdOf = (raw) => crypto.createHash("sha256").update(raw).digest("hex").slice(0, 16);
const context = (name, runId, jobId) => Buffer.from(`lane-output/v${VERSION}\0${name}\0${runId}\0${jobId}`);

// The private key: base64 PKCS#8 DER of an X25519 key, as keygen.mjs writes it.
export function parsePrivateKey(text) {
  let key;
  try {
    key = crypto.createPrivateKey({ key: Buffer.from(String(text).trim(), "base64"), format: "der", type: "pkcs8" });
  } catch {
    throw new OpenError("no-key: the private-key input is no PKCS#8 key; nothing is opened");
  }
  if (key.asymmetricKeyType !== "x25519") throw new OpenError("no-key: the private-key input is no x25519 key; nothing is opened");
  const raw = crypto.createPublicKey(key).export({ format: "der", type: "spki" }).subarray(-32);
  return { key, raw, keyId: keyIdOf(raw) };
}

// `name=bytes` lines: the payload names that may open, each with its cap.
export function parseCaps(text) {
  const caps = new Map();
  for (const line of String(text).split("\n").map((l) => l.trim()).filter(Boolean)) {
    const match = /^([^=]+)=([0-9]{1,10})$/.exec(line);
    if (!match || !NAME.test(match[1]) || caps.has(match[1])) throw new OpenError(`bad-input: the max-bytes line ${JSON.stringify(line)} is not a new name=bytes pair`);
    caps.set(match[1], Number(match[2]));
  }
  return caps;
}

// The chunks back into one base64 text. A chunk the length says is there but
// that arrived empty is the runner's withheld output, the rotation signal.
export function joinChunks(lengthText, parts) {
  if (!/^[1-9][0-9]{0,9}$/.test(lengthText)) throw mismatch("the sealed length is no count");
  const length = Number(lengthText);
  if (length > parts.length * CHUNK) throw mismatch("the sealed length is over what the chunks carry");
  for (const [i, part] of parts.entries()) {
    const want = Math.max(0, Math.min(CHUNK, length - i * CHUNK));
    if (part === "" && want > 0) {
      throw new OpenError(`output-withheld: the runner withheld sealed chunk ${i + 1} as an output that may hold a secret; nothing is opened`, { rotate: true });
    }
    if (part.length !== want) throw mismatch(`sealed chunk ${i + 1} is not its expected length`);
  }
  const text = parts.join("");
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(text) || text.length % 4 !== 0) throw mismatch("the sealed text is not base64");
  return Buffer.from(text, "base64");
}

export function openRecord(recipient, expected, name, record, runId, jobId) {
  if (record.length < HEADER + TAG) throw mismatch(`the ${name} record is truncated`);
  const header = record.subarray(0, HEADER);
  if (header[0] !== VERSION) throw mismatch(`the ${name} record has an unknown version`);
  const keyId = header.subarray(1, 9).toString("hex");
  if (!expected.includes(keyId)) throw mismatch(`the ${name} record names an unknown key id`);
  if (keyId !== recipient.keyId) throw mismatch(`the ${name} record is sealed to a key other than the one given`);
  const epk = header.subarray(9, 41);
  const nonce = header.subarray(41, HEADER);
  const bound = context(name, runId, jobId);
  try {
    const shared = crypto.diffieHellman({
      privateKey: recipient.key,
      publicKey: crypto.createPublicKey({ key: Buffer.concat([SPKI_PREFIX, epk]), format: "der", type: "spki" }),
    });
    const key = Buffer.from(crypto.hkdfSync("sha256", shared, Buffer.concat([epk, recipient.raw]), Buffer.concat([bound, Buffer.from([0]), header]), 32));
    const decipher = crypto.createDecipheriv("aes-256-gcm", key, nonce);
    decipher.setAAD(Buffer.concat([header, bound]));
    decipher.setAuthTag(record.subarray(record.length - TAG));
    // final() checks the tag; nothing decrypted is kept before it passes.
    return Buffer.concat([decipher.update(record.subarray(HEADER, record.length - TAG)), decipher.final()]);
  } catch {
    throw mismatch(`the ${name} record does not open for this key, payload name, run and job`);
  }
}

// Every record of the bundle, opened in memory, keyed by payload name.
export function openBundle(recipient, expected, caps, bundle, runId, jobId) {
  const opened = new Map();
  let at = 0;
  while (at < bundle.length) {
    const nameLength = bundle[at];
    if (at + 1 + nameLength + 4 > bundle.length) throw mismatch("the bundle is truncated");
    const name = bundle.subarray(at + 1, at + 1 + nameLength).toString("latin1");
    const recordLength = bundle.readUInt32BE(at + 1 + nameLength);
    at += 1 + nameLength + 4;
    if (!NAME.test(name) || !caps.has(name)) throw mismatch("the bundle holds a payload name the caller does not take");
    if (opened.has(name)) throw mismatch(`the bundle holds the ${name} twice`);
    if (at + recordLength > bundle.length) throw mismatch(`the ${name} record is truncated`);
    const bytes = recordLength - HEADER - TAG;
    if (bytes > caps.get(name)) {
      throw new OpenError(`too-large: the ${name} is ${bytes} bytes, over its ${caps.get(name)}-byte cap; nothing is opened`);
    }
    opened.set(name, openRecord(recipient, expected, name, bundle.subarray(at, at + recordLength), runId, jobId));
    at += recordLength;
  }
  return opened;
}

export function main(env = process.env) {
  const jobId = env.JOB_ID ?? "";
  const runId = env.GITHUB_RUN_ID ?? "";
  if (!JOB_ID.test(jobId)) throw new OpenError("bad-input: the job-id input is not a job key");
  if (!RUN_ID.test(runId)) throw new OpenError("bad-input: GITHUB_RUN_ID is not a run id");
  const expected = String(env.EXPECTED_KEY_IDS ?? "").split(/\s+/).filter(Boolean);
  if (expected.length === 0 || !expected.every((id) => KEY_ID.test(id))) {
    throw new OpenError("bad-input: expected-key-ids holds no key id, or one that is not 16 hex digits");
  }
  const caps = parseCaps(env.MAX_BYTES ?? "");
  const directory = env.DIRECTORY ?? "";
  if (!path.isAbsolute(directory)) throw new OpenError("bad-input: the directory input is not an absolute path");
  const parts = Array.from({ length: MAX_CHUNKS }, (_, i) => env[`SEALED_${i + 1}`] ?? "");
  const lengthText = env.SEALED_LENGTH ?? "";
  let opened = new Map();
  if (lengthText !== "" || parts.some((part) => part !== "")) {
    const bundle = joinChunks(lengthText, parts);
    opened = openBundle(parsePrivateKey(env.PRIVATE_KEY ?? ""), expected, caps, bundle, runId, jobId);
  }
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  if (readdirSync(directory).length > 0) throw new OpenError("bad-input: the directory is not empty");
  for (const [name, data] of opened) writeFileSync(path.join(directory, name), data, { flag: "wx", mode: 0o444 });
  appendFileSync(env.GITHUB_OUTPUT, `opened=${[...opened.keys()].join(" ")}\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const env = { ...process.env };
  delete process.env.PRIVATE_KEY;
  try {
    main(env);
  } catch (error) {
    const message = error instanceof OpenError ? error.message : `sealed-mismatch: the sealed payloads could not be opened (${error.name}); nothing is opened`;
    // One annotation, the refusal on its first line and any rotation line after it.
    process.stdout.write(`::error::${message.replaceAll("\n", "%0A")}\n`);
    process.exit(1);
  }
}
