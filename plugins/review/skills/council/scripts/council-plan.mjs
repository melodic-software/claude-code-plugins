#!/usr/bin/env node
// council-plan.mjs: the deterministic half of /review:council.
//
//   config --root <dir> [--ref <ref>] [--user-file <json>]
//     Resolves the council keys (default < user option < docs/conventions/review.yaml, per key)
//     and prints {lanes, max_rounds, scores, members, panel, rules} each as {value, layer}, plus
//     needs_risk, read_at and problems. With --ref the repository file is read from that ref's
//     committed copy. The user file holds the plugin's option values as given: scalars, and
//     JSON text (or an already-parsed value) for council_members, council_panel, council_rules.
//
//   select --config <json file> --changed <paths file> --tier <t> --tier-reason <r>
//          --risk <LEVEL|unrated> --risk-reason <r> --round <n> --dirty <true|false>
//          [--claude-version <x.y.z>]
//     Picks the panel: the first rule whose every term matches, else the panel, else every
//     catalog member. Each member gets a route and a status; a member its adapter cannot run as
//     written is skipped with the reason, never replaced. Skips come from adapters/<provider>.yaml.
//
// Exit 0 with JSON on stdout; 2 with one stderr line on a usage error.
import { spawnSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { validateData } from "../../../lib/setup-apply.mjs";
import { parse } from "../../../lib/yaml-subset.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SKILL = join(HERE, "..");
const SCHEMA = join(SKILL, "..", "..", "schemas", "review.schema.json");
const FILE = "docs/conventions/review.yaml";
const KEYS = { lanes: "council_lanes", max_rounds: "council_max_rounds", scores: "council_scores", members: "council_members", panel: "council_panel", rules: "council_rules" };
const STRUCTURED = new Set(["council_members", "council_panel", "council_rules"]);
export const DEFAULTS = {
  council_lanes: "off",
  council_max_rounds: 1,
  council_scores: "off",
  council_members: {
    correctness: { provider: "claude", model: "opus", brief: "correctness" },
    design: { provider: "claude", model: "opus", brief: "design" },
    adversarial: { provider: "claude", model: "opus", brief: "adversarial" },
  },
  council_panel: null,
  council_rules: [],
};
const RISK = ["LOW", "MEDIUM", "HIGH", "CRITICAL"];

const usage = (msg) => {
  process.stderr.write(`council-plan.mjs: ${msg}\n`);
  process.exit(2);
};
function flags(argv, known) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const name = argv[i].replace(/^--/, "");
    if (!argv[i].startsWith("--") || !known.includes(name)) usage(`unknown argument ${JSON.stringify(argv[i])}`);
    if (i + 1 >= argv.length) usage(`--${name} needs a value`);
    out[name] = argv[++i];
  }
  return out;
}
const readYaml = (path) => parse(readFileSync(path, "utf8"));
const councilSpecs = () => {
  const props = JSON.parse(readFileSync(SCHEMA, "utf8")).properties;
  return Object.fromEntries(Object.values(KEYS).map((k) => [k, props[k]]));
};

// The repository layer: { doc, read_at, problems } with doc null when absent or skipped.
function repositoryLayer(root, ref) {
  const real = realpathSync(root);
  const home = homedir();
  if (real === home || home.startsWith(real + sep)) return { doc: null, read_at: `none (${real} is $HOME or an ancestor of it)`, problems: [] };
  let text;
  let readAt;
  if (ref !== undefined) {
    if (!/^[A-Za-z0-9._/-]+$/.test(ref) || ref.startsWith("-") || ref.includes("..")) {
      return { doc: null, read_at: `none (ref ${JSON.stringify(ref)} is outside the allowed characters)`, problems: [] };
    }
    const sha = spawnSync("git", ["-C", real, "rev-parse", "--verify", "--quiet", `${ref}^{commit}`], { encoding: "utf8" });
    if (sha.status !== 0) return { doc: null, read_at: `none (${ref} does not exist)`, problems: [] };
    readAt = `${ref} (${sha.stdout.trim()})`;
    const entry = spawnSync("git", ["-C", real, "ls-tree", ref, "--", FILE], { encoding: "utf8" }).stdout.trim();
    if (entry === "") return { doc: null, read_at: `${readAt}, no ${FILE}`, problems: [] };
    if (!/^100(644|755) blob /.test(entry)) return { doc: null, read_at: readAt, problems: [`${FILE}: the committed entry is not a regular file; repository layer dropped`] };
    const shown = spawnSync("git", ["-C", real, "show", `${ref}:${FILE}`], { encoding: "utf8" });
    if (shown.status !== 0) return { doc: null, read_at: `${readAt}, no ${FILE}`, problems: [] };
    text = shown.stdout;
  } else {
    const path = join(real, FILE);
    if (!existsSync(path)) return { doc: null, read_at: `working tree, no ${FILE}`, problems: [] };
    // A symlink, or a path that resolves elsewhere through a linked directory, is refused (config.md "Resolution").
    const stat = lstatSync(path);
    if (stat.isSymbolicLink() || realpathSync(path) !== path || !stat.isFile()) {
      return { doc: null, read_at: "working tree", problems: [`${FILE}: not a regular file inside the repository; repository layer dropped`] };
    }
    text = readFileSync(path, "utf8");
    readAt = "working tree";
  }
  try {
    return { doc: parse(text) ?? {}, read_at: readAt, problems: [] };
  } catch (e) {
    return { doc: null, read_at: readAt, problems: [`${FILE}: ${e.message}; repository layer dropped`] };
  }
}

// The user layer: council values from the option file, JSON text parsed.
function userLayer(file) {
  if (file === undefined) return { doc: {}, problems: [] };
  let raw;
  try {
    raw = JSON.parse(readFileSync(file, "utf8"));
  } catch (e) {
    return { doc: {}, problems: [`user options file: ${e.message}; user layer dropped`] };
  }
  const doc = {};
  const problems = [];
  for (const k of Object.values(KEYS)) {
    let v = raw?.[k];
    if (v === undefined || v === null || v === "" || (typeof v === "string" && v.startsWith("${user_config."))) continue;
    if (k === "council_lanes") {
      problems.push("userConfig: council_lanes is repository-only; ignored");
      continue;
    }
    if (STRUCTURED.has(k) && typeof v === "string") {
      try {
        v = JSON.parse(v);
      } catch (e) {
        problems.push(`userConfig: ${k}: not JSON (${e.message}); layer dropped`);
        continue;
      }
    }
    // Option values reach the skill as text, so a whole number may arrive quoted.
    if (k === "council_max_rounds" && typeof v === "string" && /^[0-9]+$/.test(v)) v = Number(v);
    doc[k] = v;
  }
  return { doc, problems };
}

export function resolveConfig({ root, ref, userFile }) {
  const specs = councilSpecs();
  const repo = repositoryLayer(root, ref);
  const user = userLayer(userFile);
  const problems = [...repo.problems, ...user.problems];
  const layers = [
    { name: FILE, doc: repo.doc ?? {} },
    { name: "userConfig", doc: user.doc },
  ];
  // Candidates per key, highest layer first, each already checked against the schema.
  const candidates = {};
  for (const k of Object.values(KEYS)) {
    candidates[k] = [];
    for (const layer of layers) {
      if (!Object.hasOwn(layer.doc, k)) continue;
      const bad = validateData(specs[k], layer.doc[k], k);
      if (bad.length) problems.push(`${layer.name}: ${bad.join("; ")}; layer dropped for ${k}`);
      else candidates[k].push({ value: layer.doc[k], layer: layer.name });
    }
    candidates[k].push({ value: DEFAULTS[k], layer: "default" });
  }
  const out = {};
  const pick = (k, ok = () => true) => {
    for (const c of candidates[k]) {
      const why = ok(c.value);
      if (why === true) return c;
      problems.push(`${c.layer}: ${k}: ${why}; layer dropped`);
    }
    return { value: DEFAULTS[k], layer: "default" };
  };
  for (const k of ["council_lanes", "council_max_rounds", "council_scores", "council_members"]) out[k] = pick(k);
  const catalog = out.council_members.value;
  const unknown = (ids) => {
    const missing = ids.filter((id) => !Object.hasOwn(catalog, id));
    return missing.length ? `names ${missing.join(", ")}, not in the winning council_members (${out.council_members.layer})` : true;
  };
  out.council_panel = pick("council_panel", (v) => (v === null ? true : unknown(v)));
  out.council_rules = pick("council_rules", (v) => {
    for (const r of v) {
      const why = unknown(r.members);
      if (why !== true) return `rule ${r.name} ${why}`;
    }
    return true;
  });
  return {
    ...Object.fromEntries(Object.entries(KEYS).map(([short, k]) => [short, out[k]])),
    needs_risk: out.council_rules.value.some((r) => r.when.risk !== undefined),
    read_at: repo.read_at,
    problems,
  };
}

// globToRegExp: `**` any path (slashes included), `*` and `?` within one segment.
export function globToRegExp(glob) {
  let re = "";
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === "*" && glob[i + 1] === "*") {
      i++;
      if (glob[i + 1] === "/") {
        i++;
        re += "(?:.*/)?";
      } else re += ".*";
    } else if (c === "*") re += "[^/]*";
    else if (c === "?") re += "[^/]";
    else re += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  }
  return new RegExp(`^${re}$`, "u");
}

const versionAtLeast = (have, need) => {
  const a = have.split(".").map(Number);
  const b = need.split(".").map(Number);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if ((a[i] ?? 0) !== (b[i] ?? 0)) return (a[i] ?? 0) > (b[i] ?? 0);
  }
  return true;
};

export function selectPanel({ config, changed, tier, tierReason, risk, riskReason, round, dirty, claudeVersion, adaptersDir = join(SKILL, "adapters") }) {
  const catalog = config.members.value;
  const rules = config.rules.value;
  const matches = (when) =>
    (when.paths === undefined || changed.some((p) => when.paths.some((g) => globToRegExp(g).test(p)))) &&
    (when.size === undefined || when.size.includes(tier)) &&
    (when.risk === undefined || (risk !== "unrated" && RISK.indexOf(risk) >= RISK.indexOf(when.risk)));
  const rule = rules.find((r) => matches(r.when));
  const ids = rule ? rule.members : (config.panel.value ?? Object.keys(catalog));
  const flagships = readYaml(join(SKILL, "reference", "flagships.yaml"));
  const briefs = new Set(readdirSync(join(SKILL, "briefs")).filter((f) => f.endsWith(".md")).map((f) => f.slice(0, -3)));
  const members = ids.map((id) => {
    const m = catalog[id];
    const row = { id, provider: m.provider, model: null, model_from: null, brief: m.brief ?? "none", effort: null, frontier: false, route: null, status: "planned" };
    const skip = (why) => ({ ...row, status: `skipped (${why})` });
    const adapterPath = join(adaptersDir, `${m.provider}.yaml`);
    if (!/^[a-z][a-z0-9-]*$/.test(m.provider) || !existsSync(adapterPath)) return skip(`no adapter for provider ${m.provider}`);
    const a = readYaml(adapterPath);
    const sets = new Set(a.sets);
    row.route = a.kind === "agent" ? "agent" : m.brief === undefined ? "review" : "adversarial-review";
    // Model
    let model = m.model;
    if (model !== undefined) {
      if (!sets.has("model")) return skip(`a model cannot be set on ${m.provider}`);
      const flag = /^([a-z][a-z0-9-]*)\/flagship$/.exec(model);
      if (flag) {
        if (flag[1] !== m.provider) return skip(`${model} names another provider`);
        const top = flagships?.[m.provider];
        if (top === undefined || top === "unresolved") return skip(`${model} cannot be resolved yet`);
        model = top;
      }
      if (Array.isArray(a.models) && !a.models.includes(model)) {
        return skip(`${m.provider} members take a model alias (${a.models.join(", ")}), not ${model}`);
      }
      row.model = model;
      row.model_from = "member";
    } else {
      // An agent always gets a named model at dispatch, so a frontier session never makes an
      // unnamed member frontier; a script provider without one runs on its own setting.
      row.model = a.model_default === "provider" ? "provider setting" : a.model_default;
      row.model_from = a.model_default === "provider" ? "provider" : "adapter default";
    }
    row.frontier = (a.frontier ?? []).includes(model ?? a.model_default);
    // Brief
    if (m.brief !== undefined) {
      if (!sets.has("brief")) return skip(`a brief cannot be set on ${m.provider}`);
      if (!briefs.has(m.brief)) return skip(`no shipped brief named ${m.brief}`);
      if (Array.isArray(a.briefs) && !a.briefs.includes(m.brief)) return skip(`${m.provider} cannot carry the ${m.brief} brief`);
    }
    // Effort
    const effortSettable = !a.effort_min_version || Boolean(claudeVersion && versionAtLeast(claudeVersion, a.effort_min_version));
    if (m.effort !== undefined) {
      if (!sets.has("effort")) return skip(`effort cannot be set on ${m.provider}`);
      if (!effortSettable) {
        return skip(`effort cannot be set on this Claude Code version (needs ${a.effort_min_version})`);
      }
      row.effort = m.effort;
    } else row.effort = a.effort_default === "provider" || !effortSettable ? "provider setting" : a.effort_default;
    if (a.sees === "committed" && dirty) return skip("reviews committed changes only; the tree has uncommitted changes");
    if (round > 1 && !sets.has("limit-to-fix")) return skip("cannot be limited to the fix's changes");
    return row;
  });
  const planned = members.filter((m) => m.status === "planned").length;
  return {
    rule: rule ? rule.name : "fallback",
    tier: `${tier} (${tierReason})`,
    risk: risk === "unrated" ? `unrated (${riskReason})` : risk,
    members,
    planned,
    pilot: planned > 4,
  };
}

function main(argv) {
  const [verb, ...rest] = argv;
  if (verb === "config") {
    const f = flags(rest, ["root", "ref", "user-file"]);
    if (f.root === undefined) usage("config needs --root");
    return resolveConfig({ root: f.root, ref: f.ref, userFile: f["user-file"] });
  }
  if (verb === "select") {
    const f = flags(rest, ["config", "changed", "tier", "tier-reason", "risk", "risk-reason", "round", "dirty", "claude-version"]);
    for (const k of ["config", "changed", "tier", "risk", "round", "dirty"]) if (f[k] === undefined) usage(`select needs --${k}`);
    if (!["small", "medium", "large"].includes(f.tier)) usage("--tier takes small, medium or large");
    if (f.risk !== "unrated" && !RISK.includes(f.risk)) usage(`--risk takes unrated or one of ${RISK.join(", ")}`);
    if (!/^[1-9][0-9]*$/.test(f.round)) usage("--round takes a whole number of at least 1");
    if (!["true", "false"].includes(f.dirty)) usage("--dirty takes true or false");
    return selectPanel({
      config: JSON.parse(readFileSync(f.config, "utf8")),
      changed: readFileSync(f.changed, "utf8").split("\n").filter(Boolean),
      tier: f.tier,
      tierReason: f["tier-reason"] ?? "",
      risk: f.risk,
      riskReason: f["risk-reason"] ?? "",
      round: Number(f.round),
      dirty: f.dirty === "true",
      claudeVersion: f["claude-version"],
    });
  }
  usage("usage: council-plan.mjs config|select ...");
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  process.stdout.write(`${JSON.stringify(main(process.argv.slice(2)), null, 2)}\n`);
}
