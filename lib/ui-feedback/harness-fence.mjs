import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { canonicalOrigin } from "./dev-origin.mjs";

/** The response headers a real-stack route sends so only the bridge origin's host page may frame it. */
export function fenceHeaders(bridgeOrigin) {
  return { "Content-Security-Policy": `frame-ancestors ${canonicalOrigin(bridgeOrigin)}` };
}

/** A connect-style middleware that sets fenceHeaders(bridgeOrigin) on every dev-server response. */
export function harnessFence(bridgeOrigin) {
  const headers = Object.entries(fenceHeaders(bridgeOrigin));
  return (req, res, next) => {
    for (const [name, value] of headers) res.setHeader(name, value);
    next();
  };
}

function main(argv) {
  if (argv.length !== 1) {
    console.error("usage: node harness-fence.mjs <bridge origin>");
    process.exit(2);
  }
  try {
    for (const [name, value] of Object.entries(fenceHeaders(argv[0]))) console.log(`${name}: ${value}`);
  } catch (err) {
    console.error(`harness-fence: ${err.message}`);
    process.exit(2);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main(process.argv.slice(2));
