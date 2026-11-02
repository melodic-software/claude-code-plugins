// The issue status (models.issue-status): an issue's state as its Work status
// org issue field, keyed on field and option ids, and the state its labels
// collapse to. Pure: the caller fetches the facts.
import { Rejection } from "./resolve.mjs";

// The label names on an issue, from names or REST label objects.
const labelNames = (labels) => new Set((labels ?? []).map((label) => (typeof label === "string" ? label : label?.name)));

// The state an issue's labels collapse to: the first state in `order` whose
// label the issue carries, else the last state in `order`.
export function collapseStatus(labels, config) {
  const names = labelNames(labels);
  return config.order.find((state) => names.has(config.labels[state])) ?? config.order.at(-1);
}

// The option id a state is written as, for a writer to check GitHub's answer.
export function statusOption(state, config) {
  const option = Object.keys(config.options).find((id) => config.options[id] === state);
  if (option === undefined) {
    throw new Rejection("undefined-status", `models.issue-status maps no option to \`${state}\``);
  }
  return Number(option);
}

// The state the issue's Work status field holds, or null when it holds none.
// `fieldValues` is the REST issue-field-values rows as {field, option} ids. An
// option the config does not map stops the read: GitHub's options drifted.
export function issueStatus(fieldValues, config) {
  const fieldId = config["field-id"];
  const row = fieldValues.find((value) => value.field === fieldId);
  if (row === undefined || row.option === null || row.option === undefined) {
    return null;
  }
  const option = String(row.option);
  if (!Object.hasOwn(config.options, option)) {
    throw new Rejection(
      "unmapped-status",
      `issue field ${fieldId} (Work status) holds option ${option}, which models.issue-status does not map`,
    );
  }
  return config.options[option];
}

// What the schema cannot check: no two options name one state, every state has
// one label no other state has, and order lists every state once.
export function checkStatus(config) {
  const states = Object.values(config.options);
  const twice = states.find((state, i) => states.indexOf(state) !== i);
  if (twice !== undefined) {
    throw new Rejection("undefined-status", `models.issue-status maps two options to \`${twice}\``);
  }
  for (const state of Object.keys(config.labels)) {
    if (!states.includes(state)) {
      throw new Rejection("undefined-status", `models.issue-status.labels names \`${state}\`, which no option maps`);
    }
  }
  const labels = states.map((state) => config.labels[state]);
  const missing = states.find((state) => config.labels[state] === undefined);
  if (missing !== undefined) {
    throw new Rejection("undefined-status", `models.issue-status.labels gives \`${missing}\` no label`);
  }
  const shared = labels.find((label, i) => labels.indexOf(label) !== i);
  if (shared !== undefined) {
    throw new Rejection("undefined-status", `models.issue-status.labels gives \`${shared}\` to two states`);
  }
  const { order } = config;
  if (order.length !== states.length || states.some((state) => !order.includes(state))) {
    throw new Rejection("undefined-status", "models.issue-status.order must list every mapped state once");
  }
}
