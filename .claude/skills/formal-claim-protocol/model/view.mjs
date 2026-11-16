const fixed = {
  idle: "Not started",
  assigned: "Assigning itself",
  reAssign: "Assigning itself",
  checked2: "Assigning itself",
  checked: "Assigned, no one else",
  posted: "Lease posted",
  lossSup: "Lost, backing off",
  winRead: "Won, checking its assignee",
  winAdd: "Won, checking its assignee",
  held: "Holds the item",
  tSup: "Failed, backing off",
  gLeases: "Handing back its assignee",
  gList: "Handing back its assignee",
  gJudge: "Handing back its assignee",
  gARead: "Handing back its assignee",
  gRm: "Handing back its assignee",
  gRead2: "Handing back its assignee",
  gList2: "Handing back its assignee",
  gJudge2: "Handing back its assignee",
  gAdd: "Handing back its assignee",
  gRead3: "Handing back its assignee",
  gList3: "Handing back its assignee",
  gJudge3: "Handing back its assignee",
  gRm3: "Handing back its assignee",
  renLeases: "Renewing",
  renPatch: "Renewing",
  ren2Leases: "Renewed near expiry, re-checking",
  ren2Judge: "Renewed near expiry, re-checking",
  renSup: "Renew backing off",
  relLeases: "Releasing",
  relJudgeOwn: "Releasing",
  relPatch: "Releasing",
  relSup: "Release outranked, backing off",
  lost: "Backed off",
  failed: "Claim failed",
  dead: "Died backing off",
  released: "Released",
  relFail: "Release refused or failed",
  relDead: "Died releasing",
  gone: "Run ended",
  renLost: "Lost the item on renew",
};

const judging = { claim: "Lease posted", renew: "Renewing", release: "Releasing" };

const word = (v, c) => {
  const pc = v.pc[c];
  if (pc === "arbJudge" || pc === "arbRunRead" || pc === "arbRunSup") return judging[v.ctx[c]];
  return fixed[pc];
};

export const title = "One issue claimed by a local session, the issue lane and triage";

export const state = (v) => ({
  "Local session": word(v, "local"),
  "Issue lane": word(v, "lane"),
  Triage: word(v, "triage"),
});

const who = { local: "the local session", lane: "the issue lane", triage: "triage" };

const steps = {
  Assign: "assigns itself",
  CheckRead: "reads the assignees",
  ReAssign: "assigns itself again",
  PostLease: "posts its lease",
  ReadLeases: "lists the leases",
  ArbJudge: "picks the earliest live lease",
  ArbRunRead: "reads the lane run's status",
  ArbRunSup: "supersedes the completed run's lease",
  LossSup: "supersedes its own lease",
  GLeases: "reads its clock",
  GList: "lists the leases",
  GJudge: "looks for another live lease of its login",
  GARead: "reads the assignees",
  GRm: "removes its assignee",
  GRead2: "reads its clock",
  GList2: "lists the leases",
  GJudge2: "looks for another live lease of its login",
  GAdd: "assigns itself again",
  GRead3: "reads its clock",
  GList3: "lists the leases",
  GJudge3: "looks for another live lease of its login",
  GRm3: "removes its assignee",
  WinRead: "reads the assignees",
  WinAdd: "assigns itself again",
  TrapSup: "supersedes its own lease",
  RenewStart: "starts a renew",
  RenewPatch: "renews its lease",
  Ren2Leases: "lists the leases",
  Ren2Judge: "looks for a newer live lease",
  RenSup: "supersedes its renewed lease",
  ReleaseStart: "starts a release",
  RelJudgeOwn: "judges its own lease",
  RelPatch: "supersedes its lease",
  RelSup: "supersedes its outranked lease",
  Die: "dies, or a call fails",
};

const world = {
  RunCompletes: "the lane's run ends",
  Approach: "a lease comes within 300 s of expiry",
  Expire: "a lease expires",
  Done: null,
};

const actor = (from, to) =>
  Object.keys(who).find((c) => from.pc[c] !== to.pc[c] || from.ctx[c] !== to.ctx[c]);

export const step = (action, from, to) => {
  if (action in world) return world[action];
  const c = actor(from, to);
  const what = steps[action] ?? action;
  return c ? `${who[c]} ${what}` : what;
};
