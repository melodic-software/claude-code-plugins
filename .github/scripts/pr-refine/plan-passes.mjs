// Plans a PR's Refine passes from docs/conventions/pr-pipeline.yaml: the
// activities with `stage: refine` whose applies-when paths and paths-ignore
// let at least one changed path through. Pure: the caller reads the config
// and the changed paths.
//
// Passes run in batches, one batch after another. A pass joins the batch
// before it when it is not `serial`, shares that batch's group, and matched
// none of the files the batch's passes matched; otherwise it starts a new
// batch. So passes on disjoint files run in parallel, and passes on the same
// files run one after another in `order`.
import { matchedPaths } from "../../actions/resolve-config/predicate.mjs";

export const SERIAL = "serial";

// activities: the config's `activities` map. changedPaths: the PR's changed
// files. truncated: the list may be missing files, so every pass runs and its
// runner's own applies-when decides.
// Returns { passes: [{ name, order, group, files }], batches: [[name, ...]] }.
export function planPasses({ activities, changedPaths, truncated = false }) {
  const passes = Object.entries(activities ?? {})
    .filter(([, activity]) => activity?.stage === "refine")
    .map(([name, activity], index) => ({
      name,
      order: activity.order,
      group: activity.group,
      index,
      matched: matchedPaths(activity["applies-when"], changedPaths),
    }))
    .filter((pass) => truncated || pass.matched.length > 0)
    .sort((a, b) => a.order - b.order || a.index - b.index);
  const batches = [];
  for (const pass of passes) {
    const last = batches.at(-1);
    const joins =
      last !== undefined &&
      pass.group !== SERIAL &&
      last.group === pass.group &&
      !pass.matched.some((path) => last.files.has(path));
    if (joins) {
      last.names.push(pass.name);
      for (const path of pass.matched) last.files.add(path);
    } else {
      batches.push({ group: pass.group, names: [pass.name], files: new Set(pass.matched) });
    }
  }
  return {
    passes: passes.map(({ name, order, group, matched }) => ({ name, order, group, files: matched.length })),
    batches: batches.map((batch) => batch.names),
  };
}
