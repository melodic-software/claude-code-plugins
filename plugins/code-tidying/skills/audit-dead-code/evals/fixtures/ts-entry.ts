// Entry point for the knip fixture project.
//
// The dynamic import is a template literal on purpose: it is the reference
// shape a static resolver cannot follow, and it is what makes renderPanel a
// trap rather than a true finding.

import { mountPanel } from "./dead-and-dynamic.js";
import { formatBytes } from "./ts-used.js";

export async function main(moduleName: string): Promise<string> {
  const loaded = (await import(`./${moduleName}.js`)) as Record<string, () => string>;
  const render = loaded["renderPanel"];
  return `${mountPanel()} ${formatBytes(1024)} ${render()}`;
}
