#!/usr/bin/env node
/**
 * Source-adapter liveness lane for the video-digest pipeline.
 *
 * Offline (default for hermetic CI / `--offline`): replay recorded fixtures from
 * probes.json — no network, no yt-dlp required.
 *
 * Live (`--live`): spawn yt-dlp metadata probes against each probe URL and
 * compare extractor / id / format shape to the probe expectations. Never runs
 * on the merge path; the scheduled workflow owns live dispatch.
 *
 * Auth-required probes skip (never fail) when no cookies file is configured.
 *
 * Exit codes: 0 = all ok or skipped; 1 = drift / hard failure; 2 = usage error.
 */

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { spawnAsync } from "@melodic/video-digestion/shared/process";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_PROBES_PATH = path.join(HERE, "probes.json");
const ADAPTERS_REGISTRY_PATH = path.join(HERE, "..", "adapters", "registry.js");

const COOKIES_ENV_NAMES = [
  "VIDEO_DIGEST_YT_DLP_COOKIES_FILE",
  "YOUTUBE_YT_DLP_COOKIES_FILE",
];

/** Login-required stderr signatures (X raise_login_required cases). */
export const LOGIN_REQUIRED_PATTERNS = [
  /NSFW tweet requires authentication/im,
  /You are not authorized to view this protected tweet/im,
  /\bnot authorized\b/im,
];

/**
 * @typedef {"ok" | "login-required" | "error"} ProbeDisposition
 *
 * @typedef {object} ProbeObservation
 * @property {ProbeDisposition} disposition
 * @property {Record<string, unknown> | null} [metadata]
 * @property {string} [stderr]
 * @property {string} [error]
 *
 * @typedef {object} ProbeExpect
 * @property {string[]} [extractorKeys]
 * @property {string} [id]
 * @property {string} [displayId]
 * @property {number} [minFormats]
 * @property {ProbeDisposition} [disposition]
 *
 * @typedef {object} ProbeSpec
 * @property {string} id
 * @property {string} adapter
 * @property {string} url
 * @property {boolean} authRequired
 * @property {string} offlineFixture
 * @property {ProbeExpect} expect
 *
 * @typedef {object} ProbeResult
 * @property {string} id
 * @property {"pass" | "fail" | "skip"} status
 * @property {string} detail
 * @property {ProbeObservation} [observation]
 */

/**
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {string | null}
 */
export function resolveCookiesFile(env = process.env) {
  for (const name of COOKIES_ENV_NAMES) {
    const value = env[name]?.trim();
    if (value) return value;
  }
  return null;
}

/**
 * @param {string} stderr
 * @returns {boolean}
 */
export function isLoginRequiredStderr(stderr) {
  return LOGIN_REQUIRED_PATTERNS.some((pattern) => pattern.test(stderr ?? ""));
}

/**
 * @param {string} probesPath
 * @returns {Promise<{ probes: ProbeSpec[] }>}
 */
export async function loadProbes(probesPath = DEFAULT_PROBES_PATH) {
  const raw = JSON.parse(await fs.readFile(probesPath, "utf8"));
  if (!Array.isArray(raw.probes) || raw.probes.length === 0) {
    throw new Error(`probes file has no probes: ${probesPath}`);
  }
  return raw;
}

/**
 * @param {string} fixtureRel
 * @param {string} [baseDir]
 * @returns {Promise<ProbeObservation>}
 */
export async function loadOfflineFixture(fixtureRel, baseDir = HERE) {
  const absolute = path.resolve(baseDir, fixtureRel);
  const raw = JSON.parse(await fs.readFile(absolute, "utf8"));
  return {
    disposition: raw.disposition,
    metadata: raw.metadata ?? null,
    stderr: raw.stderr ?? "",
    error: raw.error,
  };
}

/**
 * @param {string} url
 * @param {{
 *   spawn?: typeof spawnAsync,
 *   cookiesFile?: string | null,
 *   env?: NodeJS.ProcessEnv,
 * }} [deps]
 * @returns {Promise<ProbeObservation>}
 */
export async function probeLiveUrl(url, deps = {}) {
  const spawn = deps.spawn ?? spawnAsync;
  const env = deps.env ?? process.env;
  const cookiesFile = deps.cookiesFile === undefined ? resolveCookiesFile(env) : deps.cookiesFile;

  /** @type {string[]} */
  const args = ["--skip-download", "--no-warnings", "-J", "--playlist-items", "1"];
  if (cookiesFile) {
    args.push("--cookies", cookiesFile);
  }
  args.push(url);

  const result = await spawn("yt-dlp", args, {
    timeout: 120_000,
    env,
  });

  const stderr = String(result.stderr ?? "");
  if (!result.success) {
    if (isLoginRequiredStderr(stderr)) {
      return { disposition: "login-required", metadata: null, stderr };
    }
    return {
      disposition: "error",
      metadata: null,
      stderr,
      error: `yt-dlp exited ${result.code ?? "non-zero"}`,
    };
  }

  try {
    const metadata = JSON.parse(String(result.stdout ?? ""));
    return { disposition: "ok", metadata, stderr };
  } catch (err) {
    return {
      disposition: "error",
      metadata: null,
      stderr,
      error: `failed to parse yt-dlp JSON: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}

/**
 * Optional adapter-registry round-trip when Phase 1+ adapters are present.
 *
 * @param {string} url
 * @param {string} expectedAdapterId
 * @returns {Promise<{ ok: boolean, detail: string }>}
 */
export async function checkAdapterDispatch(url, expectedAdapterId) {
  try {
    await fs.access(ADAPTERS_REGISTRY_PATH);
  } catch {
    return { ok: true, detail: "adapters registry not present — dispatch check skipped" };
  }

  try {
    const registry = await import(pathToFileURL(ADAPTERS_REGISTRY_PATH).href);
    const adapter = registry.resolveSourceAdapter(url);
    if (adapter.id !== expectedAdapterId) {
      return {
        ok: false,
        detail: `resolveSourceAdapter(${url}) → "${adapter.id}", expected "${expectedAdapterId}"`,
      };
    }
    const claim = adapter.matchUrl(url);
    if (!claim) {
      return { ok: false, detail: `adapter "${expectedAdapterId}" matchUrl returned null for ${url}` };
    }
    return { ok: true, detail: `adapter dispatch ok (${adapter.id})` };
  } catch (err) {
    return {
      ok: false,
      detail: `adapter dispatch failed: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}

/**
 * @param {ProbeObservation} observation
 * @param {ProbeExpect} expect
 * @returns {{ ok: boolean, detail: string }}
 */
export function compareObservation(observation, expect) {
  if (expect.disposition && observation.disposition !== expect.disposition) {
    return {
      ok: false,
      detail: `disposition ${observation.disposition} ≠ expected ${expect.disposition}`,
    };
  }

  if (expect.disposition === "login-required") {
    return { ok: true, detail: "login-required disposition matches" };
  }

  if (observation.disposition === "login-required") {
    return {
      ok: false,
      detail: "live probe returned login-required but probe does not expect that disposition",
    };
  }

  if (observation.disposition !== "ok" || !observation.metadata) {
    return {
      ok: false,
      detail: observation.error || observation.stderr || `disposition ${observation.disposition}`,
    };
  }

  const meta = observation.metadata;
  const extractorKey = String(meta.extractor_key ?? meta.extractor ?? "");
  if (expect.extractorKeys?.length) {
    const hit = expect.extractorKeys.some(
      (key) => key.toLowerCase() === extractorKey.toLowerCase(),
    );
    if (!hit) {
      return {
        ok: false,
        detail: `extractor_key "${extractorKey}" not in [${expect.extractorKeys.join(", ")}]`,
      };
    }
  }

  if (expect.id != null && String(meta.id ?? "") !== expect.id) {
    return { ok: false, detail: `id "${meta.id}" ≠ expected "${expect.id}"` };
  }

  if (expect.displayId != null) {
    const displayId = String(meta.display_id ?? meta.id ?? "");
    if (displayId !== expect.displayId) {
      return {
        ok: false,
        detail: `display_id "${displayId}" ≠ expected "${expect.displayId}"`,
      };
    }
  }

  if (expect.minFormats != null) {
    const formats = Array.isArray(meta.formats) ? meta.formats : [];
    if (formats.length < expect.minFormats) {
      return {
        ok: false,
        detail: `formats length ${formats.length} < minFormats ${expect.minFormats}`,
      };
    }
  }

  return { ok: true, detail: "shape matches expect" };
}

/**
 * @param {ProbeSpec} probe
 * @param {{
 *   mode: "offline" | "live",
 *   spawn?: typeof spawnAsync,
 *   cookiesFile?: string | null,
 *   env?: NodeJS.ProcessEnv,
 *   baseDir?: string,
 *   checkDispatch?: boolean,
 * }} options
 * @returns {Promise<ProbeResult>}
 */
export async function runProbe(probe, options) {
  const env = options.env ?? process.env;
  const cookiesFile =
    options.cookiesFile === undefined ? resolveCookiesFile(env) : options.cookiesFile;

  // Live only: absence of credentials skips auth-required rows (never fails).
  // Offline still replays the fixture so the login-required classifier stays covered.
  if (options.mode === "live" && probe.authRequired && !cookiesFile) {
    return {
      id: probe.id,
      status: "skip",
      detail: "authRequired and no cookies file configured — skip (never fail)",
    };
  }

  /** @type {ProbeObservation} */
  let observation;
  if (options.mode === "offline") {
    observation = await loadOfflineFixture(probe.offlineFixture, options.baseDir ?? HERE);
  } else {
    observation = await probeLiveUrl(probe.url, {
      spawn: options.spawn,
      cookiesFile,
      env,
    });
  }

  // Live auth-required probe that hit login-required despite cookies: still skip.
  // Offline fixtures asserting login-required must compare, not skip.
  if (
    options.mode === "live" &&
    probe.authRequired &&
    observation.disposition === "login-required"
  ) {
    return {
      id: probe.id,
      status: "skip",
      detail: "authRequired probe still login-required after cookies — skip (volatile auth window)",
      observation,
    };
  }

  const compared = compareObservation(observation, probe.expect);
  if (!compared.ok) {
    return { id: probe.id, status: "fail", detail: compared.detail, observation };
  }

  if (options.checkDispatch !== false) {
    const dispatch = await checkAdapterDispatch(probe.url, probe.adapter);
    if (!dispatch.ok) {
      return { id: probe.id, status: "fail", detail: dispatch.detail, observation };
    }
  }

  return { id: probe.id, status: "pass", detail: compared.detail, observation };
}

/**
 * @param {{
 *   mode: "offline" | "live",
 *   probesPath?: string,
 *   spawn?: typeof spawnAsync,
 *   cookiesFile?: string | null,
 *   env?: NodeJS.ProcessEnv,
 *   checkDispatch?: boolean,
 * }} options
 * @returns {Promise<{ results: ProbeResult[], failed: number, skipped: number, passed: number }>}
 */
export async function runAllProbes(options) {
  const { probes } = await loadProbes(options.probesPath ?? DEFAULT_PROBES_PATH);
  /** @type {ProbeResult[]} */
  const results = [];
  for (const probe of probes) {
    results.push(
      await runProbe(probe, {
        mode: options.mode,
        spawn: options.spawn,
        cookiesFile: options.cookiesFile,
        env: options.env,
        checkDispatch: options.checkDispatch,
      }),
    );
  }
  return {
    results,
    failed: results.filter((r) => r.status === "fail").length,
    skipped: results.filter((r) => r.status === "skip").length,
    passed: results.filter((r) => r.status === "pass").length,
  };
}

/**
 * @param {string[]} argv
 * @returns {{ mode: "offline" | "live", help: boolean, probesPath: string | null }}
 */
export function parseArgs(argv) {
  let mode = /** @type {"offline" | "live"} */ ("offline");
  let help = false;
  /** @type {string | null} */
  let probesPath = null;

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--live") {
      mode = "live";
    } else if (arg === "--offline") {
      mode = "offline";
    } else if (arg === "--help" || arg === "-h") {
      help = true;
    } else if (arg === "--probes") {
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("-")) {
        throw new Error("--probes requires a path argument");
      }
      probesPath = next;
      i += 1;
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  return { mode, help, probesPath };
}

function printHelp() {
  writeStdout(`Usage: node run-source-liveness.js [--offline|--live] [--probes <path>]

  --offline   Replay fixtures (default). Hermetic; no network / yt-dlp.
  --live      Probe each URL with yt-dlp -J (scheduled lane only).
  --probes    Alternate probes.json path.

Exit 0 when every probe passes or skips; 1 on drift; 2 on usage error.
`);
}

/**
 * @param {string[]} argv
 * @returns {Promise<number>}
 */
export async function main(argv = process.argv.slice(2)) {
  let parsed;
  try {
    parsed = parseArgs(argv);
  } catch (err) {
    writeStderr(`${err instanceof Error ? err.message : String(err)}\n`);
    printHelp();
    return 2;
  }

  if (parsed.help) {
    printHelp();
    return 0;
  }

  const summary = await runAllProbes({
    mode: parsed.mode,
    probesPath: parsed.probesPath ?? undefined,
  });

  for (const result of summary.results) {
    const tag = result.status.toUpperCase().padEnd(4);
    writeStdout(`${tag}  ${result.id}: ${result.detail}\n`);
  }
  writeStdout(
    `\n${parsed.mode}: ${summary.passed} passed, ${summary.skipped} skipped, ${summary.failed} failed\n`,
  );

  return summary.failed > 0 ? 1 : 0;
}

const isDirect =
  process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirect) {
  main().then((code) => {
    process.exitCode = code;
  });
}
