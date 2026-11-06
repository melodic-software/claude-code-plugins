// pr-refine.yml's record-passes job: one refine-pass notice per planned pass,
// and a refine-failed warning for each failed one, which monitor signal 13
// counts as a pr-refine hold (signals.mjs HOLD_NOTICES). The reason is a
// closed set, a job name and its result or `unwired`, so the finding's
// fingerprint stays put.
import { pathToFileURL } from "node:url";

const FAILED = new Set(["failure", "cancelled"]);

// One pass's outcome from its jobs' results ({ job: result }), and its push
// job's pushed commit and skip reason; null results mean the workflow has no
// jobs for the pass.
export function passOutcome({ results, pushedCommit = "", skipReason = "" }) {
  if (results === null) return { outcome: "failed", reason: "unwired" };
  const failed = Object.entries(results).find(([, result]) => FAILED.has(result));
  if (failed) return { outcome: "failed", reason: `${failed[0]}-${failed[1]}` };
  if (pushedCommit !== "") return { outcome: "pushed", reason: null };
  if (skipReason === "superseded-sha") return { outcome: "superseded", reason: null };
  return { outcome: "none", reason: null };
}

// The workflow-command lines for every planned pass, in plan order.
export function passRecords({ passes, files, seconds, wiring }) {
  return passes.flatMap((pass) => {
    const { outcome, reason } = passOutcome(wiring(pass));
    const lines = [`::notice title=refine-pass::pass=${pass} files=${files[pass] ?? 0} outcome=${outcome} seconds=${seconds}`];
    if (reason !== null) lines.push(`::warning title=refine-failed::pass=${pass} reason=${reason}`);
    return lines;
  });
}

// A pass's env prefix: fix-docs reads FIX_DOCS_RESULTS, FIX_DOCS_PUSHED and
// FIX_DOCS_SKIP.
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
  for (const line of passRecords({ passes: JSON.parse(env.PASSES || "[]"), files: JSON.parse(env.FILES || "{}"), seconds, wiring })) {
    console.log(line);
  }
}
