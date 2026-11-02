// The command a registration runs: node src/launch.mjs --config <path> --environment <name> [--write]
import { main } from './main.mjs';

process.exitCode = await main();
