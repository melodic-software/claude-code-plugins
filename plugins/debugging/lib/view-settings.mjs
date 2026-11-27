#!/usr/bin/env node
// GENERATED from lib/view-settings.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
import { execFileSync, spawnSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { configBlockBody, readLayers } from "./config-cascade.mjs";
import { BRANDING_SCHEMA, NO_PAGE, NO_PREFERENCE, PALETTE_ROLES, SCHEMA, SHIPPED_TOKENS, TYPE_STACKS, fallBack, producerOf, mediumOf, reportLines } from "./view-registry.mjs";

const CONCERN = "rendered-views";
const HOME = "docs/conventions";
const TEAM_FILE = `${HOME}/${CONCERN}.yaml`;
const PERSONAL_FILE = `${HOME}/${CONCERN}.local.yaml`;
const HERE = dirname(fileURLToPath(import.meta.url));

/** The session's project: CLAUDE_PROJECT_DIR, else the nearest directory above the cwd holding `.git`. */
export function findRoot() {
  if (process.env.CLAUDE_PROJECT_DIR) return resolve(process.env.CLAUDE_PROJECT_DIR);
  for (let at = process.cwd(); ; at = dirname(at)) {
    if (existsSync(join(at, ".git"))) return at;
    if (dirname(at) === at) return null;
  }
}

const real = (p) => {
  try {
    return realpathSync(p);
  } catch {
    return resolve(p);
  }
};
const within = (child, parent) => {
  const rel = relative(parent, child);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
};
const isLink = (p) => {
  try {
    return lstatSync(p).isSymbolicLink();
  } catch {
    return false;
  }
};
function gitOut(root, args) {
  try {
    return execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch {
    return null;
  }
}

/**
 * A personal file applies only untracked, so a pull request cannot ship one. Every directory between
 * the root and the file must be a plain, untracked directory, never a submodule, a tracked file or a
 * symlink. Not gitignored, it warns, or with `requireIgnored` is ignored too.
 */
export function personalOverrideApplies(root, path, warnings, { requireIgnored = false } = {}) {
  const rel = relative(root, path).split("\\").join("/");
  if (gitOut(root, ["ls-files", "--", `:(icase)${rel}`])) {
    warnings.push(`personal override ${rel}: tracked in git, so a pull request could set it; layer ignored`);
    return false;
  }
  const parts = rel.split("/").slice(0, -1);
  const dirs = parts.map((_, i) => parts.slice(0, i + 1).join("/"));
  for (const dir of dirs) {
    const entries = (gitOut(root, ["ls-files", "-s", "-z", "--", `:(icase)${dir}`]) ?? "").split("\0");
    if (entries.some((e) => e.split("\t")[1]?.toLowerCase() === dir.toLowerCase()) || existsSync(join(root, dir, ".git"))) {
      warnings.push(`personal override ${rel}: ${dir} is a submodule or tracked entry; layer ignored`);
      return false;
    }
    if (isLink(join(root, dir))) {
      warnings.push(`personal override ${rel}: ${dir} is a symlink; layer ignored`);
      return false;
    }
  }
  if (isLink(path) || !within(real(path), join(real(root), ...parts))) {
    warnings.push(`personal override ${rel}: the file is a symlink or resolves outside ${parts.join("/") || "the root"}; layer ignored`);
    return false;
  }
  if (gitOut(root, ["check-ignore", "-q", "--", path]) === null) {
    warnings.push(`personal override ${rel}: not gitignored, so it can reach team history${requireIgnored ? "; layer ignored" : ""}`);
    return !requireIgnored;
  }
  return true;
}

/** Repository scopes apply only inside a working tree that is not the user's home or above it. */
const repoScopes = (root, userHome) => Boolean(root) && !within(real(userHome), real(root)) && gitOut(root, ["rev-parse", "--is-inside-work-tree"]) !== null;

/** A ref name or object id: never an option, never a revision expression. */
const REF = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;

/** The team file as `ref` holds it, for the cascade reader; a ref naming no commit reads nothing. */
function teamAt(root, ref, notices) {
  const sha = REF.test(ref) ? gitOut(root, ["rev-parse", "--verify", "--quiet", `${ref}^{commit}`])?.trim() : null;
  if (!sha) {
    const named = ref ? `team ref ${JSON.stringify(ref)} names no commit here` : "no team ref was given";
    notices.push({ kind: "team-ref", text: `${named}, so ${TEAM_FILE} is not read` });
    return { path: `${ref}:${TEAM_FILE}`, text: null, sha: null };
  }
  return { path: `${sha.slice(0, 12)}:${TEAM_FILE}`, text: gitOut(root, ["show", `${sha}:${TEAM_FILE}`]), sha };
}

const mediumIn = (text) => /^[ \t]*medium:[ \t]*["']?([a-z]+)["']?[ \t]*$/m.exec(text ?? "")?.[1] ?? null;
/** The medium a retired source sets: for the team .md only its config block counts, not an example fence. */
const retiredMedium = (bytes, kind) => {
  const text = bytes?.toString("utf8") ?? null;
  return mediumIn(kind === "fenced-block" && text !== null ? configBlockBody(text) : text);
};
const readBytes = (p) => {
  try {
    return readFileSync(p);
  } catch {
    return null;
  }
};

/** This project's state key (docs/contracts/plugin-data-report-keying, rule 1), or null when it cannot be derived. */
function stateKey(root) {
  const out = spawnSync("bash", [join(HERE, "state-key.sh"), "--root", root ?? process.cwd()], { encoding: "utf8" });
  const key = out.status === 0 ? out.stdout.trim() : "";
  return /^[a-z0-9][a-z0-9._-]*(\/[a-z0-9][a-z0-9._-]*)+$/.test(key) ? key : null;
}

function writeAtomic(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  const temp = `${path}.${process.pid}.${randomBytes(4).toString("hex")}.tmp`;
  writeFileSync(temp, text);
  renameSync(temp, path);
}

const retiredWhere = (path, root, userHome) => (within(path, join(userHome, ".claude")) ? `~/${relative(userHome, path).split("\\").join("/")}` : relative(root, path).split("\\").join("/"));
const isLocal = (value) => Boolean(mediumOf(value)) && value !== NO_PREFERENCE && !mediumOf(value).publishes;

/** Highest precedence first, mirroring personal override, team, userConfig. */
const RETIRED_LOCAL = [
  ["claude-local", `${CONCERN}.local.md`],
  ["claude-project", `${CONCERN}.md`],
  ["fenced-block", `${CONCERN}.md`],
  ["claude-user", `${CONCERN}.md`],
];
const rank = ({ path, kind }) => RETIRED_LOCAL.findIndex(([k, name]) => k === kind && basename(path) === name);

/** The highest-precedence terminal or file value a retired file sets, or null; read on every call, apart from the shown-once notice state. */
function retiredLocal(legacy) {
  return (
    legacy
      .filter((entry) => rank(entry) >= 0)
      .map((entry) => ({ ...entry, value: retiredMedium(readBytes(entry.path), entry.kind) }))
      .filter(({ value }) => isLocal(value))
      .sort((a, b) => rank(a) - rank(b))[0] ?? null
  );
}

/** One notice per retired file, unless this plugin already showed it for this project with these bytes. */
function retiredNotices(legacy, { plugin, hasMediumOption, root, userHome, dataDir }) {
  const where = (path) => retiredWhere(path, root, userHome);
  const destination = { "claude-user": PERSONAL_FILE, "claude-project": TEAM_FILE, "claude-local": PERSONAL_FILE, "fenced-block": TEAM_FILE };
  const key = dataDir ? stateKey(root) : null;
  const state = key && join(dataDir, "view-settings", key, "retired-notices.json");
  let seen = {};
  try {
    seen = state ? JSON.parse(readFileSync(state, "utf8")) : {};
  } catch {
    seen = {};
  }
  const notices = [];
  let changed = false;
  const order = Object.keys(destination);
  for (const { path, kind } of [...legacy].sort((a, b) => order.indexOf(a.kind) - order.indexOf(b.kind) || a.path.localeCompare(b.path))) {
    const bytes = readBytes(path);
    if (!bytes) continue;
    const shown = where(path);
    const hash = createHash("sha256").update(bytes).digest("hex");
    if (seen[shown] === hash) continue;
    [seen[shown], changed] = [hash, true];
    const value = retiredMedium(bytes, kind);
    const to = destination[kind] ?? TEAM_FILE;
    const caveat = !mediumOf(value)?.publishes
      ? ""
      : to === TEAM_FILE
        ? "; a team file never publishes, so that value would be ignored there"
        : "; it publishes only while that file is untracked and gitignored";
    const status = rank({ path, kind }) >= 0 && isLocal(value) ? "is retired but still keeps the view local" : "is no longer read";
    const perUser = kind === "claude-user" && hasMediumOption ? `; per user, the ${plugin} plugin's medium option also works` : "";
    notices.push({ kind: "retired", path: shown, value, destination: to, text: `${shown} ${status}${value ? ` (it sets medium: ${value})` : ""}; set it in ${to} instead${caveat}${perUser}` });
  }
  if (state && changed) {
    try {
      writeAtomic(state, `${JSON.stringify(seen)}\n`);
    } catch {
    }
  }
  return notices;
}

/** True when the reader chose a publishing medium (the argument, or a trusted scope), which the publish gate takes as explicit: never the plugin default. */
export const gateExplicit = ({ preferred, decidedBy }) => Boolean(mediumOf(preferred)?.publishes) && ["argument", "userConfig", "personal override"].includes(decidedBy);

/**
 * @param {{producer: string, argument?: string|null, userConfig?: string|null, projectRoot?: string|null, teamRef?: string|null}} request
 * @param {{userHome?: string, dataDir?: string|null, interactive?: boolean}} [options]
 * @returns {{preferred: string|null, medium: string|null, decidedBy: string, notices: {kind: string, text: string}[]}}
 */
export function resolveMedium({ producer, argument = null, userConfig = null, projectRoot = null, teamRef = null }, { userHome = homedir(), dataDir = null, interactive = true } = {}) {
  const producerEntry = producerOf(producer);
  if (!producerEntry) throw new Error(`view-settings: unknown producer ${JSON.stringify(producer)}`);
  const notices = [];
  const root = repoScopes(projectRoot, userHome) ? projectRoot : null;
  const team = root && typeof teamRef === "string" ? teamAt(root, teamRef, notices) : undefined;
  const { layers, legacy } = readLayers({ plugin: CONCERN, projectRoot: root, schema: SCHEMA, userConfig: { medium: userConfig ?? "" }, team, userHome });
  notices.unshift(...retiredNotices(legacy, { plugin: producer.split(":")[0], hasMediumOption: producerEntry.hasMediumOption, root, userHome, dataDir }));
  const finish = (preferred, decidedBy) => {
    if (!preferred) return { preferred: null, medium: null, decidedBy, notices };
    const { medium, fell } = fallBack(preferred, producerEntry, { interactive });
    return { preferred, medium, decidedBy: fell ? `fell back: ${fell}` : decidedBy, notices };
  };
  if (mediumOf(argument)) return finish(argument, "argument");

  const shown = (path) => (path && root && isAbsolute(path) ? relative(root, path).split("\\").join("/") : path);
  for (const layer of layers) {
    const prefix = `${layer.name}${layer.path ? ` (${layer.path})` : ""}: `;
    const where = `${layer.name === "local" ? "personal override" : layer.name}${layer.path ? ` ${shown(layer.path)}` : ""}`;
    layer.errors.forEach((error, i) => {
      const key = layer.error_keys?.[i];
      if (typeof key === "string" && (key === "branding" || key.startsWith("branding."))) return;
      notices.push({ kind: "invalid", text: `${where}: ${error.startsWith(prefix) ? error.slice(prefix.length) : error}; ignored` });
    });
  }
  const valueOf = (name) => layers.find((l) => l.name === name)?.values.medium;
  const personal = valueOf("local");
  let personalTrusted = false;
  if (personal && mediumOf(personal)?.publishes) {
    const warnings = [];
    const personalPath = layers.find((l) => l.name === "local").path;
    const checkout = resolve(personalPath, ...PERSONAL_FILE.split("/").map(() => ".."));
    personalTrusted = personalOverrideApplies(checkout, personalPath, warnings, { requireIgnored: true });
    for (const w of warnings) notices.push({ kind: "ignored", text: w });
  }
  const scopes = [
    ["personal override", personal, personalTrusted],
    ["team", valueOf("team"), false],
    ["userConfig", valueOf("userConfig"), true],
  ].filter(([, medium]) => medium && medium !== NO_PREFERENCE);
  const local = scopes.find(([, medium]) => !mediumOf(medium).publishes);
  if (local) return finish(local[1], local[0]);
  const retired = retiredLocal(legacy);
  if (retired) return finish(retired.value, `retired ${retiredWhere(retired.path, root, userHome)}`);
  const teamValue = scopes.find(([name]) => name === "team")?.[1];
  if (teamValue) notices.push({ kind: "ignored", text: `team ${shown(layers.find((l) => l.name === "team").path)} sets medium: ${teamValue}; a team file never publishes, so it is ignored` });
  const trusted = scopes.find(([, , ok]) => ok);
  return trusted ? finish(trusted[1], trusted[0]) : finish(producerEntry.default, "plugin default");
}

const HEX_COLOR = /^#[0-9A-Fa-f]{6}$/;
const FONT_NAME = /^[A-Za-z0-9][A-Za-z0-9 _-]{0,63}$/;
const FONT_QUOTED = /^'[A-Za-z0-9][A-Za-z0-9 _-]{0,63}'$/;
const FONT_WEIGHT = /^(?:normal|bold|[1-9]00(?: [1-9]00)?)$/;
const FONT_STACK_MAX = 256;
const LABEL_MAX = 80;
const MAX_ASSET_BYTES = 5 * 1024 * 1024;
const MAX_SVG_BYTES = 256 * 1024;
const RESERVED_KEYS = new Set(["__proto__", "constructor", "prototype"]);
const SCHEMES = ["light", "dark"];
const CONTRAST_FG_ROLES = [
  ["fg", 4.5],
  ["muted", 4.5],
  ["link", 4.5],
  ["focus", 3],
];
const CONTRAST_SURFACES = ["bg", "panel"];

const SVG_TAGS = new Set([
  "svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
  "text", "tspan", "desc", "defs", "lineargradient", "radialgradient", "stop",
  "marker", "clippath", "mask", "pattern",
]);
const SVG_ATTRS = new Set([
  "class", "id", "title", "role", "href", "xlink:href",
  "xmlns", "viewbox", "width", "height", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy",
  "r", "rx", "ry", "d", "points", "fill", "stroke", "stroke-width", "stroke-linecap",
  "stroke-linejoin", "stroke-dasharray", "opacity", "fill-opacity", "stroke-opacity",
  "transform", "text-anchor", "dominant-baseline", "font-size", "font-weight",
  "offset", "stop-color", "stop-opacity", "gradientunits", "gradienttransform",
  "marker-start", "marker-mid", "marker-end", "markerwidth", "markerheight", "refx",
  "refy", "orient", "markerunits", "clip-path", "mask", "preserveaspectratio",
  "focusable", "patternunits",
]);
const SVG_ARIA = /^aria-[a-z0-9-]+$/;
const SVG_KEY = /^[a-z0-9-]{1,32}$/;
const SVG_FRAGMENT = /^#[a-z0-9-]{1,32}$/;
const SVG_URL_FRAGMENT = /^url\(#[a-z0-9-]{1,32}\)$/;
const ESCAPED_TEXT = /^(?:[^&<>"']|&(?:amp|lt|gt|quot|#x27);)*$/;

const isMapping = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const isHex = (v) => typeof v === "string" && HEX_COLOR.test(v);

function validFontStack(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > FONT_STACK_MAX || /[\r\n]/.test(value)) return null;
  const parts = value.split(",").map((p) => p.trim());
  if (!parts.length || parts.some((p) => !FONT_NAME.test(p) && !FONT_QUOTED.test(p))) return null;
  return parts.join(", ");
}

function validLabel(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed || [...trimmed].length > LABEL_MAX || /[\p{Cc}\p{Cf}]/u.test(trimmed)) return null;
  return trimmed;
}

function detectImageMediaType(buf) {
  if (buf.length >= 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47 && buf[4] === 0x0d && buf[5] === 0x0a && buf[6] === 0x1a && buf[7] === 0x0a) {
    return "image/png";
  }
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
    return "image/jpeg";
  }
  return null;
}

function detectFontFormat(buf) {
  if (buf.length < 4) return null;
  const tag = buf.subarray(0, 4).toString("ascii");
  if (tag === "wOF2") return { mediaType: "font/woff2", format: "woff2" };
  if (tag === "wOFF") return { mediaType: "font/woff", format: "woff" };
  if (tag === "OTTO") return { mediaType: "font/otf", format: "opentype" };
  if (tag === "true" || (buf[0] === 0x00 && buf[1] === 0x01 && buf[2] === 0x00 && buf[3] === 0x00)) {
    return { mediaType: "font/ttf", format: "truetype" };
  }
  return null;
}

function parseSvgAttributes(raw) {
  const attrs = [];
  const token = /\s*([^\s"'>=/]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/gy;
  let pos = 0;
  while (pos < raw.length) {
    const rest = raw.slice(pos);
    if (/^\s*$/.test(rest)) break;
    token.lastIndex = pos;
    const m = token.exec(raw);
    if (!m) return null;
    attrs.push({ name: m[1].toLowerCase(), value: m[2] ?? m[3] ?? m[4] ?? "" });
    pos = token.lastIndex;
  }
  return attrs;
}

/** Validates inline SVG against the builder's SVG allowlist (`lib/view-builder.mjs` / rendered-views rule 6). */
export function validateSvgLogo(raw) {
  if (typeof raw !== "string") return { ok: false, reason: "must be a string" };
  const svg = raw.replace(/\r\n?/g, "\n").trim();
  if (!svg) return { ok: false, reason: "is empty" };
  if (Buffer.byteLength(svg, "utf8") > MAX_SVG_BYTES) return { ok: false, reason: `exceeds ${MAX_SVG_BYTES} bytes` };
  if (/<!--|<\?|<!/i.test(svg)) return { ok: false, reason: "comments, processing instructions and declarations are refused" };
  const tagRe = /<(\/?)([A-Za-z][A-Za-z0-9]*)([^>]*?)(\/?)>/g;
  const stack = [];
  let cursor = 0;
  let rootDone = false;
  for (const m of svg.matchAll(tagRe)) {
    const text = svg.slice(cursor, m.index);
    if (text.includes("<") || text.includes(">")) return { ok: false, reason: "raw angle bracket in text" };
    if (stack.length === 0 && text.trim()) return { ok: false, reason: "unexpected text outside root <svg>" };
    if (!ESCAPED_TEXT.test(text)) return { ok: false, reason: "unescaped text" };
    if (rootDone) return { ok: false, reason: "multiple root elements" };
    cursor = m.index + m[0].length;
    const closing = m[1] === "/";
    const tag = m[2].toLowerCase();
    const attrRaw = m[3];
    const selfClosing = m[4] === "/";
    if (!SVG_TAGS.has(tag)) return { ok: false, reason: `disallowed SVG tag <${tag}>` };
    if (closing) {
      if (selfClosing || attrRaw.trim()) return { ok: false, reason: `malformed closing tag </${tag}>` };
      if (stack.pop() !== tag) return { ok: false, reason: `unbalanced closing tag </${tag}>` };
      if (stack.length === 0) rootDone = true;
      continue;
    }
    if (stack.length === 0 && tag !== "svg") return { ok: false, reason: `root element must be <svg>, got <${tag}>` };
    if (attrRaw.length > 0 && !/^\s/.test(attrRaw)) return { ok: false, reason: `malformed attributes on <${tag}>` };
    const attrs = parseSvgAttributes(attrRaw);
    if (!attrs) return { ok: false, reason: `malformed attributes on <${tag}>` };
    for (const { name, value } of attrs) {
      if (!SVG_ATTRS.has(name) && !SVG_ARIA.test(name)) return { ok: false, reason: `disallowed SVG attribute ${name}` };
      if (!ESCAPED_TEXT.test(value)) return { ok: false, reason: `unescaped attribute ${name}` };
      if (name === "xmlns" && value !== "http://www.w3.org/2000/svg") return { ok: false, reason: "disallowed xmlns value" };
      if (name === "id" && (!SVG_KEY.test(value) || value === "rv-data")) return { ok: false, reason: `invalid id ${JSON.stringify(value)}` };
      if ((name === "href" || name === "xlink:href") && !SVG_FRAGMENT.test(value)) return { ok: false, reason: `disallowed ${name} value` };
      if (/url\(/i.test(value) && !SVG_URL_FRAGMENT.test(value)) return { ok: false, reason: `disallowed url() in ${name}` };
    }
    if (!selfClosing) stack.push(tag);
    else if (stack.length === 0) rootDone = true;
  }
  const tail = svg.slice(cursor);
  if (tail.includes("<") || tail.includes(">") || tail.trim()) return { ok: false, reason: "trailing content after </svg>" };
  if (stack.length > 0 || !rootDone) return { ok: false, reason: "unclosed or missing <svg> element" };
  return { ok: true, svg };
}

function cleanRepoRelative(rawPath) {
  if (typeof rawPath !== "string" || !rawPath || rawPath.includes("\0") || rawPath.includes("\\")) return null;
  if (rawPath.startsWith("/") || rawPath.startsWith("~") || /^[A-Za-z]:/.test(rawPath)) return null;
  const parts = rawPath.split("/");
  if (parts.some((p) => p === "" || p === "." || p === "..")) return null;
  return parts.join("/");
}

function readDiskRegularFile(target, boundary, maxBytes) {
  if (boundary) {
    const rel = relative(boundary, target).split("\\").join("/");
    if (!rel || rel.startsWith("..") || isAbsolute(rel)) return { error: "path escapes allowed root" };
    const segments = rel.split("/");
    for (let i = 0; i < segments.length; i += 1) {
      if (isLink(join(boundary, ...segments.slice(0, i + 1)))) return { error: "symlinks are refused" };
    }
  }
  let st;
  try {
    st = lstatSync(target);
  } catch {
    return { error: "file not found" };
  }
  if (st.isSymbolicLink()) return { error: "symlinks are refused" };
  if (!st.isFile()) return { error: "not a regular file" };
  if (boundary && !within(real(target), real(boundary))) return { error: "path resolves outside repository" };
  if (st.size === 0) return { error: "file is empty" };
  if (st.size > maxBytes) return { error: `file exceeds ${maxBytes} bytes` };
  try {
    return { bytes: readFileSync(target) };
  } catch {
    return { error: "file cannot be read" };
  }
}

function readGitBlob(root, sha, relPath, maxBytes) {
  const tree = gitOut(root, ["ls-tree", sha, "--", relPath]);
  if (!tree) return { error: `not found at commit ${sha.slice(0, 12)}` };
  const line = tree.trimEnd().split("\n")[0];
  const match = /^([0-9]{6}) blob [0-9a-f]{40}\t(.+)$/.exec(line);
  if (!match || match[2] !== relPath) return { error: `not a regular blob at commit ${sha.slice(0, 12)}` };
  if (match[1] !== "100644" && match[1] !== "100755") return { error: `symlink or special mode ${match[1]} refused at commit ${sha.slice(0, 12)}` };
  try {
    const bytes = execFileSync("git", ["-C", root, "show", `${sha}:${relPath}`], { stdio: ["ignore", "pipe", "ignore"], maxBuffer: maxBytes + 1024 });
    if (bytes.length === 0) return { error: "file is empty" };
    if (bytes.length > maxBytes) return { error: `file exceeds ${maxBytes} bytes` };
    return { bytes };
  } catch {
    return { error: `cannot read blob at commit ${sha.slice(0, 12)}` };
  }
}

function readAssetBytes({ rawPath, layerName, root, checkout, personalTrusted, teamSha, userHome, maxBytes = MAX_ASSET_BYTES }) {
  if (typeof rawPath !== "string" || !rawPath.trim() || rawPath.includes("\0") || /[\p{Cc}]/u.test(rawPath)) {
    return { error: "invalid file path" };
  }
  if (layerName === "team") {
    const rel = cleanRepoRelative(rawPath);
    if (!rel) return { error: "team asset path must be repository-relative with no .. segment" };
    if (teamSha !== undefined) return teamSha ? readGitBlob(root, teamSha, rel, maxBytes) : { error: "team ref names no commit" };
    return readDiskRegularFile(join(root, rel), root, maxBytes);
  }
  if (layerName === "local") {
    const external = rawPath.startsWith("~/") || isAbsolute(rawPath);
    if (external) {
      if (!personalTrusted) return { error: "external asset path requires an untracked, gitignored personal override" };
      const resolved = rawPath.startsWith("~/") ? join(userHome, rawPath.slice(2)) : rawPath;
      return readDiskRegularFile(resolved, null, maxBytes);
    }
    const rel = cleanRepoRelative(rawPath);
    if (!rel) return { error: "relative asset path may not contain .. or backslashes" };
    return readDiskRegularFile(join(checkout, rel), checkout, maxBytes);
  }
  if (layerName === "userConfig") {
    if (!rawPath.startsWith("~/") && !isAbsolute(rawPath)) return { error: "userConfig asset path must be absolute or start with ~/" };
    const resolved = rawPath.startsWith("~/") ? join(userHome, rawPath.slice(2)) : rawPath;
    return readDiskRegularFile(resolved, null, maxBytes);
  }
  return { error: "unsupported layer" };
}

function parseUserConfigBranding(raw, notices) {
  if (raw === undefined || raw === null || raw === "") return {};
  if (typeof raw === "string" && raw.startsWith("${user_config.")) return {};
  let parsed = raw;
  if (typeof raw === "string") {
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      notices.push({ kind: "invalid", text: `userConfig branding: invalid JSON (${e.message}); ignored` });
      return {};
    }
  }
  if (!isMapping(parsed)) {
    notices.push({ kind: "invalid", text: "userConfig branding: expected a JSON object; ignored" });
    return {};
  }
  const values = {};
  const walk = (obj, node, parts) => {
    for (const key of Object.keys(obj)) {
      const dotted = [...parts, key].join(".");
      if (RESERVED_KEYS.has(key)) {
        notices.push({ kind: "invalid", text: `userConfig: ${JSON.stringify(dotted)}: a reserved name, never a config key; ignored` });
        continue;
      }
      const sub = isMapping(node.properties) && Object.hasOwn(node.properties, key) ? node.properties[key] : false;
      if (sub === false) {
        notices.push({ kind: "invalid", text: `userConfig: ${JSON.stringify(dotted)}: unknown key; ignored` });
        continue;
      }
      const val = obj[key];
      if (sub.type === "object" && isMapping(sub.properties)) {
        if (isMapping(val)) walk(val, sub, [...parts, key]);
        else if (val !== null) notices.push({ kind: "invalid", text: `userConfig: ${JSON.stringify(dotted)}: expected an object; ignored` });
      } else if (sub.type === "array") {
        if (Array.isArray(val)) values[dotted] = val;
        else notices.push({ kind: "invalid", text: `userConfig: ${JSON.stringify(dotted)}: expected an array; ignored` });
      } else if (sub.type === "string") {
        if (typeof val === "string") values[dotted] = val;
        else notices.push({ kind: "invalid", text: `userConfig: ${JSON.stringify(dotted)}: expected string; ignored` });
      }
    }
  };
  walk(parsed, BRANDING_SCHEMA, ["branding"]);
  return values;
}

/** Relative luminance per W3C WCAG 2.1 for a six-digit `#RRGGBB` hex color. */
function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const s = parseInt(hex.slice(i, i + 2), 16) / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG 2.1 contrast ratio (1 to 21) between two six-digit `#RRGGBB` hex colors. */
export function contrastRatio(hexA, hexB) {
  const [hi, lo] = [luminance(hexA), luminance(hexB)].sort((a, b) => b - a);
  return (hi + 0.05) / (lo + 0.05);
}

function enforceContrastFloor(palette, sources, notices) {
  for (const scheme of SCHEMES) {
    let changed = true;
    while (changed) {
      changed = false;
      for (const [role, min] of CONTRAST_FG_ROLES) {
        const key = `palette.${scheme}.${role}`;
        if (sources[key] === "default") continue;
        for (const surface of CONTRAST_SURFACES) {
          const ratio = contrastRatio(palette[scheme][role], palette[scheme][surface]);
          if (ratio < min) {
            palette[scheme][role] = SHIPPED_TOKENS.palette[scheme][role];
            sources[key] = "default";
            notices.push({
              kind: "contrast",
              role,
              scheme,
              pair: `${role} on ${surface}`,
              ratio: Number(ratio.toFixed(2)),
              minimum: min,
              text: `${scheme} ${role}: pair ${role} on ${surface} has contrast ${ratio.toFixed(2)}:1 (below ${min}:1 floor); keeping shipped value`,
            });
            changed = true;
            break;
          }
        }
      }
      for (const surface of CONTRAST_SURFACES) {
        const key = `palette.${scheme}.${surface}`;
        if (sources[key] === "default") continue;
        for (const [role, min] of CONTRAST_FG_ROLES) {
          const ratio = contrastRatio(palette[scheme][role], palette[scheme][surface]);
          if (ratio < min) {
            palette[scheme][surface] = SHIPPED_TOKENS.palette[scheme][surface];
            sources[key] = "default";
            notices.push({
              kind: "contrast",
              role: surface,
              scheme,
              pair: `${role} on ${surface}`,
              ratio: Number(ratio.toFixed(2)),
              minimum: min,
              text: `${scheme} ${surface}: pair ${role} on ${surface} has contrast ${ratio.toFixed(2)}:1 (below ${min}:1 floor); keeping shipped value`,
            });
            changed = true;
            break;
          }
        }
      }
    }
  }
}

function buildBrandingCss(palette, type, logo, sources) {
  const blocks = [];
  for (const font of type.fonts) {
    blocks.push(`@font-face { font-family: '${font.family}'; font-style: ${font.style}; font-weight: ${font.weight}; src: url(${font.dataUrl}) format('${font.format}'); }`);
  }
  const lightDecls = [];
  for (const role of PALETTE_ROLES) {
    if (sources[`palette.light.${role}`] !== "default") lightDecls.push(`--${role}: ${palette.light[role]};`);
  }
  for (const stack of TYPE_STACKS) {
    if (sources[`type.${stack}`] !== "default") lightDecls.push(`--${stack}: ${type[stack]};`);
  }
  if (lightDecls.length) blocks.push(`:root { ${lightDecls.join(" ")} }`);
  const darkDecls = [];
  for (const role of PALETTE_ROLES) {
    if (sources[`palette.dark.${role}`] !== "default") darkDecls.push(`--${role}: ${palette.dark[role]};`);
  }
  if (darkDecls.length) {
    const body = darkDecls.join(" ");
    blocks.push(`@media (prefers-color-scheme: dark) { :root:not([data-theme=light]) { ${body} } }`);
    blocks.push(`:root[data-theme=dark] { ${body} }`);
  }
  if (logo.kind === "image" && logo.dataUrl) {
    blocks.push(`.rv-logo { background-image: url(${logo.dataUrl}); }`);
  }
  return blocks.join("\n");
}

function validateBrandingLayer({ layerName, label, values, assetCtx, notices }) {
  const accepted = { palette: { light: {}, dark: {} }, type: {}, fonts: null, logoGraphic: null, logoLabel: null };
  for (const scheme of SCHEMES) {
    for (const role of PALETTE_ROLES) {
      const k = `branding.palette.${scheme}.${role}`;
      if (!Object.hasOwn(values, k)) continue;
      if (isHex(values[k])) accepted.palette[scheme][role] = values[k].toUpperCase();
      else notices.push({ kind: "invalid", text: `${label}: "${k}" must be a six-digit hex color (#RRGGBB); ignored` });
    }
  }
  for (const stack of TYPE_STACKS) {
    const k = `branding.type.${stack}`;
    if (!Object.hasOwn(values, k)) continue;
    const ok = validFontStack(values[k]);
    if (ok) accepted.type[stack] = ok;
    else notices.push({ kind: "invalid", text: `${label}: "${k}" contains characters outside the allowed font-family set; ignored` });
  }
  if (Object.hasOwn(values, "branding.type.fonts")) {
    const rawFonts = values["branding.type.fonts"];
    const validFonts = [];
    if (Array.isArray(rawFonts)) {
      rawFonts.forEach((entry, idx) => {
        const at = `branding.type.fonts[${idx}]`;
        if (!isMapping(entry)) {
          notices.push({ kind: "invalid", text: `${label}: "${at}" must be an object; ignored` });
          return;
        }
        for (const k of Object.keys(entry)) {
          if (!["family", "file", "weight", "style"].includes(k)) {
            notices.push({ kind: "invalid", text: `${label}: "${at}.${k}": unknown key; ignored` });
            return;
          }
        }
        if (typeof entry.family !== "string" || !FONT_NAME.test(entry.family.trim())) {
          notices.push({ kind: "invalid", text: `${label}: "${at}.family" must match the closed font-family character set; ignored` });
          return;
        }
        const weight = entry.weight === undefined ? "400" : String(entry.weight).trim();
        if (!FONT_WEIGHT.test(weight)) {
          notices.push({ kind: "invalid", text: `${label}: "${at}.weight" is not a valid CSS font-weight; ignored` });
          return;
        }
        const style = entry.style === undefined ? "normal" : entry.style;
        if (style !== "normal" && style !== "italic") {
          notices.push({ kind: "invalid", text: `${label}: "${at}.style" must be "normal" or "italic"; ignored` });
          return;
        }
        const read = readAssetBytes({ ...assetCtx, layerName, rawPath: entry.file });
        if (read.error) {
          notices.push({ kind: "invalid", text: `${label}: "${at}.file" (${read.error}); ignored` });
          return;
        }
        const font = detectFontFormat(read.bytes);
        if (!font) {
          notices.push({ kind: "invalid", text: `${label}: "${at}.file" magic bytes do not match WOFF2, WOFF, TTF or OTF; ignored` });
          return;
        }
        validFonts.push({
          family: entry.family.trim(),
          weight,
          style,
          format: font.format,
          mediaType: font.mediaType,
          dataUrl: `data:${font.mediaType};base64,${read.bytes.toString("base64")}`,
        });
      });
    }
    if (validFonts.length) accepted.fonts = validFonts;
  }
  const hasSvg = Object.hasOwn(values, "branding.logo.svg");
  const hasFile = Object.hasOwn(values, "branding.logo.file");
  if (hasSvg && hasFile) {
    notices.push({ kind: "invalid", text: `${label}: "branding.logo" cannot set both svg and file; ignored` });
  } else if (hasSvg) {
    const check = validateSvgLogo(values["branding.logo.svg"]);
    if (check.ok) accepted.logoGraphic = { kind: "svg", svg: check.svg, dataUrl: null, mediaType: "image/svg+xml" };
    else notices.push({ kind: "invalid", text: `${label}: "branding.logo.svg" refused by SVG allowlist (${check.reason}); ignored` });
  } else if (hasFile) {
    const read = readAssetBytes({ ...assetCtx, layerName, rawPath: values["branding.logo.file"] });
    if (read.error) {
      notices.push({ kind: "invalid", text: `${label}: "branding.logo.file" (${read.error}); ignored` });
    } else {
      const mediaType = detectImageMediaType(read.bytes);
      if (mediaType) {
        accepted.logoGraphic = { kind: "image", svg: null, dataUrl: `data:${mediaType};base64,${read.bytes.toString("base64")}`, mediaType };
      } else if (!read.bytes.includes(0) && read.bytes.toString("utf8").trimStart().startsWith("<svg")) {
        const check = validateSvgLogo(read.bytes.toString("utf8"));
        if (check.ok) accepted.logoGraphic = { kind: "svg", svg: check.svg, dataUrl: null, mediaType: "image/svg+xml" };
        else notices.push({ kind: "invalid", text: `${label}: "branding.logo.file" SVG refused by allowlist (${check.reason}); ignored` });
      } else {
        notices.push({ kind: "invalid", text: `${label}: "branding.logo.file" magic bytes do not match PNG, JPEG or SVG; ignored` });
      }
    }
  }
  if (Object.hasOwn(values, "branding.logo.label")) {
    const ok = validLabel(values["branding.logo.label"]);
    if (ok) accepted.logoLabel = ok;
    else notices.push({ kind: "invalid", text: `${label}: "branding.logo.label" must be non-empty plain text of at most ${LABEL_MAX} characters; ignored` });
  }
  return accepted;
}

/**
 * Resolves `branding` in plain ADR 0075 order: personal override, then team, then `userConfig`,
 * then shipped defaults, validating every value per layer and enforcing the WCAG 2.1 contrast floor.
 * @param {{userConfig?: string|object|null, projectRoot?: string|null, teamRef?: string|null}} [request]
 * @param {{userHome?: string}} [options]
 */
export function resolveBranding({ userConfig = null, projectRoot = null, teamRef = null } = {}, { userHome = homedir() } = {}) {
  const notices = [];
  const root = repoScopes(projectRoot, userHome) ? projectRoot : null;
  const team = root && typeof teamRef === "string" ? teamAt(root, teamRef, notices) : undefined;
  const { layers } = readLayers({ plugin: CONCERN, projectRoot: root, schema: SCHEMA, team, userHome });
  const shown = (path) => (path && root && isAbsolute(path) ? relative(root, path).split("\\").join("/") : path);
  for (const layer of layers) {
    const prefix = `${layer.name}${layer.path ? ` (${layer.path})` : ""}: `;
    const where = `${layer.name === "local" ? "personal override" : layer.name}${layer.path ? ` ${shown(layer.path)}` : ""}`;
    layer.errors.forEach((error, i) => {
      const key = layer.error_keys?.[i];
      if (key === "medium") return;
      notices.push({ kind: "invalid", text: `${where}: ${error.startsWith(prefix) ? error.slice(prefix.length) : error}; ignored` });
    });
  }
  const userValues = parseUserConfigBranding(userConfig, notices);
  const localLayer = layers.find((l) => l.name === "local");
  const teamLayer = layers.find((l) => l.name === "team");
  const checkout = localLayer?.path ? resolve(localLayer.path, ...PERSONAL_FILE.split("/").map(() => "..")) : root;
  const personalTrusted = Boolean(localLayer?.path && localLayer.state === "loaded" && personalOverrideApplies(checkout, localLayer.path, [], { requireIgnored: true }));
  const assetCtx = { root, checkout, personalTrusted, teamSha: team ? team.sha : undefined, userHome };

  const ordered = [
    { layerName: "userConfig", sourceName: "userConfig", label: "userConfig", values: userValues },
    ...(teamLayer ? [{ layerName: "team", sourceName: "team", label: `team ${shown(teamLayer.path)}`, values: teamLayer.values }] : []),
    ...(localLayer ? [{ layerName: "local", sourceName: "personal override", label: `personal override ${shown(localLayer.path)}`, values: localLayer.values }] : []),
  ];

  const palette = {
    light: { ...SHIPPED_TOKENS.palette.light },
    dark: { ...SHIPPED_TOKENS.palette.dark },
  };
  const type = { ...SHIPPED_TOKENS.type, fonts: [] };
  const logo = { kind: null, svg: null, dataUrl: null, mediaType: null, label: null };
  const sources = {};
  for (const scheme of SCHEMES) for (const role of PALETTE_ROLES) sources[`palette.${scheme}.${role}`] = "default";
  for (const stack of TYPE_STACKS) sources[`type.${stack}`] = "default";
  sources["type.fonts"] = "default";
  sources["logo.graphic"] = "default";
  sources["logo.label"] = "default";

  for (const layer of ordered) {
    const accepted = validateBrandingLayer({ ...layer, assetCtx, notices });
    for (const scheme of SCHEMES) {
      for (const role of PALETTE_ROLES) {
        if (Object.hasOwn(accepted.palette[scheme], role)) {
          palette[scheme][role] = accepted.palette[scheme][role];
          sources[`palette.${scheme}.${role}`] = layer.sourceName;
        }
      }
    }
    for (const stack of TYPE_STACKS) {
      if (Object.hasOwn(accepted.type, stack)) {
        type[stack] = accepted.type[stack];
        sources[`type.${stack}`] = layer.sourceName;
      }
    }
    if (accepted.fonts) {
      type.fonts = accepted.fonts;
      sources["type.fonts"] = layer.sourceName;
    }
    if (accepted.logoGraphic) {
      logo.kind = accepted.logoGraphic.kind;
      logo.svg = accepted.logoGraphic.svg;
      logo.dataUrl = accepted.logoGraphic.dataUrl;
      logo.mediaType = accepted.logoGraphic.mediaType;
      sources["logo.graphic"] = layer.sourceName;
    }
    if (accepted.logoLabel) {
      logo.label = accepted.logoLabel;
      sources["logo.label"] = layer.sourceName;
    }
  }

  enforceContrastFloor(palette, sources, notices);

  const overrides = { palette: { light: {}, dark: {} }, type: {}, logo: null };
  for (const scheme of SCHEMES) {
    for (const role of PALETTE_ROLES) {
      if (sources[`palette.${scheme}.${role}`] !== "default") overrides.palette[scheme][role] = palette[scheme][role];
    }
  }
  for (const stack of TYPE_STACKS) {
    if (sources[`type.${stack}`] !== "default") overrides.type[stack] = type[stack];
  }
  if (type.fonts.length) overrides.type.fonts = type.fonts;
  if (logo.kind || logo.label) overrides.logo = { ...logo };

  const css = buildBrandingCss(palette, type, logo, sources);
  return { palette, type, logo, sources, overrides, css, notices };
}

/** Human-readable lines for a resolved branding result: each overridden key with its layer, then notices. */
export function brandingReportLines({ sources, notices = [] }) {
  const overridden = Object.entries(sources).filter(([, layer]) => layer !== "default");
  const summary = overridden.length ? overridden.map(([key, layer]) => `branding: ${key} (${layer})`) : ["branding: default (shipped tokens)"];
  return [...summary, ...notices.map((n) => `notice: ${n.text}`)];
}

const USAGE =
  "usage: view-settings.mjs resolve --producer <id> --option <user_config.medium> [--argument <medium>] [--team-ref <ref>] [--branding-option <user_config.branding>]\n" +
  "       view-settings.mjs branding [--option <user_config.branding>] [--team-ref <ref>]\n";

/** CLI: the argument vector after the script path; returns the exit code. */
export function main(argv, env = process.env) {
  const [action, ...rest] = argv;
  if (action === "branding") {
    const request = { userConfig: null, teamRef: null };
    const flags = { "--option": "userConfig", "--team-ref": "teamRef" };
    for (let i = 0; i < rest.length; i += 2) {
      const key = flags[rest[i]];
      if (!key || rest[i + 1] === undefined) return usage();
      request[key] = rest[i + 1];
    }
    const resolution = resolveBranding({ ...request, projectRoot: findRoot() });
    process.stdout.write(`${JSON.stringify(resolution)}\n${brandingReportLines(resolution).join("\n")}\n`);
    return 0;
  }
  const request = { producer: null, userConfig: undefined, argument: null, teamRef: null, brandingUserConfig: undefined };
  const flags = {
    "--producer": "producer",
    "--option": "userConfig",
    "--argument": "argument",
    "--team-ref": "teamRef",
    "--branding-option": "brandingUserConfig",
  };
  for (let i = 0; i < rest.length; i += 2) {
    const key = flags[rest[i]];
    if (!key || rest[i + 1] === undefined) return usage();
    request[key] = rest[i + 1];
  }
  if (action !== "resolve" || !producerOf(request.producer) || request.userConfig === undefined) return usage();
  if (request.argument === NO_PREFERENCE) request.argument = null;
  if (request.argument !== null && !mediumOf(request.argument)) return usage();
  const ci = Boolean(env.CI) && env.CI !== "false";
  const projectRoot = findRoot();
  const resolution = resolveMedium({ ...request, projectRoot }, { dataDir: env.CLAUDE_PLUGIN_DATA || null, interactive: !ci });
  const entry = mediumOf(resolution.medium);
  const shown = entry ? { ...resolution, page: entry.id !== NO_PAGE, publishes: entry.publishes } : { ...resolution };
  let report = reportLines(resolution);
  if (request.brandingUserConfig !== undefined) {
    const branding = resolveBranding({ userConfig: request.brandingUserConfig, projectRoot, teamRef: request.teamRef });
    shown.branding = branding;
    const seen = new Set(resolution.notices.map((n) => n.text));
    for (const n of branding.notices) {
      if (!seen.has(n.text)) report.push(`notice: ${n.text}`);
    }
  }
  process.stdout.write(`${JSON.stringify(shown)}\n${report.join("\n")}\n`);
  return 0;
}

function usage() {
  process.stderr.write(USAGE);
  return 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
