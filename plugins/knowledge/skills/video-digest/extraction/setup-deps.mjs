#!/usr/bin/env node
/**
 * Install this package's node dependencies into the plugin data directory through
 * the shared installer (`vendor/node-launcher/setup-deps.mjs`), which reads this
 * package's `setupDeps` entry in package.json.
 *
 * Usage: node setup-deps.mjs --data-dir <dir>
 */
import { runPackageSetup } from "../../../vendor/node-launcher/setup-deps.mjs";

process.exit(runPackageSetup({ packageDir: import.meta.dirname, argv: process.argv.slice(2) }));
