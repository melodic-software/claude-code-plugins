#!/usr/bin/env node
/**
 * Verify transcript-sourced golden answers against a cleaned transcript file.
 *
 * Usage:
 *   node evals/check-transcript-goldens.js <transcript.txt> <goldens.json>
 */

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

/**
 * @param {string} value
 * @returns {string}
 */
export function normalizeTranscriptText(value) {
  return value
    .toLowerCase()
    .replace(/&gt;/g, ">")
    .replace(/&lt;/g, "<")
    .replace(/\b(\d+)\s*m\b/g, "$1 meters")
    .replace(/[^\w\s;]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const CLAUSE_WORD_SPLIT_PATTERN = /\s+/;

/**
 * @param {string} hay
 * @param {string} clause
 * @param {number} threshold
 * @returns {boolean}
 */
export function clauseMatches(hay, clause, threshold = 0.6) {
  const parts = clause.split(CLAUSE_WORD_SPLIT_PATTERN).filter((part) => part.length > 2);

  if (parts.length === 0) return false;

  const partMatches = (part) => {
    if (hay.includes(part)) return true;
    if (part.length > 5 && part.endsWith("ing") && hay.includes(part.slice(0, -3))) return true;
    return false;
  };

  const matched = parts.filter((part) => partMatches(part)).length;
  return matched / parts.length >= threshold;
}

/**
 * @param {string} haystack
 * @param {string} needle
 * @returns {boolean}
 */
export function fuzzyContains(haystack, needle) {
  const hay = normalizeTranscriptText(haystack);
  const clauses = needle
    .split(";")
    .map((clause) => normalizeTranscriptText(clause))
    .filter(Boolean);

  if (clauses.length > 1) {
    return clauses.every((clause) => clauseMatches(hay, clause, 0.4));
  }

  return clauseMatches(hay, normalizeTranscriptText(needle), 0.6);
}

/**
 * @param {string} transcriptPath
 * @param {string} goldensPath
 * @returns {Promise<{ passed: number; failed: Array<{ id: string; reason: string }> }>}
 */
export async function checkTranscriptGoldens(transcriptPath, goldensPath) {
  const transcript = await fs.readFile(transcriptPath, "utf8");
  const fixture = JSON.parse(await fs.readFile(goldensPath, "utf8"));
  const goldens = fixture.goldens ?? fixture;

  /** @type {Array<{ id: string; reason: string }>} */
  const failed = [];
  let passed = 0;

  for (const golden of goldens) {
    if (golden.frame_only) continue;

    const answer = golden.expected_answer ?? "";
    if (!answer) {
      failed.push({ id: golden.id, reason: "missing expected_answer" });
      continue;
    }

    if (fuzzyContains(transcript, answer)) {
      passed += 1;
    } else {
      failed.push({ id: golden.id, reason: `transcript missing expected answer: ${answer}` });
    }
  }

  return { passed, failed };
}

/**
 * @param {string[]} argv
 * @returns {Promise<number>}
 */
export async function runCheckTranscriptGoldensCli(argv) {
  const transcriptPath = argv[2];
  const goldensPath = argv[3];
  if (!transcriptPath || !goldensPath) {
    process.stderr.write(
      "Usage: node evals/check-transcript-goldens.js <transcript.txt> <goldens.json>\n",
    );
    return 1;
  }

  const result = await checkTranscriptGoldens(transcriptPath, goldensPath);
  if (result.failed.length > 0) {
    for (const failure of result.failed) {
      process.stderr.write(`FAIL: ${failure.id} — ${failure.reason}\n`);
    }
    return 1;
  }

  process.stdout.write(`PASS: ${result.passed} transcript golden(s)\n`);
  return 0;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  runCheckTranscriptGoldensCli(process.argv)
    .then((code) => process.exit(code))
    .catch((err) => {
      process.stderr.write(`${err instanceof Error ? err.message : String(err)}\n`);
      process.exit(1);
    });
}
