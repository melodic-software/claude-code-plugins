/**
 * Shared source-adapter test harness: a describe-factory each adapter's test
 * file composes with its own fixtures, so per-adapter tests add only
 * source-specific assertions instead of copy-pasting the contract-generic
 * ones. Deliberately lean — the full conformance suite is a later, separate
 * surface; this is the reusable shape.
 */

import { describe, expect, it } from "vitest";

import { validateAdapter } from "./adapter-contract.js";

/** @import { SourceAdapter } from './adapter-contract.js' */

/** Mirror of the shared slug derivation's path-safety invariant for slice keys. */
const SAFE_SLICE_KEY_PATTERN = /^[A-Za-z0-9_-]+$/;

/**
 * @typedef {Object} AdapterSuiteFixtures
 * @property {ReadonlyArray<{url: string, sliceKey: string}>} claimedUrls -
 *   URLs the adapter must claim, each with its expected slice key
 * @property {readonly string[]} unclaimedUrls - URLs the adapter must decline
 *   (host-owned non-content URLs and foreign hosts alike)
 */

/**
 * @param {SourceAdapter} adapter
 * @param {AdapterSuiteFixtures} fixtures
 */
export function describeSourceAdapterContract(adapter, fixtures) {
  describe(`${adapter.id} adapter: shared contract assertions`, () => {
    it("validates against the contract and is frozen", () => {
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
  });
}
