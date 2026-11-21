import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "../../lib/yaml-subset.mjs";
import { pluginRoot } from "./config.mjs";

const PRODUCT = /^[a-z][a-z0-9-]*$/;
const ENFORCEMENT = ["sandbox", "approval-denial"];
const UNSET_MODEL = ["cli-default", "skip-with-notice"];
const SEVERITY = ["notice", "downgrade"];
const SOFT_DENY = {
  json_item_failed: ["item_types", "text_field", "patterns"],
  json_array_nonempty: ["field"],
  stderr_substring: ["text"],
};
const COMMANDS = ["run", "resume", "review"];

const isMap = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const isStrings = (v) => Array.isArray(v) && v.every((s) => typeof s === "string");

export function validateProvider(record) {
  const problems = [];
  const need = (ok, path, what) => ok || problems.push(`${path}: ${what}`);
  if (!isMap(record)) return ["record: expected a mapping"];
  need(record.schema === 1, "schema", "expected 1");
  need(typeof record.product === "string" && PRODUCT.test(record.product), "product", "expected a lowercase name");
  need(typeof record.docs_index === "string" && record.docs_index.startsWith("https://"), "docs_index", "expected an https URL");
  need(typeof record.binary?.name === "string" && record.binary.name !== "", "binary.name", "expected the binary name");
  if (record.binary?.candidates !== undefined) {
    need(isMap(record.binary.candidates) && Object.values(record.binary.candidates).every(isStrings), "binary.candidates", "expected a list of paths per platform");
  }
  need(isStrings(record.version?.args), "version.args", "expected a list of arguments");
  need(UNSET_MODEL.includes(record.unset_model), "unset_model", `expected one of ${UNSET_MODEL.join(", ")}`);
  if (record.always_args !== undefined) need(isStrings(record.always_args), "always_args", "expected a list of arguments");
  for (const mode of ["read-only", "write"]) {
    const spec = record.modes?.[mode];
    const at = `modes.${mode}`;
    if (!isMap(spec)) {
      problems.push(`${at}: expected a mode mapping`);
      continue;
    }
    need(ENFORCEMENT.includes(spec.enforcement), `${at}.enforcement`, `expected one of ${ENFORCEMENT.join(", ")}`);
    if (spec.args !== undefined) {
      need(isMap(spec.args) && Object.entries(spec.args).every(([k, v]) => COMMANDS.includes(k) && isStrings(v)), `${at}.args`, `expected argument lists keyed by ${COMMANDS.join(", ")}`);
    }
    if (spec.settings !== undefined) {
      need(isMap(spec.settings), `${at}.settings`, "expected a mapping written to a settings file");
      need(typeof spec.settings_arg === "string", `${at}.settings_arg`, "expected the flag that takes the settings file");
    }
    if (spec.fallback_warning !== undefined) {
      need(typeof spec.fallback_warning.pattern === "string", `${at}.fallback_warning.pattern`, "expected a stderr substring");
      need(SEVERITY.includes(spec.fallback_warning.severity), `${at}.fallback_warning.severity`, `expected one of ${SEVERITY.join(", ")}`);
    }
  }
  need(Array.isArray(record.soft_deny), "soft_deny", "expected a list of rules");
  (Array.isArray(record.soft_deny) ? record.soft_deny : []).forEach((rule, i) => {
    const at = `soft_deny[${i}]`;
    const fields = SOFT_DENY[rule?.kind];
    if (!fields) {
      problems.push(`${at}.kind: expected one of ${Object.keys(SOFT_DENY).join(", ")}`);
      return;
    }
    for (const field of fields) need(rule[field] !== undefined && rule[field] !== "", `${at}.${field}`, "required for this kind");
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
