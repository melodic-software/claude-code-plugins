/**
 * Adapter contract definition and factory for the course-extraction pipeline.
 *
 * Each platform adapter is a plain object implementing these methods.
 * No classes, no inheritance - composition via method properties.
 *
 * The contract prescribes WHAT adapters produce, not HOW they produce it.
 * Dometrain reads DOM directly. Teachable intercepts network traffic and
 * fetches from cross-origin iframe contexts. Both return the same result types.
 */

/** @typedef {import('@melodic/video-digestion/shared/result').Result} PipelineResult */

/**
 * @typedef {Object} CourseExtractAdapter
 * @property {(page: import('playwright').Page, platformCfg: object) => Promise<PipelineResult>} extractTranscript
 * @property {(page: import('playwright').Page, platformCfg: object) => Promise<PipelineResult>} extractHlsUrl
 * @property {(page: import('playwright').Page, platformCfg: object) => Promise<PipelineResult>} detectResources
 * @property {(courseUrl: string, platformCfg: object) => string} deriveLandingUrl
 * @property {(course: object, lesson: object, platformCfg: object) => string} buildLessonUrl
 * @property {(page: import('playwright').Page, platformCfg: object) => Promise<void>} [setupSession]
 * @property {(page: import('playwright').Page, platformCfg: object, lesson: object) => Promise<PipelineResult>} [prepareLessonPage]
 * @property {(page: import('playwright').Page, platformCfg: object) => Promise<PipelineResult>} [extractResources]
 * @property {(page: import('playwright').Page, courseUrl: string, platformCfg: object) => Promise<PipelineResult>} [extractMetadata]
 * @property {(input: import('./auth-session.js').AuthSessionInput) => Promise<void>} [authenticate]
 * @property {(page: import('playwright').Page, platformCfg: object) => Promise<PipelineResult>} [preflight]
 * @property {(platformCfg: object) => void} [validateConfig]
 * @property {object} [defaults]
 */

import { fail, ok } from "@melodic/video-digestion/shared/result";

import { resolveAdapter, validatePlatformConfig } from "../lib/config.js";

const REQUIRED_METHODS = [
  "extractTranscript",
  "extractHlsUrl",
  "detectResources",
  "deriveLandingUrl",
  "buildLessonUrl",
];

/**
 * Validate that an adapter object implements all required methods.
 * @param {object} adapter
 * @param {string} platform
 * @returns {PipelineResult}
 */
export function validateAdapter(adapter, platform) {
  const missing = REQUIRED_METHODS.filter((m) => typeof adapter[m] !== "function");
  if (missing.length > 0) {
    return fail(
      `Adapter "${platform}" missing required methods: ${missing.join(", ")}`,
      "validate-adapter",
      null,
      0,
    );
  }
  return ok(adapter, "validate-adapter", null, 0);
}

/**
 * Resolve, validate, and return an adapter for the given platform.
 * Validates both the platformConfig and the adapter contract.
 *
 * @param {string} platform
 * @param {object} platformCfg
 * @returns {Promise<PipelineResult>}
 */
export async function createAdapter(platform, platformCfg) {
  const configResult = validatePlatformConfig(platformCfg, platform);
  if (!configResult.success) return configResult;

  const adapterModule = await resolveAdapter(platform);
  if (!adapterModule) {
    return fail(
      `No adapter found for platform "${platform}". Expected: adapters/${platform}.js`,
      "create-adapter",
      null,
      0,
    );
  }

  const adapterResult = validateAdapter(adapterModule, platform);
  if (!adapterResult.success) return adapterResult;

  return ok(adapterModule, "create-adapter", null, 0);
}
