import { balances } from "./balances.js";

function roundAmount(cents, precision) {
  const factor = 10 ** precision;
  return Math.round((cents / 100) * factor) / factor;
}

export function printReport(config) {
  for (const [account, cents] of Object.entries(balances())) {
    console.log(`${account}: ${roundAmount(cents, config.precision)} ${config.currency}`);
  }
}
