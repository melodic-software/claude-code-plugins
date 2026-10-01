/**
 * Shared source-adapter conformance suite: asserted once against the contract
 * here, star-imported into a thin per-adapter test file each adapter owns
 * (the SQLAlchemy dialect-suite shape). Per-adapter files supply only
 * source-specific fixtures and assertions; every contract-generic invariant
 * lives here so a new adapter inherits the full surface by composing
 * {@link describeSourceAdapterContract}.
 *
 * Declared-attribute shapes (hosts, extractorArgs, allowedExtractors,
 * errorPatterns tables, captionClass, transcriptStrategy, capabilities) are
 * asserted through `validateAdapter` — the single runtime authority — rather
 * than restated assertion-by-assertion. Behavioral invariants the validator
 * cannot see (claim/queue agreement, canonicalization idempotence, path-safe
 * slice keys, harvest well-formedness) are asserted directly. `acquire` is
 * I/O-bearing and stays per-adapter (fixture-driven, offline); its declared
 * arity is enforced by `validateAdapter`.
 */

import { describe, expect, it } from "vitest";

import { validateAdapter } from "./adapter-contract.js";

/** @import { SourceAdapter, SourceMetadata } from './adapter-contract.js' */

/** Mirror of the shared slug derivation's path-safety invariant for slice keys. */
const SAFE_SLICE_KEY_PATTERN = /^[A-Za-z0-9_-]+$/;

/**
 * @typedef {Object} AdapterSuiteFixtures
 * @property {ReadonlyArray<{url: string, sliceKey: string}>} claimedUrls -
 *   URLs the adapter must claim, each with its expected slice key
 * @property {readonly string[]} unclaimedUrls - URLs the adapter must decline
 *   (host-owned non-content URLs and foreign hosts alike)
 * @property {SourceMetadata} harvestMetadata - source-faithful metadata sample
 *   the harvest contract assertions run against
 */

/**
 * Cross-adapter host-collision check, matching the registry's owned-host rule
 * (exact match or `.<host>` suffix): two DISTINCT adapters claiming the same
 * or overlapping hosts is a dispatch ambiguity. Returns violation messages
 * (empty when collision-free). Pure — usable against the live registry and
 * against hypothetical registrations (mutation probes, adapter-three review).
 *
 * @param {ReadonlyArray<Pick<SourceAdapter, 'id'|'hosts'>>} adapters
 * @returns {string[]}
 */
export function findHostCollisions(adapters) {
  /** @type {string[]} */
  const collisions = [];
  for (let i = 0; i < adapters.length; i += 1) {
    for (let j = i + 1; j < adapters.length; j += 1) {
      if (adapters[i] === adapters[j]) continue;
      for (const left of adapters[i].hosts) {
        for (const right of adapters[j].hosts) {
          if (left === right || left.endsWith(`.${right}`) || right.endsWith(`.${left}`)) {
            collisions.push(
              `adapter "${adapters[i].id}" host "${left}" overlaps adapter "${adapters[j].id}" host "${right}"`,
            );
          }
        }
      }
    }
  }
  return collisions;
}

/**
 * @param {SourceAdapter} adapter
 * @param {AdapterSuiteFixtures} fixtures
 */
export function describeSourceAdapterContract(adapter, fixtures) {
  describe(`${adapter.id} adapter: shared contract assertions`, () => {
    it("validates against the contract (methods, arity, declared-attribute shapes) and is frozen", () => {
      expect(validateAdapter(adapter)).toEqual([]);
      expect(Object.isFrozen(adapter)).toBe(true);
      expect(Object.isFrozen(adapter.hosts)).toBe(true);
      expect(Object.isFrozen(adapter.errorPatterns)).toBe(true);
      expect(Object.isFrozen(adapter.capabilities)).toBe(true);
    });

    it("claims every fixture URL with a path-safe, URL-authoritative slice key", () => {
      for (const { url, sliceKey } of fixtures.claimedUrls) {
        const claim = adapter.matchUrl(url);
        expect(claim, url).not.toBeNull();
        expect(claim?.sliceKey, url).toBe(sliceKey);
        expect(typeof claim?.canonicalUrl, url).toBe("string");
        expect(SAFE_SLICE_KEY_PATTERN.test(String(claim?.sliceKey)), url).toBe(true);
        // Pre-acquisition (queue lane) and diverging-metadata calls must both
        // resolve to the URL's key.
        expect(adapter.extractSliceKey(url, null), url).toBe(sliceKey);
        expect(
          adapter.extractSliceKey(url, { id: "divergent0", title: "", description: "" }),
          url,
        ).toBe(sliceKey);
      }
    });

    it("canonicalizes idempotently: matchUrl(canonicalUrl) is a stable fixed point", () => {
      for (const { url, sliceKey } of fixtures.claimedUrls) {
        const claim = adapter.matchUrl(url);
        const canonicalUrl = String(claim?.canonicalUrl);
        const recanonical = adapter.matchUrl(canonicalUrl);
        expect(recanonical, canonicalUrl).not.toBeNull();
        expect(recanonical?.sliceKey, canonicalUrl).toBe(sliceKey);
        expect(recanonical?.canonicalUrl, canonicalUrl).toBe(canonicalUrl);
        // The queue gate and the slice key agree on the canonical form too, so
        // every entry path resolves the same slice by construction.
        expect(adapter.acceptForEnqueue(canonicalUrl), canonicalUrl).toEqual({
          ok: true,
          key: sliceKey,
        });
        expect(adapter.extractSliceKey(canonicalUrl, null), canonicalUrl).toBe(sliceKey);
      }
    });

    it("accepts every claimed URL for enqueue with the same key", () => {
      for (const { url, sliceKey } of fixtures.claimedUrls) {
        expect(adapter.acceptForEnqueue(url), url).toEqual({ ok: true, key: sliceKey });
      }
    });

    it("declines every unclaimed URL in both the claim and the queue gate", () => {
      for (const url of fixtures.unclaimedUrls) {
        expect(adapter.matchUrl(url), url).toBeNull();
        const decision = adapter.acceptForEnqueue(url);
        expect(decision.ok, url).toBe(false);
        expect(typeof decision.note, url).toBe("string");
        expect(typeof decision.reason, url).toBe("string");
      }
    });

    it("exercises every declared host through at least one claimed fixture URL", () => {
      for (const host of adapter.hosts) {
        const covered = fixtures.claimedUrls.some(({ url }) => {
          const hostname = new URL(url).hostname.toLowerCase();
          return hostname === host || hostname.endsWith(`.${host}`);
        });
        expect(covered, `declared host "${host}" has no claimed fixture URL`).toBe(true);
      }
    });

    it("harvests well-formed, deduplicated http(s) links from source-faithful metadata", () => {
      const links = adapter.harvestLinks(fixtures.harvestMetadata);
      expect(Array.isArray(links)).toBe(true);
      const seen = new Set();
      for (const link of links) {
        expect(typeof link.url, JSON.stringify(link)).toBe("string");
        const parsed = new URL(link.url);
        expect(["http:", "https:"], link.url).toContain(parsed.protocol);
        expect(typeof link.source, link.url).toBe("string");
        expect(seen.has(link.url.toLowerCase()), `duplicate harvested url: ${link.url}`).toBe(
          false,
        );
        seen.add(link.url.toLowerCase());
      }
    });
  });
}
