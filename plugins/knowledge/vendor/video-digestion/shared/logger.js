/**
 * Structured logger for video-digestion pipeline stages.
 *
 * Zero dependencies. OTEL-aligned severity levels.
 * Human-readable terminal output with level filtering.
 *
 * Severity mapping (OTEL Logs Data Model):
 *   DEBUG = 5, INFO = 9, WARN = 13, ERROR = 17
 *
 * CLI flag mapping:
 *   --verbose → debug | (default) → info | --quiet → warn
 */

import { writeStderr, writeStdout } from "./terminal.js";

export const SEVERITY = {
  debug: 5,
  info: 9,
  warn: 13,
  error: 17,
};

/**
 * @typedef {Object} PipelineLogger
 * @property {(...args: unknown[]) => void} debug
 * @property {(...args: unknown[]) => void} info
 * @property {(...args: unknown[]) => void} warn
 * @property {(...args: unknown[]) => void} error
 * @property {(result: import('./result.js').Result) => void} logResult
 * @property {(level: string) => boolean} shouldLog
 * @property {string} level
 * @property {number} severity
 */

/**
 * Create a logger with the specified minimum level.
 * Messages below the minimum level are silently dropped.
 *
 * @param {'debug' | 'info' | 'warn' | 'error'} [minLevel='info']
 * @returns {PipelineLogger}
 */
export function createLogger(minLevel = "info") {
  const minSeverity = SEVERITY[minLevel] ?? SEVERITY.info;

  /** @param {string} level */
  function shouldLog(level) {
    return (SEVERITY[/** @type {keyof typeof SEVERITY} */ (level)] ?? SEVERITY.info) >= minSeverity;
  }

  return {
    /** @param {...unknown} args */
    debug(...args) {
      if (shouldLog("debug")) writeStdout(...args);
    },
    /** @param {...unknown} args */
    info(...args) {
      if (shouldLog("info")) writeStdout(...args);
    },
    /** @param {...unknown} args */
    warn(...args) {
      if (shouldLog("warn")) writeStdout(...args);
    },
    /** @param {...unknown} args */
    error(...args) {
      if (shouldLog("error")) writeStderr(...args);
    },

    /**
     * Log a Result (domain probe pattern).
     * OK results log at INFO, failures at WARN.
     *
     * @param {import('./result.js').Result} result
     */
    logResult(result) {
      const level = result.success ? "info" : "warn";
      if (!shouldLog(level)) return;

      const ts = new Date().toISOString();
      const status = result.success ? "OK" : "FAIL";
      const ctx = result.context?.label ? ` ${result.context.label}` : "";
      const ms = `${Math.round(result.durationMs)}ms`;
      let detail = `(${ms})`;
      if (!result.success) {
        detail = `${result.error} (${ms})`;
      } else if (typeof result.data === "string") {
        detail = `(${result.data.length} chars, ${ms})`;
      }
      writeStdout(`  [${ts}] [${result.operation}]${ctx} — ${status}: ${detail}`);
    },

    shouldLog,
    level: minLevel,
    severity: minSeverity,
  };
}
