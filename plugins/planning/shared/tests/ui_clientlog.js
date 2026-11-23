#!/usr/bin/env node
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const ANSWER = "answer-text-the-log-never-holds";
const THROWN = "injected-clientlog-error";

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_clientlog.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let chromium;
  try { chromium = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_clientlog"), { ok } = s;
  const rec = recorder(chromium);
  try {
    const A = await s.start("clientlog");
    s.apply(A.dir, [{ op: "open-round", questions: [{ id: "Q1", text: "Which payment method?", alternatives: [], dependsOn: [], purpose: "decide",
      format: { kind: "choice", options: [{ id: "opt-1", label: "Card" }, { id: "opt-2", label: "Saved method" }] } }] }]);
    const owner = await rec.open(A.ownerUrl);
    await until(owner, () => window.Core.snapshot()?.me?.role === "owner");
    await owner.evaluate(() => window.Core.lock("Q1", "opt-1"));
    const guest = await rec.open(A.localUrl);
    const pid = await joinAs(guest, "Ann");

    await guest.evaluate(t => { setTimeout(() => { throw new Error(t); }); }, THROWN);
    const status = await guest.evaluate(t => window.Core.answerCiting("Q1", t, []).then(() => 200, e => e.status), ANSWER);
    ok("the answer on a locked question is refused 409", status === 409, status);

    const ownerText = await owner.evaluate(() => window.Core.setLeader(window.Core.snapshot().me.pid, true).then(() => "accepted", e => window.Core.errorText(e)));
    ok("a 400 bad-field shows the server's message", ownerText === "The owner's own role, trust and presence cannot change.", ownerText);

    const errors = () => s.share(A.dir, "logs", "--errors").lines;
    let lines = [];
    for (let i = 0; i < 40 && !lines.some(l => l.includes(THROWN)); i++) { lines = errors(); if (!lines.some(l => l.includes(THROWN))) await new Promise(r => setTimeout(r, 200)); }
    await new Promise(r => setTimeout(r, 1000));
    lines = errors();
    const thrown = lines.filter(l => l.includes(` client pid=${pid} kind=error `) && l.includes(THROWN));
    ok("the script error reaches the log as one client entry with the guest's pid, naming the browser", thrown.length === 1 && / ua="chrome computer" fp=[0-9a-f]{8}$/.test(thrown[0]), lines.join(" | "));
    const answered = lines.filter(l => l.includes(" route=/api/answer "));
    ok("the 409 is logged once, by the server's request entry with its code", answered.length === 1 && / request method=POST route=\/api\/answer status=409 /.test(answered[0]) && answered[0].includes(` pid=${pid} `) && answered[0].includes(" code=locked"), answered.join(" | "));
    const role = lines.filter(l => l.includes(" route=/api/person/role "));
    ok("the 400 bad-field is logged once, by the server's request entry", role.length === 1 && / request method=POST route=\/api\/person\/role status=400 /.test(role[0]) && role[0].includes(" code=bad-field"), role.join(" | "));
    ok("no client entry copies a refusal", !lines.some(l => / client .*kind=api /.test(l)), lines.join(" | "));
    const all = s.share(A.dir, "logs").lines.join("\n");
    ok("the answer's text never reaches the log", !all.includes(ANSWER));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally {
    await chromium.close();
  }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
