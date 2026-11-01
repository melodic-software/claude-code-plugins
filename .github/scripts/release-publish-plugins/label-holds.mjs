// Print each hold reason on the pull request read from stdin (`gh pr list
// --json number,labels` row): merge-holds.mjs labelHolds over this checkout's
// tracker config, the list ci-status and the merge queue act on, less
// `pr-verify-failed`, which only a pass at a new head removes, so it never
// holds back the rebuild that makes one.
import { readFileSync } from "node:fs";
import { labelHolds, PR_VERIFY_FAILED_LABEL } from "../pr-merge/merge-holds.mjs";

const tracker = JSON.parse(readFileSync(new URL("../../../.work-item-tracker.json", import.meta.url), "utf8"));
const { labels, number } = JSON.parse(readFileSync(0, "utf8"));
const held = Array.isArray(labels) ? labels.filter((label) => (label?.name ?? label) !== PR_VERIFY_FAILED_LABEL) : labels;
for (const reason of labelHolds(held, tracker, number)) {
  console.log(reason);
}
