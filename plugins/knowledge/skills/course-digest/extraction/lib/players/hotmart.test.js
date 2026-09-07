import { beforeEach, describe, expect, it } from "vitest";

import {
  clearCapturedData,
  DEFAULT_VIDEO_PLAYER_SELECTOR,
  getCapturedData,
  getHlsUrl,
  hasHotmartPlayer,
  installInterceptors,
  isInterceptorsInstalled,
  preparePage,
  resetState,
} from "./hotmart.js";

/**
 * Minimal Page stand-in that records `page.on` registrations and can replay
 * them, so a test can watch what a given Page actually received.
 */
function makeMockPage(url = "https://example.com") {
  const listeners = [];
  return {
    listeners,
    url: () => url,
    on: (event, handler) => {
      listeners.push({ event, handler });
    },
    async emit(event, payload) {
      for (const l of listeners.filter((x) => x.event === event)) {
        await l.handler(payload);
      }
    },
  };
}

describe("hotmart player module", () => {
  beforeEach(() => {
    resetState();
  });

  describe("clearCapturedData", () => {
    it("should remove entry for a specific URL", () => {
      const data = getCapturedData();
      data.set("https://example.com/lesson/1", {
        hlsMasterUrl: "https://cdn.hotmart.com/master.m3u8",
        subtitleManifestBody: null,
      });
      expect(data.has("https://example.com/lesson/1")).toBe(true);

      clearCapturedData("https://example.com/lesson/1");
      expect(data.has("https://example.com/lesson/1")).toBe(false);
    });

    it("should not throw when URL does not exist", () => {
      expect(() => clearCapturedData("https://nonexistent.com")).not.toThrow();
    });
  });

  describe("isInterceptorsInstalled", () => {
    it("should return false for a page that has not been set up", () => {
      expect(isInterceptorsInstalled(makeMockPage())).toBe(false);
    });

    it("should throw when no page is supplied", () => {
      expect(() => isInterceptorsInstalled()).toThrow(TypeError);
    });
  });

  describe("installInterceptors", () => {
    it("should mark the page as installed after first call", () => {
      const mockPage = makeMockPage();

      installInterceptors(mockPage, "eng");
      expect(isInterceptorsInstalled(mockPage)).toBe(true);
    });

    it("should not install twice on the same page (idempotent)", () => {
      const mockPage = makeMockPage();

      installInterceptors(mockPage, "eng");
      const firstCount = mockPage.listeners.length;
      installInterceptors(mockPage, "eng");
      expect(mockPage.listeners.length).toBe(firstCount);
    });

    it("should install on a second page in the same process", () => {
      const firstPage = makeMockPage("https://example.com/lesson/1");
      const secondPage = makeMockPage("https://example.com/lesson/2");

      installInterceptors(firstPage, "eng");
      installInterceptors(secondPage, "eng");

      expect(isInterceptorsInstalled(secondPage)).toBe(true);
      expect(secondPage.listeners.map((l) => l.event).sort()).toEqual(["request", "response"]);
      expect(secondPage.listeners.length).toBe(firstPage.listeners.length);
    });

    it("should capture the HLS master URL for a second page", async () => {
      const firstPage = makeMockPage("https://example.com/lesson/1");
      const secondPage = makeMockPage("https://example.com/lesson/2");
      const masterUrl = "https://cdn.hotmart.com/master-pkg-t-xyz.m3u8?token=abc";

      installInterceptors(firstPage, "eng");
      installInterceptors(secondPage, "eng");

      await secondPage.emit("request", { url: () => masterUrl });

      expect(getHlsUrl(secondPage)).toBe(masterUrl);
    });
  });

  describe("resetState", () => {
    it("should clear captured data and forget installed pages", () => {
      const data = getCapturedData();
      data.set("url1", { hlsMasterUrl: "x", subtitleManifestBody: null });

      const mockPage = makeMockPage("");
      installInterceptors(mockPage, "eng");

      expect(data.size).toBe(1);
      expect(isInterceptorsInstalled(mockPage)).toBe(true);

      resetState();

      expect(data.size).toBe(0);
      expect(isInterceptorsInstalled(mockPage)).toBe(false);
    });
  });

  describe("getHlsUrl", () => {
    it("should return the captured HLS master URL", () => {
      const data = getCapturedData();
      const testUrl = "https://example.com/lesson/1";
      const cdnBase = "https://cdn.hotmart.com/";
      const masterPath = "master-pkg-t-xyz.m3u8";
      const tokenQuery = "?token=abc";
      const hlsMasterUrl = `${cdnBase}${masterPath}${tokenQuery}`;
      data.set(testUrl, {
        hlsMasterUrl,
        subtitleManifestBody: null,
      });

      const mockPage = { url: () => testUrl };
      expect(getHlsUrl(mockPage)).toBe(hlsMasterUrl);
    });

    it("should throw when no HLS URL captured", () => {
      const mockPage = { url: () => "https://example.com/no-data" };
      expect(() => getHlsUrl(mockPage)).toThrow("No HLS master URL captured");
    });
  });

  describe("hasHotmartPlayer", () => {
    /**
     * Runs the evaluate callback the way Playwright does — serialized, with the
     * argument handed across the boundary — against a fake `document` whose
     * only matching selector is `presentSelector`.
     */
    function makeDomPage(presentSelector) {
      return {
        evaluate: async (fn, arg) => {
          // Rebuild the callback from source so it cannot reach any binding in
          // this module — the same isolation page.evaluate imposes.
          const detached = new Function("document", "arg", `return (${fn.toString()})(arg);`);
          const document = {
            querySelector: (s) => (s === presentSelector ? { tag: "div" } : null),
          };
          return detached(document, structuredClone(arg));
        },
      };
    }

    it("should return true when the default selector matches", async () => {
      expect(await hasHotmartPlayer(makeDomPage(DEFAULT_VIDEO_PLAYER_SELECTOR))).toBe(true);
    });

    it("should return false when the default selector does not match", async () => {
      expect(await hasHotmartPlayer(makeDomPage(".something-else"))).toBe(false);
    });

    it("should query the configured selector inside the browser context", async () => {
      const customSelector = ".custom-player-shell";

      expect(await hasHotmartPlayer(makeDomPage(customSelector), customSelector)).toBe(true);
    });

    it("should not fall back to the hardcoded literal when a selector is configured", async () => {
      expect(
        await hasHotmartPlayer(makeDomPage(DEFAULT_VIDEO_PLAYER_SELECTOR), ".custom-player-shell"),
      ).toBe(false);
    });

    it("should pass the selector as an evaluate argument, not a closure", async () => {
      let receivedArg;
      const mockPage = {
        evaluate: async (fn, arg) => {
          receivedArg = arg;
          expect(fn.toString()).not.toContain("custom-player-shell");
          return true;
        },
      };

      await hasHotmartPlayer(mockPage, ".custom-player-shell");

      expect(receivedArg).toBe(".custom-player-shell");
    });

    it("should return false on evaluate error", async () => {
      const mockPage = {
        evaluate: async () => {
          throw new Error("page crashed");
        },
      };
      expect(await hasHotmartPlayer(mockPage)).toBe(false);
    });
  });

  describe("preparePage selector threading", () => {
    function makeDetectionPage(presentSelector) {
      return {
        url: () => "https://example.com/lesson/1",
        evaluate: async (fn, arg) => {
          const detached = new Function("document", "arg", `return (${fn.toString()})(arg);`);
          const document = {
            querySelector: (s) => (s === presentSelector ? { tag: "div" } : null),
          };
          return detached(document, structuredClone(arg));
        },
        frames: () => [],
      };
    }

    it("should detect no video when the configured selector is absent", async () => {
      const page = makeDetectionPage(DEFAULT_VIDEO_PLAYER_SELECTOR);

      const result = await preparePage(page, "eng", 15000, ".skin-v2-player");

      expect(result).toEqual({ hasVideo: false, hotmartFrame: null });
    });

    it("should fail past detection when the configured selector matches", async () => {
      const page = makeDetectionPage(".skin-v2-player");

      // Detection passes, so preparePage moves on to iframe lookup and throws
      // because this stand-in exposes no Hotmart frame. That throw is the proof
      // the custom selector matched.
      await expect(preparePage(page, "eng", 15000, ".skin-v2-player")).rejects.toThrow(
        "iframe not accessible",
      );
    });
  });
});
