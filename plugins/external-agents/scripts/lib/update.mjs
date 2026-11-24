import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { checkVersion, claimDaily, parseVersion } from "../../lib/cli-version-check.mjs";
import { closeBreaker } from "./breaker.mjs";
import { pluginRoot } from "./config.mjs";
import { query } from "./process.mjs";
import { EXIT, guardValues, oneLine, pickBinary, setup, Stop } from "./runner.mjs";

const TIMEOUT_MS = 5000;
const PAGE_TIMEOUT_MS = 30_000;
const reasonOf = (error) => (error?.name === "TimeoutError" ? `no answer in ${TIMEOUT_MS} ms` : oneLine(error?.message ?? error));

/** One page's text, read through the plugin's fetch-docs.sh copy and the shared docs cache; throws with the reason it stayed unread. */
export function readCachedPage(url, env = process.env) {
  const out = mkdtempSync(join(tmpdir(), "external-agents-page-"));
  try {
    const args = [join(pluginRoot, "scripts", "fetch-docs.sh"), "--cache", "--profile", "generic", "--out", out.replaceAll("\\", "/"), url];
    const done = spawnSync("bash", args, { env, cwd: pluginRoot, encoding: "utf8", timeout: PAGE_TIMEOUT_MS, windowsHide: true });
    if (done.error) throw done.error;
    if (done.status !== 0) throw new Error(oneLine(done.stderr ?? "") || `fetch-docs.sh exited ${done.status}`);
    const page = JSON.parse(readFileSync(join(out, "manifest.json"), "utf8")).pages?.[0];
    if (page?.state !== "read") throw new Error(page?.reason ?? "fetch-docs.sh recorded no page");
    return readFileSync(page.file, "utf8");
  } finally {
    rmSync(out, { recursive: true, force: true });
  }
}

/** Every config key the runner passes with the record's config flag, in the order the record lists them. */
export function configKeys(record) {
  const lists = [record.always_args ?? [], ...Object.values(record.modes ?? {}).flatMap((mode) => Object.values(mode.args ?? {}))];
  const keys = [];
  for (const list of lists) {
    list.forEach((arg, i) => {
      if (i > 0 && list[i - 1] === record.config_arg) keys.push(arg.split("=")[0]);
    });
  }
  if (record.effort_config) keys.push(record.effort_config);
  return [...new Set(keys)];
}

/** The release source for the install channel the binary's real path shows. */
export function versionSource(record, binaryPath) {
  const sources = Object.entries(record.version.sources ?? {});
  if (!sources.length) return null;
  let real = binaryPath;
  try {
    real = realpathSync.native(binaryPath);
  } catch {}
  const folders = real.toLowerCase().split(/[\\/]/);
  const markers = record.version.markers ?? {};
  const marked = sources.find(([channel]) => (markers[channel] ?? []).some((m) => folders.includes(m.toLowerCase())));
  return (marked ?? sources.find(([channel]) => !markers[channel]) ?? sources[0])[1];
}

const named = (key) => new RegExp(`(?<![A-Za-z0-9_.])${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![A-Za-z0-9_])`);

async function checkKeys(ctx, record, help, readPage) {
  const keys = configKeys(record);
  if (!keys.length) return { line: "config keys: none passed", fine: true };
  const missing = keys.filter((key) => !named(key).test(help));
  if (!missing.length) return { line: `config keys: ok (${keys.join(", ")})`, fine: true };
  if (!record.config_reference) return { line: `config keys: drift: ${missing.join(", ")} not in the CLI help`, fine: false };
  let text;
  try {
    text = await readPage(record.config_reference, ctx.env);
  } catch (error) {
    return { line: `config keys: unverified: ${missing.join(", ")} ${missing.length === 1 ? "is" : "are"} not in the CLI help, and ${record.config_reference} could not be read (${reasonOf(error)})`, fine: false };
  }
  const absent = missing.filter((key) => !named(key).test(text));
  if (!absent.length) return { line: `config keys: ok (${keys.join(", ")})`, fine: true };
  return { line: `config keys: drift: ${absent.join(", ")} ${absent.length === 1 ? "is" : "are"} in neither the CLI help nor ${record.config_reference}`, fine: false };
}

async function checkDocs(ctx, url) {
  try {
    const res = await ctx.fetch(url, { method: "HEAD", redirect: "follow", signal: AbortSignal.timeout(TIMEOUT_MS) });
    return res.ok ? { line: `docs index: reachable (${url})`, fine: true } : { line: `docs index: unreachable (HTTP ${res.status}, ${url})`, fine: false };
  } catch (error) {
    return { line: `docs index: unreachable (${reasonOf(error)}, ${url})`, fine: false };
  }
}

function versionLine(result, source) {
  if (result.status === "current") return `version check: current (latest ${result.latest}, from ${source})`;
  if (result.status === "skipped") return "version check: already checked today";
  return `version check: ${oneLine(result.message)}`;
}

/** The cache file that holds a record's model list, beside its help files. */
export const MODELS_FILE = "models";

/** The installed version, from the record's version command. */
export function installedVersion(record, ask) {
  const said = ask(record.version.args);
  const version = parseVersion(said.code === 0 ? said.stdout : "");
  if (!version) throw new Stop("failed", `${record.binary.name} ${record.version.args.join(" ")} printed no version`);
  return { version, installed: said.stdout };
}

/** The CLI-facts folder for one installed version, created when missing. */
export function factsDir(ctx, record, version) {
  const dir = join(ctx.dataDir, "cli-facts", record.product, version);
  mkdirSync(dir, { recursive: true });
  return dir;
}

const EXCERPT_CHARS = 200;
const EMAIL = /[^\s@<>()"',;:]{1,64}@[^\s@<>()"',;:]{1,255}\.[A-Za-z]{2,63}/g;

function excerpt(got) {
  const text = oneLine((got.stderr.trim() ? got.stderr : got.stdout).replace(EMAIL, "<email>"));
  return text.length > EXCERPT_CHARS ? `${text.slice(0, EXCERPT_CHARS - 3)}...` : text;
}

/** Runs one fact command and caches what it printed as <name>.txt; returns the text, or why it was skipped. */
export function cacheFact(dir, name, args, ask) {
  const got = ask(args);
  if (got.code !== 0) {
    const said = excerpt(got);
    return { skipped: `${name}: ${args.join(" ")} exited ${got.code ?? reasonOf(got.error)}${said ? `: ${said}` : ""}` };
  }
  const text = got.stdout.trim() ? got.stdout : got.stderr;
  if (!text.trim()) return { skipped: `${name}: ${args.join(" ")} printed nothing` };
  writeFileSync(join(dir, `${name}.txt`), text);
  return { text };
}

/** Readiness and cached CLI facts for one product; never installs anything. */
export async function update(opts) {
  const product = opts.product ?? "external-agents";
  try {
    const state = setup(opts);
    const { ctx, record, settings } = state;
    const { binary, missing } = pickBinary(ctx, record, settings);
    if (!binary) {
      throw new Stop("unavailable", `${record.binary.name} not found (tried ${missing.tried.join(", ")}). This command never installs anything: install ${record.binary.name} through your dotfiles install, or set ${record.product}.binary_path, then run: external-agents update ${record.product}`);
    }
    guardValues(record, binary, {}, false);
    const ask = (args) => query(binary, args, { env: ctx.env, cwd: ctx.cwd });

    const { version, installed } = installedVersion(record, ask);
    const lines = [`version: ${version}`];
    const attention = [];
    const login = record.login_status ? ask(record.login_status.args) : null;
    if (login && login.code === null) throw new Stop("failed", `could not check the login state: ${reasonOf(login.error ?? "the query was stopped")}`);
    const loggedIn = !login || login.code === 0;
    lines.push(`login: ${!login ? "not checked (no login_status in the record)" : loggedIn ? "logged in" : "not logged in"}`);

    const facts = factsDir(ctx, record, version);
    const skipped = [];
    let help = "";
    for (const [name, args] of Object.entries(record.help ?? {})) {
      const got = cacheFact(facts, name, args, ask);
      if (got.skipped) skipped.push(got.skipped);
      else help += got.text;
    }
    if (record.models) {
      const got = cacheFact(facts, MODELS_FILE, record.models.args, ask);
      if (got.skipped) skipped.push(got.skipped);
    }
    lines.push(`cli facts: ${facts}${skipped.length ? ` (${skipped.join("; ")})` : ""}`);
    if (skipped.length) attention.push("cli facts");

    const source = versionSource(record, binary.path);
    if (source) {
      const result = await checkVersion({ stateDir: ctx.dataDir, cli: record.product, installed, source, hint: settings.update_hint ?? "", now: ctx.now(), fetch: ctx.fetch });
      lines.push(versionLine(result, source));
    }

    const docs = await checkDocs(ctx, record.docs_index);
    lines.push(docs.line);
    if (!docs.fine) attention.push("docs index");

    const due = claimDaily({ stateDir: ctx.dataDir, name: `routing-${record.product}`, now: ctx.now() });
    lines.push(due ? "routing: due; re-read the routing pointers" : "routing: checked earlier today");

    const keys = await checkKeys(ctx, record, help, opts.readPage ?? readCachedPage);
    lines.push(keys.line);
    if (!keys.fine) attention.push("config keys");

    if (loggedIn) closeBreaker(ctx.dataDir, record.product);
    const first = loggedIn
      ? `${record.product}: ready${attention.length ? ` (check: ${attention.join(", ")})` : ""}`
      : `${record.product}: unavailable: not logged in. Log in with ${record.binary.name}, then run: external-agents update ${record.product}`;
    return { code: loggedIn ? EXIT.ok : EXIT.unavailable, stdout: `${[first, ...lines].join("\n")}\n`, stderr: state.notices.map((n) => `notice: ${n}\n`).join("") };
  } catch (error) {
    const why = oneLine(error?.message ?? error);
    if (!(error instanceof Stop)) return { code: EXIT.failed, stdout: `${product}: failed (${why})\n`, stderr: "" };
    const code = error.kind === "refused" ? EXIT.usage : error.kind === "failed" ? EXIT.failed : EXIT.unavailable;
    const line = error.kind === "failed" ? `${product}: failed (${why})` : `${product}: ${error.kind}: ${why}`;
    return { code, stdout: `${line}\n`, stderr: "" };
  }
}
