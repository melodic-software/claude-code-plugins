// select-model-credential: which leg of a Claude model lane runs, for every
// lane. The chain is the role's API key, then its subscription token, then the
// central fallback token, each leg its own job. One action answers every
// question along it, so no lane writes its own presence check, skip handling
// or leg condition:
//
//   start   Before the key leg, in a job with actions: read and no secret:
//           reads the key's credit history (check-key-credit gate.cjs, its
//           one or two artifact-list calls) and names the first leg,
//           `subscription` when a credit stop in the window holds the key
//           off, else `key`.
//   leg     First in each leg job (key, subscription or fallback): whether
//           this leg's model runs (`present`), whether a fallback leg can
//           take a handoff (`fallback-ready`, for run-claude-cli), and why
//           this leg runs instead of the one before (`fallback-reason`). A
//           key leg in a job that already holds actions: read may read the
//           credit history here instead of in a start job (key-job set).
//   next    Last in each leg job, given the leg's `state` and the launcher's
//           handoff: the leg the next job runs (`next-leg`) and why
//           (`next-reason`). The next job's `if:` compares next-leg to its
//           own leg and nothing else.
//
// The rules, in one place:
//   - The key runs when it is set, the start call or the inline read did not
//     hold it off, and key-off is not `true`. Otherwise the subscription job
//     runs, for `credit-stop` when the credit history held the key off, else
//     `no-key`.
//   - The subscription token runs when it is set. When it is empty the
//     fallback job runs if the fallback token is set (`no-key`).
//   - The fallback token runs when it is set; nothing follows it.
//   - A leg that ran hands on only when run-claude-cli's handoff is `true`,
//     for its handoff-reason (key: credit-stop or auth; subscription:
//     limit-stop, credit-stop or auth, only with fallback-ready).
//   - A leg that never decided (its first call skipped) hands on nothing.
//
// Secrets never reach this action: the caller passes only whether each is
// set (`secrets.X != ''`), so no secret value leaves its step. Every reason
// is checked against report-lane-outcome's closed list, and a forged or
// unknown value becomes empty. Any failure of the credit-history read runs
// the key, as check-key-credit does on its own.
"use strict";

const fs = require("node:fs");
const gate = require("../check-key-credit/gate.cjs");
const { FALLBACK_REASONS } = require("../report-lane-outcome/classify.cjs");
const { FALLBACK_SECRET } = require("../run-claude-cli/lane.cjs");

const NEXT = { key: "subscription", subscription: "fallback", fallback: "" };
// The reasons a launcher handoff can carry, per leg (run-claude-cli
// lane.cjs handoffReason).
const HANDOFF_REASONS = {
  key: ["credit-stop", "auth"],
  subscription: ["limit-stop", "credit-stop", "auth"],
  fallback: [],
};
const ROLE = /^[a-z][a-z0-9-]{0,39}$/u;

// The secret a leg reads, named as run-claude-cli names it.
function secretName(role, leg) {
  if (leg === "fallback") return FALLBACK_SECRET;
  const prefix = role.toUpperCase().replaceAll("-", "_");
  return `${prefix}_${leg === "key" ? "CLAUDE_API_KEY" : "CLAUDE_CODE_OAUTH_TOKEN"}`;
}

// Exactly `true`: a padded or other-case value is not.
const isTrue = (value) => String(value ?? "") === "true";

// A reason from a closed list, or "".
function reasonOf(value, allowed = FALLBACK_REASONS) {
  const text = String(value ?? "").trim();
  return allowed.includes(text) ? text : "";
}

// The next job's leg and why; empty hands on nothing.
const handOn = (nextLeg = "", nextReason = "") => ({
  "next-leg": nextLeg,
  "next-reason": nextReason,
});

// The first leg, from a credit-history verdict (null when not read).
function start({ skipKey }) {
  return skipKey ? handOn("subscription", "credit-stop") : handOn("key");
}

// A leg job's own decision, from the inputs as the action receives them
// (`true` and nothing else is set). The key is held off when the start
// call `selected` the subscription leg, or the inline credit read did
// (`held`).
function leg({ leg, role, selected = "", held = false, reason = "", ...flags }) {
  const credentialSet = isTrue(flags.credentialSet);
  const fallbackSet = isTrue(flags.fallbackSet);
  const keyOff = isTrue(flags.keyOff);
  const name = secretName(role, leg);
  const keySkipped =
    leg === "key" && (held === true || String(selected).trim() === "subscription");
  const off = leg === "key" && !held && keyOff;
  const present = credentialSet && !keySkipped && !off;
  const outputs = {
    present: String(present),
    "fallback-ready": String(fallbackSet),
    "key-skipped": String(keySkipped),
    "fallback-reason": leg === "key" ? "" : reasonOf(reason),
    "secret-name": name,
    state: JSON.stringify({
      leg,
      present,
      "key-skipped": keySkipped,
      "fallback-ready": fallbackSet,
    }),
  };
  let line;
  if (keySkipped) {
    line = `::notice::${name}'s last credit stop is inside the key-credit window; the subscription job runs.`;
  } else if (off) {
    line = `::warning::key-off is true, so ${name} is held off; the subscription job runs.`;
  } else if (!credentialSet) {
    line = `::warning::${name} is empty; this job's model does not run.`;
  } else {
    line = `select-model-credential: the ${leg} leg runs on ${name}.`;
  }
  return { outputs, lines: [line] };
}

// The leg the next job runs, from this leg's state and the launcher's
// handoff. An unreadable state hands on nothing.
function next({ state, handoff, handoffReason }) {
  let parsed;
  try {
    parsed = JSON.parse(String(state ?? ""));
  } catch {
    parsed = null;
  }
  const leg = parsed?.leg;
  if (!Object.hasOwn(NEXT, leg) || typeof parsed.present !== "boolean") {
    return handOn();
  }
  const following = NEXT[leg];
  if (following === "") return handOn();
  if (!parsed.present) {
    if (leg === "key") {
      return handOn(
        following,
        parsed["key-skipped"] === true ? "credit-stop" : "no-key",
      );
    }
    return parsed["fallback-ready"] === true
      ? handOn(following, "no-key")
      : handOn();
  }
  const reason = reasonOf(handoffReason, HANDOFF_REASONS[leg]);
  return isTrue(handoff) && reason !== "" ? handOn(following, reason) : handOn();
}

// Reads the key's credit history through check-key-credit and returns
// whether it holds the key off. Its own outputs (skip-key, origin-run,
// marker, probing-marker) go to GITHUB_OUTPUT unchanged; any failure runs
// the key. With a role the markers carry the key's secret name, so every
// job on that key shares them; without one, the workflow and key job.
async function readCredit(env, lines, fetchImpl, now) {
  try {
    const role = String(env.INPUT_ROLE ?? "").trim();
    const { verdict, lines: gateLines } = await gate.main(
      {
        ...env,
        KEY_JOB: env.INPUT_KEY_JOB ?? "",
        KEY_SECRET: ROLE.test(role) ? secretName(role, "key") : "",
        WINDOW_HOURS: env.INPUT_WINDOW_HOURS ?? "",
        PROBE_MINUTES: env.INPUT_PROBE_MINUTES ?? "",
        RESET_AT: env.INPUT_RESET_AT ?? "",
      },
      fetchImpl,
      now,
    );
    lines.push(...gateLines);
    return verdict.skip === true;
  } catch {
    lines.push("select-model-credential: the credit history was not read; the key runs");
    return false;
  }
}

function writeOutputs(env, outputs) {
  if (!env.GITHUB_OUTPUT) return;
  fs.appendFileSync(
    env.GITHUB_OUTPUT,
    Object.entries(outputs)
      .map(([key, value]) => `${key}=${value}\n`)
      .join(""),
  );
}

async function main(env = process.env, fetchImpl = globalThis.fetch, now = () => new Date()) {
  const lines = [];
  const mode = String(env.INPUT_LEG ?? "").trim();
  const state = String(env.INPUT_STATE ?? "").trim();
  let outputs;
  // No leg is the call after the model. Its state is empty when the leg's
  // first call was skipped (pr-review-cli's scope step skipped the review),
  // which hands on nothing, as before; next() reads it so.
  if (mode === "") {
    outputs = next({
      state,
      handoff: env.INPUT_HANDOFF,
      handoffReason: env.INPUT_HANDOFF_REASON,
    });
    lines.push(
      outputs["next-leg"] === ""
        ? "select-model-credential: no next leg"
        : `select-model-credential: the ${outputs["next-leg"]} job runs next (${outputs["next-reason"]})`,
    );
  } else if (mode === "start") {
    outputs = start({ skipKey: await readCredit(env, lines, fetchImpl, now) });
  } else if (Object.hasOwn(NEXT, mode)) {
    const role = String(env.INPUT_ROLE ?? "").trim();
    if (!ROLE.test(role)) {
      throw new Error(`role ${JSON.stringify(role)} is not a lower-case kebab role name`);
    }
    const selected = String(env.INPUT_SELECTED ?? "").trim();
    let held = false;
    if (mode === "key" && selected !== "subscription" && String(env.INPUT_KEY_JOB ?? "").trim() !== "") {
      held = await readCredit(env, lines, fetchImpl, now);
    }
    const decided = leg({
      leg: mode,
      role,
      selected,
      credentialSet: env.INPUT_CREDENTIAL_SET,
      fallbackSet: env.INPUT_FALLBACK_SET,
      keyOff: env.INPUT_KEY_OFF,
      held,
      reason: env.INPUT_REASON,
    });
    outputs = decided.outputs;
    lines.push(...decided.lines);
  } else {
    throw new Error(`leg ${JSON.stringify(mode)} is not start, key, subscription or fallback`);
  }
  writeOutputs(env, outputs);
  return { outputs, lines };
}

if (require.main === module) {
  main()
    .then(({ lines }) => process.stdout.write(`${lines.join("\n")}\n`))
    .catch((error) => {
      process.stdout.write(`::error title=select-model-credential::${error.message}\n`);
      process.exitCode = 1;
    });
}

module.exports = { HANDOFF_REASONS, leg, main, next, secretName, start };
