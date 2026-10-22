#!/usr/bin/env node
// Issue references and repository paths on the shared page link to the session's repository, against
// `share.sh ensure-running` with the fake cloudflared. With no repository set, `#123` and `plugins/x.py:10` in a
// question's background stay plain text; `set-repo` with a repository links `#N` only; with a commit too, a path links
// to the file at that commit; an empty repository unlinks both again. A guest's answer gets the same rendering, and
// its `<b>` stays literal text. Nothing links inside a code span or an existing URL, or on a path outside the repo.
//   node plugins/planning/shared/tests/ui_reflinks.js
// Needs playwright-core and a Chromium it can launch; without them it prints SKIP and exits 0.
// Expected hrefs come from the issue's two URL forms, https://github.com/<repo>/issues/<N> and
// https://github.com/<repo>/blob/<commit>/<path>#L<line> (GitHub's #L<a>-L<b> for a range), filled with this suite's own
// repository and SHA.
"use strict";
const { loadPlaywright, suite, recorder, until, joinAs } = require("./browser_harness");

const REPO = "octo-org/demo", SHA = "0123456789abcdef0123456789abcdef01234567";
const ISSUE = n => `https://github.com/${REPO}/issues/${n}`;
const BLOB = (p, line) => `https://github.com/${REPO}/blob/${SHA}/${p}${line ? `#L${line}` : ""}`;
const URL_IN_TEXT = "https://example.com/docs/a.html#12";
const CONTEXT = `Background: see #123 and plugins/x.py:10. Also (plugins/w.py), docs/a.md:3-5, \`plugins/y.py\` and ${URL_IN_TEXT}; not and/or, w/e.g. this, client/server.Then, 1/2.5, /srv/x.py or example.com/x.html.`;
const ANSWER = "<b>bold?</b> fixes #7 in plugins/z.md";

/** In the page: the links in the rendered text holding `marker`, and whether that text has a <b> element. */
function rendered(marker) {
  const box = [...document.querySelectorAll(".vf-rich")].find(el => el.textContent.includes(marker));
  if (!box) return null;
  return { text: box.textContent, bold: !!box.querySelector("b"), links: [...box.querySelectorAll("a")].map(a => ({ href: a.href, text: a.textContent, target: a.target, rel: a.rel, inCode: !!a.closest("code") })) };
}

async function main() {
  const pw = loadPlaywright();
  if (!pw) { console.log("SKIP: ui_reflinks.js needs playwright-core (npm ci, or playwright-cli on PATH)"); return 0; } // silent-skip-ok: a browser suite needs a local Playwright
  let browser;
  try { browser = await pw.chromium.launch(); } catch (e) { console.log(`SKIP: no Chromium to launch (${String(e.message).split("\n")[0]})`); return 0; } // silent-skip-ok: no browser binary
  const s = suite("ui_reflinks"), { ok } = s, rec = recorder(browser);
  try {
    const A = await s.start("reflinks");
    s.apply(A.dir, [{ op: "open-round", questions: [{ id: "Q1", text: "Which file holds the retry rule?", context: CONTEXT, alternatives: [], dependsOn: [], purpose: "decide", format: { kind: "text" } }] }]);
    const guest = await rec.open(A.localUrl);
    await joinAs(guest, "Gus");
    const hrefsOf = r => (r ? r.links.map(l => l.href) : null);
    const ctx = () => guest.evaluate(rendered, "Background:");
    const waitHrefs = async want => { await until(guest, ([m, w]) => { const box = [...document.querySelectorAll(".vf-rich")].find(el => el.textContent.includes(m)); return !!box && JSON.stringify([...box.querySelectorAll("a")].map(a => a.href)) === JSON.stringify(w); }, ["Background:", want]); return ctx(); };

    let r = await waitHrefs([URL_IN_TEXT]);
    ok("no repository: #123 and the path stay plain text, the URL still links", JSON.stringify(hrefsOf(r)) === JSON.stringify([URL_IN_TEXT]), JSON.stringify(hrefsOf(r)));
    ok("  and the text reads as written", !!r && r.text.includes("#123 and plugins/x.py:10."), r && r.text);

    s.apply(A.dir, [{ op: "set-repo", repo: REPO }]);
    r = await waitHrefs([ISSUE(123), URL_IN_TEXT]);
    ok("a repository without a commit, set after the page drew the text: #123 links, the path stays plain", JSON.stringify(hrefsOf(r)) === JSON.stringify([ISSUE(123), URL_IN_TEXT]), JSON.stringify(hrefsOf(r)));

    s.apply(A.dir, [{ op: "set-repo", repo: REPO, commit: SHA }]);
    const want = [ISSUE(123), BLOB("plugins/x.py", 10), BLOB("plugins/w.py"), `https://github.com/${REPO}/blob/${SHA}/docs/a.md#L3-L5`, URL_IN_TEXT];
    r = await waitHrefs(want);
    ok("repository and commit: #123, plugins/x.py:10, (plugins/w.py) and a line range link; the code span, the URL and the rest do not", JSON.stringify(hrefsOf(r)) === JSON.stringify(want), JSON.stringify(hrefsOf(r)));
    const texts = r ? r.links.map(l => l.text) : [];
    ok("  each link's text is the reference as written, without the trailing punctuation", JSON.stringify(texts) === JSON.stringify(["#123", "plugins/x.py:10", "plugins/w.py", "docs/a.md:3-5", URL_IN_TEXT]), JSON.stringify(texts));
    ok("  every link opens a new tab with rel noopener noreferrer", !!r && r.links.every(l => l.target === "_blank" && l.rel === "noopener noreferrer"));
    ok("  and none sits inside a code span", !!r && r.links.every(l => !l.inCode));

    const status = await guest.evaluate(t => window.Core.answerCiting("Q1", t, []).then(() => 200, e => e.status), ANSWER);
    ok("the guest's answer is saved", status === 200, status);
    ok("the guest's answer renders", await until(guest, m => [...document.querySelectorAll(".vf-rich")].some(el => el.textContent.includes(m)), "bold?</b>"));
    const ans = await guest.evaluate(rendered, "bold?</b>");
    ok("a guest's <b> stays literal text, no element", !!ans && !ans.bold && ans.text.includes("<b>bold?</b>"), ans && ans.text);
    ok("  and its #7 and plugins/z.md link the same way", JSON.stringify(hrefsOf(ans)) === JSON.stringify([ISSUE(7), BLOB("plugins/z.md")]), JSON.stringify(hrefsOf(ans)));

    s.apply(A.dir, [{ op: "set-repo", repo: "" }]);
    r = await waitHrefs([URL_IN_TEXT]);
    ok("an empty repository unlinks them again", JSON.stringify(hrefsOf(r)) === JSON.stringify([URL_IN_TEXT]), JSON.stringify(hrefsOf(r)));

    const errs = rec.errors.filter(m => !/Failed to load resource/.test(m));
    ok("no page error", errs.length === 0, errs.slice(0, 3).join(" | "));
    const csp = await rec.cspViolations();
    ok("no CSP violation", csp.length === 0, csp.join(" | "));
  } catch (e) {
    ok("the suite ran to the end", false, String(e.stack || e).split("\n").slice(0, 3).join(" "));
  } finally { await browser.close(); }
  return s.finish();
}

main().then(code => process.exit(code), e => { console.error(e); process.exit(1); });
