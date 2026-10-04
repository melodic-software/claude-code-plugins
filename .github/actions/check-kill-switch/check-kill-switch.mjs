// Kill-switch gate for CI lanes: proceed only when the switch reads exactly
// `false`. Unset, empty and every other value stop the lane (fail closed).
import { randomUUID } from "node:crypto";
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

export function checkKillSwitch(value) {
  return value === "false"
    ? { proceed: "true", reason: "ok" }
    : { proceed: "false", reason: "kill-switch" };
}

// Every value is written in the delimited form, so no value can start a
// second output line.
export function writeOutputs(outputs, outputPath = process.env.GITHUB_OUTPUT) {
  if (!outputPath) {
    throw new Error("GITHUB_OUTPUT is not set");
  }
  let text = "";
  for (const [name, value] of Object.entries(outputs)) {
    const delimiter = `ghadelimiter_${randomUUID()}`;
    const body = String(value);
    if (body.includes(delimiter)) {
      throw new Error(`output ${name} contains its delimiter`);
    }
    text += `${name}<<${delimiter}\n${body}\n${delimiter}\n`;
  }
  appendFileSync(outputPath, text);
}

function main() {
  const result = checkKillSwitch(process.env.KILL_SWITCH_VALUE);
  writeOutputs(result);
  console.log(`check-kill-switch: proceed=${result.proceed} reason=${result.reason}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main();
}
