import fs from 'node:fs';
import { buildSchema, parse, validate, getVariableValues } from 'graphql';
const schema = buildSchema(fs.readFileSync('./schema.graphql', 'utf8'), { assumeValidSDL: true });

// Deliberately-wrong variants of the adapter's real operations. Each must FAIL.
const bad = [
  ['wrong field name on Issue',
   `query { issues(first:1) { nodes { id statusName } } }`, {}],
  ['wrong mutation name',
   `mutation($input: IssueCreateInput!) { createIssue(input:$input){ success } }`, {input:{teamId:'t'}}],
  ['wrong arg name on issues',
   `query { issues(where: {}, first:1) { nodes { id } } }`, {}],
  ['wrong nested selection',
   `query { issues(first:1){ nodes { state { category } } } }`, {}],
  ['bogus enum member in variables',
   `mutation($input: IssueRelationCreateInput!){ issueRelationCreate(input:$input){ success } }`,
   {input:{issueId:'a', relatedIssueId:'b', type:'blocked_by'}}],
  ['wrong input field name in variables',
   `mutation($id:String!,$input:IssueUpdateInput!){ issueUpdate(id:$id,input:$input){success} }`,
   {id:'x', input:{assignee_id:'u'}}],
  ['wrong variable type (Int for a String comparator)',
   `query($t:Int!){ issues(filter:{team:{key:{eq:$t}}}, first:1){ nodes { id } } }`, {t:1}],
  ['missing required input field',
   `mutation($input: IssueCreateInput!){ issueCreate(input:$input){ success } }`, {input:{title:'t'}}],
  ['pageInfo field that does not exist',
   `query { issues(first:1){ pageInfo { hasMore } } }`, {}],
  ['comments connection wrong node field',
   `query($id:String!){ issue(id:$id){ comments(first:5){ nodes { text } } } }`, {id:'x'}],
];

let caught = 0;
for (const [label, q, vars] of bad) {
  let doc, errs = [];
  try { doc = parse(q); } catch (e) { console.log(`CAUGHT(parse) ${label}`); caught++; continue; }
  errs = validate(schema, doc);
  if (errs.length === 0) {
    const opDef = doc.definitions.find(d => d.kind === 'OperationDefinition');
    const r = getVariableValues(schema, opDef.variableDefinitions ?? [], vars);
    if (r.errors) errs = r.errors;
  }
  if (errs.length) { caught++; console.log(`CAUGHT  ${label}\n          -> ${errs[0].message}`); }
  else console.log(`MISSED  ${label}  <-- harness is blind to this class`);
}
console.log(`\nnegative control: ${caught}/${bad.length} deliberate faults detected.`);
// A MISSED fault means the validator has gone blind to a whole class, which makes every green
// run of validate.mjs meaningless. That must fail the process, not merely print.
if (caught !== bad.length) process.exit(1);
