// The issue status (models.issue-status): an issue's state as its Work status
// org issue field, keyed on field and option ids, and the state its labels
// collapse to. Pure: the caller fetches the facts.
import { trustedOption } from "./dimensions.mjs";
import { Rejection } from "./resolve.mjs";

// The state an issue carrying no state label collapses to, and so the last in
// order.
const FLOOR = "needs-triage";

// GitHub label names compare without case.
const fold = (name) => String(name).toLowerCase();

// The folded label names on an issue, from names or REST label objects.
const labelNames = (labels) =>
  new Set((labels ?? []).map((label) => fold(typeof label === "string" ? label : label?.name)));

// The state an issue's labels collapse to: the first state in `order` one of
// whose labels the issue carries, else the last state in `order`.
export function collapseStatus(labels, config) {
  const names = labelNames(labels);
  return config.order.find((state) => config.labels[state].some((label) => names.has(fold(label)))) ?? config.order.at(-1);
}

// The option id a state is written as, for a writer to check GitHub's answer.
export function statusOption(state, config) {
  const option = Object.keys(config.options).find((id) => config.options[id] === state);
  if (option === undefined) {
    throw new Rejection("undefined-status", `models.issue-status maps no option to \`${state}\``);
  }
  return Number(option);
}

// The state the issue's Work status field holds, or null when no trusted
// account set it. `facts` and `trustedActors` are issueDimensions'; an option
// a trusted setter chose that the config does not map stops the read: GitHub's
// options drifted.
export function issueStatus(facts, config, trustedActors) {
  return trustedOption(
    facts,
    config,
    trustedActors,
    (option) =>
      new Rejection(
        "unmapped-status",
        `issue field ${config["field-id"]} (Work status) holds option ${option}, which models.issue-status does not map`,
      ),
  );
}

// What the schema cannot check: no two options name one state, every state has
// labels no other state has, order lists every state once and ends on the
// floor, and the field is none of models.issue-dimensions'.
export function checkStatus(config, dimensions) {
  const reject = (message) => {
    throw new Rejection("undefined-status", `models.issue-status${message}`);
  };
  const states = Object.values(config.options);
  const twice = states.find((state, i) => states.indexOf(state) !== i);
  if (twice !== undefined) {
    reject(` maps two options to \`${twice}\``);
  }
  for (const state of Object.keys(config.labels)) {
    if (!states.includes(state)) {
      reject(`.labels names \`${state}\`, which no option maps`);
    }
  }
  const missing = states.find((state) => !(config.labels[state]?.length > 0));
  if (missing !== undefined) {
    reject(`.labels gives \`${missing}\` no label`);
  }
  const labels = states.flatMap((state) => config.labels[state].map(fold));
  const shared = labels.find((label, i) => labels.indexOf(label) !== i);
  if (shared !== undefined) {
    reject(`.labels lists \`${shared}\` twice`);
  }
  const { order } = config;
  if (order.length !== states.length || states.some((state) => !order.includes(state))) {
    reject(".order must list every mapped state once");
  }
  if (order.at(-1) !== FLOOR) {
    reject(`.order must end on \`${FLOOR}\`, what an issue with no state label reads as`);
  }
  const dimensionFields = Object.values(dimensions?.fields ?? {}).map((field) => field["field-id"]);
  if (dimensionFields.includes(config["field-id"])) {
    reject(".field-id is a models.issue-dimensions field");
  }
}
