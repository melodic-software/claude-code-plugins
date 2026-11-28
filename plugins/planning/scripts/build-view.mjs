#!/usr/bin/env node
import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { applyBranding } from "../lib/html-branding.mjs";
import { escapeHtml } from "../lib/html-escape.mjs";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "../lib/plugin-options.mjs";
import { publishGate } from "../lib/publish-gate.mjs";
import { buildView, VIEW_KINDS, ViewBuildError } from "../lib/view-builder.mjs";
import { producerOf, MEDIUMS, mediumOf, NO_PAGE, NO_PREFERENCE, reportLines } from "../lib/view-registry.mjs";
import { brandingReportLines, findRoot, gateExplicit, resolveBranding, resolveMedium } from "../lib/view-settings.mjs";

export const PRODUCER = "planning";
const PLUGIN_ROOT = resolve(fileURLToPath(new URL("../", import.meta.url)));
const TOKENS_PATH = fileURLToPath(new URL("../reference/html-tokens.css", import.meta.url));

const readBrandingOption = (flagValue, env = process.env) => {
  if (typeof flagValue === "string" && flagValue !== "" && !/^\$\{user_config\./.test(flagValue)) {
    return flagValue;
  }
  if (env.CLAUDE_PLUGIN_OPTION_BRANDING) {
    return env.CLAUDE_PLUGIN_OPTION_BRANDING;
  }
  try {
    const install = resolveInstall(PLUGIN_ROOT);
    const userSettings = install.userSettings ?? (env.CLAUDE_CONFIG_DIR ? join(env.CLAUDE_CONFIG_DIR, "settings.json") : null);
    return readOperatorOptions({ ...install, userSettings }, managedSettingsFiles(), ["branding"]).branding?.value ?? null;
  } catch (err) {
    if (err instanceof OptionsError) {
      console.error(`notice: branding userConfig: ${err.message}`);
      return null;
    }
    throw err;
  }
};

const breakSlots = (text, sep) => {
  let out = text;
  while (out.includes("{{")) out = out.replaceAll("{{", `{${sep}{`);
  return out;
};

function applyTemplateBranding(template, { tokensCss, branding }) {
  const logo = branding?.logo;
  if (!logo || (!logo.label?.includes("{{") && !logo.svg?.includes("{{"))) {
    return applyBranding(template, { tokensCss, branding });
  }
  const safeLabel = logo.label ? breakSlots(logo.label, " ") : logo.label;
  const safeSvg = logo.svg ? breakSlots(logo.svg, " ") : logo.svg;
  let branded = applyBranding(template, {
    tokensCss,
    branding: { ...branding, logo: { ...logo, label: safeLabel, svg: safeSvg } },
  });
  if (logo.label?.includes("{{")) {
    const from = `<span class="rv-brand-label">${escapeHtml(safeLabel)}</span>`;
    const to = `<span class="rv-brand-label">${breakSlots(escapeHtml(logo.label), "<span></span>")}</span>`;
    branded = branded.replace(from, () => to);
  }
  return branded;
}

function renderBranded(kind, record, { connect = null, branding = null } = {}) {
  const entry = Object.hasOwn(VIEW_KINDS, kind) ? VIEW_KINDS[kind] : undefined;
  if (!entry) throw new Error(`view-builder: no view kind ${JSON.stringify(kind)}`);
  const template = readFileSync(join(PLUGIN_ROOT, entry.template), "utf8");
  const tokensCss = readFileSync(TOKENS_PATH, "utf8");
  return buildView({
    profile: entry.tier === "static" ? "report" : "interactive",
    template: applyTemplateBranding(template, { tokensCss, branding }),
    data: entry.parse(record),
    connect,
  });
}

const insideWorkingTree = (dir) => {
  for (let at = dir; ; at = dirname(at)) {
    if (existsSync(join(at, ".git"))) return at;
    if (dirname(at) === at) return null;
  }
};

const bridgeOutProblem = (out, origin) => {
  const dir = dirname(resolve(out));
  if (basename(out) !== "page.html") return `${out} must be named page.html`;
  let st;
  try {
    st = lstatSync(dir);
  } catch {
    return `${dir} does not exist`;
  }
  if (!st.isDirectory()) return `${dir} is not a plain directory`;
  if (process.platform !== "win32" && (st.uid !== process.getuid() || st.mode & 0o077)) {
    return `${dir} must be owned by you with mode 0700`;
  }
  if (realpathSync(dir) !== dir) return `${dir} is not a plain directory path (a link is in it)`;
  const root = insideWorkingTree(dir);
  if (root) return `${dir} is inside the working tree ${root}`;
  let session;
  try {
    session = JSON.parse(readFileSync(join(dir, ".view-session.json"), "utf8"));
  } catch {
    return `${dir} holds no view-bridge session; run view-bridge.sh ensure-running first`;
  }
  const port = /^http:\/\/127\.0\.0\.1:([0-9]{1,5})$/.exec(origin)?.[1];
  if (!port || Number(port) !== session?.port) return `${origin} is not the origin this data dir serves`;
  return null;
};

/** Write the page to <tmp>/planning-views/<kind>.html; the temp root is shared, so the directory is private and no link is written through. */
export function writePrivate(page, kind) {
  const dir = join(tmpdir(), "planning-views");
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  if (!lstatSync(dir).isDirectory()) throw new Error("build-view: refusing a symlinked or non-directory output path");
  chmodSync(dir, 0o700);
  const out = join(dir, `${kind}.html`);
  rmSync(out, { force: true });
  writeFileSync(out, page, { mode: 0o600 });
  return out;
}

/**
 * Deliver the `kind` view of `record` on the resolved medium. A publishing medium first passes the
 * publish gate, which keeps the page on the chain's local step for a non-public repository or a
 * credential-shaped record unless the reader chose to publish; the report then names the gate.
 * @param {{kind: string, record: unknown, resolution: {preferred: string|null, medium: string, decidedBy: string, notices: {text: string}[]}, visibility?: string, mediums?: object, write?: (page: string, kind: string) => string, context?: object}} input
 *   mediums replaces the medium registry; write stores the page and returns its path
 * @returns {{delivery: object, report: string[]}} delivery: the medium entry's deliver result, plus `page` when a page was built
 */
export function deliverView({ kind, record, resolution, branding = null, visibility = "UNKNOWN", mediums = MEDIUMS, write = writePrivate, context = {} }) {
  const entryOf = (id) => (Object.hasOwn(mediums, id) ? mediums[id] : undefined);
  let entry = entryOf(resolution.medium);
  if (!entry) throw new Error(`build-view: no medium entry for ${JSON.stringify(resolution.medium)}`);
  let shown = resolution;
  if (entry.publishes) {
    const text = typeof record === "string" ? record : JSON.stringify(record);
    const gate = publishGate({ explicit: gateExplicit(resolution), visibility, text, subject: "record" });
    if (!mediumOf(gate.medium).publishes) {
      entry = entryOf(gate.medium) ?? mediumOf(gate.medium);
      const notices = [...resolution.notices, ...(gate.opt_in ? [{ kind: "gate", text: gate.opt_in }] : [])];
      shown = { ...resolution, medium: gate.medium, decidedBy: `publish gate: ${gate.reason}`, notices };
    }
  }
  const path = entry.id === NO_PAGE ? null : write(renderBranded(kind, record, { branding }), kind);
  const delivery = entry.deliver({ kind, path }, context);
  const brandingNotices = branding?.notices?.length
    ? brandingReportLines(branding).filter((line) => line.startsWith("notice:"))
    : [];
  return { delivery: path ? { ...delivery, page: path } : delivery, report: [...reportLines(shown), ...brandingNotices] };
}

const USAGE =
  "usage: build-view.mjs <kind> [--record <file>] [--branding-option <json>] [--team-ref <ref>]\n" +
  "       build-view.mjs <kind> --option <medium option> [--argument <medium>] [--visibility <V>] [--record <file>] [--branding-option <json>] [--team-ref <ref>]\n" +
  "       build-view.mjs <kind> --connect <session-bridge origin> --out <data_dir>/page.html [--record <file>] [--branding-option <json>] [--team-ref <ref>]\n";
const FLAGS = ["--record", "--option", "--argument", "--visibility", "--connect", "--out", "--branding-option", "--team-ref"];

function main(argv, env = process.env) {
  const [kind, ...rest] = argv;
  const flags = {};
  for (let i = 0; i < rest.length; i += 2) flags[rest[i]] = rest[i + 1];
  const has = (key) => key in flags;
  const flagsOk =
    Object.keys(flags).every((key) => FLAGS.includes(key)) &&
    Object.entries(flags).every(([key, value]) => typeof value === "string" && (value !== "" || key === "--option" || key === "--branding-option")) &&
    has("--connect") === has("--out") &&
    !(has("--option") && has("--connect")) &&
    (has("--option") || !(has("--argument") || has("--visibility"))) &&
    (!has("--argument") || flags["--argument"] === NO_PREFERENCE || Boolean(mediumOf(flags["--argument"])));
  if (!producerOf(PRODUCER).kinds.includes(kind) || !flagsOk) {
    process.stderr.write(USAGE);
    return 2;
  }
  if (has("--out")) {
    const problem = bridgeOutProblem(flags["--out"], flags["--connect"]);
    if (problem) {
      console.error(`build-view: refused: ${problem}`);
      return 2;
    }
  }
  try {
    const record = readFileSync(flags["--record"] ?? 0, "utf8");
    const root = findRoot();
    const branding = resolveBranding({
      userConfig: readBrandingOption(flags["--branding-option"], env),
      projectRoot: root,
      teamRef: flags["--team-ref"] ?? null,
    });
    if (has("--option")) {
      const argument = flags["--argument"] === NO_PREFERENCE ? null : (flags["--argument"] ?? null);
      const interactive = !env.CI || env.CI === "false";
      const resolution = resolveMedium(
        { producer: PRODUCER, argument, userConfig: flags["--option"], projectRoot: root },
        { dataDir: env.CLAUDE_PLUGIN_DATA || null, interactive },
      );
      const visibility = (flags["--visibility"] ?? "UNKNOWN").toUpperCase();
      const { delivery, report } = deliverView({ kind, record, resolution, branding, visibility, context: { interactive } });
      process.stdout.write(`${JSON.stringify(delivery)}\n${report.join("\n")}\n`);
      return 0;
    }
    const page = renderBranded(kind, record, { connect: flags["--connect"] ?? null, branding });
    if (branding.notices.length) {
      for (const line of brandingReportLines(branding)) {
        if (line.startsWith("notice:")) console.error(line);
      }
    }
    const out = flags["--out"];
    if (!out) {
      console.log(writePrivate(page, kind));
      return 0;
    }
    if (existsSync(out) && lstatSync(out).isDirectory()) throw new Error(`build-view: refused: ${out} is a directory`);
    rmSync(out, { force: true });
    writeFileSync(out, page, { flag: "wx", mode: 0o600 });
    console.log(out);
    return 0;
  } catch (err) {
    console.error(err instanceof SyntaxError ? `build-view: the ${kind} record is not JSON` : err.message);
    return err instanceof ViewBuildError ? 1 : 2;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
