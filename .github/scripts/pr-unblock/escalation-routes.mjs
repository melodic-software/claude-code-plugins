// escalation-routes.json, the one routing table: each stop reason's activity
// and route (`hold` hands the PR to a person with the label; `fail` ends in a
// failing status and no label), as report-escalation.sh reads it. No
// network; imported by gate-source.mjs, the select and emitter scripts, and
// apply-patch.mjs (which copies this file and the table beside its own copy).
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const ROUTES = Object.freeze(JSON.parse(readFileSync(new URL("./escalation-routes.json", import.meta.url), "utf8")));

// The activity a reason resumes, or null for a reason the table does not
// list, which holds every activity.
export const escalationActivity = (reason) => (Object.hasOwn(ROUTES, reason) ? ROUTES[reason].activity : null);

// A reason's route, or null for a reason the table does not list.
export const escalationRoute = (reason) => (Object.hasOwn(ROUTES, reason) ? ROUTES[reason].route : null);

// The skip reason a job that stops on `reason` posts on its check: a stop
// routed to a failing status is `lane-stopped`, which limit-stop.mjs reads;
// one held for a person, or one the table does not list, `awaiting-human`.
export const stopSkip = (reason) => (escalationRoute(reason) === "fail" ? "lane-stopped" : "awaiting-human");

// A stop routed to a failing status, posted after a model turn: the emitter
// job's neutral check carrying stopSkip's lane-stopped (limit-stop.mjs
// releases the head on it). The same skip on the activity's own check is a
// select job's stop, which handles the head for good like any other check.
export const LANE_STOP = "Skipped: lane-stopped";
export const laneStop = (run) => run?.status === "completed" && run.conclusion === "neutral" && run.output?.title === LANE_STOP;

// The GitHub Actions app: only its check runs are a trusted stop record.
export const ACTIONS_APP_ID = 15368;

// The model rung a same-head retry runs at: "1" (the profile's escalate-to,
// resolve.mjs) once the head carries a lane stop from the emitter job
// (`stopRuns`, REST shape, by the GitHub Actions app), else "" (its own).
export const retryRung = (stopRuns) => (stopRuns.some((run) => laneStop(run) && run.app?.id === ACTIONS_APP_ID) ? "1" : "");

// `node escalation-routes.mjs skip` prints stopSkip of the REASON variable,
// for a workflow job that posts a select job's stop.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv[2] !== "skip") {
    throw new Error("usage: escalation-routes.mjs skip");
  }
  process.stdout.write(stopSkip(process.env.REASON ?? ""));
}
