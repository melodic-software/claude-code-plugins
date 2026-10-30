import { readdirSync } from "node:fs";
import { jobs } from "../jobs/registry";

test("every job module under jobs/ is in the registry", () => {
  const shared = new Set(["registry.ts", "job.ts", "retry.ts"]);
  const modules = readdirSync("jobs").filter((file) => !shared.has(file));
  expect(jobs).toHaveLength(modules.length);
});
