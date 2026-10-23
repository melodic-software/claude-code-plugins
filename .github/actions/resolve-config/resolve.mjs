// Pure core of resolve-config: parse and validate a pr-pipeline.yaml, apply the
// lane rules the schema cannot carry, and resolve one lane (and optionally one
// activity) with every default applied. Any rejection throws; nothing here
// reads a file or the network.
import { posix } from "node:path";

import Ajv2020 from "ajv/dist/2020.js";
import { parseDocument } from "yaml";

import { checkDimensions, dimensionBudget, issueDimensions, parsePin } from "./dimensions.mjs";
import { MissingFact, appliesAll, factsFor } from "./predicate.mjs";
import { checkActivityName, checkLaneName } from "./vocabulary.mjs";

const CONFIG_BASENAME = "pr-pipeline.yaml";
// Runner job names: `<lane> / run` would collide with pr-run-activity's own checks.
const RESERVED_ACTIVITIES = new Set(["run", "report"]);
const TRUSTED_ACTORS_PATH =
  ".github/standards/trusted-actors/trusted-actors.json";
// Model routes that are no activity: pr-verify.yml's judgment, the code and
// security review lanes, and intake triage.
const RUN_ROUTES = new Set(["verify-pr", "review-code", "review-security", "triage-issue", "summarize-reuse"]);
// The profile every run takes in a config with no `models` block.
const BUILTIN_MODELS = Object.freeze({
  profiles: { standard: { model: "default", "max-turns": 75 } },
  "default-profile": "standard",
});

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

const isComposite = (activity) => Object.hasOwn(activity, "children");

// What the schema cannot check about composites: each child is defined, a
// child's needs name its siblings, no composite contains itself, and a
// composite holds only leaves, so no leaf sits more than two layers below its
// lane.
function checkComposites(activities) {
  const composites = Object.entries(activities).filter(([, activity]) =>
    isComposite(activity),
  );
  for (const [name, { children }] of composites) {
    const siblings = new Set(children.map((child) => child.activity));
    for (const child of children) {
      if (!Object.hasOwn(activities, child.activity)) {
        throw new Rejection(
          "undefined-activity",
          `composite \`${name}\` names activity \`${child.activity}\`, which is not defined`,
        );
      }
      for (const need of child.needs ?? []) {
        if (!siblings.has(need)) {
          throw new Rejection(
            "needs-not-sibling",
            `composite \`${name}\` child \`${child.activity}\` needs \`${need}\`, which is not one of its siblings`,
          );
        }
      }
    }
  }
  const done = new Set();
  const visit = (name, trail) => {
    if (done.has(name) || !isComposite(activities[name])) {
      return;
    }
    if (trail.includes(name)) {
      throw new Rejection(
        "activity-cycle",
        `composite \`${name}\` contains itself: ${[...trail, name].join(" -> ")}`,
      );
    }
    for (const child of activities[name].children) {
      visit(child.activity, [...trail, name]);
    }
    done.add(name);
  };
  for (const [name, { children }] of composites) {
    visit(name, []);
    const nested = children.find((child) =>
      isComposite(activities[child.activity]),
    );
    if (nested) {
      throw new Rejection(
        "activity-depth",
        `composite \`${name}\` holds composite \`${nested.activity}\`; a composite holds only leaves, at most two layers below the lane`,
      );
    }
  }
}

// activity-rules.json: per leaf, the effects it may never have and what it
// never does. A leaf with no row is valid; a missing file is not, and every
// forbidden effect must be one effect-grants.json knows.
function checkActivityRules(activityRules, effectGrants) {
  const valid =
    isObject(activityRules) &&
    isObject(effectGrants) &&
    Object.values(activityRules).every(
      (row) =>
        isObject(row) &&
        typeof row.never === "string" &&
        row.never !== "" &&
        (row["forbidden-effects"] === undefined ||
          (Array.isArray(row["forbidden-effects"]) &&
            row["forbidden-effects"].every(
              (effect) =>
                typeof effect === "string" &&
                Object.hasOwn(effectGrants, effect),
            ))),
    );
  if (!valid) {
    throw new Rejection(
      "activity-rules",
      "activity-rules.json must be present and map each activity to a `never` string and an optional `forbidden-effects` list of effect-grants.json effects",
    );
  }
  return activityRules;
}

function checkLeaves(activities, activityRules) {
  for (const [name, activity] of Object.entries(activities)) {
    if (isComposite(activity)) {
      continue;
    }
    // ci-context is the read runner's one mode, apply-patch a branch-writing
    // script's; every other mode needs a skill that can write, or a read
    // skill whose patch a script applies.
    const needs = { "ci-context": "read", "apply-patch": "mutate-branch" }[activity.prepare];
    const handsOnPatch = isObject(activity["applied-by"]) && typeof activity["applied-by"].patch === "string";
    if (
      activity.prepare !== undefined &&
      (needs ? activity.effect !== needs : activity.effect === "read" && !handsOnPatch)
    ) {
      throw new Rejection(
        "invalid-prepare",
        needs
          ? `activity \`${name}\` sets prepare: ${activity.prepare}, which needs effect ${needs}`
          : `activity \`${name}\` sets prepare with effect read and no applied-by.patch; prepare needs a skill that can write or hands on a patch`,
      );
    }
    const rule = Object.hasOwn(activityRules, name)
      ? activityRules[name]
      : undefined;
    if ((rule?.["forbidden-effects"] ?? []).includes(activity.effect)) {
      throw new Rejection(
        "forbidden-by-activity",
        `activity \`${name}\` may not have effect ${activity.effect}: ${rule.never}`,
      );
    }
  }
}

// The prepare mode an applied-by target must set, per key.
const APPLIER_PREPARE = Object.freeze({ patch: "apply-patch" });

// What the schema cannot check about `applied-by`: each target is a script
// activity (a patch target one with prepare: apply-patch), and every lane that
// holds the producer holds the target in a slot that needs the producer.
function checkAppliedBy(doc) {
  const reject = (message) => {
    throw new Rejection("invalid-applied-by", message);
  };
  const handsOn = (activity) => !isComposite(activity) && isObject(activity["applied-by"]);
  for (const [name, activity] of Object.entries(doc.activities)) {
    for (const [key, target] of Object.entries(handsOn(activity) ? activity["applied-by"] : {})) {
      const applier = Object.hasOwn(doc.activities, target) ? doc.activities[target] : undefined;
      if (typeof applier?.script !== "string") {
        reject(`activity \`${name}\` applied-by.${key} names \`${target}\`, which is not a script activity`);
      }
      const prepare = APPLIER_PREPARE[key];
      if (prepare !== undefined && applier.prepare !== prepare) {
        reject(`activity \`${name}\` applied-by.${key} names \`${target}\`, which does not set prepare: ${prepare}`);
      }
    }
  }
  for (const lane of Object.keys(doc.lanes)) {
    const leaves = laneSlots(doc, lane);
    for (const producer of leaves.filter((entry) => handsOn(entry.activity))) {
      for (const [key, target] of Object.entries(producer.activity["applied-by"])) {
        const applier = leaves.find((entry) => entry.name === target);
        if (applier === undefined) {
          reject(`lane \`${lane}\` holds \`${producer.name}\`, whose applied-by.${key} \`${target}\` is not in the lane`);
        }
        if (!applier.needs.includes(producer.name)) {
          reject(`lane \`${lane}\` slot \`${target}\` applies \`${producer.name}\`'s ${key} and does not need it`);
        }
      }
    }
  }
}

// A runner names the applied-by keys it hands on (applied-by-supported, a
// comma- or space-separated list); an applying leaf with any other key would
// hand nothing on, so it fails before the head checkout.
export function checkAppliedBySupported(selected, supported = "") {
  const kinds = new Set(String(supported).split(/[\s,]+/).filter(Boolean));
  const missing = Object.keys(selected?.["applied-by"] ?? {}).filter((key) => !kinds.has(key));
  if (selected?.applies && missing.length > 0) {
    throw new Rejection(
      "applied-by-unsupported",
      `activity \`${selected.name}\` sets applied-by ${missing.join(", ")}, and this runner does not pass applied-by-supported: ${missing.join(", ")}`,
    );
  }
}

// What the schema cannot check about `models`: every profile a route,
// default-profile, escalate-to or complexity profile names exists, a
// complexity profile's key is a complexity, and every route names a skill
// activity or a run route, so a mistyped route cannot silently take the default.
function checkModels(models, activities) {
  if (models === undefined) {
    return;
  }
  const { profiles } = models;
  const complexityProfiles = models["issue-dimensions"]?.["complexity-profiles"] ?? {};
  for (const [route, profile] of [
    ["default-profile", models["default-profile"]],
    ...Object.entries(models.routes ?? {}),
    ...Object.entries(profiles).flatMap(([name, values]) =>
      values["escalate-to"] === undefined ? [] : [[`profiles.${name}.escalate-to`, values["escalate-to"]]],
    ),
    ...Object.entries(complexityProfiles).map(([complexity, profile]) => [`complexity-profiles.${complexity}`, profile]),
  ]) {
    if (!Object.hasOwn(profiles, profile)) {
      throw new Rejection(
        "undefined-profile",
        `models: \`${route}\` names profile \`${profile}\`, which is not defined`,
      );
    }
  }
  for (const route of Object.keys(models.routes ?? {})) {
    const activity = Object.hasOwn(activities, route) ? activities[route] : undefined;
    if (!RUN_ROUTES.has(route) && typeof activity?.skill !== "string") {
      throw new Rejection(
        "undefined-route",
        `models.routes names \`${route}\`, which is neither a skill activity nor ${[...RUN_ROUTES].join(", ")}`,
      );
    }
  }
  if (models["issue-dimensions"] !== undefined) {
    checkDimensions(models["issue-dimensions"]);
    const known = models["issue-dimensions"].complexity;
    const stray = Object.keys(complexityProfiles).find((complexity) => !Object.hasOwn(known, complexity));
    if (stray !== undefined) {
      throw new Rejection(
        "undefined-dimension",
        `models.issue-dimensions.complexity-profiles names \`${stray}\`, which is not a key of complexity`,
      );
    }
  }
}

// Whether a skill activity takes its budget from its issue's dimensions.
const dimensionedBy = (activity, models) =>
  models?.["issue-dimensions"] !== undefined &&
  typeof activity.skill === "string" &&
  (activity.inputs ?? []).includes("issue");

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
  checkComposites(doc.activities);
  checkModels(doc.models, doc.activities);
  checkLeaves(
    doc.activities,
    checkActivityRules(files.activityRules, files.effectGrants),
  );

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
    }
    const leaves = expand(doc, lane.slots ?? [], ROOT).map(
      (entry) => entry.name,
    );
    const repeated = leaves.find(
      (name, index) => leaves.indexOf(name) !== index,
    );
    if (repeated !== undefined) {
      throw new Rejection(
        "undefined-activity",
        `lane \`${laneName}\` holds activity \`${repeated}\` more than once; a leaf may appear once in a lane`,
      );
    }
    checkActivityGrants(laneName, rule["activity-grants"], leaves);
    for (const name of leaves) {
      const activity = doc.activities[name];
      // The lane rule compares strictly, so it must not depend on the schema enum.
      if (typeof activity.effect !== "string") {
        throw new Rejection(
          "invalid-config",
          `activity \`${name}\` has an effect that is not a string`,
        );
      }
      if (
        rule["forbidden-effects"].includes(activity.effect) ||
        (rule["forbidden-gating"] ?? []).includes(activity.gating)
      ) {
        throw new Rejection(
          "forbidden-by-lane",
          `lane \`${laneName}\` may not run \`${name}\` (effect ${activity.effect}, gating ${activity.gating}): ${rule.never}`,
        );
      }
    }
  }
  checkAppliedBy(doc);
  return doc;
}

function laneSection(doc, lane) {
  if (typeof lane !== "string" || !Object.hasOwn(doc.lanes, lane)) {
    throw new Rejection("undefined-lane", `the config has no lane \`${lane}\``);
  }
  return doc.lanes[lane];
}

const ROOT = Object.freeze({ enabled: true, predicates: [], needs: [] });

// The leaf keys a needs entry waits on: a composite's leaves, or the leaf.
const leafKeys = (doc, name) =>
  isComposite(doc.activities[name])
    ? doc.activities[name].children.map((child) => child.activity)
    : [name];

// Each leaf under these slots, depth first in list order, with its own
// effective predicate, every predicate it must also pass (ancestors first),
// enabled as the AND down its path, and needs as its ancestors' then its own.
function expand(doc, slots, parent) {
  return slots.flatMap((slot) => {
    const activity = doc.activities[slot.activity];
    const predicate = slot["applies-when"] ?? activity["applies-when"];
    const path = {
      enabled: parent.enabled && (slot.enabled ?? true),
      predicates:
        predicate === undefined
          ? parent.predicates
          : [...parent.predicates, predicate],
      needs: [
        ...new Set([
          ...parent.needs,
          ...(slot.needs ?? []).flatMap((need) => leafKeys(doc, need)),
        ]),
      ],
    };
    return isComposite(activity)
      ? expand(doc, activity.children, path)
      : [{ name: slot.activity, activity, predicate, ...path }];
  });
}

// Each leaf of the lane, with its activity, predicates and enabled flag.
function laneSlots(doc, lane) {
  const section = laneSection(doc, lane);
  return expand(doc, section.slots ?? [], {
    ...ROOT,
    enabled: section.enabled ?? true,
  });
}

// Whether the lane holds a slot for the activity, in a config that passes
// every check loadConfig makes; a config that does not is a Rejection.
export function laneHasActivity(files, { lane, activity, configPath }) {
  const doc = loadConfig(files, { configPath });
  return laneSlots(doc, lane).some((entry) => entry.name === activity);
}

// The index of the requested activity's slot, -1 when none was requested.
function selectedIndex(entries, lane, activity) {
  if (activity === undefined || activity === "") {
    return -1;
  }
  const indexes = entries.flatMap((entry, index) =>
    entry.name === activity ? [index] : [],
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
export function neededFacts(files, { lane, activity, configPath, pinnedDimensions }) {
  const doc = loadConfig(files, { configPath });
  const entries = laneSlots(doc, lane);
  const selected = selectedIndex(entries, lane, activity);
  const needed = new Set();
  entries.forEach(({ activity: definition, predicates, enabled }, index) => {
    if (enabled && decides(index, selected)) {
      for (const fact of predicates.flatMap(factsFor)) {
        needed.add(fact);
      }
      if ((definition.inputs ?? []).includes("changed-paths")) {
        needed.add("changedPaths");
      }
      // The fields are read now, unless an earlier resolve pinned them.
      if (dimensionedBy(definition, doc.models) && !pinnedDimensions) {
        needed.add("fieldValues");
        needed.add("fieldSetters");
      }
    }
  });
  return [...needed];
}

// Files Claude Code or a plugin loads as instructions. Target selection, not a
// control: a write activity is not asked to fix them, though its token and
// tools can change any file and the PR reviews what it did.
const INSTRUCTION_SURFACES = [
  "**/claude.md",
  "**/claude.local.md",
  "**/agents.md",
  "**/.claude/**",
  "**/.claude-plugin/**",
  "**/skill.md",
  "**/skills/**",
  "**/agents/**",
  "**/commands/**",
  "**/hooks/**",
  "**/output-styles/**",
  "**/prompts/**",
];
// A name that is safe as a prompt word: no space, quote, comma, glob or shell
// character, no `.`/`..` segment, no segment that starts with `-`, so it
// cannot read as an option, and no leading `@`, so it cannot read as a file
// mention.
const SAFE_PATH = /^(?![-@])[A-Za-z0-9_@+.-]+(?:\/(?!-)[A-Za-z0-9_@+.-]+)*$/;
const isSafePath = (path) =>
  SAFE_PATH.test(path) &&
  !path.split("/").some((segment) => segment === "." || segment === "..");

// Every path pattern in CODEOWNERS, owned or not, as globs: a leading `/`
// anchors at the root, any other pattern matches at any depth, and a pattern
// also covers everything under it.
function codeownersGlobs(text) {
  return (text ?? "").split("\n").flatMap((line) => {
    const pattern = line.replace(/#.*/, "").trim().split(/\s+/)[0];
    if (!pattern) {
      return [];
    }
    const body = pattern.startsWith("/") ? pattern.slice(1) : `**/${pattern}`;
    const trimmed = body.replace(/\/+$/, "");
    return trimmed ? [trimmed, `${trimmed}/**`] : [];
  });
}

// The changed-paths input: the PR's changed files that still exist, that match
// the slot's `paths` predicate when it has one, and that have a safe name. For
// an activity that edits (an effect other than `read`, or a patch it hands
// on), instruction surfaces and every path CODEOWNERS lists are left out of
// what it is asked to fix. Sorted, without duplicates.
export function changedPathTargets({
  paths,
  predicatePaths,
  edits,
  codeowners,
}) {
  const owned = codeownersGlobs(codeowners);
  const notTargeted = (path) =>
    edits &&
    (INSTRUCTION_SURFACES.some((glob) =>
      posix.matchesGlob(path.toLowerCase(), glob),
    ) ||
      owned.some((glob) => posix.matchesGlob(path, glob)));
  const kept = paths.filter(
    (path) =>
      isSafePath(path) &&
      (predicatePaths === undefined ||
        predicatePaths.some((glob) => posix.matchesGlob(path, glob))) &&
      !notTargeted(path),
  );
  return [...new Set(kept)].sort();
}

const GRANT_SCOPES = ["contents", "issues", "pull-requests"];
const GRANT_LEVELS = new Set(["read", "write"]);

// A lane-rules.json row may add `actions: read`, and nothing else, to named
// leaves of its lane through `activity-grants`; the effect row stays the base.
function checkActivityGrants(laneName, activityGrants, leaves) {
  if (activityGrants === undefined) {
    return;
  }
  const valid =
    isObject(activityGrants) &&
    Object.entries(activityGrants).every(
      ([name, extra]) =>
        leaves.includes(name) &&
        isObject(extra) &&
        Object.keys(extra).join() === "actions" &&
        extra.actions === "read",
    );
  if (!valid) {
    throw new Rejection(
      "lane-grant",
      `lane-rules.json row \`${laneName}\` activity-grants must map leaves of the lane to exactly { "actions": "read" }`,
    );
  }
}

const activityGrantOf = (laneRules, lane, activity) =>
  laneRules[lane]?.["activity-grants"]?.[activity] ?? {};

// An empty or partial grant would mint a token with every App permission, so a
// row must name exactly the three scopes, each read or write.
function grantFor(effectGrants, effect, extra = {}) {
  if (typeof effect !== "string" || !Object.hasOwn(effectGrants, effect)) {
    throw new Rejection(
      "effect-grant",
      `effect-grants.json has no row for \`${effect}\``,
    );
  }
  const row = effectGrants[effect];
  if (
    !isObject(row) ||
    Object.keys(row).sort().join() !== GRANT_SCOPES.join() ||
    !GRANT_SCOPES.every((scope) => GRANT_LEVELS.has(row[scope]))
  ) {
    throw new Rejection(
      "effect-grant",
      `effect-grants.json row \`${effect}\` must set exactly ${GRANT_SCOPES.join(", ")}, each read or write`,
    );
  }
  return Object.freeze({ ...row, ...extra });
}

// The owner's model for a role route that resolves to no alias: CI has no
// session, so `inherit`, a missing role map or role, and any value that is not
// an alias (`default`, a model ID) all run on it. The frontier tier (`fable`,
// and `best`, which may resolve to it) never routes automatically, so it runs
// on it too.
const FALLBACK_MODEL = "opus";
const ROUTED_ALIASES = new Set(["haiku", "opus", "sonnet"]);
const EFFORTS = new Set(["low", "medium", "high", "xhigh", "max"]);

// The multi-agent role map (plugins/multi-agent/reference/defaults.yaml) as
// data, or null when its text is absent or does not parse (an alias included).
function roleMapOf(text) {
  if (typeof text !== "string") {
    return null;
  }
  const document = parseDocument(text, { maxAliasCount: 0, merge: false, uniqueKeys: true });
  if (document.errors.length > 0) {
    return null;
  }
  let map;
  try {
    map = document.toJS({ maxAliasCount: 0 });
  } catch {
    return null;
  }
  return isObject(map?.roles) ? map : null;
}

const roleOf = (roleMap, name) =>
  roleMap !== null && Object.hasOwn(roleMap.roles, name) && isObject(roleMap.roles[name])
    ? roleMap.roles[name]
    : {};

// A role profile's model and effort from the role map: the workload's value
// over the role's own, `effort-role` naming the role whose effort applies.
function roleModels(values, roleMapText) {
  const roleMap = roleMapOf(roleMapText);
  const role = roleOf(roleMap, values.role);
  const workload = isObject(role.workloads) && isObject(role.workloads[values.workload])
    ? role.workloads[values.workload]
    : {};
  const model = workload.model ?? role.model;
  const effortRole = values["effort-role"] === undefined ? undefined : roleOf(roleMap, values["effort-role"]);
  const effort = effortRole === undefined ? (workload.effort ?? role.effort) : effortRole.effort;
  return {
    role: values.role,
    ...(values.workload === undefined ? {} : { workload: values.workload }),
    model: ROUTED_ALIASES.has(model) ? model : FALLBACK_MODEL,
    effort: EFFORTS.has(effort) ? effort : null,
  };
}

// The profile a route takes, with every default applied: its route's profile,
// else default-profile; the built-in one when the config has no `models`.
const routeProfile = (models, route) => {
  const routes = models.routes ?? {};
  return Object.hasOwn(routes, route) ? routes[route] : models["default-profile"];
};

// A profile's resolved values, at `rung` 1 its escalate-to profile's: one
// rung at most, never the escalate-to's own, and a profile with no rung above
// is refused, so a retry never reruns the same model. A role profile takes
// its model and effort from the role map.
function profileModels(models, start, roleMapText, rung = 0) {
  const climbed = rung === 1 ? models.profiles[start]["escalate-to"] : undefined;
  if (rung === 1 && climbed === undefined) {
    throw new Rejection("no-rung-up", `model rung 1 asks for the rung above profile \`${start}\`, which names no escalate-to`);
  }
  const profile = climbed ?? start;
  const values = models.profiles[profile];
  return {
    profile,
    ...(values.role === undefined
      ? { model: values.model, effort: values.effort ?? null }
      : roleModels(values, roleMapText)),
    "subagent-model": values["subagent-model"] ?? "inherit",
    "max-turns": values["max-turns"],
  };
}

// The Claude Code arguments a resolved profile sets: `--model` unless the
// model is `default`, `--max-turns`, and `--effort` only when the profile sets
// one. Every value is a schema enum or integer, never free text.
export function modelArgs(models) {
  return [
    ...(models.model === "default" ? [] : ["--model", models.model]),
    "--max-turns",
    String(models["max-turns"]),
    ...(models.effort === null ? [] : ["--effort", models.effort]),
  ].join(" ");
}

// The settings JSON a resolved profile sets: the subagent model as settings
// env, or empty for `inherit`.
export function modelSettings(models) {
  return models["subagent-model"] === "inherit"
    ? ""
    : JSON.stringify({ env: { CLAUDE_CODE_SUBAGENT_MODEL: models["subagent-model"] } });
}

const routeModels = (models = BUILTIN_MODELS, route, roleMapText, rung = 0) =>
  profileModels(models, routeProfile(models, route), roleMapText, rung);

// The model rung a run asks for: 0 (or none) is its profile, 1 the rung above.
function checkRung(rung) {
  if (rung !== undefined && rung !== 0 && rung !== 1) {
    throw new Rejection("invalid-rung", `model rung \`${rung}\` is neither 0 nor 1`);
  }
  return rung ?? 0;
}

// The resolved profile of a run that is no lane activity (RUN_ROUTES), after
// the same file checks as resolve().
export function resolveRoute(files, { route, configPath }) {
  if (!RUN_ROUTES.has(route)) {
    throw new Rejection(
      "undefined-route",
      `\`${route}\` is not a run route; one of ${[...RUN_ROUTES].join(", ")} is required`,
    );
  }
  return routeModels(loadConfig(files, { configPath }).models, route, files.roleMap);
}

function resolveSlot(
  { name, activity, predicate, predicates, enabled, needs },
  { effectGrants, codeowners, trustedActors, roleMap },
  facts,
  decided,
  models,
  pinnedDimensions,
  rung,
  extraGrant,
) {
  const grant = grantFor(effectGrants, activity.effect, extraGrant);
  let outcome = { applies: null, skipReason: null };
  if (!enabled) {
    outcome = { applies: false, skipReason: "disabled-by-config" };
  } else if (decided) {
    outcome = appliesAll(predicates, facts);
  }
  let targets;
  if (outcome.applies && (activity.inputs ?? []).includes("changed-paths")) {
    if (facts.changedTargets === undefined) {
      throw new MissingFact("changedTargets");
    }
    // A composite's paths predicate narrows its leaves' targets too.
    const ancestors =
      predicate === undefined ? predicates : predicates.slice(0, -1);
    targets = changedPathTargets({
      paths: facts.changedTargets.filter((path) =>
        ancestors.every(
          (outer) =>
            outer.paths === undefined ||
            outer.paths.some((glob) => posix.matchesGlob(path, glob)),
        ),
      ),
      predicatePaths: predicate?.paths,
      edits: activity.effect !== "read" || activity["applied-by"]?.patch !== undefined,
      codeowners,
    });
    if (targets.length === 0) {
      outcome = { applies: false, skipReason: "not-applicable-paths" };
    }
  }
  const kind = activity.skill === undefined ? "script" : "skill";
  let runModels = kind === "skill" ? routeModels(models, name, roleMap, rung) : null;
  let sizing = {};
  if (dimensionedBy(activity, models)) {
    const config = models["issue-dimensions"];
    let dims;
    if (pinnedDimensions) {
      // What an earlier resolve read for this run, whose job timeout is
      // already fixed: the fields are not read again.
      dims = parsePin(pinnedDimensions, config);
    } else if (decided) {
      for (const fact of ["fieldValues", "fieldSetters"]) {
        if (facts[fact] === undefined) {
          throw new MissingFact(fact);
        }
      }
      dims = issueDimensions(facts, config, trustedActors);
    } else {
      dims = parsePin("not-assessed", config);
    }
    const budget = dimensionBudget(dims, config);
    if (budget.skip !== null && outcome.applies) {
      outcome = { applies: false, skipReason: budget.skip };
    }
    if (budget.skip === null) {
      // The issue's Complexity may pick the profile the run starts on.
      const start = config["complexity-profiles"]?.[dims.complexity];
      if (start !== undefined) {
        runModels = profileModels(models, start, roleMap, rung);
      }
      runModels = { ...runModels, "max-turns": budget["max-turns"] };
    }
    sizing = { "issue-dimensions": budget.pin, "timeout-minutes": budget["timeout-minutes"] };
  }
  return {
    name,
    kind,
    [kind]: activity[kind],
    ...(activity.args === undefined ? {} : { args: activity.args }),
    ...(activity.prepare === undefined ? {} : { prepare: activity.prepare }),
    ...(activity.checks === undefined ? {} : { checks: activity.checks }),
    ...(activity["self-checks"] === undefined ? {} : { "self-checks": activity["self-checks"] }),
    ...(activity["verify-scripts"] === undefined ? {} : { "verify-scripts": activity["verify-scripts"] }),
    ...(activity["web-access"] === undefined ? {} : { "web-access": activity["web-access"] }),
    ...(activity["permission-mode"] === undefined ? {} : { "permission-mode": activity["permission-mode"] }),
    ...(activity["applied-by"] === undefined ? {} : { "applied-by": activity["applied-by"] }),
    effect: activity.effect,
    gating: activity.gating,
    "reads-untrusted": activity["reads-untrusted"],
    scope: activity.scope ?? "diff",
    inputs: activity.inputs ?? [],
    needs,
    ...(predicate === undefined ? {} : { "applies-when": predicate }),
    enabled,
    models: runModels,
    ...sizing,
    grant,
    applies: outcome.applies,
    "skip-reason": outcome.skipReason,
    ...(outcome.applies && targets ? { "changed-paths": targets } : {}),
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
  if (!entry.enabled) {
    throw new Rejection(
      "slot-disabled",
      `lane \`${lane}\` disables activity \`${activity}\`; a disabled slot gets no grant`,
    );
  }
  return {
    effect: entry.activity.effect,
    grant: grantFor(
      files.effectGrants,
      entry.activity.effect,
      activityGrantOf(files.laneRules, lane, activity),
    ),
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

// The `limits` leaf with every default applied, in hours and counts; the lane
// scripts' copy of these defaults is
// .github/scripts/work-resolve-issue/limits.mjs.
const limitsOf = (limits = {}) => ({
  "fallback-reset": limits["fallback-reset"] ?? 5,
  "reset-clamp-min": limits["reset-clamp-min"] ?? 1,
  "reset-clamp-max": limits["reset-clamp-max"] ?? 168,
  "restarts-per-run": limits["restarts-per-run"] ?? 5,
  "limit-stops-per-head": limits["limit-stops-per-head"] ?? 3,
  "limit-stops-per-issue": limits["limit-stops-per-issue"] ?? 3,
  "wip-cap": limits["wip-cap"] ?? 60,
  "turn-cap-restarts": limits["turn-cap-restarts"] ?? 0,
  "fix-ci-per-run": limits["fix-ci-per-run"] ?? 2,
  "fix-ci-restarts": limits["fix-ci-restarts"] ?? 1,
  "fix-docs-per-run": limits["fix-docs-per-run"] ?? 2,
  "admission-factor": limits["admission-factor"] ?? 0.8,
  "admission-min-per-hour": limits["admission-min-per-hour"] ?? 1,
});

const loopOf = (loop = {}) => ({
  "review-rounds": loop["review-rounds"] ?? 2,
  "no-progress": loop["no-progress"] ?? 3,
  "dependency-review-rounds": loop["dependency-review-rounds"] ?? 2,
  "fix-ci-rounds": loop["fix-ci-rounds"] ?? 3,
});

// The resolved loop caps alone, after the same file checks as resolve(), for
// a job that resolves no lane slot (pr-unblock.yml's fix-ci-context).
export function resolveLoop(files, { configPath }) {
  return loopOf(loadConfig(files, { configPath }).loop);
}

// The resolved limits alone, after the same file checks as resolve(), for a
// run that resolves no lane slot (pr-unblock-dispatch.yml).
export function resolveLimits(files, { configPath }) {
  return limitsOf(loadConfig(files, { configPath }).limits);
}

// The wip leaf as set, after the same file checks as resolve(), for the WIP
// cap check. Its defaults have one copy, WIP_DEFAULTS in
// .github/scripts/work-resolve-issue/limits.mjs, which its readers apply;
// this module imports nothing outside this action's sparse checkout.
export function resolveWipLeaf(files, { configPath }) {
  return loadConfig(files, { configPath }).wip ?? {};
}

export function resolve(
  files,
  { lane, activity, configPath, basePath, facts, pinnedDimensions, rung },
) {
  const modelRung = checkRung(rung);
  const doc = loadConfig(files, { configPath });
  const section = laneSection(doc, lane);
  const entries = laneSlots(doc, lane);
  const index = selectedIndex(entries, lane, activity);
  const slots = entries.map((entry, i) =>
    // Only the selected slot runs, so only it climbs.
    resolveSlot(
      entry,
      files,
      facts,
      decides(i, index),
      doc.models,
      pinnedDimensions,
      i === index ? modelRung : 0,
      activityGrantOf(files.laneRules, lane, entry.name),
    ),
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
    loop: loopOf(doc.loop),
    limits: limitsOf(doc.limits),
    wip: doc.wip ?? {},
    merge: resolveMerge(doc.merge, configPath),
  };
}
