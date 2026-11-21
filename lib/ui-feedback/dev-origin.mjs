import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

/** `input` when it is an http or https origin exactly as new URL(input).origin spells it; else throws. */
export function canonicalOrigin(input) {
  let url;
  try {
    url = new URL(input);
  } catch {
    throw new Error(`${JSON.stringify(input)} is not a URL`);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`${JSON.stringify(input)} is not an http or https origin`);
  }
  if (url.origin !== input) {
    throw new Error(`${JSON.stringify(input)} is not its own origin; pass ${url.origin}`);
  }
  if (!/^[a-z0-9.-]+$/.test(url.hostname)) {
    throw new Error(`${JSON.stringify(input)} has a host a CSP frame-src cannot name; use a name such as localhost`);
  }
  return url.origin;
}

function main(argv) {
  if (argv.length !== 1) {
    console.error("usage: node dev-origin.mjs <origin>");
    process.exit(2);
  }
  try {
    console.log(canonicalOrigin(argv[0]));
  } catch (err) {
    console.error(`dev-origin: ${err.message}`);
    process.exit(2);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main(process.argv.slice(2));
