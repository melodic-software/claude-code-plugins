// pr-refine.yml's plan job: reads the base config (JSON, from yq) and the
// PR's changed paths (one a line), expands the pr-refine lane's slots through
// resolve.mjs laneSlots, plans the Refine passes (plan-passes.mjs) and writes
// them as step outputs: passes and batches as JSON, files as a JSON map of
// pass to files matched, and `<pass>=true` for each planned pass, which the
// pass's first job gates on.
import { appendFileSync, existsSync, readFileSync } from "node:fs";

import { laneSlots, slotTargets } from "../../actions/resolve-config/resolve.mjs";
import { planPasses } from "./plan-passes.mjs";

const LANE = "pr-refine";

// CODEOWNERS_FILE: the base's .github/CODEOWNERS, as resolve-config reads it.
const { CONFIG_FILE, PATHS_FILE, CODEOWNERS_FILE, TRUNCATED, GITHUB_OUTPUT } = process.env;
const doc = JSON.parse(readFileSync(CONFIG_FILE, "utf8"));
const changedPaths = readFileSync(PATHS_FILE, "utf8").split("\n").filter(Boolean);
const codeowners = existsSync(CODEOWNERS_FILE ?? "") ? readFileSync(CODEOWNERS_FILE, "utf8") : undefined;
const targetsOf = (slot, paths) => ((slot.activity.inputs ?? []).includes("changed-paths") ? slotTargets(slot, paths, codeowners) : null);
const plan = planPasses({ slots: laneSlots(doc, LANE), changedPaths, targetsOf, truncated: TRUNCATED === "true" });

const names = plan.passes.map((pass) => pass.name);
const files = Object.fromEntries(plan.passes.map((pass) => [pass.name, pass.files]));
const lines = [`passes=${JSON.stringify(names)}`, `batches=${JSON.stringify(plan.batches)}`, `files=${JSON.stringify(files)}`, ...names.map((name) => `${name}=true`)];
appendFileSync(GITHUB_OUTPUT, `${lines.join("\n")}\n`);
console.log(
  `::notice title=refine-plan::changed=${changedPaths.length}${TRUNCATED === "true" ? "+" : ""} passes=${names.join(",") || "none"} batches=${plan.batches.map((batch) => batch.join("+")).join(",") || "none"}`,
);
