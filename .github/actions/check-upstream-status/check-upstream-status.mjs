import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { ACTIONS, NPM_INSTALL, readComponents } from "../../scripts/maintenance-reconcile-lost-runs/component-status.mjs";

export const GATED = [ACTIONS, NPM_INSTALL];
export const OUTAGE = new Set(["partial_outage", "major_outage"]);

const clean = (text) => String(text).replace(/[\r\n]+/g, " ").replaceAll("::", ": :");

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
