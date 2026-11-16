// A stand-in for `claude` in the CLI tests. It answers `plugin list --json` from the file
// PP_STUB_LIST names, appends one line per call to PP_STUB_CALLS, and for the first
// PP_STUB_TOUCH_TIMES calls adds a permission rule to the settings file PP_STUB_TOUCH names, the
// way a concurrent writer such as a permission answer would. `plugin marketplace list --json`
// answers from PP_STUB_MARKETPLACES, `agents --json` from PP_STUB_AGENTS or an empty list. `plugin install <id> --scope user` adds the plugin to the
// PP_STUB_LIST file and switches it on in $HOME/.claude/settings.json, as the real install does,
// or fails when PP_STUB_INSTALL_FAIL is set.
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const env = process.env;
const calls = env.PP_STUB_CALLS ? (existsSync(env.PP_STUB_CALLS) ? readFileSync(env.PP_STUB_CALLS, "utf8").split("\n").filter(Boolean).length : 0) : 0;
if (env.PP_STUB_CALLS) appendFileSync(env.PP_STUB_CALLS, `${process.argv.slice(2).join(" ")}\n`);
if (env.PP_STUB_TOUCH && calls < Number(env.PP_STUB_TOUCH_TIMES ?? 0)) {
  const doc = existsSync(env.PP_STUB_TOUCH) ? JSON.parse(readFileSync(env.PP_STUB_TOUCH, "utf8")) : {};
  doc.permissions ??= {};
  doc.permissions.allow = [...(doc.permissions.allow ?? []), `Bash(stub-writer-${calls + 1})`];
  writeFileSync(env.PP_STUB_TOUCH, `${JSON.stringify(doc, null, 2)}\n`);
}
const args = process.argv.slice(2);
const command = args.join(" ");
if (command === "plugin list --json") process.stdout.write(readFileSync(env.PP_STUB_LIST, "utf8"));
else if (command === "plugin marketplace list --json") process.stdout.write(readFileSync(env.PP_STUB_MARKETPLACES, "utf8"));
else if (command === "agents --json") process.stdout.write(env.PP_STUB_AGENTS ? readFileSync(env.PP_STUB_AGENTS, "utf8") : "[]");
else if (args[0] === "plugin" && args[1] === "install" && args.length === 5 && args[3] === "--scope" && args[4] === "user") {
  if (env.PP_STUB_INSTALL_FAIL) {
    process.stderr.write(`${env.PP_STUB_INSTALL_FAIL}\n`);
    process.exitCode = 1;
  } else {
    const id = args[2];
    const installPath = join(env.HOME, "installs", id.split("@")[0]);
    mkdirSync(join(installPath, ".claude-plugin"), { recursive: true });
    writeFileSync(join(installPath, ".claude-plugin", "plugin.json"), JSON.stringify({ name: id.split("@")[0] }));
    const list = JSON.parse(readFileSync(env.PP_STUB_LIST, "utf8"));
    list.push({ id, version: "1.0.0", scope: "user", enabled: true, installPath });
    writeFileSync(env.PP_STUB_LIST, JSON.stringify(list));
    const settings = join(env.HOME, ".claude", "settings.json");
    const doc = existsSync(settings) ? JSON.parse(readFileSync(settings, "utf8")) : {};
    doc.enabledPlugins = { ...doc.enabledPlugins, [id]: true };
    mkdirSync(join(env.HOME, ".claude"), { recursive: true });
    writeFileSync(settings, `${JSON.stringify(doc, null, 2)}\n`);
  }
} else process.exitCode = 1;
