#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolveSettings } from "./settings.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const USAGE = "usage: toolchain.mjs <check|resolve|install model-checker|install renderer> [--data-dir D] [--jar F] [--java F] [--runtime F] [--project-dir P]";

export const RELEASES = JSON.parse(readFileSync(join(here, "..", "releases.json"), "utf8"));
export const MAX_DOWNLOAD_BYTES = 100 * 1024 * 1024;
export const DOWNLOAD_TIMEOUT_MS = 300_000;

const VERSION = /^[0-9A-Za-z.+-]+$/;
const PACKAGE = /^(?:@[a-z0-9-~][a-z0-9-._~]*\/)?[a-z0-9-~][a-z0-9-._~]*$/;
const SOURCE_KEY = /\.(url|sha256|integrity)$/;

const unset = (v) => !v || v.startsWith("${");

export function settings(projectDir) {
  const { values, layers } = resolveSettings(projectDir);
  for (const layer of layers) {
    (layer.error_keys ?? []).forEach((key, i) => {
      if (key && SOURCE_KEY.test(key))
        throw new Error(
          `${layer.path ?? layer.name} sets ${key}. Download sources and checksums come only from the plugin's releases.json, never from the repository.`,
        );
      process.stderr.write(`settings: ${layer.errors[i]}\n`);
    });
  }
  return values;
}

export function release(kind, s, releases = RELEASES) {
  const version = kind === "renderer" ? s.renderer.version : s.model_checker.version;
  if (!VERSION.test(version)) throw new Error(`${kind} version ${JSON.stringify(version)} is not a version.`);
  if (kind === "renderer" && !PACKAGE.test(s.renderer.package))
    throw new Error(`renderer package ${JSON.stringify(s.renderer.package)} is not an npm package name.`);
  const key = kind === "renderer" ? `${s.renderer.package}@${version}` : version;
  const table = releases[kind === "renderer" ? "renderer" : "model_checker"] ?? {};
  const entry = Object.hasOwn(table, key) ? table[key] : undefined;
  if (!entry)
    throw new Error(
      `No pinned checksum for ${kind} ${key}. The plugin's releases.json pins: ${Object.keys(table).join(", ") || "none"}.`,
    );
  return entry;
}

export function within(base, target) {
  const rel = relative(resolve(base), resolve(target));
  if (rel === "" || rel.startsWith("..") || isAbsolute(rel))
    throw new Error(`${target} is outside ${base}; nothing was written.`);
  return target;
}

export const jarPath = (dataDir, version) => within(dataDir, join(dataDir, "toolchain", `tla2tools-${version}.jar`));
export const rendererDir = (dataDir, pkg, version) => within(dataDir, join(dataDir, "renderer", `${pkg}-${version}`));

const sha256 = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");
const sri512 = (file) => `sha512-${createHash("sha512").update(readFileSync(file)).digest("base64")}`;

export function javaMajor(text) {
  const m = /version "(\d+)(?:\.(\d+))?/.exec(text);
  if (!m) return null;
  return m[1] === "1" && m[2] ? Number(m[2]) : Number(m[1]);
}

function probeJava(java) {
  const r = spawnSync(java, ["-version"], { encoding: "utf8" });
  if (r.error) return { found: false, detail: `${java} was not found` };
  return { found: true, major: javaMajor(`${r.stdout}${r.stderr}`) };
}

function probeRuntime(runtime) {
  const r = spawnSync(runtime, ["--version"], { encoding: "utf8" });
  if (r.error || r.status !== 0) return { found: false, detail: `${runtime} --version did not run` };
  return { found: true, detail: `${runtime} ${r.stdout.trim().split("\n")[0]}` };
}

export function inspect({ dataDir, jar, java, runtime, settings: s, releases = RELEASES }) {
  const rows = [];
  const add = (status, id, detail) => rows.push({ status, id, detail });

  const run = runtime ?? "node";
  const rt = probeRuntime(run);
  add(rt.found ? "PASS" : "FAIL", "script-runtime", rt.found ? rt.detail : `${rt.detail}. Install Node, Bun or Deno, or set the script_runtime option.`);

  const j = java ?? "java";
  const pj = probeJava(j);
  const min = Number(s.java.min_version);
  if (!pj.found) add("FAIL", "java", `${pj.detail}. Install Java ${min} or later (for example ${s.java.distribution}), or set the java option. The plugin never installs Java.`);
  else if (pj.major === null) add("INFO", "java", `${j}: could not read its version; Java ${min} or later is needed.`);
  else if (pj.major < min) add("FAIL", "java", `${j} is Java ${pj.major}; Java ${min} or later is needed.`);
  else add("PASS", "java", `${j} (Java ${pj.major})`);

  let installed = null;
  let pin = null;
  let unpinned = null;
  try {
    pin = release("model-checker", s, releases);
    installed = dataDir ? jarPath(dataDir, s.model_checker.version) : null;
  } catch (error) {
    unpinned = error.message;
  }
  const theJar = jar ?? installed;
  if (!jar && unpinned) add("FAIL", "model-checker", unpinned);
  else if (!theJar) add("FAIL", "model-checker", "No jar: pass --data-dir or set the model_checker_jar option.");
  else if (!existsSync(theJar)) add("FAIL", "model-checker", `${theJar} is missing. Type /formal-verification:setup apply install-model-checker, or set the model_checker_jar option.`);
  else if (theJar === installed && sha256(theJar) !== pin.sha256) add("FAIL", "model-checker", `${theJar} does not match the pinned sha256. Type /formal-verification:setup apply install-model-checker to replace it.`);
  else add("PASS", "model-checker", theJar);

  const r = s.renderer;
  let pkg = null;
  try {
    release("renderer", s, releases);
    pkg = dataDir ? join(rendererDir(dataDir, r.package, r.version), "node_modules", r.package, "package.json") : null;
  } catch (error) {
    add("INFO", "renderer", error.message);
  }
  if (!rows.some((row) => row.id === "renderer")) {
    if (pkg && existsSync(pkg) && JSON.parse(readFileSync(pkg, "utf8")).version === r.version) add("PASS", "renderer", dirname(pkg));
    else add("INFO", "renderer", `${r.package} ${r.version} is not installed; it is needed only for an image of a chart. Type /formal-verification:setup apply install-renderer.`);
  }

  return { rows, jar: theJar, java: j, runtime: runtime ?? null };
}

export async function download(url, dest, matches, what, { fetchImpl = fetch, maxBytes = MAX_DOWNLOAD_BYTES, timeoutMs = DOWNLOAD_TIMEOUT_MS } = {}) {
  if (!url.startsWith("https:")) throw new Error(`${what}: ${url} is not an https URL; nothing was downloaded.`);
  const stage = mkdtempSync(join(dirname(dest), ".download-"));
  try {
    const tmp = join(stage, "file");
    const res = await fetchImpl(url, { signal: AbortSignal.timeout(timeoutMs) });
    if (!res.ok) throw new Error(`${what}: GET ${url} returned ${res.status}`);
    if (Number(res.headers.get("content-length") ?? 0) > maxBytes)
      throw new Error(`${what}: ${url} is larger than ${maxBytes} bytes; nothing was kept`);
    const parts = [];
    let size = 0;
    for await (const chunk of res.body) {
      size += chunk.length;
      if (size > maxBytes) throw new Error(`${what}: ${url} is larger than ${maxBytes} bytes; nothing was kept`);
      parts.push(chunk);
    }
    writeFileSync(tmp, Buffer.concat(parts));
    if (!matches(tmp)) throw new Error(`${what}: ${url} does not match the pinned checksum; nothing was kept`);
    renameSync(tmp, dest);
  } finally {
    rmSync(stage, { recursive: true, force: true });
  }
}

export async function install(what, { dataDir, settings: s, releases = RELEASES, fetchImpl }) {
  if (!dataDir) throw new Error("install needs --data-dir");
  if (what === "model-checker") {
    const pin = release("model-checker", s, releases);
    const dest = jarPath(dataDir, s.model_checker.version);
    mkdirSync(dirname(dest), { recursive: true });
    if (existsSync(dest) && sha256(dest) === pin.sha256) return `${dest} (already present)`;
    await download(pin.url, dest, (f) => sha256(f) === pin.sha256, "model checker", { fetchImpl });
    return dest;
  }
  if (what === "renderer") {
    const r = s.renderer;
    const pin = release("renderer", s, releases);
    const dir = rendererDir(dataDir, r.package, r.version);
    const target = within(dataDir, join(dir, "node_modules", r.package));
    const manifest = join(target, "package.json");
    if (existsSync(manifest) && JSON.parse(readFileSync(manifest, "utf8")).version === r.version) return `${target} (already present)`;
    mkdirSync(dir, { recursive: true });
    const tarball = within(dataDir, join(dir, `${r.version}.tgz`));
    await download(pin.url, tarball, (f) => sri512(f) === pin.integrity, "renderer", { fetchImpl });
    rmSync(target, { recursive: true, force: true });
    mkdirSync(target, { recursive: true });
    const x = spawnSync("tar", ["-xzf", tarball, "-C", target, "--strip-components=1", "--no-same-owner"], { encoding: "utf8" });
    rmSync(tarball, { force: true });
    if (x.status !== 0) {
      rmSync(target, { recursive: true, force: true });
      throw new Error(`renderer: tar could not unpack ${pin.url}: ${x.stderr.trim()}`);
    }
    return target;
  }
  throw new Error(`install takes model-checker or renderer, not ${what}`);
}

async function main(argv) {
  const { values: o, positionals } = parseArgs({
    args: argv,
    allowPositionals: true,
    options: {
      "data-dir": { type: "string" },
      jar: { type: "string" },
      java: { type: "string" },
      runtime: { type: "string" },
      "project-dir": { type: "string" },
    },
  });
  const [mode, what] = positionals;
  const opts = {
    dataDir: unset(o["data-dir"]) ? null : o["data-dir"],
    jar: unset(o.jar) ? null : o.jar,
    java: unset(o.java) ? null : o.java,
    runtime: unset(o.runtime) ? null : o.runtime,
    settings: settings(o["project-dir"] ?? process.cwd()),
  };
  if (mode === "install") {
    console.log(await install(what, opts));
    return 0;
  }
  if (mode !== "check" && mode !== "resolve") throw new Error(USAGE);
  const found = inspect(opts);
  if (mode === "check") {
    for (const { status, id, detail } of found.rows) console.log(`${status}\t${id}\t${detail}`);
    const failed = found.rows.filter((r) => r.status === "FAIL").length;
    console.log(failed ? `${failed} prerequisite(s) missing` : "toolchain ready");
    return failed ? 1 : 0;
  }
  const missing = found.rows.filter((r) => r.status === "FAIL").map((r) => r.id);
  if (missing.length) {
    console.error(`blocked: toolchain missing: ${missing.join(", ")}`);
    return 3;
  }
  const { bounds, allowed_modules } = opts.settings;
  console.log(JSON.stringify({ jar: found.jar, java: found.java, runtime: found.runtime, bounds, allowed_modules }));
  return 0;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (error) => {
      console.error(error.message);
      process.exit(error.message === USAGE || error.code === "ERR_PARSE_ARGS_UNKNOWN_OPTION" ? 2 : 1);
    },
  );
}
