// pr-rate-merge-risk.yml's controls (#13657), pinned on the file's text:
// the run-name the arm side matches, a read-only job token, no pull request
// code, base-side scripts only, one credential per leg job (#13586), the
// model's tool cage, and the names the arm side reads.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { ARTIFACT_PREFIX, RATING_WORKFLOW_PATH, runTitle } from "../pr-merge/merge-risk-line.mjs";

const text = readFileSync(new URL("../../workflows/pr-rate-merge-risk.yml", import.meta.url), "utf8");
const LEGS = { key: "rate-merge-risk", subscription: "rate-merge-risk-subscription", fallback: "rate-merge-risk-fallback" };
// Each job's text, by its id: from its id line to the next job's, less the
// next job's header comment.
const jobsText = text.split("\njobs:\n")[1];
const starts = [...jobsText.matchAll(/^ {2}([a-z-]+):$/gm)];
const jobs = new Map(starts.map((match, i) => [match[1], jobsText.slice(match.index, starts[i + 1]?.index).replace(/\s*(?:\n {2}#[^\n]*)*\s*$/, "\n")]));
const job = (id) => {
  assert.ok(jobs.has(id), `no job ${id}`);
  return jobs.get(id);
};
// A job's steps' text, by step name, less the next step's comment.
const stepsOf = (id) =>
  new Map(
    job(id)
      .split(/\n(?= {6}- name: )/)
      .slice(1)
      .map((block) => [/^ {6}- name: (.+)$/m.exec(block)[1], block.replace(/\s*(?:\n {6}#[^\n]*)*\s*$/, "\n")]),
  );
const step = (id, name) => {
  const steps = stepsOf(id);
  assert.ok(steps.has(name), `${id} has no step named ${name}`);
  return steps.get(name);
};
const list = (block, key) =>
  new RegExp(`\\n {10}${key}: \\|\\n((?: {12}.+\\n)+)`)
    .exec(block)[1]
    .trim()
    .split("\n")
    .map((line) => line.trim());

test("the run-name renders as runTitle, so a run still going is found for its head", () => {
  const line = /^run-name: (.+)$/m.exec(text)[1];
  assert.equal(line, `"merge-risk #\${{ github.event.workflow_run.pull_requests[0].number || 'none' }} \${{ github.event.workflow_run.head_sha }}"`);
  const rendered = JSON.parse(line.replaceAll(/\$\{\{ github\.event\.workflow_run\.pull_requests\[0\]\.number \|\| 'none' \}\}/g, "7").replaceAll("${{ github.event.workflow_run.head_sha }}", "a".repeat(40)));
  assert.equal(rendered, runTitle(7, "a".repeat(40)));
});

test("the workflow grants nothing, its three jobs are the three legs, and each job token only reads", () => {
  assert.match(text, /\npermissions: \{\}\n/);
  assert.deepEqual([...jobs.keys()], Object.values(LEGS));
  for (const id of Object.values(LEGS)) {
    assert.match(job(id), /\n {4}cache-mode: read\n {4}permissions:\n {6}contents: read # [^\n]+\n {6}pull-requests: read # [^\n]+\n {6}actions: read # [^\n]+\n {4}(?:outputs|steps):/, id);
  }
  assert.doesNotMatch(text, /^ +[a-z-]+: write\b/m);
  assert.doesNotMatch(text, /id-token|request-lane-token|create-github-app-token/);
});

test("no pull request code is checked out, and every script and local action is main's", () => {
  for (const id of Object.values(LEGS)) {
    assert.equal([...job(id).matchAll(/uses: actions\/checkout@/g)].length, 1, id);
    assert.match(step(id, "Check out the default branch tip"), /ref: \$\{\{ steps\.tip\.outputs\.sha \}\}\n {10}path: \.base\n {10}persist-credentials: false/, id);
  }
  for (const [, uses] of text.matchAll(/uses: (\.\/[^\s]+)/g)) assert.match(uses, /^\.\/\.base\//, uses);
  for (const [, script] of text.matchAll(/node (\S+\.mjs)/g)) assert.match(script, /^\.base\//, script);
});

test("each leg holds one credential, in its presence check and its rating step alone", () => {
  const credential = {
    key: { secret: "PR_VERIFY_CLAUDE_API_KEY", input: "api-key" },
    subscription: { secret: "PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN", input: "subscription-token" },
    fallback: { secret: "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN", input: "fallback-token" },
  };
  for (const [leg, id] of Object.entries(LEGS)) {
    const { secret, input } = credential[leg];
    const holders = [...stepsOf(id)].filter(([, block]) => /secrets\./.test(block)).map(([name]) => name);
    assert.deepEqual(holders, ["Check the credential", "Rate the pull request"], id);
    const check = step(id, "Check the credential");
    assert.match(check, /uses: melodic-software\/ci-workflows\/\.github\/actions\/select-model-credential@[0-9a-f]{40} /, id);
    assert.match(check, new RegExp(`\\n {10}leg: ${leg}\\n {10}role: pr-verify\\n {10}credential-set: \\$\\{\\{ secrets\\.${secret} != '' \\}\\}\\n`), id);
    const rate = step(id, "Rate the pull request");
    assert.deepEqual([...rate.matchAll(/secrets\.([A-Z_]+)/g)].map(([, name]) => name), [secret], id);
    assert.match(rate, new RegExp(`\\n {10}${input}: \\$\\{\\{ secrets\\.${secret} \\}\\}\\n`), id);
    // Beyond its own, a job may only ask whether the fallback token is set.
    const others = [...job(id).matchAll(/secrets\.([A-Z_]+)( != '')?/g)].filter(([, name]) => name !== secret);
    assert.deepEqual(others.map(([whole]) => whole), leg === "subscription" ? ["secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != ''"] : [], id);
  }
  assert.match(step(LEGS.subscription, "Rate the pull request"), /\n {10}fallback-ready: \$\{\{ steps\.credential\.outputs\.fallback-ready \}\}\n/);
});

// credential-legs.test.mjs holds every start and credential decision to the
// conditions before select-model-credential; this pins their shape.
test("each leg starts only after the one before named it as the next leg, and a handoff is no failure", () => {
  assert.match(job(LEGS.subscription), /\n {4}needs: rate-merge-risk\n/);
  assert.match(job(LEGS.subscription), /&& needs\.rate-merge-risk\.result == 'success'\n {6}&& needs\.rate-merge-risk\.outputs\.next-leg == 'subscription'\n {4}runs-on:/);
  assert.match(job(LEGS.fallback), /\n {4}needs: rate-merge-risk-subscription\n/);
  assert.match(job(LEGS.fallback), /&& needs\.rate-merge-risk-subscription\.result == 'success'\n {6}&& needs\.rate-merge-risk-subscription\.outputs\.next-leg == 'fallback'\n {4}runs-on:/);
  for (const id of [LEGS.subscription, LEGS.fallback]) assert.match(job(id), /\n {4}if: >-\n {6}!cancelled\(\)\n {6}&& github\.ref == 'refs\/heads\/main'\n/, id);
  for (const id of Object.values(LEGS)) {
    assert.match(step(id, "Fail without a rating"), /if: always\(\) && steps\.checker\.outcome == 'success' && steps\.credential\.outputs\.present == 'true' && steps\.rating\.outcome != 'success' && steps\.rate\.outputs\.handoff != 'true'\n/, id);
  }
  // The key leg reads its credit history in its own step, under
  // continue-on-error and a 2-minute limit, so a read that fails or hangs runs
  // the key; its credential call skips a key whose credit stop is recent, and
  // the job marks a new one.
  const credit = step(LEGS.key, "Read the key's credit history");
  assert.match(credit, /\n {8}id: credit\n/);
  assert.match(credit, /\n {8}continue-on-error: true\n {8}timeout-minutes: 2\n/);
  assert.match(credit, /\n {10}leg: start\n {10}key-job: rate-merge-risk\n/);
  assert.match(credit, /\n {10}probe-minutes: "0"\n/);
  // The key leg decides its credential right after the resolver lets the head
  // through, before the trigger check, and only a key that runs goes on to
  // the trigger check and the reads after it.
  const keyOrder = [...stepsOf(LEGS.key).keys()];
  assert.deepEqual(keyOrder.slice(keyOrder.indexOf("Resolve the pull request"), keyOrder.indexOf("Check the trigger") + 1), ["Resolve the pull request", "Read the key's credit history", "Check the credential", "Report the skipped key leg", "Check the trigger"]);
  assert.match(credit, /\n {8}if: steps\.pr\.outputs\.proceed == 'true'\n/);
  assert.match(step(LEGS.key, "Check the credential"), /\n {8}if: steps\.pr\.outputs\.proceed == 'true'\n/);
  assert.match(step(LEGS.key, "Check the trigger"), /\n {8}if: steps\.pr\.outputs\.proceed == 'true' && steps\.credential\.outputs\.present == 'true'\n/);
  const check = step(LEGS.key, "Check the credential");
  assert.match(check, /\n {10}selected: \$\{\{ steps\.credit\.outputs\.next-leg \}\}\n/);
  assert.doesNotMatch(check, /key-job/);
  assert.match(step(LEGS.key, "Report the skipped key leg"), /if: steps\.credential\.outputs\.key-skipped == 'true'\n/);
  assert.match(step(LEGS.key, "Write the key's credit-stop marker"), /steps\.credit\.outputs\.marker == 'key-credit-stop-pr-rate-merge-risk\.yml-rate-merge-risk' && steps\.rate\.outputs\.handoff-reason == 'credit-stop'/);
  assert.match(step(LEGS.key, "Upload the key's credit-stop marker"), /name: key-credit-stop-pr-rate-merge-risk\.yml-rate-merge-risk\n/);
  // The key and subscription legs name the next leg the same way; the
  // fallback leg, last, names none.
  assert.equal(step(LEGS.key, "Pick the next leg"), step(LEGS.subscription, "Pick the next leg"));
  assert.ok(!stepsOf(LEGS.fallback).has("Pick the next leg"));
  for (const [leg, id] of Object.entries(LEGS)) {
    if (leg !== "key") assert.match(step(id, "Report the rating's outcome"), /\n {10}fallback-reason: \$\{\{ steps\.credential\.outputs\.fallback-reason \}\}\n/, id);
  }
});

// Every leg is the key leg's steps but for its credential, the key's credit
// gate and marker, the next-leg call, the lane record's fallback reason, and
// the key trigger check's wait on the credential decision.
test("the subscription and fallback legs repeat the key leg's steps exactly, step order included", () => {
  const KEY_ONLY = ["Read the key's credit history", "Report the skipped key leg", "Write the key's credit-stop marker", "Scan the key's credit-stop marker for credentials", "Upload the key's credit-stop marker"];
  const shape = (id) =>
    [...stepsOf(id)]
      .filter(([name]) => !KEY_ONLY.includes(name) && name !== "Check the credential" && name !== "Pick the next leg")
      .map(([name, block]) =>
        name === "Rate the pull request"
          ? block.replace(/\n {10}(?:api-key|subscription-token|fallback-token|fallback-ready): [^\n]+/g, "")
          : name === "Report the rating's outcome"
            ? block.replace(/\n {10}fallback-reason: [^\n]+/, "")
            : name === "Check the trigger" && id === LEGS.key
              ? block.replace(" && steps.credential.outputs.present == 'true'\n", "\n")
              : block,
      );
  const key = shape(LEGS.key);
  assert.ok(key.length >= 20, `the key leg has ${key.length} shared steps`);
  assert.deepEqual(shape(LEGS.subscription), key);
  assert.deepEqual(shape(LEGS.fallback), key);
});

// A step runs only when every step its if: requires ran: a conjunction (no
// `||`) of terms, where `steps.X.outcome == 'success'`, `steps.X.outputs.Y ==
// '<value>'` and `steps.X.outputs.Y != ''` each need X to have run.
const requires = (id) => {
  const ifs = new Map();
  for (const block of stepsOf(id).values()) {
    const sid = /^ {8}id: (\S+)$/m.exec(block)?.[1];
    if (sid) ifs.set(sid, /^ {8}if: (.*)$/m.exec(block)?.[1] ?? "");
  }
  // The steps a condition requires, transitively.
  return (start) => {
    const seen = new Set();
    const walk = (cond, at) => {
      assert.doesNotMatch(cond, /\|\|/, `${id} ${at}'s if is a conjunction`);
      for (const [, dep] of cond.matchAll(/steps\.([a-z-]+)\.(?:outcome == 'success'|outputs\.[a-z-]+ (?:== '[^']+'|!= ''))/g)) {
        if (!seen.has(dep)) {
          seen.add(dep);
          walk(ifs.get(dep) ?? "", `step ${dep}`);
        }
      }
    };
    walk(start, "the step");
    return seen;
  };
};

test("in every leg, no model or upload step runs unless the resolver and the trigger check let the head through", () => {
  const GUARDED = ["Stage the review plugin", "Apply the Claude managed settings", "Isolate the runner", "Write the prompt and schema", "Rate the pull request", "Write the rating", "Upload the rating", "Upload the sealed transcript"];
  for (const id of Object.values(LEGS)) {
    const needs = requires(id);
    const names = [...stepsOf(id).keys()];
    const guarded = id === LEGS.key ? [...GUARDED, "Upload the key's credit-stop marker"] : GUARDED;
    for (const name of guarded) {
      assert.ok(names.includes(name), `${id} has ${name}`);
      const deps = needs(/^ {8}if: (.*)$/m.exec(step(id, name))?.[1] ?? "");
      for (const gate of ["pr", "gate", "agree"]) assert.ok(deps.has(gate), `${id}: ${name} requires step ${gate}`);
    }
  }
  // The trigger check runs only on the resolver's proceed (in the key leg,
  // also only for a key that runs), and the agreement step only on the
  // trigger check's.
  for (const id of Object.values(LEGS)) {
    assert.match(step(id, "Check the trigger"), /\n {8}if: steps\.pr\.outputs\.proceed == 'true'(?: && steps\.credential\.outputs\.present == 'true')?\n/, id);
    assert.match(step(id, "Assert the gate and the resolver agree"), /\n {8}if: steps\.gate\.outputs\.proceed == 'true'\n/, id);
  }
});

test("the rating runs under dontAsk on the data directory and the review plugin's copy alone", () => {
  for (const id of Object.values(LEGS)) {
    const rate = step(id, "Rate the pull request");
    assert.match(rate, /uses: melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli@[0-9a-f]{40} /);
    assert.match(rate, /role: pr-verify\n/);
    assert.match(rate, /permission-mode: dontAsk\n/);
    assert.match(rate, /continue-on-error: true\n/);
    assert.deepEqual(list(rate, "tools"), ["Read", "Skill", "Agent"]);
    assert.deepEqual(list(rate, "allowed-tools"), ["Read(./merge-risk-data/**)", "Read(./.lane/plugins/review/**)", "Skill(review:merge-risk *)", "Agent"]);
    const denied = list(rate, "disallowed-tools");
    assert.deepEqual(denied, [
      "Read(./.base/**)",
      "Read(/${{ runner.temp }}/**)",
      "Read(~/.config/**)",
      "Read(~/.git-credentials)",
      "Read(~/.claude/**)",
      "Read(//proc/**)",
      "Read(//sys/**)",
      "Read(//etc/**)",
      "Glob",
      "Grep",
      "Bash",
      "Edit",
      "Write",
      "NotebookEdit",
      "WebFetch",
      "WebSearch",
      "mcp__*",
    ]);
    // None may name the workspace or the home whole: the workspace sits under it.
    assert.ok(!denied.some((rule) => ["Read(~/**)", "Read(./**)", "Read(//**)", "Read"].includes(rule)));
    assert.deepEqual(list(rate, "plugin-dirs"), [".lane/plugins/review"]);
    assert.match(rate, /CLAUDE_CODE_SUBAGENT_MODEL_FORCE: \$\{\{ steps\.checker\.outputs\.force \}\}/);
    // The managed settings and the isolation come first.
    const order = [...stepsOf(id).keys()];
    assert.ok(order.indexOf("Apply the Claude managed settings") < order.indexOf("Isolate the runner"), id);
    assert.ok(order.indexOf("Isolate the runner") < order.indexOf("Rate the pull request"), id);
    assert.match(step(id, "Stage the review plugin"), /chmod -R a-w \.lane\/plugins\/review/);
  }
  // merge-risk's frontmatter allowed-tools pre-approves bare Read once the
  // skill runs, so these deny rules, not the allow list, bound what it reads.
  assert.match(readFileSync(new URL("../../../plugins/review/skills/merge-risk/SKILL.md", import.meta.url), "utf8"), /^allowed-tools: \[[^\]]*"Read"/m);
  assert.match(text, /allow rules do not bound Read once the skill runs/);
});

test("the names the arm side reads match merge-risk-line.mjs", () => {
  for (const id of Object.values(LEGS)) {
    const resolve = step(id, "Resolve the pull request");
    assert.match(resolve, new RegExp(`RATED_WORKFLOW_PATH: ${RATING_WORKFLOW_PATH.replaceAll(".", "\\.")}\\n`));
    assert.match(resolve, new RegExp(`RATED_ARTIFACT_PREFIX: ${ARTIFACT_PREFIX}\\n`));
    assert.match(resolve, /VERIFY_AUTHORS: lane\n/);
    const upload = step(id, "Upload the rating");
    assert.match(upload, new RegExp(`name: ${ARTIFACT_PREFIX}-\\$\\{\\{ steps\\.pr\\.outputs\\.pr-number \\}\\}-\\$\\{\\{ steps\\.pr\\.outputs\\.head-sha \\}\\}\\n`));
    assert.match(upload, /retention-days: 7\n/);
    assert.match(upload, /steps\.scan-upload\.outputs\.clean == 'true'/);
  }
});

test("the trigger is pr-verify's, judged only for a successful same-repository pull_request run on main", () => {
  assert.match(text, /\non:\n {2}# [^\n]+\n {2}workflow_run: # zizmor: ignore\[dangerous-triggers\]\n {4}workflows: \[PR Require Checks\]\n {4}types: \[completed\]\n/);
  for (const id of Object.values(LEGS)) {
    assert.match(job(id), /github\.ref == 'refs\/heads\/main'\n {6}&& github\.event\.workflow_run\.event == 'pull_request'\n {6}&& github\.event\.workflow_run\.conclusion == 'success'\n {6}&& github\.event\.workflow_run\.head_repository\.full_name == github\.repository\n/, id);
  }
  assert.match(text, /cancel-in-progress: false\n/);
});
