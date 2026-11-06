// Plans a PR's Refine passes from the pr-refine lane's slots as resolve.mjs
// laneSlots expands them: each enabled leaf with `stage: refine` whose
// predicates (a slot's replaced applies-when and any composite's, as the
// runner reads them) let at least one changed path through, by the
// predicates' paths and paths-ignore. Pure: the caller reads the config and
// the changed paths.
//
// Passes are grouped into batches. A pass joins the batch before it when it
// is not `serial`, shares that batch's group, and matched none of the files
// the batch's passes matched; otherwise it starts a new batch. So passes on
// disjoint files may run in parallel, and passes on the same files in
// `order`. pr-refine.yml reads no batch yet: a second pass's first job must
// wait on the batch before it.
import { matchedPaths } from "../../actions/resolve-config/predicate.mjs";

export const SERIAL = "serial";

// slots: laneSlots's entries, { name, activity, predicates, enabled }.
// changedPaths: the PR's changed files. targetsOf(slot, changedPaths): the
// files the runner would hand the slot (resolve.mjs slotTargets), or null
// when it takes no changed-paths input. truncated: the list may be missing
// files, so every pass runs and its runner's own applies-when decides.
// Returns { passes: [{ name, order, group, files }], batches: [[name, ...]] }.
export function planPasses({ slots, changedPaths, targetsOf = () => null, truncated = false }) {
  const passes = (slots ?? [])
    .filter((slot) => slot.enabled && slot.activity?.stage === "refine")
    .map((slot, index) => {
      // Each predicate's paths keys must pass on their own, as resolve's
      // appliesAll reads them; a slot with targets also needs one left.
      const pathsPass = slot.predicates.every((predicate) => matchedPaths(predicate, changedPaths).length > 0);
      const targets = targetsOf(slot, changedPaths);
      const matched = targets ?? slot.predicates.reduce((kept, predicate) => matchedPaths(predicate, kept), changedPaths);
      return {
        name: slot.name,
        order: slot.activity.order,
        group: slot.activity.group,
        index,
        matched,
        applies: pathsPass && (targets === null || targets.length > 0),
      };
    })
    .filter((pass) => truncated || pass.applies)
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
