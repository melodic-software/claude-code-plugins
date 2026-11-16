// A stand-in for `claude` in the CLI tests. It answers `plugin list --json` from the file
// PP_STUB_LIST names, appends one line per call to PP_STUB_CALLS, and for the first
// PP_STUB_TOUCH_TIMES calls adds a permission rule to the settings file PP_STUB_TOUCH names, the
// way a concurrent writer such as a permission answer would.
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";

const env = process.env;
const calls = env.PP_STUB_CALLS ? (existsSync(env.PP_STUB_CALLS) ? readFileSync(env.PP_STUB_CALLS, "utf8").split("\n").filter(Boolean).length : 0) : 0;
if (env.PP_STUB_CALLS) appendFileSync(env.PP_STUB_CALLS, `${process.argv.slice(2).join(" ")}\n`);
if (env.PP_STUB_TOUCH && calls < Number(env.PP_STUB_TOUCH_TIMES ?? 0)) {
  const doc = existsSync(env.PP_STUB_TOUCH) ? JSON.parse(readFileSync(env.PP_STUB_TOUCH, "utf8")) : {};
  doc.permissions ??= {};
  doc.permissions.allow = [...(doc.permissions.allow ?? []), `Bash(stub-writer-${calls + 1})`];
  writeFileSync(env.PP_STUB_TOUCH, `${JSON.stringify(doc, null, 2)}\n`);
}
if (process.argv.slice(2).join(" ") === "plugin list --json") process.stdout.write(readFileSync(env.PP_STUB_LIST, "utf8"));
else process.exitCode = 1;
