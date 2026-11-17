const contract = {
  idle: "Not started",
  list: "Checking for a full run",
  read: "Checking for a full run",
  verify: "Checking the recorded verdict",
  decide: "Checking the recorded verdict",
  hold: "Holding for a full run",
  sRead: "Checking the recorded verdict",
  sList: "Checking the recorded verdict",
  sReRead: "Checking the recorded verdict",
  pass: "Passed",
  fail: "Failed",
};

const fullRun = (v, r) => {
  if (v.att[r] === 0) return "Not started";
  if (!v.live[r]) return "Ended";
  if (v.gate[r] === "running") return "Verdict recorded, finishing";
  if (v.gate[r] === "none") return v.mark[r] === "done" ? "Marked in flight" : "Started";
  return "Verdict recorded, finishing";
};

export const title = "One pull request head: full runs record ci-lanes, a label flip carries it";

export const state = (v) => ({
  "Label-flip CI Status": contract[v.cpc],
  "Full run 1": fullRun(v, "run1"),
  "Full run 2": fullRun(v, "run2"),
});

const steps = {
  Start: "a push, reopen or ready flip starts a full run",
  Mark: "mark-lanes records ci-lanes pending",
  MarkFails: "mark-lanes fails",
  Aggregate: "CI Status records the lanes verdict",
  StepEnds: "the verdict step finishes",
  Complete: "the full run ends",
  Cancel: "the full run is cancelled",
  Rerun: "someone re-runs the full run",
  CStart: "a label flip starts CI Status",
  CList: "it lists the runs on the head",
  CRead: "it reads ci-lanes",
  CVerify: "it checks which run wrote the success",
  CDecide: "it decides",
  CHoldEnds: "its hold ends",
  CTimeout: "its wait runs out",
  SRead: "it reads ci-lanes",
  SList: "it lists the runs on the head",
  SReRead: "it reads ci-lanes again",
  Done: null,
};

export const step = (action) => steps[action] ?? action;
