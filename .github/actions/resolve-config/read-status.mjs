// The Work status reader for the status-label readers (models.issue-status).
// Labels are written first and reach the field afterwards, so while an issue
// carries any status label the labels decide; the field a trusted account set
// (issue-status.mjs issueStatus) can only add a hold the labels lack, and
// decides alone only for an issue with no status label. An unset field, an
// untrusted setter, or any failure leaves the labels as they are. Imports
// nothing outside node at load, so a reader whose job installs no
// resolve-config dependencies loads it and only warns.
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { FIELD_API } from "./write-status.mjs";

const TRUSTED_ACTORS = ".github/standards/trusted-actors/trusted-actors.json";
// The states that hold an issue for a person.
export const HOLD_STATES = ["needs-human", "needs-owner-decision", "needs-reporter-info", "needs-spec"];
const annotate = (line) => String(line).replaceAll(/[\r\n%]/g, " ");
const fold = (name) => String(name).toLowerCase();

// `names` as the field's `state` may change them: with a status label on the
// issue, only a hold state the labels lack adds its labels; with none, any
// state but the floor (an issue with no status label reads as the floor)
// adds its labels. Labels are never removed. Pure.
export function statusLabels(state, names, config) {
  if (state === null || state === undefined || !config) {
    return names;
  }
  const labelsOf = (states) => new Set(states.flatMap((one) => config.labels[one] ?? []).map(fold));
  const status = labelsOf(Object.keys(config.labels));
  const carried = names.filter((name) => status.has(fold(name)));
  if (carried.length === 0) {
    return state === config.order.at(-1) ? names : [...names, ...config.labels[state]];
  }
  const holds = labelsOf(HOLD_STATES);
  return HOLD_STATES.includes(state) && !carried.some((name) => holds.has(fold(name))) ? [...names, ...config.labels[state]] : names;
}

// The trusted-actor list: TRUSTED_ACTORS_PATH, else under BASE_PATH (default `.base`).
export function loadTrustedActors(env = {}) {
  return JSON.parse(readFileSync(env.TRUSTED_ACTORS_PATH || join(env.BASE_PATH || ".base", TRUSTED_ACTORS), "utf8"));
}

// The state the issue's Work status field holds (issue-status.mjs
// issueStatus over the issue's field events), or null when no counted account
// set it; throws when the field cannot be read. `issueStatus` and
// `fieldEvents` default to the modules'.
export async function fieldStatus({ github, repository, number, config, trustedActors, issueStatus, fieldEvents }) {
  const status = issueStatus ?? (await import("./issue-status.mjs")).issueStatus;
  const events = fieldEvents ?? (await import("./resolve-config.mjs")).fieldEvents;
  const rows = await github("GET", `/repos/${repository}/issues/${number}/issue-field-values`, undefined, FIELD_API);
  if (!Array.isArray(rows)) {
    throw new Error("its field values answered something other than a list");
  }
  const facts = {
    fieldValues: rows.map((row) => ({ field: row?.issue_field_id, option: row?.single_select_option?.id ?? null })),
    fieldEvents: await events(github, repository, number),
  };
  return status(facts, config, trustedActors);
}

// What a reader's entry point hands its run: `labels(number, names)`, the
// issue's label names with the field's say added (statusLabels), read fresh on
// each call, since a reader may ask again after the status changed, and at
// most `limit` reads a run; past the limit the labels decide.
// `config` and `trustedActors` default to the base config's models.issue-status
// and the trusted-actor list (TRUSTED_ACTORS_PATH, else under BASE_PATH); an
// unset config reads nothing. `github(method, path, body, headers)` is
// check-trusted-trigger.mjs createGitHub's.
export function statusReader({ env = {}, github, repository, log = console.log, limit = Infinity, config, trustedActors }) {
  let setup;
  const prepare = async () => {
    try {
      const { fieldEvents, issueStatusFromBase } = await import("./resolve-config.mjs");
      const { issueStatus } = await import("./issue-status.mjs");
      const leaf = config === undefined ? issueStatusFromBase(env) : config;
      if (!leaf) {
        return null;
      }
      const actors = trustedActors ?? loadTrustedActors(env);
      return { config: leaf, trustedActors: actors, issueStatus, fieldEvents };
    } catch (error) {
      log(`::warning title=work-status::the Work status field is not read, so status labels decide: ${annotate(error?.message ?? error)}`);
      return null;
    }
  };
  const read = async (number) => {
    try {
      return await fieldStatus({ github, repository, number, ...setup });
    } catch (error) {
      log(`::warning title=work-status::#${number}'s Work status field could not be read, so its labels decide: ${annotate(error?.message ?? error)}`);
      return null;
    }
  };
  let reads = 0;
  return async (number, names) => {
    if (setup === undefined) {
      setup = await prepare();
    }
    if (setup === null || reads >= limit) {
      return names;
    }
    reads += 1;
    return statusLabels(await read(Number(number)), names, setup.config);
  };
}
