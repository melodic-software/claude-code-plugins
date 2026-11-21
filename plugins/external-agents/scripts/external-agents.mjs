import { readFileSync } from "node:fs";
import { cancel, EXIT, result, review, run, status } from "./lib/runner.mjs";
import { update } from "./lib/update.mjs";

const USAGE = `usage: external-agents <command> [options]

  run <product> --use task|investigate [--mode read-only|write] [--model M]
                [--resume <thread-id>|--last] [--prompt-file F]   (prompt on stdin without --prompt-file)
  review <product> --base <ref> [--model M] [--brief-file F]
  status [<job>]
  result <job>
  cancel <job>
  update <product>

exit codes: 0 ok, 1 failed, 2 usage, 3 blocked by the mode, 4 CLI unavailable or skipped
`;

const OPTIONS = {
  run: { "--use": "use", "--mode": "mode", "--model": "model", "--resume": "resume", "--last": null, "--prompt-file": "promptFile" },
  review: { "--base": "base", "--model": "model", "--brief-file": "briefFile" },
  status: {},
  result: {},
  cancel: {},
  update: {},
};

function parse(command, rest) {
  const known = OPTIONS[command];
  const parsed = { positional: [] };
  for (let i = 0; i < rest.length; i += 1) {
    const arg = rest[i];
    if (!arg.startsWith("--")) {
      parsed.positional.push(arg);
    } else if (!(arg in known)) {
      throw new Error(`${command}: unknown option ${arg}`);
    } else if (known[arg] === null) {
      parsed[arg.slice(2)] = true;
    } else {
      if (i + 1 >= rest.length) throw new Error(`${command}: ${arg} needs a value`);
      parsed[known[arg]] = rest[(i += 1)];
    }
  }
  return parsed;
}

const usageError = (message) => {
  process.stderr.write(`external-agents: ${message}\n${USAGE}`);
  return EXIT.usage;
};

export async function main(argv) {
  const [command, ...rest] = argv;
  if (!command || command === "--help" || command === "-h") {
    process.stdout.write(USAGE);
    return 0;
  }
  if (!(command in OPTIONS)) return usageError(`${command}: unknown command`);
  let options;
  let text;
  try {
    options = parse(command, rest);
    const file = options.promptFile ?? options.briefFile;
    text = file ? readFileSync(file, "utf8") : command === "run" ? readFileSync(0, "utf8") : undefined;
  } catch (error) {
    if (command === "review") {
      const product = /^[a-z][a-z0-9-]*$/.test(rest[0] ?? "") ? rest[0] : "external-agents";
      process.stdout.write(`${product}: failed (${error.message.replace(/\s+/g, " ").trim()})\n`);
    }
    return usageError(error.message);
  }
  const [first] = options.positional;
  const outcome =
    command === "run" ? await run({ product: first, use: options.use, mode: options.mode, model: options.model, resume: options.resume, last: options.last, prompt: text })
    : command === "review" ? await review({ product: first, base: options.base, model: options.model, brief: text })
    : command === "update" ? await update({ product: first })
    : { status, result, cancel }[command]({ jobId: first });
  process.stdout.write(outcome.stdout);
  process.stderr.write(outcome.stderr);
  return outcome.code;
}
