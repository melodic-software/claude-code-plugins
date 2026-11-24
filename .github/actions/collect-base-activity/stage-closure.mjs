import { cpSync, existsSync, mkdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const JS_LOADS = /(?:^\s*(?:import|export)\b[^;]*?\bfrom\s*|^\s*import\s+|\bimport\(\s*|\bnew URL\(\s*)["'](\.\.?\/[^"']+)["']/gm;
const SH_LOADS = /(?:\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)|\$\{BASH_SOURCE\[0\]%\/\*\})\/([^"\s]+)/g;

export function loads(file) {
  const text = readFileSync(file, "utf8");
  const shell = /\.(sh|bash)$/.test(file) || /^#!.*\b(?:bash|sh)\b/.test(text);
  if (!shell && !/\.m?js$/.test(file) && !/^#!.*\bnode\b/.test(text)) return [];
  const code = text.replace(shell ? /^\s*#.*$/gm : /^\s*\/\/.*$/gm, "");
  return [...code.matchAll(shell ? SH_LOADS : JS_LOADS)].map((m) => path.resolve(path.dirname(file), m[1]));
}

export function stage(base, script, dest) {
  const root = path.resolve(base);
  const targets = new Set();
  const seen = new Set();
  const visit = (file) => {
    const rel = path.relative(root, file);
    if (seen.has(file) || !rel || rel.startsWith("..") || path.isAbsolute(rel) || !existsSync(file)) return;
    seen.add(file);
    if (statSync(file).isDirectory()) return targets.add(rel);
    targets.add(path.dirname(rel) === "." ? rel : path.dirname(rel));
    for (const next of loads(file)) visit(next);
  };
  visit(path.join(root, script));
  for (const rel of targets) {
    if ([...targets].some((dir) => rel.startsWith(`${dir}${path.sep}`))) continue;
    mkdirSync(path.dirname(path.join(dest, rel)), { recursive: true });
    cpSync(path.join(root, rel), path.join(dest, rel), { recursive: true, verbatimSymlinks: true });
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const [base, script, dest] = process.argv.slice(2);
  stage(base, script, dest);
}
