import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { SAME_TREE_LIST, STANDARDS_LIST_PATH } from "./trusted-actors.mjs";

let checkout;

export function standardsCheckout() {
  if (checkout) return checkout;
  checkout = tempDir("standards-checkout-");
  mkdirSync(join(checkout, "components/trusted-actors"), { recursive: true });
  writeFileSync(join(checkout, STANDARDS_LIST_PATH), readFileSync(SAME_TREE_LIST));
  return checkout;
}
