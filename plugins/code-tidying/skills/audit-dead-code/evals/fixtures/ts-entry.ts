import { mountPanel } from "./dead-and-dynamic.js";
import { formatBytes } from "./ts-used.js";

export async function main(moduleName: string): Promise<string> {
  const loaded = (await import(`./${moduleName}.js`)) as Record<string, () => string>;
  const render = loaded["renderPanel"];
  return `${mountPanel()} ${formatBytes(1024)} ${render()}`;
}
