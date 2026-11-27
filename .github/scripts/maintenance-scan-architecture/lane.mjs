import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";

export const LANE = "maintenance-scan-architecture";
export const SOURCE_LABEL = "source: architecture-improve";
export const DEFAULT_OPEN_CAP = 5;
export const CONVENTION_HOME = "docs/conventions";
const CAP_KEY = "find_open_item_cap";

const isCap = (value) => Number.isSafeInteger(value) && value >= 0;

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
  const warnings = [];
  let cap = DEFAULT_OPEN_CAP;
  let source = "default";
  const layer = (name) => {
    const value = readLayer(join(root, home, name))?.[CAP_KEY];
    if (value === undefined) return undefined;
    if (isCap(value)) return value;
    warnings.push(`${join(home, name)} ${CAP_KEY} ${JSON.stringify(value)} is not a non-negative integer, so that layer is ignored`);
    return undefined;
  };
  const team = layer("improvement.yaml");
  if (team !== undefined) [cap, source] = [team, "team"];
  const personal = layer("improvement.local.yaml");
  if (personal !== undefined) {
    if (personal < cap) [cap, source] = [personal, "personal"];
    else if (personal > cap) warnings.push(`${join(home, "improvement.local.yaml")} ${CAP_KEY} ${personal} is above the ${source} cap ${cap}; a personal layer only lowers it`);
  }
  return { cap, source, warnings };
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
