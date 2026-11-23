#!/usr/bin/env node
import { runPackageSetup } from "../../../vendor/node-launcher/setup-deps.mjs";

process.exit(runPackageSetup({ packageDir: import.meta.dirname, argv: process.argv.slice(2) }));
