// Lane and activity name checks over the standards github-actions-conventions
// vocabulary data. Each returns undefined for a valid name, else the reason.

function longestPrefix(candidates, text) {
  return candidates
    .filter(
      (candidate) => text === candidate || text.startsWith(`${candidate}-`),
    )
    .sort((left, right) => right.length - left.length)[0];
}

const stageOf = (name, vocabulary) =>
  longestPrefix(
    vocabulary.stages.map((entry) => entry.name),
    name,
  );

// A lane is named `<stage>-<function>[-<modifier>]`, both from the vocabulary.
export function checkLaneName(name, vocabulary) {
  const stage = stageOf(name, vocabulary);
  const fn =
    stage === undefined || name === stage
      ? undefined
      : longestPrefix(
          (vocabulary.functions[stage] ?? []).map((entry) => entry.name),
          name.slice(stage.length + 1),
        );
  return fn === undefined
    ? `lane \`${name}\` is not <stage>-<function> from the vocabulary`
    : undefined;
}

export function checkActivityName(name, vocabulary) {
  const grammar = vocabulary.activityGrammar;
  if (!new RegExp(grammar.pattern, "u").test(name)) {
    return `activity \`${name}\` does not match ${grammar.pattern}`;
  }
  // The schema's $defs/name and report-check-run allow no mode suffix: a skill's
  // mode goes in the activity's `args`.
  if (name.includes("#")) {
    return `activity \`${name}\` has a \`#\` mode suffix; put the mode in the activity's \`args\``;
  }
  if (vocabulary.engines.includes(name)) {
    return undefined;
  }
  const stage = stageOf(name, vocabulary);
  if (stage !== undefined) {
    return `activity \`${name}\` starts with the stage word \`${stage}\``;
  }
  if (!vocabulary.verbs.includes(name.split("-")[0])) {
    return `activity \`${name}\` does not start with an accepted verb`;
  }
  return undefined;
}
