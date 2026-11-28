import { matchedPaths } from "../../actions/resolve-config/predicate.mjs";

export const SERIAL = "serial";

export function planPasses({ slots, changedPaths, targetsOf = () => null, truncated = false }) {
  const passes = (slots ?? [])
    .filter((slot) => slot.enabled && slot.activity?.stage === "refine")
    .map((slot, index) => {
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
