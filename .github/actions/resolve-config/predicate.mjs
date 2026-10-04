// `applies-when` over the facts of one run: every listed key must match, and
// within a key any listed value matches.
import { posix } from "node:path";

export class MissingFact extends Error {
  constructor(fact) {
    super(
      `an applies-when predicate needs ${fact}, which this run did not supply`,
    );
    this.name = "MissingFact";
  }
}

// Predicate key, the fact it reads, and the test of one listed value.
const KEYS = [
  [
    "paths",
    "changedPaths",
    (glob, paths) => paths.some((path) => posix.matchesGlob(path, glob)),
  ],
  ["labels", "labels", (label, labels) => labels.includes(label)],
  ["work-classes", "workClasses", (cls, classes) => classes.includes(cls)],
  ["events", "event", (event, current) => event === current],
];

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
export function factsFor(predicate) {
  return KEYS.filter(
    ([key, fact]) => predicate?.[key] !== undefined && fact !== "event",
  ).map(([, fact]) => fact);
}

export function applies(predicate, facts) {
  let miss = null;
  for (const [key, fact, matches] of KEYS) {
    const listed = predicate?.[key];
    if (listed === undefined) {
      continue;
    }
    if (facts[fact] === undefined) {
      throw new MissingFact(fact);
    }
    if (!listed.some((value) => matches(value, facts[fact]))) {
      if (key === "paths") {
        return { applies: false, skipReason: "not-applicable-paths" };
      }
      miss = "not-applicable";
    }
  }
  return miss === null
    ? { applies: true, skipReason: null }
    : { applies: false, skipReason: miss };
}
