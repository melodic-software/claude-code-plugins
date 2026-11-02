// The Work status writer (models.issue-status): after a label change, sets the
// issue's Work status field to the state its labels collapse to, so the field
// mirrors the labels. Labels stay the source of truth: a failed write warns
// and never throws, so it neither fails nor undoes the label write. Imports
// nothing outside node at load, so a writer whose job installs no
// resolve-config dependencies loads it and only warns.
export const FIELD_API = { "X-GitHub-Api-Version": "2026-03-10" };

const annotate = (line) => String(line).replaceAll(/[\r\n%]/g, " ");

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
      return { outcome: "unchanged", state };
    }
    const fieldId = config["field-id"];
    const written = await github(
      "POST",
      `/repos/${repository}/issues/${number}/issue-field-values`,
      { issue_field_values: [{ field_id: fieldId, value: state }] },
      FIELD_API,
    );
    const row = (Array.isArray(written) ? written : []).find((value) => value?.issue_field_id === fieldId);
    if (row?.single_select_option?.id !== option) {
      return warn(`GitHub kept option ${row?.single_select_option?.id ?? "none"} for \`${state}\`, not ${option}; models.issue-status has drifted from the field`);
    }
    return { outcome: "written", state };
  } catch (error) {
    return warn(error?.message ?? error);
  }
}

// What a writer's entry point hands its run: `mirror(number, labels, fields)`
// over the base config's models.issue-status, where `fields`, when the writer
// already read them, maps a field id to {option}. A config that cannot be
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
  return (number, labels, fields) =>
    writeStatus({ github, repository, number, labels, config, current: fields?.[String(config?.["field-id"])]?.option, log });
}
