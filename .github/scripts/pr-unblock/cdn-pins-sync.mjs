import { lstatSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

import { CDN_BUMP_PATHS, CDN_LOCK, CDN_MANIFEST, CDN_RECORD, CDN_SCRIPT, cdnPaths } from "../apply-patch/cdn-paths.mjs";
import { unifiedDiff } from "./install-script-pin.mjs";

const EXACT = /^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/;

function needsSync(manifestText, record) {
  let manifest;
  try {
    manifest = JSON.parse(manifestText);
  } catch {
    return false;
  }
  return Object.entries(record?.packages ?? {}).some(([name, pin]) => {
    const version = manifest?.dependencies?.[name];
    return typeof version === "string" && EXACT.test(version) && version !== pin?.version;
  });
}

export async function cdnRequest({ files, changedFiles, baseDir, readText }) {
  if (!baseDir || !files.length || files.length !== changedFiles ||
      files.some(({ filename, previous_filename }) => !CDN_BUMP_PATHS.has(filename) || previous_filename)) {
    return null;
  }
  let base;
  let script;
  try {
    base = JSON.parse(readFileSync(join(baseDir, CDN_RECORD), "utf8"));
    script = readFileSync(join(baseDir, CDN_SCRIPT), "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
  const record = await readText(CDN_RECORD);
  const head = JSON.parse(record);
  if (!head || !isDeepStrictEqual(head.targets, base.targets)) return null;
  const paths = cdnPaths(base);
  const texts = await Promise.all([CDN_MANIFEST, CDN_LOCK, ...paths.slice(1)].map(readText));
  if (texts.some((text) => text === null)) return null;
  const [manifest, lock, ...targets] = texts;
  if (!needsSync(manifest, head)) return null;
  return { script, manifest, lock, files: Object.fromEntries(paths.map((path, i) => [path, i === 0 ? record : targets[i - 1]])) };
}

export function cdnPatch(request, resultDir) {
  return cdnPaths(JSON.parse(request.files[CDN_RECORD])).map((path) => {
    const result = join(resultDir, path);
    const stat = lstatSync(result, { throwIfNoEntry: false });
    if (!stat) return "";
    if (!stat.isFile()) throw new Error(`${path} is not a regular sync result`);
    const before = request.files[path];
    const after = readFileSync(result, "utf8");
    return before === after ? "" : unifiedDiff(path, before, after);
  }).join("");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [mode, requestPath, resultDir, patchPath] = process.argv.slice(2);
  if (mode !== "patch" || !patchPath) throw new Error("usage: cdn-pins-sync.mjs patch <request.json> <result-dir> <patch.diff>");
  const patch = cdnPatch(JSON.parse(readFileSync(requestPath, "utf8")), resultDir);
  if (patch) writeFileSync(patchPath, patch);
  else process.exitCode = 1;
}
