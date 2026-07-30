#!/usr/bin/env node

// Generate Cursor dual-target manifests from the Claude Code SSOTs.
//
// Claude owns:
//   .claude-plugin/marketplace.json
//   plugins/*/.claude-plugin/plugin.json
//
// This writes (never hand-edit; regenerate + commit):
//   .cursor-plugin/marketplace.json
//   plugins/*/.cursor-plugin/plugin.json
//
// Cursor schema (https://cursor.com/docs/reference/plugins): kebab-case name,
// relative source paths, optional description/category/tags/logo. Claude-only
// fields (relevance, defaultEnabled, userConfig, $schema) are stripped.
//
//   node scripts/generate-cursor-manifests.mjs           write
//   node scripts/generate-cursor-manifests.mjs --check   fail on drift

import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import process from "node:process";

const root = join(import.meta.dirname, "..");
const claudeMarketplacePath = join(root, ".claude-plugin", "marketplace.json");
const cursorMarketplacePath = join(root, ".cursor-plugin", "marketplace.json");

/** Fields copied from Claude plugin.json into Cursor plugin.json. */
const PLUGIN_FIELDS = [
  "name",
  "version",
  "description",
  "author",
  "homepage",
  "repository",
  "license",
  "keywords",
  "logo",
];

/** Fields copied from Claude marketplace entries into Cursor marketplace entries. */
const ENTRY_FIELDS = ["name", "displayName", "source", "category", "tags", "logo"];

function rel(path) {
  return relative(root, path).split(sep).join("/");
}

function stableStringify(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function pick(source, keys) {
  const out = {};
  for (const key of keys) {
    if (source[key] !== undefined) out[key] = source[key];
  }
  return out;
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function pluginManifestPath(source, host) {
  const dir = source.replace(/^\.\//, "");
  return join(root, dir, `.${host}-plugin`, "plugin.json");
}

function buildCursorPlugin(claudePlugin) {
  const cursor = pick(claudePlugin, PLUGIN_FIELDS);
  if (!cursor.name) throw new Error("plugin.json missing required name");
  if (!cursor.description) {
    throw new Error(`${cursor.name}: plugin.json has no description`);
  }
  return cursor;
}

function buildCursorMarketplace(claudeMarketplace, pluginByName) {
  if (!claudeMarketplace.name) throw new Error("marketplace.json missing name");
  if (!claudeMarketplace.owner?.name) {
    throw new Error("marketplace.json missing owner.name");
  }
  if (!Array.isArray(claudeMarketplace.plugins)) {
    throw new Error("marketplace.json missing plugins array");
  }

  // Cursor marketplace blurb: dual-target wording (Claude catalog keeps its own
  // description SSOT). Plugin entry descriptions still copy Claude plugin.json.
  const description =
    "Reusable, repo-agnostic plugins for Claude Code and Cursor — skills, hooks, agents, and MCP servers.";

  return {
    name: claudeMarketplace.name,
    owner: {
      name: claudeMarketplace.owner.name,
      ...(claudeMarketplace.owner.email
        ? { email: claudeMarketplace.owner.email }
        : {}),
    },
    metadata: {
      description,
      ...(claudeMarketplace.version ? { version: claudeMarketplace.version } : {}),
      ...(claudeMarketplace.pluginRoot
        ? { pluginRoot: claudeMarketplace.pluginRoot }
        : {}),
    },
    plugins: claudeMarketplace.plugins.map((entry) => {
      if (!entry.name) throw new Error("marketplace entry missing name");
      if (!entry.source) throw new Error(`${entry.name}: missing source`);
      const plugin = pluginByName.get(entry.name);
      if (!plugin) {
        throw new Error(
          `${entry.name}: no Claude plugin.json loaded for marketplace entry`,
        );
      }
      const cursorEntry = pick(entry, ENTRY_FIELDS);
      cursorEntry.description = plugin.description;
      return cursorEntry;
    }),
  };
}

function expectedArtifacts() {
  const claudeMarketplace = readJson(claudeMarketplacePath);
  const pluginByName = new Map();
  const pluginFiles = new Map();

  for (const entry of claudeMarketplace.plugins) {
    const path = pluginManifestPath(entry.source, "claude");
    if (!existsSync(path)) {
      throw new Error(`${entry.name}: missing ${rel(path)}`);
    }
    const claudePlugin = readJson(path);
    if (claudePlugin.name !== entry.name) {
      throw new Error(
        `${entry.name}: Claude plugin.json name "${claudePlugin.name}" does not match catalog key`,
      );
    }
    const cursorPlugin = buildCursorPlugin(claudePlugin);
    pluginByName.set(entry.name, cursorPlugin);
    pluginFiles.set(pluginManifestPath(entry.source, "cursor"), cursorPlugin);
  }

  return {
    marketplace: buildCursorMarketplace(claudeMarketplace, pluginByName),
    pluginFiles,
    expectedPluginPaths: new Set(pluginFiles.keys()),
  };
}

function listCursorPluginFiles() {
  const pluginsRoot = join(root, "plugins");
  if (!existsSync(pluginsRoot)) return [];
  const paths = [];
  for (const name of readdirSync(pluginsRoot, { withFileTypes: true })) {
    if (!name.isDirectory()) continue;
    const path = join(pluginsRoot, name.name, ".cursor-plugin", "plugin.json");
    if (existsSync(path)) paths.push(path);
  }
  return paths.sort();
}

function writeArtifacts({ marketplace, pluginFiles }) {
  mkdirSync(dirname(cursorMarketplacePath), { recursive: true });
  writeFileSync(cursorMarketplacePath, stableStringify(marketplace));

  for (const [path, plugin] of pluginFiles) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, stableStringify(plugin));
  }

  // Remove orphaned Cursor plugin manifests (plugin removed from Claude catalog).
  for (const path of listCursorPluginFiles()) {
    if (!pluginFiles.has(path)) {
      rmSync(path);
      const dir = dirname(path);
      try {
        rmSync(dir);
      } catch {
        // Directory not empty — leave sibling files alone.
      }
    }
  }
}

function checkArtifacts({ marketplace, pluginFiles, expectedPluginPaths }) {
  const errors = [];

  if (!existsSync(cursorMarketplacePath)) {
    errors.push(`missing ${rel(cursorMarketplacePath)}`);
  } else {
    const actual = readFileSync(cursorMarketplacePath, "utf8");
    const expected = stableStringify(marketplace);
    if (actual !== expected) {
      errors.push(`${rel(cursorMarketplacePath)} is stale`);
    }
  }

  for (const [path, plugin] of pluginFiles) {
    if (!existsSync(path)) {
      errors.push(`missing ${rel(path)}`);
      continue;
    }
    const actual = readFileSync(path, "utf8");
    const expected = stableStringify(plugin);
    if (actual !== expected) {
      errors.push(`${rel(path)} is stale`);
    }
  }

  for (const path of listCursorPluginFiles()) {
    if (!expectedPluginPaths.has(path)) {
      errors.push(`unexpected orphan ${rel(path)}`);
    }
  }

  return errors;
}

const check = process.argv.includes("--check");
const artifacts = expectedArtifacts();

if (check) {
  const errors = checkArtifacts(artifacts);
  if (errors.length === 0) {
    console.log("Cursor manifests are in sync with the Claude SSOTs.");
    process.exit(0);
  }
  console.error("Cursor manifest drift:");
  for (const error of errors) console.error(`  - ${error}`);
  console.error("Run `node scripts/generate-cursor-manifests.mjs` and commit the result.");
  process.exit(1);
}

writeArtifacts(artifacts);
console.log(
  `Wrote ${rel(cursorMarketplacePath)} and ${artifacts.pluginFiles.size} Cursor plugin manifests.`,
);
