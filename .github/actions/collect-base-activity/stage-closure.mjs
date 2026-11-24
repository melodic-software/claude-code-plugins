import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const JS_LOADS = /(?:^\s*(?:import|export)\b[^;]*?\bfrom\s*|^\s*import\s+|\bimport\(\s*|\bnew URL\(\s*)["'](\.\.?\/[^"']+)["']/gm;
const SH_LOADS = /(?:\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)|\$\{BASH_SOURCE\[0\]%\/\*\})\/([^"\s]+)/g;

function moduleKind(file, text) {
  if (/\.(sh|bash)$/.test(file) || /^#!.*\b(?:bash|sh)\b/.test(text)) return "shell";
  if (/\.[mc]?js$/.test(file) || /^#!.*\bnode\b/.test(text)) return "js";
  return null;
}

export function loads(file) {
  const text = readFileSync(file, "utf8");
  const kind = moduleKind(file, text);
  if (!kind) return [];
  const code = text.replace(kind === "shell" ? /^\s*#.*$/gm : /^\s*\/\/.*$/gm, "");
  return [...code.matchAll(kind === "shell" ? SH_LOADS : JS_LOADS)].map((m) => path.resolve(path.dirname(file), m[1]));
}

const KEPT_TREES = [path.join(".github", "actions", "resolve-config", "node_modules")];

export function stage(base, script, dest) {
  const root = path.resolve(base);
  const copies = new Set();
  const entryDir = path.dirname(path.normalize(script));
  if (entryDir !== ".") {
    for (const entry of readdirSync(path.join(root, entryDir), { withFileTypes: true })) {
      if (!entry.isDirectory()) copies.add(path.join(entryDir, entry.name));
    }
  }
  const seen = new Set();
  const visit = (file) => {
    const rel = path.relative(root, file);
    if (seen.has(file) || !rel || rel.startsWith("..") || path.isAbsolute(rel) || !existsSync(file)) return;
    seen.add(file);
    copies.add(rel);
    if (statSync(file).isDirectory()) return;
    for (const kept of KEPT_TREES) if (path.dirname(kept) === path.dirname(rel) && existsSync(path.join(root, kept))) copies.add(kept);
    for (const next of loads(file)) visit(next);
  };
  visit(path.join(root, script));
  for (const rel of copies) {
    mkdirSync(path.dirname(path.join(dest, rel)), { recursive: true });
    cpSync(path.join(root, rel), path.join(dest, rel), { recursive: true, verbatimSymlinks: true });
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const [base, script, dest] = process.argv.slice(2);
  stage(base, script, dest);
}
