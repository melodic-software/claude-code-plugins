// `applies-when` over the facts of one run: every listed key must match, and
// within a key any listed value matches, except `labels-absent`, which matches
// only when none of its labels is on the PR or issue, `labeled-after`, one
// time an issue's label event must come after, and `admission` (admits()).
import { posix } from "node:path";

export class MissingFact extends Error {
  constructor(fact) {
    super(
      `an applies-when predicate needs ${fact}, which this run did not supply`,
    );
    this.name = "MissingFact";
  }
}

const WORK_CLASS = "work-class: ";

// An issue carrying a work-class label outside `classes` is refused, even
// beside a listed one. Otherwise it is admitted by a listed class or, with
// `ratified`, by the owner's ratification marker (the `ratified` fact).
function admits({ classes, ratified }, labels, facts) {
  if (labels.some((label) => label.startsWith(WORK_CLASS) && !classes.includes(label))) {
    return false;
  }
  return classes.some((cls) => labels.includes(cls)) || (ratified === true && facts.ratified);
}

// Predicate key, the fact it reads, and whether the listed values match the
// fact. Most keys match when any listed value does.
const any = (test) => (listed, fact) =>
  listed.some((value) => test(value, fact));
const KEYS = [
  [
    "paths",
    "changedPaths",
    any((glob, paths) => paths.some((path) => posix.matchesGlob(path, glob))),
  ],
  ["labels", "labels", any((label, labels) => labels.includes(label))],
  [
    "labels-absent",
    "labels",
    (listed, labels) => !listed.some((label) => labels.includes(label)),
  ],
  ["admission", "labels", admits],
  ["work-classes", "workClasses", any((cls, classes) => classes.includes(cls))],
  ["events", "event", any((event, current) => event === current)],
  [
    "labeled-after",
    "labeledAt",
    (after, labeledAt) => Date.parse(labeledAt) > Date.parse(after),
  ],
  // null is unknown mergeability, which never matches.
  ["mergeable", "mergeable", any((state, current) => state === current)],
  ["draft", "draft", any((draft, current) => draft === current)],
];

// A miss's skip reason when the predicate decides more than one key: a held PR
// first, since only a human resumes it, then a decided miss over an unknown.
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
    return payload.action === "labeled" ? "labeled" : null;
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
  if (predicate?.admission?.ratified === true) {
    facts.push("ratified");
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
    if (key === "admission" && listed.ratified === true && facts.ratified === undefined) {
      throw new MissingFact("ratified");
    }
    if (!matches(listed, facts[fact], facts)) {
      if (key === "paths") {
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
