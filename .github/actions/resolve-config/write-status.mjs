// The Work status writer (models.issue-status). An issue's Work status field
// is its state: writeState and statusWriter set it to a named state, and a
// write that does not land throws StatusWriteError. Imports nothing outside
// node at load, so a job that installs no resolve-config dependencies can
// still import FIELD_API; its writer then throws on every call.
export const FIELD_API = { "X-GitHub-Api-Version": "2026-03-10" };

// The wait between a restart's clear and its set. GitHub can stamp the removal
// after an add sent right behind it; the newest event then reads as a removal
// while the field holds a value, and every status listing that could match the
// issue fails until the field is written again.
export const RESTART_GAP_MS = 3000;

// The statuses GitHub answers a field value that names no option with.
const NAME_REFUSED = new Set([400, 422]);
const titleCased = (name) => name.charAt(0).toUpperCase() + name.slice(1);

// Writes `values` ({field_id, value}, each a lowercase option name) through
// `post(values)` and returns the rows GitHub answered. The REST write takes an
// option name, not an id, and the Size, Complexity and Uncertainty options
// (`titled` holds their field ids) move from Title case to lowercase: the write
// goes lowercase, then Title-cased when GitHub refuses it, then one field at a
// time, each in either casing, while part of a rename has landed. Any other
// failure throws.
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

// A Work status write that did not land, for a writer whose field write must
// fail its run.
export class StatusWriteError extends Error {
  constructor(message, options) {
    super(message, options);
    this.name = "StatusWriteError";
  }
}

// Sets the issue's Work status field to `state` (a models.issue-status state)
// with one POST, and throws StatusWriteError on any failure: no config, a
// state no option maps, a failed call, or GitHub keeping another option.
// `current`, when the writer already read the field, is the option id it
// holds: a match skips the write. Never PUT, which replaces every field value
// on the issue, and never DELETE.
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
    // Safe to send twice: the POST sets the field to one option, so a second
    // copy after a 5xx that GitHub did apply sets the same value.
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

// What a state writer's entry point hands its run, over the base config's
// models.issue-status and trusted-actor list (read-status.mjs
// loadTrustedActors):
// - `set(number, state, {fields, keepHold, releases})` writes `state`
//   (writeState), skipping an option this process already wrote for the
//   issue, or one `fields` (field id -> {option}) shows it holds. `fields`
//   must come from a trusted read (read-status.mjs fieldStatus's rule): an
//   option an untrusted account set would otherwise stop a write the field
//   needs. With `keepHold`, the field is read first on every call, and that
//   read alone decides a skip; a hold (HOLD_STATES) a listed human set is not
//   replaced unless it is `releases`, the hold the write answers: `set`
//   answers `{outcome: "held", state}` and the caller treats the issue as held;
// - `leaveAgentReady(number, state, {orUnset})` writes `state` only while the
//   field's trusted state (read-status.mjs fieldStatus) is agent-ready, so
//   taking agent-ready off never resets another state. With `orUnset`, it also
//   writes while no trusted state is set: an unset field leaves the labels
//   deciding (read-status.mjs statusLabels), so only a set field takes an
//   agent-ready label off.
// A config that cannot be read makes every call throw StatusWriteError; a
// trusted-actor list that cannot be read, every call that reads the field.
export async function statusWriter({ env, github, repository, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)) }) {
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
  // The field's trusted state, and whether it is a hold a listed human set.
  // Only a field read needs the trusted-actor list, so a plain `set` writes without it.
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
  const set = async (number, state, { fields, keepHold, releases } = {}) => {
    if (failure) {
      throw failure;
    }
    // A person may set a hold after any write, this process's own included.
    if (keepHold) {
      const now = await readField(number);
      if (now.personHold && now.state !== releases) {
        return { outcome: "held", state: now.state };
      }
      if (now.state === state) {
        return { outcome: "unchanged", state };
      }
    }
    const current = keepHold ? null : (wrote.get(number) ?? fields?.[String(config?.["field-id"])]?.option);
    const result = await writeState({ github, repository, number, state, config, current });
    wrote.set(number, result.option);
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
  // Restarts the issue lane: clears the field, then sets agent-ready with no
  // skip, so GitHub sends the field_added that starts a run. A hold a listed
  // human set stops it (`{outcome: "held"}`); so does a trusted state outside
  // `from` (the states the caller restarts from, null for unset), since a
  // person may have moved the issue off agent-ready after the caller's read
  // (`{outcome: "moved"}`). With no `from`, any state but a hold restarts.
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
