#!/usr/bin/env node

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";
import process from "node:process";

const root = process.cwd();
const failures = [];

function filesUnder(directory) {
  if (!existsSync(directory)) return [];
  const files = [];
  for (const entry of readdirSync(directory)) {
    if (entry === "node_modules" || entry === ".git") continue;
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) files.push(...filesUnder(path));
    else files.push(path);
  }
  return files;
}

function read(path) {
  return readFileSync(path, "utf8");
}

function fail(path, message) {
  failures.push(`${relative(root, path)}: ${message}`);
}

const pluginRoot = join(root, "plugins");
const pluginFiles = filesUnder(pluginRoot);

// Every plugin file under `directory`, taken from the single plugins/ walk
// above rather than walking the subtree again — same set, same order, one
// traversal instead of one per checked subtree.
function filesIn(directory) {
  return pluginFiles.filter((path) => path.startsWith(directory + sep));
}

const setupSkills = pluginFiles.filter((path) =>
  /[\\/]skills[\\/]setup[\\/]SKILL\.md$/.test(path),
);

for (const path of setupSkills) {
  const content = read(path);
  const frontmatter = content.match(/^---\r?\n([\s\S]*?)\r?\n---/)?.[1] ?? "";
  if (!/^disable-model-invocation:\s*true\s*$/m.test(frontmatter)) {
    fail(path, "setup skills must set disable-model-invocation: true");
  }
  // Uniform contract shape (PLUGIN-PHILOSOPHY "Setup is explicit and repeatable"):
  // check is the default read-only action; apply exists unless the skill declares the
  // userConfig-only check-only carve-out the doctrine sanctions.
  if (!/^argument-hint:\s*"check(?:\s*\||\s*\[|")/m.test(frontmatter)) {
    fail(path, 'setup skills must declare check as the leading action in argument-hint ("check", "check | apply ...", or "check [<subaction>]")');
  }
  const body = content.slice(content.indexOf("---", 3) + 3);
  if (!/`check`/.test(body)) {
    fail(path, "setup skills must document the read-only check action");
  }
  if (!/`apply`/.test(body) && !/check-only/i.test(body)) {
    fail(path, "setup skills must document apply, or declare the check-only userConfig-only carve-out");
  }
}

const setupContractFiles = pluginFiles.filter(
  (path) =>
    /[\\/]skills[\\/]setup[\\/]/.test(path) &&
    /\.(?:md|json)$/.test(path),
);
for (const path of setupContractFiles) {
  const content = read(path);
  if (/pluginConfigs\s*\[\s*["'][^"']+@/i.test(content)) {
    fail(path, "must not write marketplace-qualified pluginConfigs keys");
  }
  if (/@melodic-software\b/i.test(content)) {
    fail(path, "must not bind setup behavior to a marketplace name");
  }
}

for (const path of pluginFiles.filter((path) => /[\\/]skills[\\/].*\.md$/.test(path))) {
  const content = read(path);
  if (/@melodic-software\b|melodic-software\/github-iac/i.test(content)) {
    fail(path, "reusable skill content must not require publisher-specific runtime identifiers");
  }
  if (/\bMELODIC_[A-Z0-9_]+\b/.test(content)) {
    fail(path, "reusable skill content must not introduce publisher-prefixed configuration");
  }
}

for (const path of pluginFiles.filter(
  (path) => /[\\/]hooks[\\/].*\.sh$/.test(path) && !path.endsWith(".test.sh"),
)) {
  const content = read(path);
  if (/^\s*npx(?:\s|$)|^\s*[A-Z_][A-Z0-9_]*=\(\s*npx\b/m.test(content)) {
    fail(path, "hooks must not invoke npx or download tools at runtime");
  }
}

for (const path of pluginFiles.filter((path) => path.endsWith(".schema.json"))) {
  if (/melodic\.local/i.test(read(path))) {
    fail(path, "schema identifiers must use a neutral absolute URI");
  }
}

for (const plugin of ["discovery", "planning", "implementation"]) {
  const manifest = join(pluginRoot, plugin, ".claude-plugin", "plugin.json");
  if (existsSync(manifest) && /"notes_dir"\s*:/.test(read(manifest))) {
    fail(manifest, "shared project artifact locations cannot use personal userConfig");
  }
  for (const path of filesIn(join(pluginRoot, plugin, "skills"))) {
    if (path.endsWith(".md") && /\$\{user_config\.notes_dir\}/.test(read(path))) {
      fail(path, "lifecycle skills must use the shared repository artifact protocol");
    }
  }
}

const canonicalLifecycleProtocol = join(root, "docs", "PLUGIN-ARTIFACT-PROTOCOL.md");
const canonicalLifecycleContent = existsSync(canonicalLifecycleProtocol)
  ? read(canonicalLifecycleProtocol)
  : null;
if (canonicalLifecycleContent === null) {
  failures.push("docs/PLUGIN-ARTIFACT-PROTOCOL.md: shared lifecycle protocol is required");
}

const lifecycleProtocolCopies = ["discovery", "planning", "implementation", "verification"].map((plugin) =>
  join(pluginRoot, plugin, "reference", "artifact-protocol.md"),
);
for (const path of lifecycleProtocolCopies) {
  if (!existsSync(path)) {
    fail(path, "every lifecycle plugin must ship the canonical artifact protocol");
    continue;
  }
  if (canonicalLifecycleContent !== null && read(path) !== canonicalLifecycleContent) {
    fail(path, "must remain byte-identical to docs/PLUGIN-ARTIFACT-PROTOCOL.md");
  }
}

const aiBriefingRoot = join(pluginRoot, "ai-briefing");
// skills/generate/scripts once held the automated-X collectors and stays
// tombstoned, with one carve-out: run-tests.sh, the skill's public test entry
// facade over the private output/build package (encapsulation contract, #2701).
// The automatedXTokens content scan below covers the carved-out file too, so a
// collector cannot return under the allowed name.
const legacyScriptsPath = join(aiBriefingRoot, "skills", "generate", "scripts");
// filesUnder, not filesIn: this probes paths that must NOT exist, so it has
// to look at the filesystem rather than at a walk that already excluded them.
const legacyScriptsExtras = filesUnder(legacyScriptsPath).filter(
  (path) => relative(legacyScriptsPath, path) !== "run-tests.sh",
);
if (legacyScriptsExtras.length > 0) {
  fail(
    legacyScriptsPath,
    "legacy automated-X collectors must not be shipped (only the run-tests.sh entry facade may live here)",
  );
}
const legacySeedPath = join(aiBriefingRoot, "skills", "generate", "seed");
if (filesUnder(legacySeedPath).length > 0) {
  fail(legacySeedPath, "legacy automated-X collectors must not be shipped");
}

const aiBriefingFiles = filesIn(aiBriefingRoot);
const automatedXTokens =
  /--refresh-following|--grok-preload|following-list\.json|chrome-extract|per-profile-runner|grok-capture|mcp__claude-in-chrome/i;
for (const path of aiBriefingFiles.filter((path) => /\.(?:js|json|md|sh)$/.test(path))) {
  if (automatedXTokens.test(read(path))) {
    fail(path, "must not expose or retain legacy automated-X collection paths");
  }
}

const aiBriefingSkill = join(aiBriefingRoot, "skills", "generate", "SKILL.md");
if (existsSync(aiBriefingSkill)) {
  const content = read(aiBriefingSkill);
  if (!content.includes("${user_config.active_profile}")) {
    fail(aiBriefingSkill, "must render active_profile in skill content");
  }
  if (!/AI_BRIEFING_PROFILE=["']?\$PROFILE/.test(content)) {
    fail(aiBriefingSkill, "must explicitly pass the resolved profile to build subprocesses");
  }
}

const aiBriefingSetup = join(aiBriefingRoot, "skills", "setup", "SKILL.md");
if (existsSync(aiBriefingSetup)) {
  const content = read(aiBriefingSetup);
  for (const marker of [
    "mktemp -d",
    "npm ci",
    "playwright install --with-deps --only-shell chromium",
    "chromium.launch()",
  ]) {
    if (!content.includes(marker)) {
      fail(aiBriefingSetup, `transactional build setup must include ${marker}`);
    }
  }
}

const aiBriefingBuildRoot = join(
  aiBriefingRoot,
  "skills",
  "generate",
  "output",
  "build",
);
for (const path of filesIn(aiBriefingBuildRoot).filter((path) => path.endsWith(".js"))) {
  if (/fonts\.googleapis|fonts\.gstatic|cdn\.jsdelivr\.net|simple-icons@latest|networkidle/i.test(read(path))) {
    fail(path, "deterministic local rendering must not depend on remote assets or networkidle");
  }
}

const aiBriefingPaths = join(aiBriefingBuildRoot, "lib", "paths.js");
if (existsSync(aiBriefingPaths)) {
  const content = read(aiBriefingPaths);
  if (!/validateProfileName/.test(content) || !/lowercase-kebab/.test(content) || !/com\[1-9\]/i.test(content)) {
    fail(aiBriefingPaths, "must enforce portable profile slugs before joining state or project paths");
  }
}

const aiBriefingBrandOverlay = join(aiBriefingBuildRoot, "lib", "brand-overlay.js");
if (existsSync(aiBriefingBrandOverlay)) {
  const content = read(aiBriefingBrandOverlay);
  if (!content.includes('"brand.json"') || !content.includes("realpathSync") || !content.includes(".strict()")) {
    fail(aiBriefingBrandOverlay, "must load schema-validated brand.json and confine logo real paths");
  }
  // A brand.js literal is allowed only for passive legacy-profile detection
  // and migration errors. Keep rejecting the executable overlay paths used by
  // earlier runtimes, including direct imports of profile-controlled files.
  if (
    /data:text\/javascript|import\s*\(\s*(?:dataUrl|overlayPath|legacyOverlayPath)\s*\)/.test(
      content,
    )
  ) {
    fail(aiBriefingBrandOverlay, "must not execute consumer-controlled brand configuration");
  }
}

// The autonomy plugin's contract text is tool- and fleet-agnostic: the org
// token and bare fleet repo names may not appear anywhere under it. Author
// metadata in plugin.json is the single allowed occurrence. The normative
// reference/ docs additionally ban vendor names outright — surface classes
// replace them; tool-specific detail lives in SKILL.md/README.
const autonomyRoot = join(pluginRoot, "autonomy");
if (existsSync(autonomyRoot)) {
  const fleetTokens = /melodic-software|ci-workflows|github-iac/i;
  const vendorTokens = /github|gitlab|bitbucket|slack|anthropic|claude|openai|copilot|cursor|devin/i;
  const autonomyReference = join(autonomyRoot, "reference") + sep;
  for (const path of filesIn(autonomyRoot)) {
    let content = read(path);
    if (path.endsWith(`${sep}.claude-plugin${sep}plugin.json`)) {
      // Only the author block is exempt — description/keywords/etc. stay gated.
      const manifest = JSON.parse(content);
      delete manifest.author;
      content = JSON.stringify(manifest);
    }
    if (fleetTokens.test(content)) {
      fail(path, "autonomy plugin must not name the org or fleet repos (binding-seam owns instances)");
    }
    if (path.startsWith(autonomyReference) && vendorTokens.test(content)) {
      fail(path, "autonomy reference/ contracts must use surface classes, never vendor names");
    }
  }
}

// A manifest component field names hook files, skill directories, and the rest
// at NON-default paths. Pointing one at the path Claude Code already discovers
// re-registers a component the harness has loaded: for `hooks` that is a
// duplicate-file load error that takes the whole hook file down with it, and it
// is redundant for every other field. The failure is silent at load time, so a
// gate catches it and a reviewer does not.
const defaultComponentPaths = {
  agents: ["agents", "agents/"],
  commands: ["commands", "commands/"],
  hooks: ["hooks/hooks.json"],
  lspServers: [".lsp.json"],
  mcpServers: [".mcp.json"],
  skills: ["skills", "skills/"],
};
for (const path of pluginFiles) {
  if (!path.endsWith(`${sep}.claude-plugin${sep}plugin.json`)) continue;
  const manifest = JSON.parse(read(path));
  for (const [field, defaults] of Object.entries(defaultComponentPaths)) {
    const declared = [manifest[field] ?? []].flat();
    for (const value of declared) {
      if (typeof value !== "string") continue;
      const normalized = value.replace(/\\/g, "/").replace(/^\.\//, "");
      if (defaults.includes(normalized)) {
        fail(path, `${field} must not name its auto-discovered default path (${value})`);
      }
    }
  }
}

// An `archive` catalog entry installs a plugin from a zip fetched over HTTPS
// (Claude Code v2.1.224+). The platform's floor is transport-level only — HTTPS,
// no loopback/link-local/cloud-metadata hosts, same rules on every redirect hop —
// and the `sha256` digest that pins the bytes is documented as optional. Unpinned,
// the same URL can serve different content on every install with nothing to detect
// it, which is the mutable-remote-artifact surface the plugin-acceptance security
// review (docs/MIGRATION-PLAYBOOK.md, criterion 6) denies by default. The pin is
// required here so review never has to catch it by eye.
const marketplacePath = join(root, ".claude-plugin", "marketplace.json");
if (existsSync(marketplacePath)) {
  const catalog = JSON.parse(read(marketplacePath));
  for (const entry of [catalog.plugins ?? []].flat()) {
    if (!entry || typeof entry !== "object") continue;
    const source = entry.source;
    // Documented entry shape: "source": { "source": "archive", "url": ..., "sha256"? : ... }.
    if (typeof source !== "object" || source === null || source.source !== "archive") continue;
    // The digest is 64 hex characters, uppercase or lowercase.
    if (!/^[0-9a-fA-F]{64}$/.test(String(source.sha256 ?? ""))) {
      fail(
        marketplacePath,
        `archive entry "${entry.name ?? "(unnamed)"}" must pin its download with a 64-hex sha256`,
      );
    }
  }
}

if (failures.length > 0) {
  console.error("Plugin contract validation failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(
  `Plugin contracts validated: ${setupSkills.length} setup skills and ${pluginFiles.length} plugin files checked.`,
);
