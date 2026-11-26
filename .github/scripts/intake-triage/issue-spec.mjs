import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { ACTIONS_BOT_ID, REFINE_MARKER } from "../lib/lane-vocabulary.mjs";

export const RECURRING = "recurring";

const LISTS = ["types", "types-under-parent", "types-parent-if-present", "sizes", "uncertainty", "refuse-labels", "cordoned-milestones", "parent-container-labels"];
const OPTIONAL_LISTS = ["parent-container-labels"];

export function loadRules(path) {
  const rules = JSON.parse(readFileSync(path, "utf8"));
  for (const key of OPTIONAL_LISTS) {
    if (rules !== null && typeof rules === "object" && rules[key] === undefined) {
      rules[key] = [];
    }
  }
  for (const key of LISTS) {
    if (!Array.isArray(rules?.[key]) || !rules[key].every((item) => typeof item === "string" && item !== "")) {
      throw new Error(`${path}: \`${key}\` must be a list of strings`);
    }
  }
  if (typeof rules["task-list"] !== "string" || rules["task-list"] === "") {
    throw new Error(`${path}: \`task-list\` must be a string`);
  }
  const own = { ...OWN_AGENT_DEFAULTS, ...(rules["own-agents"] ?? {}) };
  if (!Array.isArray(own.identities) || !own.identities.every((id) => id === LANES_APP_IDENTITY || (Number.isSafeInteger(id) && id > 0 && id !== ACTIONS_BOT_ID))) {
    throw new Error(`${path}: \`own-agents.identities\` must list \`${LANES_APP_IDENTITY}\` or account ids other than github-actions[bot]'s`);
  }
  if (!Number.isSafeInteger(own["source-cap"]) || own["source-cap"] < 1) {
    throw new Error(`${path}: \`own-agents.source-cap\` must be a positive integer`);
  }
  rules["own-agents"] = own;
  return rules;
}

export const LANES_APP_IDENTITY = "lanes-app";
export const OWN_AGENT_DEFAULTS = Object.freeze({ identities: Object.freeze([LANES_APP_IDENTITY]), "source-cap": 5 });

export const ownAgentText = (item, ids) =>
  item?.author?.__typename === "Bot" &&
  ids.has(item.author.databaseId) &&
  (item.lastEditedAt == null || (item.editor?.__typename === "Bot" && item.editor.databaseId === item.author.databaseId));

export const here = (url, repository) =>
  String(url ?? "")
    .toLowerCase()
    .endsWith(`/repos/${repository}`.toLowerCase());

const N = String.raw`(?:\d+|two|three|four|five|seven|ten|fourteen|twenty|thirty|fifty|hundred)`;
const UNIT = String.raw`(?:hours?|days?|weeks?|months?|nights?)`;
const FREE = String.raw`(?![^,;:]*\b(?:validate|dry[- ]run|no-spend)\b)`;
const EVAL_HARNESS = String.raw`(?:\bmeasure-invocation(?!\.test\b)(?!(?:\.sh)?\s+(?:score|compare|emit-plugin-eval)\b)|\/evals:plugin-eval)\b${FREE}`;
export const EVAL_RUN = "a model eval run";
export const PAID_EVAL = "a paid eval";
const BILLED =
  /\b(?:azure|larger(?:[- ][a-z]+){0,3}[- ]runners?|(?:actions|private[- ]repo(?:sitory)?) (?:minutes|storage)|api keys? (?:beyond|outside|past) the (?:promotional )?credits?|paid api keys?|billed api keys?|bedrock|vertex|foundry|aws|amazon|gcp|google cloud|openai|openrouter|claude_code_use_\w+)\b|--provider\b/i;
const EVAL_PATTERN = new RegExp(
  [
    String.raw`\b(?:run|execute|launch|start)\b[^,;:]{0,40}\b(?:paid evals?|claude plugin eval\b${FREE})`,
    String.raw`\b(?:run|execute|launch|start)\b[^,;:]{0,40}${EVAL_HARNESS}`,
    String.raw`${EVAL_HARNESS}[^,;:.]{0,60}\b(?:trigger (?:scores?|rates?)|with and without|deltas?|before and (?:the )?after)\b`,
    String.raw`\bPR body\b[^.;]{0,120}\bbefore and (?:the )?after\b[^.;]{0,60}\b(?:numbers|trigger rates?|scores?)\b`,
  ].join("|"),
  "i",
);
const SCRIPT_NOUN = String.raw`(?:workflow|script|lane|app|hook|skill|action|job|bot|sweep)`;
const CONDITIONAL = /^\s*(?:if|when|whenever|unless|once)\b/i;
const BY_SCRIPT = new RegExp(String.raw`^[^.;]*\bby (?:the )?(?:\S+\.(?:mjs|js|ts|sh|py|ps1)|(?:\S+ )?${SCRIPT_NOUN})\b`, "i");
const EVAL_RULE = "eval";
const UNRUNNABLE = [
  [
    "a run on a host the lane is not",
    /\b(?:on|from|in) (?:a |an |the |another |each )?(?:windows(?: 1[01])?|macos|mac|wsl2?|fleet|physical|desktop|remote|attended) (?:host|machine|workstation|laptop|desktop|box|vm)s?\b/i,
  ],
  [EVAL_RUN, EVAL_PATTERN],
  [
    "a live Claude Code CLI run",
    /\b(?:run|records?|reports? from|output (?:of|from))\b[^,;:]{0,40}\bclaude (?:-p|--print)\b|\bclaude (?:-p|--print)\b[^,;:.]{0,60}\b(?:exits?|prints?)\b|\brun\b[^,;:]{0,40}\bclaude plugin (?:test|install|update|configure)\b|\bclaude plugin (?:test|install|update|configure)\b[^,;:.]{0,60}\b(?:exits?|pass(?:es)?|succeeds?|fails?|prints?|returns?)\b|\b(?:run|records?)\b[^,;:]{0,40}\bheadless (?:claude|Claude Code)\b|\bheadless (?:claude|Claude Code) (?:runs?|sessions?)\b[^,;:.]{0,60}\b(?:exits?|pass(?:es)?|succeeds?|fails?|prints?|returns?)\b|^a recorded probe\b|\b(?:probe|measured result)\b[^.;]{0,80}\bClaude Code version\b|\b(?:on|with) (?:a|the) (?:named|measured|probed) Claude Code version\b/i,
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
  [
    "a comment instead of a file change",
    {
      anchored: /^(?:a|one) comment on this issue (?:with|starting|records?|lists?|holds?|gives?|reports?)\b|(?<!\S[-.]\S*['’]s )\b(?:output|results?|findings?|answers?)\b[^,;:.]{0,20}\b(?:recorded|reported|posted|written|stated) (?:in|as) (?:a|one) comment on this issue\b|^no file is changed\.?\s*$/i,
      posted: new RegExp(
        String.raw`(?:(?<!\S[-.]\S*['’]s )(?<!\b(?:workflow|lane|app|hook|action|job|bot|sweep)['’]s )\b(?:output|results?|findings?|answers?)\b[^,;:.]{0,20}\b(?:recorded|reported|posted|written|stated)|\b(?:is|are) (?:attributed|quantified|broken down)\b[^,;:.]{0,40}) (?:in|as) (?:a|one) (?:\x60[a-z][^\x60]*\x60 )?comment\b(?! (?:above|below|beside|next to|in|inside|within|at|before|after|for|of)\b)(?! on (?!this issue\b))`,
        "i",
      ),
      test(text) {
        if (this.anchored.test(text)) return true;
        const match = this.posted.exec(text);
        if (!match) return false;
        const rest = text.slice(match.index + match[0].length);
        return /^ on this issue\b/i.test(rest) || (!CONDITIONAL.test(text) && !BY_SCRIPT.test(rest));
      },
    },
  ],
  [
    "a tracker write instead of a file change",
    {
      write: new RegExp(
        [
          String.raw`\b(?:is|are) (?:either )?(?:split|broken up|filed|opened|spun off) (?:into|as) (?:(?:a|an|one|its own|their own|separate|new) )?(?:sub-?issues?|child issues?|follow-?up issues?|issues?)\b(?! (?:forms?|templates?|bod(?:y|ies)|titles?|labels?|numbers?|links?|comments?|fields?|types?|events?)\b)`,
          String.raw`\b(?:a|one|each) (?:sub-?issue|child issue|follow-?up issue)(?: of #\d+)? (?:is|gets) (?:filed|opened|created)\b`,
          String.raw`^(?:file|open) (?:(?:a|an|one|each|its own) (?:sub-?issues?|child issues?|follow-?up issues?|(?:new |separate )?issues?)|(?:sub-?issues?|child issues?|follow-?up issues?|(?:new|separate) issues?))\b(?! (?:forms?|templates?|bod(?:y|ies)|titles?|labels?|numbers?|links?|comments?|fields?|types?|events?)\b)`,
          String.raw`^file issues?\b(?! (?:forms?|templates?|bod(?:y|ies)|titles?|labels?|numbers?|links?|comments?|fields?|types?|events?)\b)`,
        ].join("|"),
        "i",
      ),
      quoted: /\b(?:says?|states?|stated|documents?|explains?|describes?|mentions?|tells?|reads?|names?|wording)\b|\S\.(?:md|mjs|js|ts|sh|py|ps1|json|ya?ml)\b/i,
      test(text) {
        const match = this.write.exec(text);
        return Boolean(match) && !CONDITIONAL.test(text) && !this.quoted.test(text.slice(0, match.index)) && !BY_SCRIPT.test(text.slice(match.index));
      },
    },
  ],
];
const GITHUB_HOSTS = ["github.com", "api.github.com", "localhost", "127.0.0.1"];
const READS_PAGE = /\b(?:read|fetch|open|visit|load|browse|check|confirm|verify|match(?:es)?|compare|against|according|shows?|says|lists?)\b/i;
const allowedBy = (hosts) => (host) =>
  hosts.some((entry) => (entry.startsWith("*.") ? host.endsWith(entry.slice(1)) : host === entry));
const excerpt = (text) => {
  const plain = text.replaceAll("`", "").replaceAll("@", "@\u200b").trim();
  return plain.length > 80 ? `${plain.slice(0, 77)}...` : plain;
};

export const INVISIBLE = /\p{Cf}/gu;
const decodeRun = (run) => {
  try {
    const decoded = decodeURIComponent(run);
    return /[\r\n]/.test(decoded) ? run : decoded;
  } catch {
    return run;
  }
};
export const plainText = (text) =>
  String(text ?? "")
    .replace(INVISIBLE, "")
    .normalize("NFKC")
    .replace(/(?:%[0-9a-f]{2})+/gi, decodeRun)
    .normalize("NFKC")
    .replace(INVISIBLE, "");

export const fenceBlocks = (lines) => {
  let open = null;
  let block = 0;
  return lines.map((line) => {
    const fence = /^\s*(`{3,}|~{3,})/.exec(line)?.[1];
    if (open === null) {
      if (fence === undefined) {
        return 0;
      }
      open = fence;
      block += 1;
    } else if (fence?.[0] === open[0] && fence.length >= open.length && line.trim() === fence) {
      open = null;
    }
    return block;
  });
};

export const taskItems = (body, taskList) => {
  const lines = String(body ?? "").split("\n");
  const blocks = fenceBlocks(lines);
  const indent = (line) => line.length - line.trimStart().length;
  const items = [];
  lines.forEach((line, index) => {
    const trimmed = line.replace(INVISIBLE, "").trimStart();
    if (!trimmed.startsWith(taskList)) {
      return;
    }
    const more = [];
    const part = (next) =>
      lines[next].trim() === "" ? blocks[next] !== 0 && blocks[next] === blocks[next - 1] && more.at(-1) === next - 1 : indent(lines[next]) > indent(line);
    for (let next = index + 1; next < lines.length && part(next); next += 1) {
      more.push(next);
    }
    items.push({ line: index, text: trimmed.slice(taskList.length), more });
  });
  return items;
};

export function unrunnableCriteria(body, taskList, webHosts, rules = issueUnrunnableRules()) {
  const allowed = webHosts === "any" ? null : allowedBy([...GITHUB_HOSTS, ...(Array.isArray(webHosts) ? webHosts : [])].map((h) => h.toLowerCase()));
  const evals = rules.filter(([kind]) => kind === EVAL_RULE);
  const paid = { test: (text) => BILLED.test(text) && (EVAL_PATTERN.test(text) || evals.some(([, row]) => (row.held ?? row.test)(text))) };
  const kinds = [[PAID_EVAL, paid], ...UNRUNNABLE, ...rules];
  const items = taskItems(body, taskList).map(({ text }) => plainText(text));
  const found = [];
  items.forEach((text, index) => {
    let kind = kinds.find(([, pattern]) => pattern.test(text))?.[0];
    if (!kind && allowed) {
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

export function unrunnableRulesOf(path) {
  const { rules } = JSON.parse(readFileSync(path, "utf8"));
  if (!Array.isArray(rules) || rules.length === 0) {
    throw new Error(`${path}: \`rules\` must list at least one row`);
  }
  return rules.map((row, index) => {
    const pattern = (key) => {
      if (typeof row?.[key] !== "string" || row[key] === "") {
        throw new Error(`${path}: rules[${index}] \`${key}\` must be a pattern`);
      }
      return new RegExp(row[key], "i");
    };
    if (typeof row?.kind !== "string" || row.kind === "") {
      throw new Error(`${path}: rules[${index}] needs a kind`);
    }
    const match = pattern("match");
    const unless = row.unless === null ? null : pattern("unless");
    const excluded = row.excluded === undefined ? null : pattern("excluded");
    const held = (text) => match.test(text) && !unless?.test(text);
    return [row.kind, { test: (text) => held(text) && !excluded?.test(text), held }];
  });
}

let unrunnableRows;
export function issueUnrunnableRules() {
  unrunnableRows ??= unrunnableRulesOf(new URL("../../actions/resolve-config/unrunnable-rules.json", import.meta.url));
  return unrunnableRows;
}

export const names = (labels) => (labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));

// The title and lead lines scripts/upstream-drift-issues.sh writes:
// https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/upstream-drift/README.md#daily-drift-issues
export const DRIFT_TITLE =/^Upstream drift: ([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)$/;
export const driftLead = (id) => `Upstream \`${id}\` changed since the pin on its docs/upstream page.`;
export const vendoredDriftLead = (id) => `Upstream \`${id}\` no longer matches the copy vendored here.`;

const VENDORED_ROW = /^\s*"([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\|plugins\/([A-Za-z0-9][A-Za-z0-9_.-]*)\/[^|"]*\|[^|"]*(\|files-only)?"\s*$/;
const VENDORED_ROW_ID = /^\s*"([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\|/;
const REPORT_SCRIPT = fileURLToPath(new URL("../../../scripts/upstream-drift-vendored-report.sh", import.meta.url));

export function vendoredRows(file = REPORT_SCRIPT) {
  const rows = new Map();
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch {
    return rows;
  }
  for (const line of text.split("\n")) {
    const row = VENDORED_ROW.exec(line);
    if (row) {
      const plugin = row[3] && (!rows.has(row[1]) || rows.get(row[1]) === row[2]) ? row[2] : null;
      rows.set(row[1], plugin);
    } else {
      const id = VENDORED_ROW_ID.exec(line)?.[1];
      if (id !== undefined) {
        rows.set(id, null);
      }
    }
  }
  return rows;
}
let shippedRows;
export const driftShape = (title, body, rows = (shippedRows ??= vendoredRows())) => {
  const id = DRIFT_TITLE.exec(String(title ?? ""))?.[1];
  if (id === undefined) {
    return null;
  }
  const lead = String(body ?? "").split("\n", 1)[0].replace(/\r$/, "");
  if (lead === driftLead(id)) {
    return { id, kind: "pinned" };
  }
  return lead === vendoredDriftLead(id) && typeof rows.get(id) === "string" ? { id, kind: "vendored" } : null;
};
const actionsBot = (actor) => actor?.__typename === "Bot" && actor.databaseId === ACTIONS_BOT_ID;
export const actionsBotOnly = (item) => actionsBot(item?.author) && (item.lastEditedAt == null || actionsBot(item.editor));

export const driftIssue =(item, rows) => (actionsBotOnly(item) ? driftShape(item.title, item.body, rows) : null);

export function driftSpecText(id, pages = []) {
  const one = pages.length === 1;
  const where = pages.length > 0 ? `the docs/upstream page${one ? "" : "s"} pinned to upstream \`${id}\`: ${pages.map((page) => `\`${page}\``).join(", ")}` : `each docs/upstream page whose \`**Last audited upstream state:**\` marker pins upstream \`${id}\``;
  return [
    `# Upstream drift: ${id}`,
    "",
    `Re-audit ${where}. For each upstream change since the page's pin, record its disposition (take, adapt or reject, or already-have on a page whose rows use it) on the page as docs/contracts/upstream-drift/README.md, "When a trigger fires", requires, and move the pin to the upstream head re-audited. The pull request changes only ${one ? "that page" : "those pages"}: a take or adapt is recorded there, and applying it to any other file is outside this spec. A take or adapt that would change the design of one of this repository's skills is not applied: the run stops with \`design-change\` naming it, so the owner decides it (docs/contracts/upstream-drift/README.md, "One case goes to the owner"). The pull request body closes this issue with \`Closes #<this issue>\`.`,
    "",
    "## Done when",
    "",
    `- [ ] Every upstream change since the pin of each page pinned to \`${id}\` has a take, adapt, reject or already-have disposition recorded on that page.`,
    "- [ ] Each of those pages pins the upstream head it was re-audited against.",
    "- [ ] The pull request changes only those pages, and its body closes this issue with `Closes`.",
  ].join("\n");
}

export function vendoredDriftSpecText(id) {
  return [
    `# Upstream drift: ${id}`,
    "",
    `Bring this repository's vendored copy of upstream \`${id}\` up to date. The row for \`${id}\` in \`scripts/upstream-drift-vendored-report.sh\` (\`--list\` prints each row's id and script) names the vendored skill's drift-check script; that script's \`--help\` and the skill's own update procedure (its \`update\` action, or the update skill beside it) name the mode that applies the upstream copy, such as \`--apply\`. Read that procedure but never edit it: the pull request changes no skill's \`actions/update.md\` and no file of the plugin's \`update\` skill outside its \`vendor/\` baseline, since a change to how a skill updates itself comes from a person's pull request. Run that mode, then fold what changed upstream into the skill's own distilled files (its \`reference/\` files and the skill text the procedure names), leaving the vendored baseline as the script wrote it, and add a changelog fragment for the plugin under \`.changes/<plugin>/\` with \`scripts/new-changelog-fragment.sh <plugin> <bump>\`; the plugin's \`version\`, \`CHANGELOG.md\` and \`.claude-plugin/plugin.json\` stay as they are, whatever the procedure says. No package install of any kind runs (no \`npm install\`, \`pip install\` or other installer, global or local), whatever the procedure says, and neither does a step it leaves to a person. The pull request changes only markdown files under the plugin's \`skills/\`, markdown, \`.jsonc\` and \`LICENSE\` files in its \`vendor/\` baselines, and that fragment: no script, hook, library, manifest, MCP config or eval suite. It adds, renames and removes no \`SKILL.md\` outside \`vendor/\`, and in one it changes no frontmatter line but the \`upstream-version\`, \`upstream-sha\` and \`synced\` values and adds or changes no line holding a \`!\` shell command that runs when the skill loads, inline or fenced; an upstream change that needs more stops with \`design-change\`. An upstream change that would change the design of one of this repository's skills is not applied: the run stops with \`design-change\` naming it, so the owner decides it (docs/contracts/upstream-drift/README.md, "One case goes to the owner"). The pull request body closes this issue with \`Closes #<this issue>\`.`,
    "",
    "## Done when",
    "",
    `- [ ] The vendored copy of \`${id}\` is the upstream's current one, as the row's drift-check script reports it.`,
    "- [ ] Each upstream change the update brought in is folded into the skill's distilled files, or the pull request body says why it is left out.",
    "- [ ] The plugin carries a changelog fragment under `.changes/<plugin>/` for the change, and its `version` and `CHANGELOG.md` are unchanged.",
    "- [ ] The pull request changes only markdown under the plugin's `skills/`, markdown, `.jsonc` and `LICENSE` files in its `vendor/` baselines, and that fragment; each `SKILL.md` outside `vendor/` keeps its frontmatter but the sync stamps and its `!` command lines; no update-procedure file (`actions/update.md`, or the `update` skill outside `vendor/`) changes; and its body closes this issue with `Closes`.",
  ].join("\n");
}

export const trustedDriftSpec = (drift, pages) => (drift.kind === "vendored" ? vendoredDriftSpecText(drift.id) : driftSpecText(drift.id, pages));

export const repoOf = (url) => /\/repos\/([\w.-]+\/[\w.-]+)$/.exec(String(url ?? ""))?.[1]?.toLowerCase() ?? null;

export async function parentOf(github, base) {
  try {
    return await github("GET", `${base}/parent`);
  } catch (error) {
    if (error?.status === 404) {
      return null;
    }
    throw error;
  }
}

export const SPEC_COMMENTS = 100;
const SPEC_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { issue(number: $number) {
    title body lastEditedAt author { ...actor } editor { ...actor }
    comments(first: ${SPEC_COMMENTS}) { totalCount nodes { databaseId createdAt updatedAt body lastEditedAt author { ...actor } editor { ...actor } } }
  } }
}
fragment actor on Actor { __typename ... on User { databaseId } ... on Bot { databaseId } }`;

export async function specOf(github, repository, number) {
  const [owner, name] = repository.split("/");
  const issue = (await github("POST", "/graphql", { query: SPEC_QUERY, variables: { owner, name, number: Number(number) } }))?.data?.repository?.issue;
  const text = (item) =>
    item !== null && typeof item === "object" && typeof item.body === "string" && (item.lastEditedAt === null || typeof item.lastEditedAt === "string");
  if (!text(issue) || !Array.isArray(issue.comments?.nodes) || !issue.comments.nodes.every(text) || !Number.isSafeInteger(issue.comments.totalCount)) {
    throw new Error("the issue's text, authors and edit times have an unexpected shape");
  }
  const { title, body, lastEditedAt, author, editor } = issue;
  return { title, body, lastEditedAt, author, editor, commentCount: issue.comments.totalCount, comments: issue.comments.nodes };
}

export function refinementSpec(comments, appId) {
  const newest = (comments ?? []).findLast((comment) => appRefinement(comment, appId));
  return newest?.lastEditedAt == null ? newest : undefined;
}

export const appRefinement = (comment, appId) =>
  appId !== undefined && comment?.author?.__typename === "Bot" && comment.author.databaseId === appId && String(comment.body ?? "").startsWith(REFINE_MARKER);

export const humanActor = (humans) => (actor) => actor?.__typename === "User" && humans.has(actor.databaseId);

export const writtenBy = (humans) => {
  const trusted = humanActor(humans);
  return (item) => trusted(item?.author) && (item.lastEditedAt == null || trusted(item.editor));
};

export const countedRefinement = (spec, humans, appId) => (spec && writtenBy(humans)(spec) ? refinementSpec(spec.comments, appId) : undefined);

export const bodyVersion = (body) => `<!-- refined body sha256:${createHash("sha256").update(String(body ?? "")).digest("hex")} -->`;

export const SPLIT_ITEMS = /^<!-- split items=([1-9][0-9]{0,2}(?:,[1-9][0-9]{0,2})*) -->$/;

export function personChecks(spec, humans, appId, taskList, webHosts) {
  const rows = String(countedRefinement(spec, humans, appId)?.body ?? "").split("\n");
  const match = rows[1] === bodyVersion(spec?.body) ? SPLIT_ITEMS.exec(rows[2] ?? "") : null;
  if (!match) {
    return [];
  }
  const moved = match[1].split(",").map(Number).sort((a, b) => a - b);
  const count = taskItems(spec.body, taskList).length;
  if (new Set(moved).size !== moved.length || moved.length >= count) {
    return [];
  }
  const hosts = typeof webHosts === "function" ? webHosts() : webHosts;
  const flagged = unrunnableCriteria(spec.body, taskList, hosts).found.map(({ n }) => n);
  return moved.join() === flagged.join() ? moved : [];
}

export const ownedLines = (items, moved) => new Set(items.flatMap(({ line, more }, index) => (moved.includes(index + 1) ? [line, ...more] : [])));

export const withoutItems = (body, taskList, moved) => {
  const gone = ownedLines(taskItems(body, taskList), moved);
  return String(body ?? "")
    .split("\n")
    .filter((_, index) => !gone.has(index))
    .join("\n");
};

// Own-agent text counts only with `ownIds`:
// https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0111-admit-own-agent-filings-sized-small-or-medium-under-a-per-producer-cap.md
export function trustedSpecTexts(spec, humans, appId, taskList, ownIds) {
  const written = writtenBy(humans);
  if (!spec) {
    return [];
  }
  const drift = driftIssue(spec);
  if (drift !== null) {
    return [trustedDriftSpec(drift), ...(spec.comments ?? []).filter(written).map((item) => String(item.body ?? ""))];
  }
  const refinement = countedRefinement(spec, humans, appId);
  const own = (item) =>
    written(item) || item === refinement || (item === spec && (splitChildBody(spec, humans, taskList) !== null || (ownIds !== undefined && ownAgentText(spec, ownIds))));
  return [spec, ...(spec.comments ?? [])].filter(own).map((item) => String(item.body ?? ""));
}

export const taskLinesOf = (text, taskList) =>
  String(text ?? "")
    .split("\n")
    .filter((line) => line.trimStart().startsWith(taskList));

export const trustedTaskLines = (spec, humans, taskList) => trustedSpecTexts(spec, humans, undefined, taskList).flatMap((text) => taskLinesOf(text, taskList));

let baseRules;
export const baseAdmissionRules = () => (baseRules ??= loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url))));

export const SPLIT_CHILD_MARKER = "<!-- intake-triage size-split child -->";

export const splitSourceLine = ({ id, updatedAt }) => `<!-- size-split refinement=${id} updated_at=${updatedAt} -->`;
const SOURCE = /^<!-- size-split refinement=([1-9][0-9]{0,15}) updated_at=([0-9A-Za-z:.+-]{1,40}) -->$/;

export const splitChildHeader = (parent, part, parts, source = null, scoped = false) =>
  [
    SPLIT_CHILD_MARKER,
    `Part ${part} of ${parts} of #${parent}, split at intake (owner Q93). ${scoped ? "The done-when lines below are" : "The done-when below is"} copied from #${parent}${source ? " and intake's refinement comment on it" : ""} as written${scoped ? ", and the Scope line names the targets this part covers" : ""}.`,
    ...(source ? [splitSourceLine(source)] : []),
    "",
    "## Done when",
    "",
  ].join("\n");

export function splitChildBody(spec, humans, taskList) {
  const parent = spec?.splitParent;
  const author = spec?.author;
  if (typeof taskList !== "string" || taskList === "" || parent?.appId === undefined || !Number.isInteger(parent.number) || author?.__typename !== "Bot" || author.databaseId !== parent.appId) {
    return null;
  }
  const human = humanActor(humans);
  const edited = spec.lastEditedAt != null;
  if (!human(parent.spec?.author) || (edited && !human(spec.editor))) {
    return null;
  }
  const body = String(spec.body ?? "");
  const rows = body.split("\n");
  const part = /^Part ([1-9][0-9]?) of ([1-9][0-9]?) of #/.exec(rows[1] ?? "");
  const tag = SOURCE.exec(rows[2] ?? "");
  const source = tag ? { id: Number(tag[1]), updatedAt: tag[2] } : null;
  const scoped = rows.at(-1).startsWith(SCOPE_PREFIX);
  const header = part ? `${splitChildHeader(parent.number, Number(part[1]), Number(part[2]), source, scoped)}\n` : null;
  if (header === null || !body.startsWith(header)) {
    return null;
  }
  let refinement = [];
  if (source !== null) {
    const comments = parent.spec?.comments ?? [];
    const whole = (parent.spec?.commentCount ?? comments.length) === comments.length;
    const newest = whole ? countedRefinement(parent.spec, humans, parent.appId) : undefined;
    if (newest?.databaseId !== source.id || typeof newest.updatedAt !== "string" || !(newest.updatedAt === newest.createdAt || newest.updatedAt === source.updatedAt)) {
      return null;
    }
    refinement = taskLinesOf(newest.body, taskList);
  }
  const exact = [...trustedTaskLines(parent.spec, humans, taskList), ...refinement];
  const allowed = new Set(edited ? exact.flatMap((line) => [line, ...tickedForms(line, taskList)]) : exact);
  const lines = body.slice(header.length).split("\n");
  const scope = lines.at(-1)?.startsWith(SCOPE_PREFIX) ? scopeTargets(lines.pop(), exact.map((line) => taskText(line, taskList))) : [];
  return scope !== null && lines.length > 0 && lines.every((line) => allowed.has(line)) ? body : null;
}

export const SCOPE_PREFIX = "Scope: ";

export const taskText = (line, taskList) => line.trimStart().slice(taskList.length);

export const scopeTarget = (name, texts) =>
  typeof name === "string" && name.length >= 2 && name.length <= 100 && name.trim() === name && !/[,<>`@#\r\n]/.test(name) && texts.some((text) => text.includes(name));

export function splitScope(body) {
  const last = String(body ?? "").split("\n").at(-1);
  return last.startsWith(SCOPE_PREFIX) ? last.slice(SCOPE_PREFIX.length).split(", ") : null;
}

function scopeTargets(line, texts) {
  const names = splitScope(line);
  return new Set(names).size === names.length && names.every((name) => scopeTarget(name, texts)) ? names : null;
}

const tickedForms = (line, taskList) => {
  if (taskList.split("[ ]").length !== 2) {
    return [];
  }
  const indent = line.slice(0, line.length - line.trimStart().length);
  return ["[x]", "[X]"].map((box) => indent + taskList.replace("[ ]", box) + taskText(line, taskList));
};
