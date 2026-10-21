// The owner's offline key generation for open-lane-output. Prints the public
// key file's one line to stdout and writes the private key, base64 PKCS#8 DER,
// to the file descriptor --private-key-fd names (3 or above, so never the
// terminal), for a pipe into the secret store. It writes no file itself.
//
//   { node keygen.mjs --private-key-fd 3 >key.pub; } 3>&1 | gh secret set NAME --env ENV
import crypto from "node:crypto";
import { fstatSync, writeSync } from "node:fs";
import process from "node:process";
import { fileURLToPath } from "node:url";

export function generate() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync("x25519");
  const raw = publicKey.export({ format: "der", type: "spki" }).subarray(-32);
  const keyId = crypto.createHash("sha256").update(raw).digest("hex").slice(0, 16);
  return {
    publicLine: `x25519 ${keyId} ${raw.toString("base64")}\n`,
    privateText: privateKey.export({ format: "der", type: "pkcs8" }).toString("base64"),
  };
}

export function main(argv = process.argv.slice(2)) {
  const [flag, value, ...rest] = argv;
  if (flag !== "--private-key-fd" || !/^[0-9]+$/.test(value ?? "") || rest.length > 0) {
    throw new Error("usage: keygen.mjs --private-key-fd <fd>, with fd 3 or above");
  }
  const fd = Number(value);
  if (fd < 3) throw new Error("the private key never goes to stdin, stdout or stderr; name fd 3 or above");
  try {
    fstatSync(fd);
  } catch {
    throw new Error(`file descriptor ${fd} is not open; nothing was generated`);
  }
  const { publicLine, privateText } = generate();
  writeSync(fd, privateText);
  process.stdout.write(publicLine);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`keygen: ${error.message}\n`);
    process.exit(2);
  }
}
