import fs from 'node:fs';
import { buildSchema, parse, validate, getVariableValues } from 'graphql';

const schema = buildSchema(fs.readFileSync('./schema.graphql', 'utf8'), { assumeValidSDL: true });

const F = `
  id
  identifier
  number
  title
  url
  state { type name }
  assignee { displayName email }
  labels(first: 50) { nodes { name } }
  parent { identifier team { key } number }
  team { key }
  inverseRelations(first: 100) { nodes { type issue { state { type } } } }
`;

const ops = [
  { name: 'fetch_issue (wit_linear_fetch_issue)', loc: 'common.sh:547-551',
    q: `query($team: String!, $num: Float!) {
    issues(filter: { team: { key: { eq: $team } }, number: { eq: $num } }, first: 1) {
      nodes { ${F} }
    }
  }`, vars: { team: 'ENG', num: 123 } },

  { name: 'viewer (wit_linear_resolve_viewer)', loc: 'common.sh:674',
    q: `query { viewer { id displayName email } }`, vars: {} },

  { name: 'activity_since (wit_linear_activity_since)', loc: 'common.sh:704-711',
    q: `query($id: String!, $first: Int!, $after: String) {
    issue(id: $id) {
      comments(first: $first, after: $after) {
        nodes { body createdAt }
        pageInfo { hasNextPage endCursor }
      }
    }
  }`, vars: { id: 'u', first: 50, after: null } },

  { name: 'lease_comments (wit_linear_lease_comments)', loc: 'common.sh:737-744',
    q: `query($id: String!, $first: Int!, $after: String) {
    issue(id: $id) {
      comments(first: $first, after: $after) {
        nodes { id body createdAt }
        pageInfo { hasNextPage endCursor }
      }
    }
  }`, vars: { id: 'u', first: 50, after: 'cur' } },

  { name: 'commentCreate (wit_linear_post_comment)', loc: 'common.sh:794',
    q: `mutation($input: CommentCreateInput!) { commentCreate(input: $input) { success comment { id createdAt } } }`,
    vars: { input: { issueId: 'u', body: 'b' } } },

  { name: 'commentUpdate (wit_linear_update_comment)', loc: 'common.sh:811',
    q: `mutation($id: String!, $input: CommentUpdateInput!) { commentUpdate(id: $id, input: $input) { success } }`,
    vars: { id: 'u', input: { body: 'b' } } },

  { name: 'issueUpdate assign (wit_linear_set_assignee, assign)', loc: 'common.sh:819',
    q: `mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success } }`,
    vars: { id: 'u', input: { assigneeId: 'uid' } } },

  { name: 'issueUpdate unassign (assigneeId: null)', loc: 'common.sh:819-821',
    q: `mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success } }`,
    vars: { id: 'u', input: { assigneeId: null } } },

  { name: 'list-items issues', loc: 'list-items.sh:57-62',
    q: `query($teams: [String!], $first: Int!, $after: String) {
  issues(filter: { team: { key: { in: $teams } } }, first: $first, after: $after) {
    nodes { ${F} }
    pageInfo { hasNextPage endCursor }
  }
}`, vars: { teams: ['ENG'], first: 50, after: null } },

  { name: 'create-item team resolve', loc: 'create-item.sh:110',
    q: `query($key: String!) { teams(filter: { key: { eq: $key } }, first: 1) { nodes { id } } }`,
    vars: { key: 'ENG' } },

  // Labels come from the ROOT issueLabels connection, filtered to this team OR workspace-level
  // (team: { null: true }), paginated. This replaced a single unpaginated team.labels(first: 250)
  // page, which could neither see workspace labels nor read past its own first page.
  { name: 'create-item label resolve (root issueLabels, team-or-workspace)', loc: 'create-item.sh:154-164',
    q: `query($team: ID!, $first: Int!, $after: String) {
    issueLabels(
      filter: { or: [{ team: { id: { eq: $team } } }, { team: { null: true } }] }
      first: $first
      after: $after
    ) {
      nodes { id name }
      pageInfo { hasNextPage endCursor }
    }
  }`,
    vars: { team: '00000000-0000-0000-0000-000000000000', first: 50, after: null } },

  { name: 'issueCreate', loc: 'create-item.sh:151',
    q: `mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { id number team { key } } } }`,
    vars: { input: { title: 't', teamId: 'tid', description: 'd', labelIds: ['l1'], parentId: 'p' } } },

  { name: 'issueRelationCreate (create-item)', loc: 'create-item.sh:167-168',
    q: `mutation($input: IssueRelationCreateInput!) { issueRelationCreate(input: $input) { success } }`,
    vars: { input: { issueId: 'b', relatedIssueId: 't', type: 'blocks' } } },

  { name: 'issueUpdate parentId (add-sub-item)', loc: 'add-sub-item.sh:60-61',
    q: `mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success } }`,
    vars: { id: 'c', input: { parentId: 'p' } } },

  { name: 'list-sub-items children', loc: 'list-sub-items.sh:53-60',
    q: `query($id: String!, $first: Int!, $after: String) {
  issue(id: $id) {
    children(first: $first, after: $after) {
      nodes { ${F} }
      pageInfo { hasNextPage endCursor }
    }
  }
}`, vars: { id: 'u', first: 50, after: null } },

  { name: 'issueRelationCreate (link-blocks)', loc: 'link-blocks.sh:55-57',
    q: `mutation($input: IssueRelationCreateInput!) { issueRelationCreate(input: $input) { success } }`,
    vars: { input: { issueId: 'b', relatedIssueId: 't', type: 'blocks' } } },

  { name: 'conformance list issues', loc: 'conformance/bindings/linear.sh:58',
    q: `query($t: String!, $a: String) { issues(filter: { team: { key: { eq: $t } } }, first: 50, after: $a) { nodes { id } pageInfo { hasNextPage endCursor } } }`,
    vars: { t: 'ENG', a: null } },

  { name: 'conformance issueArchive', loc: 'conformance/bindings/linear.sh:73',
    q: `mutation($id: String!) { issueArchive(id: $id) { success } }`, vars: { id: 'u' } },
];

let fail = 0;
for (const op of ops) {
  let doc, errs = [];
  try { doc = parse(op.q); } catch (e) { console.log(`FAIL PARSE  ${op.name} :: ${e.message}`); fail++; continue; }
  errs = validate(schema, doc);
  let varErrs = [];
  if (errs.length === 0) {
    const opDef = doc.definitions.find(d => d.kind === 'OperationDefinition');
    const r = getVariableValues(schema, opDef.variableDefinitions ?? [], op.vars);
    if (r.errors) varErrs = r.errors;
  }
  const all = [...errs, ...varErrs];
  if (all.length) { fail++; console.log(`FAIL        ${op.name}  [${op.loc}]`); for (const e of all) console.log(`              -> ${e.message}`); }
  else console.log(`OK          ${op.name}  [${op.loc}]`);
}
console.log(`\n${ops.length - fail}/${ops.length} operations validate clean against the real schema.`);
// Exit status, not just prose. A check that prints FAIL and exits 0 cannot be a regression
// check: every caller — a shell, CI, a future close-out — reads the status, and a green status
// over red output is exactly the vacuous pass this harness exists to rule out.
if (fail > 0) process.exit(1);
