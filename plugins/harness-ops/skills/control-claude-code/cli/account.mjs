#!/usr/bin/env node
// Prints the signed-in account's email and organization name, one per line, for
// drive's mask post-check (SKILL.md `## Mask` `values:`). Reads only; see README.md.
import { authStatus, statusValues } from '../driver/driver.mjs';

const args = process.argv.slice(2);
if (args.length) {
  console.error(`account takes no arguments: ${args.join(' ')}`);
  process.exit(2);
}
try {
  const status = authStatus();
  const values = statusValues(status);
  if (values.length) console.log(values.join('\n'));
  else if (status?.authMethod === 'api_key') console.log('none: API-key auth has no signed-in account');
  // An --unattended capture keeps its credential away from this process (the CI driven session
  // holds only a broker's dummy key), so here Claude Code reports no login at all.
  else if (status?.loggedIn === false && status?.authMethod === 'none') console.log('none: no account is signed in');
  else throw new Error('claude auth status names no email or organization');
} catch (err) {
  console.error(`account: ${err.message}`);
  process.exit(1);
}
