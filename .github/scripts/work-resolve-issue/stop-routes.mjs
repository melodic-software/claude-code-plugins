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
//   close     closes the issue as completed with the run's words.
//   fail      removes agent-ready and adds no label: the comment's outcome
//             marker is the visible stop the maintenance monitor reports.
import { readFileSync } from "node:fs";

const ROUTE_NAMES = new Set(["hold", "host-run", "attended", "retry", "wait", "intake", "close", "fail"]);
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
// A reason that names a security concern, even inside a word.
const SECURITY_WORD = /security|vuln|inject|credential|secret|token|exfiltrat|malicious/i;
// The routes that end the lane's work on the issue rather than bring it back:
// a security mention after one of their codes still reaches a person (owner
// decision 2026-10-29). A wait or retry code comes back to the lane anyway.
const ENDING_ROUTES = new Set(["close", "host-run", "attended"]);

// The code a run's stop reason opens with, read NFKC-normalized (so a
// full-width letter reads as its ASCII one) past any emphasis, backticks and a
// `Reason:` label. A code whose route ends the lane's work, followed by text
// that names security, is security-risk instead. With no code, security-risk
// when it names security, so a misformatted security code still reaches a
// person; else "stopped". Intent, design and cost words are common in plain
// reasons, so only their code holds for them.
export const runCode = (reason) => {
  const text = String(reason ?? "")
    .normalize("NFKC")
    .replace(/[\p{Cf}\p{Mn}]/gu, "")
    .replace(/^[\s*_`]*(?:reason\s*:)?[\s*_`]*/i, "");
  for (const [name, code] of CODES) {
    const match = code.exec(text);
    if (match) {
      return ENDING_ROUTES.has(STOP_ROUTES[name].route) && SECURITY_WORD.test(text.slice(match[0].length)) ? "security-risk" : name;
    }
  }
  return SECURITY_WORD.test(text) ? "security-risk" : "stopped";
};
