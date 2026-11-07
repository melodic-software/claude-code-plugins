// The Work status writer (models.issue-status). An issue's Work status field
// is its state: writeState and statusWriter set it to a named state, and a
// write that does not land throws StatusWriteError. Imports nothing outside
// node at load, so a job that installs no resolve-config dependencies can
// still import FIELD_API; its writer then throws on every call.
export const FIELD_API = { "X-GitHub-Api-Version": "2026-03-10" };

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
// - `set(number, state, {fields})` writes `state` (writeState), skipping an
//   option this process already wrote for the issue, or one `fields` (field
//   id -> {option}) shows it holds. `fields` must come from a trusted read
//   (read-status.mjs fieldStatus's rule): an option an untrusted account set
//   would otherwise stop a write the field needs;
// - `leaveAgentReady(number, state)` writes `state` only while the field's
//   trusted state (read-status.mjs fieldStatus) is agent-ready, so taking
//   agent-ready off never resets another state.
// A config that cannot be read makes every call throw StatusWriteError.
export async function statusWriter({ env, github, repository }) {
  let config;
  let trustedActors;
  let failure;
  try {
    const { issueStatusFromBase } = await import("./resolve-config.mjs");
    const { loadTrustedActors } = await import("./read-status.mjs");
    config = issueStatusFromBase(env);
    trustedActors = loadTrustedActors(env);
  } catch (error) {
    failure = new StatusWriteError(`models.issue-status could not be read: ${error?.message ?? error}`, { cause: error });
  }
  const wrote = new Map();
  const set = async (number, state, { fields } = {}) => {
    if (failure) {
      throw failure;
    }
    const current = wrote.get(number) ?? fields?.[String(config?.["field-id"])]?.option;
    const result = await writeState({ github, repository, number, state, config, current });
    wrote.set(number, result.option);
    return result;
  };
  const leaveAgentReady = async (number, state) => {
    if (failure) {
      throw failure;
    }
    let held;
    try {
      const { fieldStatus } = await import("./read-status.mjs");
      held = await fieldStatus({ github, repository, number, config, trustedActors });
    } catch (error) {
      throw new StatusWriteError(`#${number}'s Work status field could not be read: ${error?.message ?? error}`, { cause: error });
    }
    return held === "agent-ready" ? set(number, state) : { outcome: "unchanged", state: held };
  };
  return { set, leaveAgentReady };
}
