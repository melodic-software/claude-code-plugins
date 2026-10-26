// The judge's per-unit handoff between its legs: key, subscription, fallback.
// A matrix job's outputs are not per unit, so a leg that hands its unit on
// uploads a marker artifact, and a route job with no secret turns the markers
// into the next leg's matrix. Each marker is one file named for its leg and
// unit, downloaded with merge-multiple into one flat directory: without it,
// download-artifact puts a lone match's files straight into the path and
// several matches each in its own directory. Every value is checked against a closed set: a
// marker names a collector unit id and a handoff reason run-claude-cli set
// after it restored the step files, so the model cannot set either.
//
//   record     LEG, UNIT, REASON, HANDOFF_DIR: writes HANDOFF_DIR/<prefix><unit>.json
//   check-leg  LOG_FILE, GITHUB_OUTPUT: clean=true when the leg hit no denial
//   route      LEG, HANDOFF_DIR, GITHUB_OUTPUT: matrix and count for the next leg
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

export const UNIT = /^[acd][1-8]$/;
// What each leg may hand on with: run-claude-cli's handoff-reason, and for
// the key leg an empty key as well.
export const REASONS = {
  key: ["credit-stop", "auth", "no-key"],
  subscription: ["limit-stop", "credit-stop", "auth"],
};
// The artifact and file name each leg's marker uploads under, before the
// unit; the route job downloads by it.
export const PREFIX = { key: "judge-handoff-", subscription: "judge-subscription-handoff-" };

const legOf = (leg) => {
  if (!Object.hasOwn(REASONS, leg)) throw new Error(`leg '${leg}' is not key or subscription`);
  return leg;
};

export function marker(leg, unit, reason) {
  if (!UNIT.test(unit ?? "")) throw new Error(`unit '${unit}' is not a collector id`);
  if (!REASONS[legOf(leg)].includes(reason)) throw new Error(`reason '${reason}' is not a ${leg} handoff reason`);
  return { unit, reason };
}

// run-claude-cli's log, one object per leg, counts the leg's denials. A leg
// that reached past its rules gets no second attempt on another credential.
export function denials(logText) {
  return logText
    .split("\n")
    .filter((line) => line.trim() !== "")
    .reduce((sum, line) => sum + (JSON.parse(line)?.denials?.count ?? 0), 0);
}

export const markerName = (leg, unit) => `${PREFIX[legOf(leg)]}${unit}.json`;

// The next leg's matrix from the downloaded markers, one file each. A file
// that is not a marker, or names another unit than its own, fails the route.
export function route(leg, dir) {
  const prefix = PREFIX[legOf(leg)];
  const include = [];
  for (const name of existsSync(dir) ? readdirSync(dir).sort() : []) {
    if (!name.startsWith(prefix) || !name.endsWith(".json")) throw new Error(`'${name}' is not a ${leg} handoff marker`);
    const { unit, reason } = JSON.parse(readFileSync(join(dir, name), "utf8"));
    if (markerName(leg, unit) !== name) throw new Error(`marker '${name}' holds unit '${unit}'`);
    include.push(marker(leg, unit, reason));
  }
  return { include };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const env = process.env;
  try {
    switch (process.argv[2]) {
      case "record": {
        const record = marker(env.LEG, env.UNIT, env.REASON);
        mkdirSync(env.HANDOFF_DIR, { recursive: true });
        writeFileSync(join(env.HANDOFF_DIR, markerName(env.LEG, record.unit)), `${JSON.stringify(record)}\n`);
        console.log(`handoff: unit ${record.unit} handed on (${record.reason})`);
        break;
      }
      case "check-leg": {
        let logText;
        try {
          logText = readFileSync(env.LOG_FILE, "utf8");
        } catch {
          throw new Error("the leg's log is unreadable");
        }
        const count = denials(logText);
        if (count > 0) throw new Error(`the leg hit ${count} permission denial(s); nothing is handed on`);
        appendFileSync(env.GITHUB_OUTPUT, "clean=true\n");
        break;
      }
      case "route": {
        const matrix = route(env.LEG, env.HANDOFF_DIR);
        appendFileSync(env.GITHUB_OUTPUT, `matrix=${JSON.stringify(matrix)}\ncount=${matrix.include.length}\n`);
        console.log(`handoff: ${matrix.include.length} unit(s) for the next leg`);
        break;
      }
      default:
        throw new Error(`unknown command '${process.argv[2]}'`);
    }
  } catch (error) {
    console.log(`::error::${error.message}`);
    process.exitCode = 1;
  }
}
