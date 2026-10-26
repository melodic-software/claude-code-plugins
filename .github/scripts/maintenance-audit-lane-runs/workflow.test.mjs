// maintenance-audit-lane-runs.yml's hardening, from docs/conventions/pr-pipeline/README.md
// ("Every lane" and "The lane sweep"): only a schedule or a manual run starts
// it, the model legs and the route jobs hold read permissions only, each leg
// runs run-claude-cli as the automations role on one credential with Read,
// Grep and Glob and no shell, only the scripted file and triage-sweep jobs
// write, and every job checks the kill switch first. A unit moves from the key
// leg to the subscription leg, and from there to the fallback leg, only on a
// clean handoff. The hourly schedule runs only the triage sweep.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/maintenance-audit-lane-runs.yml", import.meta.url), "utf8");
const jobs = Object.fromEntries(
  `\n${text.split("\njobs:\n")[1]}`
    .split(/\n(?= {2}[a-z][a-z-]*:\n)/)
    .slice(1)
    .map((block) => [/^ {2}([a-z-]+):/.exec(block)[1], block]),
);
const permissions = (job) => {
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(jobs[job])[1];
  return Object.fromEntries([...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => [m[1], m[2]]));
};
const KEY = "judge";
const SUB = "judge-subscription";
const FB = "judge-fallback";
const LEGS = [KEY, SUB, FB];
const ROUTES = ["judge-handoffs", "judge-subscription-handoffs"];
const FALLBACK = "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN";
const CREDENTIAL = {
  [KEY]: ["api-key", "AUTOMATIONS_CLAUDE_API_KEY"],
  [SUB]: ["subscription-token", "AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN"],
  [FB]: ["fallback-token", FALLBACK],
};
// Each step starts at a `      - name:` line of its job.
const steps = (job) =>
  jobs[job]
    .split(/\n(?= {6}- name: )/)
    .slice(1)
    .map((block) => ({ name: /^ {6}- name: (.*)$/m.exec(block)[1], block }));
const step = (name, job) => {
  const found = steps(job).find((s) => s.name === name);
  assert.ok(found, `a step named ${name} in ${job}`);
  return found.block;
};
const value = (block, key, indent = 10) => new RegExp(`^ {${indent}}${key}: (.*)$`, "m").exec(block)?.[1];
const list = (block, key) =>
  (new RegExp(`^ {10}${key}: \\|\\n((?: {12}.*\\n?)+)`, "m").exec(block)?.[1] ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
const LAUNCHER = /^melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli@[0-9a-f]{40} # v\d+\.\d+\.\d+$/;
// Why each later leg ran, for its unit's one lane record: the route job's
// closed-set reason, compared to fixed strings, never written into a script.
const SUB_REASON =
  "${{ matrix.reason == 'credit-stop' && 'credit-stop' || matrix.reason == 'auth' && 'auth' || matrix.reason == 'no-key' && 'no-key' || '' }}";
const FB_REASON =
  "${{ matrix.reason == 'limit-stop' && 'limit-stop' || matrix.reason == 'credit-stop' && 'credit-stop' || matrix.reason == 'auth' && 'auth' || '' }}";

test("only a schedule or a manual run starts the lane, with no default permissions", () => {
  const on = /\non:\n((?: {2}.*\n| {4}.*\n)+)/.exec(text)[1];
  assert.deepEqual(
    [...on.matchAll(/^ {2}([a-z_]+):/gm)].map((m) => m[1]),
    ["schedule", "workflow_dispatch"],
  );
  assert.match(text, /\npermissions: \{\}\n/);
});

test("the jobs run collect, the three legs with a route job between each, file and triage-sweep, in that order", () => {
  assert.deepEqual(Object.keys(jobs), ["collect", KEY, ROUTES[0], SUB, ROUTES[1], FB, "file", "triage-sweep"]);
  assert.match(jobs[KEY], /\n {4}needs: collect\n/);
  assert.match(jobs[ROUTES[0]], /\n {4}needs: judge\n/);
  assert.match(jobs[SUB], /\n {4}needs: judge-handoffs\n/);
  assert.match(jobs[ROUTES[1]], /\n {4}needs: judge-subscription\n/);
  assert.match(jobs[FB], /\n {4}needs: judge-subscription-handoffs\n/);
  assert.match(jobs.file, /\n {4}needs: \[collect, judge, judge-subscription, judge-fallback\]\n/);
});

test("only the file and triage-sweep jobs write, and no job can mint a token", () => {
  for (const job of ["collect", ...LEGS, ...ROUTES]) {
    assert.ok(
      Object.values(permissions(job)).every((v) => v === "read"),
      job,
    );
  }
  assert.deepEqual(permissions("file"), {
    actions: "read",
    contents: "read",
    issues: "write",
  });
  assert.deepEqual(permissions("triage-sweep"), {
    actions: "write",
    contents: "read",
    issues: "write",
  });
  assert.match(jobs["triage-sweep"], /\n {10}GITHUB_TOKEN: \$\{\{ github\.token \}\}\n/);
  assert.doesNotMatch(text, /id-token|request-lane-token|secrets\.[A-Z_]*(APP|PRIVATE)_KEY/);
});

test("the model runs only in the three legs, on one pinned run-claude-cli as the automations role, each on its one secret", () => {
  assert.doesNotMatch(text, /claude-code-action/);
  const pins = new Set();
  for (const job of LEGS) {
    const launchers = steps(job).filter((s) => /uses: melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli@/.test(s.block));
    assert.deepEqual(
      launchers.map((s) => s.name),
      ["Judge the unit"],
      job,
    );
    const judge = launchers[0].block;
    pins.add(value(judge, "uses", 8));
    assert.match(value(judge, "uses", 8), LAUNCHER, job);
    assert.equal(value(judge, "role"), "automations", job);
    assert.equal(value(judge, "continue-on-error", 8), "true", job);
    const [input, secret] = CREDENTIAL[job];
    assert.equal(value(judge, input), `\${{ secrets.${secret} }}`, job);
    for (const [other] of LEGS.filter((id) => id !== job).map((id) => CREDENTIAL[id])) {
      assert.equal(value(judge, other), undefined, `${job} ${other}`);
    }
    // Each secret is read in its own leg, and the fallback token's presence
    // only in the subscription leg, which may hand off to it.
    const secrets = [...jobs[job].matchAll(/secrets\.([A-Z_]+)/g)].map((m) => m[1]);
    assert.deepEqual([...new Set(secrets)].sort(), job === SUB ? [secret, FALLBACK].sort() : [secret], job);
  }
  assert.equal(pins.size, 1, "one launcher pin");
  for (const job of ["collect", ...ROUTES, "file", "triage-sweep"]) assert.doesNotMatch(jobs[job], /secrets\./, job);
});

test("each leg reads only the data and the checkout, with Read, Grep and Glob and no shell, under dontAsk", () => {
  for (const job of LEGS) {
    const judge = step("Judge the unit", job);
    assert.equal(value(judge, "permission-mode"), "dontAsk", job);
    assert.deepEqual(list(judge, "tools"), ["Read", "Grep", "Glob"], job);
    // A bare Grep or Glob allow rule reaches every path, /proc included.
    assert.deepEqual(list(judge, "allowed-tools"), ["Read(./.lane-sweep-data/**)", "Read(./.base/**)"], job);
    const denied = list(judge, "disallowed-tools");
    for (const rule of ["Bash", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch", "Agent", "mcp__*"]) {
      assert.ok(denied.includes(rule), `${job} denies ${rule}`);
    }
    for (const path of ["//proc/**", "//sys/**", "~/.*", "~/.*/**", "/${{ runner.temp }}/**"]) {
      assert.ok(denied.includes(`Read(${path})`), `${job} denies Read(${path})`);
    }
    // The workspace is under home, so a home-wide deny would block the checkout.
    assert.ok(!denied.includes("Read(~/**)"), job);
    assert.equal(value(judge, "json-schema-file"), "${{ runner.temp }}/lane-sweep-schema.json", job);
    assert.match(value(step("Write the findings", job), "STRUCTURED_OUTPUT_FILE"), /^\$\{\{ steps\.judge\.outputs\.structured-output-file \}\}$/, job);
  }
});

test("the later legs repeat the key leg's steps but for the credential, the leg check and the fallback reason", () => {
  // Comments differ, and so do the lines that name the credential, the
  // handoff and the leg's place in the chain; every other line is equal.
  const differs = [
    /^ {10}(api-key|subscription-token|fallback-token|fallback-ready|fallback-reason|known-failure-class): /,
    /^ {8}if: .*steps\.(handoff|key-leg|sub-leg)\.|^ {8}if: always\(\) /,
    /^ {8}if: steps\.judge\.outcome == 'success' \|\| steps\.judge\.outcome == 'failure'$/,
  ];
  const normalize = (job) =>
    steps(job)
      .filter((s) => !/^Check the (key|subscription) leg$|^(Record|Upload) the handoff$|^Check the credential$/.test(s.name))
      .map(({ name, block }) => ({
        name,
        lines: block.split("\n").filter((line) => line.trim() !== "" && !/^\s*#/.test(line) && !differs.some((re) => re.test(line))),
      }));
  assert.deepEqual(normalize(SUB), normalize(KEY));
  assert.deepEqual(normalize(FB), normalize(KEY));
});

test("a unit reaches the next leg only through a clean handoff its route job reads from a marker", () => {
  assert.match(jobs[SUB], /\n {4}if: \$\{\{ !cancelled\(\) && needs\.judge-handoffs\.result == 'success' && needs\.judge-handoffs\.outputs\.count != '' && needs\.judge-handoffs\.outputs\.count != '0' \}\}\n/);
  assert.match(jobs[SUB], /\n {6}matrix: \$\{\{ fromJson\(needs\.judge-handoffs\.outputs\.matrix\) \}\}\n/);
  assert.match(
    jobs[FB],
    /\n {4}if: \$\{\{ !cancelled\(\) && needs\.judge-subscription-handoffs\.result == 'success' && needs\.judge-subscription-handoffs\.outputs\.count != '' && needs\.judge-subscription-handoffs\.outputs\.count != '0' \}\}\n/,
  );
  assert.match(jobs[FB], /\n {6}matrix: \$\{\{ fromJson\(needs\.judge-subscription-handoffs\.outputs\.matrix\) \}\}\n/);
  // The key leg hands off on the launcher's handoff after a denial-free leg,
  // or on an empty key; the subscription leg only on the launcher's handoff,
  // and only with the fallback token set; the fallback leg never.
  assert.equal(value(step("Record the handoff", KEY), "if", 8), "steps.key-leg.outputs.clean == 'true' || steps.credential.outputs.present == 'false'");
  assert.equal(value(step("Record the handoff", SUB), "if", 8), "steps.sub-leg.outputs.clean == 'true'");
  assert.ok(!steps(FB).some((s) => /handoff/i.test(s.name)), "the fallback leg records no handoff");
  for (const [job, leg] of [
    [KEY, "key-leg"],
    [SUB, "sub-leg"],
  ]) {
    const check = steps(job).find((s) => / leg$/.test(s.name)).block;
    assert.equal(value(check, "id", 8), leg, job);
    assert.equal(value(check, "if", 8), "steps.judge.outputs.handoff == 'true'", job);
    assert.match(check, /handoff\.mjs check-leg\n/, job);
  }
  assert.equal(value(step("Judge the unit", SUB), "fallback-ready"), "${{ steps.credential.outputs.fallback-ready }}");
  for (const job of [KEY, FB]) assert.equal(value(step("Judge the unit", job), "fallback-ready"), undefined, job);
  assert.equal(value(step("Upload the handoff", KEY), "name"), "judge-handoff-${{ matrix.unit }}");
  assert.equal(value(step("Upload the handoff", SUB), "name"), "judge-subscription-handoff-${{ matrix.unit }}");
  assert.equal(value(step("Upload the handoff", KEY), "path"), "${{ runner.temp }}/lane-sweep-handoff/judge-handoff-${{ matrix.unit }}.json");
  assert.equal(value(step("Upload the handoff", SUB), "path"), "${{ runner.temp }}/lane-sweep-handoff/judge-subscription-handoff-${{ matrix.unit }}.json");
  for (const [route, leg, pattern] of [
    [ROUTES[0], "key", "judge-handoff-*"],
    [ROUTES[1], "subscription", "judge-subscription-handoff-*"],
  ]) {
    assert.equal(value(step("Download the handoff markers", route), "pattern"), pattern, route);
    // A lone match would otherwise land straight in the path, several each in its own directory.
    assert.equal(value(step("Download the handoff markers", route), "merge-multiple"), "true", route);
    const routeStep = steps(route).find((s) => s.name.startsWith("Route the handed-off units")).block;
    assert.equal(value(routeStep, "LEG"), leg, route);
    assert.match(routeStep, /\n {8}run: node \.base\/\.github\/scripts\/maintenance-audit-lane-runs\/handoff\.mjs route\n/, route);
  }
});

test("each unit leaves one lane record, from the leg that saw its end", () => {
  const report = (job) => step("Report the judgment's outcome", job);
  const ran = "(steps.judge.outcome == 'success' || steps.judge.outcome == 'failure')";
  assert.equal(value(report(KEY), "if", 8), `${ran} && (steps.judge.outputs.handoff != 'true' || steps.key-leg.outcome == 'failure')`);
  assert.equal(value(report(SUB), "if", 8), `${ran} && (steps.judge.outputs.handoff != 'true' || steps.sub-leg.outcome == 'failure')`);
  assert.equal(value(report(FB), "if", 8), "steps.judge.outcome == 'success' || steps.judge.outcome == 'failure'");
  assert.equal(value(report(KEY), "fallback-reason"), undefined);
  assert.equal(value(report(SUB), "fallback-reason"), SUB_REASON);
  assert.equal(value(report(FB), "fallback-reason"), FB_REASON);
  // matrix.reason reaches nothing else.
  for (const job of LEGS) assert.equal(jobs[job].match(/matrix\.reason/g)?.length ?? 0, job === KEY ? 0 : 3, job);
  // A handoff spares a leg its red; any other run with no findings fails last.
  for (const job of LEGS) {
    const names = steps(job).map((s) => s.name);
    assert.equal(names.at(-1), "Fail without findings", job);
    const fail = value(step("Fail without findings", job), "if", 8);
    const expected = "always() && steps.unit.outcome == 'success' && steps.findings.outcome != 'success'";
    assert.equal(fail, job === FB ? expected : `${expected} && steps.handoff.outcome != 'success'`, job);
  }
});

test("every job checks the kill switch before its first API or model step", () => {
  for (const [name, block] of Object.entries(jobs)) {
    const kill = block.indexOf("check-kill-switch");
    assert.ok(kill > 0, `${name} checks the kill switch`);
    const work = block.search(/node \.base\/\.github\/scripts\/maintenance-audit-lane-runs\/|run-claude-cli@|download-artifact@/);
    assert.ok(work > kill, `${name} works only after the kill switch`);
  }
});

test("the daily schedule runs the audit, the hourly one only the triage sweep", () => {
  const crons = [...text.matchAll(/\n {4}- cron: "([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(crons, ["33 6 * * *", "17 * * * *"]);
  assert.match(jobs.collect, /\n {4}if: github\.ref == 'refs\/heads\/main' && github\.event\.schedule != '17 \* \* \* \*'\n/);
  assert.match(jobs["triage-sweep"], /\n {4}if: github\.ref == 'refs\/heads\/main'\n/);
  // Two passes at once could dispatch the same issue twice.
  assert.match(jobs["triage-sweep"], /\n {4}concurrency:\n {6}group: [^\n]+\n {6}cancel-in-progress: false\n/);
});
