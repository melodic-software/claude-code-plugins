#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

/** The file marker the loader requires (data/json.ts, isValidExcalidrawData). */
export const FILE_TYPE = "excalidraw";

/** Element types this plugin draws; restore drops a type it has no case for. */
export const ELEMENT_TYPES = Object.freeze(["rectangle", "ellipse", "diamond", "arrow", "line", "text", "frame"]);

const LINEAR = new Set(["arrow", "line"]);
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const finite = (value) => typeof value === "number" && Number.isFinite(value);
const isPoint = (point) => Array.isArray(point) && point.length === 2 && point.every(finite);

function elementProblems(element, at, ids) {
  if (!isObject(element)) return [`${at} is not an object`];
  const problems = [];
  const name = typeof element.id === "string" && element.id !== "" ? `${at} (${element.id})` : at;
  if (name === at) problems.push(`${at} has no string id`);
  if (!ELEMENT_TYPES.includes(element.type)) problems.push(`${name} has type ${JSON.stringify(element.type)}, outside ${ELEMENT_TYPES.join(", ")}`);
  for (const key of ["x", "y"]) if (!finite(element[key])) problems.push(`${name} has no finite ${key}`);
  if (element.link != null) problems.push(`${name} carries a link`);
  if (element.isDeleted === true) problems.push(`${name} is marked deleted`);
  if (LINEAR.has(element.type)) {
    if (!Array.isArray(element.points) || element.points.length < 2 || !element.points.every(isPoint)) {
      problems.push(`${name} needs at least two [x, y] points`);
    }
  } else if (!(finite(element.width) && finite(element.height) && (element.width !== 0 || element.height !== 0))) {
    problems.push(`${name} needs a finite width and height, not both zero`);
  }
  if (element.type === "text") {
    if (typeof element.text !== "string" || element.text === "") problems.push(`${name} has no text`);
    if (!(finite(element.fontSize) && element.fontSize > 0)) problems.push(`${name} needs a positive fontSize`);
    if (element.lineHeight != null && !(finite(element.lineHeight) && element.lineHeight > 0)) problems.push(`${name} has a lineHeight that is not a positive number`);
  }
  if (element.type === "frame" && element.name != null && typeof element.name !== "string") problems.push(`${name} has a name that is not a string`);
  const refs = [
    ["frameId", element.frameId],
    ["containerId", element.containerId],
    ["startBinding", element.startBinding?.elementId],
    ["endBinding", element.endBinding?.elementId],
  ];
  for (const [field, target] of refs) {
    if (target != null && !ids.has(target)) problems.push(`${name} ${field} names ${JSON.stringify(target)}, which no element has`);
  }
  return problems;
}

/** The problems that keep `text` from being a diagram file the skill may write; [] when it passes. */
export function checkExcalidraw(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch (error) {
    return { ok: false, elements: 0, problems: [`not JSON (${error.message})`] };
  }
  if (!isObject(data)) return { ok: false, elements: 0, problems: ["the top level is not an object"] };
  const problems = [];
  if (data.type !== FILE_TYPE) problems.push(`type is ${JSON.stringify(data.type)}, not "${FILE_TYPE}"`);
  if (!finite(data.version)) problems.push("version is not a number");
  if (data.appState !== undefined && !isObject(data.appState)) problems.push("appState is not an object");
  if (data.files !== undefined && !(isObject(data.files) && Object.keys(data.files).length === 0)) problems.push("files is not empty");
  if (!Array.isArray(data.elements)) {
    problems.push("elements is not an array");
    return { ok: false, elements: 0, problems };
  }
  if (data.elements.length === 0) problems.push("elements is empty");
  const ids = new Set();
  for (const [i, element] of data.elements.entries()) {
    const id = element?.id;
    if (typeof id !== "string") continue;
    if (ids.has(id)) problems.push(`elements[${i}] repeats the id ${JSON.stringify(id)}`);
    ids.add(id);
  }
  data.elements.forEach((element, i) => problems.push(...elementProblems(element, `elements[${i}]`, ids)));
  return { ok: problems.length === 0, elements: data.elements.length, problems };
}

function main(argv) {
  if (argv.length !== 1 || argv[0].startsWith("--") || !argv[0].endsWith(".excalidraw")) {
    process.stderr.write("usage: diagram-file-check.mjs <file.excalidraw>\n");
    return 2;
  }
  const file = resolve(argv[0]);
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch (error) {
    process.stderr.write(`diagram-file-check: cannot read ${file}: ${error.message}\n`);
    return 2;
  }
  const result = checkExcalidraw(text);
  process.stdout.write(`${JSON.stringify({ file, ...result })}\n`);
  return result.ok ? 0 : 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
