#!/usr/bin/env node
// The one SessionStart prerequisites row for every enabled plugin
// (docs/contracts/prerequisites/README.md#hook-notices). For each enabled plugin whose
// prerequisites.json declares session_probe, it runs that plugin's own lib/prerequisites.mjs probe
// as a child, with that plugin's CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA, so the probe's latch,
// its git-hook drift check and the plugin's hook::notice_once all see the plugin's own directories.
// The notices print as one systemMessage. Always exits 0.
//
//   prerequisites-fleet.mjs        (SessionStart hook input on stdin)
//
// Enabled plugins come from enabledPlugins in the user and project settings plus
// installed_plugins.json, the settings path of check-prerequisites.mjs; never from
// `claude plugin list`, which would start a nested claude on every session start. The config
// directory is the prefix of this install's own path (plugin-options.mjs resolveInstall), else
// CLAUDE_CONFIG_DIR or ~/.claude for a --plugin-dir checkout.
//
// A plugin's kill switch, session_probe.run_if_unset_or_true, is read from the operator's settings
// (pluginConfigs, channel F of docs/contracts/hook-config-delivery), else the option's declared
// default. Anything but true skips the plugin; so does a settings file that cannot be read.
import { spawn } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { managedSettingsFiles, readOperatorOptions, resolveInstall } from "../lib/plugin-options.mjs";
import { loadManifest } from "../lib/prerequisites.mjs";
import { rootsFromSettings } from "../skills/prerequisites/scripts/check-prerequisites.mjs";

const CHILD_TIMEOUT_MS = 10_000;
const OWN_ROOT = path.dirname(path.dirname(realpathSync(fileURLToPath(import.meta.url))));

export function configDir(ownRoot, env) {
  const { userSettings } = resolveInstall(ownRoot);
  if (userSettings) return path.dirname(userSettings);
  return env.CLAUDE_CONFIG_DIR || path.join(env.HOME || homedir(), ".claude");
}

// The kill switch's value: the operator's setting, else the option's declared default.
function gateValue(root, install, gate, managed) {
  const key = gate.toLowerCase();
  const set = readOperatorOptions(install, managed, [key], { booleans: true })[key];
  if (set) return set.value;
  try {
    const fallback = JSON.parse(readFileSync(path.join(root, ".claude-plugin", "plugin.json"), "utf8")).userConfig?.[key]
      ?.default;
    return fallback === undefined ? undefined : String(fallback);
  } catch {
    return undefined;
  }
}

// The probes to run: [{ root, env }], one per enabled plugin that declares session_probe and is not
// switched off.
export function planProbes(roots, config, managed, env) {
  const base = Object.fromEntries(
    Object.entries(env).filter(([k]) => !k.startsWith("CLAUDE_PLUGIN_OPTION_") && k !== "CLAUDE_PLUGIN_DATA"),
  );
  const plan = [];
  for (const root of roots) {
    if (!existsSync(path.join(root, "lib", "prerequisites.mjs"))) continue;
    const { manifest, errors, absent } = loadManifest(root);
    if (absent || errors.length || !manifest.session_probe) continue;
    const install = resolveInstall(root);
    const gate = manifest.session_probe.run_if_unset_or_true;
    if (gate) {
      let value;
      try {
        value = gateValue(root, install, gate, managed);
      } catch {
        continue;
      }
      if (value !== undefined && value !== "" && value !== "true") continue;
    }
    const childEnv = { ...base, CLAUDE_PLUGIN_ROOT: root };
    if (install.pluginId) {
      childEnv.CLAUDE_PLUGIN_DATA = path.join(config, "plugins", "data", install.pluginId.replace(/[^A-Za-z0-9_-]/g, "-"));
    }
    plan.push({ root, env: childEnv });
  }
  return plan;
}

function runProbe({ root, env }, input) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [path.join(root, "lib", "prerequisites.mjs"), "probe", root], {
      env,
      stdio: ["pipe", "pipe", "ignore"],
      timeout: CHILD_TIMEOUT_MS,
    });
    let out = "";
    child.stdout.on("data", (chunk) => {
      out += chunk;
    });
    child.on("error", () => resolve([]));
    child.on("close", () => {
      const messages = [];
      for (const line of out.split("\n")) {
        try {
          const message = JSON.parse(line).systemMessage;
          if (typeof message === "string" && message) messages.push(message);
        } catch {
          // Not a hook document.
        }
      }
      resolve(messages);
    });
    child.stdin.on("error", () => {});
    child.stdin.end(input);
  });
}

// main(ctx) -> the systemMessage text, or "" when no plugin has a notice.
export async function main({ env = process.env, input = "", ownRoot = OWN_ROOT, managed } = {}) {
  const config = configDir(ownRoot, env);
  const { roots } = rootsFromSettings(config, env.CLAUDE_PROJECT_DIR || "");
  let managedFiles = managed;
  if (managedFiles === undefined) {
    try {
      managedFiles = managedSettingsFiles();
    } catch {
      return "";
    }
  }
  const plan = planProbes(roots, config, managedFiles, env);
  const results = await Promise.all(plan.map((probe) => runProbe(probe, input)));
  return results.flat().join("\n");
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  const input = process.stdin.isTTY ? "" : readFileSync(0, "utf8");
  const message = await main({ input }).catch(() => "");
  if (message) process.stdout.write(`${JSON.stringify({ systemMessage: message })}\n`);
}
