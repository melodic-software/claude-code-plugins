const USAGE = `usage: external-agents <command> [options]

  run <product> --use task|investigate [--resume <id>|--last]
  review <product> --base <ref> [--model M] [--brief-file F]
  status [<job>]
  result <job>
  cancel <job>
  update <product>
`;

export async function main(argv) {
  const [command] = argv;
  if (!command || command === "--help" || command === "-h") {
    process.stdout.write(USAGE);
    return 0;
  }
  process.stderr.write(`external-agents: ${command}: not implemented yet\n${USAGE}`);
  return 2;
}
