#!/usr/bin/env node
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import {
  OPTION_NAMES,
  PERSONAL_YAML,
  RETIRED_PERSONAL,
  RETIRED_USER,
  addSetting,
  isValidSetting,
  parseYamlLayer,
  projectRootOf,
  userConfigLayer,
} from "../../../lib/review-digest.mjs";
import { findRoot, personalOverrideApplies } from "../../../lib/view-settings.mjs";

const USAGE = "usage: digest-migrate.mjs check|user|personal [--setting <digest option>=<value> ...] [--yes]\n";
const LIST_KEYS = ["blast_radius", "risk_paths"];

/** A retired file's settings: the valid ones, and the keys that are unknown or hold an invalid value. */
export function readRetired(path) {
  let value;
  try {
    value = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    return { error: error.message };
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return { error: "not a JSON object" };
  const settings = {};
  const bad = [];
  for (const [key, v] of Object.entries(value)) {
    if (key === "$schema") continue;
    if (isValidSetting(key, v)) settings[key] = v;
    else bad.push(key);
  }
  return { settings, bad };
}

/** The settings as review-digest YAML the team-file parser reads back: lists in block form, strings double-quoted. */
export function toYaml(settings) {
  const line = ([key, v]) => {
    if (!Array.isArray(v)) return `${key}: ${typeof v === "number" ? v : JSON.stringify(v)}`;
    return v.length ? `${key}:\n${v.map((s) => `  - ${JSON.stringify(s)}`).join("\n")}` : `${key}: []`;
  };
  return `${Object.entries(settings).map(line).join("\n")}\n`;
}

const optionValue = (key, v) => (LIST_KEYS.includes(key) ? JSON.stringify(v) : String(v));

function userRows(path, options) {
  const old = readRetired(path);
  if (old.error) return { old, rows: [] };
  const set = userConfigLayer(options);
  const rows = Object.entries(old.settings).map(([key, value]) => ({
    key,
    option: OPTION_NAMES[key],
    value: optionValue(key, value),
    done: Object.hasOwn(set, key) && isValidSetting(key, set[key]),
    holdable: !(key === "opt_in_label" && value === ""),
  }));
  return { old, rows };
}

function report(lines, code) {
  process.stdout.write(`${lines.join("\n")}\n`);
  return code;
}

function check(env) {
  const lines = [];
  if (existsSync(env.userPath)) {
    const { old, rows } = userRows(env.userPath, env.options);
    if (old.error) lines.push(`WARN ${env.userPath}: ${old.error}; fix or delete it by hand`);
    for (const key of old.bad ?? []) lines.push(`WARN ${env.userPath}: ${key} is unknown or invalid; remove it from the file before the move`);
    for (const r of rows) {
      const state = r.done ? "already set, and the option wins" : r.holdable ? `set the review plugin's ${r.option} option to ${r.value}` : `an option cannot hold an empty label; set opt_in_label: "" in ${PERSONAL_YAML} where you want it, then remove the key from the file`;
      lines.push(`WARN ${env.userPath}: ${r.key} -> ${r.option}: ${state}`);
    }
  }
  if (env.root && existsSync(join(env.root, RETIRED_PERSONAL))) {
    const refused = [];
    if (!personalOverrideApplies(env.root, join(env.root, RETIRED_PERSONAL), refused)) {
      lines.push(`INFO ${RETIRED_PERSONAL}: not read (${refused.join("; ")}), so not moved`);
    } else {
      const plan = personalPlan(env.root);
      const detail = plan.error ?? `moves ${Object.keys(plan.missing).join(", ") || "no key"} to ${PERSONAL_YAML}${plan.covered.length ? `, which already sets ${plan.covered.join(", ")}` : ""}`;
      lines.push(`WARN ${RETIRED_PERSONAL}: ${detail}`);
    }
  }
  return report(lines.length ? lines : ["INFO review-digest: no retired file"], 0);
}

/** What moving the retired personal file does: the keys the new file lacks, and the keys it already sets, which win. */
function personalPlan(root) {
  const old = readRetired(join(root, RETIRED_PERSONAL));
  if (old.error || old.bad.length) return { error: `${old.error ?? `unknown or invalid keys ${old.bad.join(", ")}`}; fix the file first` };
  const to = join(root, PERSONAL_YAML);
  const before = existsSync(to) ? readFileSync(to, "utf8") : null;
  const current = before === null ? {} : parseYamlLayer(before, "personal-override", PERSONAL_YAML, []);
  if (!current) return { error: `${PERSONAL_YAML} does not parse; fix it first` };
  const covered = Object.keys(old.settings).filter((key) => Object.hasOwn(current, key) && isValidSetting(key, current[key]));
  const missing = Object.fromEntries(Object.entries(old.settings).filter(([key]) => !covered.includes(key)));
  return { before, covered, missing };
}

function retireUser(env) {
  if (!existsSync(env.userPath)) return report([`INFO ${env.userPath}: absent`], 0);
  const { old, rows } = userRows(env.userPath, env.options);
  if (old.error || old.bad.length) return report([`${env.userPath}: ${old.error ?? `unknown or invalid keys ${old.bad.join(", ")}`}; fix the file first`], 1);
  const open = rows.filter((r) => !r.done);
  if (open.length) return report(open.map((r) => `${r.key}: ${r.holdable ? `set ${r.option} to ${r.value} with /plugin configure review, then run this again` : `move opt_in_label: "" to ${PERSONAL_YAML} and remove it from the file`}`), 4);
  if (!env.yes) return report([`every setting in ${env.userPath} is set in the review plugin's options, which win over it; rerun with --yes to delete the file`], 3);
  rmSync(env.userPath);
  return report([`deleted ${env.userPath}`], 0);
}

function movePersonal(env) {
  if (!env.root) return report(["not inside a repository working tree"], 1);
  const from = join(env.root, RETIRED_PERSONAL);
  const to = join(env.root, PERSONAL_YAML);
  if (!existsSync(from)) return report([`INFO ${RETIRED_PERSONAL}: absent`], 0);
  const refused = [];
  if (!personalOverrideApplies(env.root, from, refused)) return report([`${RETIRED_PERSONAL}: not read (${refused.join("; ")}); it is not moved`], 1);
  const plan = personalPlan(env.root);
  if (plan.error) return report([`${RETIRED_PERSONAL}: ${plan.error}`], 1);
  const added = Object.keys(plan.missing).length ? toYaml(plan.missing) : "";
  const kept = plan.covered.length ? [`${PERSONAL_YAML} already sets ${plan.covered.join(", ")}, which wins and is kept`] : [];
  if (!env.yes) {
    const head = added ? [`would ${plan.before === null ? "write" : "add to"} ${PERSONAL_YAML}:`, added.trimEnd()] : [];
    return report([...head, ...kept, `then delete ${RETIRED_PERSONAL}; rerun with --yes`], 3);
  }
  if (!added) {
    rmSync(from);
    return report([...kept, `deleted ${RETIRED_PERSONAL}`], 0);
  }
  const restore = () => (plan.before === null ? rmSync(to, { force: true }) : writeFileSync(to, plan.before));
  mkdirSync(dirname(to), { recursive: true });
  const lead = plan.before === null || plan.before === "" || plan.before.endsWith("\n") ? "" : "\n";
  writeFileSync(to, `${plan.before ?? ""}${lead}${added}`);
  const warnings = [];
  const applies = personalOverrideApplies(env.root, to, warnings, { requireIgnored: true });
  const now = parseYamlLayer(readFileSync(to, "utf8"), "personal-override", PERSONAL_YAML, warnings) ?? {};
  const differs = Object.entries(plan.missing).filter(([key, v]) => !isDeepStrictEqual(now[key], v)).map(([key]) => key);
  if (!applies || differs.length) {
    restore();
    const why = differs.length ? [`${PERSONAL_YAML} would not resolve ${differs.join(", ")} to the old values`] : [];
    return report([...why, ...warnings, `${PERSONAL_YAML} left as it was; ${RETIRED_PERSONAL} kept`], 1);
  }
  rmSync(from);
  return report([`${plan.before === null ? "wrote" : "added to"} ${PERSONAL_YAML}`, ...kept, `deleted ${RETIRED_PERSONAL}`], 0);
}

export function main(argv) {
  const [action, ...rest] = argv;
  const env = { options: {}, yes: false, userPath: join(homedir(), ".claude", RETIRED_USER), root: projectRootOf(findRoot()) };
  let usable = true;
  for (let i = 0; i < rest.length; i += 1) {
    if (rest[i] === "--yes") env.yes = true;
    else if (rest[i] === "--setting" && addSetting(env.options, rest[i + 1])) i += 1;
    else usable = false;
  }
  const actions = { check, user: retireUser, personal: movePersonal };
  if (!usable || !Object.hasOwn(actions, action)) {
    process.stderr.write(USAGE);
    return 2;
  }
  return actions[action](env);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
