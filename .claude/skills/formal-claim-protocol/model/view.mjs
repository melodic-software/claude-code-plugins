const words = {
  idle: "Not started",
  assigned: "Assigned itself",
  checked: "No other assignee",
  posted: "Lease posted",
  won: "Holds the item",
  lost: "Backed off",
  released: "Released",
};

const lane = (v) =>
  v.runDone && v.pc.lane !== "idle" ? "Run ended" : words[v.pc.lane];

export const title = "One issue claimed by a local session, the issue lane and triage";

export const state = (v) => ({
  "Local session": words[v.pc.local],
  "Issue lane": lane(v),
  Triage: words[v.pc.triage],
});

const steps = {
  Assign: "assigns itself",
  CheckAssignees: "reads the assignees",
  Post: "posts its lease",
  Arbitrate: "reads the leases",
  Release: "finishes and releases",
  RunCompletes: "the lane's run ends",
  Expire: "a lease runs out",
  Finished: null,
};

export const step = (action) => steps[action] ?? action;
