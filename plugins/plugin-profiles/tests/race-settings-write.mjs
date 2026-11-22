import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";

const rename = fs.renameSync;
let record = null;
let fired = false;
/** Loaded with node --import: the first rename onto a settings.local.json overwrites the record this run last saved with another apply's, then fails, as a second apply racing a failed settings write would. */
fs.renameSync = (from, to) => {
  if (/[\\/]records[\\/][^\\/]+\.json$/.test(to)) record = to;
  if (record && !fired && to.endsWith("settings.local.json")) {
    fired = true;
    const other = { ...JSON.parse(fs.readFileSync(record, "utf8")), profile: "other-apply" };
    fs.writeFileSync(record, `${JSON.stringify(other, null, 2)}\n`);
    throw Object.assign(new Error("settings write failed"), { code: "EIO" });
  }
  return rename(from, to);
};
syncBuiltinESMExports();
