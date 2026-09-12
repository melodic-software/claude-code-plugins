import { describe, expect, it } from "vitest";

import { TAG_COLORS } from "./tags.js";

// Authoritative set from the Miro create-tag API.
// Ref: https://developers.miro.com/reference/create-tag
const MIRO_VALID_TAG_COLORS = [
  "red",
  "light_green",
  "cyan",
  "yellow",
  "magenta",
  "green",
  "blue",
  "gray",
  "violet",
  "dark_green",
  "dark_blue",
  "black",
];

describe("TAG_COLORS", () => {
  it("should exactly match the Miro create-tag fillColor enum", () => {
    expect([...TAG_COLORS].sort()).toEqual([...MIRO_VALID_TAG_COLORS].sort());
  });

  it("should not include orange (rejected by the Miro API)", () => {
    expect(TAG_COLORS).not.toContain("orange");
  });

  it("should include black", () => {
    expect(TAG_COLORS).toContain("black");
  });
});
