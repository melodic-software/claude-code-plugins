/**
 * Post-extraction artifact quality validator.
 *
 * Runs declarative checks against course.json and the filesystem to verify
 * extraction completeness, schema consistency, and resource flag accuracy.
 * Writes validation-report.json for regression detection on subsequent runs.
 *
 * Usage:
 *   node validate-extraction.js --course-dir <path> [--verbose] [--quiet]
 *
 * Exit codes:
 *   0 — all checks passed (or warnings only)
 *   1 — one or more checks failed
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { createLogger } from "@melodic/video-digestion/shared/logger";

import {
  checkMetadata,
  checkRegression,
  checkResourceFlags,
  checkSchema,
  checkTranscripts,
  FAIL,
  WARN,
} from "./lib/validators.js";
import { loadCourseDir, parseCliArgs, resolveLogLevel } from "./utils.js";

const args = parseCliArgs();
const log = createLogger(resolveLogLevel(args));

function main() {
  const { courseDir, course } = loadCourseDir(args, { logger: log });
  const modulesDir = join(courseDir, "modules");
  const reportPath = join(courseDir, "validation-report.json");
  log.info(`\n  ${course.title} — Artifact Validation`);
  log.debug(`  Node: ${process.version} | OS: ${process.platform}`);

  const allChecks = [];

  log.info("  Running metadata checks...");
  allChecks.push(...checkMetadata(course));

  log.info("  Running transcript checks...");
  allChecks.push(...checkTranscripts(course, modulesDir));

  log.info("  Running schema checks...");
  allChecks.push(...checkSchema(course));

  log.info("  Running resource flag checks...");
  allChecks.push(...checkResourceFlags(course, modulesDir));

  if (existsSync(reportPath)) {
    try {
      const previousReport = JSON.parse(readFileSync(reportPath, "utf-8"));
      log.info("  Running regression checks...");
      const preSummary = {
        total: allChecks.length,
        passed: allChecks.filter((c) => c.severity === "pass").length,
        warnings: allChecks.filter((c) => c.severity === "warn").length,
        failed: allChecks.filter((c) => c.severity === "fail").length,
      };
      const regressions = checkRegression(
        { summary: preSummary, checks: allChecks },
        previousReport,
      );
      allChecks.push(...regressions);
    } catch {
      log.warn("  Could not parse previous validation-report.json — skipping regression checks");
    }
  } else {
    log.debug("  No previous validation-report.json — skipping regression checks");
  }

  const summary = {
    total: allChecks.length,
    passed: allChecks.filter((c) => c.severity === "pass").length,
    warnings: allChecks.filter((c) => c.severity === "warn").length,
    failed: allChecks.filter((c) => c.severity === "fail").length,
  };

  const currentReport = {
    timestamp: new Date().toISOString(),
    course: course.title,
    summary,
    checks: allChecks,
  };

  log.info("\n  ────────────────────────────────────────────");

  const failures = allChecks.filter((c) => c.severity === FAIL);
  const warnings = allChecks.filter((c) => c.severity === WARN);

  if (failures.length > 0) {
    log.info("  FAILURES:");
    for (const f of failures) {
      log.info(`    ✗ ${f.message}`);
      log.debug(`      ${JSON.stringify(f.details)}`);
    }
  }

  if (warnings.length > 0) {
    log.info("  WARNINGS:");
    for (const w of warnings) {
      log.info(`    ⚠ ${w.message}`);
      log.debug(`      ${JSON.stringify(w.details)}`);
    }
  }

  log.info(
    `\n  Summary: ${currentReport.summary.passed} passed, ${currentReport.summary.warnings} warnings, ${currentReport.summary.failed} failed (${currentReport.summary.total} total)`,
  );

  writeFileSync(reportPath, JSON.stringify(currentReport, null, 2), "utf-8");
  log.info(`  Report: ${reportPath}\n`);

  if (currentReport.summary.failed > 0) {
    process.exit(1);
  }
}

main();
