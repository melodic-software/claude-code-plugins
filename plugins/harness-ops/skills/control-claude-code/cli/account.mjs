#!/usr/bin/env node
// Prints the driven session's account email and organization name, one per line, for drive's mask
// post-check (SKILL.md `## Mask` `values:`). The session holder reads them in that session's own
// launch environment, which the caller may not share (in CI it runs in another sandbox). See README.md.
import { parseArgs } from 'node:util';
import { drivenAccount } from '../driver/driver.mjs';

let session;
try {
  ({ values: { session } } = parseArgs({ options: { session: { type: 'string' } } }));
} catch (err) {
  console.error(`account: ${err.message}`);
  process.exit(2);
}
try {
  console.log((await drivenAccount(session)).join('\n'));
} catch (err) {
  console.error(`account: ${err.message}`);
  process.exit(err.code === 2 ? 2 : 1);
}
