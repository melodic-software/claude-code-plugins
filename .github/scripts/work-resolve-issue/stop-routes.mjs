// stop-routes.json, the issue lane's one routing table: each stop reason's
// route and why, as report-outcome.mjs reads it. It mirrors pr-unblock's
// escalation-routes.json shape rather than sharing its loader, because
// report-outcome runs from a copy of this directory alone.
//   hold      hands the issue to a person: the human-gated label and the
//             escalation marker. Only an intent, design, security or cost
//             reason routes here: each hold row's `class` (HOLD_CLASSES)
//             says which.
//   host-run  adds the host-run label, the host queue's one signal, and
//             removes agent-ready, so an unattended agent run on a host builds it.
//   attended  adds the attended label and removes agent-ready: the work needs
//             a manual external step only the owner, present, can take; only
//             a listed human removes the label. It asks the owner for no
//             decision, which stays needs-human's.
//   retry     keeps agent-ready, so work-unblock starts it again, up to
//             limits.stop-retries, or the row's `retries` when fewer; past
//             that it takes retry-spent's route. The cap counts every retry
//             since a listed human last added agent-ready, whatever stop
//             wrote it, so a row's `retries` is a ceiling on that shared count.
//   wait      keeps agent-ready with the open pull request the run names in
//             its marker, so work-unblock starts it again once that pull
//             request merges or closes, up to limits.stop-retries waits;
//             past that it takes retry-spent's route.
//   intake    removes agent-ready, status: ready and admission-deferred, so
//             the triage sweep sends the issue back through intake, whose
//             admission and refinement decide it as the owner settled, up
//             to limits.stop-retries, or the row's `retries` when fewer;
//             past that it takes retry-spent's route.
//   park      removes agent-ready, status: ready and admission-deferred and
//             adds status: confirmed beside the lanes App's admission comment
//             naming the reason, as admission parks a refusal no person
//             answers; intake takes it again once the reason is met.
//   close     closes the issue as completed with the run's words.
//   fail      removes agent-ready and adds no label: the comment's outcome
//             marker is the visible stop the maintenance monitor reports.
import { readFileSync } from "node:fs";

const ROUTE_NAMES = new Set(["hold", "host-run", "attended", "retry", "wait", "intake", "park", "close", "fail"]);
// The routes a row's `retries` may cap.
const COUNTED_ROUTES = new Set(["retry", "wait", "intake"]);
// The owner's reasons for a person (owner direction 2026-10-27).
export const HOLD_CLASSES = new Set(["intent-change", "design-change", "security-risk", "cost-risk"]);

export const STOP_ROUTES = Object.freeze(JSON.parse(readFileSync(new URL("./stop-routes.json", import.meta.url), "utf8")));
for (const [reason, row] of Object.entries(STOP_ROUTES)) {
  if (!ROUTE_NAMES.has(row?.route) || typeof row.why !== "string" || row.why === "") {
    throw new Error(`stop-routes.json: ${reason} needs a route (${[...ROUTE_NAMES].join(", ")}) and a why`);
  }
  if (row.retries !== undefined && !(COUNTED_ROUTES.has(row.route) && Number.isSafeInteger(row.retries) && row.retries >= 0)) {
    throw new Error(`stop-routes.json: ${reason}'s retries needs a ${[...COUNTED_ROUTES].join(", ")} route and a whole number`);
  }
  if (row.route === "hold" && !HOLD_CLASSES.has(row.class)) {
    throw new Error(`stop-routes.json: ${reason} holds, so its class needs to be one of ${[...HOLD_CLASSES].join(", ")}`);
  }
  if (row.route !== "hold" && row.class !== undefined) {
    throw new Error(`stop-routes.json: ${reason} does not hold, so it takes no class`);
  }
}
// runCode's security backstop routes to this row.
if (STOP_ROUTES["security-risk"]?.route !== "hold" || STOP_ROUTES["security-risk"].class !== "security-risk") {
  throw new Error("stop-routes.json: security-risk needs a hold route and class security-risk");
}
// A spent cap that routed to retry would retry without end.
for (const spent of ["retry-spent", "turn-cap-spent"]) {
  if (STOP_ROUTES[spent]?.route === "retry" || !Object.hasOwn(STOP_ROUTES, spent)) {
    throw new Error(`stop-routes.json: ${spent} needs a route other than retry`);
  }
}

// The label host-run routes add: github-iac GovernedRepositories.cs defines it.
export const HOST_RUN_LABEL = "host-run";
// The label attended routes add, likewise declared in github-iac.
export const ATTENDED_LABEL = "attended";

// A reason's route; a reason the table does not list names no owner reason,
// so it fails rather than reaching a person.
export const stopRoute = (reason) => (Object.hasOwn(STOP_ROUTES, reason) ? STOP_ROUTES[reason].route : "fail");
// The stop-reason code (../lib/stop-reason.mjs) a reason's comment carries:
// its hold row's class as intent, design, security or cost, else none.
const CLASS_CODES = { "intent-change": "intent", "design-change": "design", "security-risk": "security", "cost-risk": "cost" };
export const stopReasonCode = (reason) => (Object.hasOwn(STOP_ROUTES, reason) && CLASS_CODES[STOP_ROUTES[reason].class]) || "none";
// The most retries a reason's row allows, within limits.stop-retries.
export const stopRetries = (reason, cap) => Math.min(cap, (Object.hasOwn(STOP_ROUTES, reason) ? STOP_ROUTES[reason].retries : undefined) ?? cap);
export const stopWhy = (reason) => (Object.hasOwn(STOP_ROUTES, reason) ? STOP_ROUTES[reason].why : "the stop reason is not in the lane's route table");

// The codes a run may open its `stopped` reason with, longest first, each in
// any case: security-risk with a hyphen, underscore, space or nothing between
// its words, every other code only hyphenated and followed by no word
// character or hyphen, so "Design change in X" names no code.
const CODES = Object.keys(STOP_ROUTES)
  .filter((reason) => STOP_ROUTES[reason].code === true)
  .sort((a, b) => b.length - a.length)
  .map((code) => [code, code === "security-risk" ? /^security[-_\s]*risk/i : new RegExp(`^${code}(?![\\w-])`, "i")]);
// A reason that names a security concern, even inside a word; the short
// acronyms (XSS, RCE, CVE) only as whole words, so "source" names none.
const SECURITY_CONCERN =
  /security|vuln|inject|exfiltrat|malicious|backdoor|exploit|branch[\s_-]?protection|attack|unauthori[sz]|hijack|\btake[\s-]?over\b|took\s+over|\bstol(?:e|en)\b|\bstranger|\boutsider|\b(?:xss|rce|cve)\b|ignore\b.{0,40}\binstructions?\b/i;
// The secret nouns: a security word everywhere, released only after an
// ending code and only in a capability phrasing (CAPABILITY below).
const SECRET_NOUN = String.raw`credential|secret|token|passw(?:or)?d|api[\s_-]?key|private[\s_-]?key|deploy[\s_-]?key|ssh[\s_-]?key|access[\s_-]?key|\bpat\b(?!-)`;
const SECURITY_WORD = new RegExp(`${SECURITY_CONCERN.source}|${SECRET_NOUN}`, "i");
// The phrasings that name a secret only as something a run needs ("a host
// with model credentials", "needs an API key the lane does not hold", "tokens
// per task"). Fail closed: the phrasing counts only when the secret noun,
// after at most a model or deploy qualifier, ends the clause or is followed by
// a lane capability ("the lane", "to run"), so "needs the token to be
// rotated", "needs the API key, which ..." and "needs the reused token" hold.
const N = "(?:credentials?|api[\\s_-]?keys?|tokens?|secrets?|passwords?)";
const END = "(?=\\s*(?:$|[.;)]|\\s(?:to\\s+(?:run|invoke|call|use|reach|spend)|the\\s+lane|this\\s+lane|it\\s+does|which\\s+only|only)\\b))";
const CAPABILITY = new RegExp(
  `\\b(?:(?:a|the)\\s+)?host\\s+with\\s+(?:(?:model|an?|the)\\s+)*${N}${END}|\\b(?:needs?|requires?|lacks?)\\s+(?:(?:an?|the|model|deploy)\\s+)*${N}${END}|\\btokens?\\s+(?:per|spent|count|usage|budget)\\b|,\\s*tokens\\s*,`,
  "gi",
);
// The only words a reason that names a secret noun may hold beside its
// capability phrasings. Fail closed: any other word, so any exposure however
// worded ("uploaded", "posted", "the key was ..."), a pronoun that could point
// at the secret, or a word in another script, holds. "this" and "that" count
// only before "lane" or "needs".
const CAPABILITY_WORDS = new Set(
  "a an the and or to on of for with not no cannot can does only lane host desktop machine gpu run runs need needs requires lacks hold invoke call spend credit prepaid eval evals suite suites claude model live task tasks completed work against records pass rate advisor wall time printer driver".split(" "),
);
const capabilityOnly = (text) => {
  const words = text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  return words.every((word, i) => CAPABILITY_WORDS.has(word) || (/^th(?:is|at)$/.test(word) && /^(?:lane|needs)$/.test(words[i + 1] ?? "")));
};
// The routes that end the lane's work on the issue rather than bring it back:
// a security mention after one of their codes still reaches a person (owner
// decision 2026-10-29), unless the secret is only named in a capability
// phrasing: a person is only for a real security risk such as a leaked token
// (owner direction, docs/contracts/loop-lane/README.md "When work stops for
// the owner"), and a capability limit is none. This holds for a pushback that
// opens with a host-run or attended code too. A wait or retry code comes back
// to the lane anyway, except after a pushback (runCode's anyCodeEnds).
const ENDING_ROUTES = new Set(["close", "host-run", "attended"]);
const endingRiskWord = (text) => {
  const rest = text.replace(CAPABILITY, " ");
  return SECURITY_CONCERN.exec(text)?.[0] ?? SECURITY_WORD.exec(rest)?.[0] ?? (capabilityOnly(rest) ? "" : (SECURITY_WORD.exec(text)?.[0] ?? ""));
};
const namesEndingRisk = (text) => endingRiskWord(text) !== "";

// The code a run's stop reason opens with, read NFKC-normalized (so a
// full-width letter reads as its ASCII one) past any emphasis, backticks and a
// `Reason:` label. A code whose route ends the lane's work, followed by text
// that names security, is security-risk instead. With no code, security-risk
// when it names security, so a misformatted security code still reaches a
// person; else "stopped". Intent, design and cost words are common in plain
// reasons, so only their code holds for them.
const plainText = (text) =>
  String(text ?? "")
    .normalize("NFKC")
    .replace(/[\p{Cf}\p{Mn}]/gu, "");
const reasonText = (reason) => plainText(reason).replace(/^[\s*_`]*(?:reason\s*:)?[\s*_`]*/i, "");
// A pushback's `cause` as a row name: read as a reason is, lowercased, with
// trailing `.`, `:`, `;` and spaces dropped and each run of spaces,
// underscores and hyphens one hyphen, so "Security Risk", "intent - change"
// and "intent:" name their rows.
export const causeName = (cause) =>
  plainText(cause)
    .trim()
    .toLowerCase()
    .replace(/[.:;\s]+$/, "")
    .replace(/[\s_-]+/g, "-")
    .replace(/^-+|[-.:;]+$/g, "");
// The code a reason explicitly opens with, read as runCode reads it, with no
// security-word reading: "" when it opens with none.
export const leadingCode = (reason) => {
  const text = reasonText(reason);
  return CODES.find(([, code]) => code.test(text))?.[0] ?? "";
};
// With `anyCodeEnds`, every code reads as ending the lane's work: a pushback
// never waits or retries, so a security mention after a wait code such as
// blocked-by-pr counts as well.
export const runCode = (reason, { anyCodeEnds = false } = {}) => {
  const text = reasonText(reason);
  for (const [name, code] of CODES) {
    const match = code.exec(text);
    if (match) {
      return (anyCodeEnds || ENDING_ROUTES.has(STOP_ROUTES[name].route)) && namesEndingRisk(text.slice(match[0].length)) ? "security-risk" : name;
    }
  }
  return SECURITY_WORD.test(text) ? "security-risk" : "stopped";
};
// The security word runCode, with `anyCodeEnds`, reads in `reason`, as text
// safe to show in a code span of a public comment: a match can hold free text
// ("ignore ... instructions"), so it keeps only ASCII letters, digits, hyphens,
// underscores and single spaces. "" when it names none.
export const securityWord = (reason) => {
  const text = reasonText(reason);
  const found = CODES.find(([, code]) => code.test(text));
  const word = found ? endingRiskWord(text.slice(found[1].exec(text)[0].length)) : (SECURITY_WORD.exec(text)?.[0] ?? "");
  return word.replaceAll(/[^A-Za-z0-9_-]+/g, " ").trim();
};
