#!/usr/bin/env node
// GENERATED from lib/prerequisites.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  accessSync,
  constants,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export const KINDS = ["cli", "runtime", "system-lib", "python-pkg", "node-pkg", "env", "mcp"];
export const NEEDS = ["required", "optional"];
const ENTRY_KEYS = ["id", "kind", "need", "for", "detect", "degrade", "install", "check", "when"];
const OPTIONAL_KEYS = ["check", "when"];
const DETECT_KEYS = {
  cli: { required: ["any"], optional: ["local_bin", "version", "reject_store_alias"] },
  runtime: { required: ["any"], optional: ["local_bin", "version", "reject_store_alias"] },
  "system-lib": { required: ["probe"], optional: [] },
  "python-pkg": { required: ["any", "import"], optional: [] },
  "node-pkg": { required: ["module", "paths"], optional: [] },
  env: { required: ["name"], optional: [] },
  mcp: { required: ["server"], optional: [] },
};
const ID_RE = /^[a-z0-9][a-z0-9._+-]*$/;
const FOR_RE = /^(plugin|(skill|hook|mcp):[A-Za-z0-9._/-]+)$/;
const CHECK_RE = /^\/[a-z0-9-]+:[a-z0-9-]+( [^\n]+)?$/;
const MIN_RE = /^\d+(\.\d+)*$/;
const LATEST_RE = /^(npm:(@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*|github:[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*)$/;
const MODULE_RE = /^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$/;
const NPM_RE = /^(@[a-z0-9._-]+\/)?[a-z0-9._-]+$/;
const ENV_RE = /^[A-Za-z_]\w*$/;
const OPTION_RE = /^[A-Z0-9_]+$/;
const SERVER_RE = /^[A-Za-z0-9._-]+$/;
const MANAGER_RE = /^[a-z][a-z0-9-]*$/;
const PROBE_TIMEOUT_MS = 20000;
const HERE = path.dirname(fileURLToPath(import.meta.url));
const LOCAL_BIN_DEPTH = 8;

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const isText = (v) => typeof v === "string" && v.trim() !== "";
const isTextList = (v) => Array.isArray(v) && v.length > 0 && v.every(isText);
const matches = (v, re) => typeof v === "string" && re.test(v);

function keysErrors(obj, allowed, where) {
  return Object.keys(obj)
    .filter((k) => !allowed.includes(k))
    .map((k) => `${where}: unknown key "${k}"`);
}

function patternErrors(pattern, where, needsGroup) {
  if (!isText(pattern)) return [`${where}.pattern must be a non-empty string`];
  try {
    const groups = new RegExp(`${pattern}|`).exec("").length - 1;
    if (needsGroup && groups < 1) return [`${where}.pattern needs a capture group for the version`];
  } catch (err) {
    return [`${where}.pattern is not a valid regular expression: ${err.message}`];
  }
  return [];
}

function relativePathErrors(list, where) {
  if (!isTextList(list)) return [`${where} must be a non-empty list of paths`];
  return list
    .filter((p) => path.isAbsolute(p) || p.split(/[\\/]/).includes(".."))
    .map((p) => `${where}: "${p}" must be relative and stay inside its base`);
}

function detectErrors(kind, detect, where) {
  if (!isObject(detect)) return [`${where} must be an object`];
  const shape = DETECT_KEYS[kind];
  const errors = keysErrors(detect, [...shape.required, ...shape.optional], where);
  for (const key of shape.required) {
    if (!(key in detect)) errors.push(`${where}.${key} is required for kind ${kind}`);
  }
  if ("any" in detect && !isTextList(detect.any)) errors.push(`${where}.any must be a non-empty list of names`);
  if ("local_bin" in detect) errors.push(...relativePathErrors(detect.local_bin, `${where}.local_bin`));
  if ("reject_store_alias" in detect && typeof detect.reject_store_alias !== "boolean") {
    errors.push(`${where}.reject_store_alias must be true or false`);
  }
  if ("version" in detect) {
    const v = detect.version;
    const vw = `${where}.version`;
    if (!isObject(v)) {
      errors.push(`${vw} must be an object`);
    } else {
      errors.push(...keysErrors(v, ["args", "pattern", "min", "below", "latest"], vw));
      if ("latest" in v && !matches(v.latest, LATEST_RE)) {
        errors.push(`${vw}.latest must be npm:<package> or github:<owner>/<repo>`);
      }
      if (!Array.isArray(v.args) || !v.args.every((a) => typeof a === "string")) {
        errors.push(`${vw}.args must be a list of strings`);
      }
      errors.push(...patternErrors(v.pattern, vw, true));
      if (!matches(v.min, MIN_RE)) errors.push(`${vw}.min must be a dotted number such as 2.94.0`);
      if ("below" in v) {
        if (!matches(v.below, MIN_RE)) {
          errors.push(`${vw}.below must be a dotted number such as 3.0.0`);
        } else if (matches(v.min, MIN_RE) && compareVersions(v.below, v.min) <= 0) {
          errors.push(`${vw}.below must be greater than ${vw}.min`);
        }
      }
    }
  }
  if ("probe" in detect) {
    const p = detect.probe;
    const pw = `${where}.probe`;
    if (!isObject(p)) {
      errors.push(`${pw} must be an object`);
    } else {
      errors.push(...keysErrors(p, ["args", "pattern"], pw));
      if (!isTextList(p.args)) errors.push(`${pw}.args must be a non-empty list; the first item is the binary`);
      errors.push(...patternErrors(p.pattern, pw, false));
    }
  }
  if ("import" in detect && !matches(detect.import, MODULE_RE)) errors.push(`${where}.import must be a Python module name`);
  if ("module" in detect && !matches(detect.module, NPM_RE)) errors.push(`${where}.module must be an npm package name`);
  if ("paths" in detect) {
    const strip = (p) => (typeof p === "string" ? p.replace(/^\$\{CLAUDE_PLUGIN_(DATA|ROOT)\}\/?/, "") || "." : p);
    errors.push(
      ...relativePathErrors(Array.isArray(detect.paths) ? detect.paths.map(strip) : detect.paths, `${where}.paths`),
    );
  }
  if ("name" in detect && !matches(detect.name, ENV_RE)) errors.push(`${where}.name must be an environment variable name`);
  if ("server" in detect && !matches(detect.server, SERVER_RE)) errors.push(`${where}.server must be an MCP server name`);
  return errors;
}

function entryErrors(entry, where) {
  if (!isObject(entry)) return [`${where} must be an object`];
  const errors = keysErrors(entry, ENTRY_KEYS, where);
  for (const key of ENTRY_KEYS) {
    if (!(key in entry) && !OPTIONAL_KEYS.includes(key)) errors.push(`${where}.${key} is required`);
  }
  if ("id" in entry && !matches(entry.id, ID_RE)) errors.push(`${where}.id must match ${ID_RE.source}`);
  if ("kind" in entry && !KINDS.includes(entry.kind)) errors.push(`${where}.kind must be one of ${KINDS.join(", ")}`);
  if ("need" in entry && !NEEDS.includes(entry.need)) errors.push(`${where}.need must be one of ${NEEDS.join(", ")}`);
  if ("for" in entry) {
    const scopes = entry.for;
    if (!Array.isArray(scopes) || scopes.length === 0) {
      errors.push(`${where}.for must be a non-empty list`);
    } else {
      for (const s of scopes) {
        if (!matches(s, FOR_RE)) {
          errors.push(`${where}.for: "${s}" must be plugin, skill:<name>, hook:<script> or mcp:<server>`);
        }
      }
      if (new Set(scopes).size !== scopes.length) errors.push(`${where}.for repeats a scope`);
    }
  }
  if ("detect" in entry && KINDS.includes(entry.kind))
    errors.push(...detectErrors(entry.kind, entry.detect, `${where}.detect`));
  if ("degrade" in entry && !isText(entry.degrade)) errors.push(`${where}.degrade must say what stops working`);
  if ("install" in entry) {
    const inst = entry.install;
    if (!isObject(inst) || Object.keys(inst).length === 0) {
      errors.push(`${where}.install must be an object with at least one hint`);
    } else {
      for (const [k, v] of Object.entries(inst)) {
        if (!MANAGER_RE.test(k)) errors.push(`${where}.install: "${k}" is not a package-manager key`);
        if (!isText(v)) errors.push(`${where}.install.${k} must be a non-empty string`);
      }
    }
  }
  if ("check" in entry && !matches(entry.check, CHECK_RE)) errors.push(`${where}.check must name a skill, such as /<plugin>:check`);
  if ("when" in entry) errors.push(...whenErrors(entry.when, `${where}.when`));
  return errors;
}

const NAME = "[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*";
const SEGMENT = "[A-Za-z0-9._*?-]*[A-Za-z0-9_*?-][A-Za-z0-9._*?-]*";
const CONFIG_RE = new RegExp(`^(${NAME}|${SEGMENT}(/${SEGMENT})+)$`);
const GIT_TIMEOUT_MS = 2000;

function whenErrors(when, where) {
  if (!isObject(when)) return [`${where} must be an object`];
  const errors = keysErrors(when, ["config_any"], where);
  const list = when.config_any;
  if (!Array.isArray(list) || list.length === 0) return [...errors, `${where}.config_any must be a non-empty list`];
  for (const item of list) {
    const file = typeof item === "string" ? item : isObject(item) ? item.file : undefined;
    if (!matches(file, CONFIG_RE)) {
      errors.push(
        `${where}.config_any: each item is a file name or a path from the repository root (no "..", no wildcard in a bare name), or { file, pattern }`,
      );
    }
    if (isObject(item)) {
      errors.push(...keysErrors(item, ["file", "pattern"], `${where}.config_any`));
      if (!isText(item.pattern)) errors.push(`${where}.config_any: { file, pattern } needs a pattern`);
      else if (patternErrors(item.pattern, `${where}.config_any pattern`, false).length) {
        errors.push(`${where}.config_any: ${item.file}'s pattern is not a valid regular expression`);
      }
    }
  }
  return errors;
}

const configOf = (item) => (typeof item === "string" ? { file: item } : item);
const repoGlob = (file) => (file.includes("/") ? file : `**/${file}`);

function globRegExp(glob) {
  let re = "";
  for (let i = 0; i < glob.length; i++) {
    const wholeSegment = glob.startsWith("**", i) && (i === 0 || glob[i - 1] === "/");
    if (wholeSegment && i + 2 === glob.length) {
      re += ".*";
      i++;
    } else if (wholeSegment && glob[i + 2] === "/") {
      re += "(?:.*/)?";
      i += 2;
    } else {
      re += glob[i] === "*" ? "[^/]*" : glob[i] === "?" ? "[^/]" : glob[i].replace(".", "\\.");
    }
  }
  return new RegExp(`^${re}$`);
}

function configMatches(file, config) {
  if (!existsSync(file)) return false;
  if (!config.pattern) return true;
  try {
    return new RegExp(config.pattern, "m").test(readFileSync(file, "utf8"));
  } catch {
    return false;
  }
}

function trackedConfigs(configs, top, ctx) {
  const git = which("git", ctx.env, ctx.platform, ctx.fs);
  if (!git) return null;
  const specs = [...new Set(configs.map((c) => `:(top,glob)${repoGlob(c.file)}`))];
  const r = spawnSync(path.resolve(git), ["-C", top, "ls-files", "-z", "--", ...specs], {
    cwd: HERE,
    encoding: "utf8",
    env: ctx.env,
    timeout: GIT_TIMEOUT_MS,
    stdio: ["ignore", "pipe", "ignore"],
  });
  return r.error || r.status !== 0 ? null : r.stdout.split("\0").filter(Boolean);
}

function whenChecker(entries, ctx) {
  const start = path.resolve(ctx.env.CLAUDE_PROJECT_DIR || ctx.cwd);
  const dirs = [];
  for (let dir = start; ; dir = path.dirname(dir)) {
    dirs.push(dir);
    if (path.dirname(dir) === dir) break;
  }
  const top = dirs.find((dir) => existsSync(path.join(dir, ".git")));
  const all = entries.filter((e) => e.when).flatMap((e) => e.when.config_any.map(configOf));
  let tracked;
  return (entry) => {
    if (!entry.when) return true;
    const configs = entry.when.config_any.map(configOf);
    const literal = configs.filter((c) => !/[*?/]/.test(c.file));
    if (dirs.some((dir) => literal.some((c) => configMatches(path.join(dir, c.file), c)))) return true;
    if (!top) return false;
    if (tracked === undefined) tracked = trackedConfigs(all, top, ctx);
    if (tracked === null) return true;
    return configs.some((c) => {
      const re = globRegExp(repoGlob(c.file));
      return tracked.some((f) => re.test(f) && configMatches(path.join(top, f), c));
    });
  };
}

const whenText = (entry) =>
  entry.when.config_any.map((i) => (typeof i === "string" ? i : `${i.file} matching /${i.pattern}/`)).join(" or ");

export function validateManifest(manifest) {
  if (!isObject(manifest)) return ["the manifest must be a JSON object"];
  const errors = keysErrors(manifest, ["$schema", "session_probe", "requires"], "manifest");
  if ("$schema" in manifest && typeof manifest.$schema !== "string") errors.push("manifest.$schema must be a string");
  if ("session_probe" in manifest) {
    const sp = manifest.session_probe;
    if (!isObject(sp)) {
      errors.push("manifest.session_probe must be an object");
    } else {
      errors.push(...keysErrors(sp, ["run_if_unset_or_true"], "session_probe"));
      if ("run_if_unset_or_true" in sp && !matches(sp.run_if_unset_or_true, OPTION_RE)) {
        errors.push("session_probe.run_if_unset_or_true must be an option name in capitals, such as EXAMPLE_ENABLED");
      }
    }
  }
  if (!Array.isArray(manifest.requires) || manifest.requires.length === 0) {
    errors.push("manifest.requires must be a non-empty list");
    return errors;
  }
  const seen = new Set();
  manifest.requires.forEach((entry, i) => {
    errors.push(...entryErrors(entry, `requires[${i}]`));
    if (isObject(entry) && typeof entry.id === "string") {
      if (seen.has(entry.id)) errors.push(`requires[${i}].id "${entry.id}" is declared twice`);
      seen.add(entry.id);
    }
  });
  return errors;
}

function pluginName(root) {
  try {
    const name = JSON.parse(readFileSync(path.join(root, ".claude-plugin", "plugin.json"), "utf8")).name;
    if (isText(name)) return name;
  } catch {
  }
  return path.basename(path.resolve(root));
}

export function loadManifest(root) {
  const plugin = pluginName(root);
  const file = path.join(root, "prerequisites.json");
  if (!existsSync(file)) return { plugin, manifest: null, errors: [], absent: true };
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(file, "utf8"));
  } catch (err) {
    return { plugin, manifest: null, errors: [`prerequisites.json is not valid JSON: ${err.message}`], absent: false };
  }
  return { plugin, manifest, errors: validateManifest(manifest), absent: false };
}

export function compareVersions(a, b) {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return Math.sign(d);
  }
  return 0;
}

const FS = { statSync, lstatSync, readlinkSync, accessSync };

const PYTHON_STUB_TARGET = "appinstallerpythonredirector.exe";
const PYTHON_STUB_NAMES = new Set(["python", "python3"]);

const isWindowsApps = (dir) => path.basename(dir).toLowerCase() === "windowsapps";

function isAppAlias(file, fs) {
  if (!isWindowsApps(path.dirname(file))) return false;
  try {
    if (!fs.lstatSync(file).isSymbolicLink()) return false;
  } catch {
    return false;
  }
  let target;
  try {
    target = fs.readlinkSync(file);
  } catch {
    return !PYTHON_STUB_NAMES.has(path.basename(file).toLowerCase().replace(/\.exe$/, ""));
  }
  return path.win32.basename(target).toLowerCase() !== PYTHON_STUB_TARGET;
}

function isExecutable(file, platform, fs = FS) {
  try {
    if (!fs.statSync(file).isFile()) return false;
    if (platform !== "win32") fs.accessSync(file, constants.X_OK);
    return true;
  } catch {
    return platform === "win32" && isAppAlias(file, fs);
  }
}

export function which(name, env = process.env, platform = process.platform, fs = FS, rejectStoreAlias = false, runnable = false) {
  const pathVar = env.PATH ?? env.Path ?? "";
  const pathExts = (env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD").split(";").filter(Boolean);
  const exts = platform !== "win32" ? [""] : runnable ? pathExts : ["", ...pathExts];
  for (const dir of pathVar.split(path.delimiter)) {
    if (!dir || (rejectStoreAlias && platform === "win32" && isWindowsApps(dir))) continue;
    for (const ext of exts) {
      const candidate = path.join(dir, name + ext);
      if (isExecutable(candidate, platform, fs)) return candidate;
    }
  }
  return null;
}

function findLocalBin(rels, cwd, platform, fs) {
  for (const rel of rels ?? []) {
    let dir = path.resolve(cwd);
    for (let i = 0; i < LOCAL_BIN_DEPTH; i++) {
      const candidate = path.join(dir, rel);
      if (isExecutable(candidate, platform, fs)) return candidate;
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  }
  return null;
}

function run(file, args, env) {
  const viaCmd = process.platform === "win32" && /\.(bat|cmd)$/i.test(file);
  const line = [path.resolve(file), ...args].map((a) => `"${a}"`).join(" ");
  const [command, argv] = viaCmd ? [env?.ComSpec ?? process.env.ComSpec ?? "cmd.exe", ["/d", "/s", "/c", `"${line}"`]] : [path.resolve(file), args];
  const r = spawnSync(command, argv, {
    windowsVerbatimArguments: viaCmd,
    cwd: HERE,
    encoding: "utf8",
    timeout: PROBE_TIMEOUT_MS,
    stdio: ["ignore", "pipe", "pipe"],
    ...(env && { env }),
  });
  return { ok: !r.error && r.status === 0, out: `${r.stdout ?? ""}${r.stderr ?? ""}`, stdout: r.stdout ?? "" };
}

function firstOnPath(names, ctx, rejectStoreAlias = false, runnable = false) {
  for (const name of names) {
    const found = which(name, ctx.env, ctx.platform, ctx.fs, rejectStoreAlias, runnable);
    if (found) return found;
  }
  return null;
}

// Hooks receive CLAUDE_PLUGIN_DATA and Bash-tool commands do not, so a skill passes --data-dir:
// https://code.claude.com/docs/en/plugins-reference#where-each-variable-resolves
function ownDataDir(ctx) {
  const flag = ctx.dataDir;
  if (flag && !flag.startsWith("${")) return flag;
  const env = ctx.env.CLAUDE_PLUGIN_DATA;
  if (!env || env.startsWith("${")) return null;
  const plugin = pluginName(ctx.root);
  const last = path.basename(env);
  return last === plugin || last.startsWith(`${plugin}-`) ? env : null;
}

function expandPluginPath(p, ctx) {
  if (p.startsWith("${CLAUDE_PLUGIN_DATA}")) {
    const data = ownDataDir(ctx);
    if (!data) return null;
    return path.join(data, p.slice("${CLAUDE_PLUGIN_DATA}".length));
  }
  return path.join(ctx.root, p.replace(/^\$\{CLAUDE_PLUGIN_ROOT\}/, ""));
}

function pluginPythonSet(python, ctx) {
  const lock = path.join(ctx.root, "requirements.txt");
  if (!existsSync(lock)) return null;
  const data = expandPluginPath("${CLAUDE_PLUGIN_DATA}", ctx);
  if (!data) return { dir: null };
  const tag = run(python, ["-c", "import sys; print(sys.implementation.cache_tag)"], ctx.env);
  const cacheTag = tag.ok ? tag.stdout.trim() : "";
  if (!/^[A-Za-z0-9._-]+$/.test(cacheTag)) return null;
  const key = createHash("sha256").update(readFileSync(lock)).digest("hex").slice(0, 12);
  return { dir: path.join(data, "python", `${key}-${cacheTag}`) };
}

export function detectEntry(entry, ctx) {
  const d = entry.detect;
  switch (entry.kind) {
    case "cli":
    case "runtime": {
      const found = firstOnPath(d.any, ctx, d.reject_store_alias) ?? findLocalBin(d.local_bin, ctx.cwd, ctx.platform, ctx.fs);
      if (!found) {
        const where = d.local_bin ? `on PATH or as ${d.local_bin.join(", ")}` : "on PATH";
        return { status: "missing", detail: `${d.any.join(" or ")} was not found ${where}` };
      }
      if (!d.version) return { status: "present", detail: found };
      const runnable = firstOnPath(d.any, ctx, d.reject_store_alias, true) ?? found;
      const match = new RegExp(d.version.pattern).exec(run(runnable, d.version.args).out);
      if (!match?.[1] || !MIN_RE.test(match[1])) {
        return { status: "unverified", detail: `${found}: could not read a version to compare with ${d.version.min}` };
      }
      if (compareVersions(match[1], d.version.min) < 0) {
        return { status: "outdated", detail: `${found} is ${match[1]}; ${d.version.min} or newer is needed` };
      }
      if (d.version.below !== undefined && compareVersions(match[1], d.version.below) >= 0) {
        return {
          status: "outdated",
          detail: `${found} is ${match[1]}; the supported range is >= ${d.version.min}, < ${d.version.below}`,
        };
      }
      return { status: "present", detail: `${found} ${match[1]}` };
    }
    case "system-lib": {
      const [bin, ...args] = d.probe.args;
      const found = which(bin, ctx.env, ctx.platform, ctx.fs);
      if (!found) return { status: "missing", detail: `${bin} was not found on PATH to probe` };
      if (new RegExp(d.probe.pattern).test(run(found, args).out)) return { status: "present", detail: found };
      return { status: "missing", detail: `${bin} ${args.join(" ")} did not report ${d.probe.pattern}` };
    }
    case "python-pkg": {
      const pythons = [...new Set(d.any.map((n) => which(n, ctx.env, ctx.platform, ctx.fs)).filter(Boolean))];
      const [found] = pythons;
      if (!found) return { status: "missing", detail: `no Python interpreter (${d.any.join(", ")}) on PATH` };
      const env = { ...ctx.env, PYTHONSAFEPATH: "1" };
      if (run(found, ["-c", `import ${d.import}`], env).ok)
        return { status: "present", detail: `${found} imports ${d.import}` };
      const setEnv = { ...env };
      delete setEnv.PYTHONHOME;
      const tried = [];
      for (const python of pythons) {
        const set = pluginPythonSet(python, ctx);
        if (!set) continue;
        if (set.dir === null) {
          return {
            status: "unverified",
            detail: `${found} cannot import ${d.import} on its own, and the plugin data directory is unknown here; pass --data-dir`,
          };
        }
        tried.push(set.dir);
        if (existsSync(set.dir) && run(python, ["-S", "-c", `import ${d.import}`], { ...setEnv, PYTHONPATH: set.dir }).ok)
          return { status: "present", detail: `${python} imports ${d.import} from ${set.dir}` };
      }
      const where = tried.length ? ` on its own or from ${tried.join(", ")}` : "";
      return { status: "missing", detail: `${found} cannot import ${d.import}${where}` };
    }
    case "node-pkg": {
      let unresolved = false;
      for (const p of d.paths) {
        const dir = expandPluginPath(p, ctx);
        unresolved ||= dir === null;
        if (dir && existsSync(path.join(dir, d.module, "package.json"))) {
          return { status: "present", detail: path.join(dir, d.module) };
        }
      }
      if (unresolved) {
        return {
          status: "unverified",
          detail: `${d.module}: the plugin data directory is unknown here; pass --data-dir`,
        };
      }
      return { status: "missing", detail: `${d.module} is not installed under ${d.paths.join(", ")}` };
    }
    case "env":
      return ctx.env[d.name]
        ? { status: "present", detail: `${d.name} is set` }
        : { status: "missing", detail: `${d.name} is not set` };
    case "mcp":
      return { status: "agent-check", detail: `only the agent can see whether MCP server ${d.server} is connected` };
    default:
      return { status: "missing", detail: `unknown kind ${entry.kind}` };
  }
}

const isFailure = (status) => status === "missing" || status === "outdated";

function installText(entry) {
  return Object.entries(entry.install)
    .map(([k, v]) => `${k}: ${v}`)
    .join("; ");
}

function remediation(entry) {
  return `${entry.degrade} Install (${installText(entry)}). Then run ${entry.check ?? "this check again"}.`;
}

function inScope(entry, scope) {
  return !scope || entry.for.includes("plugin") || entry.for.includes(scope);
}

const schemaFailure = (plugin, errors) => `${plugin}: prerequisites.json fails the schema:\n  ${errors.join("\n  ")}`;

const USAGE = [
  "usage: prerequisites.mjs report --plugin-root <dir> [--plugin-root <dir>...]",
  "       prerequisites.mjs check <plugin-root> [--for <scope>] [--data-dir <dir>]",
  "       prerequisites.mjs probe <plugin-root> [--run-if-unset-or-true <OPTION>]",
  "       prerequisites.mjs latest <plugin-root> [--for <scope>] [--data-dir <dir>]",
].join("\n");

class UsageError extends Error {}

function parseArgs(argv) {
  const [mode, ...rest] = argv;
  if (!["report", "check", "probe", "latest"].includes(mode))
    throw new UsageError(mode ? `unknown mode: ${mode}` : "no mode given");
  const opts = { mode, roots: [], scope: null, dataDir: null, gate: null };
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (arg === "--plugin-root" && mode === "report") {
      if (!rest[i + 1]) throw new UsageError("--plugin-root needs a directory");
      opts.roots.push(rest[++i]);
    } else if (arg === "--for" && (mode === "check" || mode === "latest")) {
      if (!rest[i + 1] || !FOR_RE.test(rest[i + 1])) throw new UsageError("--for needs a scope such as skill:<name>");
      opts.scope = rest[++i];
    } else if (arg === "--data-dir" && (mode === "check" || mode === "latest")) {
      if (!rest[i + 1]) throw new UsageError("--data-dir needs a directory");
      opts.dataDir = rest[++i];
    } else if (arg === "--run-if-unset-or-true" && mode === "probe") {
      if (!rest[i + 1] || !OPTION_RE.test(rest[i + 1])) {
        throw new UsageError("--run-if-unset-or-true needs the option name in capitals, such as EXAMPLE_ENABLED");
      }
      opts.gate = rest[++i];
    } else if (!arg.startsWith("--") && mode !== "report" && opts.roots.length === 0) {
      opts.roots.push(arg);
    } else {
      throw new UsageError(`unexpected argument: ${arg}`);
    }
  }
  if (opts.roots.length === 0) throw new UsageError(`${mode} needs a plugin root`);
  for (const root of opts.roots) {
    if (!existsSync(root) || !statSync(root).isDirectory()) throw new UsageError(`not a directory: ${root}`);
  }
  return opts;
}

function readHookInput(stdin) {
  try {
    const raw = stdin();
    const id = JSON.parse(raw || "{}").session_id;
    return typeof id === "string" && id ? id.replace(/[^A-Za-z0-9_-]/g, "-") : "no-session";
  } catch {
    return "no-session";
  }
}

function firstNoticeThisSession(plugin, id, session, env) {
  if (!env.CLAUDE_PLUGIN_DATA) return true;
  const dir = path.join(env.CLAUDE_PLUGIN_DATA, "skip-notices");
  const marker = path.join(dir, `${plugin}-${id}.${session}.user`);
  try {
    if (existsSync(marker)) return false;
    mkdirSync(dir, { recursive: true });
    writeFileSync(marker, "1\n");
  } catch {
  }
  return true;
}

function cmdCheck(opts, ctx, out) {
  const root = opts.roots[0];
  const { plugin, manifest, errors, absent } = loadManifest(root);
  if (absent) {
    out.stdout(`${plugin}: no prerequisites.json; this plugin declares no external dependency.`);
    return 0;
  }
  if (errors.length) {
    out.stderr(schemaFailure(plugin, errors));
    return 2;
  }
  const local = { ...ctx, root, dataDir: opts.dataDir };
  const counts = { failed: 0, warned: 0, passed: 0 };
  const entries = manifest.requires.filter((e) => inScope(e, opts.scope));
  const needed = whenChecker(entries, local);
  for (const entry of entries) {
    const label = `${entry.id} (${entry.kind}, ${entry.need})`;
    if (!needed(entry)) {
      const dir = path.resolve(local.env.CLAUDE_PROJECT_DIR || local.cwd);
      out.stdout(`INFO  ${label}: not needed here: no ${whenText(entry)} at or above ${dir}, and none tracked in its git repository`);
      continue;
    }
    const { status, detail } = detectEntry(entry, local);
    if (status === "present") {
      counts.passed++;
      out.stdout(`PASS  ${label}: ${detail}`);
    } else if (status === "agent-check") {
      out.stdout(`INFO  ${label}: ${detail}. Check the session's tool list; if it is absent: ${remediation(entry)}`);
    } else if (status === "unverified") {
      counts.warned++;
      out.stdout(`WARN  ${label}: ${detail}`);
    } else if (entry.need === "required") {
      counts.failed++;
      out.stdout(`FAIL  ${label}: ${detail}. ${remediation(entry)}`);
    } else {
      counts.warned++;
      out.stdout(`WARN  ${label}: ${detail}. ${remediation(entry)}`);
    }
  }
  out.stdout(`${plugin}: failed=${counts.failed} warned=${counts.warned} passed=${counts.passed}`);
  return counts.failed ? 1 : 0;
}

async function cmdLatest(opts, ctx, out) {
  const root = opts.roots[0];
  const { plugin, manifest, errors, absent } = loadManifest(root);
  if (absent) return 0;
  if (errors.length) {
    out.stderr(schemaFailure(plugin, errors));
    return 2;
  }
  const local = { ...ctx, root, dataDir: opts.dataDir };
  const entries = manifest.requires.filter((e) => inScope(e, opts.scope) && e.detect.version?.latest);
  if (entries.length === 0) return 0;
  const stateDir = ownDataDir(local);
  if (!stateDir) {
    out.stderr(`${plugin}: the plugin data directory is unknown; pass --data-dir "\${CLAUDE_PLUGIN_DATA}"`);
    return 2;
  }
  const { checkVersion } = await import("./cli-version-check.mjs");
  for (const entry of entries) {
    const d = entry.detect;
    const found = firstOnPath(d.any, local, d.reject_store_alias, true) ?? findLocalBin(d.local_bin, local.cwd, local.platform, local.fs);
    const installed = found ? (new RegExp(d.version.pattern).exec(run(found, d.version.args).out)?.[1] ?? "") : "";
    const result = await checkVersion({ stateDir, cli: entry.id, installed, source: d.version.latest, fetch: ctx.fetch });
    if (result.message) out.stdout(result.message);
  }
  return 0;
}

export function report(roots, ctx, out) {
  out.stdout(["plugin", "id", "kind", "need", "status", "check", "install"].join("\t"));
  let missing = 0;
  let present = 0;
  let requiredMissing = false;
  let invalid = false;
  for (const root of roots) {
    const { plugin, manifest, errors, absent } = loadManifest(root);
    if (absent) continue;
    if (errors.length) {
      invalid = true;
      out.stderr(schemaFailure(plugin, errors));
      continue;
    }
    for (const entry of manifest.requires) {
      const { status } = detectEntry(entry, { ...ctx, root });
      if (isFailure(status)) {
        missing++;
        if (entry.need === "required") requiredMissing = true;
      } else if (status === "present") {
        present++;
      }
      out.stdout([plugin, entry.id, entry.kind, entry.need, status, entry.check, installText(entry)].join("\t"));
    }
  }
  out.stdout(`missing=${missing} present=${present}`);
  if (invalid) return 2;
  return requiredMissing ? 1 : 0;
}

function cmdProbe(opts, ctx, out) {
  if (opts.gate) {
    const value = ctx.env[`CLAUDE_PLUGIN_OPTION_${opts.gate}`];
    if (value !== undefined && value !== "" && value !== "true") return 0;
  }
  const root = opts.roots[0];
  const { plugin, manifest, errors, absent } = loadManifest(root);
  if (absent) return 0;
  if (errors.length) {
    out.stderr(schemaFailure(plugin, errors));
    return 2;
  }
  const session = readHookInput(ctx.stdin);
  const notices = [];
  const entries = manifest.requires.filter((e) => e.for.some((s) => s.startsWith("hook:")));
  const needed = whenChecker(entries, ctx);
  for (const entry of entries) {
    if (!needed(entry)) continue;
    const { status, detail } = detectEntry(entry, { ...ctx, root });
    if (!isFailure(status) || !firstNoticeThisSession(plugin, entry.id, session, ctx.env)) continue;
    notices.push(userNotice(plugin, { ...entry, root }, status, detail));
  }
  const drift = gitHookDrift(root, ctx);
  if (drift.length && firstNoticeThisSession(plugin, "git-hooks", session, ctx.env)) notices.push(...drift);
  if (notices.length) out.stdout(JSON.stringify({ systemMessage: notices.join("\n") }));
  return 0;
}

function gitHookDrift(root, ctx) {
  const installer = path.join(HERE, "git-hooks", "install.mjs");
  if (!existsSync(path.join(root, "git-hooks", "entries.json")) || !existsSync(installer)) return [];
  const repo = ctx.env.CLAUDE_PROJECT_DIR || ctx.cwd;
  const r = spawnSync(process.execPath, [installer, "verify", "--quiet", "--repo", repo, "--plugin-root", root], {
    encoding: "utf8",
    env: ctx.env,
    timeout: PROBE_TIMEOUT_MS,
    stdio: ["ignore", "pipe", "ignore"],
  });
  return (r.stdout ?? "").split("\n").filter((line) => line.trim() !== "");
}

function userNotice(plugin, entry, status, detail) {
  const onPath = status === "missing" && (entry.kind === "cli" || entry.kind === "runtime");
  const local = entry.detect.local_bin?.length ? ` or at ${entry.detect.local_bin.join(" or ")}` : "";
  const what = onPath ? `${entry.id} not on the hook PATH${local}` : detail;
  return (
    `${plugin}: ${what}. ${entry.degrade} Install (${installText(entry)}). ` +
    `Hooks read Claude Code's PATH, not your shell profile. No further notice this session; diagnose with: node "${entry.root}/lib/prerequisites.mjs" check "${entry.root}"`
  );
}

export function main(argv, ctx = {}, out = {}) {
  const context = {
    env: ctx.env ?? process.env,
    platform: ctx.platform ?? process.platform,
    cwd: ctx.cwd ?? process.cwd(),
    fs: ctx.fs ?? FS,
    stdin: ctx.stdin ?? (() => (process.stdin.isTTY ? "" : readFileSync(0, "utf8"))),
    fetch: ctx.fetch,
  };
  const io = { stdout: out.stdout ?? ((s) => console.log(s)), stderr: out.stderr ?? ((s) => console.error(s)) };
  let opts;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    if (!(err instanceof UsageError)) throw err;
    io.stderr(`prerequisites.mjs: ${err.message}\n${USAGE}`);
    return 2;
  }
  if (opts.mode === "report") return report(opts.roots, context, io);
  if (opts.mode === "check") return cmdCheck(opts, context, io);
  if (opts.mode === "latest") return cmdLatest(opts, context, io);
  return cmdProbe(opts, context, io);
}

function realPath(p) {
  try {
    return realpathSync(p);
  } catch {
    return path.resolve(p);
  }
}

if (process.argv[1] && realPath(process.argv[1]) === realPath(fileURLToPath(import.meta.url))) {
  Promise.resolve(main(process.argv.slice(2))).then((code) => {
    process.exitCode = code;
  });
}
