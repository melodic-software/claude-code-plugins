import { copyFileSync, cpSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";

const CAPTURED_LIST_COMMITS = new URL("./fixtures/standards-list-commits.json", import.meta.url);
export function listCommits(date) {
  const commits = JSON.parse(readFileSync(CAPTURED_LIST_COMMITS, "utf8"));
  if (date !== undefined) commits[0].commit.committer.date = date;
  return commits;
}

export const STANDARDS_FIXTURE = fileURLToPath(new URL("./fixtures/standards", import.meta.url));
export const LIST_FIXTURE = `${STANDARDS_FIXTURE}/components/trusted-actors/trusted-actors.json`;
export const VOCABULARY_FIXTURE = `${STANDARDS_FIXTURE}/components/github-actions-conventions/vocabulary.json`;

export function standardsAt(dir) {
  mkdirSync(join(dir, "components/trusted-actors"), { recursive: true });
  mkdirSync(join(dir, "components/github-actions-conventions"), { recursive: true });
  copyFileSync(VOCABULARY_FIXTURE, join(dir, "components/github-actions-conventions/vocabulary.json"));
  return { dir, list: join(dir, "components/trusted-actors/trusted-actors.json") };
}

let checkout;

export function standardsCheckout() {
  if (checkout) return checkout;
  checkout = tempDir("standards-checkout-");
  cpSync(STANDARDS_FIXTURE, checkout, { recursive: true });
  return checkout;
}
