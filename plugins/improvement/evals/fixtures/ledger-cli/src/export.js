import { writeFileSync } from "node:fs";
import { balances } from "./balances.js";

function roundAmount(cents, precision) {
  const factor = 10 ** precision;
  return Math.round((cents / 100) * factor) / factor;
}

export function writeExport(config) {
  const rows = Object.entries(balances()).map(
    ([account, cents]) => `${account},${roundAmount(cents, config.precision)},${config.currency}`,
  );
  writeFileSync("balances.csv", ["account,amount,currency", ...rows].join("\n"));
}
