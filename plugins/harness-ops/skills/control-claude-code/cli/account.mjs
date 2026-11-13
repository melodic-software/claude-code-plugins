#!/usr/bin/env node
// Prints the driven session's account email and organization name, one per line, for drive's mask
// post-check (SKILL.md `## Mask` `values:`). The session holder reads them in that session's own
// launch environment, which the caller may not share (in CI it runs in another sandbox). See README.md.
import { parseArgs } from 'node:util';
import { drivenAccount } from '../driver/driver.mjs';

const HELP = `node cli/account.mjs [--session <name>]

Prints the driven session's account email and organization name, one per line, or
"none: API-key auth has no signed-in account". Reads only, so it takes no --dry-run.
--session names the session; without it, the one session running.

Exit: 0 printed, 1 no session or several running, or the session could not name the account, 2 a bad argument.`;

let session;
let help;
try {
  ({ values: { session, help } } = parseArgs({ options: { session: { type: 'string' }, help: { type: 'boolean' } } }));
} catch (err) {
  console.error(`account: ${err.message}; node cli/account.mjs --help shows its flags`);
  process.exit(2);
}
if (help) {
  console.log(HELP);
  process.exit(0);
}
try {
  console.log((await drivenAccount(session)).join('\n'));
} catch (err) {
  console.error(`account: ${err.message}`);
  process.exit(err.code === 2 ? 2 : 1);
}
