import { readFileSync } from "node:fs";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { labelHolds, PR_VERIFY_FAILED_LABEL, TRACKER_BINDING_PATH, trackerBindingText } from "../pr-merge/merge-holds.mjs";

const tracker = JSON.parse(trackerBindingText(fileURLToPath(new URL(`../../../${TRACKER_BINDING_PATH}`, import.meta.url))));
const { labels, number } = JSON.parse(readFileSync(0, "utf8"));
const queue = process.argv.includes("--queue");
const held = queue || !Array.isArray(labels) ? labels : labels.filter((label) => (label?.name ?? label) !== PR_VERIFY_FAILED_LABEL);
for (const reason of labelHolds(held, tracker, number)) {
  console.log(reason);
}
