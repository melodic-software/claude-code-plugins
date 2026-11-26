import { appendFileSync, existsSync, readFileSync } from "node:fs";

import { configFromBase } from "../../actions/resolve-config/resolve-config.mjs";
import { laneSlots, slotTargets } from "../../actions/resolve-config/resolve.mjs";
import { planPasses } from "./plan-passes.mjs";

const LANE = "pr-refine";

const { BASE_PATH, STANDARDS_DIR, PATHS_FILE, CODEOWNERS_FILE, TRUNCATED, GITHUB_OUTPUT } = process.env;
const truncated = TRUNCATED === "true";
const doc = configFromBase({ BASE_PATH, STANDARDS_DIR });
const changedPaths = readFileSync(PATHS_FILE, "utf8").split("\n").filter(Boolean);
const codeowners = existsSync(CODEOWNERS_FILE ?? "") ? readFileSync(CODEOWNERS_FILE, "utf8") : undefined;
const targetsOf = (slot, paths) => ((slot.activity.inputs ?? []).includes("changed-paths") ? slotTargets(slot, paths, codeowners) : null);
const plan = planPasses({ slots: laneSlots(doc, LANE), changedPaths, targetsOf, truncated });

const names = plan.passes.map((pass) => pass.name);
const files = Object.fromEntries(plan.passes.map((pass) => [pass.name, pass.files]));
const lines = [`passes=${JSON.stringify(names)}`, `batches=${JSON.stringify(plan.batches)}`, `files=${JSON.stringify(files)}`, ...names.map((name) => `${name}=true`)];
appendFileSync(GITHUB_OUTPUT, `${lines.join("\n")}\n`);
console.log(
  `::notice title=refine-plan::changed=${changedPaths.length}${truncated ? "+" : ""} passes=${names.join(",") || "none"} batches=${plan.batches.map((batch) => batch.join("+")).join(",") || "none"}`,
);
