import { readFileSync } from "node:fs";
import { join } from "node:path";

import { FIELD_API } from "./write-status.mjs";

const STANDARDS_TRUSTED_ACTORS = "components/trusted-actors/trusted-actors.json";
export const HOLD_STATES = ["needs-human", "needs-owner-decision", "needs-reporter-info", "needs-spec"];
const LABEL_STATE = "agent-ready";
export class StatusReadError extends Error {
  constructor(number, cause) {
    super(`#${number}'s Work status could not be read: ${cause?.message ?? cause}`, { cause });
    this.name = "StatusReadError";
    this.number = number;
  }
}
const annotate = (line) => String(line).replaceAll(/[\r\n%]/g, " ");
const fold = (name) => String(name).toLowerCase();

export const DECISION_LABELS = Object.freeze(["needs-owner-decision"]);
export const INFO_LABELS = Object.freeze(["needs-reporter-info"]);
const HOLD_NAMES = new Set([...DECISION_LABELS, ...INFO_LABELS]);
export const carried = (labels, names) => names.find((name) => labels.includes(name));
export const isStatusLabel = (name) => fold(name).startsWith("status:") || HOLD_NAMES.has(fold(name));

export function statusLabels(state, names, config) {
  if (state === null || state === undefined || !config) {
    return names;
  }
  const queue = new Set(
    Object.keys(config.labels)
      .filter((one) => !HOLD_STATES.includes(one))
      .flatMap((one) => config.labels[one].map(fold)),
  );
  const kept = names.filter((name) => !queue.has(fold(name)));
  const label = config.labels[state]?.[0];
  return label === undefined || kept.some((name) => fold(name) === fold(label)) ? kept : [...kept, label];
}

export async function readyWhileDeferred(field, own, fieldDeferred = async () => false) {
  if (!field.includes("admission-deferred") || field.includes("status: ready")) {
    return field;
  }
  const lost = own.includes("admission-deferred") && !own.includes("status: ready") && !(await fieldDeferred());
  return lost ? field : [...field, "status: ready"];
}

export function syntheticFrom(event, config) {
  const actor = { id: event.actorId, login: event.actorType === "Bot" ? `${event.actorLogin}[bot]` : event.actorLogin, type: event.actorType };
  return [
    ["unlabeled", event.from],
    ["labeled", event.to],
  ].flatMap(([kind, state]) => {
    const name = state === LABEL_STATE ? undefined : config.labels[state]?.[0];
    return name === undefined ? [] : [{ id: null, event: kind, label: { name }, actor, created_at: event.at }];
  });
}

export async function statusEvents({ github, repository, number, config, since = config?.["field-events-since"], fieldEvents }) {
  const { paginate } = await import("../../scripts/lib/github-client.mjs");
  const events = fieldEvents ?? (await import("./resolve-config.mjs")).fieldEvents;
  const rest = await paginate(github, `/repos/${repository}/issues/${number}/events`);
  const cutoff = since ? Date.parse(since) : Number.NEGATIVE_INFINITY;
  const field = String(config["field-id"]);
  const synthetic = (await events(github, repository, number))
    .filter((event) => event.field === field && !(event.actorType === "Bot" && Date.parse(event.at) < cutoff))
    .flatMap((event) => syntheticFrom(event, config));
  const keyed = [...rest.map((event) => [0, event]), ...synthetic.map((event) => [1, event])];
  keyed.sort(([a, x], [b, y]) => Date.parse(x.created_at) - Date.parse(y.created_at) || a - b || (a === 0 ? x.id - y.id : 0));
  return keyed.map(([, event]) => event);
}

export function loadTrustedActors(env = {}) {
  const path = env.STANDARDS_DIR ? join(env.STANDARDS_DIR, STANDARDS_TRUSTED_ACTORS) : env.TRUSTED_ACTORS_PATH;
  if (!path) {
    throw new Error("no standards checkout (STANDARDS_DIR is unset), so the trusted-actor list cannot be read");
  }
  return JSON.parse(readFileSync(path, "utf8"));
}

export async function fieldStatus(read) {
  return (await fieldStatusSetter(read)).state;
}

export const DISAGREEMENT_WAIT_MS = 3000;

export async function fieldStatusSetter({ github, repository, number, config, trustedActors, issueStatusSetter, fieldEvents, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)) }) {
  const status = issueStatusSetter ?? (await import("./issue-status.mjs")).issueStatusSetter;
  const events = fieldEvents ?? (await import("./resolve-config.mjs")).fieldEvents;
  const readOnce = async (options) => {
    const rows = await github("GET", `/repos/${repository}/issues/${number}/issue-field-values`, undefined, FIELD_API);
    if (!Array.isArray(rows)) {
      throw new Error("its field values answered something other than a list");
    }
    const facts = {
      fieldValues: rows.map((row) => ({ field: row?.issue_field_id, option: row?.single_select_option?.id ?? null })),
      fieldEvents: await events(github, repository, number, options),
    };
    facts.fieldEventsFull = facts.fieldEvents.full === true;
    return status(facts, config, trustedActors);
  };
  try {
    return await readOnce();
  } catch (error) {
    if (error?.name !== "StatusDisagreement") {
      throw error;
    }
    await sleep(DISAGREEMENT_WAIT_MS);
    return readOnce({ again: true });
  }
}

/**
 * What a reader's entry point hands its run: `labels(number, names)`, the
 * issue's label names as the field decides them (statusLabels), read fresh on
 * each call, since a reader may ask again after the status changed, and at
 * most `limit` reads a run. `labels.events(number)` is statusEvents for the
 * issue, reusing the field events the newest `labels` call for it read, and
 * `labels.state(number)` the trusted state that call read (null when unset),
 * reading it only when no call has. A failed read, or one past the limit,
 * throws StatusReadError from any of them.
 * `config` and `trustedActors` default to the base config's models.issue-status
 * and the trusted-actor list (loadTrustedActors: STANDARDS_DIR, else
 * TRUSTED_ACTORS_PATH, never BASE_PATH).
 * An unset config reads nothing: labels and REST events come back as they
 * are; a config or trusted-actor list that cannot be loaded
 * makes every call throw.
 * `github` is a createGitHub client.
 */
export function statusReader({ env = {}, github, repository, log = console.log, limit = Infinity, config, trustedActors, sleep }) {
  let setup;
  const prepare = async () => {
    try {
      const { fieldEvents, issueStatusFromBase } = await import("./resolve-config.mjs");
      const { issueStatusSetter } = await import("./issue-status.mjs");
      const leaf = config === undefined ? issueStatusFromBase(env) : config;
      if (!leaf) {
        return null;
      }
      const actors = trustedActors ?? loadTrustedActors(env);
      return { config: leaf, trustedActors: actors, issueStatusSetter, fieldEvents };
    } catch (error) {
      log(`::warning title=work-status::the Work status config could not be loaded, so every status read fails: ${annotate(error?.message ?? error)}`);
      return { error };
    }
  };
  const ready = async () => {
    if (setup === undefined) {
      setup = await prepare();
    }
    return setup;
  };
  const read = new Map();
  const states = new Map();
  let reads = 0;
  const fieldEventsOf = (number) => {
    if (!read.has(number)) {
      reads += 1;
      read.set(number, setup.fieldEvents(github, repository, number));
    }
    return read.get(number);
  };
  const overLimit = (issue) => {
    if (setup.error !== undefined) {
      throw new StatusReadError(issue, setup.error);
    }
    if (!read.has(issue) && reads >= limit) {
      throw new StatusReadError(issue, `the reader's limit of ${limit} field reads is reached`);
    }
  };
  const labels = async (number, names) => {
    if ((await ready()) === null) {
      return names;
    }
    const issue = Number(number);
    read.delete(issue);
    states.delete(issue);
    overLimit(issue);
    try {
      const state = await fieldStatus({
        github,
        repository,
        number: issue,
        ...setup,
        ...(sleep ? { sleep } : {}),
        fieldEvents: (_github, _repository, _number, options) => {
          if (options?.again) {
            read.set(issue, setup.fieldEvents(github, repository, issue));
          }
          return fieldEventsOf(issue);
        },
      });
      states.set(issue, state);
      return statusLabels(state, names, setup.config);
    } catch (error) {
      throw new StatusReadError(issue, error);
    }
  };
  labels.state = async (number) => {
    const issue = Number(number);
    if (!states.has(issue) && (await ready()) !== null) {
      await labels(issue, []);
    }
    return states.get(issue) ?? null;
  };
  labels.unset = async (number) => (await ready()) !== null && (await labels.state(number)) === null;
  labels.events = async (number) => {
    const issue = Number(number);
    if ((await ready()) === null) {
      return (await import("../../scripts/lib/github-client.mjs")).paginate(github, `/repos/${repository}/issues/${issue}/events`);
    }
    overLimit(issue);
    try {
      return await statusEvents({ github, repository, number: issue, config: setup.config, fieldEvents: () => fieldEventsOf(issue) });
    } catch (error) {
      throw new StatusReadError(issue, error);
    }
  };
  labels.fieldRows = async (number) => {
    const issue = Number(number);
    if ((await ready()) === null) {
      return [];
    }
    overLimit(issue);
    try {
      return await fieldEventsOf(issue);
    } catch (error) {
      throw new StatusReadError(issue, error);
    }
  };
  return labels;
}
