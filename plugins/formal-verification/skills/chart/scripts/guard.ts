export const STANDARD_MODULES = [
  "Naturals",
  "Integers",
  "Reals",
  "Sequences",
  "FiniteSets",
  "Bags",
  "TLC",
  "TLCExt",
  "Json",
  "Randomization",
  "RealTime",
  "Toolbox",
];

export const GENERATED_MODULES = ["ChartBound", "ChartRun"];

export const GENERATED_NAMES = [
  ...GENERATED_MODULES,
  "ChartTLC",
  "ChartNaturals",
  "ChartBudget",
  "ChartBroken",
  "ChartMark",
];

export const MAX_LINE_CHARS = 500;

export const MAX_BUG_LINES = 200;

export function fence(text: string) {
  let longest = 0;
  for (const run of text.matchAll(/`+/g)) longest = Math.max(longest, run[0].length);
  const ticks = "`".repeat(Math.max(3, longest + 1));
  return [ticks, text, ticks].join("\n");
}

export { escapeText as escapeMarkdown } from "./ir.ts";

export const capLine = (text: string, max = MAX_LINE_CHARS) =>
  text.length <= max ? text : `${text.slice(0, max)}… (${text.length - max} more characters)`;

export function colonsBeforeHash(s: string) {
  const hits: number[] = [];
  let hash = false;
  for (let i = s.length - 1; i >= 0; i--) {
    const c = s[i];
    if (c === "#") hash = true;
    else if (/\s/u.test(c)) hash = false;
    else if (c === ":" && hash) hits.push(i);
  }
  return hits.reverse();
}

export function stripComments(tla: string) {
  let out = "";
  let depth = 0;
  const literal = /"(?:\\.|[^"\\\n])*"?/y;
  for (let i = 0; i < tla.length; i++) {
    if (!depth && tla[i] === '"') {
      literal.lastIndex = i;
      const text = literal.exec(tla)![0];
      out += text;
      i += text.length - 1;
    } else if (tla.startsWith("(*", i)) {
      depth++;
      i++;
    } else if (depth && tla.startsWith("*)", i)) {
      depth--;
      i++;
    } else if (!depth && tla.startsWith("\\*", i)) {
      const end = tla.indexOf("\n", i);
      if (end === -1) break;
      i = end - 1;
    } else if (!depth) out += tla[i];
    else if (tla[i] === "\n") out += "\n";
  }
  return out;
}

export function moduleName(tla: string) {
  return /^-{4,}\s*MODULE\s+(\w+)\s*-{4,}/m.exec(stripComments(tla))?.[1];
}

export function referencedModules(tla: string) {
  const text = stripComments(tla);
  const found = new Set<string>();
  for (const [, names] of text.matchAll(/\bEXTENDS\s+(\w+(?:\s*,\s*\w+)*)/g))
    for (const name of names.split(",")) found.add(name.trim());
  for (const [, name] of text.matchAll(/\bINSTANCE\s+(\w+)/g)) found.add(name);
  return [...found];
}

export const usesGeneratedName = (tla: string) =>
  GENERATED_NAMES.find((name) => new RegExp(`\\b${name}\\b`).test(stripComments(tla)));

export const shadowsStandard = (name: string) =>
  STANDARD_MODULES.includes(name) || GENERATED_MODULES.includes(name) || name.startsWith("_");
