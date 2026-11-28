// test-scope: .github/workflows/pr-dispatch-feedback.yml .github/scripts/pr-merge/merge-holds.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { admits } from "../lib/gate-expression.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const wf = workflowText(readFileSync(new URL("../../workflows/pr-dispatch-feedback.yml", import.meta.url), "utf8"));
const JOB = "lift-verify-fail";
const STEP = "Post pr-verify success on a trusted approval of the head";
const REPO = "melodic-software/claude-code-plugins";
const HEAD = "a".repeat(40);
const KYLE = 153232337;
const script = () => /\n {8}run: \|\n([\s\S]*?)(?=\n\n {6}- name: )/.exec(wf.stepNamed(JOB, STEP).text + "\n\n      - name: ")[1].replace(/^ {10}/gm, "");

const APPROVED = ".github/workflows/pr-review-approved.yml";
const upstream = (overrides = {}, ref = "refs/heads/main") => ({
  github: {
    ref,
    repository: REPO,
    event: {
      workflow_run: {
        path: APPROVED,
        event: "pull_request_review",
        conclusion: "success",
        repository: { full_name: REPO },
        head_repository: { full_name: REPO },
        ...overrides,
      },
    },
  },
});

test("lift-verify-fail runs only for pr-review-approved on a same-repository review, holding statuses: write and two reads", () => {
  assert.equal(admits(wf.jobIf(JOB), upstream()), true);
  for (const overrides of [
    { path: ".github/workflows/pr-verify.yml" },
    { event: "pull_request" },
    { conclusion: "skipped" },
    { head_repository: { full_name: "fork/claude-code-plugins" } },
  ]) {
    assert.equal(admits(wf.jobIf(JOB), upstream(overrides)), false, JSON.stringify(overrides));
  }
  const job = wf.job(JOB);
  const block = /^ {4}permissions:\n((?: {6}.*\n)+)/m.exec(job)[1];
  assert.deepEqual([...block.matchAll(/^ {6}([a-z-]+): ([a-z]+)/gm)].map((m) => `${m[1]}: ${m[2]}`), ["contents: read", "pull-requests: read", "statuses: write"]);
  const step = wf.stepNamed(JOB, STEP);
  assert.equal(step.env.HEAD_SHA, "${{ github.event.workflow_run.head_sha }}");
  assert.equal(step.env.PR_NUMBER, undefined, "the pull request comes from the head, not workflow_run.pull_requests");
  assert.doesNotMatch(script(), /\$\{\{/);
  assert.match(script(), /^lifters=\$\(node \.base\/\.github\/scripts\/pr-merge\/merge-holds\.mjs lifters "\$RUNNER_TEMP\/reviews\.jsonl" "\$TRUSTED_ACTORS" "\$HEAD_SHA"\)$/m);
  assert.doesNotMatch(script(), /node -e|--input-type/, "the lift rule runs only through merge-holds.mjs's lifters entry");
  assert.match(script(), /^\{ \. \.base\/\.github\/actions\/log-api-budget\/api-budget\.bash 2>\/dev\/null && api_budget_wrap_gh github-token; \} \|\| true$/m);
  assert.match(job, /\n {12}\/\.github\/scripts\/pr-merge\/merge-holds\.mjs\n/);
  assert.match(wf.stepNamed(JOB, "Log the API budget at the end").text, /^ {8}if: always\(\)$/m);
});

test("lift-verify-fail's if: admits exactly the approval runs rerun-ci-status admits", () => {
  const paths = [APPROVED, ".github/workflows/pr-review-hosted.yml", ".github/workflows/pr-review-security-hosted.yml", ".github/workflows/pr-verify.yml"];
  let lifts = 0;
  for (const path of paths)
    for (const event of ["pull_request_review", "pull_request", "workflow_run"])
      for (const conclusion of ["success", "skipped"])
        for (const repository of [REPO, "fork/claude-code-plugins"])
          for (const headRepository of [REPO, "fork/claude-code-plugins"])
            for (const ref of ["refs/heads/main", "refs/heads/other"]) {
              const context = upstream({ path, event, conclusion, repository: { full_name: repository }, head_repository: { full_name: headRepository } }, ref);
              const lift = admits(wf.jobIf(JOB), context);
              assert.equal(lift, admits(wf.jobIf("rerun-ci-status"), context) && path === APPROVED, JSON.stringify(context));
              lifts += lift;
            }
  assert.equal(lifts, 1);
});

const review = (id, login, state, commit = HEAD, type = "User", at = "2026-11-28T10:00:00Z") => ({ id: 1, user: { id, login, type }, state, commit_id: commit, submitted_at: at });
const pull = (overrides = {}) => ({ number: 41, state: "open", head: { sha: HEAD, repo: { full_name: REPO } }, base: { ref: "main" }, ...overrides });
const status = (state) => ({
  state: "failure",
  statuses: [{ context: "CI Status", state: "success", updated_at: "2026-11-28T12:00:00Z" }, ...(state ? [{ context: "pr-verify", state, updated_at: "2026-11-28T09:00:00Z" }] : [])],
});
const KYLE_APPROVES = [review(KYLE, "kyle-sexton", "APPROVED")];

const STUB = (dir, args, fails) =>
  [
    "#!/bin/sh",
    `printf '%s\\n' "$*" >>'${args}'`,
    `case "$*" in *"-X POST"*) [ "$(grep -c -- '-X POST' '${args}')" -gt ${fails} ]; exit ;; esac`,
    "endpoint= filter=",
    'while [ $# -gt 0 ]; do',
    '  case $1 in',
    '  --jq) filter=$2; shift ;;',
    '  api | --paginate) ;;',
    '  *) [ -n "$endpoint" ] || endpoint=$1 ;;',
    '  esac',
    '  shift',
    'done',
    'case $endpoint in',
    '*"/pulls?"*) file=pulls ;;',
    '*"/status?"*) file=status ;;',
    '*"/reviews?"*) file=reviews ;;',
    '*) exit 9 ;;',
    'esac',
    `[ -f '${dir}'/"$file.json" ] || exit 1`,
    `exec jq -r "$filter" '${dir}'/"$file.json"`,
    "",
  ].join("\n");

const lift = ({ pulls = [pull()], state = "failure", statuses = status(state), reviews = KYLE_APPROVES, fails = 0, env = {} } = {}) => {
  const dir = tempDir("lift-verify-fail-");
  const bin = path.join(dir, "bin");
  mkdirSync(bin);
  mkdirSync(path.join(dir, ".base/.github/scripts/pr-merge"), { recursive: true });
  cpSync(path.join(ROOT, ".github/scripts/pr-merge/merge-holds.mjs"), path.join(dir, ".base/.github/scripts/pr-merge/merge-holds.mjs"));
  const args = path.join(dir, "args");
  writeFileSync(args, "");
  for (const [name, body] of Object.entries({ pulls, status: statuses, reviews })) {
    if (body !== null) {
      writeFileSync(path.join(dir, `${name}.json`), JSON.stringify(body));
    }
  }
  writeFileSync(path.join(bin, "gh"), STUB(dir, args, fails), { mode: 0o755 });
  writeFileSync(path.join(bin, "sleep"), "#!/bin/sh\n", { mode: 0o755 });
  const run = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", script()], {
    cwd: dir,
    env: {
      PATH: `${bin}:${process.env.PATH}`,
      HOME: process.env.HOME,
      RUNNER_TEMP: dir,
      GITHUB_REPOSITORY: REPO,
      GITHUB_SERVER_URL: "https://github.com",
      GITHUB_RUN_ID: "9",
      GH_TOKEN: "t",
      HEAD_SHA: HEAD,
      TRUSTED_ACTORS: path.join(ROOT, ".github/scripts/lib/fixtures/standards/components/trusted-actors/trusted-actors.json"),
      ...env,
    },
    encoding: "utf8",
  });
  return { status: run.status, stdout: run.stdout + run.stderr, gh: readFileSync(args, "utf8").split("\n").filter(Boolean) };
};
const POSTED = (description) => `api -X POST repos/${REPO}/statuses/${HEAD} -f state=success -f context=pr-verify -f description=${description} -f target_url=https://github.com/${REPO}/actions/runs/9`;
const POST = POSTED("pr-verify FAIL lifted: kyle-sexton approved this head");
const UNPASSED = POSTED("pr-verify not passed at this head; lifted: kyle-sexton approved this head");
const posts = (run) => run.gh.filter((call) => call.includes("-X POST")).length;

test("a trusted approval of the head posts pr-verify success once when its status is failure, pending or absent, naming a FAIL only when there was one", () => {
  for (const [state, post] of [["failure", POST], ["pending", UNPASSED], ["error", UNPASSED], [null, UNPASSED]]) {
    const run = lift({ state });
    assert.equal(run.status, 0, run.stdout);
    assert.equal(posts(run), 1, String(state));
    assert.equal(run.gh.at(-1), post, String(state));
    assert.equal(run.gh.length, 4, `${state}: pulls, status and reviews reads, then one post`);
    assert.match(run.gh[0], new RegExp(`^api repos/${REPO}/commits/${HEAD}/pulls\\?per_page=100 `));
    assert.match(run.gh[1], new RegExp(`^api repos/${REPO}/commits/${HEAD}/status\\?per_page=100 `));
    assert.match(run.gh[2], new RegExp(`^api repos/${REPO}/pulls/41/reviews\\?per_page=100 --paginate `));
  }
});

test("lift-verify-fail cuts the success description to GitHub's 140 characters", () => {
  const many = Array.from({ length: 8 }, (_, i) => ({ id: 200 + i, login: `trusted-approver-${String(i).padStart(3, "0")}`, kind: "human" }));
  const actors = path.join(tempDir("lift-verify-fail-actors-"), "trusted-actors.json");
  writeFileSync(actors, JSON.stringify({ version: 1, actors: many }));
  const logins = many.map(({ login }) => login).join(", ");
  for (const [state, text] of [["failure", `pr-verify FAIL lifted: ${logins} approved this head`], [null, `pr-verify not passed at this head; lifted: ${logins} approved this head`]]) {
    const run = lift({ state, reviews: many.map(({ id, login }) => review(id, login, "APPROVED")), env: { TRUSTED_ACTORS: actors } });
    assert.ok(text.length > 140);
    assert.equal(run.gh.at(-1), POSTED(text.slice(0, 140)), String(state));
  }
});

test("a newer status in another context does not hide pr-verify's", () => {
  for (const [state, expected] of [["failure", 1], ["success", 0]]) {
    const statuses = { state: "pending", statuses: [{ context: "pr-verify-notes", state: "success" }, { context: "CI Status", state: "pending" }, { context: "pr-verify", state }] };
    assert.equal(posts(lift({ statuses })), expected, state);
  }
});

test("a head already at success, or with no trusted person's standing approval of it, posts nothing", () => {
  const passed = lift({ state: "success" });
  assert.equal(passed.status, 0);
  assert.equal(passed.gh.length, 2, "no reviews read once pr-verify is success");
  assert.match(passed.stdout, /pr-verify is already success/);
  for (const [why, reviews] of [
    ["no review", []],
    ["an untrusted approver", [review(5, "stranger", "APPROVED")]],
    ["a trusted bot", [review(49699333, "dependabot[bot]", "APPROVED", HEAD, "Bot")]],
    ["an approval of an earlier head", [review(KYLE, "kyle-sexton", "APPROVED", "b".repeat(40))]],
    ["a dismissed approval", [review(KYLE, "kyle-sexton", "DISMISSED")]],
    ["a later change request", [...KYLE_APPROVES, review(KYLE, "kyle-sexton", "CHANGES_REQUESTED", HEAD, "User", "2026-11-28T11:00:00Z")]],
  ]) {
    const run = lift({ reviews });
    assert.equal(run.status, 0, why);
    assert.equal(posts(run), 0, why);
    assert.match(run.stdout, /its pr-verify failure stands/, why);
  }
});

test("no single open same-repository pull request into main at the head gives a notice, exit 0 and no post", () => {
  for (const [why, pulls] of [
    ["zero", []],
    ["two", [pull(), pull({ number: 42 })]],
    ["closed", [pull({ state: "closed" })]],
    ["moved head", [pull({ head: { sha: "b".repeat(40), repo: { full_name: REPO } } })]],
    ["fork head", [pull({ head: { sha: HEAD, repo: { full_name: "fork/claude-code-plugins" } } })]],
    ["not into main", [pull({ base: { ref: "release" } })]],
  ]) {
    const run = lift({ pulls });
    assert.equal(run.status, 0, why);
    assert.equal(run.gh.length, 1, `${why}: only the pulls read`);
    assert.match(run.stdout, /::notice title=pr-verify lift::no single open pull request into main/, why);
  }
  const among = lift({ pulls: [pull({ number: 7, state: "closed" }), pull()] });
  assert.equal(posts(among), 1, "a closed pull request beside the open one is ignored");
});

test("a read that fails stops non-zero before any post", () => {
  const pullsFailed = lift({ pulls: null });
  assert.equal(pullsFailed.status, 1);
  assert.equal(pullsFailed.gh.length, 1);
  assert.match(pullsFailed.stdout, /the pull requests of a{40} did not read/);
  for (const broken of [{ statuses: null }, { reviews: null }, { env: { TRUSTED_ACTORS: "/nonexistent/trusted-actors.json" } }]) {
    const run = lift(broken);
    assert.notEqual(run.status, 0, JSON.stringify(broken));
    assert.equal(posts(run), 0, JSON.stringify(broken));
  }
});

test("lift-verify-fail retries a failed post twice, then fails, and reads nothing for a head that is not a SHA", () => {
  assert.equal(lift({ fails: 2 }).status, 0);
  const failed = lift({ fails: 3 });
  assert.notEqual(failed.status, 0);
  assert.equal(posts(failed), 3);
  for (const HEAD_SHA of ["main", "", `${HEAD}; x`]) {
    const run = lift({ env: { HEAD_SHA } });
    assert.notEqual(run.status, 0, HEAD_SHA);
    assert.deepEqual(run.gh, [], HEAD_SHA);
  }
});
