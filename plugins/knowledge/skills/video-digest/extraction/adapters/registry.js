/**
 * Static host-keyed source-adapter registry.
 *
 * Dispatch is a STATIC map from owned host to a statically-imported adapter
 * module — never a computed dynamic import in any spelling (template, variable,
 * concatenation, helper-mediated). A static map is type-checkable and
 * untraversable, where an interpolated import specifier fed URL-derived input
 * is neither (CWE-829/CWE-22).
 *
 * Host matching rule: a URL's hostname (lowercased, trailing dot stripped)
 * matches a registered host when it equals the host exactly or ends with
 * `.<host>` — so `www.youtube.com`, `m.youtube.com`, and `music.youtube.com`
 * all resolve to the `youtube.com` owner, while `notyoutube.com` and
 * `youtube.com.evil.example` do not. Adapter URL patterns (`matchUrl`) are
 * evaluated only AFTER owned-host selection. An unknown host fails closed with
 * the supported-source list ({@link UnsupportedSourceError}).
 */

import { UnsupportedSourceError } from "./adapter-contract.js";
import * as xModule from "./x.js";
import * as youtubeModule from "./youtube.js";

/** @import { AcquireOutcome, SourceAdapter } from './adapter-contract.js' */

/**
 * Host → statically-imported adapter module. Keys must mirror each adapter's
 * declared `hosts` (verified below at module init).
 *
 * @type {Readonly<Record<string, typeof youtubeModule | typeof xModule>>}
 */
export const SOURCE_MODULES = Object.freeze({
  "youtube.com": youtubeModule,
  "youtu.be": youtubeModule,
  "x.com": xModule,
  "twitter.com": xModule,
});

// Init-time consistency check (pure, no I/O): every registry key is declared
// by its adapter, and every declared host is registered. Safe at module init
// because nothing this registry imports (directly or transitively) imports it
// back — shared acquisition machinery must never import this module, or the
// cycle would make `module.adapter` dereference a still-initializing module.
// Cross-adapter host collisions are covered by the conformance suite.
for (const [host, module] of Object.entries(SOURCE_MODULES)) {
  if (!module.adapter.hosts.includes(host)) {
    throw new Error(
      `Registry key "${host}" is not declared in adapter "${module.adapter.id}" hosts [${module.adapter.hosts.join(", ")}]`,
    );
  }
}
for (const module of new Set(Object.values(SOURCE_MODULES))) {
  for (const host of module.adapter.hosts) {
    if (SOURCE_MODULES[host] !== module) {
      throw new Error(
        `Adapter "${module.adapter.id}" declares host "${host}" but the registry does not map it`,
      );
    }
  }
}

/**
 * @returns {readonly string[]} registered hosts, registration order
 */
export function supportedHosts() {
  return Object.keys(SOURCE_MODULES);
}

/**
 * @returns {readonly SourceAdapter[]} distinct registered adapters
 */
export function sourceAdapters() {
  return [...new Set(Object.values(SOURCE_MODULES))].map((module) => module.adapter);
}

/**
 * @param {string} hostname
 * @returns {string}
 */
function normalizeHostname(hostname) {
  return hostname.toLowerCase().replace(/\.$/, "");
}

/**
 * Resolve the adapter owning a URL's host. Fails closed: an unparseable URL or
 * a host no adapter owns throws {@link UnsupportedSourceError} listing the
 * supported sources.
 *
 * @param {string} url
 * @returns {SourceAdapter}
 */
export function resolveSourceAdapter(url) {
  /** @type {URL} */
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    throw new UnsupportedSourceError(url, supportedHosts());
  }

  const hostname = normalizeHostname(parsed.hostname);
  for (const [host, module] of Object.entries(SOURCE_MODULES)) {
    if (hostname === host || hostname.endsWith(`.${host}`)) {
      return module.adapter;
    }
  }
  throw new UnsupportedSourceError(url, supportedHosts());
}

/**
 * Source-agnostic acquisition entry: resolve the owning adapter, require a
 * positive URL claim, and acquire through the adapter with the claim's
 * canonical URL. Fails closed with {@link UnsupportedSourceError} when no
 * adapter owns the host OR the owning adapter declines the URL (null claim) —
 * `acquire` is never called with an unclaimed URL.
 *
 * @param {string} url
 * @param {{workDir: string, mode: 'full'|'transcript'}} options
 * @param {object} [deps] - adapter-specific injectable I/O (tests only)
 * @returns {Promise<AcquireOutcome>}
 */
export async function acquireMedia(url, { workDir, mode }, deps = {}) {
  const adapter = resolveSourceAdapter(url);
  const claim = adapter.matchUrl(url);
  if (!claim) {
    throw new UnsupportedSourceError(url, supportedHosts());
  }
  return adapter.acquire(claim.canonicalUrl, { workDir, mode, deps });
}
