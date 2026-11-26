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
