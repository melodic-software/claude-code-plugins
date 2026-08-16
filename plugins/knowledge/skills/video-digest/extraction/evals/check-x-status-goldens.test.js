/**
 * Offline CI eval gate for the X source adapter's golden fixture
 * (`evals/fixtures/x-status-goldens.json`, skill-level): drives the REAL
 * acquisition path against the fixture-defined yt-dlp pass outputs on a real
 * temp working directory and asserts the goldens — 0..N result shape, the
 * slice-key pair, and the source:* provenance fields (counts, snowflake
 * aliasing, blocked delegations) exactly as they persist into watch state
 * through `sourceMetadataSubset`. Pins the X golden behavior so later
 * refactors cannot silently regress it.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { sourceMetadataSubset } from "../adapters/adapter-contract.js";
import { resolveSourceAdapter } from "../adapters/registry.js";
import { acquireXMedia, adapter } from "../adapters/x.js";
import { harvestMetadataLinks } from "../harvesting/harvest-links.js";

const GOLDENS_PATH = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "evals",
  "fixtures",
  "x-status-goldens.json",
);

/** @type {any} */
let goldens;
/** @type {string} */
let workDir;

/**
 * Spawn double honoring the fixture's pass table: call N applies pass N's
 * files to the REAL working directory and returns its exit disposition, so
 * everything else (listing, info-JSON parsing, artifact matching) runs the
 * production fs code paths.
 *
 * @param {any[]} passes
 */
function fixtureSpawn(passes) {
  const spawn = vi.fn(async () => {
    const pass = passes[spawn.mock.calls.length - 1] ?? {};
    for (const [name, content] of Object.entries(pass.files ?? {})) {
      const text = typeof content === "string" ? content : JSON.stringify(content);
      await fs.writeFile(path.join(workDir, name), text, "utf8");
    }
    const success = pass.success !== false;
    return {
      success,
      code: success ? 0 : 1,
      signal: null,
      stdout: "",
      stderr: pass.stderr ?? "",
      timedOut: false,
    };
  });
  return spawn;
}

describe("x status golden eval fixture", () => {
  beforeEach(async () => {
    goldens = JSON.parse(await fs.readFile(GOLDENS_PATH, "utf8"));
    workDir = await fs.mkdtemp(path.join(os.tmpdir(), "x-goldens-"));
  });

  afterEach(async () => {
    await fs.rm(workDir, { recursive: true, force: true });
  });

  it("pins the slice-key pair: canonical identity is the URL's status id on the canonical URL", () => {
    expect(resolveSourceAdapter(goldens.statusUrl).id).toBe("x");
    const claim = adapter.matchUrl(goldens.statusUrl);
    expect(claim).toEqual({ sliceKey: goldens.sliceKey, canonicalUrl: goldens.canonicalUrl });
    expect(adapter.extractSliceKey(goldens.statusUrl, null)).toBe(goldens.sliceKey);
  });

  it("reproduces every golden case: result shape, slice key, and persisted source:* provenance", async () => {
    for (const goldenCase of goldens.cases) {
      const caseDir = await fs.mkdtemp(path.join(workDir, "case-"));
      const outerWorkDir = workDir;
      workDir = caseDir;
      try {
        const spawn = fixtureSpawn(goldenCase.passes);
        const result = await acquireXMedia(goldens.canonicalUrl, {
          workDir: caseDir,
          mode: "full",
          deps: {
            spawn,
            sleep: async () => {},
            withThrottle: (/** @type {() => Promise<unknown>} */ fn) => fn(),
          },
        });

        expect(result.success, goldenCase.name).toBe(true);
        const envelope = result.data;
        const expected = goldenCase.expected;

        // 0..N result shape: arity is a property of the result.
        expect(envelope.entries.length, goldenCase.name).toBe(expected.entryCount);
        for (const entry of envelope.entries) {
          expect(typeof entry.mediaPath, goldenCase.name).toBe("string");
          expect(Array.isArray(entry.captionPaths), goldenCase.name).toBe(true);
          expect(entry.metadataPath, goldenCase.name).toContain(".info.json");
        }

        // Slice-key pair: metadata.id is the media discriminator; the slice
        // key stays the URL's status id regardless of it.
        expect(envelope.metadata.id, goldenCase.name).toBe(expected.metadataId);
        expect(adapter.extractSliceKey(goldens.canonicalUrl, envelope.metadata), goldenCase.name).toBe(
          goldens.sliceKey,
        );

        // Persisted provenance: exactly what watch state stores via
        // sourceMetadataSubset must carry the golden source:* fields.
        const persisted = sourceMetadataSubset(envelope.metadata);
        expect(persisted, goldenCase.name).toMatchObject(expected.persistedSourceMetadata);
        if (expected.aliasingRecorded) {
          expect(persisted["source:snowflakeAliasing"], goldenCase.name).toEqual(
            expected.persistedSourceMetadata["source:snowflakeAliasing"],
          );
        } else {
          expect(persisted["source:snowflakeAliasing"], goldenCase.name).toBeUndefined();
        }

        const harvested = harvestMetadataLinks(envelope.metadata, adapter).map((link) => link.url);
        for (const url of expected.harvestedLinks) {
          expect(harvested, goldenCase.name).toContain(url);
        }
      } finally {
        workDir = outerWorkDir;
      }
    }
  });
});
