import { beforeEach, describe, expect, it } from "vitest";

import {
  clearCapturedData,
  getCapturedData,
  getHlsUrl,
  hasHotmartPlayer,
  installInterceptors,
  isInterceptorsInstalled,
  resetState,
} from "./hotmart.js";

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
    it("should return false initially", () => {
      expect(isInterceptorsInstalled()).toBe(false);
    });
  });

  describe("installInterceptors", () => {
    it("should set interceptorsInstalled to true after first call", () => {
      const mockPage = {
        on: () => {},
        url: () => "https://example.com",
      };

      installInterceptors(mockPage, "eng");
      expect(isInterceptorsInstalled()).toBe(true);
    });

    it("should not install twice (idempotent)", () => {
      let callCount = 0;
      const mockPage = {
        on: () => {
          callCount++;
        },
        url: () => "https://example.com",
      };

      installInterceptors(mockPage, "eng");
      const firstCount = callCount;
      installInterceptors(mockPage, "eng");
      expect(callCount).toBe(firstCount);
    });
  });

  describe("resetState", () => {
    it("should clear captured data and reset interceptors flag", () => {
      const data = getCapturedData();
      data.set("url1", { hlsMasterUrl: "x", subtitleManifestBody: null });

      const mockPage = { on: () => {}, url: () => "" };
      installInterceptors(mockPage, "eng");

      expect(data.size).toBe(1);
      expect(isInterceptorsInstalled()).toBe(true);

      resetState();

      expect(data.size).toBe(0);
      expect(isInterceptorsInstalled()).toBe(false);
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
    it("should return true when page has .hotmart_video_player", async () => {
      const mockPage = {
        evaluate: async () => true,
      };
      expect(await hasHotmartPlayer(mockPage)).toBe(true);
    });

    it("should return false when page lacks .hotmart_video_player", async () => {
      const mockPage = {
        evaluate: async () => false,
      };
      expect(await hasHotmartPlayer(mockPage)).toBe(false);
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
});
