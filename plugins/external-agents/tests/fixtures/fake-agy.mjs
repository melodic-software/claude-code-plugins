import { appendFileSync, readFileSync, writeFileSync } from "node:fs";

const scenario = JSON.parse(readFileSync(process.env.FAKE_SCENARIO, "utf8"));
const argv = process.argv.slice(2);
appendFileSync(scenario.record, `${JSON.stringify({ argv })}\n`);
const logFile = argv.indexOf("--log-file");
if (logFile !== -1 && scenario.log !== undefined) writeFileSync(argv[logFile + 1], scenario.log);

const answer = scenario.answers?.[argv.join(" ")];
if (answer) {
  process.stdout.write(answer.stdout ?? "");
  process.exit(answer.exit ?? 0);
}
if (argv[0] === "--version") {
  process.stdout.write("1.0.0\n");
  process.exit(0);
}
process.stdout.write(`${JSON.stringify(scenario.envelope)}\n`);
if (scenario.stderr) process.stderr.write(scenario.stderr);
process.exit(scenario.exit ?? 0);
