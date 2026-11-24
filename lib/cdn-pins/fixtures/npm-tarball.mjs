import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";

const REGISTRY = "https://registry.npmjs.org/";

export const tarballUrl = (name, version) => `${REGISTRY}${name}/-/${name.slice(name.lastIndexOf("/") + 1)}-${version}.tgz`;
export const sha512 = (bytes) => `sha512-${createHash("sha512").update(bytes).digest("base64")}`;

function header(name, size, { type = "0", prefix = "" } = {}) {
  const block = Buffer.alloc(512);
  const put = (text, start) => block.write(text, start, "latin1");
  put(name, 0);
  put("0000644\0", 100);
  put("0000000\0", 108);
  put("0000000\0", 116);
  put(`${size.toString(8).padStart(11, "0")}\0`, 124);
  put("00000000000\0", 136);
  put("        ", 148);
  put(type, 156);
  put("ustar\0", 257);
  put("00", 263);
  put(prefix, 345);
  const sum = block.reduce((acc, byte) => acc + byte, 0);
  put(`${sum.toString(8).padStart(6, "0")}\0 `, 148);
  return block;
}

/** A ustar archive of `entries`, each { name, body, type?, prefix? }, ending in two zero blocks. */
export function tar(entries) {
  const parts = [];
  for (const { name, body = "", type, prefix } of entries) {
    const data = Buffer.from(body);
    parts.push(header(name, data.length, { type, prefix }), data, Buffer.alloc((512 - (data.length % 512)) % 512));
  }
  return Buffer.concat([...parts, Buffer.alloc(1024)]);
}

/** The gzipped npm tarball holding one file under package/, as npm pack lays it out. */
export const npmTarball = (file, body) => gzipSync(tar([{ name: "package/package.json", body: "{}" }, { name: `package/${file}`, body }]));

/** A lockfileVersion 3 lock entry per { name: [version, tarball bytes] }. */
export function lockOf(entries) {
  const packages = { "": { name: "cdn-pins" } };
  for (const [name, [version, bytes]] of Object.entries(entries)) {
    packages[`node_modules/${name}`] = { version, resolved: tarballUrl(name, version), integrity: sha512(bytes) };
  }
  return { name: "cdn-pins", lockfileVersion: 3, requires: true, packages };
}

/** The fake-fetch body for binary bytes. */
export const binary = (bytes) => ({ base64: Buffer.from(bytes).toString("base64") });
