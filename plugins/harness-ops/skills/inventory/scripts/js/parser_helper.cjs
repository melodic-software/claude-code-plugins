"use strict";
// Long-lived parser helper for inventory.py --reader=parser.
//
// Protocol: one JSON request per line on stdin, one JSON response per line on
// stdout, in order. Every response echoes the request's `id`.
//
//   {"id":1,"op":"ping"}
//     -> {"id":1,"ok":true,"node":"v24.0.0","acorn":"8.18.0","eslint_scope":"9.1.2"}
//   {"id":2,"op":"parse_ok","source":"..."}
//     -> {"id":2,"ok":true,"parsed":true}
//     -> {"id":2,"ok":true,"parsed":false,"error":"Unexpected token (3:4)","pos":17}
//   anything else
//     -> {"id":...,"ok":false,"error":"..."}
//
// acorn and eslint-scope are resolved through NODE_PATH, which the Python
// side points at the node_modules `npm ci` installed from this directory's
// lockfile. Both are required at load, so a ping answering at all proves the
// whole dependency set loads.

const readline = require("node:readline");

let acorn;
let eslintScope;
try {
  acorn = require("acorn");
  eslintScope = require("eslint-scope");
} catch (e) {
  process.stderr.write(`cannot load the parser packages: ${e.message.split("\n")[0]}\n`);
  process.exit(1);
}

const PARSE_OPTIONS = { ecmaVersion: "latest", sourceType: "module" };

function handle(req) {
  switch (req.op) {
    case "ping":
      return {
        ok: true,
        node: process.version,
        acorn: acorn.version,
        eslint_scope: eslintScope.version,
      };
    case "parse_ok":
      if (typeof req.source !== "string") {
        return { ok: false, error: "parse_ok needs a string `source`" };
      }
      try {
        acorn.parse(req.source, PARSE_OPTIONS);
        return { ok: true, parsed: true };
      } catch (e) {
        return { ok: true, parsed: false, error: e.message, pos: e.pos ?? null };
      }
    default:
      return { ok: false, error: `unknown op: ${JSON.stringify(req.op)}` };
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  let req;
  try {
    req = JSON.parse(line);
  } catch (e) {
    process.stdout.write(`${JSON.stringify({ id: null, ok: false, error: `bad request: ${e.message}` })}\n`);
    return;
  }
  const res = handle(req);
  process.stdout.write(`${JSON.stringify({ id: req.id ?? null, ...res })}\n`);
});
