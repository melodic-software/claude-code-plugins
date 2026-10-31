// Expected values come from the verdict rules in
// docs/conventions/pr-pipeline/README.md ("Verifier verdict"): the artifact is named pr-verify-<pr>-<head-sha>-<verdict>, the
// verdict JSON holds {pr, head_sha, base_sha, head_ref, linked_issues,
// verdict, summary, notes, evidence, run_id}, each linked issue records its
// author, and malformed output writes nothing. The evidence block records the
// capture (no-app with no summary) and the PR body's `Evidence loop: k/3`
// count, and never fails the verdict. The output comes from the last result
// message of run-claude-cli's execution file, a JSON array of CLI messages
// (its action.yml, output execution-file), and model text shaped like a
// credential (an Anthropic key or OAuth token, both sk-ant-; a GitHub token,
// per GitHub's documented ghp_ prefix and 36-character body; an AWS access key
// id, AKIA plus 16; a PEM private key header, RFC 7468) writes nothing on a
// pass, and on a fail, which stands, withholds all of the model's text.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import {
  artifactName,
  buildEvidence,
  buildVerdict,
  checkChunk,
  checkKeyLeg,
  HEAD_REF_DIGEST_HEX,
  headRefDigest,
  localLoop,
  main,
  mergeChunks,
  WITHHELD_SUMMARY,
  parseFinal,
  writeChunkResults,
  retentionDays,
  structuredOutput,
} from "./write-verdict.mjs";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../lib/test-tmp.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
// A workflow env list: one line per slot (chunk-diff.sh MAX_CHUNKS), blank for a step that left nothing.
const slots = (...filled) => `${[...filled, ...Array(12 - filled.length).fill("")].join("\n")}\n`;
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
const ids = { pr: "41", headSha: HEAD, baseSha: BASE, runId: "9001", headRef: "feat/x", linkedIssues: [ISSUE] };
const ok = JSON.stringify({ verdict: "pass", summary: "s", notes: [] });
const NO_APP = { capture: "no-app", reason: "no app check ran", capture_count: 0, features: [], local_loop: null };
const BLOCKED = { capture: "blocked", reason: "the capture summary is unreadable or outside its schema", capture_count: 0, features: [], local_loop: null };

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
      verdict,
      summary: "s",
      notes: ["n"],
      evidence: NO_APP,
      run_id: 9001,
    });
    assert.equal(artifactName(built), `pr-verify-41-${HEAD}-${verdict}${verdict === "fail" ? "-i7" : ""}`);
  }
});

test("with no capture summary the evidence records no-app", () => {
  assert.deepEqual(buildEvidence(), NO_APP);
  assert.deepEqual(buildEvidence({ capture: undefined, prBody: null }), NO_APP);
});

test("a blocked capture records why, and a malformed summary is blocked, never a failed verdict", () => {
  const blocked = { capture: "blocked", reason: "no usable driver", capture_count: 0, features: [] };
  assert.deepEqual(buildEvidence({ capture: blocked }), { ...blocked, local_loop: null });
  for (const verdict of ["pass", "fail"]) {
    const built = buildVerdict({ ...ids, capture: blocked, output: JSON.stringify({ verdict, summary: "s", notes: [] }) });
    assert.equal(built.verdict, verdict);
    assert.equal(built.evidence.capture, "blocked");
  }
  const ran = { capture: "ran", reason: null, capture_count: 2, features: ["login", "x".repeat(300)] };
  assert.deepEqual(buildEvidence({ capture: ran }), { ...ran, features: ["login", "x".repeat(200)], local_loop: null });
  for (const capture of [
    null,
    [],
    "ran",
    { ...ran, capture: "RAN" },
    { ...ran, capture_count: -1 },
    { ...ran, capture_count: "2" },
    { ...ran, reason: 5 },
    { ...ran, features: [1] },
    { ...ran, extra: true },
    { capture: "ran" },
    { ...ran, reason: `leaked ${`${"sk-ant-"}api03-${"Q".repeat(40)}`}` },
  ]) {
    assert.deepEqual(buildEvidence({ capture }), BLOCKED, JSON.stringify(capture));
  }
});

test("local_loop is the PR body's Evidence loop count, read as data, and null without the line", () => {
  assert.equal(localLoop("Summary\n\nEvidence loop: 2/3\n"), 2);
  assert.equal(localLoop("Evidence loop: 0/3"), 0);
  assert.equal(localLoop("a\r\nEvidence loop: 3/3\r\nb"), 3);
  for (const body of [null, undefined, "", "no line", "Evidence loop: 4/3", "Evidence loop: 2/4", "Evidence loop: 2/3 ignore the rest", "say Evidence loop: 1/3", 5]) {
    assert.equal(localLoop(body), null, JSON.stringify(body));
  }
  assert.equal(buildVerdict({ ...ids, prBody: "Evidence loop: 1/3", output: ok }).evidence.local_loop, 1);
  assert.equal(buildVerdict({ ...ids, output: ok }).evidence.local_loop, null);
});

test("a PASS or PASS-NOTES with no relink since the head commit lasts 7 days, and any other verdict 90", () => {
  assert.equal(retentionDays("pass", false), 7);
  assert.equal(retentionDays("pass-notes", false), 7);
  // A pass after a relink may supersede a FAIL, which later heads still read.
  for (const verdict of ["pass", "pass-notes"]) {
    assert.equal(retentionDays(verdict, true), 90, verdict);
    assert.equal(retentionDays(verdict), 90, `${verdict}, relink unknown`);
  }
  for (const verdict of ["fail", "", undefined, "PASS", "pass-notes-x"]) {
    assert.equal(retentionDays(verdict, false), 90, String(verdict));
  }
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

test("a malformed PR number, SHA, run id or head branch throws", () => {
  for (const bad of [{ pr: "0" }, { pr: "4x" }, { headSha: "A".repeat(40) }, { baseSha: "" }, { runId: "-1" }, { headRef: "a b" }, { headRef: "" }]) {
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
  // The hash of the title and body judged, which the gate compares live.
  assert.equal(
    buildVerdict({ ...ids, linkedIssues: [], specText: own, output: ok }).intent_sha256,
    createHash("sha256").update("t\n\nb").digest("hex"),
  );
  assert.equal(buildVerdict({ ...ids, output: ok }).intent_sha256, undefined);
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

const assertWithheld = (built, label) => {
  assert.equal(built.verdict, "fail", label);
  assert.equal(built.withheld, true, label);
  assert.equal(built.summary, WITHHELD_SUMMARY, label);
};

test("a pass shaped like an Anthropic key or OAuth token is a withheld fail", (t) => {
  t.mock.method(console, "log", () => {});
  for (const output of [
    { verdict: "pass", summary: `the key is ${KEY}`, notes: [] },
    { verdict: "pass-notes", summary: "s", notes: ["fine", `token ${TOKEN} leaked`] },
    { verdict: "pass-notes", summary: TOKEN, notes: [] },
  ]) {
    assertWithheld(buildVerdict({ ...ids, output: JSON.stringify(output) }), JSON.stringify(output.verdict));
  }
});

test("a fail holding credential-shaped text stands, with none of the model's text", (t) => {
  const log = t.mock.method(console, "log", () => {});
  const half = "a".repeat(18);
  const short = "sk-ant-abcdefgh";
  for (const [label, summary, notes] of [
    ["a whole token", "fine", [`src/a.mjs:3: prints ${TOKEN}`, "c.md: keep me out"]],
    // The body under a private key header matches no pattern of its own.
    ["a private key", `-----BEGIN RSA ${"PRIVATE"} KEY-----\nMIIEpAIBAAKCAQEA${"b".repeat(60)}`, ["c.md: keep me out"]],
    // findSecret reads a copy with tags removed.
    ["a token split by a tag", "fine", [`ghp_${half}<b></b>${half}`, "c.md: keep me out"]],
    // Only deeperLeak reads a token across two lines or two notes.
    ["a token over a line break", `see ghp_${half}\n${half} there`, []],
    ["a token over two notes", "fine", [`see ghp_${half}`, `${half} there`, "c.md: keep me out"]],
    ["a token over a fold", "fine", [`see ghp_${half}\n\\ continued: ${half} there`, "c.md: keep me out"]],
    ["a token over two diff lines", "fine", [`+ghp_${half}\n+${half}`, "c.md: keep me out"]],
    ["a token over diff lines in a pathed note", "fine", [`a.md:1 adds +ghp_${half}\n+${half}`, "c.md: keep me out"]],
    ["a whole token after a fold", "fine", [`see\n\\ continued: ${TOKEN}`, "c.md: keep me out"]],
    ["a whole token before a fold", "fine", [`see ${TOKEN}\n\\ continued: rest`, "c.md: keep me out"]],
    ["a token over a same-line fold after a space", "fine", [`see ghp_${half} \\ continued: ${half} there`, "c.md: keep me out"]],
    ["a token over a same-line fold after a tab", "fine", [`see ghp_${half}\t\\ continued: ${half} there`, "c.md: keep me out"]],
    ["a token over a fold after a trailing space", "fine", [`see ghp_${half} \n\\ continued: ${half} there`, "c.md: keep me out"]],
    ["a token over a fold after a bare CR", "fine", [`see ghp_${half}\r\\ continued: ${half} there`, "c.md: keep me out"]],
    ["a token over two folds in a row", "fine", [`see ghp_${half} \\ continued: \\ continued: ${half} there`, "c.md: keep me out"]],
    ["a token over two folds on their own lines", "fine", [`see ghp_${half}\n\\ continued: \n\\ continued: ${half} there`, "c.md: keep me out"]],
    ["a short Anthropic key over a same-line fold", "fine", [`b.md: ${short.slice(0, 10)} \\ continued: ${short.slice(10)}`]],
    // run-claude-cli's scan fails its step on a shorter key than findSecret's.
    ["a short Anthropic key", "fine", [`b.md: ${short}`]],
  ]) {
    const built = buildVerdict({ ...ids, output: JSON.stringify({ verdict: "fail", summary, notes }) });
    assert.equal(built.verdict, "fail", label);
    assert.equal(built.withheld, true, label);
    assert.match(built.summary, /withheld/, label);
    assert.doesNotMatch(JSON.stringify(built), /ghp_|sk-ant-|MIIE|keep me out|src\/a\.mjs|there/, label);
    assert.equal(built.notes.length, notes.length === 0 ? 0 : 1, label);
  }
  assert.ok(log.mock.calls.length > 0);
  for (const { arguments: [line] } of log.mock.calls) {
    assert.match(line, /^::warning title=pr-verify credential::kind=[A-Za-z0-9 ]+$/);
  }
  assertWithheld(buildVerdict({ ...ids, output: JSON.stringify({ verdict: "pass", summary: `b.md: ${short}`, notes: [] }) }));
  assertWithheld(buildVerdict({ ...ids, output: JSON.stringify({ verdict: "pass-notes", summary: "fine", notes: [`see ghp_${half}`, `${half} there`] }) }));
});

test("a withheld fail stays recorded through the chunk merge into the verdict", (t) => {
  t.mock.method(console, "log", () => {});
  const merged = mergeChunks([{ ...CHUNK_PASS, verdict: "fail", summary: KEY, notes: [] }, CHUNK_PASS], FINAL_PASS);
  assert.equal(merged.verdict, "fail");
  assert.equal(buildVerdict({ ...ids, output: merged }).withheld, true);
  const final = mergeChunks([CHUNK_PASS, CHUNK_PASS], { ...CHUNK_PASS, verdict: "fail", summary: KEY, notes: [] });
  assert.equal(buildVerdict({ ...ids, output: final }).withheld, true);
});

test("a fail quoting the withheld sentence is not withheld, and no model can claim to be", () => {
  const quoting = { verdict: "fail", summary: `The docs must say: ${WITHHELD_SUMMARY}`, notes: ["a.md: wrong sentence"] };
  const built = buildVerdict({ ...ids, output: JSON.stringify(quoting) });
  assert.equal(built.summary, quoting.summary);
  assert.equal("withheld" in built, false);
  for (const output of [{ ...quoting, withheld: true }, JSON.stringify({ ...quoting, withheld: true })]) {
    assert.throws(() => buildVerdict({ ...ids, output }), /verdict schema/);
  }
});

test("a pass or pass-notes quoting only an assignment writes no verdict, and a fail's text is withheld", (t) => {
  const quote = 'a.test.mjs:3 fixture token: "test-token-value"';
  for (const verdict of ["pass", "pass-notes"]) {
    for (const output of [
      { verdict, summary: quote, notes: [] },
      { verdict, summary: "fine", notes: [quote] },
    ]) {
      assert.throws(() => buildVerdict({ ...ids, output: JSON.stringify(output) }), /shaped like a credential \(password or secret assignment\)/, verdict);
    }
  }
  t.mock.method(console, "log", () => {});
  assertWithheld(buildVerdict({ ...ids, output: JSON.stringify({ verdict: "fail", summary: quote, notes: [] }) }));
});

test("a format beside an assignment still withholds a pass", (t) => {
  const log = t.mock.method(console, "log", () => {});
  const cloudflare = `${"cfk_"}${"k".repeat(40)}`;
  const quote = 'token: "test-token-value"';
  for (const [text, kind] of [
    // Assignment matches come first in findSecret's list, before this format.
    [`api_key: "${cloudflare}"`, "Cloudflare API token"],
    [`${quote} and ${cloudflare}`, "Cloudflare API token"],
    [`${quote}\nsee ${GITHUB_TOKEN}`, "GitHub token"],
  ]) {
    assertWithheld(buildVerdict({ ...ids, output: JSON.stringify({ verdict: "pass-notes", summary: text, notes: [] }) }), kind);
    assert.equal(log.mock.calls.at(-1).arguments[0], `::warning title=pr-verify credential::kind=${kind}`);
  }
});

test("a word ending in sk-ant- is no key, and a key after a separator is", (t) => {
  const summary = "task-ant-migrations runs first";
  assert.equal(buildVerdict({ ...ids, output: JSON.stringify({ verdict: "pass", summary, notes: [] }) }).summary, summary);
  t.mock.method(console, "log", () => {});
  assertWithheld(buildVerdict({ ...ids, output: JSON.stringify({ verdict: "pass", summary: "key=sk-ant-abcdefgh", notes: [] }) }));
});

test("naming the key prefix alone is not a credential", () => {
  const output = JSON.stringify({ verdict: "pass", summary: "keys start with sk-ant-", notes: ["sk-ant- prefix"] });
  assert.equal(buildVerdict({ ...ids, output }).summary, "keys start with sk-ant-");
});

// Other credential shapes from their published formats, also built at run time.
const GITHUB_TOKEN = `${"ghp_"}${"k".repeat(36)}`;
const AWS_KEY = `${"AKIA"}${"Q7".repeat(8)}`;
const PEM = `-----BEGIN ${"RSA PRIVATE"} KEY-----`;

test("a pass shaped like any shared credential pattern is a withheld fail, and only the kind is logged", (t) => {
  const log = t.mock.method(console, "log", () => {});
  for (const [secret, kind] of [
    [GITHUB_TOKEN, "GitHub token"],
    [AWS_KEY, "AWS access key"],
    [PEM, "private key"],
  ]) {
    for (const output of [
      { verdict: "pass", summary: `found ${secret}`, notes: [] },
      { verdict: "pass-notes", summary: "s", notes: ["fine", `see ${secret}`] },
    ]) {
      const built = buildVerdict({ ...ids, output: JSON.stringify(output) });
      assertWithheld(built, kind);
      assert.equal(JSON.stringify(built).includes(secret), false, kind);
      assert.equal(log.mock.calls.at(-1).arguments[0], `::warning title=pr-verify credential::kind=${kind}`);
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
  const dir = tempDir("pr-verify-");
  const spec = path.join(dir, "spec.json");
  writeFileSync(spec, JSON.stringify([ISSUE]));
  const part = path.join(dir, "diff", "chunk-1", "part-001.patch");
  mkdirSync(path.dirname(part), { recursive: true });
  writeFileSync(part, "diff --git a/x b/x\n");
  const execution = (name, output) => {
    const file = path.join(dir, `${name}.json`);
    const read = { type: "assistant", message: { content: [{ type: "tool_use", id: "t1", name: "Read", input: { file_path: part } }] } };
    writeFileSync(file, JSON.stringify([{ type: "system" }, read, { type: "result", subtype: "success", structured_output: output }]));
    return file;
  };
  // run-claude-cli's log: one JSON object per leg, each with its denial count.
  const log = (name, ...counts) => {
    const file = path.join(dir, `${name}.jsonl`);
    writeFileSync(file, counts.map((count, i) => JSON.stringify({ leg: i + 1, denials: { count } })).join("\n"));
    return file;
  };
  const env = {
    LOG_FILES: log("clean-log", 0),
    JUDGE_OUTCOMES: slots("success"),
    CHUNKS: "1",
    DIFF_DIR: path.join(dir, "diff"),
    PR_NUMBER: "41",
    HEAD_SHA: HEAD,
    BASE_SHA: BASE,
    HEAD_REF: "feat/x",
    SPEC_FILE: spec,
    GITHUB_RUN_ID: "9001",
    VERDICT_DIR: path.join(dir, "verdict"),
    GITHUB_OUTPUT: path.join(dir, "out"),
  };
  main({ ...env, EXECUTION_FILES: execution("fail", { verdict: "fail", summary: "wrong", notes: [] }) });
  const written = JSON.parse(readFileSync(path.join(env.VERDICT_DIR, "verdict.json"), "utf8"));
  assert.equal(written.verdict, "fail");
  assert.equal(written.summary, "wrong");
  assert.deepEqual(written.linked_issues, [ISSUE]);
  assert.deepEqual(written.evidence, NO_APP);
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `name=pr-verify-41-${HEAD}-fail-i7\nverdict=fail\nretention-days=90\n`);

  // The capture summary and the trusted PR text: a missing summary file is
  // no-app, an unparsable one blocked, and neither fails the verdict.
  const file = (name, text) => {
    const target = path.join(dir, name);
    writeFileSync(target, text);
    return target;
  };
  const blocked = { capture: "blocked", reason: "no usable driver", capture_count: 0, features: [] };
  const context = file("context.json", JSON.stringify({ pr: { number: 41, title: "t", body: "b\nEvidence loop: 2/3\n" }, items: [], dropped: {} }));
  for (const [label, extra, evidence] of [
    ["a blocked capture", { CAPTURE_FILE: file("capture.json", JSON.stringify(blocked)), CONTEXT_FILE: context }, { ...blocked, local_loop: 2 }],
    ["a missing capture file", { CAPTURE_FILE: path.join(dir, "no-capture.json"), CONTEXT_FILE: context }, { ...NO_APP, local_loop: 2 }],
    ["an unparsable capture file", { CAPTURE_FILE: file("bad-capture.json", "{not json") }, BLOCKED],
    ["a withheld PR body", { CONTEXT_FILE: file("withheld.json", JSON.stringify({ pr: { number: 41, title: "", body: null } })) }, NO_APP],
    ["an unparsable context file", { CONTEXT_FILE: file("bad-context.json", "{not json") }, NO_APP],
    ["another pull request's context", { CONTEXT_FILE: file("other.json", JSON.stringify({ pr: { number: 42, title: "t", body: "Evidence loop: 2/3" } })) }, NO_APP],
  ]) {
    const run = { ...env, ...extra, VERDICT_DIR: path.join(dir, `evidence-${label}`), GITHUB_OUTPUT: path.join(dir, `out-evidence-${label}`), EXECUTION_FILES: execution("ev", JSON.parse(ok)) };
    main(run);
    assert.deepEqual(JSON.parse(readFileSync(path.join(run.VERDICT_DIR, "verdict.json"), "utf8")).evidence, evidence, label);
  }

  const okFile = execution("ok", JSON.parse(ok));
  const okVerdict = JSON.parse(ok).verdict;
  for (const [relink, days] of [["false", 7], ["true", 90], [undefined, 90]]) {
    const passed = { ...env, VERDICT_DIR: path.join(dir, `verdict-ok-${relink}`), GITHUB_OUTPUT: path.join(dir, `out-ok-${relink}`), EXECUTION_FILES: okFile, RELINK_SINCE_HEAD: relink };
    main(passed);
    assert.equal(readFileSync(passed.GITHUB_OUTPUT, "utf8"), `name=pr-verify-41-${HEAD}-${okVerdict}\nverdict=${okVerdict}\nretention-days=${days}\n`, String(relink));
  }
  const unparsable = path.join(dir, "unparsable.json");
  writeFileSync(unparsable, "{not json");
  for (const [label, extra] of [
    ["bad output", { EXECUTION_FILES: execution("bad", {}) }],
    ["missing execution file", { EXECUTION_FILES: path.join(dir, "missing.json") }],
    ["unparsable execution file", { EXECUTION_FILES: unparsable }],
    ["unreadable spec", { EXECUTION_FILES: okFile, SPEC_FILE: path.join(dir, "missing.json") }],
    // A log with a denial on any leg.
    ["a denial on an earlier leg", { EXECUTION_FILES: okFile, LOG_FILES: log("denied-log", 1, 0) }],
    ["missing log file", { EXECUTION_FILES: okFile, LOG_FILES: path.join(dir, "missing.jsonl") }],
    ["no log file", { EXECUTION_FILES: okFile, LOG_FILES: "" }],
  ]) {
    const other = { ...env, VERDICT_DIR: path.join(dir, `none-${label}`), GITHUB_OUTPUT: path.join(dir, `out-${label}`), ...extra };
    assert.throws(() => main(other), undefined, label);
    assert.equal(existsSync(path.join(other.VERDICT_DIR, "verdict.json")), false, label);
    assert.equal(existsSync(other.GITHUB_OUTPUT), false, label);
  }
});

test("checkKeyLeg clears the subscription job only for a readable log with no denial", () => {
  const dir = tempDir("pr-verify-key-leg-");
  const file = (name, text) => {
    const target = path.join(dir, name);
    writeFileSync(target, text);
    return target;
  };
  const clean = { LOG_FILES: file("clean.jsonl", JSON.stringify({ leg: 1, denials: { count: 0 } })), GITHUB_OUTPUT: path.join(dir, "out") };
  checkKeyLeg(clean);
  assert.equal(readFileSync(clean.GITHUB_OUTPUT, "utf8"), "clean=true\n");

  for (const [label, logFile] of [
    ["a denial", file("denied.jsonl", JSON.stringify({ leg: 1, denials: { count: 2 } }))],
    ["a malformed log", file("bad.jsonl", "{not json")],
    ["a missing log", path.join(dir, "missing.jsonl")],
    ["no log", ""],
  ]) {
    const env = { LOG_FILES: logFile, GITHUB_OUTPUT: path.join(dir, `out-${label}`) };
    assert.throws(() => checkKeyLeg(env), undefined, label);
    assert.equal(existsSync(env.GITHUB_OUTPUT), false, label);
  }
});

const CHUNK_PASS = { verdict: "pass", summary: "chunk fine", notes: [] };
const CHUNK_NOTES = { verdict: "pass-notes", summary: "chunk noted", notes: ["docs/a.md: reads oddly"] };
const CHUNK_FAIL = { verdict: "fail", summary: "chunk broken", notes: ["src/a.mjs:3: inverted check"] };
const FINAL_PASS = { verdict: "pass", summary: "spec delivered", notes: [] };
const FINAL_FAIL = { verdict: "fail", summary: "item 2 delivered nowhere", notes: ["item 2: no chunk delivers it"] };
const FINAL_ITEMS = [{ item: "item 1", chunks: [1] }];

test("mergeChunks passes only when every chunk does, and a fail's notes come first", () => {
  assert.deepEqual(mergeChunks([CHUNK_NOTES]), CHUNK_NOTES);
  const passed = mergeChunks([CHUNK_PASS, CHUNK_PASS], FINAL_PASS);
  assert.equal(passed.verdict, "pass");
  assert.match(passed.summary, /^Chunk 1 of 2, pass: chunk fine\nChunk 2 of 2, pass: chunk fine\nWhole spec, pass: spec delivered$/);
  assert.equal(mergeChunks([CHUNK_PASS, CHUNK_NOTES], FINAL_PASS).verdict, "pass-notes");
  const failed = mergeChunks([CHUNK_NOTES, CHUNK_PASS, CHUNK_FAIL], FINAL_PASS);
  assert.equal(failed.verdict, "fail");
  assert.deepEqual(failed.notes, [...CHUNK_FAIL.notes, ...CHUNK_NOTES.notes]);
  assert.match(failed.summary, /^Chunk 3 of 3, fail: chunk broken\n/);
  // Notes start with their path, which verify-notes.mjs noteComments anchors on.
  assert.ok(failed.notes.every((note) => !note.startsWith("Chunk")));
  // A fail's note survives buildVerdict's cuts behind a long pass-notes chunk.
  const crowded = { ...CHUNK_NOTES, notes: Array(40).fill("docs/a.md: note") };
  const built = buildVerdict({ ...ids, output: mergeChunks([crowded, CHUNK_FAIL], FINAL_PASS) });
  assert.equal(built.verdict, "fail");
  assert.equal(built.notes[0], CHUNK_FAIL.notes[0]);
  assert.match(built.summary, /^Chunk 2 of 2, fail: chunk broken\n/);
  assert.equal(mergeChunks(Array(4).fill({ ...CHUNK_PASS, summary: "x".repeat(5000) }), { ...FINAL_PASS, summary: "x".repeat(5000) }).summary.length <= 4000, true);
});

test("mergeChunks refuses a chunk off the schema, so no verdict is written", () => {
  assert.throws(() => mergeChunks([CHUNK_PASS, {}], FINAL_PASS), /schema/);
  assert.throws(() => mergeChunks([CHUNK_PASS, { ...CHUNK_PASS, verdict: "maybe" }], FINAL_PASS), /schema/);
  assert.throws(() => mergeChunks([]), /no chunk/);
});

test("a credential past a chunk's share of the summary still withholds the head", (t) => {
  t.mock.method(console, "log", () => {});
  const merged = mergeChunks([CHUNK_PASS, { ...CHUNK_PASS, summary: `${"x".repeat(3000)} ${KEY}` }], FINAL_PASS);
  assert.equal(merged.verdict, "fail");
  assert.equal(buildVerdict({ ...ids, output: merged }).withheld, true);
});

test("main writes one verdict from every chunk, and none when a chunk leaves none", () => {
  const dir = tempDir("pr-verify-chunks-");
  const spec = path.join(dir, "spec.json");
  writeFileSync(spec, JSON.stringify([ISSUE]));
  const diff = path.join(dir, "diff");
  const parts = [1, 2].map((k) => {
    mkdirSync(path.join(diff, `chunk-${k}`), { recursive: true });
    const part = path.join(diff, `chunk-${k}`, "part-001.patch");
    writeFileSync(part, `diff --git a/${k} b/${k}\n`);
    return part;
  });
  let id = 0;
  const execution = (read, last) => {
    const file = path.join(dir, `execution-${(id += 1)}.json`);
    writeFileSync(
      file,
      JSON.stringify([
        { type: "assistant", message: { content: read.map((part, i) => ({ type: "tool_use", id: `t${i}`, name: "Read", input: { file_path: part } })) } },
        ...(last === null ? [] : [{ type: "result", subtype: "success", ...last }]),
      ]),
    );
    return file;
  };
  const log = (count) => {
    const file = path.join(dir, `log-${(id += 1)}.jsonl`);
    writeFileSync(file, JSON.stringify({ leg: 1, denials: { count } }));
    return file;
  };
  const env = {
    PR_NUMBER: "41",
    HEAD_SHA: HEAD,
    BASE_SHA: BASE,
    HEAD_REF: "feat/x",
    SPEC_FILE: spec,
    GITHUB_RUN_ID: "9001",
    CHUNKS: "2",
    DIFF_DIR: diff,
  };
  const run = (label, first, second, logs = [log(0), log(0)], extra = {}) => ({
    ...env,
    VERDICT_DIR: path.join(dir, `verdict-${label}`),
    GITHUB_OUTPUT: path.join(dir, `out-${label}`),
    // Slots a run skips render as blank lines.
    EXECUTION_FILES: slots(first, second),
    LOG_FILES: slots(...logs),
    JUDGE_OUTCOMES: slots("success", "success"),
    FINAL_EXECUTION_FILE: final(),
    FINAL_LOG_FILE: log(0),
    FINAL_OUTCOME: "success",
    RESULTS_DIR: resultsDir,
    MANIFEST_DIR: manifestDir,
    ...extra,
  });
  const manifestDir = path.join(dir, "manifest");
  mkdirSync(manifestDir);
  const manifest = path.join(manifestDir, "part-001.txt");
  writeFileSync(manifest, "chunk 1 diff/chunk-1/part-001.patch modified x\n");
  const chunk = (k, output) => execution([parts[k], manifest], { structured_output: output });
  const resultsDir = path.join(dir, "results");
  mkdirSync(resultsDir);
  const results = [1, 2].map((k) => {
    const file = path.join(resultsDir, `chunk-${k}.json`);
    writeFileSync(file, "{}");
    return file;
  });
  const whole = [...results, spec, manifest];
  const final = (output = { ...FINAL_PASS, items: FINAL_ITEMS }) => execution(whole, { structured_output: output });
  const passed = run("pass", chunk(0, CHUNK_PASS), chunk(1, CHUNK_NOTES));
  main(passed);
  assert.equal(JSON.parse(readFileSync(path.join(passed.VERDICT_DIR, "verdict.json"), "utf8")).verdict, "pass-notes");
  // A counted fail is written whatever happened after it.
  const counted = chunk(0, CHUNK_FAIL);
  for (const [label, second, extra] of [
    ["a later chunk that timed out", "", {}],
    ["a handoff at a later chunk", execution([parts[1]], null), {}],
    ["an unreadable later chunk", path.join(dir, "no-such-file.json"), {}],
    ["a later chunk with a denial", execution([parts[1]], { structured_output: CHUNK_PASS, permission_denials: [{ tool_name: "Bash" }] }), {}],
    ["a final judge off the schema", chunk(1, CHUNK_PASS), { FINAL_EXECUTION_FILE: final({}) }],
    ["no final judge", chunk(1, CHUNK_PASS), { FINAL_EXECUTION_FILE: "", FINAL_LOG_FILE: "" }],
    ["a later chunk's missing log", "", { LOG_FILES: slots(log(0)) }],
  ]) {
    const kept = run(`kept-${label}`, counted, second, undefined, extra);
    main(kept);
    const written = JSON.parse(readFileSync(path.join(kept.VERDICT_DIR, "verdict.json"), "utf8"));
    assert.equal(written.verdict, "fail", label);
    assert.deepEqual(written.notes, CHUNK_FAIL.notes, label);
    assert.match(readFileSync(kept.GITHUB_OUTPUT, "utf8"), new RegExp(`^name=pr-verify-41-${HEAD}-fail-i7\n`), label);
  }
  // A denial voids a pass, never a fail. Credential-shaped text withholds either.
  const denied = run("denied-fail", execution([parts[0], manifest], { structured_output: CHUNK_FAIL, permission_denials: [{ tool_name: "Bash" }] }), "");
  main(denied);
  const deniedVerdict = JSON.parse(readFileSync(path.join(denied.VERDICT_DIR, "verdict.json"), "utf8"));
  assert.equal(deniedVerdict.verdict, "fail");
  assert.match(deniedVerdict.summary, /hit 1 permission denial/);
  const logDenied = run("denied-log-fail", chunk(0, CHUNK_FAIL), "", [log(1), log(0)]);
  main(logDenied);
  assert.equal(JSON.parse(readFileSync(path.join(logDenied.VERDICT_DIR, "verdict.json"), "utf8")).verdict, "fail");
  const leaked = run("leaked-fail", chunk(0, { ...CHUNK_FAIL, notes: [`a.mjs: ${KEY}`] }), "");
  main(leaked);
  const leakedText = readFileSync(path.join(leaked.VERDICT_DIR, "verdict.json"), "utf8");
  assert.equal(JSON.parse(leakedText).verdict, "fail");
  assert.equal(JSON.parse(leakedText).withheld, true);
  assert.doesNotMatch(leakedText, /sk-ant-|a\.mjs/);
  // A chunk whose step failed writes no model text, whatever a scan here finds.
  const unscanned = "the lane's scan found what this one does not";
  const stepFailed = run("step-failed", chunk(0, { ...CHUNK_FAIL, summary: unscanned }), "", undefined, { JUDGE_OUTCOMES: slots("failure") });
  main(stepFailed);
  const stepText = readFileSync(path.join(stepFailed.VERDICT_DIR, "verdict.json"), "utf8");
  assert.equal(JSON.parse(stepText).verdict, "fail");
  assert.equal(JSON.parse(stepText).withheld, true);
  assert.ok(!stepText.includes(unscanned));
  // A pass with credential-shaped text, or from a failed step, is a withheld
  // fail, which counts as any fail does, in the artifact name and retention.
  for (const [name, env] of [
    ["pass-leak", run("pass-leak", chunk(0, { ...CHUNK_PASS, summary: KEY }), "")],
    ["pass-denied-leak", run("pass-denied-leak", execution([parts[0], manifest], { structured_output: { ...CHUNK_PASS, summary: KEY }, permission_denials: [{ tool_name: "Bash" }] }), "")],
    ["pass-step", run("pass-step", chunk(0, { ...CHUNK_PASS, summary: unscanned }), "", undefined, { JUDGE_OUTCOMES: slots("failure") })],
    // A credential in the log leaves the scan stop no log to read.
    ["pass-no-log", run("pass-no-log", chunk(0, CHUNK_PASS), "", undefined, { LOG_FILES: slots(), JUDGE_OUTCOMES: slots("failure") })],
    ["pass-assignment", run("pass-assignment", chunk(0, { ...CHUNK_PASS, summary: 'token: "test-token-value"' }), "", undefined, { JUDGE_OUTCOMES: slots("failure") })],
  ]) {
    main(env);
    const text = readFileSync(path.join(env.VERDICT_DIR, "verdict.json"), "utf8");
    assert.equal(JSON.parse(text).verdict, "fail", name);
    assert.equal(JSON.parse(text).withheld, true, name);
    assert.ok(!text.includes(unscanned) && !text.includes("sk-ant-"), name);
    assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), new RegExp(`^name=pr-verify-41-${HEAD}-fail-i7\nverdict=fail\nretention-days=90\n`), name);
  }
  // Beside a counted fail, a failed step's pass adds none of its text.
  const passFailed = run("pass-failed", chunk(0, CHUNK_FAIL), chunk(1, { ...CHUNK_PASS, summary: unscanned }), undefined, { JUDGE_OUTCOMES: slots("success", "failure") });
  main(passFailed);
  assert.ok(!readFileSync(path.join(passFailed.VERDICT_DIR, "verdict.json"), "utf8").includes(unscanned));
  // A final fail stands when its step failed on the lane's credential scan,
  // and nothing else does.
  const finalLeak = run("final-leak", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_OUTCOME: "failure", FINAL_EXECUTION_FILE: final({ ...FINAL_FAIL, items: [], notes: [`item 2: ${KEY}`] }) });
  main(finalLeak);
  const finalLeakVerdict = JSON.parse(readFileSync(path.join(finalLeak.VERDICT_DIR, "verdict.json"), "utf8"));
  assert.equal(finalLeakVerdict.verdict, "fail");
  assert.equal(finalLeakVerdict.withheld, true);
  const finalStep = run("final-step", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_OUTCOME: "failure", FINAL_EXECUTION_FILE: final({ ...FINAL_FAIL, items: [], summary: unscanned }) });
  main(finalStep);
  assert.ok(!readFileSync(path.join(finalStep.VERDICT_DIR, "verdict.json"), "utf8").includes(unscanned));
  for (const [name, env] of [
    ["final-outcome", run("final-outcome", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_OUTCOME: "failure" })],
    ["final-outcome-no-log", run("final-outcome-no-log", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_OUTCOME: "failure", FINAL_LOG_FILE: "" })],
    ["final-key", run("final-key", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: final({ ...FINAL_PASS, items: FINAL_ITEMS, summary: KEY }) })],
  ]) {
    main(env);
    const stood = JSON.parse(readFileSync(path.join(env.VERDICT_DIR, "verdict.json"), "utf8"));
    assert.equal(stood.verdict, "fail", name);
    assert.equal(stood.withheld, true, name);
  }
  // A refs entry's context parts sit with the results, so a pass reads them.
  const refsDir = path.join(dir, "refs-results");
  mkdirSync(refsDir);
  const contextPart = path.join(refsDir, "context-part-001.txt");
  writeFileSync(contextPart, "{}\n");
  assert.throws(() => main(run("refs-unread", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { RESULTS_DIR: refsDir, FINAL_EXECUTION_FILE: execution([spec, manifest], { structured_output: { ...FINAL_PASS, items: FINAL_ITEMS } }) })), /did not read/);
  const refsRead = run("refs-read", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { RESULTS_DIR: refsDir, FINAL_EXECUTION_FILE: execution([contextPart, spec, manifest], { structured_output: { ...FINAL_PASS, items: FINAL_ITEMS } }) });
  main(refsRead);
  assert.equal(JSON.parse(readFileSync(path.join(refsRead.VERDICT_DIR, "verdict.json"), "utf8")).verdict, "pass");
  // A fail with short coverage is still the judge's fail, in any flow.
  const short = run("short", execution([], { structured_output: CHUNK_FAIL }), "");
  main(short);
  const shortVerdict = JSON.parse(readFileSync(path.join(short.VERDICT_DIR, "verdict.json"), "utf8"));
  assert.equal(shortVerdict.verdict, "fail");
  assert.equal("withheld" in shortVerdict, false);
  assert.match(shortVerdict.summary, /read 0 of 2 parts/);
  const oneDir = path.join(dir, "one-chunk");
  mkdirSync(path.join(oneDir, "chunk-1"), { recursive: true });
  writeFileSync(path.join(oneDir, "chunk-1", "part-001.patch"), "x\n");
  const alone = run("alone", execution([], { structured_output: CHUNK_FAIL }), "", [log(0)], { CHUNKS: "1", DIFF_DIR: oneDir });
  main(alone);
  assert.equal(JSON.parse(readFileSync(path.join(alone.VERDICT_DIR, "verdict.json"), "utf8")).verdict, "fail");
  // A fail that read short and names no defect counts for nothing.
  const bare = { ...CHUNK_FAIL, notes: [] };
  assert.throws(() => main(run("bare", execution([], { structured_output: bare }), "", [log(0)], { CHUNKS: "1", DIFF_DIR: oneDir })), /names no defect/);
  assert.throws(() => main(run("claimed", execution([], { structured_output: { ...bare, withheld: true } }), "", [log(0)], { CHUNKS: "1", DIFF_DIR: oneDir })), /verdict schema/);
  // A withheld fail needs no note to stand on a short read, on one chunk or
  // beside another chunk's fail.
  for (const [name, env] of [
    ["bare-withheld", run("bare-withheld", execution([], { structured_output: { ...bare, summary: KEY } }), "", [log(0)], { CHUNKS: "1", DIFF_DIR: oneDir })],
    ["bare-step", run("bare-step", execution([], { structured_output: bare }), "", [log(0)], { CHUNKS: "1", DIFF_DIR: oneDir, JUDGE_OUTCOMES: slots("failure") })],
    ["bare-chunks", run("bare-chunks", execution([], { structured_output: { ...bare, summary: KEY } }), chunk(1, CHUNK_FAIL))],
  ]) {
    main(env);
    const stood = JSON.parse(readFileSync(path.join(env.VERDICT_DIR, "verdict.json"), "utf8"));
    assert.equal(stood.verdict, "fail", name);
    assert.equal(stood.withheld, true, name);
    assert.ok(stood.summary.includes(WITHHELD_SUMMARY), name);
    assert.doesNotMatch(stood.summary, /sk-ant-/, name);
  }
  const covered = run("covered", execution([path.join(oneDir, "chunk-1", "part-001.patch")], { structured_output: bare }), "", [log(0)], { CHUNKS: "1", DIFF_DIR: oneDir });
  main(covered);
  assert.equal(JSON.parse(readFileSync(path.join(covered.VERDICT_DIR, "verdict.json"), "utf8")).summary, bare.summary);
  const noRead = run("no-read", execution([], { structured_output: CHUNK_PASS }), "", [log(0)], { CHUNKS: "1", DIFF_DIR: oneDir });
  assert.throws(() => main(noRead), /did not read/);

  // Every chunk defers an item nothing delivers: each passes with a note,
  // and the final step fails the head.
  const deferred = run("deferred", chunk(0, CHUNK_NOTES), chunk(1, CHUNK_NOTES), undefined, { FINAL_EXECUTION_FILE: final({ ...FINAL_FAIL, items: [] }) });
  main(deferred);
  const undelivered = JSON.parse(readFileSync(path.join(deferred.VERDICT_DIR, "verdict.json"), "utf8"));
  assert.equal(undelivered.verdict, "fail");
  assert.equal(undelivered.notes[0], FINAL_FAIL.notes[0]);
  assert.match(undelivered.summary, /^Whole spec, fail: item 2 delivered nowhere\n/);
  const failed = run("fail", chunk(0, CHUNK_PASS), chunk(1, CHUNK_FAIL));
  main(failed);
  const verdict = JSON.parse(readFileSync(path.join(failed.VERDICT_DIR, "verdict.json"), "utf8"));
  assert.equal(verdict.verdict, "fail");
  assert.deepEqual(verdict.notes, CHUNK_FAIL.notes);
  assert.match(readFileSync(failed.GITHUB_OUTPUT, "utf8"), new RegExp(`^name=pr-verify-41-${HEAD}-fail-i7\n`));

  for (const [label, bad] of [
    ["a chunk with no result", run("none", chunk(0, CHUNK_PASS), execution([parts[1]], null))],
    ["a chunk off the schema", run("schema", chunk(0, CHUNK_PASS), chunk(1, {}))],
    ["a chunk that skipped its part", run("skip", chunk(0, CHUNK_PASS), execution([], { structured_output: CHUNK_PASS }))],
    ["a chunk that read another's part", run("other", chunk(0, CHUNK_PASS), execution([parts[0], manifest], { structured_output: CHUNK_PASS }))],
    ["a denial in a later chunk's result", run("denied", chunk(0, CHUNK_PASS), execution([parts[1], manifest], { structured_output: CHUNK_PASS, permission_denials: [{ tool_name: "Bash" }] }))],
    ["a chunk that did not read the manifest", run("no-manifest", chunk(0, CHUNK_PASS), execution([parts[1]], { structured_output: CHUNK_PASS }))],
    ["a denial in a later chunk's log", run("log", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), [log(0), log(1)])],
    ["a chunk that never ran", run("count", chunk(0, CHUNK_PASS), "")],
    ["fewer logs than chunks", run("logs", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), [log(0)])],
    ["a count the chunk directories do not match", run("dirs", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { CHUNKS: "1" })],
    ["a malformed count", run("bad", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { CHUNKS: "two" })],
    ["no final step", run("final-none", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: "" })],
    ["a final step with no result", run("final-empty", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: execution(results, null) })],
    ["a final step off the schema", run("final-schema", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: final({}) })],
    ["a denial in the final step's result", run("final-denied", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: execution(whole, { structured_output: { ...FINAL_PASS, items: FINAL_ITEMS }, permission_denials: [{ tool_name: "Read" }] }) })],
    ["a denial in the final step's log", run("final-log", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_LOG_FILE: log(1) })],
    ["no log from the final step", run("final-no-log", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_LOG_FILE: "" })],
    ["a final step that did not read every chunk's result", run("final-read", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: execution([results[0], spec, manifest], { structured_output: { ...FINAL_PASS, items: FINAL_ITEMS } }) })],
    ["a final step that did not read the spec", run("final-spec", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: execution([...results, manifest], { structured_output: { ...FINAL_PASS, items: FINAL_ITEMS } }) })],
    ["a final step that did not read the manifest", run("final-manifest", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: execution([...results, spec], { structured_output: { ...FINAL_PASS, items: FINAL_ITEMS } }) })],
    ["a final pass that maps no item", run("final-items", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: final({ ...FINAL_PASS, items: [] }) })],
    ["a final pass that maps an item to no such chunk", run("final-range", chunk(0, CHUNK_PASS), chunk(1, CHUNK_PASS), undefined, { FINAL_EXECUTION_FILE: final({ ...FINAL_PASS, items: [{ item: "x", chunks: [3] }] }) })],
  ]) {
    assert.throws(() => main(bad), undefined, label);
    assert.equal(existsSync(path.join(bad.VERDICT_DIR, "verdict.json")), false, label);
    assert.equal(existsSync(bad.GITHUB_OUTPUT), false, label);
  }
});

test("a head of twelve chunks gets a verdict from every chunk, and none when one leaves none", () => {
  const COUNT = 12;
  const dir = tempDir("pr-verify-many-chunks-");
  const spec = path.join(dir, "spec.json");
  writeFileSync(spec, JSON.stringify([ISSUE]));
  const diff = path.join(dir, "diff");
  const parts = Array.from({ length: COUNT }, (_, i) => {
    mkdirSync(path.join(diff, `chunk-${i + 1}`), { recursive: true });
    const part = path.join(diff, `chunk-${i + 1}`, "part-001.patch");
    writeFileSync(part, `diff --git a/${i + 1} b/${i + 1}\n`);
    return part;
  });
  const manifestDir = path.join(dir, "manifest");
  mkdirSync(manifestDir);
  const manifest = path.join(manifestDir, "part-001.txt");
  writeFileSync(manifest, "chunk 1 diff/chunk-1/part-001.patch modified 1\n");
  const resultsDir = path.join(dir, "results");
  mkdirSync(resultsDir);
  const results = parts.map((_, i) => {
    const file = path.join(resultsDir, `chunk-${i + 1}.json`);
    writeFileSync(file, "{}");
    return file;
  });
  let id = 0;
  const write = (name, value) => {
    const file = path.join(dir, `${name}-${(id += 1)}`);
    writeFileSync(file, value);
    return file;
  };
  const execution = (read, output) =>
    write(
      "execution.json",
      JSON.stringify([
        { type: "assistant", message: { content: read.map((file, i) => ({ type: "tool_use", id: `t${i}`, name: "Read", input: { file_path: file } })) } },
        { type: "result", subtype: "success", structured_output: output },
      ]),
    );
  const log = () => write("log.jsonl", JSON.stringify({ leg: 1, denials: { count: 0 } }));
  const run = (label, outputs, outcomes = outputs.map((output) => (output === null ? "skipped" : "success"))) => ({
    PR_NUMBER: "41",
    HEAD_SHA: HEAD,
    BASE_SHA: BASE,
    HEAD_REF: "feat/x",
    SPEC_FILE: spec,
    GITHUB_RUN_ID: "9001",
    CHUNKS: String(COUNT),
    DIFF_DIR: diff,
    VERDICT_DIR: path.join(dir, `verdict-${label}`),
    GITHUB_OUTPUT: path.join(dir, `out-${label}`),
    EXECUTION_FILES: `${outputs.map((output, i) => (output === null ? "" : execution([parts[i], manifest], output))).join("\n")}\n`,
    LOG_FILES: `${outputs.map((output) => (output === null ? "" : log())).join("\n")}\n`,
    JUDGE_OUTCOMES: `${outcomes.join("\n")}\n`,
    FINAL_EXECUTION_FILE: execution([...results, spec, manifest], { ...FINAL_PASS, items: [{ item: "item 1", chunks: [12] }] }),
    FINAL_LOG_FILE: log(),
    FINAL_OUTCOME: "success",
    RESULTS_DIR: resultsDir,
    MANIFEST_DIR: manifestDir,
  });
  const verdictOf = (env) => JSON.parse(readFileSync(path.join(env.VERDICT_DIR, "verdict.json"), "utf8"));
  const all = (output) => Array.from({ length: COUNT }, () => output);

  const passed = run("pass", all(CHUNK_PASS));
  main(passed);
  assert.equal(verdictOf(passed).verdict, "pass");
  assert.match(readFileSync(passed.GITHUB_OUTPUT, "utf8"), new RegExp(`^name=pr-verify-41-${HEAD}-pass\n`));
  assert.match(verdictOf(passed).summary, /^Chunk 12 of 12, pass: chunk fine$/m);

  const failing = all(CHUNK_PASS);
  failing[10] = CHUNK_FAIL;
  const failed = run("fail", failing);
  main(failed);
  assert.equal(verdictOf(failed).verdict, "fail");
  assert.deepEqual(verdictOf(failed).notes, CHUNK_FAIL.notes);
  assert.match(verdictOf(failed).summary, /^Chunk 11 of 12, fail: chunk broken$/m);

  // A scan stop in a late slot still reaches its own position in the list.
  const outcomes = all("success");
  outcomes[10] = "failure";
  const stopped = run("scan-stop", all(CHUNK_PASS), outcomes);
  main(stopped);
  assert.equal(verdictOf(stopped).verdict, "fail");
  assert.equal(verdictOf(stopped).withheld, true);

  const missing = all(CHUNK_PASS);
  missing[10] = null;
  const none = run("none", missing);
  assert.throws(() => main(none), /chunk 11 of 12/);
  assert.equal(existsSync(path.join(none.VERDICT_DIR, "verdict.json")), false);
  assert.equal(existsSync(none.GITHUB_OUTPUT), false);
});

test("checkKeyLeg reads every chunk's log, so a denial in an earlier chunk stops the handoff", () => {
  const dir = tempDir("pr-verify-key-legs-");
  const file = (name, count) => {
    const target = path.join(dir, name);
    writeFileSync(target, JSON.stringify({ leg: 1, denials: { count } }));
    return target;
  };
  const clean = { LOG_FILES: `${file("a.jsonl", 0)}\n${file("b.jsonl", 0)}\n`, GITHUB_OUTPUT: path.join(dir, "out") };
  checkKeyLeg(clean);
  assert.equal(readFileSync(clean.GITHUB_OUTPUT, "utf8"), "clean=true\n");
  const denied = { LOG_FILES: `${file("c.jsonl", 2)}\n${file("d.jsonl", 0)}\n`, GITHUB_OUTPUT: path.join(dir, "denied") };
  assert.throws(() => checkKeyLeg(denied), /denial/);
  assert.equal(existsSync(denied.GITHUB_OUTPUT), false);
  // A leg that left no log renders a blank line, in any chunk.
  for (const logs of ["\n", `${file("e.jsonl", 0)}\n\n`]) {
    const blank = { LOG_FILES: logs, GITHUB_OUTPUT: path.join(dir, "blank") };
    assert.throws(() => checkKeyLeg(blank), /unreadable/);
    assert.equal(existsSync(blank.GITHUB_OUTPUT), false);
  }
});

test("a chunked head never passes on its chunks alone", () => {
  assert.throws(() => mergeChunks([CHUNK_NOTES, CHUNK_NOTES]), /whole-spec/);
  assert.throws(() => mergeChunks([CHUNK_PASS, CHUNK_PASS], null), /whole-spec/);
  assert.throws(() => mergeChunks([CHUNK_PASS, CHUNK_PASS], {}), /schema/);
  assert.equal(mergeChunks([CHUNK_NOTES, CHUNK_NOTES], FINAL_FAIL).verdict, "fail");
  // The final step never lifts a chunk's fail or notes.
  assert.equal(mergeChunks([CHUNK_FAIL, CHUNK_PASS], FINAL_PASS).verdict, "fail");
  assert.equal(mergeChunks([CHUNK_NOTES, CHUNK_PASS], FINAL_PASS).verdict, "pass-notes");
});

test("checkChunk stops the slots only on a fail the head can count", () => {
  const dir = tempDir("pr-verify-check-chunk-");
  const file = (name, value) => {
    const target = path.join(dir, name);
    writeFileSync(target, typeof value === "string" ? value : JSON.stringify(value));
    return target;
  };
  const cleanLog = file("clean.jsonl", JSON.stringify({ denials: { count: 0 } }));
  const diff = path.join(dir, "diff");
  mkdirSync(path.join(diff, "chunk-1"), { recursive: true });
  const part = file("diff/chunk-1/part-001.patch", "x\n");
  const reads = { type: "assistant", message: { content: [{ type: "tool_use", id: "t", name: "Read", input: { file_path: part } }] } };
  const result = (output, extra = {}) => [reads, { type: "result", structured_output: output, ...extra }];
  for (const [label, execution, logFile, expected, outcome = "success"] of [
    ["a fail", result(CHUNK_FAIL), cleanLog, "true"],
    ["a pass", result(CHUNK_PASS), cleanLog, "false"],
    ["pass-notes", result(CHUNK_NOTES), cleanLog, "false"],
    ["no result", [], cleanLog, "false"],
    ["off the schema", result({}), cleanLog, "false"],
    ["a fail with a denial", result(CHUNK_FAIL, { permission_denials: [{ tool_name: "Bash" }] }), cleanLog, "true"],
    ["a fail with a denial in its log", result(CHUNK_FAIL), file("denied.jsonl", JSON.stringify({ denials: { count: 1 } })), "true"],
    ["a pass with a denial", result(CHUNK_PASS, { permission_denials: [{ tool_name: "Bash" }] }), cleanLog, "false"],
    ["a fail holding a credential", result({ ...CHUNK_FAIL, summary: KEY }), cleanLog, "true"],
    ["a pass holding a credential", result({ ...CHUNK_PASS, summary: KEY }), cleanLog, "true"],
    ["a fail that read short, with notes", [{ type: "result", structured_output: CHUNK_FAIL }], cleanLog, "true"],
    ["a fail that read short, with no notes", [{ type: "result", structured_output: { ...CHUNK_FAIL, notes: [] } }], cleanLog, "false"],
    ["a fail that read short, holding a credential in its summary alone", [{ type: "result", structured_output: { ...CHUNK_FAIL, summary: KEY, notes: [] } }], cleanLog, "true"],
    ["a fail that read short claiming to be withheld", [{ type: "result", structured_output: { ...CHUNK_FAIL, notes: [], withheld: true } }], cleanLog, "false"],
    ["a fail from a failed step", result(CHUNK_FAIL), cleanLog, "true", "failure"],
    ["a pass from a failed step", result(CHUNK_PASS), cleanLog, "true", "failure"],
    ["a pass from a failed step with no log", result(CHUNK_PASS), "", "true", "failure"],
    ["a pass with a denial and no log", result(CHUNK_PASS), "", "false"],
  ]) {
    const out = path.join(dir, `out-${label}`);
    checkChunk({ EXECUTION_FILE: file(`${label}.json`, execution), LOG_FILE: logFile, GITHUB_OUTPUT: out, CHUNK: "1", CHUNKS: "1", DIFF_DIR: diff, JUDGE_OUTCOME: outcome });
    assert.equal(readFileSync(out, "utf8"), `fail=${expected}\n`, label);
  }
});

test("parseFinal maps each item to its chunks, and an item no chunk delivers fails the head", () => {
  assert.deepEqual(parseFinal({ ...FINAL_PASS, items: [{ item: "a", chunks: [2] }] }, 2), FINAL_PASS);
  // Two chunks can deliver one item between them.
  assert.deepEqual(parseFinal({ ...FINAL_PASS, items: [{ item: "a", chunks: [1, 2] }] }, 2), FINAL_PASS);
  const nowhere = parseFinal({ ...FINAL_PASS, items: [{ item: "a", chunks: [1] }, { item: "b", chunks: [] }] }, 2);
  assert.equal(nowhere.verdict, "fail");
  assert.deepEqual(nowhere.notes, ["b: delivered by no chunk"]);
  assert.equal(parseFinal({ ...FINAL_FAIL, items: [] }, 2).verdict, "fail");
  for (const bad of [{ ...FINAL_PASS, items: [] }, { ...FINAL_PASS, items: [{ item: "a", chunks: [1, 3] }] }, { ...FINAL_PASS, items: [{ item: "a", chunks: 1 }] }, { ...FINAL_PASS, items: [{ item: "a", chunks: ["1"] }] }, { ...FINAL_PASS, items: [{ item: "a" }] }, FINAL_PASS, {}]) {
    assert.throws(() => parseFinal(bad, 2), /schema|item/);
  }
  const masked = parseFinal({ ...FINAL_PASS, items: [{ item: KEY, chunks: [] }] }, 2);
  assert.equal(masked.verdict, "fail");
  assert.ok(!JSON.stringify(masked).includes(KEY));
  // An item no chunk delivers fails the head, even beside a chunk out of range.
  assert.equal(parseFinal({ ...FINAL_PASS, items: [{ item: "a", chunks: [9] }, { item: "b", chunks: [] }] }, 2).verdict, "fail");
});

test("writeChunkResults hands the final step each chunk's output whole, and the spec, each file one Read", () => {
  const dir = tempDir("pr-verify-results-");
  const diff = path.join(dir, "diff");
  const write = (name, value) => {
    const file = path.join(dir, name);
    writeFileSync(file, typeof value === "string" ? value : JSON.stringify(value));
    return file;
  };
  const parts = [1, 2].map((k) => {
    mkdirSync(path.join(diff, `chunk-${k}`), { recursive: true });
    return write(`diff/chunk-${k}/part-001.patch`, "x\n");
  });
  mkdirSync(path.join(dir, "manifest"));
  const manifestParts = [write("manifest/part-001.txt", "chunk 1 x\n"), write("manifest/part-002.txt", "chunk 2 y\n")];
  const execution = (name, part, output) =>
    write(name, [
      { type: "assistant", message: { content: [part, ...manifestParts].map((file, i) => ({ type: "tool_use", id: `t${i}`, name: "Read", input: { file_path: file } })) } },
      { type: "result", subtype: "success", structured_output: output },
    ]);
  const logs = `${write("a.jsonl", JSON.stringify({ denials: { count: 0 } }))}\n${write("b.jsonl", JSON.stringify({ denials: { count: 0 } }))}\n`;
  // More than one file holds: the item at the end of the summary, and the
  // last note past a note's own length, still reach the final step.
  const crowded = { ...CHUNK_NOTES, summary: `${"delivers x. ".repeat(1000)}delivers the last item`, notes: [...Array(30).fill("n".repeat(1000)), `${"m".repeat(1500)} the last note`] };
  const env = {
    CHUNKS: "2",
    DIFF_DIR: diff,
    LOG_FILES: logs,
    RESULTS_DIR: path.join(dir, "results"),
    PART_BYTES: "15000",
    JUDGE_OUTCOMES: slots("success", "success"),
    SPEC_TEXT_FILE: write("spec-text.json", `[\n  {"body": "${"é long spec ".repeat(5000)}"}\n]\n`),
    SPEC_FILE: write("spec.json", "[]\n"),
    CONTEXT_FILE: write("context.json", "{}\n"),
    PR_FILE: write("pr.json", "{}\n"),
    MANIFEST_DIR: path.join(dir, "manifest"),
    PROMPT_FILE: path.join(dir, "prompt-spec.md"),
    PROMPT_TEMPLATE: fileURLToPath(new URL("./spec-prompt.md", import.meta.url)),
    SCHEMA_FILE: path.join(dir, "spec-schema.json"),
  };
  writeChunkResults({ ...env, EXECUTION_FILES: slots(execution("e1.json", parts[0], crowded), execution("e2.json", parts[1], CHUNK_PASS)) });
  const resultParts = (k) => readdirSync(env.RESULTS_DIR).filter((name) => name.startsWith(`chunk-${k}-part-`)).sort();
  assert.ok(resultParts(1).length > 1);
  for (const name of resultParts(1)) {
    const text = readFileSync(path.join(env.RESULTS_DIR, name), "utf8");
    assert.ok(Buffer.byteLength(text) <= 15000, name);
    assert.ok(text.split("\n").every((line) => line.length <= 1500), name);
  }
  const result = (k) => JSON.parse(resultParts(k).map((name) => readFileSync(path.join(env.RESULTS_DIR, name), "utf8")).join("").replaceAll("\n", ""));
  assert.deepEqual(result(1), { chunk: 1, of: 2, ...crowded });
  assert.deepEqual(result(2), { chunk: 2, of: 2, ...CHUNK_PASS });
  assert.deepEqual(resultParts(2), ["chunk-2-part-001.txt"]);
  assert.deepEqual(readdirSync(env.RESULTS_DIR).filter((name) => name.startsWith("context-part-")), []);
  const specParts = readdirSync(env.RESULTS_DIR).filter((name) => name.startsWith("spec-part-")).sort();
  assert.ok(specParts.length > 1);
  let rejoined = "";
  for (const name of specParts) {
    const text = readFileSync(path.join(env.RESULTS_DIR, name), "utf8");
    assert.ok(Buffer.byteLength(text) <= 15000, name);
    assert.ok(text.split("\n").every((line) => line.length <= 1500), name);
    rejoined += text;
  }
  assert.ok(rejoined.length >= readFileSync(env.SPEC_TEXT_FILE, "utf8").length);
  const prompt = readFileSync(env.PROMPT_FILE, "utf8");
  assert.ok(prompt.includes(`  - \`${path.join(env.RESULTS_DIR, resultParts(1).at(-1))}\`\n  - \`${path.join(env.RESULTS_DIR, "chunk-2-part-001.txt")}\``));
  for (const name of specParts) assert.ok(prompt.includes(`  - \`${path.join(env.RESULTS_DIR, name)}\``), name);
  for (const file of [env.SPEC_FILE, env.CONTEXT_FILE, env.PR_FILE, ...manifestParts]) assert.ok(prompt.includes(file), file);
  assert.doesNotMatch(prompt, /RESULT_FILES|SPEC_PARTS|MANIFEST_PARTS|SPEC_FILE|PR_FILE|CONTEXT_FILE/);
  assert.ok(!prompt.includes("/diff/"), "the final step is pointed at no diff");
  assert.deepEqual(JSON.parse(readFileSync(env.SCHEMA_FILE, "utf8")).required, ["verdict", "summary", "notes", "items"]);
  const secret = { ...env, RESULTS_DIR: path.join(dir, "none"), EXECUTION_FILES: `${execution("e3.json", parts[0], { ...CHUNK_PASS, summary: KEY })}\n${execution("e4.json", parts[1], CHUNK_PASS)}\n` };
  writeChunkResults(secret);
  const secretResult = readFileSync(path.join(secret.RESULTS_DIR, "chunk-1-part-001.txt"), "utf8");
  assert.ok(!secretResult.includes("sk-ant-"));
  assert.equal(JSON.parse(secretResult).verdict, "fail");
  // A refs entry's context goes through the same parts, one Read each.
  const refsSpec = { ...env, RESULTS_DIR: path.join(dir, "refs"), PROMPT_FILE: path.join(dir, "prompt-refs.md"), SPEC_TEXT_FILE: write("spec-refs.json", [{ spec_kind: "refs", body: "x" }]), CONTEXT_FILE: write("context-long.json", { pr: { body: "é long body ".repeat(5000) } }), EXECUTION_FILES: `${execution("e7.json", parts[0], CHUNK_PASS)}\n${execution("e8.json", parts[1], CHUNK_PASS)}\n` };
  writeChunkResults(refsSpec);
  const contextParts = readdirSync(refsSpec.RESULTS_DIR).filter((name) => name.startsWith("context-part-")).sort();
  assert.ok(contextParts.length > 1);
  const refsPrompt = readFileSync(refsSpec.PROMPT_FILE, "utf8");
  for (const name of contextParts) {
    assert.ok(Buffer.byteLength(readFileSync(path.join(refsSpec.RESULTS_DIR, name))) <= 15000, name);
    assert.ok(refsPrompt.includes(path.join(refsSpec.RESULTS_DIR, name)), name);
  }
  assert.ok(!refsPrompt.includes(refsSpec.CONTEXT_FILE));
  // More results than the final judge's budget stop before it runs.
  const huge = { ...CHUNK_NOTES, summary: "y".repeat(16000), notes: Array(40).fill("z".repeat(8000)) };
  const over = { ...env, RESULTS_DIR: path.join(dir, "over"), EXECUTION_FILES: `${execution("e9.json", parts[0], huge)}\n${execution("e10.json", parts[1], CHUNK_PASS)}\n` };
  assert.throws(() => writeChunkResults(over), /parts/);
  assert.equal(existsSync(over.RESULTS_DIR), false);
  // The workflow names the Read budget, and no default stands in for it.
  for (const bad of [undefined, "", "many", "100"]) {
    assert.throws(() => writeChunkResults({ ...env, PART_BYTES: bad, RESULTS_DIR: path.join(dir, "bad"), EXECUTION_FILES: `${execution("e5.json", parts[0], CHUNK_PASS)}\n${execution("e6.json", parts[1], CHUNK_PASS)}\n` }), /PART_BYTES/, String(bad));
  }
});

test("checkKeyLeg on the final step reads the chunks that ran, past the blank slots", () => {
  const dir = tempDir("pr-verify-final-leg-");
  const file = (name) => {
    const target = path.join(dir, name);
    writeFileSync(target, JSON.stringify({ denials: { count: 0 } }));
    return target;
  };
  const [a, b, c] = [file("a"), file("b"), file("c")];
  const clean = { CHUNKS: "2", LOG_FILES: `${slots(a, b)}${c}\n`, GITHUB_OUTPUT: path.join(dir, "out") };
  checkKeyLeg(clean);
  assert.equal(readFileSync(clean.GITHUB_OUTPUT, "utf8"), "clean=true\n");
  const short = { CHUNKS: "2", LOG_FILES: `${slots(a)}${c}\n`, GITHUB_OUTPUT: path.join(dir, "short") };
  assert.throws(() => checkKeyLeg(short), /unreadable/);
  assert.equal(existsSync(short.GITHUB_OUTPUT), false);
});
