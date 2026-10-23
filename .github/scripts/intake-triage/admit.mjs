// admit.mjs: after apply-verdict set `status: ready`, adds `agent-ready` as
// the lanes App when the issue meets #9212's admission criteria (owner
// decision Q51), and the issue lane's caps have room. No model. The rules come
// from the default branch's .github/actions/resolve-config/admission-rules.json.
//
// Criteria 1, 5 and 6 (exact intent, no very-high security risk, no charge)
// are already in `status: ready`: apply-verdict withholds it on any flag
// (triage flags security only for a very-high risk) or a hold label, and the
// cost rule adds needs-human. Criterion 4 (no protected path named) is not
// applied. This checks the rest:
//
// - 2: the Issue Type is in `types`, or in `types-under-parent` under an open
//   parent issue a listed human filed that awaits no decision;
// - 3: the class, Size and Uncertainty apply-verdict wrote are in `classes`,
//   `sizes` and `uncertainty`;
// - 7: the body has a `task-list` line, the criteria the lane checks;
// - 8: no `refuse-labels` label, every blocker a merged pull request or an
//   issue closed as completed by a listed human or a merge here (the close
//   work-unblock counts), and no open pull request in this repository names
//   the issue;
// - 9: the author is a listed human or the lanes App;
// - lane-runnable done-when: no task-list item asks for what an unattended
//   lane run cannot do (unrunnableCriteria below): a run on a named host or
//   OS, a paid eval, a run repeated N times, a measurement over time, or a
//   page on a host outside resolve-issue's web-access domains. The refusal
//   recommends splitting those items into a needs-human child issue;
// - 10: check-wip-cap's status: over the queued cap, or with the lane paused
//   over the WIP or held cap (from wip.pause-from), the issue gets
//   `admission-deferred`, which work-unblock's hourly sweep admits once there
//   is room.
//
// A refusal a person must settle swaps `status: ready` for
// `status: needs-decision`; a blocker or an open pull request keeps
// `status: ready`. Either way one App comment carrying ADMIT_MARKER says why.
// An open pull request also adds `admission-deferred`: work-unblock's sweep
// skips the issue while such a pull request is open and admits it once none
// is. An issue that waits only on a blocker loses `admission-deferred`, and
// work-unblock admits it when its blocker closes. A refused issue loses it
// too, so the sweep, which does not read these rules, cannot admit it. An
// issue already agent-ready, or whose agent-ready was ever removed, is left
// alone. Issue text can only
// refuse: it never satisfies a criterion the fields, labels or API decide.
import { readFileSync } from "node:fs";

import { isTrustedClose, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const AGENT_READY = "agent-ready";
export const DEFERRED = "admission-deferred";
export const ADMIT_MARKER = "<!-- intake-triage admission -->";
const READY = "status: ready";
const NEEDS_DECISION = "status: needs-decision";
const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";
const PARENT_HOLDS = new Set(["needs-human", "needs-owner-decision", NEEDS_DECISION]);
const LISTS = ["types", "types-under-parent", "classes", "sizes", "uncertainty", "refuse-labels"];

// The rules file, each list checked to hold strings.
export function loadRules(path) {
  const rules = JSON.parse(readFileSync(path, "utf8"));
  for (const key of LISTS) {
    if (!Array.isArray(rules?.[key]) || !rules[key].every((item) => typeof item === "string" && item !== "")) {
      throw new Error(`${path}: \`${key}\` must be a list of strings`);
    }
  }
  if (typeof rules["task-list"] !== "string" || rules["task-list"] === "") {
    throw new Error(`${path}: \`task-list\` must be a string`);
  }
  return rules;
}

const here = (url, repository) =>
  String(url ?? "")
    .toLowerCase()
    .endsWith(`/repos/${repository}`.toLowerCase());

// The open pull requests in `repository` an issue's timeline says reference it.
export const openPullsNaming = (timeline, repository) =>
  timeline
    .map((event) => (event?.event === "cross-referenced" ? event.source?.issue : null))
    .filter((source) => source?.pull_request && source.state === "open" && here(source.repository_url, repository))
    .map((source) => source.number);

// Done-when items an unattended lane run cannot perform. Each pattern needs
// an action or a place within one clause of its subject, so an item that only
// names a host, a threshold or a retention period passes.
const N = String.raw`(?:\d+|two|three|four|five|seven|ten|fourteen|twenty|thirty|fifty|hundred)`;
const UNIT = String.raw`(?:hours?|days?|weeks?|months?|nights?)`;
const UNRUNNABLE = [
  [
    "a run on a host the lane is not",
    /\b(?:on|from|in) (?:a |an |the |another |each )?(?:windows(?: 1[01])?|macos|mac|wsl2?|fleet|physical|desktop|remote|attended) (?:host|machine|workstation|laptop|desktop|box|vm)s?\b/i,
  ],
  [
    "a paid eval",
    /\b(?:run|execute|launch|start)\b[^,;:]{0,40}\b(?:paid evals?|claude plugin eval\b(?![^,;:]*\b(?:validate|dry[- ]run|no-spend)\b))/i,
  ],
  [
    "a repeated run",
    new RegExp(
      String.raw`\b(?:run|execute|repeat|pass(?:es)?|succeed|complete)\b[^,;:]{0,40}\b${N} (?:consecutive|successive|back-to-back|repeated|loaded|parallel) (?:runs?|passes|iterations|sessions|times)\b|\b${N} (?:consecutive|successive|back-to-back|repeated|loaded|parallel) (?:runs?|passes|iterations|sessions) (?:pass|succeed|complete|show|report)`,
      "i",
    ),
  ],
  [
    "a measurement over time",
    {
      // An observation window, not a duration the lane can read from config:
      // an expiry or retention period passes.
      window: new RegExp(
        [
          String.raw`\b(?:for|over|across|during) the (?:next|following|coming) (?:${N} )?${UNIT}\b`,
          String.raw`\b(?:measure|observe|monitor|watch|track)\b[^,;:]{0,60}\b(?:for|over|across|during) (?:a |an |one |${N} )?${UNIT}\b`,
          String.raw`\b(?:measure|observe|monitor|watch|track|confirm|verify|check)\b[^,;:]{0,60}\bafter (?:a |an |one |${N} )?${UNIT} (?:of (?:use|running|runs|operation|traffic)|that)\b`,
        ].join("|"),
        "i",
      ),
      retention: /\b(?:expir\w*|keeps?|kept|retain\w*|retention|older than|ttl)\b/i,
      test(text) {
        return this.window.test(text) && !this.retention.test(text);
      },
    },
  ],
];
// The lane can always reach these; a page elsewhere needs resolve-issue's
// web access.
const GITHUB_HOSTS = ["github.com", "api.github.com", "localhost", "127.0.0.1"];
// An item reads a page only when its clause asks to open or compare against it,
// not when it names a URL as text to edit.
const READS_PAGE = /\b(?:read|fetch|open|visit|load|browse|check|confirm|verify|match(?:es)?|compare|against|according|shows?|says|lists?)\b/i;
const allowedBy = (hosts) => (host) =>
  hosts.some((entry) => (entry.startsWith("*.") ? host.endsWith(entry.slice(1)) : host === entry));
// Backtick-free, mention-free, at most 80 characters: issue text
// quoted back into an App comment.
const excerpt = (text) => {
  const plain = text.replaceAll("`", "").replaceAll("@", "@\u200b").trim();
  return plain.length > 80 ? `${plain.slice(0, 77)}...` : plain;
};

// [{n, kind, text}] for each task-list item (1-based n) the lane cannot
// perform. `webHosts` is resolve-issue's web-access domains: "any" skips the
// URL check, an absent list allows only GitHub and local hosts, and a `*.`
// entry allows that domain's subdomains. Pure.
export function unrunnableCriteria(body, taskList, webHosts) {
  const allowed = webHosts === "any" ? null : allowedBy([...GITHUB_HOSTS, ...(Array.isArray(webHosts) ? webHosts : [])].map((h) => h.toLowerCase()));
  const items = String(body ?? "")
    .split("\n")
    .map((line) => line.trimStart())
    .filter((line) => line.startsWith(taskList))
    .map((line) => line.slice(taskList.length));
  const found = [];
  items.forEach((text, index) => {
    let kind = UNRUNNABLE.find(([, pattern]) => pattern.test(text))?.[0];
    if (!kind && allowed) {
      // Clauses split on , ; and a colon that does not start ://.
      const outside = text
        .split(/[,;]|:(?!\/\/)/)
        .filter((clause) => READS_PAGE.test(clause))
        .flatMap((clause) => [...clause.matchAll(/\bhttps?:\/\/([a-z0-9.-]+)/gi)].map((m) => m[1].toLowerCase().replace(/\.+$/, "")))
        .find((host) => !allowed(host));
      if (outside) {
        kind = `a page on ${outside}, outside the lane's web hosts`;
      }
    }
    if (kind) {
      found.push({ n: index + 1, kind, text: excerpt(text) });
    }
  });
  return { items: items.length, found };
}

// The refusal reason for unrunnableCriteria's result, with the split it
// recommends, or null when every item is runnable.
export function unrunnableReason({ items, found }) {
  if (found.length === 0) {
    return null;
  }
  const list = found.map(({ n, kind, text }) => `item ${n} (${kind}: "${text}")`).join(", ");
  const split =
    found.length === items
      ? "no done-when item is left for the lane, so a person takes the issue"
      : "recommended split: keep the other items here as the admissible issue and move these to a needs-human child issue";
  return `its done-when asks for what an unattended lane run cannot perform: ${list}; ${split}`;
}

const names = (labels) => (labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));

// {verdict: admit | refuse | wait | skip, reasons}. Pure.
export function decide({ issue, verdict, rules, parent, blockers, trustedCloses, timeline, events, humans, appId, repository, webHosts }) {
  const labels = names(issue.labels);
  if (!labels.includes(READY)) {
    return { verdict: "skip", reasons: [`no ${READY}`] };
  }
  if (labels.includes(AGENT_READY)) {
    return { verdict: "skip", reasons: [`already ${AGENT_READY}`] };
  }
  if (events.some((event) => event?.event === "unlabeled" && event.label?.name === AGENT_READY)) {
    return { verdict: "skip", reasons: [`${AGENT_READY} was removed before`] };
  }

  const refuse = [];
  const author = issue.user?.id;
  if (!(humans.has(author) || (appId !== undefined && author === appId))) {
    refuse.push("the author is neither a listed human nor the lanes App");
  }
  const type = issue.type?.name ?? "none";
  if (rules["types-under-parent"].includes(type)) {
    const parentOk =
      parent !== null && parent.state === "open" && humans.has(parent.user?.id) && !names(parent.labels).some((label) => PARENT_HOLDS.has(label));
    if (!parentOk) {
      refuse.push(`a ${type} needs an open parent issue a listed human filed that awaits no decision`);
    }
  } else if (!rules.types.includes(type)) {
    refuse.push(`type ${type} is not one of ${[...rules.types, ...rules["types-under-parent"]].join(", ")}`);
  }
  if (!rules.classes.includes(verdict.workClass)) {
    refuse.push(`${verdict.workClass} is not one of ${rules.classes.join(", ")}`);
  }
  if (!rules.sizes.includes(verdict.dimensions?.size)) {
    refuse.push(`Size ${verdict.dimensions?.size} is not one of ${rules.sizes.join(", ")}`);
  }
  if (!rules.uncertainty.includes(verdict.dimensions?.uncertainty)) {
    refuse.push(`Uncertainty ${verdict.dimensions?.uncertainty} is not one of ${rules.uncertainty.join(", ")}`);
  }
  const lines = String(issue.body ?? "").split("\n");
  if (!lines.some((line) => line.trimStart().startsWith(rules["task-list"]))) {
    refuse.push(`it has no \`${rules["task-list"]}\` task list to check`);
  }
  const unrunnable = unrunnableReason(unrunnableCriteria(issue.body, rules["task-list"], webHosts));
  if (unrunnable) {
    refuse.push(unrunnable);
  }
  for (const label of rules["refuse-labels"]) {
    if (labels.includes(label)) {
      refuse.push(`it carries ${label}`);
    }
  }
  if (refuse.length > 0) {
    return { verdict: "refuse", reasons: refuse };
  }

  const wait = [];
  for (const blocker of blockers) {
    const done =
      blocker.state === "closed" &&
      here(blocker.repository_url, repository) &&
      (blocker.pull_request
        ? Boolean(blocker.pull_request.merged_at)
        : blocker.state_reason === "completed" && trustedCloses.has(blocker.number));
    if (!done) {
      wait.push(`blocker #${blocker.number} is not closed as completed by a listed human or a merge`);
    }
  }
  const pulls = openPullsNaming(timeline, repository);
  for (const pull of pulls) {
    wait.push(`open pull request #${pull} names it`);
  }
  if (wait.length > 0) {
    return { verdict: "wait", reasons: wait, pulls };
  }
  return { verdict: "admit", reasons: [] };
}

async function parentOf(github, base) {
  try {
    return await github("GET", `${base}/parent`);
  } catch (error) {
    if (error?.status === 404) {
      return null;
    }
    throw error;
  }
}

// One App comment carrying ADMIT_MARKER, edited in place on a later run.
async function sayWhy(github, repository, base, text) {
  const body = `${ADMIT_MARKER}\n${text}`;
  const own = (await paginate(github, `${base}/comments`)).find(
    (comment) => comment.user?.login === LANES_APP_LOGIN && String(comment.body ?? "").startsWith(ADMIT_MARKER),
  );
  if (own) {
    await github("PATCH", `/repos/${repository}/issues/comments/${own.id}`, {
      body,
    });
  } else {
    await github("POST", `${base}/comments`, { body });
  }
}

// For an issue apply-verdict held without admission (a flag, an escalation or
// a hold), the same split note a refusal posts, when a done-when item is one
// the lane cannot perform, so the split survives a verdict that never reaches
// decide(). Returns {outcome: noted | none, reasons}.
export async function noteUnrunnable({ github, repository, number, body, rules, webHosts, log = console.log }) {
  const reason = unrunnableReason(unrunnableCriteria(body, rules["task-list"], webHosts));
  if (!reason) {
    return { outcome: "none", reasons: [] };
  }
  await sayWhy(github, repository, `/repos/${repository}/issues/${number}`, `Not admitted to the issue lane: ${reason}.`);
  log(`admit: #${number} held; split noted (${reason})`);
  return { outcome: "noted", reasons: [reason] };
}

// Reads the issue fresh, decides, and writes. `status` answers check-wip-cap's
// status for the issue lane. Returns {outcome, reasons}.
export async function admit({ github, repository, number, verdict, rules, humans, appId, status, webHosts, log = console.log }) {
  const base = `/repos/${repository}/issues/${number}`;
  const issue = await github("GET", base);
  const blockers = await paginate(github, `${base}/dependencies/blocked_by`);
  // Anyone may close their own issue as completed, so a blocking issue counts
  // only with a trusted close, read fresh from the issue.
  const trustedCloses = new Set();
  for (const blocker of blockers) {
    if (!blocker.pull_request && blocker.state === "closed" && blocker.state_reason === "completed" && here(blocker.repository_url, repository)) {
      if (await isTrustedClose(github, repository, await github("GET", `/repos/${repository}/issues/${blocker.number}`), humans)) {
        trustedCloses.add(blocker.number);
      }
    }
  }
  const decision = decide({
    issue,
    verdict,
    rules,
    parent: rules["types-under-parent"].includes(issue.type?.name) ? await parentOf(github, base) : null,
    blockers,
    trustedCloses,
    timeline: await paginate(github, `${base}/timeline`),
    events: await paginate(github, `${base}/events`),
    humans,
    appId,
    repository,
    webHosts,
  });
  const reasons = decision.reasons.join("; ");
  const undefer = async () => {
    if (names(issue.labels).includes(DEFERRED)) {
      await github("DELETE", `${base}/labels/${DEFERRED}`);
    }
  };
  if (decision.verdict === "skip") {
    log(`admit: #${number} left as is (${reasons})`);
    return { outcome: "skipped", reasons: decision.reasons };
  }
  if (decision.verdict === "refuse") {
    await github("DELETE", `${base}/labels/${encodeURIComponent(READY)}`);
    await github("POST", `${base}/labels`, { labels: [NEEDS_DECISION] });
    await undefer();
    await sayWhy(
      github,
      repository,
      base,
      `Not admitted to the issue lane: ${reasons}. A recorded decision does not change these rules (\`.github/actions/resolve-config/admission-rules.json\`); a person who wants it worked adds \`agent-ready\`.`,
    );
    log(`admit: #${number} refused (${reasons})`);
    return { outcome: "refused", reasons: decision.reasons };
  }
  if (decision.verdict === "wait") {
    if (decision.pulls.length === 0) {
      await undefer();
    } else if (!names(issue.labels).includes(DEFERRED)) {
      await github("POST", `${base}/labels`, { labels: [DEFERRED] });
    }
    await sayWhy(github, repository, base, `Not admitted to the issue lane yet: ${reasons}.`);
    log(`admit: #${number} waits (${reasons})`);
    return { outcome: "waiting", reasons: decision.reasons };
  }
  const s = await status();
  if (s.paused || !s.admission_open || (s.admission_room ?? 1) <= 0) {
    await github("POST", `${base}/labels`, { labels: [DEFERRED] });
    const why = s.paused ? `the lane is paused (${s.pause_reason})` : `admissions are closed (${s.admission_reason})`;
    log(`admit: #${number} deferred: ${why}`);
    return { outcome: "deferred", reasons: [why] };
  }
  await github("POST", `${base}/labels`, { labels: [AGENT_READY] });
  log(`admit: #${number} labeled ${AGENT_READY}`);
  return { outcome: "admitted", reasons: [] };
}
