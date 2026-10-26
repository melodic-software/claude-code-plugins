// Expected values come from the verdict rules in
// docs/conventions/pr-pipeline/README.md ("Verifier verdict"): the artifact is named pr-verify-<pr>-<head-sha>-<verdict>, the
// verdict JSON holds {pr, head_sha, base_sha, head_ref, linked_issues,
// verdict, summary, notes, run_id}, each linked issue records its author, and
// malformed output writes nothing. The output comes from the last result
// message of run-claude-cli's execution file, a JSON array of CLI messages
// (its action.yml, output execution-file), and model text shaped like a
// credential (an Anthropic key or OAuth token, both sk-ant-; a GitHub token,
// per GitHub's documented ghp_ prefix and 36-character body; an AWS access key
// id, AKIA plus 16; a PEM private key header, RFC 7468) writes nothing.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { artifactName, buildVerdict, checkKeyLeg, HEAD_REF_DIGEST_HEX, headRefDigest, main, prText, structuredOutput } from "./write-verdict.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const ISSUE = {
  number: 7,
  author_login: "maintainer",
  author_id: 100,
  author_type: "User",
  last_edited_at: null,
  editor_login: null,
  editor_id: null,
  editor_type: null,
  spec_comments: [{ id: 1, updated_at: "2026-10-12T00:00:00Z" }],
};
// `printf 'feat: x\n\nthe body' | sha256sum`: the title and body judged.
const BODY = "30c46c02508c68bec029c3f02ee3b211984ba7568654283435694c3eb137717f";
const ids = { pr: "41", headSha: HEAD, baseSha: BASE, runId: "9001", headRef: "feat/x", bodySha256: BODY, linkedIssues: [ISSUE] };
const ok = JSON.stringify({ verdict: "pass", summary: "s", notes: [] });

test("each verdict names its artifact with the PR, the head and the verdict", () => {
  for (const verdict of ["pass", "pass-notes", "fail"]) {
    const built = buildVerdict({ ...ids, output: JSON.stringify({ verdict, summary: "s", notes: ["n"] }) });
    assert.deepEqual(built, {
      pr: 41,
      head_sha: HEAD,
      base_sha: BASE,
      head_ref: "feat/x",
      linked_issues: [ISSUE],
      spec_kind: "closes",
      intent: "issues",
      intent_sha256: BODY,
      verdict,
      summary: "s",
      notes: ["n"],
      run_id: 9001,
    });
    assert.equal(artifactName(built), `pr-verify-41-${HEAD}-${verdict}${verdict === "fail" ? "-i7" : ""}`);
  }
});

test("the judged text is the title and body, and its digest the sha256 of that", () => {
  assert.equal(prText({ title: "feat: x", body: "the body" }), "feat: x\n\nthe body");
  assert.equal(prText({ title: "feat: x", body: null }), "feat: x\n\n");
  assert.equal(createHash("sha256").update(prText({ title: "feat: x", body: "the body" })).digest("hex"), BODY);
});

test("a FAIL's name carries the issues it records, ascending and once each", () => {
  const issue = (number) => ({ ...ISSUE, number });
  const name = (verdict, linkedIssues) =>
    artifactName(buildVerdict({ ...ids, linkedIssues, output: JSON.stringify({ verdict, summary: "s", notes: [] }) }));
  assert.equal(name("fail", [issue(12), issue(7), issue(12)]), `pr-verify-41-${HEAD}-fail-i7.12`);
  assert.equal(name("fail", []), `pr-verify-41-${HEAD}-fail`);
  assert.equal(name("pass", [issue(7)]), `pr-verify-41-${HEAD}-pass`);
  assert.equal(name("pass-notes", [issue(7)]), `pr-verify-41-${HEAD}-pass-notes`);
  const ten = Array.from({ length: 10 }, (_, i) => issue(i + 1));
  assert.equal(name("fail", ten), `pr-verify-41-${HEAD}-fail-i1.2.3.4.5.6.7.8.9.10`);
});

test("a FAIL whose issues no name can carry is written under the plain name, with one warning", (t) => {
  const log = t.mock.method(console, "log", () => {});
  const fail = (numbers) => ({ pr: 41, head_sha: HEAD, verdict: "fail", linked_issues: numbers.map((number) => ({ number })) });
  // Eleven issues pass the cap; an 11-digit issue number passes the pattern.
  const eleven = Array.from({ length: 11 }, (_, i) => i + 1);
  for (const numbers of [eleven, [10000000000]]) {
    log.mock.resetCalls();
    assert.equal(artifactName(fail(numbers)), `pr-verify-41-${HEAD}-fail`, JSON.stringify(numbers));
    assert.equal(log.mock.callCount(), 1);
    assert.match(log.mock.calls[0].arguments[0], /^::warning::/);
  }
});

test("a name the readers would not take is refused before any upload", () => {
  // An 11-digit pull request number, or a head that is not lowercase hex:
  // the readers' pattern (resolve-pr NAME) refuses both, so the writer does.
  const fail = (overrides) => ({ pr: 41, head_sha: HEAD, verdict: "fail", linked_issues: [], ...overrides });
  assert.equal(artifactName(fail({ pr: 9999999999 })), `pr-verify-9999999999-${HEAD}-fail`);
  for (const verdict of [fail({ pr: 10000000000 }), fail({ head_sha: "A".repeat(40) })]) {
    assert.throws(() => artifactName(verdict), /no reader takes/, JSON.stringify(verdict));
  }
});

test("the head-ref digest is the first 16 hex digits of the branch's SHA-256", () => {
  // `printf %s <ref> | sha256sum`, cut to 16 digits.
  assert.equal(HEAD_REF_DIGEST_HEX, 16);
  assert.equal(headRefDigest("feat/x"), "79b4cc554b80dca6");
  assert.equal(headRefDigest("feat/a+b"), "a27da2afd9962004");
  assert.equal(headRefDigest("fix/\u00e9"), "8c8a071ad0e51f5e");
});

test("output outside the schema throws", () => {
  for (const output of [
    "",
    "not json",
    "[]",
    JSON.stringify({ verdict: "PASS", summary: "s", notes: [] }),
    JSON.stringify({ verdict: "pass", summary: 1, notes: [] }),
    JSON.stringify({ verdict: "pass", summary: "s", notes: "n" }),
    JSON.stringify({ verdict: "pass", summary: "s", notes: [1] }),
    JSON.stringify({ verdict: "pass", summary: "s" }),
    JSON.stringify({ verdict: "pass", summary: "s", notes: [], extra: true }),
  ]) {
    assert.throws(() => buildVerdict({ ...ids, output }), undefined, output);
  }
});

test("a malformed PR number, SHA, run id, head branch or body digest throws", () => {
  for (const bad of [
    { pr: "0" },
    { pr: "4x" },
    { headSha: "A".repeat(40) },
    { baseSha: "" },
    { runId: "-1" },
    { headRef: "a b" },
    { headRef: "" },
    { bodySha256: undefined },
    { bodySha256: "" },
    { bodySha256: BODY.toUpperCase() },
    { bodySha256: BODY.slice(1) },
  ]) {
    assert.throws(() => buildVerdict({ ...ids, ...bad, output: ok }), undefined, JSON.stringify(bad));
  }
});

test("linked issues outside their schema throw", () => {
  for (const linkedIssues of [
    null,
    {},
    [{ ...ISSUE, number: 0 }],
    [{ ...ISSUE, author_login: 5 }],
    [{ ...ISSUE, author_id: "100" }],
    [{ ...ISSUE, author_type: 1 }],
    [{ ...ISSUE, editor_login: 5 }],
    [{ ...ISSUE, editor_id: "200" }],
    [{ ...ISSUE, editor_type: false }],
    [{ ...ISSUE, last_edited_at: 0 }],
    [{ ...ISSUE, spec_comments: null }],
    [{ ...ISSUE, spec_comments: [{ id: "1", updated_at: "t" }] }],
    [{ ...ISSUE, spec_comments: [{ id: 1, updated_at: null }] }],
    [{ ...ISSUE, spec_comments: [{ id: 1, updated_at: "t", body: "x" }] }],
    [{ ...ISSUE, extra: 1 }],
    [{ number: 7, author_login: "m", author_id: 1 }],
  ]) {
    assert.throws(() => buildVerdict({ ...ids, linkedIssues, output: ok }), undefined, JSON.stringify(linkedIssues));
  }
  assert.deepEqual(buildVerdict({ ...ids, linkedIssues: [], output: ok }).linked_issues, []);
  // The intent source: the pull request's own title and body when the spec
  // text holds them (resolve-pr.mjs), else its closing issues.
  const own = [{ number: 41, source: "pull-request", body: "t\n\nb", comments: [] }];
  assert.equal(buildVerdict({ ...ids, linkedIssues: [], specText: own, output: ok }).intent, "pull-request");
  // The hash of the title and body judged, on every verdict, which the gate
  // compares live for a pull-request intent and across verdicts of the same
  // change.
  assert.equal(buildVerdict({ ...ids, linkedIssues: [], specText: own, output: ok }).intent_sha256, BODY);
  assert.equal(buildVerdict({ ...ids, output: ok }).intent_sha256, BODY);
  assert.equal(buildVerdict({ ...ids, linkedIssues: [], specText: [], output: ok }).intent, "issues");
  assert.equal(buildVerdict({ ...ids, output: ok }).intent, "issues");
  // The link kind resolve-pr gave each spec entry: a Refs issue is recorded as
  // `refs`, which the gate binds to the live link.
  const kind = (specText, linked = [ISSUE]) => buildVerdict({ ...ids, linkedIssues: linked, specText, output: ok }).spec_kind;
  assert.equal(kind([{ number: 7, spec_kind: "refs", body: "b", comments: [] }]), "refs");
  assert.equal(kind([{ number: 7, spec_kind: "closes", body: "b", comments: [] }]), "closes");
  assert.equal(kind(own, []), "pull-request");
  assert.equal(kind([], []), "none");
  // A Refs FAIL carries its issue in its name, as a closing one does: the
  // gate counts another PR's FAILs toward the issue's cap by name alone.
  const refsFail = buildVerdict({
    ...ids,
    linkedIssues: [ISSUE],
    specText: [{ number: 7, spec_kind: "refs", body: "b", comments: [] }],
    output: JSON.stringify({ verdict: "fail", summary: "s", notes: [] }),
  });
  assert.equal(artifactName(refsFail), `pr-verify-41-${HEAD}-fail-i7`);
  const edited = { ...ISSUE, last_edited_at: "2026-10-14T00:00:00Z", editor_login: "lanes", editor_id: 200, editor_type: "Bot" };
  assert.deepEqual(buildVerdict({ ...ids, linkedIssues: [edited], output: ok }).linked_issues, [edited]);
});

// Built at run time so no key-shaped literal sits in the repository.
const KEY = `${"sk-ant-"}api03-${"Q".repeat(40)}`;
const TOKEN = `${"sk-ant-"}oat01-${"Z".repeat(40)}`;

test("a summary or note shaped like an Anthropic key or OAuth token throws", () => {
  for (const output of [
    { verdict: "pass", summary: `the key is ${KEY}`, notes: [] },
    { verdict: "fail", summary: "s", notes: ["fine", `token ${TOKEN} leaked`] },
    { verdict: "pass-notes", summary: TOKEN, notes: [] },
  ]) {
    assert.throws(() => buildVerdict({ ...ids, output: JSON.stringify(output) }), /credential/, JSON.stringify(output));
  }
});

test("naming the key prefix alone is not a credential", () => {
  const output = JSON.stringify({ verdict: "pass", summary: "keys start with sk-ant-", notes: ["sk-ant- prefix"] });
  assert.equal(buildVerdict({ ...ids, output }).summary, "keys start with sk-ant-");
});

// Other credential shapes from their published formats, also built at run time.
const GITHUB_TOKEN = `${"ghp_"}${"k".repeat(36)}`;
const AWS_KEY = `${"AKIA"}${"Q7".repeat(8)}`;
const PEM = `-----BEGIN ${"RSA PRIVATE"} KEY-----`;

test("a summary or note shaped like any shared credential pattern throws, naming the kind", () => {
  for (const [secret, kind] of [
    [GITHUB_TOKEN, "GitHub token"],
    [AWS_KEY, "AWS access key"],
    [PEM, "private key"],
  ]) {
    for (const output of [
      { verdict: "pass", summary: `found ${secret}`, notes: [] },
      { verdict: "fail", summary: "s", notes: ["fine", `see ${secret}`] },
    ]) {
      assert.throws(() => buildVerdict({ ...ids, output: JSON.stringify(output) }), new RegExp(`credential \\(${kind}\\)`), kind);
    }
  }
});

test("an ordinary verdict naming SHAs, paths and the ghp_ prefix passes", () => {
  const summary = `Checked ${HEAD} against ${BASE}; lib/publish-gate.mjs:27 matches tokens that start ghp_.`;
  const output = JSON.stringify({ verdict: "pass-notes", summary, notes: [".github/scripts/pr-verify/write-verdict.mjs:95 changed"] });
  assert.equal(buildVerdict({ ...ids, output }).summary, summary);
});

test("the structured output is the last result message's", () => {
  const first = { verdict: "fail", summary: "first", notes: [] };
  const last = { verdict: "pass", summary: "last", notes: [] };
  assert.deepEqual(
    structuredOutput([
      { type: "system", subtype: "init" },
      { type: "result", subtype: "success", structured_output: first },
      { type: "assistant" },
      { type: "result", subtype: "success", structured_output: last },
    ]),
    last,
  );
  for (const messages of [[], [{ type: "assistant" }], [{ type: "result", subtype: "error_max_turns" }], {}, null]) {
    assert.throws(() => structuredOutput(messages), /no result with a structured output/, JSON.stringify(messages));
  }
});

test("a result with permission denials throws, naming the tools and never their inputs", () => {
  const messages = [
    {
      type: "result",
      subtype: "success",
      structured_output: { verdict: "pass", summary: "s", notes: [] },
      permission_denials: [
        { tool_name: "Read", tool_use_id: "t1", tool_input: { file_path: "/secret/path" } },
        { tool_name: "Bash", tool_use_id: "t2", tool_input: { command: "env" } },
        { tool_name: "Read", tool_use_id: "t3", tool_input: { file_path: "/other" } },
      ],
    },
  ];
  assert.throws(
    () => structuredOutput(messages),
    (error) => {
      assert.match(error.message, /permission denial/);
      assert.match(error.message, /Read, Bash/);
      assert.doesNotMatch(error.message, /secret|env|other/);
      return true;
    },
  );
  assert.deepEqual(structuredOutput([{ ...messages[0], permission_denials: [] }]), messages[0].structured_output);
});

test("long model text is cut, not refused", () => {
  const built = buildVerdict({
    ...ids,
    output: JSON.stringify({ verdict: "pass-notes", summary: "x".repeat(5000), notes: Array(40).fill("y".repeat(1200)) }),
  });
  assert.equal(built.summary.length, 4000);
  assert.equal(built.notes.length, 30);
  assert.equal(built.notes[0].length, 1000);
});

test("main writes the verdict file and the artifact name, and nothing on bad output", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-"));
  const spec = path.join(dir, "spec.json");
  writeFileSync(spec, JSON.stringify([ISSUE]));
  const execution = (name, output) => {
    const file = path.join(dir, `${name}.json`);
    writeFileSync(file, JSON.stringify([{ type: "system" }, { type: "result", subtype: "success", structured_output: output }]));
    return file;
  };
  // run-claude-cli's log: one JSON object per leg, each with its denial count.
  const log = (name, ...counts) => {
    const file = path.join(dir, `${name}.jsonl`);
    writeFileSync(file, counts.map((count, i) => JSON.stringify({ leg: i + 1, denials: { count } })).join("\n"));
    return file;
  };
  const env = {
    LOG_FILE: log("clean-log", 0),
    PR_NUMBER: "41",
    HEAD_SHA: HEAD,
    BASE_SHA: BASE,
    HEAD_REF: "feat/x",
    BODY_SHA256: BODY,
    SPEC_FILE: spec,
    GITHUB_RUN_ID: "9001",
    VERDICT_DIR: path.join(dir, "verdict"),
    GITHUB_OUTPUT: path.join(dir, "out"),
  };
  main({ ...env, EXECUTION_FILE: execution("fail", { verdict: "fail", summary: "wrong", notes: [] }) });
  const written = JSON.parse(readFileSync(path.join(env.VERDICT_DIR, "verdict.json"), "utf8"));
  assert.equal(written.verdict, "fail");
  assert.equal(written.summary, "wrong");
  assert.deepEqual(written.linked_issues, [ISSUE]);
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `name=pr-verify-41-${HEAD}-fail-i7\nverdict=fail\n`);

  const okFile = execution("ok", JSON.parse(ok));
  const unparsable = path.join(dir, "unparsable.json");
  writeFileSync(unparsable, "{not json");
  for (const [label, extra] of [
    ["bad output", { EXECUTION_FILE: execution("bad", {}) }],
    ["a credential in the summary", { EXECUTION_FILE: execution("key", { verdict: "pass", summary: KEY, notes: [] }) }],
    ["missing execution file", { EXECUTION_FILE: path.join(dir, "missing.json") }],
    ["unparsable execution file", { EXECUTION_FILE: unparsable }],
    ["unreadable spec", { EXECUTION_FILE: okFile, SPEC_FILE: path.join(dir, "missing.json") }],
    // A log with a denial on any leg.
    ["a denial on an earlier leg", { EXECUTION_FILE: okFile, LOG_FILE: log("denied-log", 1, 0) }],
    ["missing log file", { EXECUTION_FILE: okFile, LOG_FILE: path.join(dir, "missing.jsonl") }],
    ["no log file", { EXECUTION_FILE: okFile, LOG_FILE: "" }],
  ]) {
    const other = { ...env, VERDICT_DIR: path.join(dir, `none-${label}`), GITHUB_OUTPUT: path.join(dir, `out-${label}`), ...extra };
    assert.throws(() => main(other), undefined, label);
    assert.equal(existsSync(path.join(other.VERDICT_DIR, "verdict.json")), false, label);
    assert.equal(existsSync(other.GITHUB_OUTPUT), false, label);
  }
});

test("checkKeyLeg clears the subscription job only for a readable log with no denial", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-key-leg-"));
  const file = (name, text) => {
    const target = path.join(dir, name);
    writeFileSync(target, text);
    return target;
  };
  const clean = { LOG_FILE: file("clean.jsonl", JSON.stringify({ leg: 1, denials: { count: 0 } })), GITHUB_OUTPUT: path.join(dir, "out") };
  checkKeyLeg(clean);
  assert.equal(readFileSync(clean.GITHUB_OUTPUT, "utf8"), "clean=true\n");

  for (const [label, logFile] of [
    ["a denial", file("denied.jsonl", JSON.stringify({ leg: 1, denials: { count: 2 } }))],
    ["a malformed log", file("bad.jsonl", "{not json")],
    ["a missing log", path.join(dir, "missing.jsonl")],
    ["no log", ""],
  ]) {
    const env = { LOG_FILE: logFile, GITHUB_OUTPUT: path.join(dir, `out-${label}`) };
    assert.throws(() => checkKeyLeg(env), undefined, label);
    assert.equal(existsSync(env.GITHUB_OUTPUT), false, label);
  }
});
