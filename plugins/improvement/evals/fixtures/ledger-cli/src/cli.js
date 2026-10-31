import config from "../config/ledger.json" with { type: "json" };
import { printReport } from "./report.js";
import { writeExport } from "./export.js";

const [command] = process.argv.slice(2);

if (command === "report") {
  printReport(config);
} else if (command === "export") {
  writeExport(config);
} else {
  console.error("usage: ledger <report|export>");
  process.exit(1);
}
