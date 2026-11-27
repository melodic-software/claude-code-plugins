#!/usr/bin/env node
import { existsSync, lstatSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";

import { escapeHtml } from "../../../lib/html-escape.mjs";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "../../../lib/plugin-options.mjs";
import { buildView, validateView } from "../../../lib/view-builder.mjs";
import { findRoot, resolveBranding } from "../../../lib/view-settings.mjs";

const selfDir = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = join(selfDir, "../../..");
export const TEMPLATE_PATH = join(selfDir, "../templates/digest.html");
const TOKENS_PATH = join(selfDir, "../../../reference/html-tokens.css");
const BRAND_CSS = [
  ".rv-brand { display: inline-flex; align-items: center; gap: 0.5rem; margin-right: auto; }",
  ".rv-brand svg { height: 1.5rem; width: auto; display: block; }",
  ".rv-brand-mark { display: inline-block; width: 1.5rem; height: 1.5rem; background-size: contain; background-repeat: no-repeat; background-position: center; }",
  ".rv-brand-label { font-family: var(--sans); font-weight: 600; font-size: 0.95rem; color: var(--fg); }",
].join("\n");

function readBrandingOption(explicitOption) {
  if (typeof explicitOption === "string" && explicitOption !== "" && !/^\$\{user_config\./.test(explicitOption)) {
    return explicitOption;
  }
  if (process.env.CLAUDE_PLUGIN_OPTION_BRANDING) {
    return process.env.CLAUDE_PLUGIN_OPTION_BRANDING;
  }
  try {
    return readOperatorOptions(resolveInstall(PLUGIN_ROOT), managedSettingsFiles(), ["branding"]).branding?.value ?? null;
  } catch (err) {
    if (err instanceof OptionsError) {
      process.stderr.write(`notice: branding userConfig: ${err.message}\n`);
      return null;
    }
    throw err;
  }
}

function applyBranding(template, teamRef, brandingOption = null) {
  const tokens = readFileSync(TOKENS_PATH, "utf8").replace(/\r\n?/g, "\n").replace(/^(?:\s*\/\*[\s\S]*?\*\/\s*)+/, "").trim();
  const safeRef = typeof teamRef === "string" ? teamRef : "";
  const branding = resolveBranding({ userConfig: readBrandingOption(brandingOption), projectRoot: findRoot(), teamRef: safeRef });
  for (const notice of branding.notices) {
    process.stderr.write(`notice: ${notice.text}\n`);
  }
  const logo = branding?.logo;
  const parts = [];
  if (logo?.kind === "svg" && logo.svg) {
    parts.push(logo.svg);
  } else if (logo?.kind === "image") {
    parts.push(`<span class="rv-brand-mark rv-logo" role="img" aria-label="${escapeHtml(logo.label || "Brand logo")}"></span>`);
  }
  if (logo?.label) {
    parts.push(`<span class="rv-brand-label">${escapeHtml(logo.label)}</span>`);
  }
  const slot = parts.length ? `<div class="rv-brand">${parts.join("")}</div>` : "";
  const extraCss = [slot ? BRAND_CSS : "", branding?.css ?? ""].filter(Boolean).join("\n");
  let out = template.replace(/<style>\s*/i, (open) => `${open}${tokens}\n`);
  if (extraCss) out = out.replace(/<\/style>/i, (close) => `\n${extraCss}\n${close}`);
  if (slot) out = out.replace(/<div class="rv-bar">/i, (bar) => `${bar}${slot}`);
  return out;
}

const text = (value) =>
  typeof value === "string" ? value : typeof value === "number" ? String(value) : "";
const list = (value) => (Array.isArray(value) ? value.filter((row) => row && typeof row === "object") : []);
const texts = (value) => (Array.isArray(value) ? value : []).map(text).filter((item) => item !== "");

/** What the fresh-context check said about a risk row. Anything else reads as unchecked. */
export const CHECKS = Object.freeze(["agreed", "disputed", "added", "unchecked"]);

/**
 * Keep only the fields the template binds, each as a string. Anything else in
 * the input never reaches the page. The quiz and the recording become lists of
 * zero or one section, so the page omits a section the input does not carry.
 */
export function shapeDigest(input) {
  const src = input && typeof input === "object" ? input : {};
  const questions = list(src.quiz)
    .map((q) => ({ question: text(q.question), choices: texts(q.choices), answer: text(q.answer) }))
    .filter((q) => q.question !== "");
  const recording = src.recording && typeof src.recording === "object" ? src.recording : {};
  const recordingPath = /^(?:[/\\~]|[A-Za-z]:)/.test(text(recording.path)) ? "" : text(recording.path);
  return {
    title: text(src.title) || "Change digest",
    change: text(src.change),
    why: text(src.why),
    before: text(src.before),
    after: text(src.after),
    risks: list(src.risks).map((r) => ({
      area: text(r.area),
      level: text(r.level),
      why: text(r.why),
      check: CHECKS.includes(r.check) ? r.check : "unchecked",
      checker: text(r.checker),
    })),
    focus: texts(src.focus),
    recording: recordingPath ? [{ path: recordingPath, head: text(recording.head) }] : [],
    files: list(src.files).map((f) => ({
      path: text(f.path),
      status: text(f.status),
      note: text(f.note),
      hunks: list(f.hunks).map((h) => ({ at: text(h.at), code: text(h.code), note: text(h.note) })),
    })),
    quiz: questions.length ? [{ questions }] : [],
  };
}

export function buildDigest(input, connect = null, { teamRef = "", brandingOption = null } = {}) {
  const data = shapeDigest(input);
  return buildView({
    profile: "interactive",
    template: applyBranding(readFileSync(TEMPLATE_PATH, "utf8"), teamRef, brandingOption),
    data,
    connect,
    title: data.title,
  });
}

/**
 * Why dir cannot take a connected page for origin, or null when it can: it must be
 * a plain directory owned by this user with mode 0700, outside any working tree,
 * holding the session file view-bridge ensure-running wrote for that origin's port.
 */
export function bridgeDirProblem(dir, origin) {
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
  if (realpathSync(dir) !== resolve(dir)) return `${dir} is not a plain directory path (a link is in it)`;
  const root = repoRoot(dir);
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
}

/** The working tree holding dir, found by walking up to a .git entry. */
export function repoRoot(dir) {
  let at = resolve(dir);
  for (;;) {
    if (existsSync(join(at, ".git"))) return at;
    const up = dirname(at);
    if (up === at) return null;
    at = up;
  }
}

const inside = (child, parent) => {
  const rel = relative(parent, child);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
};

function fail(message, code) {
  process.stderr.write(`build-digest: ${message}\n`);
  process.exit(code);
}

function main(args) {
  if (args[0] === "--check") {
    if (!args[1]) fail("usage: build-digest.mjs --check <file>", 2);
    let html;
    try {
      html = readFileSync(args[1], "utf8");
    } catch (error) {
      fail(error.message, 2);
    }
    const verdict = validateView(html);
    if (!verdict.ok) fail(verdict.failures.join(","), 1);
    process.stdout.write("ok\n");
    return;
  }
  const usage = "usage: build-digest.mjs [--team-ref <sha>] [--branding-option <value>] [--connect <origin> --dir <view-bridge data dir>] < data.json | --check <file>";
  const flags = {};
  if (args.length % 2 !== 0) fail(usage, 2);
  for (let i = 0; i < args.length; i += 2) {
    const flag = args[i];
    const value = args[i + 1];
    const allowEmpty = flag === "--team-ref" || flag === "--branding-option";
    if (!["--connect", "--dir", "--team-ref", "--branding-option"].includes(flag) || Object.hasOwn(flags, flag) || typeof value !== "string" || (!allowEmpty && value === "")) {
      fail(usage, 2);
    }
    flags[flag] = value;
  }
  const hasConnect = Object.hasOwn(flags, "--connect");
  const hasDir = Object.hasOwn(flags, "--dir");
  if (hasConnect !== hasDir) fail(usage, 2);
  const connected = hasConnect && hasDir;
  if (connected) {
    const problem = bridgeDirProblem(flags["--dir"], flags["--connect"]);
    if (problem) fail(`refused: ${problem}`, 2);
  }
  const temp = realpathSync(tmpdir());
  const root = repoRoot(temp);
  if (!connected && root && inside(temp, realpathSync(root))) {
    fail(`refused: the temp dir ${temp} is inside the working tree ${root}; write the view outside it`, 2);
  }
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    fail(`invalid JSON (${error.message})`, 2);
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) fail("JSON root must be an object", 2);
  let page;
  try {
    page = buildDigest(input, connected ? flags["--connect"] : null, {
      teamRef: flags["--team-ref"] ?? "",
      brandingOption: flags["--branding-option"] ?? null,
    });
  } catch (error) {
    fail(error.message, 1);
  }
  if (connected) {
    const out = join(realpathSync(flags["--dir"]), "page.html");
    if (existsSync(out) && lstatSync(out).isDirectory()) fail(`refused: ${out} is a directory`, 2);
    rmSync(out, { force: true });
    writeFileSync(out, page, { flag: "wx", mode: 0o600 });
    process.stderr.write(
      `build-digest: ${out} is a connected page: it is local-only and works only on this machine. Never publish it as an Artifact: it names the local session-bridge port.\n`,
    );
    process.stdout.write(`${out}\n`);
    return;
  }
  const out = join(mkdtempSync(join(temp, "explain-change-")), "digest.html");
  writeFileSync(out, page, { flag: "wx" });
  process.stdout.write(`${out}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2));
}
