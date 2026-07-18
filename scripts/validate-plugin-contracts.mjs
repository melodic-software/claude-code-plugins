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
const setupSkills = pluginFiles.filter((path) =>
  /[\\/]skills[\\/]setup[\\/]SKILL\.md$/.test(path),
);

for (const path of setupSkills) {
  const content = read(path);
  const frontmatter = content.match(/^---\r?\n([\s\S]*?)\r?\n---/)?.[1] ?? "";
  if (!/^disable-model-invocation:\s*true\s*$/m.test(frontmatter)) {
    fail(path, "setup skills must set disable-model-invocation: true");
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
  for (const path of filesUnder(join(pluginRoot, plugin, "skills"))) {
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
for (const legacyPath of [
  join(aiBriefingRoot, "skills", "generate", "scripts"),
  join(aiBriefingRoot, "skills", "generate", "seed"),
]) {
  if (filesUnder(legacyPath).length > 0) {
    fail(legacyPath, "legacy automated-X collectors must not be shipped");
  }
}

const aiBriefingFiles = filesUnder(aiBriefingRoot);
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
for (const path of filesUnder(aiBriefingBuildRoot).filter((path) => path.endsWith(".js"))) {
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
  for (const path of filesUnder(autonomyRoot)) {
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

if (failures.length > 0) {
  console.error("Plugin contract validation failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(
  `Plugin contracts validated: ${setupSkills.length} setup skills and ${pluginFiles.length} plugin files checked.`,
);
