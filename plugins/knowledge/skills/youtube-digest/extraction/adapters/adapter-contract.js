/**
 * Source-adapter contract for the video-digest extraction pipeline.
 *
 * Contract stability: PRIVATE. This contract is versioned with the plugin and may
 * change in any release; it is not a public extension point. Adapters live in this
 * directory and are registered in `registry.js` via static imports only.
 *
 * Construction rule: adapter construction (`createSourceAdapter`) performs no network
 * or filesystem I/O — only validation and cheap pure normalization. All I/O happens
 * inside `acquire` at call time.
 *
 * ## Result envelope
 *
 * `acquire` resolves to an {@link AcquisitionEnvelope}: a collection of 0..N entry
 * results plus one shared metadata object. Arity is a property of the RESULT, never
 * of the adapter — a source may yield 0, 1, or N media entries per post/video, and
 * all three are well-formed. A 0-entry envelope is a valid metadata-only result:
 * never `null`, never a throw. Consumers must not assume exactly one entry; the
 * {@link singleEntry} convenience accessor may collapse arity at a call site, the
 * contract itself never does.
 *
 * The shared metadata object is an open namespace: adapters may add fields, and
 * keys prefixed `source:` are reserved for source-specific extensions. Transcripts
 * travel as replayable caption FILE PATHS on each entry (`captionPaths`, `caption`),
 * never as inline text.
 *
 * ## Error taxonomy
 *
 * Exactly four types:
 *
 * - {@link UnsupportedSourceError} — dispatch-level "no adapter claims this URL",
 *   deliberately OUTSIDE the adapter error hierarchy (the adapter is never reached).
 * - {@link RetryableSourceError} — the source failed transiently; the shared retry
 *   loop may re-attempt. Degradation detail (e.g. a rate-limited fallback response)
 *   is carried as `degradation` METADATA on this type, never as a fifth type.
 * - {@link FatalSourceError} — the source answered definitively (gone, private,
 *   invalid); retrying cannot help.
 * - {@link LoginRequiredError} — the source demands authentication; ONLY this class
 *   gates cookie-based auth fallback.
 *
 * "Mine but empty" is NOT an error — it is a well-formed 0-entry envelope.
 *
 * Adapters additionally declare the same taxonomy as a pattern table
 * ({@link SourceErrorPatterns}) so shared spawn-level machinery can classify child
 * process stderr without a per-adapter callback ({@link classifyErrorDetail}).
 */

import { CAPTION_CLASSES } from "../acquisition/select-caption.js";

/** @import { CaptionClass, CaptionSelection } from '../acquisition/select-caption.js' */
/** @import { HarvestedLink } from '../harvesting/models.js' */

/**
 * Per-source transcript strategy (T5): how a transcript is produced from the
 * acquired artifacts. Adapters declare a default; the pipeline may override.
 *
 * @typedef {'captions'|'captions+repair'|'asr'} TranscriptStrategy
 */

/**
 * Dispatch-level error: no registered adapter owns the URL's host. Deliberately not
 * part of the adapter error hierarchy — it is thrown by the registry before any
 * adapter is selected. Always lists the supported sources so the failure is
 * actionable.
 */
export class UnsupportedSourceError extends Error {
  /**
   * @param {string} url
   * @param {readonly string[]} supportedHosts
   */
  constructor(url, supportedHosts) {
    super(
      `Unsupported source URL: ${url}. Supported sources: ${supportedHosts.join(", ")}`,
    );
    this.name = "UnsupportedSourceError";
    this.supportedHosts = supportedHosts;
  }
}

/** Transient source failure — eligible for the shared retry loop. */
export class RetryableSourceError extends Error {
  /**
   * @param {string} message
   * @param {Record<string, unknown>|null} [degradation] - degradation detail
   *   (e.g. rate-limited fallback markers); metadata on this type, never a fifth type
   */
  constructor(message, degradation = null) {
    super(message);
    this.name = "RetryableSourceError";
    this.degradation = degradation;
  }
}

/** Definitive source failure — retrying cannot help. */
export class FatalSourceError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = "FatalSourceError";
  }
}

/** The source demands authentication; the only class that gates cookie fallback. */
export class LoginRequiredError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = "LoginRequiredError";
  }
}

/**
 * @typedef {Object} SourceErrorPatterns
 * @property {readonly RegExp[]} retryable - stderr signatures of transient failures
 * @property {readonly RegExp[]} fatal - stderr signatures of definitive failures
 * @property {readonly RegExp[]} loginRequired - stderr signatures that gate cookie fallback
 */

/**
 * Classify a child-process failure detail against an adapter's declared patterns.
 *
 * Precedence: login-required, then fatal, then retryable. `null` means
 * unclassified — the caller applies its own default (e.g. preflight treats
 * unclassified as transient).
 *
 * @param {SourceErrorPatterns} errorPatterns
 * @param {string} detail
 * @returns {'login-required'|'fatal'|'retryable'|null}
 */
export function classifyErrorDetail(errorPatterns, detail) {
  if (!detail) return null;
  if (errorPatterns.loginRequired.some((pattern) => pattern.test(detail))) {
    return "login-required";
  }
  if (errorPatterns.fatal.some((pattern) => pattern.test(detail))) {
    return "fatal";
  }
  if (errorPatterns.retryable.some((pattern) => pattern.test(detail))) {
    return "retryable";
  }
  return null;
}

/**
 * @typedef {Object} UrlClaim
 * @property {string} sliceKey - URL-authoritative slice identity (e.g. the video id)
 * @property {string} canonicalUrl - the URL the pipeline should acquire from
 */

/**
 * @typedef {Object} EnqueueDecision
 * @property {boolean} ok
 * @property {string} [key] - slice key when accepted
 * @property {string} [note] - queue-table note cell when rejected
 * @property {string} [reason] - human reason when rejected
 */

/**
 * Shared acquisition metadata. Open namespace: adapters may carry additional
 * fields; keys prefixed `source:` are reserved for source-specific extensions.
 *
 * @typedef {Object} SourceMetadata
 * @property {string} id
 * @property {string} title
 * @property {string} description
 */

/**
 * One acquired media entry. `mediaPath` is `""` when no media was downloaded
 * (transcript mode, or a media-less entry).
 *
 * @typedef {Object} SourceEntryResult
 * @property {string} mediaPath
 * @property {string[]} captionPaths - replayable caption file paths
 * @property {string} metadataPath - source metadata JSON file path ("" when absent)
 * @property {CaptionSelection|null} caption - selected caption, when one resolved
 */

/**
 * @typedef {Object} AcquisitionEnvelope
 * @property {readonly SourceEntryResult[]} entries - 0..N entry results
 * @property {SourceMetadata} metadata - shared metadata (open namespace)
 * @property {string} workDir - staging directory the entries' paths live under
 * @property {Record<string, unknown>} [acquireMetrics]
 */

/**
 * Construct a validated, frozen acquisition envelope. A 0-entry envelope is
 * well-formed (metadata-only result); `entries` and `metadata` are required.
 *
 * @param {Object} parts
 * @param {SourceEntryResult[]} parts.entries
 * @param {SourceMetadata} parts.metadata
 * @param {string} parts.workDir
 * @param {Record<string, unknown>} [parts.acquireMetrics]
 * @returns {AcquisitionEnvelope}
 */
export function createAcquisitionEnvelope({ entries, metadata, workDir, acquireMetrics }) {
  if (!Array.isArray(entries)) {
    throw new TypeError("AcquisitionEnvelope.entries must be an array (0..N entries)");
  }
  for (const [index, entry] of entries.entries()) {
    if (!entry || typeof entry !== "object") {
      throw new TypeError(`AcquisitionEnvelope.entries[${index}] must be an object`);
    }
    if (typeof entry.mediaPath !== "string") {
      throw new TypeError(`AcquisitionEnvelope.entries[${index}].mediaPath must be a string`);
    }
    if (!Array.isArray(entry.captionPaths)) {
      throw new TypeError(`AcquisitionEnvelope.entries[${index}].captionPaths must be an array`);
    }
    if (typeof entry.metadataPath !== "string") {
      throw new TypeError(`AcquisitionEnvelope.entries[${index}].metadataPath must be a string`);
    }
  }
  if (!metadata || typeof metadata !== "object") {
    throw new TypeError("AcquisitionEnvelope.metadata must be an object");
  }
  if (typeof workDir !== "string") {
    throw new TypeError("AcquisitionEnvelope.workDir must be a string");
  }
  /** @type {AcquisitionEnvelope} */
  const envelope = {
    entries: Object.freeze(entries.map((entry) => Object.freeze({ ...entry }))),
    metadata,
    workDir,
    ...(acquireMetrics !== undefined ? { acquireMetrics } : {}),
  };
  return Object.freeze(envelope);
}

/**
 * Convenience accessor: the envelope's single entry when arity is exactly 1,
 * `null` otherwise. Call sites may collapse arity through this; the contract
 * itself never does.
 *
 * @param {AcquisitionEnvelope} envelope
 * @returns {SourceEntryResult|null}
 */
export function singleEntry(envelope) {
  return envelope.entries.length === 1 ? envelope.entries[0] : null;
}

/**
 * Convenience accessor for call sites that operate on one distinguished entry:
 * the first media-bearing entry, else the first caption-bearing entry, else
 * the first entry, else null. Defined ONCE here so transcript naming and
 * watch orchestration always pair on the same entry.
 *
 * @param {AcquisitionEnvelope} envelope
 * @returns {SourceEntryResult|null}
 */
export function primaryEntry(envelope) {
  const { entries } = envelope;
  return (
    entries.find((entry) => Boolean(entry.mediaPath)) ??
    entries.find((entry) => Boolean(entry.caption)) ??
    entries[0] ??
    null
  );
}

/**
 * Outcome of an adapter `acquire` call (structurally the shared `ok`/`fail`
 * result shape, with the envelope as payload).
 *
 * @typedef {Object} AcquireOutcome
 * @property {boolean} success
 * @property {AcquisitionEnvelope} [data]
 * @property {string} [error]
 */

/**
 * Context the shared driver supplies to `acquire`: the resolved staging
 * directory the adapter must land artifacts in, the pipeline mode, and
 * injectable I/O for tests. Auth and throttle context are supplied by the
 * shared machinery the adapter composes; the adapter never reads global state
 * to find its output directory.
 *
 * @typedef {Object} AcquireContext
 * @property {string} workDir - staging directory; MUST be empty and exclusive
 *   to this acquisition (adapters attribute every file found under it to this
 *   post — a shared or pre-populated directory breaks provenance and entry
 *   matching; production entry points mkdtemp a fresh one per run)
 * @property {'full'|'transcript'} mode - 'transcript' must not download media
 * @property {object} [deps] - adapter-specific injectable I/O (tests only)
 */

/**
 * @callback MatchUrlFn
 * @param {string} url
 * @returns {UrlClaim|null} claim + canonicalization; null when the adapter does
 *   not claim the URL. Pure — no I/O.
 */

/**
 * @callback ExtractSliceKeyFn
 * @param {string} url
 * @param {SourceMetadata|null} metadata - null when called before acquisition
 *   (queue lane); the key is URL-authoritative, metadata is a fallback only
 * @returns {string|null} the slice key, which becomes an on-disk directory
 *   segment: it MUST match `[A-Za-z0-9_-]+` (no separators, no dots) — the
 *   shared slug derivation rejects anything else, so a non-conforming key is
 *   an adapter bug, not a path
 */

/**
 * @callback AcquireFn
 * @param {string} url - canonical URL (from `matchUrl`)
 * @param {AcquireContext} context
 * @returns {Promise<AcquireOutcome>} envelope with media path(s), caption
 *   path(s), and the shared metadata object
 */

/**
 * @callback HarvestLinksFn
 * @param {SourceMetadata} metadata
 * @returns {HarvestedLink[]}
 */

/**
 * @callback AcceptForEnqueueFn
 * @param {string} url
 * @returns {EnqueueDecision} pure URL-shape gate for the queue lane; no I/O
 */

/**
 * Optional behaviors, CLOSED BY DEFAULT: an adapter that omits a capability
 * declares it absent, and shared machinery must treat absence as `false`.
 *
 * @typedef {Object} SourceCapabilities
 * @property {boolean} [comments] - source exposes harvestable comments; gates the
 *   comment-download flag in acquisition args
 * @property {boolean} [browserCookieFallback] - the browser-cookie-profile
 *   fallback loop may iterate for this source; a cookies-file-only source
 *   declares false and must never iterate browser profiles
 * @property {boolean} [mediaOptional] - a 0-media post/URL is a well-formed
 *   metadata-only result for this source: acquisition and queue preflight pass
 *   `--ignore-no-formats-error` so yt-dlp reports metadata instead of erroring
 * @property {boolean} [contentClaim] - RESERVED, UNIMPLEMENTED: content-shaped
 *   (non-host) URL claims. Declaring `true` is rejected until implemented.
 */

/**
 * @typedef {Object} SourceAdapter
 * @property {string} id - stable source identifier (e.g. "youtube")
 * @property {readonly string[]} hosts - owned hosts; the registry's keys
 * @property {string|null} extractorArgs - acquisition extractor args, or null
 * @property {string|null} allowedExtractors - acquisition extractor allow-list
 *   for this source's URLs (`--use-extractors` value), or null for no
 *   restriction. A source whose upstream extractor can delegate to foreign
 *   URLs MUST declare one so the delegation is refused without any fetch
 *   (SSRF guard); every probe/acquire/preflight invocation consumes it.
 * @property {CaptionClass} captionClass - declared caption provenance class,
 *   consumed by the shared caption-selection ladder
 *   (`acquisition/select-caption.js`); must be one of {@link CAPTION_CLASSES}
 * @property {SourceErrorPatterns} errorPatterns
 * @property {TranscriptStrategy} transcriptStrategy - per-source default;
 *   pipeline-overridable
 * @property {SourceCapabilities} capabilities
 * @property {MatchUrlFn} matchUrl
 * @property {ExtractSliceKeyFn} extractSliceKey
 * @property {AcquireFn} acquire
 * @property {HarvestLinksFn} harvestLinks
 * @property {AcceptForEnqueueFn} acceptForEnqueue
 */

/** @typedef {SourceAdapter} SourceAdapterSpec */

export const REQUIRED_METHODS = Object.freeze([
  "matchUrl",
  "extractSliceKey",
  "acquire",
  "harvestLinks",
  "acceptForEnqueue",
]);

/**
 * Declared parameter counts, enforced at runtime because the type lane accepts
 * too-few-parameters silently (`checkJs` with `strict: false`).
 */
export const REQUIRED_METHOD_ARITY = Object.freeze({
  matchUrl: 1,
  extractSliceKey: 2,
  acquire: 2,
  harvestLinks: 1,
  acceptForEnqueue: 1,
});

/** The transcript-strategy vocabulary ({@link TranscriptStrategy}). */
export const TRANSCRIPT_STRATEGIES = Object.freeze(
  /** @type {readonly TranscriptStrategy[]} */ (["captions", "captions+repair", "asr"]),
);
const KNOWN_CAPABILITIES = Object.freeze([
  "comments",
  "browserCookieFallback",
  "mediaOptional",
  "contentClaim",
]);
const ERROR_PATTERN_CLASSES = Object.freeze(["retryable", "fatal", "loginRequired"]);
const HOST_KEY_PATTERN = /^[a-z0-9][a-z0-9.-]*$/;

/**
 * Validate an adapter spec against the contract. Returns violation messages
 * (empty when valid). Pure — no I/O.
 *
 * @param {object} spec
 * @returns {string[]}
 */
// biome-ignore lint/complexity/noExcessiveCognitiveComplexity: single exhaustive contract walk; splitting would scatter the contract
export function validateAdapter(spec) {
  /** @type {string[]} */
  const violations = [];
  if (!spec || typeof spec !== "object") {
    return ["adapter spec must be an object"];
  }
  const record = /** @type {Record<string, unknown>} */ (spec);

  for (const method of REQUIRED_METHODS) {
    const value = record[method];
    if (typeof value !== "function") {
      violations.push(`required method "${method}" is missing or not a function`);
      continue;
    }
    const expected =
      REQUIRED_METHOD_ARITY[/** @type {keyof typeof REQUIRED_METHOD_ARITY} */ (method)];
    if (value.length !== expected) {
      violations.push(
        `method "${method}" declares ${value.length} parameter(s); the contract requires exactly ${expected} (no defaulted/rest required parameters)`,
      );
    }
  }

  if (typeof record.id !== "string" || record.id.length === 0) {
    violations.push('attribute "id" must be a non-empty string');
  }
  if (
    !Array.isArray(record.hosts) ||
    record.hosts.length === 0 ||
    !record.hosts.every(
      (host) => typeof host === "string" && HOST_KEY_PATTERN.test(host),
    )
  ) {
    violations.push(
      'attribute "hosts" must be a non-empty array of lowercase bare hostnames (no scheme, no path)',
    );
  }
  if (record.extractorArgs !== null && typeof record.extractorArgs !== "string") {
    violations.push('attribute "extractorArgs" must be a string or null');
  }
  if (record.allowedExtractors !== null && typeof record.allowedExtractors !== "string") {
    violations.push('attribute "allowedExtractors" must be a string or null');
  }
  if (
    typeof record.captionClass !== "string" ||
    !CAPTION_CLASSES.includes(/** @type {CaptionClass} */ (record.captionClass))
  ) {
    violations.push(
      `attribute "captionClass" must be one of: ${CAPTION_CLASSES.join(", ")} (the classes the shared caption ladder consumes)`,
    );
  }
  if (
    typeof record.transcriptStrategy !== "string" ||
    !TRANSCRIPT_STRATEGIES.includes(
      /** @type {TranscriptStrategy} */ (record.transcriptStrategy),
    )
  ) {
    violations.push(
      `attribute "transcriptStrategy" must be one of: ${TRANSCRIPT_STRATEGIES.join(", ")}`,
    );
  }

  const patterns = record.errorPatterns;
  if (!patterns || typeof patterns !== "object") {
    violations.push('attribute "errorPatterns" must be an object');
  } else {
    const patternRecord = /** @type {Record<string, unknown>} */ (patterns);
    for (const cls of ERROR_PATTERN_CLASSES) {
      const list = patternRecord[cls];
      if (!Array.isArray(list) || !list.every((entry) => entry instanceof RegExp)) {
        violations.push(`errorPatterns.${cls} must be an array of RegExp`);
      }
    }
    for (const key of Object.keys(patternRecord)) {
      if (!ERROR_PATTERN_CLASSES.includes(key)) {
        violations.push(
          `errorPatterns declares unknown class "${key}" (taxonomy is exactly: ${ERROR_PATTERN_CLASSES.join(", ")})`,
        );
      }
    }
  }

  const capabilities = record.capabilities;
  if (!capabilities || typeof capabilities !== "object") {
    violations.push('attribute "capabilities" must be an object (closed by default)');
  } else {
    const capabilityRecord = /** @type {Record<string, unknown>} */ (capabilities);
    for (const [key, value] of Object.entries(capabilityRecord)) {
      if (!KNOWN_CAPABILITIES.includes(key)) {
        violations.push(
          `capabilities declares unknown capability "${key}" (capabilities are closed; known: ${KNOWN_CAPABILITIES.join(", ")})`,
        );
      } else if (typeof value !== "boolean") {
        violations.push(`capability "${key}" must be a boolean`);
      }
    }
    if (capabilityRecord.contentClaim === true) {
      violations.push('capability "contentClaim" is reserved and unimplemented; it must not be declared true');
    }
  }

  return violations;
}

/**
 * Validate and freeze an adapter spec. Throws on any contract violation.
 * Performs no network or filesystem I/O.
 *
 * @param {SourceAdapterSpec} spec
 * @returns {SourceAdapter}
 */
export function createSourceAdapter(spec) {
  const violations = validateAdapter(spec);
  if (violations.length > 0) {
    throw new Error(
      `Invalid source adapter${spec && typeof spec.id === "string" ? ` "${spec.id}"` : ""}:\n- ${violations.join("\n- ")}`,
    );
  }
  const adapter = {
    ...spec,
    hosts: Object.freeze([...spec.hosts]),
    errorPatterns: Object.freeze({
      retryable: Object.freeze([...spec.errorPatterns.retryable]),
      fatal: Object.freeze([...spec.errorPatterns.fatal]),
      loginRequired: Object.freeze([...spec.errorPatterns.loginRequired]),
    }),
    capabilities: Object.freeze({ ...spec.capabilities }),
  };
  return Object.freeze(adapter);
}
