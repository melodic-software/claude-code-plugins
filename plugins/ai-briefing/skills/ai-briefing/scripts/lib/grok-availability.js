// Grok Build availability — optional tooling; never hard-require for shared-repo workflows.

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";

export const CRLF_LINE_SPLIT = /\r?\n/;
export const WINDOWS_CMD_BAT_SUFFIX = /\.(cmd|bat)$/i;

export const GROK_AUTH_PATH = path.join(os.homedir(), ".grok", "auth.json");
export const GROK_INSTALL_DOC = "https://x.ai/cli";

const INSTALL_HINT =
  "Optional — curl -fsSL https://x.ai/cli/install.sh | bash, then grok login (SuperGrok/X Premium+). See https://x.ai/cli";

function resolveGrokHomeBin() {
  const binDir = path.join(os.homedir(), ".grok", "bin");
  if (process.platform === "win32") {
    const exe = path.join(binDir, "grok.exe");
    if (existsSync(exe)) {
      return exe;
    }
  }
  const plain = path.join(binDir, "grok");
  if (existsSync(plain)) {
    return plain;
  }
  return null;
}

/** Resolve grok binary: explicit path, ~/.grok/bin/grok(.exe), then PATH. */
export function resolveGrokBin(explicit) {
  if (explicit && explicit !== "grok") {
    return existsSync(explicit) ? explicit : null;
  }

  const homeBin = resolveGrokHomeBin();
  if (homeBin) {
    return homeBin;
  }

  const lookup = spawnSync(process.platform === "win32" ? "where" : "which", ["grok"], {
    encoding: "utf-8",
    shell: true,
  });
  if (lookup.status === 0) {
    const line = lookup.stdout.trim().split(CRLF_LINE_SPLIT)[0]?.trim();
    if (line) {
      return line;
    }
  }

  return null;
}

/**
 * Probe whether Wave 0 / agent-loop Grok features can run on this machine.
 *
 * - `available`: binary runs `--version`
 * - `ready`: available + subscription auth file present (default `~/.grok/auth.json`)
 */
export function probeGrokAvailability({ grokBin, authPath = GROK_AUTH_PATH } = {}) {
  const bin = resolveGrokBin(grokBin ?? "grok");

  if (!bin) {
    return {
      available: false,
      ready: false,
      reason: "not_installed",
      message:
        "Grok Build CLI is not installed. Wave 0 X preload and agent-loop grok-default pool are skipped; ai-briefing Chrome Wave 1 is unchanged.",
      install_hint: INSTALL_HINT,
      doc: GROK_INSTALL_DOC,
      bin: null,
      auth_present: false,
      version: null,
    };
  }

  const needsShell = process.platform === "win32" && WINDOWS_CMD_BAT_SUFFIX.test(bin);
  const versionRun = spawnSync(bin, ["--no-auto-update", "--version"], {
    encoding: "utf-8",
    timeout: 30_000,
    shell: needsShell,
  });
  const version =
    (versionRun.stdout || versionRun.stderr || "").trim().split(CRLF_LINE_SPLIT)[0] || null;

  if (versionRun.error || versionRun.status !== 0) {
    return {
      available: false,
      ready: false,
      reason: "not_executable",
      message: `Grok binary failed --version (${bin}). Wave 0 skipped; use Chrome capture.`,
      install_hint: INSTALL_HINT,
      doc: GROK_INSTALL_DOC,
      bin,
      auth_present: existsSync(authPath),
      version,
    };
  }

  const authPresent = existsSync(authPath);
  if (!authPresent) {
    return {
      available: true,
      ready: false,
      reason: "not_authenticated",
      message:
        "Grok CLI is installed but not signed in (~/.grok/auth.json missing). Run grok login or skip Wave 0; briefing still works via Chrome.",
      install_hint: "grok login",
      doc: GROK_INSTALL_DOC,
      bin,
      auth_present: false,
      version,
    };
  }

  return {
    available: true,
    ready: true,
    reason: null,
    message: null,
    install_hint: null,
    doc: GROK_INSTALL_DOC,
    bin,
    auth_present: true,
    version,
  };
}
