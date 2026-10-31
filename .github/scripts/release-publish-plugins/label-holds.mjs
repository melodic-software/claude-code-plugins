// Print each hold reason on the pull request read from stdin (`gh pr list
// --json number,labels` row): merge-holds.mjs labelHolds over this checkout's
// tracker config, the list ci-status and the merge queue act on.
import { readFileSync } from "node:fs";
import { labelHolds } from "../pr-merge/merge-holds.mjs";

const tracker = JSON.parse(readFileSync(new URL("../../../.work-item-tracker.json", import.meta.url), "utf8"));
const { labels, number } = JSON.parse(readFileSync(0, "utf8"));
for (const reason of labelHolds(labels, tracker, number)) {
  console.log(reason);
}
