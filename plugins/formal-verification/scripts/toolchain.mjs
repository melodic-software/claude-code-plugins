#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const here = dirname(fileURLToPath(import.meta.url));
const USAGE = "usage: toolchain.mjs <check|resolve|install model-checker|install renderer> [--data-dir D] [--jar F] [--java F] [--runtime F] [--project-dir P]";

const unset = (v) => !v || v.startsWith("${");

export function settings(projectDir) {
  const r = spawnSync(process.execPath, [join(here, "settings.mjs"), "--project-dir", projectDir], {
    encoding: "utf8",
  });
  if (r.status !== 0) throw new Error(`settings.mjs failed: ${r.stderr.trim()}`);
  if (r.stderr.trim()) process.stderr.write(r.stderr);
  return JSON.parse(r.stdout);
}

export const jarPath = (dataDir, version) => join(dataDir, "toolchain", `tla2tools-${version}.jar`);
export const rendererDir = (dataDir, pkg, version) => join(dataDir, "renderer", `${pkg}-${version}`);

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

export function inspect({ dataDir, jar, java, runtime, settings: s }) {
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

  const installed = dataDir ? jarPath(dataDir, s.model_checker.version) : null;
  const theJar = jar ?? installed;
  if (!theJar) add("FAIL", "model-checker", "No jar: pass --data-dir or set the model_checker_jar option.");
  else if (!existsSync(theJar)) add("FAIL", "model-checker", `${theJar} is missing. Type /formal-verification:setup apply install-model-checker, or set the model_checker_jar option.`);
  else if (theJar === installed && sha256(theJar) !== s.model_checker.sha256) add("FAIL", "model-checker", `${theJar} does not match the pinned sha256. Type /formal-verification:setup apply install-model-checker to replace it.`);
  else add("PASS", "model-checker", theJar);

  const r = s.renderer;
  const pkg = dataDir ? join(rendererDir(dataDir, r.package, r.version), "node_modules", r.package, "package.json") : null;
  if (pkg && existsSync(pkg) && JSON.parse(readFileSync(pkg, "utf8")).version === r.version) add("PASS", "renderer", dirname(pkg));
  else add("INFO", "renderer", `${r.package} ${r.version} is not installed; it is needed only for an image of a chart. Type /formal-verification:setup apply install-renderer.`);

  return { rows, jar: theJar, java: j, runtime: runtime ?? null };
}

async function download(url, dest, matches, what) {
  const stage = mkdtempSync(join(dirname(dest), ".download-"));
  try {
    const tmp = join(stage, "file");
    const res = await fetch(url);
    if (!res.ok) throw new Error(`${what}: GET ${url} returned ${res.status}`);
    writeFileSync(tmp, Buffer.from(await res.arrayBuffer()));
    if (!matches(tmp)) throw new Error(`${what}: ${url} does not match the pinned checksum; nothing was kept`);
    renameSync(tmp, dest);
  } finally {
    rmSync(stage, { recursive: true, force: true });
  }
}

async function install(what, { dataDir, settings: s }) {
  if (!dataDir) throw new Error("install needs --data-dir");
  if (what === "model-checker") {
    const dest = jarPath(dataDir, s.model_checker.version);
    mkdirSync(dirname(dest), { recursive: true });
    if (existsSync(dest) && sha256(dest) === s.model_checker.sha256) return `${dest} (already present)`;
    await download(s.model_checker.url, dest, (f) => sha256(f) === s.model_checker.sha256, "model checker");
    return dest;
  }
  if (what === "renderer") {
    const r = s.renderer;
    const dir = rendererDir(dataDir, r.package, r.version);
    const target = join(dir, "node_modules", r.package);
    const manifest = join(target, "package.json");
    if (existsSync(manifest) && JSON.parse(readFileSync(manifest, "utf8")).version === r.version) return `${target} (already present)`;
    mkdirSync(dir, { recursive: true });
    const tarball = join(dir, `${r.package}-${r.version}.tgz`);
    await download(r.url, tarball, (f) => sri512(f) === r.integrity, "renderer");
    rmSync(target, { recursive: true, force: true });
    mkdirSync(target, { recursive: true });
    const x = spawnSync("tar", ["-xzf", tarball, "-C", target, "--strip-components=1"], { encoding: "utf8" });
    rmSync(tarball, { force: true });
    if (x.status !== 0) {
      rmSync(target, { recursive: true, force: true });
      throw new Error(`renderer: tar could not unpack ${r.url}: ${x.stderr.trim()}`);
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
  const { bounds } = opts.settings;
  console.log(JSON.stringify({ jar: found.jar, java: found.java, runtime: found.runtime, bounds }));
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
