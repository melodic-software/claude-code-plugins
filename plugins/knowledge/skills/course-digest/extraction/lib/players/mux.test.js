import { describe, expect, it } from "vitest";

import { getHlsUrl, hasMuxPlayer } from "./mux.js";

describe("mux player module", () => {
  describe("getHlsUrl", () => {
    it("should return src from mux-player element", async () => {
      const mockPage = {
        evaluate: async () => "https://stream.mux.com/abc123.m3u8",
      };
      const url = await getHlsUrl(mockPage, "mux-player");
      expect(url).toBe("https://stream.mux.com/abc123.m3u8");
    });

    it("should throw when player not found or has no src", async () => {
      const mockPage = {
        evaluate: async () => null,
      };
      await expect(getHlsUrl(mockPage, "mux-player")).rejects.toThrow(
        "Video player not found (selector: mux-player)",
      );
    });
  });

  describe("hasMuxPlayer", () => {
    it("should return true when player exists", async () => {
      const mockPage = {
        evaluate: async () => true,
      };
      expect(await hasMuxPlayer(mockPage, "mux-player")).toBe(true);
    });

    it("should return false when player missing", async () => {
      const mockPage = {
        evaluate: async () => false,
      };
      expect(await hasMuxPlayer(mockPage, "mux-player")).toBe(false);
    });

    it("should return false on evaluate error", async () => {
      const mockPage = {
        evaluate: async () => {
          throw new Error("crashed");
        },
      };
      expect(await hasMuxPlayer(mockPage, "mux-player")).toBe(false);
    });
  });
});
