import { appendFileSync, readFileSync } from "node:fs";

const scenario = JSON.parse(readFileSync(process.env.FAKE_SCENARIO, "utf8"));
const argv = process.argv.slice(2);
appendFileSync(scenario.record, `${JSON.stringify({ argv })}\n`);

if (argv[0] === "--version") {
  process.stdout.write("1.0.0\n");
  process.exit(0);
}
process.stdout.write(`${JSON.stringify(scenario.envelope)}\n`);
if (scenario.stderr) process.stderr.write(scenario.stderr);
process.exit(scenario.exit ?? 0);
