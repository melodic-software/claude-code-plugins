// Pure check-run decision for a pipeline activity. Lane, activity, run result,
// act outcome, gate reason, head SHA and the signed-commit result are the
// report job's own inputs or the run job's runner-computed outputs. The verdict
// was written after head code ran: it is validated, its lane, activity, gate
// reason and head SHA must match those inputs, and it is never the source of
// the name, the head SHA, the outcome or any text in the check.

const NAME = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/;
const RESERVED_NAME = "ci-status";
const SHA = /^[0-9a-f]{40}$/;
const GATES = ["kill-switch", "trigger"];
const CONFIG = new Set(["valid", "invalid", "not-read"]);
const OUTCOME = new Set(["success", "failure", "skipped", "not-run"]);

const isPlainObject = (value) =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const isGateResult = (gate) =>
  gate == null ||
  (isPlainObject(gate) &&
    typeof gate.proceed === "string" &&
    typeof gate.reason === "string");

// Required fields and their types from contract-spec Verdict.
function isVerdict(verdict) {
  return (
    isPlainObject(verdict) &&
    verdict.version === 1 &&
    typeof verdict.lane === "string" &&
    typeof verdict.activity === "string" &&
    typeof verdict["run-url"] === "string" &&
    isPlainObject(verdict.gates) &&
    GATES.every((name) => isGateResult(verdict.gates[name])) &&
    CONFIG.has(verdict.config) &&
    OUTCOME.has(verdict.outcome) &&
    (verdict["skip-reason"] == null ||
      typeof verdict["skip-reason"] === "string") &&
    (verdict["head-sha"] == null || typeof verdict["head-sha"] === "string") &&
    (verdict["dirty-tree"] == null ||
      typeof verdict["dirty-tree"] === "boolean")
  );
}

export function decide(verdict, inputs) {
  const { lane, activity, runResult, actOutcome, signedCommits } = inputs;
  const { gateReason, headSha, headShaFallback, prHeadSha } = inputs;
  const { gateSkipReasons, skipReasons } = inputs;
  if (
    ![lane, activity].every(
      (part) => NAME.test(part ?? "") && part !== RESERVED_NAME,
    )
  ) {
    return {
      kind: "refuse",
      why: `lane and activity must be convention names other than ${RESERVED_NAME}`,
    };
  }
  const post = (conclusion, title, summary) => ({
    kind: "post",
    report: {
      name: `${lane} / ${activity}`,
      head_sha: headSha || headShaFallback,
      status: "completed",
      conclusion,
      output: { title, summary },
    },
  });
  const failure = (summary) => post("failure", "Failed", summary);
  // Every neutral passes this one check against the base schema's enum.
  const neutral = (reason) =>
    skipReasons.includes(reason)
      ? post("neutral", `Skipped: ${reason}`, `Skip reason: ${reason}`)
      : failure(
          "The skip reason is not a member of the schema's skip-reason enum.",
        );

  // A job timeout or a manual cancel also reads cancelled; only a newer PR head
  // read at report time shows the run was superseded.
  if (runResult === "cancelled") {
    return SHA.test(prHeadSha ?? "") &&
      prHeadSha !== (headSha || headShaFallback)
      ? neutral("superseded-sha")
      : failure("The run was cancelled and no newer head superseded it.");
  }
  if (verdict == null) {
    return failure("The run left no verdict.");
  }
  if (!isVerdict(verdict)) {
    return failure("The verdict does not match its contract.");
  }
  if (verdict.lane !== lane || verdict.activity !== activity) {
    return failure("The verdict names another lane or activity.");
  }
  const stopped = GATES.map((name) => verdict.gates[name]).find(
    (gate) => gate != null && gate.proceed !== "true",
  );
  if (
    (stopped ? stopped.reason : null) !== (gateReason || null) ||
    (verdict["head-sha"] || null) !== (headSha || null)
  ) {
    return failure(
      "The verdict's gate result or head SHA disagrees with the run job's.",
    );
  }
  if (verdict.config === "invalid") {
    return failure("The pipeline config is invalid.");
  }
  if (gateReason) {
    if (gateReason === "no-pr" && !headSha) {
      return { kind: "none", why: "gate reason no-pr with no head SHA" };
    }
    if (!Object.hasOwn(gateSkipReasons, gateReason)) {
      return failure(
        "A gate stopped the run with a reason that has no skip mapping.",
      );
    }
    return neutral(gateSkipReasons[gateReason]);
  }
  // No skip reason can neutralize these.
  if (signedCommits && signedCommits.all_verified !== true) {
    return failure("A commit on the pull request is not GitHub-verified.");
  }
  if (actOutcome === "failure") {
    return failure("The activity step failed.");
  }
  if (verdict["dirty-tree"] === true) {
    return failure("A read activity left the working tree dirty.");
  }
  // A skip reason counts only in a run job that succeeded, after a script
  // exited 0 with one (success) or when the act step never ran, so no head
  // code wrote the verdict (skipped).
  if (verdict["skip-reason"] != null) {
    return runResult === "success" &&
      (actOutcome === "success" || actOutcome === "skipped")
      ? neutral(verdict["skip-reason"])
      : failure("A skip reason came with an act step that did not finish.");
  }
  if (actOutcome !== "success") {
    return failure(
      "The activity step did not run and no skip reason explains it.",
    );
  }
  if (runResult !== "success") {
    return failure("The run job did not succeed.");
  }
  return post("success", "Passed", "The activity ran and passed.");
}
