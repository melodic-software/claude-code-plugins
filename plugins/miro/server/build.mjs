// Deterministic single-file bundler for the miro MCP server.
//
// Plugin install copies the plugin directory into the consumer's cache and runs no
// build step, so the runtime artifact must ship committed. This bundles the TypeScript
// source and all runtime dependencies into one self-contained `dist/index.min.js`,
// invoked via `node ${CLAUDE_PLUGIN_ROOT}/server/dist/index.min.js` (a bundled
// `node <server>` sidesteps the open Windows bare-`npx` spawn bug entirely).
//
// The Node project lives under `server/`, not at the plugin root, on purpose: Claude
// Code runs `npm ci` in the cached copy whenever the plugin ROOT holds both a
// package.json and a lockfile, and that install cannot be turned off. Kept here, the
// lockfile still pins the toolchain for CI and Dependabot, but no consumer's cache
// materialises this project's devDependencies (plugins-reference.md, "Node.js package
// dependencies", verified 2026-09-11; recheck when that section changes).
//
// The source is the single source of truth; the bundle is generated output. `--check`
// rebuilds in memory and fails on any drift from the committed artifact, so CI proves
// the committed bundle is exactly what the pinned toolchain produces from source.

import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const root = dirname(fileURLToPath(import.meta.url));
const outfile = join(root, "dist", "index.min.js");
const checkOnly = process.argv.includes("--check");

// Top-level `await` in the entry forces ESM output; the createRequire banner supplies
// the `require` that bundled CommonJS dependencies expect under `"type": "module"`.
// Minified + `.min.js`: a committed generated bundle is reviewed via its source, not its
// bytes (the drift check proves they match), and `.min.` is the repo-wide carve-out that
// keeps generated bundles out of the text-quality lanes (typos, editorconfig).
const result = await build({
  entryPoints: [join(root, "src", "index.ts")],
  bundle: true,
  minify: true,
  platform: "node",
  format: "esm",
  target: "node24",
  legalComments: "none",
  banner: {
    js: 'import { createRequire } from "node:module";\nconst require = createRequire(import.meta.url);',
  },
  write: false,
});

// The server runs via `node dist/index.min.js`, so drop the entry shebang esbuild preserves —
// the committed artifact is not marked executable and must not trip the shebang exec-bit gate.
const code = result.outputFiles[0].text.replace(/^#!.*\r?\n/, "");

if (checkOnly) {
  let committed;
  try {
    committed = readFileSync(outfile, "utf8");
  } catch {
    console.error("dist/index.min.js is missing — run `npm run bundle` and commit the result.");
    process.exit(1);
  }
  if (committed !== code) {
    console.error("dist/index.min.js is stale — run `npm run bundle` and commit the result.");
    process.exit(1);
  }
  console.log("dist/index.min.js matches source.");
} else {
  mkdirSync(dirname(outfile), { recursive: true });
  writeFileSync(outfile, code);
  console.log(`Wrote ${outfile} (${code.length} bytes).`);
}
