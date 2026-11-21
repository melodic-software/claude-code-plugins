import { execFileSync, spawn, spawnSync } from "node:child_process";
import { join } from "node:path";

const windows = process.platform === "win32";
const system32 = (...parts) => join(process.env.SystemRoot ?? "C:\\Windows", "System32", ...parts);
const isPid = (pid) => Number.isInteger(pid) && pid > 0;

const INERT_IN_CMD = /^[A-Za-z0-9_.,:=@+~/\\ -]*$/;

export const shellUnsafe = (text) => !INERT_IN_CMD.test(text) || text.endsWith("\\");

const quoted = (binary, args) => (binary.shell ? [[binary.path, ...args].map((a) => `"${a}"`).join(" "), []] : [binary.path, args]);

/** Runs a short CLI query (version, login status) to completion. */
export function query(binary, args, { env, timeout = 30_000 } = {}) {
  const [command, list] = quoted(binary, [...(binary.args ?? []), ...args]);
  const done = spawnSync(command, list, { env, shell: binary.shell, windowsHide: true, encoding: "utf8", timeout, stdio: ["ignore", "pipe", "pipe"] });
  return { code: done.error ? null : done.status, stdout: done.stdout ?? "", stderr: done.stderr ?? "", error: done.error ?? null };
}

/** Starts the CLI as the root of its own process tree, so the tree can be killed as one. */
export function start(binary, args, { cwd, env, stdio }) {
  const [command, list] = quoted(binary, [...(binary.args ?? []), ...args]);
  return spawn(command, list, { cwd, env, stdio, shell: binary.shell, windowsHide: true, detached: !windows });
}

export function pidStartTime(pid) {
  if (!isPid(pid)) return null;
  try {
    const out = windows
      ? execFileSync(system32("WindowsPowerShell", "v1.0", "powershell.exe"), ["-NoProfile", "-NonInteractive", "-Command", `(Get-Process -Id ${pid}).StartTime.ToUniversalTime().ToString('o')`], { encoding: "utf8", windowsHide: true, stdio: ["ignore", "pipe", "ignore"] })
      : execFileSync("ps", ["-o", "lstart=", "-p", String(pid)], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
    return out.trim() || null;
  } catch {
    return null;
  }
}

export function killTree(pid) {
  if (!isPid(pid)) return false;
  try {
    if (windows) execFileSync(system32("taskkill.exe"), ["/T", "/F", "/PID", String(pid)], { windowsHide: true, stdio: "ignore" });
    else process.kill(-pid, "SIGKILL");
    return true;
  } catch {
    return false;
  }
}
