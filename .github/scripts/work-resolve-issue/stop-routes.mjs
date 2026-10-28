// stop-routes.json, the issue lane's one routing table: each stop reason's
// route and why, as report-outcome.mjs reads it. It mirrors pr-unblock's
// escalation-routes.json shape rather than sharing its loader, because
// report-outcome runs from a copy of this directory alone.
//   hold      hands the issue to a person: the human-gated label and the
//             escalation marker. Only an intent, design, security or cost
//             reason routes here.
//   host-run  adds the host-run label, the host queue's one signal, and
//             removes agent-ready, so a maintainer session builds it by hand.
//   retry     keeps agent-ready, so work-unblock starts it again, up to
//             limits.stop-retries; past that it takes retry-spent's route.
//   fail      removes agent-ready and adds no label: the comment's outcome
//             marker is the visible stop the maintenance monitor reports.
import { readFileSync } from "node:fs";

const ROUTE_NAMES = new Set(["hold", "host-run", "retry", "fail"]);

export const STOP_ROUTES = Object.freeze(JSON.parse(readFileSync(new URL("./stop-routes.json", import.meta.url), "utf8")));
for (const [reason, row] of Object.entries(STOP_ROUTES)) {
  if (!ROUTE_NAMES.has(row?.route) || typeof row.why !== "string" || row.why === "") {
    throw new Error(`stop-routes.json: ${reason} needs a route (${[...ROUTE_NAMES].join(", ")}) and a why`);
  }
}
// A spent cap that routed to retry would retry without end.
for (const spent of ["retry-spent", "turn-cap-spent"]) {
  if (STOP_ROUTES[spent]?.route === "retry" || !Object.hasOwn(STOP_ROUTES, spent)) {
    throw new Error(`stop-routes.json: ${spent} needs a route other than retry`);
  }
}

// The label host-run routes add: github-iac GovernedRepositories.cs defines it.
export const HOST_RUN_LABEL = "host-run";

// A reason's route; a reason the table does not list holds.
export const stopRoute = (reason) => (Object.hasOwn(STOP_ROUTES, reason) ? STOP_ROUTES[reason].route : "hold");
export const stopWhy = (reason) => (Object.hasOwn(STOP_ROUTES, reason) ? STOP_ROUTES[reason].why : "the stop reason is not in the lane's route table");

// The codes a run may open its `stopped` reason with, longest first.
const CODES = Object.keys(STOP_ROUTES)
  .filter((reason) => STOP_ROUTES[reason].code === true)
  .sort((a, b) => b.length - a.length);

// The code a run's stop reason opens with, or "stopped" for none.
export const runCode = (reason) => CODES.find((code) => new RegExp(`^\\s*\`?${code}\\b`).test(reason ?? "")) ?? "stopped";
