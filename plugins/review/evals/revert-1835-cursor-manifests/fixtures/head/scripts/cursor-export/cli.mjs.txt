// CLI entry for the Cursor companion-host export.
//
//   node scripts/generate-cursor-manifests.mjs           # write
//   node scripts/generate-cursor-manifests.mjs --check   # CI drift gate

import process from "node:process";
import { planCursorExport } from "./artifacts.mjs";
import { checkCursorExport, writeCursorExport } from "./io.mjs";
import { cursorMarketplacePath, defaultRepoRoot, rel } from "./paths.mjs";

export function runCursorExportCli(argv = process.argv.slice(2), repoRoot = defaultRepoRoot) {
  const check = argv.includes("--check");
  const { writes, counts } = planCursorExport(repoRoot);

  if (check) {
    const errors = checkCursorExport(repoRoot, writes);
    if (errors.length === 0) {
      console.log("Cursor manifests are in sync with the Claude SSOTs.");
      return 0;
    }
    console.error("Cursor manifest drift:");
    for (const error of errors) console.error(`  - ${error}`);
    console.error(
      "Run `node scripts/generate-cursor-manifests.mjs` and commit the result.",
    );
    return 1;
  }

  writeCursorExport(repoRoot, writes);
  const extras = [];
  if (counts.hooksStubs) {
    extras.push(`${counts.hooksStubs} empty Cursor hooks stub(s)`);
  }
  if (counts.mcpFiles) {
    extras.push(`${counts.mcpFiles} Cursor mcp.json file(s)`);
  }
  const extraNote = extras.length ? `, and ${extras.join(", ")}` : "";
  console.log(
    `Wrote ${rel(repoRoot, cursorMarketplacePath(repoRoot))}, ${counts.plugins} Cursor plugin manifests${extraNote}.`,
  );
  return 0;
}
