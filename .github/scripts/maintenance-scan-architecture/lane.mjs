import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";

import { openCap } from "../../../plugins/improvement/scripts/filing-plan.mjs";

export const LANE = "maintenance-scan-architecture";
export const SOURCE_LABEL = "source: architecture-improve";
export const CONVENTION_HOME = "docs/conventions";
const CAP_KEY = "find_open_item_cap";

function readLayer(path) {
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return undefined;
    throw error;
  }
  const { parse } = createRequire(new URL("../../actions/resolve-config/package.json", import.meta.url))("yaml");
  return parse(text) ?? {};
}

export function openItemCap(root, home = CONVENTION_HOME) {
  const names = { team: join(home, "improvement.yaml"), personal: join(home, "improvement.local.yaml") };
  return openCap({ team: readLayer(join(root, names.team))?.[CAP_KEY], personal: readLayer(join(root, names.personal))?.[CAP_KEY], names });
}

export async function countOpen(call, repository, label, cap) {
  let open = 0;
  for (let page = 1; open <= cap; page += 1) {
    const batch = (await call("GET", `/repos/${repository}/issues?state=open&labels=${encodeURIComponent(label)}&per_page=100&page=${page}`)) ?? [];
    open += batch.filter((item) => !item.pull_request).length;
    if (batch.length < 100) break;
  }
  return open;
}
