/**
 * Semantic synthesis PNG naming helpers (vision-gated promotion).
 */

import path from "node:path";

import { slugifyTitle } from "../transcript/derive-video-slug.js";

export const MAX_SYNTHESIS_NAME_CHARS = 48;

/** @type {readonly RegExp[]} */
export const FORBIDDEN_SYNTHESIS_NAME_PREFIXES = [
  /^at-/,
  /^scene_/,
  /^anchor_/,
  /^densification-/,
  /^dens-/,
  /^code-code-/,
  /^code-demo-/,
  /^code-terminal-/,
  /^code-slides-/,
  /^win-code-/,
];

/** @type {readonly RegExp[]} */
export const FORBIDDEN_SYNTHESIS_NAME_PATTERNS = [/dens-scene\d+/, /-m\d+(?:-s\d+)?\.png$/];

/** Pipeline filler session slugs (deprecated bulk-promote paths) — not claim-inventory segments. */
/** @type {readonly RegExp[]} */
export const FORBIDDEN_PIPELINE_SESSION_SLUG_PATTERNS = [/-topup$/, /^pipeline-/];

/** Gap-note templates emitted by tooling when vision did not run — not slice content. */
/** @type {readonly RegExp[]} */
export const PIPELINE_PLACEHOLDER_GAP_PATTERNS = [
  /^Frame in code densification window\.?$/i,
  /^Densification window \([^)]+\) visual evidence\.?$/i,
];

const KEBAB_NAME_RE = /^[a-z0-9]+(-[a-z0-9]+)*\.png$/;

/**
 * @param {string} sessionSlug
 * @returns {boolean}
 */
export function isForbiddenPipelineSessionSlug(sessionSlug) {
  if (!sessionSlug || typeof sessionSlug !== "string") {
    return false;
  }
  const slug = sessionSlug.trim();
  return FORBIDDEN_PIPELINE_SESSION_SLUG_PATTERNS.some((pattern) => pattern.test(slug));
}

/**
 * @param {string} gapNote
 * @returns {boolean}
 */
export function isPipelinePlaceholderGapNote(gapNote) {
  const trimmed = gapNote.trim();
  return PIPELINE_PLACEHOLDER_GAP_PATTERNS.some((pattern) => pattern.test(trimmed));
}

/**
 * @param {string} fileName
 * @returns {string|null}
 */
export function forbiddenSynthesisFileNameReason(fileName) {
  const base = path.basename(fileName);
  if (FORBIDDEN_SYNTHESIS_NAME_PREFIXES.some((pattern) => pattern.test(base))) {
    return `forbidden prefix/pattern: ${base}`;
  }
  if (FORBIDDEN_SYNTHESIS_NAME_PATTERNS.some((pattern) => pattern.test(base))) {
    return `forbidden pipeline token in name: ${base}`;
  }
  if (/\.png-\d+/.test(base)) {
    return "collision suffix forbidden";
  }
  if (!KEBAB_NAME_RE.test(base)) {
    return "must be semantic kebab-case.png";
  }
  return null;
}

/**
 * @param {string} gapNote
 * @param {Set<string>} [reserved]
 * @returns {string}
 */
export function deriveSemanticNameFromGapNote(gapNote, reserved = new Set()) {
  const cleaned = gapNote
    .replace(/^On-screen visual:\s*/i, "")
    .replace(/^On-screen\s*/i, "")
    .replace(/^Densification window \([^)]+\) visual evidence\.?$/i, "")
    .replace(/^Frame in code densification window\.?$/i, "")
    .replace(/\s+not fully in transcript\.?$/i, "")
    .trim();

  let slug = slugifyTitle(cleaned).slice(0, MAX_SYNTHESIS_NAME_CHARS).replace(/-+$/g, "");
  const forbiddenSlugPrefixes = [
    "densification-code",
    "densification",
    "dens-code",
    "dens-demo",
    "dens-terminal",
    "dens-scene",
    "code-code",
    "code-demo",
    "code-terminal",
    "code-slides",
    "win-code",
  ];
  for (const prefix of forbiddenSlugPrefixes) {
    if (slug.startsWith(prefix)) {
      slug = slug.slice(prefix.length).replace(/^-+/, "");
    }
  }
  if (!slug) {
    slug = "synthesis-frame";
  }

  let candidate = `${slug}.png`;
  let suffix = 2;
  while (reserved.has(candidate)) {
    const stem = slug.slice(0, Math.max(8, MAX_SYNTHESIS_NAME_CHARS - 4));
    candidate = `${stem}-${suffix}.png`;
    suffix += 1;
  }
  reserved.add(candidate);
  return candidate;
}

/**
 * @param {string} note
 * @returns {boolean}
 */
export function isStubQualityAuditNote(note) {
  const trimmed = note.trim().toLowerCase();
  if (trimmed.length < 20) {
    return true;
  }
  const stubTokens = new Set([
    "audit",
    "ok",
    "pass",
    "yes",
    "good",
    "reviewed",
    "fine",
    "looks good",
  ]);
  return stubTokens.has(trimmed);
}
