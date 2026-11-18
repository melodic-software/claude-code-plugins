// On Windows a .cmd runs only through a shell, which would split or interpret the arguments
// (https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows), so spawn claude.exe.
import { existsSync } from "node:fs";
import { win32 as win32Path } from "node:path";

export function claudeCommand(env = process.env, platform = process.platform, isFile = (path) => existsSync(path)) {
  if (platform !== "win32") return { file: "claude" };
  const pathVar = Object.keys(env).find((key) => key.toUpperCase() === "PATH");
  const dirs = (pathVar ? env[pathVar] : "").split(";").filter(Boolean);
  const exe = dirs.map((dir) => win32Path.join(dir, "claude.exe")).find(isFile);
  if (exe) return { file: exe };
  const script = dirs.flatMap((dir) => ["claude.cmd", "claude.bat"].map((name) => win32Path.join(dir, name))).find(isFile);
  return {
    refusal: script
      ? `found ${script} but no claude.exe on PATH; a .cmd runs only through a shell, which would split or interpret your arguments, so this needs the native claude.exe.`
      : "no claude.exe on PATH.",
  };
}
