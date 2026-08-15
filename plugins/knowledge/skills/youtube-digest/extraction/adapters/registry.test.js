import { describe, expect, it } from "vitest";

import { UnsupportedSourceError } from "./adapter-contract.js";
import {
  resolveSourceAdapter,
  SOURCE_MODULES,
  sourceAdapters,
  supportedHosts,
} from "./registry.js";

describe("registry static-import conformance", () => {
  it("maps every host to a statically-imported module object (no thenables, no specifier strings)", () => {
    const values = Object.values(SOURCE_MODULES);
    expect(values.length).toBeGreaterThan(0);
    for (const value of values) {
      expect(typeof value).toBe("object");
      expect(typeof value).not.toBe("string");
      expect(typeof (/** @type {{then?: unknown}} */ (value).then)).not.toBe("function");
      expect(Object.prototype.toString.call(value)).toBe("[object Module]");
      expect(typeof value.adapter).toBe("object");
      expect(typeof value.adapter.matchUrl).toBe("function");
    }
  });

  it("registers exactly the hosts each adapter declares", () => {
    for (const adapter of sourceAdapters()) {
      for (const host of adapter.hosts) {
        expect(Object.keys(SOURCE_MODULES)).toContain(host);
      }
    }
    expect(supportedHosts().sort()).toEqual(["youtu.be", "youtube.com"]);
  });
});

describe("resolveSourceAdapter", () => {
  it("fails closed on an unknown host, listing the supported sources", () => {
    expect(() => resolveSourceAdapter("https://vimeo.com/1")).toThrow(UnsupportedSourceError);
    try {
      resolveSourceAdapter("https://vimeo.com/1");
    } catch (error) {
      expect(error.message).toContain("https://vimeo.com/1");
      expect(error.message).toContain("youtube.com");
      expect(error.message).toContain("youtu.be");
      expect(error.supportedHosts).toEqual(supportedHosts());
    }
  });

  it("evaluates URL patterns only after owned-host selection", () => {
    // A YouTube-shaped ?v= query on an unowned host must never reach the
    // YouTube adapter's URL grammar.
    expect(() => resolveSourceAdapter("https://vimeo.com/watch?v=7zZy1QTvokM")).toThrow(
      UnsupportedSourceError,
    );
  });

  it("fails closed on an unparseable URL", () => {
    expect(() => resolveSourceAdapter("not a url")).toThrow(UnsupportedSourceError);
  });

  it("resolves registered hosts and their subdomains", () => {
    const urls = [
      "https://youtube.com/watch?v=7zZy1QTvokM",
      "https://www.youtube.com/watch?v=7zZy1QTvokM",
      "https://m.youtube.com/watch?v=7zZy1QTvokM",
      "https://music.youtube.com/watch?v=7zZy1QTvokM",
      "https://YOUTUBE.COM/watch?v=7zZy1QTvokM",
      "https://youtube.com./watch?v=7zZy1QTvokM",
      "https://youtu.be/7zZy1QTvokM",
    ];
    for (const url of urls) {
      expect(resolveSourceAdapter(url).id).toBe("youtube");
    }
  });

  it("rejects lookalike and suffix-spoofed hosts", () => {
    for (const url of [
      "https://notyoutube.com/watch?v=7zZy1QTvokM",
      "https://youtube.com.evil.example/watch?v=7zZy1QTvokM",
      "https://evilyoutu.be/7zZy1QTvokM",
    ]) {
      expect(() => resolveSourceAdapter(url)).toThrow(UnsupportedSourceError);
    }
  });
});
