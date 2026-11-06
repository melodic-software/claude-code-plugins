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

// The one state a bot-setters account's value never counts for.
const PERSON_ONLY_STATE = "agent-ready";
// The job token's bot, the one bot-setters entry trusted-actors.json does not list.
const ACTIONS_BOT = { id: 41898282, login: "github-actions[bot]" };
// The lanes App counts through trustedOption already, agent-ready included.
const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";

// The state the issue's Work status field holds, or null when no trusted
// account set it. `facts` and `trustedActors` are issueDimensions'. A listed
// human or the lanes App counts for every state; a `bot-setters` account for
// every state but agent-ready, github-actions[bot] always and a `melodic-` bot
// only while `trustedActors` lists it as a bot with the same id and login (one
// the list dropped reads as unset). `facts.fieldNames`, when given, maps a
// field id to the option name its newest field event left: a value that
// names another option than the REST value maps to reads as unset, since the
// setter read belongs to another write. An option a counted setter chose that
// the config does not map stops the read: GitHub's options drifted.
export function issueStatus(facts, config, trustedActors) {
  const unmapped = (option) =>
    new Rejection(
      "unmapped-status",
      `issue field ${config["field-id"]} (Work status) holds option ${option}, which models.issue-status does not map`,
    );
  const fieldId = config["field-id"];
  const setter = facts.fieldSetters[String(fieldId)];
  const named = facts.fieldNames?.[String(fieldId)];
  const held = facts.fieldValues.find((value) => value.field === fieldId);
  if (typeof named === "string" && held !== undefined && config.options[String(held.option)] !== named) {
    return null;
  }
  const actors = Array.isArray(trustedActors?.actors) ? trustedActors.actors : [];
  const listed = ({ id, login }) =>
    (id === ACTIONS_BOT.id && login === ACTIONS_BOT.login) ||
    actors.some((actor) => actor?.id === id && actor?.login === login && actor?.kind === "bot");
  if (!(config["bot-setters"] ?? []).some((entry) => entry.id === setter && listed(entry))) {
    return trustedOption(facts, config, trustedActors, unmapped);
  }
  const row = facts.fieldValues.find((value) => value.field === fieldId);
  if (row === undefined) {
    return null;
  }
  const option = String(row.option);
  if (!Object.hasOwn(config.options, option)) {
    throw unmapped(option);
  }
  const state = config.options[option];
  return state === PERSON_ONLY_STATE ? null : state;
}

// What the schema cannot check: no two options name one state, every state has
// labels no other state has, order lists every state once and ends on the
// floor, and the field is none of models.issue-dimensions'. Each `bot-setters`
// entry is github-actions[bot] or a `melodic-` bot other than the lanes App,
// and no id is listed twice. Whether the trusted-actor list still holds an
// entry is issueStatus's to read, not a config error.
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
  const setters = config["bot-setters"] ?? [];
  const ids = setters.map((entry) => entry.id);
  const repeated = ids.find((id, i) => ids.indexOf(id) !== i);
  if (repeated !== undefined) {
    reject(`.bot-setters lists id ${repeated} twice`);
  }
  for (const { id, login } of setters) {
    if (login === ACTIONS_BOT.login || id === ACTIONS_BOT.id) {
      if (login !== ACTIONS_BOT.login || id !== ACTIONS_BOT.id) {
        reject(`.bot-setters names ${login} (${id}); github-actions[bot] is ${ACTIONS_BOT.id}`);
      }
      continue;
    }
    if (login === LANES_APP_LOGIN || !/^melodic-.+\[bot\]$/.test(login)) {
      reject(`.bot-setters names ${login}, which is neither github-actions[bot] nor a melodic- bot other than the lanes App`);
    }
  }
}
