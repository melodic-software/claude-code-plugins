import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const ROUTES = Object.freeze(JSON.parse(readFileSync(new URL("./escalation-routes.json", import.meta.url), "utf8")));

export const escalationActivity = (reason) => (Object.hasOwn(ROUTES, reason) ? ROUTES[reason].activity : null);

export const escalationRoute = (reason) => (Object.hasOwn(ROUTES, reason) ? ROUTES[reason].route : null);

export const stopSkip = (reason) => (escalationRoute(reason) === "fail" ? "lane-stopped" : "awaiting-human");

export const LANE_STOP = "Skipped: lane-stopped";
export const laneStop = (run) => run?.status === "completed" && run.conclusion === "neutral" && run.output?.title === LANE_STOP;

export const STOP_RESOLVED = "Skipped: stop-resolved";

// The GitHub Actions app: only its check runs are a trusted stop record.
export const ACTIONS_APP_ID = 15368;

export const retryRung = (stopRuns) => (stopRuns.some((run) => laneStop(run) && run.app?.id === ACTIONS_APP_ID) ? "1" : "");

// `node escalation-routes.mjs skip` prints stopSkip of the REASON variable,
// for a workflow job that posts a select job's stop.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv[2] !== "skip") {
    throw new Error("usage: escalation-routes.mjs skip");
  }
  process.stdout.write(stopSkip(process.env.REASON ?? ""));
}
