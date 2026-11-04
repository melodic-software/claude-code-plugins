// Print each hold reason on the pull request read from stdin (`gh pr list
// --json number,labels` row): merge-holds.mjs labelHolds over this checkout's
// tracker config, the list ci-status and the merge queue act on. Without
// `--queue` it leaves out `pr-verify-failed`, which a pr-verify pass removes,
// at a new head or at the same head judged again after trusted people alone
// edited the body, so it never holds back the rebuild that makes a new head; with `--queue`
// it counts every hold label, since the merge queue removes a pull request
// carrying any of them.
import { readFileSync } from "node:fs";
import process from "node:process";
import { labelHolds, PR_VERIFY_FAILED_LABEL } from "../pr-merge/merge-holds.mjs";

const tracker = JSON.parse(readFileSync(new URL("../../../.work-item-tracker.json", import.meta.url), "utf8"));
const { labels, number } = JSON.parse(readFileSync(0, "utf8"));
const queue = process.argv.includes("--queue");
const held = queue || !Array.isArray(labels) ? labels : labels.filter((label) => (label?.name ?? label) !== PR_VERIFY_FAILED_LABEL);
for (const reason of labelHolds(held, tracker, number)) {
  console.log(reason);
}
