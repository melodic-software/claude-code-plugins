#!/usr/bin/env node

// Thin CLI wrapper for the Cursor companion-host export package.
// Implementation lives in scripts/cursor-export/ (one concern per module).
//
// Authoritative schemas (re-fetch before changing the export package):
//   https://cursor.com/docs/reference/plugins
//   https://cursor.com/docs/hooks
//   https://cursor.com/docs/reference/third-party-hooks
//   https://code.claude.com/docs/en/plugins-reference
//
// Ownership and design rules: scripts/cursor-export/README.md
//
//   node scripts/generate-cursor-manifests.mjs           # write
//   node scripts/generate-cursor-manifests.mjs --check   # CI drift gate

import process from "node:process";
import { resolve } from "node:path";
import { runCursorExportCli } from "./cursor-export/cli.mjs";

const invokedAsCli =
  Boolean(process.argv[1]) &&
  resolve(process.argv[1]) === resolve(import.meta.filename);

if (import.meta.main || invokedAsCli) {
  process.exit(runCursorExportCli(process.argv.slice(2)));
}
