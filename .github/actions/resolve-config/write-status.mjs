export const FIELD_API = { "X-GitHub-Api-Version": "2026-03-10" };

export const RESTART_GAP_MS = 3000;

const NAME_REFUSED = new Set([400, 422]);
const AGENT_READY = "agent-ready";
const HOST_RUN_OR_PARK_STOP_STATE = "confirmed";
const fold = (name) => String(name).toLowerCase();
const notFound = (error) => error?.status === 404 || /\bstatus 404\b/.test(String(error?.message ?? error));
const titleCased = (name) => name.charAt(0).toUpperCase() + name.slice(1);

export async function postOptionNames(post, values, titled, log = console.log) {
  const send = async (batch) => {
    try {
      return { rows: await post(batch) };
    } catch (error) {
      if (!NAME_REFUSED.has(error?.status)) {
        throw error;
      }
      return { error };
    }
  };
  const title = (value) => (titled.has(value.field_id) ? { ...value, value: titleCased(value.value) } : value);
  let { rows, error } = await send(values);
  if (error) {
    log(`GitHub refused the lowercase field names (${error.status} ${error.detail}); sending them Title-cased`);
    ({ rows, error } = await send(values.map(title)));
  }
  if (!error) {
    return rows;
  }
  log(`GitHub refused the Title-cased field names too (${error.status} ${error.detail}); sending each field on its own`);
  const answered = [];
  for (const value of values) {
    let write = await send([value]);
    if (write.error) {
      write = await send([title(value)]);
    }
    if (write.error) {
      throw write.error;
    }
    answered.push(...(Array.isArray(write.rows) ? write.rows : []));
  }
  return answered;
}

export class StatusWriteError extends Error {
  constructor(message, options) {
    super(message, options);
    this.name = "StatusWriteError";
  }
}

export async function writeState({ github, repository, number, state, config, current }) {
  const fail = (why, cause) => {
    throw new StatusWriteError(`#${number}'s Work status field was not set to \`${state}\`: ${why}`, cause === undefined ? undefined : { cause });
  };
  if (!config) {
    fail("models.issue-status is not set");
  }
  let option;
  try {
    const { statusOption } = await import("./issue-status.mjs");
    option = statusOption(state, config);
  } catch (error) {
    fail(error?.message ?? error, error);
  }
  if (current !== undefined && current !== null && Number(current) === option) {
    return { outcome: "unchanged", state, option };
  }
  const fieldId = config["field-id"];
  let written;
  try {
    written = await github(
      "POST",
      `/repos/${repository}/issues/${number}/issue-field-values`,
      { issue_field_values: [{ field_id: fieldId, value: state }] },
      FIELD_API,
      { resendOnce: true },
    );
  } catch (error) {
    fail(error?.message ?? error, error);
  }
  const row = (Array.isArray(written) ? written : []).find((value) => value?.issue_field_id === fieldId);
  if (row?.single_select_option?.id !== option) {
    fail(`GitHub kept option ${row?.single_select_option?.id ?? "none"}, not ${option}; models.issue-status has drifted from the field`);
  }
  return { outcome: "written", state, option };
}

export async function statusWriter({ env, github, repository, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), log = console.log }) {
  let config;
  let trustedActors;
  let failure;
  try {
    const { issueStatusFromBase } = await import("./resolve-config.mjs");
    config = issueStatusFromBase(env);
  } catch (error) {
    failure = new StatusWriteError(`models.issue-status could not be read: ${error?.message ?? error}`, { cause: error });
  }
  const wrote = new Map();
  const readField = async (number) => {
    try {
      const { fieldStatusSetter, HOLD_STATES, loadTrustedActors } = await import("./read-status.mjs");
      trustedActors ??= loadTrustedActors(env);
      const { state, setter } = await fieldStatusSetter({ github, repository, number, config, trustedActors });
      const person = (trustedActors?.actors ?? []).some((actor) => actor?.kind === "human" && actor?.id === setter);
      return { state, personHold: person && HOLD_STATES.includes(state) };
    } catch (error) {
      throw new StatusWriteError(`#${number}'s Work status field could not be read: ${error?.message ?? error}`, { cause: error });
    }
  };
  const clearStatusLabels = async (number) => {
    const path = `/repos/${repository}/issues/${number}/labels`;
    let names;
    let holds;
    try {
      const { paginate } = await import("../../scripts/lib/github-client.mjs");
      ({ HOLD_STATES: holds } = await import("./read-status.mjs"));
      names = (await paginate(github, path)).map((label) => String(label?.name ?? label));
    } catch (error) {
      throw new StatusWriteError(`#${number}'s labels could not be read before its agent-ready write: ${error?.message ?? error}`, { cause: error });
    }
    const states = Object.keys(config?.labels ?? {});
    const stateOf = (name) => states.find((one) => config.labels[one].some((label) => fold(label) === fold(name)));
    const stale = [];
    for (const name of names) {
      const one = stateOf(name);
      if (one !== undefined && holds.includes(one)) {
        return { outcome: "held", state: one };
      }
      if (one !== undefined && one !== AGENT_READY) {
        stale.push(name);
      }
    }
    const removed = [];
    for (const name of stale) {
      try {
        await github("DELETE", `${path}/${encodeURIComponent(name)}`);
        removed.push(name);
      } catch (error) {
        if (!notFound(error)) {
          throw new StatusWriteError(`#${number}'s status label \`${name}\` was not removed, so agent-ready was not set: ${error?.message ?? error}`, { cause: error });
        }
      }
    }
    return { removed };
  };
  const restoreAndThrow = async (number, removed, error) => {
    if (removed.length > 0) {
      try {
        await github("POST", `/repos/${repository}/issues/${number}/labels`, { labels: removed });
      } catch (putBack) {
        throw new StatusWriteError(`${error?.message ?? error}; the status labels it removed (${removed.join(", ")}) were not put back: ${putBack?.message ?? putBack}`, { cause: error });
      }
    }
    throw error;
  };
  const dropAgentReadyLabel = async (number) => {
    for (const name of config?.labels?.[AGENT_READY] ?? []) {
      try {
        await github("DELETE", `/repos/${repository}/issues/${number}/labels/${encodeURIComponent(name)}`);
      } catch (error) {
        if (!notFound(error)) {
          log(`::warning title=write-status::#${number}'s \`${name}\` label was not removed after its Work status left agent-ready: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
        }
      }
    }
  };
  const stopsLane = async (state) => state === HOST_RUN_OR_PARK_STOP_STATE || (await import("./read-status.mjs")).HOLD_STATES.includes(state);
  const set = async (number, state, { fields, keepHold, releases, from } = {}) => {
    if (failure) {
      throw failure;
    }
    const fresh = keepHold || Array.isArray(from);
    if (fresh) {
      const now = await readField(number);
      if (keepHold && now.personHold && now.state !== releases) {
        return { outcome: "held", state: now.state };
      }
      if (now.state === state) {
        return { outcome: "unchanged", state };
      }
      if (Array.isArray(from) && !from.includes(now.state ?? null)) {
        return { outcome: "moved", state: now.state };
      }
    }
    let removed = [];
    if (state === AGENT_READY && config) {
      const cleared = await clearStatusLabels(number);
      if (cleared.outcome === "held") {
        return cleared;
      }
      ({ removed } = cleared);
    }
    const current = fresh ? null : (wrote.get(number) ?? fields?.[String(config?.["field-id"])]?.option);
    let result;
    try {
      result = await writeState({ github, repository, number, state, config, current });
    } catch (error) {
      await restoreAndThrow(number, removed, error);
    }
    wrote.set(number, result.option);
    if (result.outcome === "written" && (await stopsLane(state))) {
      await dropAgentReadyLabel(number);
    }
    return result;
  };
  const leaveAgentReady = async (number, state, { orUnset = false } = {}) => {
    if (failure) {
      throw failure;
    }
    const { state: held } = await readField(number);
    const leave = held === "agent-ready" || (orUnset && (held === null || held === undefined));
    return leave ? set(number, state) : { outcome: "unchanged", state: held };
  };
  const restart = async (number, { from } = {}) => {
    if (failure) {
      throw failure;
    }
    const now = await readField(number);
    if (now.personHold) {
      return { outcome: "held", state: now.state };
    }
    if (Array.isArray(from) && !from.includes(now.state ?? null)) {
      return { outcome: "moved", state: now.state };
    }
    const cleared = await clearStatusLabels(number);
    if (cleared.outcome === "held") {
      return cleared;
    }
    try {
      await github("DELETE", `/repos/${repository}/issues/${number}/issue-field-values/${config["field-id"]}`, undefined, FIELD_API);
      await sleep(RESTART_GAP_MS);
    } catch (error) {
      if (!/\bstatus 404\b/.test(String(error?.message ?? error))) {
        throw new StatusWriteError(`#${number}'s Work status field was not cleared for a restart: ${error?.message ?? error}`, { cause: error });
      }
    }
    wrote.delete(number);
    const result = await writeState({ github, repository, number, state: "agent-ready", config, current: null });
    wrote.set(number, result.option);
    return result;
  };
  return { set, leaveAgentReady, restart };
}
