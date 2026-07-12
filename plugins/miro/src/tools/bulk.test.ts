import { describe, expect, it } from "vitest";

import { elementAt } from "../test-support/assertions.js";
import { stickyNoteSchema } from "./bulk.js";

describe("stickyNoteSchema", () => {
  it("should accept square shape explicitly", () => {
    const result = stickyNoteSchema.parse({
      content: "Test",
      x: 0,
      y: 0,
      shape: "square",
    });
    expect(result.shape).toBe("square");
  });

  it("should accept rectangle shape", () => {
    const result = stickyNoteSchema.parse({
      content: "External System",
      x: 100,
      y: -600,
      shape: "rectangle",
    });
    expect(result.shape).toBe("rectangle");
  });

  it("should default to square when shape omitted", () => {
    const result = stickyNoteSchema.parse({
      content: "Domain Event",
      x: 0,
      y: 0,
    });
    expect(result.shape).toBe("square");
  });

  it("should reject invalid shape values", () => {
    expect(() =>
      stickyNoteSchema.parse({
        content: "Test",
        x: 0,
        y: 0,
        shape: "circle",
      }),
    ).toThrow();
  });

  it("should default color to light_yellow", () => {
    const result = stickyNoteSchema.parse({
      content: "Test",
      x: 0,
      y: 0,
    });
    expect(result.color).toBe("light_yellow");
  });

  it("should accept valid color names", () => {
    const result = stickyNoteSchema.parse({
      content: "Hot Spot",
      x: 0,
      y: 0,
      color: "red",
    });
    expect(result.color).toBe("red");
  });

  it("should reject invalid color names", () => {
    expect(() =>
      stickyNoteSchema.parse({
        content: "Test",
        x: 0,
        y: 0,
        color: "neon_purple",
      }),
    ).toThrow();
  });

  it("should require content, x, and y", () => {
    expect(() => stickyNoteSchema.parse({})).toThrow();
    expect(() => stickyNoteSchema.parse({ content: "Test" })).toThrow();
    expect(() => stickyNoteSchema.parse({ content: "Test", x: 0 })).toThrow();
  });

  it("should handle EventStorming external system pattern", () => {
    // The exact use case that motivated the shape parameter
    const externalSystem = stickyNoteSchema.parse({
      content: "Sandata EAS (EVV aggregator)",
      color: "light_pink",
      shape: "rectangle",
      x: -200,
      y: -800,
    });
    expect(externalSystem.shape).toBe("rectangle");
    expect(externalSystem.color).toBe("light_pink");
  });

  it("should handle batch of mixed shapes", () => {
    const notes = [
      { color: "orange", content: "Domain Event", shape: "square", x: 0, y: 0 },
      { color: "light_green", content: "Read Model", shape: "rectangle", x: 0, y: -400 },
      { color: "blue", content: "Command", x: 400, y: 0 }, // shape defaults to square
    ];

    const parsed = notes.map((n) => stickyNoteSchema.parse(n));
    expect(elementAt(parsed, 0).shape).toBe("square");
    expect(elementAt(parsed, 1).shape).toBe("rectangle");
    expect(elementAt(parsed, 2).shape).toBe("square");
  });
});
