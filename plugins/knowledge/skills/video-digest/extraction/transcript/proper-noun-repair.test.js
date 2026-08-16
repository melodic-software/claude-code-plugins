import { describe, expect, it } from "vitest";

import {
  buildRepairLexicon,
  osaDistance,
  repairCues,
  repairProperNouns,
} from "./proper-noun-repair.js";

describe("buildRepairLexicon", () => {
  it("extracts proper-noun-shaped terms from the post text", () => {
    const lexicon = buildRepairLexicon(
      "Claude Code now ships MySkills — run npx via the CLI, model large-v3, by @anthropic #DevTools",
    );
    expect(lexicon).toContain("Claude Code");
    expect(lexicon).toContain("MySkills");
    expect(lexicon).toContain("CLI");
    expect(lexicon).toContain("large-v3");
    expect(lexicon).toContain("anthropic");
    expect(lexicon).toContain("DevTools");
  });

  it("the author's spaced phrase wins a key collision with its hashtag compaction", () => {
    const lexicon = buildRepairLexicon("Claude Code is out #ClaudeCode");
    expect(lexicon).toContain("Claude Code");
    expect(lexicon).not.toContain("ClaudeCode");
  });

  it("skips stopwords and plain prose", () => {
    const lexicon = buildRepairLexicon("The quick brown fox jumps over the lazy dog");
    expect(lexicon).not.toContain("The");
    expect(lexicon).not.toContain("quick");
  });

  it("harvests vocabulary from link hosts and path segments", () => {
    const lexicon = buildRepairLexicon("", [
      { url: "https://github.com/anthropics/claude-code", source: "description" },
    ]);
    expect(lexicon).toContain("github");
    expect(lexicon).toContain("anthropics");
    expect(lexicon).toContain("claude-code");
  });

  it("prefers the author's casing over a link slug on a key collision", () => {
    const lexicon = buildRepairLexicon("GitHub is where it lives", [
      { url: "https://github.com/x", source: "description" },
    ]);
    expect(lexicon).toContain("GitHub");
    expect(lexicon).not.toContain("github");
  });
});

describe("osaDistance", () => {
  it("counts adjacent transposition as one edit (the mishearing shape)", () => {
    expect(osaDistance("clawed", "claude")).toBe(2);
    expect(osaDistance("abc", "abc")).toBe(0);
    expect(osaDistance("ab", "ba")).toBe(1);
  });
});

describe("repairProperNouns", () => {
  it("repairs the observed ASR corruption 'Clawed code' → 'Claude Code'", () => {
    const result = repairProperNouns(
      "so I opened Clawed code and typed the prompt",
      ["Claude Code"],
    );
    expect(result.text).toBe("so I opened Claude Code and typed the prompt");
    expect(result.replacementCount).toBe(1);
  });

  it("restores the author's casing on an exact (case-insensitive) match", () => {
    const result = repairProperNouns("install myskills from the repo", ["MySkills"]);
    expect(result.text).toBe("install MySkills from the repo");
  });

  it("preserves punctuation around the repaired span", () => {
    const result = repairProperNouns('he said "clawed code!"', ["Claude Code"]);
    expect(result.text).toBe('he said "Claude Code!"');
  });

  it("leaves already-correct text untouched", () => {
    const result = repairProperNouns("Claude Code is here", ["Claude Code"]);
    expect(result.text).toBe("Claude Code is here");
    expect(result.replacementCount).toBe(0);
  });

  it("does not repair ordinary words within fuzzy reach of nothing", () => {
    const result = repairProperNouns("the cloud is grey today", ["Claude"]);
    expect(result.text).toBe("the cloud is grey today");
    expect(result.replacementCount).toBe(0);
  });

  it("keeps the ASR text when two lexicon terms are equally close (ambiguity)", () => {
    const result = repairProperNouns("we tried clate here", ["clatex", "clatey"]);
    expect(result.text).toBe("we tried clate here");
  });

  it("never fuzzy-matches short terms", () => {
    const result = repairProperNouns("run nppx now", ["npx"]);
    expect(result.text).toBe("run nppx now");
  });
});

describe("repairCues", () => {
  it("repairs cue text and leaves timestamps untouched", () => {
    const { cues, replacementCount } = repairCues(
      [
        { startSec: 0, endSec: 2, text: "opening clawed code" },
        { startSec: 2, endSec: 4, text: "nothing to fix" },
      ],
      ["Claude Code"],
    );
    expect(cues[0]).toEqual({ startSec: 0, endSec: 2, text: "opening Claude Code" });
    expect(cues[1].text).toBe("nothing to fix");
    expect(replacementCount).toBe(1);
  });

  it("is a no-op for an empty lexicon", () => {
    const input = [{ startSec: 0, endSec: 1, text: "hello" }];
    const { cues, replacementCount } = repairCues(input, []);
    expect(cues).toEqual(input);
    expect(replacementCount).toBe(0);
  });
});
