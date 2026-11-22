import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "../../lib/yaml-subset.mjs";
import { pluginRoot } from "./config.mjs";

const PRODUCT = /^[a-z][a-z0-9-]*$/;
const ENFORCEMENT = ["sandbox", "approval-denial"];
const UNSET_MODEL = ["cli-default", "skip-with-notice"];
const SEVERITY = ["notice", "downgrade"];
const COMMANDS = ["run", "resume", "review"];
const REVIEW_KIND = ["native", "diff_file"];
const UNAVAILABLE = ["auth", "usage-limit"];
const HELP_NAME = /^[a-z0-9][a-z0-9-]*$/;
const PREFACE_TOKENS = ["{base}", "{merge_base}", "{file_count}", "{files}"];

const isMap = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const isText = (v) => typeof v === "string" && v !== "";
const isStrings = (v) => Array.isArray(v) && v.every((s) => typeof s === "string");
const isStringMap = (v) => isMap(v) && Object.values(v).every((s) => typeof s === "string");

const TOP = ["schema", "product", "docs_index", "config_reference", "help","binary", "version", "login_status", "unset_model", "model_flag", "profile_flag", "profile_on", "effort_flag", "effort_config", "config_arg", "always_args", "prompt", "output", "run", "resume", "review", "modes", "soft_deny", "unavailable"];
const MODE = ["enforcement", "args", "settings", "settings_arg", "fallback_warning", "prompt_preface"];
const OUTPUT = {
  jsonl_events: {
    text: ["final_message_arg", "thread_event", "thread_field", "turn_ok_event", "item_event", "item_prefix"],
    lists: ["failure_events"],
    optionalLists: ["mcp_item_types"],
  },
  json_envelope: { text: ["status_field", "success_value", "message_field", "thread_field", "error_field"], lists: [], optionalLists: [] },
};
const SOFT_DENY = {
  json_item_failed: { required: ["item_types"], optional: ["statuses", "text_field", "patterns"], lists: ["item_types", "statuses", "patterns"] },
  json_array_nonempty: { required: ["field"], optional: [], lists: [] },
  stderr_substring: { required: ["text"], optional: [], lists: [] },
};

export function validateProvider(record) {
  const problems = [];
  const need = (ok, path, what) => ok || problems.push(`${path}: ${what}`);
  const known = (value, allowed, at) => {
    if (!isMap(value)) return;
    for (const key of Object.keys(value)) if (!allowed.includes(key)) problems.push(`${at ? `${at}.` : ""}${key}: unknown key`);
  };
  const optional = (value, ok, path, what) => value === undefined || need(ok(value), path, what);
  if (!isMap(record)) return ["record: expected a mapping"];
  known(record, TOP, "");
  need(record.schema === 1, "schema", "expected 1");
  need(typeof record.product === "string" && PRODUCT.test(record.product), "product", "expected a lowercase name");
  need(typeof record.docs_index === "string" && record.docs_index.startsWith("https://"), "docs_index", "expected an https URL");

  known(record.binary, ["name", "candidates"], "binary");
  need(isText(record.binary?.name), "binary.name", "expected the binary name");
  optional(record.binary?.candidates, (v) => isMap(v) && Object.values(v).every(isStrings), "binary.candidates", "expected a list of paths per platform");

  optional(record.config_reference, (v) => typeof v === "string" && v.startsWith("https://"), "config_reference", "expected an https URL");
  optional(record.help, isMap, "help", "expected a mapping of cache file name to help arguments");
  for (const [name, args] of Object.entries(isMap(record.help) ? record.help : {})) {
    need(HELP_NAME.test(name), `help.${name}`, "expected a lowercase file name");
    need(isStrings(args) && args.length > 0, `help.${name}`, "expected a list of arguments");
  }

  known(record.version, ["args", "sources", "markers"], "version");
  need(isStrings(record.version?.args), "version.args", "expected a list of arguments");
  optional(record.version?.sources, isStringMap, "version.sources", "expected a source per install channel");
  optional(record.version?.markers, isMap, "version.markers", "expected folder names per install channel");
  for (const [channel, names] of Object.entries(isMap(record.version?.markers) ? record.version.markers : {})) {
    need(isStrings(names) && Object.hasOwn(record.version?.sources ?? {}, channel), `version.markers.${channel}`, "expected a list of folder names for a channel in version.sources");
  }
  known(record.login_status, ["args"], "login_status");
  optional(record.login_status, (v) => isStrings(v?.args), "login_status.args", "expected a list of arguments");

  need(UNSET_MODEL.includes(record.unset_model), "unset_model", `expected one of ${UNSET_MODEL.join(", ")}`);
  for (const key of ["model_flag", "profile_flag", "effort_flag", "effort_config", "config_arg"]) optional(record[key], isText, key, "expected text");
  if (record.effort_config !== undefined) need(isText(record.config_arg), "config_arg", "expected the flag that takes effort_config as key=value");
  optional(record.profile_on, (v) => isStrings(v) && v.every((c) => COMMANDS.includes(c)), "profile_on", `expected a list drawn from ${COMMANDS.join(", ")}`);
  optional(record.always_args, isStrings, "always_args", "expected a list of arguments");

  known(record.prompt, ["form"], "prompt");
  need(isText(record.prompt?.form), "prompt.form", "expected `-` for stdin or an argument holding {prompt}");

  const shape = OUTPUT[record.output?.kind];
  if (!shape) {
    problems.push(`output.kind: expected one of ${Object.keys(OUTPUT).join(", ")}`);
  } else {
    known(record.output, ["kind", ...shape.text, ...shape.lists, ...shape.optionalLists], "output");
    for (const key of shape.text) need(isText(record.output[key]), `output.${key}`, "required for this kind");
    for (const key of shape.lists) need(isStrings(record.output[key]), `output.${key}`, "expected a list");
    for (const key of shape.optionalLists) optional(record.output[key], isStrings, `output.${key}`, "expected a list");
  }

  for (const command of ["run", "resume"]) {
    known(record[command], ["args"], command);
    optional(record[command], (v) => isStrings(v?.args), `${command}.args`, "expected a list of arguments");
  }
  optional(record.resume, (v) => (v?.args ?? []).some((a) => a.includes("{thread}")), "resume.args", "expected an argument holding {thread}");
  if (record.review !== undefined) {
    known(record.review, ["kind", "args", "brief_args", "brief_preface", "dir_arg", "config_paths"], "review");
    optional(record.review?.brief_args, isStrings, "review.brief_args", "expected the arguments of a review that carries a brief");
    optional(record.review?.brief_preface, isText, "review.brief_preface", "expected text, with {base} where the base ref goes");
    for (const [token] of String(record.review?.brief_preface ?? "").matchAll(/\{[^}]*\}/g)) {
      if (!PREFACE_TOKENS.includes(token)) problems.push(`review.brief_preface: unknown token ${token}`);
    }
    need(REVIEW_KIND.includes(record.review?.kind), "review.kind", `expected one of ${REVIEW_KIND.join(", ")}`);
    if (record.review?.kind === "native") need(isStrings(record.review.args) && record.review.args.some((a) => a.includes("{base}")), "review.args", "expected arguments holding {base}");
    if (record.review?.kind === "diff_file") need(isText(record.review.dir_arg), "review.dir_arg", "expected the flag that adds a readable folder");
    optional(record.review?.config_paths, isStrings, "review.config_paths", "expected a list of path prefixes");
  }

  for (const mode of ["read-only", "write"]) {
    const spec = record.modes?.[mode];
    const at = `modes.${mode}`;
    if (!isMap(spec)) {
      problems.push(`${at}: expected a mode mapping`);
      continue;
    }
    known(spec, MODE, at);
    need(ENFORCEMENT.includes(spec.enforcement), `${at}.enforcement`, `expected one of ${ENFORCEMENT.join(", ")}`);
    optional(spec.args, (v) => isMap(v) && Object.entries(v).every(([k, list]) => COMMANDS.includes(k) && isStrings(list)), `${at}.args`, `expected argument lists keyed by ${COMMANDS.join(", ")}`);
    if (spec.settings !== undefined) {
      need(isMap(spec.settings), `${at}.settings`, "expected a mapping written to a settings file");
      need(isText(spec.settings_arg), `${at}.settings_arg`, "expected the flag that takes the settings file");
    }
    if (spec.fallback_warning !== undefined) {
      known(spec.fallback_warning, ["pattern", "severity"], `${at}.fallback_warning`);
      need(isText(spec.fallback_warning?.pattern), `${at}.fallback_warning.pattern`, "expected a stderr substring");
      need(SEVERITY.includes(spec.fallback_warning?.severity), `${at}.fallback_warning.severity`, `expected one of ${SEVERITY.join(", ")}`);
    }
    optional(spec.prompt_preface, isText, `${at}.prompt_preface`, "expected text");
  }
  known(record.modes, ["read-only", "write"], "modes");

  need(Array.isArray(record.soft_deny), "soft_deny", "expected a list of rules");
  (Array.isArray(record.soft_deny) ? record.soft_deny : []).forEach((rule, i) => {
    const at = `soft_deny[${i}]`;
    const fields = SOFT_DENY[rule?.kind];
    if (!fields) {
      problems.push(`${at}.kind: expected one of ${Object.keys(SOFT_DENY).join(", ")}`);
      return;
    }
    known(rule, ["kind", ...fields.required, ...fields.optional], at);
    for (const field of fields.required) need(rule[field] !== undefined && rule[field] !== "", `${at}.${field}`, "required for this kind");
    for (const field of fields.lists) optional(rule[field], isStrings, `${at}.${field}`, "expected a list");
    if (rule.kind === "json_item_failed") need((rule.patterns === undefined) === (rule.text_field === undefined), `${at}.patterns`, "patterns and text_field are set together");
  });

  optional(record.unavailable, Array.isArray, "unavailable", "expected a list of rules");
  (Array.isArray(record.unavailable) ? record.unavailable : []).forEach((rule, i) => {
    const at = `unavailable[${i}]`;
    known(rule, ["class", "patterns", "reset_pattern"], at);
    need(UNAVAILABLE.includes(rule?.class), `${at}.class`, `expected one of ${UNAVAILABLE.join(", ")}`);
    need(isStrings(rule?.patterns) && rule.patterns.length > 0, `${at}.patterns`, "expected a list of substrings");
    optional(rule?.reset_pattern, isText, `${at}.reset_pattern`, "expected a regular expression with one capture group");
  });
  return problems;
}

export function loadProvider(product, root = pluginRoot) {
  if (!PRODUCT.test(product ?? "")) throw new Error(`invalid product: ${JSON.stringify(product)}`);
  const file = join(root, "providers", `${product}.yaml`);
  if (!existsSync(file)) throw new Error(`${product}: no provider record (providers/${product}.yaml)`);
  const record = parse(readFileSync(file, "utf8"));
  const problems = validateProvider(record);
  if (problems.length) throw new Error(`providers/${product}.yaml: ${problems.join("; ")}`);
  return record;
}
