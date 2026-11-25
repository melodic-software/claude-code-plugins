#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { lookupVisibility, prFromFacts } from "./repo-visibility.mjs";
import { SECRET_PATTERNS, findSecret, publishGate as sharedGate } from "../../../lib/publish-gate.mjs";
import { findRoot, gateExplicit, resolveMedium as resolveViewMedium } from "../../../lib/view-settings.mjs";
import { mediumOf, reportLines } from "../../../lib/view-registry.mjs";

import { POLICIES, LEVELS, addSetting, isSha, decide, resolveDigestConfig } from "../../../lib/review-digest.mjs";

export { DEFAULTS, CONFIG_PATHS, MAX_RISK_PATHS, MAX_GLOB_LENGTH, parseYamlLayer, resolveDigestConfig, globMatcher, decide } from "../../../lib/review-digest.mjs";
/**
 * Where the digest goes, by the shared medium resolver: `option` is this plugin's `medium` option,
 * and the team file is read from the base commit only, never the working tree. `explicit` is what
 * the publish gate's `--explicit` takes: true only when the reader chose the medium, never for the
 * plugin's own default. `where` and `publishes` come from the medium registry, so the skill names
 * the destination without listing medium values itself.
 */
export function resolveMedium(option, baseOid) {
  const teamRef = isSha(baseOid) ? baseOid : "";
  const resolution = resolveViewMedium(
    { lane: "review:explain-change", userConfig: option, projectRoot: findRoot(), teamRef },
    { dataDir: process.env.CLAUDE_PLUGIN_DATA || null },
  );
  const entry = mediumOf(resolution.medium);
  return {
    value: resolution.medium,
    source: resolution.decidedBy,
    explicit: gateExplicit(resolution),
    where: entry?.reportName ?? null,
    publishes: Boolean(entry?.publishes),
    report: reportLines(resolution),
  };
}

export { SECRET_PATTERNS, findSecret };

/**
 * Where an `artifact` page actually goes, by the shared publish gate. A pull
 * request always has a repository, so `NONE` counts as not PUBLIC here.
 * @param {{explicit: boolean, visibility: string, diff: string}} input
 */
export function publishGate({ explicit, visibility, diff }) {
  const known = visibility === "NONE" ? "UNKNOWN" : visibility;
  return sharedGate({ explicit, visibility: known, text: diff, subject: "diff" });
}

function gateMain(argv) {
  const [flag, facts, ...rest] = argv;
  if (flag !== "--facts" || !facts || facts.startsWith("--") || rest.some((a) => a !== "--explicit")) {
    process.stderr.write("usage: digest-policy.mjs --publish-gate --facts <facts.json> [--explicit] < diff\n");
    return 2;
  }
  const diff = readFileSync(0, "utf8");
  const target = prFromFacts(facts);
  const visibility = target ? lookupVisibility(target.host, target.repo) : "UNKNOWN";
  const result = publishGate({ explicit: rest.includes("--explicit"), visibility, diff });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return 0;
}

function parseArgs(argv) {
  const opts = { policy: null, event: "review", blastRadius: "", requested: false, option: null, settings: {} };
  for (let i = 0; i < argv.length; i += 1) {
    const [flag, next] = [argv[i], argv[i + 1]];
    if (flag === "--requested") opts.requested = true;
    else if (flag === "--setting" && addSetting(opts.settings, next)) i += 1;
    else if (flag === "--policy" && POLICIES.includes(next)) [opts.policy, i] = [next, i + 1];
    else if (flag === "--event" && ["ready", "review"].includes(next)) [opts.event, i] = [next, i + 1];
    else if (flag === "--option" && next !== undefined) [opts.option, i] = [next, i + 1];
    else if (flag === "--blast-radius" && LEVELS.includes(next?.toUpperCase())) [opts.blastRadius, i] = [next.toUpperCase(), i + 1];
    else return null;
  }
  return opts;
}

function main(argv) {
  if (argv[0] === "--publish-gate") return gateMain(argv.slice(1));
  const opts = parseArgs(argv);
  if (!opts) {
    process.stderr.write(
      "usage: digest-policy.mjs [--event ready|review] [--blast-radius LOW|MEDIUM|HIGH|CRITICAL] [--policy off|offer|always] [--requested] [--option <medium>] [--setting <digest option>=<value> ...] < facts.json\n",
    );
    return 2;
  }
  let facts;
  try {
    facts = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    process.stderr.write(`digest-policy: facts are not JSON (${error.message})\n`);
    return 2;
  }
  if (!facts || typeof facts !== "object" || Array.isArray(facts)) {
    process.stderr.write("digest-policy: facts must be a JSON object\n");
    return 2;
  }
  const { config, warnings } = resolveDigestConfig(facts.baseRefOid, opts.settings);
  const policy = opts.policy ? { value: opts.policy, source: "argument" } : config.digest_policy;
  const result = decide(facts, { ...opts, policy: policy.value }, config);
  const medium = resolveMedium(opts.option, facts.baseRefOid);
  process.stdout.write(
    `${JSON.stringify({ ...result, policy, event: opts.event, requested: opts.requested, medium, config, warnings }, null, 2)}\n`,
  );
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
