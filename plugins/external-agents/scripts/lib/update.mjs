import { mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { checkVersion, claimDaily, parseVersion } from "../../lib/cli-version-check.mjs";
import { closeBreaker } from "./breaker.mjs";
import { query } from "./process.mjs";
import { EXIT, guardValues, oneLine, pickBinary, setup, Stop } from "./runner.mjs";

const TIMEOUT_MS = 5000;
const reasonOf = (error) => (error?.name === "TimeoutError" ? `no answer in ${TIMEOUT_MS} ms` : oneLine(error?.message ?? error));

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

async function checkKeys(ctx, record, help) {
  const keys = configKeys(record);
  if (!keys.length) return { line: "config keys: none passed", fine: true };
  const missing = keys.filter((key) => !named(key).test(help));
  if (!missing.length) return { line: `config keys: ok (${keys.join(", ")})`, fine: true };
  if (!record.config_reference) return { line: `config keys: drift: ${missing.join(", ")} not in the CLI help`, fine: false };
  let text;
  try {
    const res = await ctx.fetch(record.config_reference, { headers: { accept: "text/markdown, text/plain" }, signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    text = await res.text();
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

    const said = ask(record.version.args);
    const installed = said.code === 0 ? said.stdout : "";
    const version = parseVersion(installed);
    if (!version) throw new Stop("failed", `${record.binary.name} ${record.version.args.join(" ")} printed no version`);

    const lines = [`version: ${version}`];
    const attention = [];
    const login = record.login_status ? ask(record.login_status.args) : null;
    if (login && login.code === null) throw new Stop("failed", `could not check the login state: ${reasonOf(login.error ?? "the query was stopped")}`);
    const loggedIn = !login || login.code === 0;
    lines.push(`login: ${!login ? "not checked (no login_status in the record)" : loggedIn ? "logged in" : "not logged in"}`);

    const facts = join(ctx.dataDir, "cli-facts", record.product, version);
    mkdirSync(facts, { recursive: true });
    const skipped = [];
    let help = "";
    for (const [name, args] of Object.entries(record.help ?? {})) {
      const got = ask(args);
      if (got.code !== 0) {
        skipped.push(`${name}: ${args.join(" ")} exited ${got.code ?? reasonOf(got.error)}`);
        continue;
      }
      const text = got.stdout.trim() ? got.stdout : got.stderr;
      if (!text.trim()) {
        skipped.push(`${name}: ${args.join(" ")} printed nothing`);
        continue;
      }
      writeFileSync(join(facts, `${name}.txt`), text);
      help += text;
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

    const keys = await checkKeys(ctx, record, help);
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
