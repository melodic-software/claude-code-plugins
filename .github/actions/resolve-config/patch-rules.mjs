// patch-rules.json's own check, kept out of resolve.mjs: the lanes token
// broker fetches resolve.mjs at a pinned commit and never checks patch rules,
// so a change to the refusal set needs no broker pin.

import Ajv2020 from "ajv/dist/2020.js";

import { Rejection } from "./resolve.mjs";

// Every patch-rules.json row refuses these, so no row can admit them.
const UNIVERSAL_REFUSE = Object.freeze([
  "github-workflows",
  "settings",
  "agent-instructions",
  "gitattributes",
  "symlink",
  "gitlink",
  "rename-into-refused",
]);

const isObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);

// patch-rules.json against its schema, which names every refusal and allow
// rule apply-patch knows; then what the schema cannot check: each row refuses
// the universal set, a two-parent commit allows exactly merge-result, and
// each prepare mode a patch-producing activity uses has a row.
export function checkPatchRules(patchRules, schema, activities = {}) {
  const fail = (message) => {
    throw new Rejection("patch-rules", message);
  };
  if (!isObject(patchRules) || !isObject(schema)) {
    fail("patch-rules.json and patch-rules.schema.json must be present");
  }
  const validate = new Ajv2020({ allErrors: true, strict: false, validateFormats: false }).compile(schema);
  if (!validate(patchRules)) {
    fail(
      `patch-rules.json fails its schema: ${validate.errors.map((error) => `${error.instancePath || "/"} ${error.message}`).join("; ")}`,
    );
  }
  for (const [row, rules] of Object.entries(patchRules)) {
    const missing = UNIVERSAL_REFUSE.filter((name) => !rules.refuse.includes(name));
    if (missing.length > 0) {
      fail(`patch-rules.json row \`${row}\` does not refuse ${missing.join(", ")}`);
    }
    if (rules.commit.parents.includes("base") && (rules.allow.length !== 1 || rules.allow[0] !== "merge-result")) {
      fail(`patch-rules.json row \`${row}\` commits with the base as a parent, so its allow must be exactly [merge-result]`);
    }
  }
  for (const [name, activity] of Object.entries(activities)) {
    const row = activity?.prepare ?? "default";
    if (activity?.["applied-by"]?.patch !== undefined && !Object.hasOwn(patchRules, row)) {
      fail(`activity \`${name}\` hands on a patch with prepare: ${row}, and patch-rules.json has no \`${row}\` row`);
    }
  }
  return patchRules;
}
