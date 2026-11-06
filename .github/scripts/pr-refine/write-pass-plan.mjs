// pr-refine.yml's plan job: reads the base config's activities (JSON, from
// yq) and the PR's changed paths (one a line), plans the Refine passes
// (plan-passes.mjs) and writes them as step outputs: passes and batches as
// JSON, files as a JSON map of pass to files matched, and `<pass>=true` for
// each planned pass, which the pass's first job gates on.
import { appendFileSync, readFileSync } from "node:fs";

import { planPasses } from "./plan-passes.mjs";

const { ACTIVITIES_FILE, PATHS_FILE, TRUNCATED, GITHUB_OUTPUT } = process.env;
const activities = JSON.parse(readFileSync(ACTIVITIES_FILE, "utf8"));
const changedPaths = readFileSync(PATHS_FILE, "utf8").split("\n").filter(Boolean);
const plan = planPasses({ activities, changedPaths, truncated: TRUNCATED === "true" });

const names = plan.passes.map((pass) => pass.name);
const files = Object.fromEntries(plan.passes.map((pass) => [pass.name, pass.files]));
const lines = [`passes=${JSON.stringify(names)}`, `batches=${JSON.stringify(plan.batches)}`, `files=${JSON.stringify(files)}`, ...names.map((name) => `${name}=true`)];
appendFileSync(GITHUB_OUTPUT, `${lines.join("\n")}\n`);
console.log(
  `::notice title=refine-plan::changed=${changedPaths.length}${TRUNCATED === "true" ? "+" : ""} passes=${names.join(",") || "none"} batches=${plan.batches.map((batch) => batch.join("+")).join(",") || "none"}`,
);
