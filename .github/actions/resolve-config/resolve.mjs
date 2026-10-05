// Pure core of resolve-config: parse and validate a pr-pipeline.yaml, apply the
// lane rules the schema cannot carry, and resolve one lane (and optionally one
// activity) with every default applied. Any rejection throws; nothing here
// reads a file or the network.
import { posix } from "node:path";

import Ajv2020 from "ajv/dist/2020.js";
import { parseDocument } from "yaml";

import { applies, factsFor } from "./predicate.mjs";
import { checkActivityName, checkLaneName } from "./vocabulary.mjs";

const CONFIG_BASENAME = "pr-pipeline.yaml";
// Runner job names: `<lane> / run` would collide with pr-run-activity's own checks.
const RESERVED_ACTIVITIES = new Set(["run", "report"]);
const TRUSTED_ACTORS_PATH =
  ".github/standards/trusted-actors/trusted-actors.json";

export class Rejection extends Error {
  constructor(code, message) {
    super(message);
    this.name = "Rejection";
    this.code = code;
  }
}

const isObject = (value) =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export function checkConfigPath(configPath) {
  const fail = (why) => {
    throw new Rejection("config-path", `config-path \`${configPath}\` ${why}`);
  };
  if (typeof configPath !== "string" || configPath === "") {
    fail("is empty");
  }
  if (configPath.startsWith("/")) {
    fail("is absolute");
  }
  if (configPath.split("/").includes("..")) {
    fail("contains `..`");
  }
  if (posix.basename(configPath) !== CONFIG_BASENAME) {
    fail(`has a basename other than ${CONFIG_BASENAME}`);
  }
  if (posix.normalize(configPath).startsWith(".github/actions/")) {
    fail("is under .github/actions/");
  }
  return undefined;
}

function parseConfig(text, configPath) {
  if (typeof text !== "string") {
    throw new Rejection("invalid-config", `no config file at ${configPath}`);
  }
  const document = parseDocument(text, {
    maxAliasCount: 0,
    merge: false,
    prettyErrors: true,
    strict: true,
    uniqueKeys: true,
  });
  if (document.errors.length > 0) {
    throw new Rejection(
      "invalid-config",
      `${configPath} is not valid YAML: ${document.errors.map((error) => error.message).join("; ")}`,
    );
  }
  try {
    return document.toJS({ maxAliasCount: 0 });
  } catch (error) {
    throw new Rejection("invalid-config", `${configPath}: ${error.message}`);
  }
}

function validateSchema(doc, schema, configPath) {
  const validate = new Ajv2020({
    allErrors: true,
    strict: false,
    validateFormats: false,
  }).compile(schema);
  if (!validate(doc)) {
    const errors = validate.errors.map(
      (error) => `${error.instancePath || "/"} ${error.message}`,
    );
    throw new Rejection(
      "invalid-config",
      `${configPath} fails the schema: ${errors.join("; ")}`,
    );
  }
}

function checkVocabularyShape(vocabulary) {
  if (
    !isObject(vocabulary) ||
    !Array.isArray(vocabulary.stages) ||
    !isObject(vocabulary.functions) ||
    !Array.isArray(vocabulary.verbs) ||
    !Array.isArray(vocabulary.engines) ||
    typeof vocabulary.activityGrammar?.pattern !== "string" ||
    !Array.isArray(vocabulary.activityGrammar?.modes)
  ) {
    throw new Rejection(
      "vocabulary",
      "the vocabulary is missing or does not have its expected shape",
    );
  }
}

// Rejections 1, 2, 4-9 and 3 over the whole file, whichever lane the run asked for.
export function loadConfig(files, { configPath }) {
  checkConfigPath(configPath);
  const doc = parseConfig(files.config, configPath);
  if (isObject(doc) && Object.hasOwn(doc, "extends")) {
    throw new Rejection(
      "extends",
      "`extends:` is deferred; the reader rejects any value",
    );
  }
  validateSchema(doc, files.schema, configPath);

  for (const name of Object.keys(doc.activities)) {
    if (RESERVED_ACTIVITIES.has(name)) {
      throw new Rejection(
        "reserved-name",
        `activity \`${name}\` is a pr-run-activity job name`,
      );
    }
  }
  checkVocabularyShape(files.vocabulary);
  for (const name of Object.keys(doc.lanes)) {
    const problem = checkLaneName(name, files.vocabulary);
    if (problem) {
      throw new Rejection("vocabulary", problem);
    }
  }
  for (const name of Object.keys(doc.activities)) {
    const problem = checkActivityName(name, files.vocabulary);
    if (problem) {
      throw new Rejection("vocabulary", problem);
    }
  }

  for (const [laneName, lane] of Object.entries(doc.lanes)) {
    const rule = Object.hasOwn(files.laneRules, laneName)
      ? files.laneRules[laneName]
      : undefined;
    if (rule === undefined) {
      throw new Rejection(
        "lane-stage",
        `lane \`${laneName}\` has no row in lane-rules.json`,
      );
    }
    if (rule.stage !== lane.stage) {
      throw new Rejection(
        "lane-stage",
        `lane \`${laneName}\` has stage \`${lane.stage}\`; lane-rules.json says \`${rule.stage}\``,
      );
    }
    const inLane = new Set((lane.slots ?? []).map((slot) => slot.activity));
    for (const slot of lane.slots ?? []) {
      if (!Object.hasOwn(doc.activities, slot.activity)) {
        throw new Rejection(
          "undefined-activity",
          `lane \`${laneName}\` names activity \`${slot.activity}\`, which is not defined`,
        );
      }
      for (const need of slot.needs ?? []) {
        if (!inLane.has(need)) {
          throw new Rejection(
            "needs-outside-lane",
            `lane \`${laneName}\` slot \`${slot.activity}\` needs \`${need}\`, which is not in the lane`,
          );
        }
      }
      const activity = doc.activities[slot.activity];
      if (
        rule["forbidden-effects"].includes(activity.effect) ||
        (rule["forbidden-gating"] ?? []).includes(activity.gating)
      ) {
        throw new Rejection(
          "forbidden-by-lane",
          `lane \`${laneName}\` may not run \`${slot.activity}\` (effect ${activity.effect}, gating ${activity.gating}): ${rule.never}`,
        );
      }
    }
  }
  return doc;
}

function laneSection(doc, lane) {
  if (typeof lane !== "string" || !Object.hasOwn(doc.lanes, lane)) {
    throw new Rejection("undefined-lane", `the config has no lane \`${lane}\``);
  }
  return doc.lanes[lane];
}

// Each slot of the lane with its activity, effective predicate and enabled flag.
function laneSlots(doc, lane) {
  const section = laneSection(doc, lane);
  const laneEnabled = section.enabled ?? true;
  return (section.slots ?? []).map((slot) => ({
    slot,
    activity: doc.activities[slot.activity],
    predicate:
      slot["applies-when"] ?? doc.activities[slot.activity]["applies-when"],
    enabled: laneEnabled && (slot.enabled ?? true),
  }));
}

// The index of the requested activity's slot, -1 when none was requested.
function selectedIndex(entries, lane, activity) {
  if (activity === undefined || activity === "") {
    return -1;
  }
  const indexes = entries.flatMap((entry, index) =>
    entry.slot.activity === activity ? [index] : [],
  );
  if (indexes.length !== 1) {
    throw new Rejection(
      "undefined-activity",
      `lane \`${lane}\` has ${indexes.length} slots for activity \`${activity}\`; exactly one is required`,
    );
  }
  return indexes[0];
}

// Whether a slot's predicate is decided: every slot without an activity, only
// the selected one with it, so another slot's predicate cannot fail the run.
const decides = (index, selected) => selected < 0 || index === selected;

// The facts the decided enabled slots read. Rejects the same files and request
// resolve() would, before any fact is fetched.
export function neededFacts(files, { lane, activity, configPath }) {
  const doc = loadConfig(files, { configPath });
  const entries = laneSlots(doc, lane);
  const selected = selectedIndex(entries, lane, activity);
  const needed = new Set();
  entries.forEach(({ predicate, enabled }, index) => {
    if (enabled && decides(index, selected)) {
      for (const fact of factsFor(predicate)) {
        needed.add(fact);
      }
    }
  });
  return [...needed];
}

function grantFor(effectGrants, effect) {
  if (!Object.hasOwn(effectGrants, effect)) {
    throw new Rejection(
      "effect-grant",
      `effect-grants.json has no row for \`${effect}\``,
    );
  }
  return { ...effectGrants[effect] };
}

function resolveSlot(
  { slot, activity, predicate, enabled },
  effectGrants,
  facts,
  decided,
) {
  const grant = grantFor(effectGrants, activity.effect);
  let outcome = { applies: null, skipReason: null };
  if (!enabled) {
    outcome = { applies: false, skipReason: "disabled-by-config" };
  } else if (decided) {
    outcome = applies(predicate, facts);
  }
  const kind = activity.skill === undefined ? "script" : "skill";
  return {
    name: slot.activity,
    kind,
    [kind]: activity[kind],
    ...(activity.args === undefined ? {} : { args: activity.args }),
    effect: activity.effect,
    gating: activity.gating,
    "reads-untrusted": activity["reads-untrusted"],
    scope: activity.scope ?? "diff",
    inputs: activity.inputs ?? [],
    needs: slot.needs ?? [],
    ...(predicate === undefined ? {} : { "applies-when": predicate }),
    enabled,
    model: activity.model ?? null,
    "max-turns": activity["max-turns"] ?? null,
    grant,
    applies: outcome.applies,
    "skip-reason": outcome.skipReason,
  };
}

// The token broker's entry point: the same file and lane checks as resolve(),
// for one required activity, deciding no predicate, so it needs no facts.
export function resolveGrant(files, { lane, activity, configPath }) {
  const doc = loadConfig(files, { configPath });
  const entries = laneSlots(doc, lane);
  if (activity === undefined || activity === "") {
    throw new Rejection(
      "undefined-activity",
      `a grant needs an activity of lane \`${lane}\``,
    );
  }
  const entry = entries[selectedIndex(entries, lane, activity)];
  return {
    enabled: entry.enabled,
    effect: entry.activity.effect,
    grant: grantFor(files.effectGrants, entry.activity.effect),
  };
}

function resolveMerge(merge = {}, configPath) {
  const diffCheck = merge["diff-check"] ?? {};
  const denied = [
    ...new Set([
      ...(diffCheck["denied-paths"] ?? []),
      configPath,
      ".github/**",
      TRUSTED_ACTORS_PATH,
    ]),
  ];
  return {
    rung: merge.rung ?? "off",
    "diff-check": { ...diffCheck, "denied-paths": denied },
    "stack-landing": merge["stack-landing"] ?? "manual",
  };
}

export function resolve(
  files,
  { lane, activity, configPath, basePath, facts },
) {
  const doc = loadConfig(files, { configPath });
  const section = laneSection(doc, lane);
  const entries = laneSlots(doc, lane);
  const index = selectedIndex(entries, lane, activity);
  const slots = entries.map((entry, i) =>
    resolveSlot(entry, files.effectGrants, facts, decides(i, index)),
  );
  return {
    version: 1,
    source: { "base-path": basePath, "config-path": configPath },
    lane: {
      name: lane,
      stage: section.stage,
      enabled: section.enabled ?? true,
      slots,
    },
    selected: index < 0 ? null : slots[index],
    loop: {
      "review-rounds": doc.loop?.["review-rounds"] ?? 2,
      "no-progress": doc.loop?.["no-progress"] ?? 3,
    },
    merge: resolveMerge(doc.merge, configPath),
  };
}
