#!/usr/bin/env node

// Generates the machine-readable identity-and-prerequisite emission from the
// ten v1 routine definition leaves. Leaves stay the authored single home; this
// file is derived output the resolver and CI consume. Run with no argument to
// rewrite the emission; run with --check to fail on drift (CI gate).
//
// Usage:
//   node generate-identity-prerequisites.mjs [--check] [--root <dir>]
// Exit 0 = in sync (or rewritten); 1 = drift / parse failure; 2 = usage error.

import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_PLUGIN_ROOT = join(SCRIPT_DIR, "..", "..", "..");
const LEAVES_REL = join("reference", "routines");
const EMISSION_REL = join("generated", "identity-prerequisites.json");
const SCHEMA_VERSION = 1;

// Stable need vocabulary derived from leaf "Repo needs" prose. Order is the
// match priority; each id appears at most once per identity after expansion.
const NEED_PATTERNS = [
  {
    id: "tracker",
    re: /tracker binding via the work-item tracker seam/,
    probe_class: "repo-file",
    seam: "work-item-tracker",
  },
  {
    id: "tracker",
    re: /tracker binding when filing/,
    probe_class: "repo-file",
    seam: "work-item-tracker",
  },
  {
    id: "ci_config",
    re: /CI-config presence/,
    probe_class: "repo-file",
    owner: "resolution-contract",
  },
  {
    id: "dependency_manifests",
    re: /dependency \/ build manifests/,
    probe_class: "repo-file",
  },
  {
    id: "ecosystems",
    re: /ecosystems via the toolchain seam/,
    probe_class: "repo-file",
    seam: "toolchain",
  },
  {
    id: "advisory_database",
    re: /curated advisory-database/,
    probe_class: "harness-context",
  },
  {
    id: "merge_path",
    re: /merge-bearing path/,
    probe_class: "harness-context",
  },
  {
    id: "upstream_changelog",
    re: /upstream release-note/,
    probe_class: "harness-context",
  },
  {
    id: "source_tree",
    re: /repository source tree/,
    probe_class: "repo-file",
  },
  {
    id: "documentation_corpus",
    re: /documentation corpus/,
    probe_class: "repo-file",
  },
  {
    id: "activity_signals",
    re: /repository activity signals/,
    probe_class: "repo-file",
  },
];

function usage() {
  console.error(
    "usage: node generate-identity-prerequisites.mjs [--check] [--root <dir>]",
  );
  process.exit(2);
}

function parseArgs(argv) {
  let check = false;
  let root = null;
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--check") {
      check = true;
      continue;
    }
    if (arg === "--root") {
      root = argv[++i];
      if (!root) usage();
      continue;
    }
    usage();
  }
  return { check, root };
}

function posixRel(from, to) {
  return relative(from, to).split(sep).join("/");
}

function firstBacktick(value) {
  const match = value.match(/`([^`]+)`/);
  return match ? match[1] : null;
}

function parseConnectorEntitlements(value) {
  const trimmed = value.trim();
  if (/^none\b/i.test(trimmed)) return [];
  const tokens = [...trimmed.matchAll(/`([^`]+)`/g)].map((m) => m[1]);
  return tokens.filter((t) => t !== "repo");
}

function parseConnectorRung(value) {
  if (/^n\/a\b/i.test(value.trim())) return null;
  if (/Org binding layer/i.test(value)) return "org";
  return firstBacktick(value);
}

function needsFromProse(prose) {
  const byId = new Map();
  for (const pattern of NEED_PATTERNS) {
    if (!pattern.re.test(prose)) continue;
    if (byId.has(pattern.id)) continue;
    const need = { id: pattern.id, probe_class: pattern.probe_class };
    if (pattern.seam) need.seam = pattern.seam;
    if (pattern.owner) need.owner = pattern.owner;
    byId.set(pattern.id, need);
  }
  return [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
}

function extractPrerequisitesSection(markdown) {
  const start = markdown.search(/^## Prerequisites\s*$/m);
  if (start === -1) {
    throw new Error("missing ## Prerequisites section");
  }
  const after = markdown.slice(start);
  const endMatch = after.slice(after.indexOf("\n") + 1).search(/^## /m);
  if (endMatch === -1) return after;
  return after.slice(0, after.indexOf("\n") + 1 + endMatch);
}

function parseAxisTable(block) {
  const axes = {};
  for (const line of block.split("\n")) {
    const match = line.match(/^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$/);
    if (!match) continue;
    const axis = match[1].trim();
    const value = match[2].trim();
    if (axis === "Axis" || /^-+$/.test(axis.replace(/\s/g, ""))) continue;
    axes[axis] = value;
  }
  return axes;
}

function splitIdentityBlocks(section) {
  const bodies = [];
  const headingRe = /^### `([^`]+)`\s*$/gm;
  const headings = [...section.matchAll(headingRe)];
  if (headings.length > 0) {
    for (let i = 0; i < headings.length; i += 1) {
      const start = headings[i].index;
      const end = i + 1 < headings.length ? headings[i + 1].index : section.length;
      bodies.push({
        identity: headings[i][1],
        block: section.slice(start, end),
      });
    }
    return bodies;
  }

  const single = section.match(/Single-posture identity:\s*`([^`]+)`/);
  if (!single) {
    throw new Error("no ### identity headings and no Single-posture identity line");
  }
  return [{ identity: single[1], block: section }];
}

function classAndPosture(identity) {
  const slash = identity.indexOf("/");
  if (slash === -1) return { classToken: identity, posture: null };
  return {
    classToken: identity.slice(0, slash),
    posture: identity.slice(slash + 1),
  };
}

function recordFromAxes(identity, axes, leafRel) {
  const access = axes["Access class"];
  const floor = axes["Isolation floor"];
  const entitlements = axes["Connector entitlements"];
  const rung = axes["Connector entitlement rung"];
  const repoNeeds = axes["Repo needs"];
  if (!access || !floor || !entitlements || !rung || !repoNeeds) {
    throw new Error(`${identity}: incomplete axis table`);
  }
  const accessClass = firstBacktick(access);
  const isolationFloor = firstBacktick(floor);
  if (!accessClass || !isolationFloor) {
    throw new Error(`${identity}: Access class / Isolation floor missing backtick token`);
  }
  const { classToken, posture } = classAndPosture(identity);
  return {
    identity,
    class: classToken,
    posture,
    leaf: leafRel,
    access_class: accessClass,
    isolation_floor: isolationFloor,
    connector_entitlements: parseConnectorEntitlements(entitlements),
    connector_entitlement_rung: parseConnectorRung(rung),
    executor_class_merge_cap: "security-binding",
    repo_needs_prose: repoNeeds,
    needs: null,
  };
}

function expandNeeds(records) {
  const byIdentity = new Map(records.map((r) => [r.identity, r]));
  const byPosture = new Map();
  for (const record of records) {
    if (record.posture) byPosture.set(`${record.class}/${record.posture}`, record);
  }

  for (const record of records) {
    const prose = record.repo_needs_prose;
    const inherit = prose.match(/everything\s+`([^`]+)`\s+requires/i);
    let needs = [];
    if (inherit) {
      const token = inherit[1];
      const parentKey = token.includes("/")
        ? token
        : `${record.class}/${token}`;
      const parent = byIdentity.get(parentKey) || byPosture.get(parentKey);
      if (!parent) {
        throw new Error(`${record.identity}: cannot expand inheritance from ${token}`);
      }
      if (parent.needs === null) {
        // Parent must be expanded first; two-pass below handles ordering.
        record._inheritFrom = parent.identity;
        continue;
      }
      needs = parent.needs.map((n) => ({ ...n }));
    }
    const own = needsFromProse(prose);
    const byId = new Map(needs.map((n) => [n.id, n]));
    for (const need of own) byId.set(need.id, need);
    record.needs = [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
  }

  // Second pass for inherit-before-parent edge cases.
  let pending = records.filter((r) => r.needs === null);
  let guard = pending.length + 1;
  while (pending.length > 0 && guard > 0) {
    guard -= 1;
    for (const record of pending) {
      const parent = byIdentity.get(record._inheritFrom);
      if (!parent || parent.needs === null) continue;
      const byId = new Map(parent.needs.map((n) => [n.id, { ...n }]));
      for (const need of needsFromProse(record.repo_needs_prose)) {
        byId.set(need.id, need);
      }
      record.needs = [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
      delete record._inheritFrom;
    }
    pending = records.filter((r) => r.needs === null);
  }
  if (pending.length > 0) {
    throw new Error(
      `unresolved inheritance for: ${pending.map((r) => r.identity).join(", ")}`,
    );
  }

  for (const record of records) {
    delete record.repo_needs_prose;
    delete record._inheritFrom;
  }
}

function parseLeaf(markdown, leafRel) {
  const section = extractPrerequisitesSection(markdown);
  const blocks = splitIdentityBlocks(section);
  const records = [];
  for (const { identity, block } of blocks) {
    const axes = parseAxisTable(block);
    records.push(recordFromAxes(identity, axes, leafRel));
  }
  return records;
}

function buildEmission(pluginRoot) {
  const leavesDir = join(pluginRoot, LEAVES_REL);
  const leafFiles = readdirSync(leavesDir)
    .filter((name) => name.endsWith(".md"))
    .sort();
  if (leafFiles.length === 0) {
    throw new Error(`no routine leaves under ${posixRel(pluginRoot, leavesDir)}`);
  }

  const records = [];
  for (const name of leafFiles) {
    const abs = join(leavesDir, name);
    const leafRel = posixRel(pluginRoot, abs);
    const markdown = readFileSync(abs, "utf8");
    records.push(...parseLeaf(markdown, leafRel));
  }

  expandNeeds(records);
  records.sort((a, b) => a.identity.localeCompare(b.identity));

  const seen = new Set();
  for (const record of records) {
    if (seen.has(record.identity)) {
      throw new Error(`duplicate identity ${record.identity}`);
    }
    seen.add(record.identity);
    if (!record.needs || record.needs.length === 0) {
      throw new Error(`${record.identity}: derived need set is empty`);
    }
  }

  return {
    _comment:
      "GENERATED — do not hand-edit. Regenerate with plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs",
    schema_version: SCHEMA_VERSION,
    identities: records,
  };
}

function serialize(emission) {
  return `${JSON.stringify(emission, null, 2)}\n`;
}

function main() {
  const { check, root } = parseArgs(process.argv.slice(2));
  const pluginRoot = root ? join(root) : DEFAULT_PLUGIN_ROOT;
  const emissionPath = join(pluginRoot, EMISSION_REL);
  const emissionLabel = root
    ? posixRel(root, emissionPath)
    : posixRel(join(DEFAULT_PLUGIN_ROOT, "..", ".."), emissionPath);

  let expected;
  try {
    expected = serialize(buildEmission(pluginRoot));
  } catch (error) {
    console.error(`identity-prerequisites: ${error.message}`);
    process.exit(1);
  }

  let existing = null;
  try {
    existing = readFileSync(emissionPath, "utf8");
  } catch {
    existing = null;
  }

  if (check) {
    if (existing === expected) {
      console.log("Identity-prerequisite emission is in sync with the leaves.");
      process.exit(0);
    }
    console.error(`Identity-prerequisite emission drift: ${emissionLabel} is stale.`);
    console.error(
      "Run `node plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs` and commit the emission.",
    );
    if (existing === null) {
      console.error("  found:    <missing>");
    } else {
      const expectedLines = expected.split("\n");
      const existingLines = existing.split("\n");
      const at = expectedLines.findIndex((line, i) => line !== existingLines[i]);
      if (at !== -1) {
        console.error(`First difference at generated line ${at + 1}:`);
        console.error(`  expected: ${JSON.stringify(expectedLines[at] ?? null)}`);
        console.error(`  found:    ${JSON.stringify(existingLines[at] ?? null)}`);
      }
    }
    process.exit(1);
  }

  if (existing === expected) {
    console.log(`Identity-prerequisite emission already in sync; ${emissionLabel} unchanged.`);
    process.exit(0);
  }

  mkdirSync(dirname(emissionPath), { recursive: true });
  writeFileSync(emissionPath, expected);
  console.log(`Identity-prerequisite emission regenerated in ${emissionLabel}.`);
}

main();
