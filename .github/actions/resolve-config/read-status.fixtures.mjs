// Test fixtures for the Work status readers (read-status.mjs): the live
// models.issue-status, a trusted-actor list, and a client wrapper that answers
// the field reads.
import { readFileSync } from "node:fs";

import { parse } from "yaml";

import { collapseStatus } from "./issue-status.mjs";
import { statusLabels } from "./read-status.mjs";

export const STATUS_CONFIG = parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8")).models[
  "issue-status"
];
const FIELD = STATUS_CONFIG["field-id"];
// The option id of each state, from the config's map.
export const OPTION = Object.fromEntries(Object.entries(STATUS_CONFIG.options).map(([id, state]) => [state, Number(id)]));
export const HUMAN_ID = 11;
export const STRANGER_ID = 99;
export const TRUSTED_ACTORS = { version: 1, actors: [{ id: HUMAN_ID, login: "person", kind: "human" }] };

// `github` with issue field reads answered from `fields`: issue number ->
// {state, setter, named, nodes} (setter defaults to HUMAN_ID, named, the
// option name the newest field event left, to state, and nodes, the GraphQL
// field event nodes, to one change event naming them), or an Error the read
// throws. An issue `fields` omits holds no value. Every other call goes to
// `github`.
export function withFields(github, fields = {}) {
  return async (method, path, body, ...rest) => {
    const read = /\/issues\/([0-9]+)\/issue-field-values$/.exec(path);
    if (method === "GET" && read) {
      const entry = fields[read[1]];
      if (entry instanceof Error) {
        throw entry;
      }
      return entry ? [{ issue_field_id: FIELD, single_select_option: { id: OPTION[entry.state] } }] : [];
    }
    if (method === "POST" && path === "/graphql" && body?.variables?.number !== undefined && /IssueFieldAddedEvent/.test(body?.query ?? "")) {
      const entry = fields[String(body.variables.number)];
      const nodes = !entry || entry instanceof Error ? [] : (entry.nodes ?? [{ __typename: "IssueFieldChangedEvent", newValue: entry.named ?? entry.state, actor: { databaseId: entry.setter ?? HUMAN_ID }, issueField: { fullDatabaseId: String(FIELD) } }]);
      return { data: { repository: { issue: { timelineItems: { nodes } } } } };
    }
    return github(method, path, body, ...rest);
  };
}

// A reader whose field holds exactly what the labels collapse to, as the
// mirror leaves it: every reader must answer as it does on labels alone.
export const mirroredStatusOf = async (number, names) => statusLabels(collapseStatus(names, STATUS_CONFIG), names, STATUS_CONFIG);
