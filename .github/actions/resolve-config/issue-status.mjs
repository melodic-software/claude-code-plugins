import { trustedOption, trustedSetters } from "./dimensions.mjs";
import { Rejection } from "./resolve.mjs";

const FLOOR = "needs-triage";

export class StatusDisagreement extends Error {
  constructor(message) {
    super(message);
    this.name = "StatusDisagreement";
  }
}

const fold = (name) => String(name).toLowerCase();

const labelNames = (labels) =>
  new Set((labels ?? []).map((label) => fold(typeof label === "string" ? label : label?.name)));

export function collapseStatus(labels, config) {
  const names = labelNames(labels);
  return config.order.find((state) => config.labels[state].some((label) => names.has(fold(label)))) ?? config.order.at(-1);
}

export function statusOption(state, config) {
  const option = Object.keys(config.options).find((id) => config.options[id] === state);
  if (option === undefined) {
    throw new Rejection("undefined-status", `models.issue-status maps no option to \`${state}\``);
  }
  return Number(option);
}

const PERSON_ONLY_STATE = "agent-ready";
const ACTIONS_BOT = { id: 41898282, login: "github-actions[bot]" };
const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";

export function statusBotSetters(trustedActors, config) {
  const actors = Array.isArray(trustedActors?.actors) ? trustedActors.actors : [];
  const explicit = config?.["bot-setters"];
  if (Array.isArray(explicit)) {
    return explicit
      .filter(
        ({ id, login }) =>
          (id === ACTIONS_BOT.id && login === ACTIONS_BOT.login) ||
          actors.some((actor) => actor?.id === id && actor?.login === login && actor?.kind === "bot"),
      )
      .map(({ id, login }) => ({ id, login }));
  }
  const melodic = actors.filter(
    (actor) => actor?.kind === "bot" && typeof actor.login === "string" && actor.login.startsWith("melodic-") && actor.login !== LANES_APP_LOGIN,
  );
  return [ACTIONS_BOT, ...melodic.map(({ id, login }) => ({ id, login }))];
}

export function issueStatus(facts, config, trustedActors) {
  return issueStatusSetter(facts, config, trustedActors).state;
}

export function issueStatusSetter(facts, config, trustedActors) {
  const fieldId = config["field-id"];
  const unmapped = (option) =>
    new Rejection(
      "unmapped-status",
      `issue field ${fieldId} (Work status) holds option ${option}, which models.issue-status does not map`,
    );
  const bots = statusBotSetters(trustedActors, config);
  const botSetter = (id) => bots.some((entry) => entry.id === id);
  const row = facts.fieldValues.find((value) => value.field === fieldId);
  if (Array.isArray(facts.fieldEvents)) {
    const people = trustedSetters(trustedActors);
    const states = new Set(Object.values(config.options));
    const events = facts.fieldEvents.filter((event) => event?.field === String(fieldId));
    const rest = row === undefined ? null : config.options[String(row.option)];
    if (events.length > 0 && rest !== undefined && (events.at(-1).to ?? null) !== rest) {
      const left = events.at(-1).to === null ? "removed it" : `set \`${events.at(-1).to}\``;
      throw new StatusDisagreement(`issue field ${fieldId} (Work status) holds ${row === undefined ? "no value" : `option ${row.option}`}, but its newest field event ${left}`);
    }
    for (let i = events.length - 1; i >= 0; i -= 1) {
      const { actorId, removed, to } = events[i];
      const person = people.has(actorId);
      if (!person && !botSetter(actorId)) {
        continue;
      }
      const newest = i === events.length - 1;
      if (removed || (newest && row === undefined)) {
        return { state: null, setter: actorId };
      }
      const option = newest ? String(row.option) : to;
      const state = newest ? (Object.hasOwn(config.options, option) ? config.options[option] : undefined) : states.has(to) ? to : undefined;
      if (state === undefined) {
        throw unmapped(option);
      }
      if (person || state !== PERSON_ONLY_STATE) {
        return { state, setter: actorId };
      }
    }
    if (facts.fieldEventsFull && row !== undefined) {
      throw new Error(`issue field ${fieldId} (Work status) has no counted setter among its newest field events, and older ones were not read`);
    }
    return { state: null, setter: undefined };
  }
  const setter = facts.fieldSetters[String(fieldId)];
  const named = facts.fieldNames?.[String(fieldId)];
  if (typeof named === "string" && row !== undefined && config.options[String(row.option)] !== named) {
    throw new StatusDisagreement(`issue field ${fieldId} (Work status) holds option ${row.option}, but its newest field event set \`${named}\``);
  }
  if (!botSetter(setter)) {
    return { state: trustedOption(facts, config, trustedActors, unmapped), setter };
  }
  if (row === undefined) {
    return { state: null, setter };
  }
  const option = String(row.option);
  if (!Object.hasOwn(config.options, option)) {
    throw unmapped(option);
  }
  const state = config.options[option];
  return { state: state === PERSON_ONLY_STATE ? null : state, setter };
}

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
  const since = config["field-events-since"];
  if (since !== undefined && (typeof since !== "string" || Number.isNaN(Date.parse(since)) || new Date(since).toISOString().replace(".000Z", "Z") !== since)) {
    reject(`.field-events-since \`${since}\` is no ISO UTC time such as 2026-11-07T12:00:00Z`);
  }
}
