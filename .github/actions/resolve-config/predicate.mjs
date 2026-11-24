import { posix } from "node:path";

export class MissingFact extends Error {
  constructor(fact) {
    super(
      `an applies-when predicate needs ${fact}, which this run did not supply`,
    );
    this.name = "MissingFact";
  }
}

const matchesAny = (path, globs) =>
  globs.some((glob) => posix.matchesGlob(path, glob));

// The changed paths a predicate's `paths` and `paths-ignore` let through: a
// path matching a `paths` glob (any path when `paths` is absent) and no
// `paths-ignore` glob.
export function matchedPaths(predicate, changedPaths) {
  const paths = predicate?.paths;
  const ignored = predicate?.["paths-ignore"] ?? [];
  return changedPaths.filter(
    (path) =>
      (paths === undefined || matchesAny(path, paths)) &&
      !matchesAny(path, ignored),
  );
}

const any = (test) => (listed, fact) =>
  listed.some((value) => test(value, fact));
const somePathMatches = (_listed, paths, predicate) =>
  matchedPaths(predicate, paths).length > 0;
const KEYS = [
  ["paths", "changedPaths", somePathMatches],
  ["paths-ignore", "changedPaths", somePathMatches],
  ["labels", "labels", any((label, labels) => labels.includes(label))],
  [
    "labels-absent",
    "labels",
    (listed, labels) => !listed.some((label) => labels.includes(label)),
  ],
  ["events", "event", any((event, current) => event === current)],
  // null is unknown mergeability, which never matches.
  ["mergeable", "mergeable", any((state, current) => state === current)],
  ["draft", "draft", any((draft, current) => draft === current)],
];

const MISS_ORDER = ["awaiting-human", "not-applicable", "prerequisite-missing"];
const missReason = (key, fact) => {
  if (key === "labels-absent") {
    return "awaiting-human";
  }
  return key === "mergeable" && fact === null
    ? "prerequisite-missing"
    : "not-applicable";
};

const PULL_REQUEST_ACTIONS = {
  ready_for_review: "ready",
  synchronize: "synchronize",
  labeled: "labeled",
  unlabeled: "unlabeled",
  dequeued: "dequeued",
};

const EVENTS = {
  push: "push",
  schedule: "schedule",
  workflow_dispatch: "dispatch",
  workflow_run: "workflow-run",
};

export function pipelineEvent(eventName, payload) {
  if (eventName === "issues") {
    return payload.action === "labeled" || payload.action === "field_added" ? payload.action : null;
  }
  if (eventName === "pull_request") {
    if (payload.action === "opened") {
      return payload.pull_request?.draft === false ? "ready" : null;
    }
    return Object.hasOwn(PULL_REQUEST_ACTIONS, payload.action)
      ? PULL_REQUEST_ACTIONS[payload.action]
      : null;
  }
  return Object.hasOwn(EVENTS, eventName) ? EVENTS[eventName] : null;
}

// The facts a predicate reads that need an API call; `event` is always known.
// `freshLabels` asks for labels read from the PR now, never from the event
// payload, so a hold added after the event still holds a queued run.
export function factsFor(predicate) {
  const facts = KEYS.filter(
    ([key, fact]) => predicate?.[key] !== undefined && fact !== "event",
  ).map(([, fact]) => fact);
  if (predicate?.["labels-absent"] !== undefined) {
    facts.push("freshLabels");
  }
  return [...new Set(facts)];
}

export function applies(predicate, facts) {
  const misses = new Set();
  for (const [key, fact, matches] of KEYS) {
    const listed = predicate?.[key];
    if (listed === undefined) {
      continue;
    }
    if (facts[fact] === undefined) {
      throw new MissingFact(fact);
    }
    if (!matches(listed, facts[fact], predicate)) {
      if (fact === "changedPaths") {
        return { applies: false, skipReason: "not-applicable-paths" };
      }
      misses.add(missReason(key, facts[fact]));
    }
  }
  return outcome(misses);
}

function outcome(misses) {
  const miss = MISS_ORDER.find((reason) => misses.has(reason));
  return miss === undefined
    ? { applies: true, skipReason: null }
    : { applies: false, skipReason: miss };
}

// Several predicates that must all match, such as a composite's and its
// leaf's, with the same precedence as the keys of one predicate.
export function appliesAll(predicates, facts) {
  const misses = new Set(
    predicates
      .map((predicate) => applies(predicate, facts).skipReason)
      .filter((reason) => reason !== null),
  );
  return misses.has("not-applicable-paths")
    ? { applies: false, skipReason: "not-applicable-paths" }
    : outcome(misses);
}
