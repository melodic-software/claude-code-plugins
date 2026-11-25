import { readFileSync } from "node:fs";

import { ATTENDED as ATTENDED_LABEL, HOST_RUN as HOST_RUN_LABEL } from "../lib/lane-vocabulary.mjs";

export { ATTENDED_LABEL, HOST_RUN_LABEL };

const ROUTE_NAMES = new Set(["hold", "host-run", "attended", "retry", "wait", "intake", "park", "close", "fail"]);
const COUNTED_ROUTES = new Set(["retry", "wait", "intake"]);
export const HOLD_CLASSES = new Set(["intent-change", "design-change", "security-risk", "cost-risk"]);

export const STOP_ROUTES = Object.freeze(JSON.parse(readFileSync(new URL("./stop-routes.json", import.meta.url), "utf8")));
for (const [reason, row] of Object.entries(STOP_ROUTES)) {
  if (!ROUTE_NAMES.has(row?.route) || typeof row.why !== "string" || row.why === "") {
    throw new Error(`stop-routes.json: ${reason} needs a route (${[...ROUTE_NAMES].join(", ")}) and a why`);
  }
  if (row.retries !== undefined && !(COUNTED_ROUTES.has(row.route) && Number.isSafeInteger(row.retries) && row.retries >= 0)) {
    throw new Error(`stop-routes.json: ${reason}'s retries needs a ${[...COUNTED_ROUTES].join(", ")} route and a whole number`);
  }
  if (row.fault !== undefined && !(row.route === "retry" && row.fault === true)) {
    throw new Error(`stop-routes.json: ${reason}'s fault needs a retry route and the value true`);
  }
  if (row.route === "hold" && !HOLD_CLASSES.has(row.class)) {
    throw new Error(`stop-routes.json: ${reason} holds, so its class needs to be one of ${[...HOLD_CLASSES].join(", ")}`);
  }
  if (row.route !== "hold" && row.class !== undefined) {
    throw new Error(`stop-routes.json: ${reason} does not hold, so it takes no class`);
  }
}
if (STOP_ROUTES["security-risk"]?.route !== "hold" || STOP_ROUTES["security-risk"].class !== "security-risk") {
  throw new Error("stop-routes.json: security-risk needs a hold route and class security-risk");
}
for (const spent of ["retry-spent", "turn-cap-spent"]) {
  if (STOP_ROUTES[spent]?.route === "retry" || !Object.hasOwn(STOP_ROUTES, spent)) {
    throw new Error(`stop-routes.json: ${spent} needs a route other than retry`);
  }
}

const rowOf = (reason) => (Object.hasOwn(STOP_ROUTES, reason) ? STOP_ROUTES[reason] : undefined);
export const stopRoute = (reason) => rowOf(reason)?.route ?? "fail";
const CLASS_CODES = { "intent-change": "intent", "design-change": "design", "security-risk": "security", "cost-risk": "cost" };
export const stopReasonCode = (reason) => CLASS_CODES[rowOf(reason)?.class] || "none";
export const stopRetries = (reason, cap) => Math.min(cap, rowOf(reason)?.retries ?? cap);
export const stopFault = (reason) => rowOf(reason)?.fault === true;
export const stopWhy = (reason) => rowOf(reason)?.why ?? "the stop reason is not in the lane's route table";

const CODES = Object.keys(STOP_ROUTES)
  .filter((reason) => STOP_ROUTES[reason].code === true)
  .sort((a, b) => b.length - a.length)
  .map((code) => [code, code === "security-risk" ? /^security[-_\s]*risk/i : new RegExp(`^${code}(?![\\w-])`, "i")]);
const SECURITY_CONCERN =
  /security|vuln|inject|exfiltrat|malicious|backdoor|exploit|branch[\s_-]?protection|attack|unauthori[sz]|hijack|\btake[\s-]?over\b|took\s+over|\bstol(?:e|en)\b|\bstranger|\boutsider|\b(?:xss|rce|cve)\b|ignore\b.{0,40}\binstructions?\b/i;
const SECRET_NOUN = String.raw`credential|secret|token|passw(?:or)?d|api[\s_-]?key|private[\s_-]?key|deploy[\s_-]?key|ssh[\s_-]?key|access[\s_-]?key|\bpat\b(?!-)`;
const SECURITY_WORD = new RegExp(`${SECURITY_CONCERN.source}|${SECRET_NOUN}`, "i");
const readKnownNames = () => {
  try {
    return JSON.parse(readFileSync(new URL("./known-names.json", import.meta.url), "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return {};
    throw error;
  }
};
const KNOWN_NAMES = readKnownNames();
if (KNOWN_NAMES === null || typeof KNOWN_NAMES !== "object" || Array.isArray(KNOWN_NAMES)) {
  throw new Error("known-names.json: needs an object of name to why");
}
for (const [name, why] of Object.entries(KNOWN_NAMES)) {
  if (!/^[a-z0-9]+(?:[-_:][a-z0-9]+)+$/.test(name) || new RegExp(SECRET_NOUN, "i").test(name) || typeof why !== "string" || why === "") {
    throw new Error(`known-names.json: ${name} needs to join lowercase parts with -, _ or :, hold no secret noun, and have a why`);
  }
}
const NAME_EDGE = String.raw`[\p{L}\p{N}_:-]`;
const LISTED_NAME = Object.keys(KNOWN_NAMES).length
  ? new RegExp(
      `(?<!${NAME_EDGE})(?:${Object.keys(KNOWN_NAMES)
        .sort((a, b) => b.length - a.length)
        .join("|")})(?!${NAME_EDGE})`,
      "gu",
    )
  : null;
const outsideNames = (pattern) => {
  const global = new RegExp(pattern.source, `${pattern.flags}g`);
  return (text) => {
    const spans = LISTED_NAME ? [...text.matchAll(LISTED_NAME)].map((name) => [name.index, name.index + name[0].length]) : [];
    global.lastIndex = 0;
    for (let found = global.exec(text); found; found = global.exec(text)) {
      if (!spans.some(([start, end]) => found.index >= start && found.index + found[0].length <= end)) return found[0];
      global.lastIndex = found.index + 1;
    }
    return undefined;
  };
};
const concernOutsideNames = outsideNames(SECURITY_CONCERN);
const wordOutsideNames = outsideNames(SECURITY_WORD);
const N = "(?:credentials?|api[\\s_-]?keys?|tokens?|secrets?|passwords?)";
const END = "(?=\\s*(?:$|[.;)]|\\s(?:to\\s+(?:run|invoke|call|use|reach|spend)|the\\s+lane|this\\s+lane|it\\s+does|which\\s+only|only)\\b))";
const CAPABILITY = new RegExp(
  `\\b(?:(?:a|the)\\s+)?host\\s+with\\s+(?:(?:model|an?|the)\\s+)*${N}${END}|\\b(?:needs?|requires?|lacks?)\\s+(?:(?:an?|the|model|deploy)\\s+)*${N}${END}|\\btokens?\\s+(?:per|spent|count|usage|budget)\\b|,\\s*tokens\\s*,`,
  "gi",
);
const TOKEN_COUNT =
  /(?<![\w.,])(?:\d{1,3}(?:,\d{3})+|\d{4,}|\d+(?:\.\d+)?[kKM])\s?tokens?\b(?=\s*(?:\.?\s*$|\))|\s+(?:headless|interactive|vs|versus|per|spent|used|total|budget|startup|payload|context|prompt|cached|saved|more|fewer|less)\b)/g;
const TOKEN_HANDLING = /\b(?:rotat|revok|leak|expos|upload|paste|print|commit|push|dump|reveal|email|cop(?:y|ie[ds])|gist|screenshot)|\b(?:post(?:ed|s)?|shar(?:e|ed|es|ing)|logged|visible|shown|reus\w*|stol\w*)\b/i;
const TOKEN_MEASURE = /\b[\w-]+-per-tokens?\b|\bper-tokens?\b|\btokens?-(?:spending|budget|count|counting|usage)\b/gi;
const SCOPE = String.raw`(?:\x60[^\x60\n]{1,40}\x60|[\w-]+:\s*(?:read|write)|(?:[\w-]+\s+)?(?:permissions?|scopes?))`;
const CRED_SENSE = new RegExp(
  String.raw`\b(?:subscription|model|input|output|cache)\s+tokens?\b|\b(?:[\w-]+:\s*(?:read|write)|read-only|read|write)\s+tokens?\b|\btokens?\s+(?:has|have|had)\s+no\s+${SCOPE}|\btoken['’]s\s+(?:permissions?|scopes?)\b|(?<=\b(?:has|have|had)\s+no\s+(?:[\w-]+\s+(?:and|or|nor)\s+no\s+)?(?:[\w-]+\s+)?)${N}\b`,
  "gi",
);
const withoutCounts = (text) => (TOKEN_HANDLING.test(text) ? text : text.replace(TOKEN_COUNT, " ").replace(TOKEN_MEASURE, " "));
const CAPABILITY_WORDS = new Set(
  "a an the and or to on of for with not no cannot can does do only lane host desktop machine gpu run runs need needs requires lacks hold invoke call calls spend paid credit prepaid eval evals suite suites claude model live task tasks completed work against records pass rate advisor wall time printer driver it has have had role s ci azure gh dequeue step merge job whose read write cover workflow".split(" "),
);
const capabilityOnly = (text) => {
  const words = text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  return words.every((word, i) => CAPABILITY_WORDS.has(word) || (/^th(?:is|at)$/.test(word) && /^(?:lane|needs|ci)$/.test(words[i + 1] ?? "")));
};
const ENDING_ROUTES = new Set(["close", "host-run", "attended", "intake"]);
const endingRiskWord = (text) => {
  const counted = withoutCounts(text);
  const capabilities = counted.replace(CAPABILITY, " ");
  const rest = TOKEN_HANDLING.test(text) ? capabilities : capabilities.replace(CRED_SENSE, " ");
  return concernOutsideNames(text) ?? wordOutsideNames(rest) ?? (capabilityOnly(rest) ? "" : (wordOutsideNames(counted) ?? ""));
};
const namesEndingRisk = (text) => endingRiskWord(text) !== "";

const plainText = (text) =>
  String(text ?? "")
    .normalize("NFKC")
    .replace(/[\p{Cf}\p{Mn}]/gu, "");
const reasonText = (reason) => plainText(reason).replace(/^[\s*_`]*(?:reason\s*:)?[\s*_`]*/i, "");
export const causeName = (cause) =>
  plainText(cause)
    .trim()
    .toLowerCase()
    .replace(/[.:;\s]+$/, "")
    .replace(/[\s_-]+/g, "-")
    .replace(/^-+|[-.:;]+$/g, "");
export const leadingCode = (reason) => {
  const text = reasonText(reason);
  return CODES.find(([, code]) => code.test(text))?.[0] ?? "";
};
export const runCode = (reason, { anyCodeEnds = false } = {}) => {
  const text = reasonText(reason);
  for (const [name, code] of CODES) {
    const match = code.exec(text);
    if (match) {
      return (anyCodeEnds || ENDING_ROUTES.has(STOP_ROUTES[name].route)) && namesEndingRisk(text.slice(match[0].length)) ? "security-risk" : name;
    }
  }
  return wordOutsideNames(text) !== undefined ? "security-risk" : "stopped";
};
export const securityWord = (reason) => {
  const text = reasonText(reason);
  const found = CODES.find(([, code]) => code.test(text));
  const word = found ? endingRiskWord(text.slice(found[1].exec(text)[0].length)) : (wordOutsideNames(text) ?? "");
  return word.replaceAll(/[^A-Za-z0-9_-]+/g, " ").trim();
};
