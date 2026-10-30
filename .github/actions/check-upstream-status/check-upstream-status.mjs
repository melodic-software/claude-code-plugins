// Upstream-status gate for token-spending lanes: skip the run while GitHub
// Actions or npm package installation lists an outage, so a lane does not
// spend tokens on a run the incident will fail. Reads each service's own
// component, never the page rollup (component-status.mjs). Fails open: a page
// that cannot be read, or lists no such component, lets the lane proceed.
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { ACTIONS, NPM_INSTALL, readComponents } from "../../scripts/maintenance-reconcile-lost-runs/component-status.mjs";

export const GATED = [ACTIONS, NPM_INSTALL];
// The Statuspage component statuses that skip a run: broken for a subset of
// customers, or completely unavailable
// (https://support.atlassian.com/statuspage/docs/what-is-a-component).
// degraded_performance ("working but is slow") and under_maintenance ("being
// worked on") run: during incident pwxsjgnvrk6b Actions listed a degraded
// status while its jobs kept succeeding, and a skip there cost every lane run
// it touched. The shared verdictOf stays as it is: the reconciler idles on any
// status but operational.
export const OUTAGE = new Set(["partial_outage", "major_outage"]);

// Page text reaches the log and an output: keep one line with no workflow
// command in it.
const clean = (text) => String(text).replace(/[\r\n]+/g, " ").replaceAll("::", ": :");

// { degraded, reason, notes }: degraded is "true" only when a component lists
// an OUTAGE status; notes are the lines to log, one per component that is not
// operational.
export async function checkUpstreamStatus({ fetchStatus } = {}) {
  const verdicts = await readComponents({ fetchStatus, components: GATED });
  const down = verdicts.filter((v) => OUTAGE.has(v.status));
  const slow = verdicts.filter((v) => v.verdict === "degraded" && !OUTAGE.has(v.status));
  const unknown = verdicts.filter((v) => v.verdict === "unknown");
  const notes = [
    ...down.map((v) => clean(`${v.host} lists ${v.component} as ${v.status}; this run is skipped`)),
    ...slow.map((v) => clean(`${v.host} lists ${v.component} as ${v.status}; the gate lets this run proceed`)),
    ...unknown.map((v) => clean(`${v.reason}; the gate fails open for it`)),
  ];
  if (down.length > 0) {
    return { degraded: "true", reason: clean(down.map((v) => `${v.component} ${v.status}`).join(", ")), notes };
  }
  return { degraded: "false", reason: unknown.length > 0 ? "unknown" : "ok", notes };
}

async function main() {
  const result = await checkUpstreamStatus();
  writeOutputs({ degraded: result.degraded, reason: result.reason });
  for (const note of result.notes) {
    console.log(`::notice::upstream status: ${note}`);
  }
  console.log(`check-upstream-status: degraded=${result.degraded} reason=${result.reason}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
