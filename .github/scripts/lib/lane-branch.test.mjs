import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { laneBranch, laneBranchPattern, laneBranchPrefix, parseLaneBranch, WORK_RESOLVE_ISSUE } from "./lane-branch.mjs";

const ANY_LANE = "[a-z][a-z0-9-]{0,63}";
const MALFORMED = [
  "work-resolve-issue/issue-012-345-1",
  "work-resolve-issue/issue-12-0-1",
  "work-resolve-issue/issue-12-345-0",
  "work-resolve-issue/issue-12-345",
  "work-resolve-issue/issue-12-345-1-2",
  "work-resolve-issue/issue-x-345-1",
  "work-resolve-issue/issue-12-345-1 ",
  "refs/heads/work-resolve-issue/issue-12-345-1",
  "",
];

test("a formatted lane branch parses back to its lane, issue, run id and attempt", () => {
  const name = laneBranch(WORK_RESOLVE_ISSUE, 12, 345, 1);
  assert.equal(name, "work-resolve-issue/issue-12-345-1");
  assert.deepEqual(parseLaneBranch(name), { lane: "work-resolve-issue", issue: "12", run: "345", attempt: "1" });
});

test("parse takes only work-resolve-issue unless the caller widens the lane", () => {
  assert.equal(parseLaneBranch("work-unblock/issue-12-345-1"), null);
  assert.deepEqual(parseLaneBranch("work-unblock/issue-12-345-1", { lanePattern: ANY_LANE }), { lane: "work-unblock", issue: "12", run: "345", attempt: "1" });
  assert.equal(parseLaneBranch("Work-unblock/issue-12-345-1", { lanePattern: ANY_LANE }), null, "a lane name starts with a lowercase letter");
});

test("parse refuses a zero, a leading zero, a missing or extra part, and a ref path", () => {
  for (const name of MALFORMED) assert.equal(parseLaneBranch(name), null, name);
  assert.equal(parseLaneBranch(undefined), null);
});

test("a narrowed run id caps its digits", () => {
  const runPattern = "[1-9][0-9]{0,19}";
  assert.equal(parseLaneBranch(`work-resolve-issue/issue-12-${"9".repeat(20)}-1`, { runPattern })?.run, "9".repeat(20));
  assert.equal(parseLaneBranch(`work-resolve-issue/issue-12-${"9".repeat(21)}-1`, { runPattern }), null);
});

test("the issue pattern matches any run and attempt of that issue's branch only", () => {
  const shape = laneBranchPattern(WORK_RESOLVE_ISSUE, 12);
  assert.deepEqual([...shape.exec("work-resolve-issue/issue-12-345-2").slice(1)], ["345", "2"]);
  for (const name of ["work-resolve-issue/issue-123-345-2", "work-resolve-issue/issue-1-345-2", "work-unblock/issue-12-345-2", ...MALFORMED]) {
    assert.equal(shape.test(name), false, name);
  }
  assert.equal(laneBranchPattern("work-unblock", 12).test("work-unblock/issue-12-345-2"), true);
});

test("the issue prefix does not prefix a longer issue number", () => {
  assert.equal(laneBranchPrefix(WORK_RESOLVE_ISSUE, 12), "work-resolve-issue/issue-12-");
  assert.equal("work-resolve-issue/issue-123-345-1".startsWith(laneBranchPrefix(WORK_RESOLVE_ISSUE, 12)), false);
});

const ISSUE = "12";
const RUN = "345";
const VECTORS = [
  "work-resolve-issue/issue-12-345-1",
  "work-resolve-issue/issue-12-345-3",
  "work-resolve-issue/issue-12-678-1",
  "work-resolve-issue/issue-123-345-1",
  "work-resolve-issue/issue-1-345-1",
  "work-unblock/issue-12-345-1",
  ...MALFORMED.filter(Boolean),
];
const bashMatches = (shape, name) => {
  try {
    execFileSync("bash", ["-c", `shape="${shape}"; [[ $NAME =~ $shape ]]`], { env: { ...process.env, ISSUE_NUMBER: ISSUE, RUN_ID: RUN, NAME: name }, stdio: "ignore" });
    return true;
  } catch (error) {
    if (error.status === 1) return false;
    throw error;
  }
};

test("work-resolve-issue.yml's lane branch shapes accept what the module accepts", () => {
  const workflow = readFileSync(new URL("../../workflows/work-resolve-issue.yml", import.meta.url), "utf8");
  const step = workflow.slice(workflow.indexOf("- name: Pick the lane branch"), workflow.indexOf("- name: Check out the lane branch"));
  const shapes = [...new Set([...step.matchAll(/^\s*shape="([^"]+)"$/gm)].map((match) => match[1]))];
  assert.equal(shapes.length, 2, "the step has an any-run shape and a this-run shape");
  const anyRun = laneBranchPattern(WORK_RESOLVE_ISSUE, ISSUE);
  const expected = {
    any: (name) => anyRun.test(name),
    own: (name) => anyRun.exec(name)?.[1] === RUN,
  };
  for (const shape of shapes) {
    const kind = shape.includes("$RUN_ID") ? "own" : "any";
    for (const name of VECTORS) assert.equal(bashMatches(shape, name), expected[kind](name), `${kind} shape on ${name}`);
  }
});

test("collect-base-activity names the changelog fragment's branch as the module formats it", () => {
  const action = readFileSync(new URL("../../actions/collect-base-activity/action.yml", import.meta.url), "utf8");
  const [, template] = /^\s*fragment_branch=(work-resolve-issue\/\S+)$/m.exec(action) ?? [];
  assert.ok(template, "the action assigns fragment_branch from the run's ids");
  const name = execFileSync("bash", ["-c", `printf '%s' ${template}`], { env: { ...process.env, ISSUE_NUMBER: ISSUE, RUN_ID: RUN, RUN_ATTEMPT: "2" }, encoding: "utf8" });
  assert.equal(name, laneBranch(WORK_RESOLVE_ISSUE, ISSUE, RUN, 2));
  assert.deepEqual(parseLaneBranch(name), { lane: WORK_RESOLVE_ISSUE, issue: ISSUE, run: RUN, attempt: "2" });
});
