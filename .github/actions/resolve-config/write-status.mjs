// The Work status writers (models.issue-status). The mirror (writeStatus,
// statusMirror): after a label change, sets the issue's Work status field to
// the state its labels collapse to, so the field mirrors the labels; a failed
// write warns and never throws, so it neither fails nor undoes the label
// write. The state writer (writeState, statusWriter): sets the field to a
// named state, and a write that does not land throws StatusWriteError.
// Imports nothing outside node at load, so a writer whose job installs no
// resolve-config dependencies loads it, and the mirror only warns.
export const FIELD_API = { "X-GitHub-Api-Version": "2026-03-10" };

const annotate = (line) => String(line).replaceAll(/[\r\n%]/g, " ");
const fold = (name) => String(typeof name === "string" ? name : name?.name).toLowerCase();

// The label names an issue that had `had` holds once `add` lands and `remove`
// comes off; names compare without case, as GitHub's do.
export function labelsAfter(had = [], add = [], remove = []) {
  const off = new Set(remove.map(fold));
  const names = [...had, ...add].map((label) => (typeof label === "string" ? label : label?.name));
  return names.filter((name, i) => !off.has(fold(name)) && names.findIndex((other) => fold(other) === fold(name)) === i);
}

// `labels` is the issue's label set after the change, as names or REST label
// objects; `config` the models.issue-status leaf, or null when unset, which
// writes nothing. `current`, when the writer already read the field, is the
// option id it holds (null for none): a match skips the write. One POST
// otherwise; never PUT, which replaces every field value on the issue, and
// never DELETE, since every label set collapses to a state.
export async function writeStatus({ github, repository, number, labels, config, current, log = console.log }) {
  if (!config) {
    return { outcome: "unset" };
  }
  const warn = (why) => {
    log(`::warning title=work-status::#${number}'s Work status field not written: ${annotate(why)}; its labels stand`);
    return { outcome: "failed", reason: String(why) };
  };
  try {
    const { collapseStatus, statusOption } = await import("./issue-status.mjs");
    const state = collapseStatus(labels, config);
    const option = statusOption(state, config);
    if (current !== undefined && current !== null && Number(current) === option) {
      return { outcome: "unchanged", state, option };
    }
    const fieldId = config["field-id"];
    // Safe to send twice: the POST sets the field to one option, so a second
    // copy after a 5xx that GitHub did apply sets the same value.
    const written = await github(
      "POST",
      `/repos/${repository}/issues/${number}/issue-field-values`,
      { issue_field_values: [{ field_id: fieldId, value: state }] },
      FIELD_API,
      { resendOnce: true },
    );
    const row = (Array.isArray(written) ? written : []).find((value) => value?.issue_field_id === fieldId);
    if (row?.single_select_option?.id !== option) {
      return warn(`GitHub kept option ${row?.single_select_option?.id ?? "none"} for \`${state}\`, not ${option}; models.issue-status has drifted from the field`);
    }
    return { outcome: "written", state, option };
  } catch (error) {
    return warn(error?.message ?? error);
  }
}

// What a writer's entry point hands its run: `mirror(number, {had, add,
// remove, fields})` over the base config's models.issue-status, `had` the
// labels the writer read and `add`/`remove` what it wrote. A change that
// leaves the label set as it was writes nothing; so does an option this
// process already wrote for the issue, or one `fields` (field id -> {option},
// when the writer already read them) shows it holds. A config that cannot be
// read warns once and every mirror call then writes nothing.
export async function statusMirror({ env, github, repository, log = console.log }) {
  let config;
  try {
    const { issueStatusFromBase } = await import("./resolve-config.mjs");
    config = issueStatusFromBase(env);
  } catch (error) {
    log(`::warning title=work-status::models.issue-status could not be read, so no Work status field is written: ${annotate(error?.message ?? error)}`);
    return async () => ({ outcome: "failed" });
  }
  const wrote = new Map();
  return async (number, { had = [], add = [], remove = [], fields } = {}) => {
    const labels = labelsAfter(had, add, remove);
    const before = new Set(labelsAfter(had).map(fold));
    if (labels.length === before.size && labels.every((name) => before.has(fold(name)))) {
      return { outcome: "unchanged" };
    }
    const current = wrote.get(number) ?? fields?.[String(config?.["field-id"])]?.option;
    const result = await writeStatus({ github, repository, number, labels, config, current, log });
    if (result.option !== undefined) {
      wrote.set(number, result.option);
    }
    return result;
  };
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
// holds: a match skips the write. Never PUT, never DELETE.
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
    // Safe to send twice, as in writeStatus.
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
