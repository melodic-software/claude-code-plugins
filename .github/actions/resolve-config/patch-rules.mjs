import Ajv2020 from "ajv/dist/2020.js";

import { Rejection } from "./resolve.mjs";

const UNIVERSAL_REFUSE = Object.freeze([
  "github-workflows",
  "codeowners",
  "gitmodules",
  "settings",
  "lane-grants",
  "symlink",
  "gitlink",
  "rename-into-refused",
]);

const isObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);

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
    const only = rules["clean-patch"] === true ? "shared-copies" : "merge-result";
    if (rules.commit.parents.includes("base") && (rules.allow.length !== 1 || rules.allow[0] !== only)) {
      fail(`patch-rules.json row \`${row}\` commits with the base as a parent, so its allow must be exactly [${only}]`);
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
