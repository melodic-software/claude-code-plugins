// Upstream-status gate for token-spending lanes: skip the run while GitHub
// Actions or npm package installation reports a degraded component, so a lane
// does not spend tokens on a run the incident will fail. Reads each service's
// own component, never the page rollup (component-status.mjs). Fails open: a
// page that cannot be read, or lists no such component, lets the lane proceed.
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { ACTIONS, NPM_INSTALL, readComponents } from "../../scripts/maintenance-reconcile-lost-runs/component-status.mjs";

export const GATED = [ACTIONS, NPM_INSTALL];

// Page text reaches the log and an output: keep one line with no workflow
// command in it.
const clean = (text) => String(text).replace(/[\r\n]+/g, " ").replaceAll("::", ": :");

// { degraded, reason, notes }: degraded is "true" only when a component's
// verdict is degraded; notes are the lines to log, one per component that is
// not operational.
export async function checkUpstreamStatus({ fetchStatus } = {}) {
  const verdicts = await readComponents({ fetchStatus, components: GATED });
  const down = verdicts.filter((v) => v.verdict === "degraded");
  const unknown = verdicts.filter((v) => v.verdict === "unknown");
  const notes = [
    ...down.map((v) => clean(`${v.host} lists ${v.component} as ${v.status}; this run is skipped`)),
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
