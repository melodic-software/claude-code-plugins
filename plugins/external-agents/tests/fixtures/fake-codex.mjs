import { appendFileSync, readFileSync, writeFileSync } from "node:fs";

const scenario = JSON.parse(readFileSync(process.env.FAKE_SCENARIO, "utf8"));
const argv = process.argv.slice(2);
const stdin = argv.at(-1) === "-" ? readFileSync(0, "utf8") : null;
appendFileSync(scenario.record, `${JSON.stringify({ argv, stdin })}\n`);

if (argv[0] === "login") process.exit(scenario.login_exit ?? 0);
if (argv[0] === "--version") {
  process.stdout.write("codex-cli 0.0.1\n");
  process.exit(0);
}
if (scenario.stdout_file) process.stdout.write(readFileSync(scenario.stdout_file, "utf8"));
if (scenario.stdout) process.stdout.write(scenario.stdout);
if (scenario.stderr) process.stderr.write(scenario.stderr);
const out = argv.indexOf("-o");
if (out !== -1 && scenario.final !== undefined) writeFileSync(argv[out + 1], scenario.final);
setTimeout(() => process.exit(scenario.exit ?? 0), scenario.sleep_ms ?? 0);
