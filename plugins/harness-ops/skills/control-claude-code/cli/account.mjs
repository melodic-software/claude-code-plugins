#!/usr/bin/env node
// Prints the signed-in account's email and organization name, one per line, for
// drive's mask post-check (SKILL.md `## Mask` `values:`). Reads only; see README.md.
import { accountValues } from '../driver/driver.mjs';

const args = process.argv.slice(2);
if (args.length) {
  console.error(`account takes no arguments: ${args.join(' ')}`);
  process.exit(2);
}
try {
  const values = accountValues();
  if (!values.length) throw new Error('claude auth status names no email or organization');
  console.log(values.join('\n'));
} catch (err) {
  console.error(`account: ${err.message}`);
  process.exit(1);
}
