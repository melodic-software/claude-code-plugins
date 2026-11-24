import { pathToFileURL } from "node:url";
import { markLaneHold } from "../lib/lane-hold-marker.mjs";

const FAILED = new Set(["failure", "cancelled"]);
const REFINE_FAILED = "::warning title=refine-failed::";

export function passOutcome({ results, pushedCommit = "", skipReason = "" }) {
  if (results === null) return { outcome: "failed", reason: "unwired" };
  const jobs = Object.entries(results);
  const recovered = jobs.findLastIndex(([job, result]) => job.endsWith("-fallback") && result === "success");
  const failed = jobs.slice(recovered + 1).find(([, result]) => FAILED.has(result));
  if (failed) return { outcome: "failed", reason: `${failed[0]}-${failed[1]}` };
  if (pushedCommit !== "") return { outcome: "pushed", reason: null };
  if (skipReason === "superseded-sha") return { outcome: "superseded", reason: null };
  return { outcome: "none", reason: null };
}

export function passRecords({ planResult = "success", passes, files, seconds, wiring }) {
  if (planResult === "failure") return [`${REFINE_FAILED}pass=plan reason=plan-failure`];
  return passes.flatMap((pass) => {
    const { outcome, reason } = passOutcome(wiring(pass));
    const lines = [`::notice title=refine-pass::pass=${pass} files=${files[pass] ?? 0} outcome=${outcome} seconds=${seconds}`];
    if (reason !== null) lines.push(`${REFINE_FAILED}pass=${pass} reason=${reason}`);
    return lines;
  });
}

export const envPrefix = (pass) => pass.toUpperCase().replaceAll("-", "_");

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const env = process.env;
  const started = Number(env.STARTED_AT);
  const seconds = Number.isSafeInteger(started) && started > 0 ? Math.max(0, Math.round(Date.now() / 1000) - started) : "na";
  const wiring = (pass) => {
    const prefix = envPrefix(pass);
    const results = env[`${prefix}_RESULTS`];
    return {
      results: results ? JSON.parse(results) : null,
      pushedCommit: env[`${prefix}_PUSHED`] ?? "",
      skipReason: env[`${prefix}_SKIP`] ?? "",
    };
  };
  for (const line of passRecords({ planResult: env.PLAN_RESULT, passes: JSON.parse(env.PASSES || "[]"), files: JSON.parse(env.FILES || "{}"), seconds, wiring })) {
    console.log(line);
    if (line.startsWith(REFINE_FAILED)) markLaneHold(env);
  }
}
