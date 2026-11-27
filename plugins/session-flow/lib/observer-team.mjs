import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { parse } from "./yaml-subset.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

export const section = (markdown, title = "Observer guidance") => {
  const lines = markdown.split(/\r?\n/);
  const start = lines.findIndex((l) => new RegExp(`^##\\s+${title}\\s*$`, "i").test(l));
  if (start < 0) return "";
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((l) => /^#{1,2}\s/.test(l));
  return (end < 0 ? rest : rest.slice(0, end)).join("\n").trim();
};

export const observerMap = (yaml) => {
  const map = parse(yaml)?.observer;
  return map !== null && typeof map === "object" && !Array.isArray(map) ? map : {};
};

export const homeOf = (stderr) => /default-branch-file: (\S+)\/session-flow\.yaml at /.exec(stderr)?.[1];

const read = (args) => {
  const r = spawnSync("bash", [join(HERE, "default-branch-file.sh"), ...args], { encoding: "utf8", timeout: 20_000 });
  return { code: r.status, out: r.stdout ?? "", err: r.stderr ?? "" };
};

export const team = (run = read) => {
  const out = { observer: {}, guidance: "", notes: [] };
  const yaml = run(["--plugin", "session-flow"]);
  if (yaml.code === 0) {
    try {
      out.observer = observerMap(yaml.out);
    } catch (err) {
      out.notes.push(`session-flow.yaml: ${err.message}`);
    }
  } else if (yaml.code !== 1) out.notes.push(yaml.err.trim());
  const home = homeOf(yaml.err);
  if (home !== undefined) {
    const md = run(["--path", `${home}/session-flow.md`]);
    if (md.code === 0) out.guidance = section(md.out);
  }
  return out;
};

if (process.argv[1] === fileURLToPath(import.meta.url)) process.stdout.write(JSON.stringify(team()));
