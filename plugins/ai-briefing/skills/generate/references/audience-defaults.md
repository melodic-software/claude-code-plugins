# Audience defaults for /ai-briefing:generate

The engine's **default** audience framing, pragmatic-use ranking lens, and apolitical
filter. Loaded by S4 categorize (ranking) and Step 4.5 enrichment (impact tag). These
are documented, **overridable** defaults: a consumer profile can refine or replace them
(a profile's `audience.md` in `.claude/ai-briefing/[<profile>/]` overlays this file).

## Pragmatic-use filter (ranking lens)

The default audience is a **software engineering team** thinking about **pragmatic use of
AI in everyday development, engineering, and life** — NOT pure research breakthroughs, NOT
speculative AGI debates. When ranking HIGH/MED/LOW, weight items by:

- **Will an engineer use this next week?** (Claude Code release, Cursor SDK, Copilot feature) → HIGH bias
- **Does it change cost/access economics?** (model pricing, compute deals, chip launches that drop $/token) → HIGH bias
- **Does it shift the legal/regulatory landscape with industry-wide impact?** (governance trials, copyright suits, AI-Act enforcement) → HIGH bias
- **Is it real-world AI deployment at scale?** (robotaxi launches, humanoid production, AI-in-cars) → HIGH for production, MED for prototypes
- **Is it pure research speculation or vibe?** (alignment thought-pieces, viral tweets) → LOW bias

This filter is the difference between "noise from the AI hype cycle" and "things that affect how a team ships".

## Apolitical filter — drop partisan content

**Rule:** stay away from purely political / partisan material. Political-themed AI memes
(politician deepfakes, campaign-AI controversies, partisan policy debates) get DROPPED —
they alienate part of the audience and don't serve "pragmatic use of AI in development".

**EXCEPTION — true industry-wide controversy** that materially affects AI access, cost, or
regulation IS in scope, even if a politician is named. Worked examples:

- KEEP **supply-chain / procurement disputes** affecting which vendors an org can buy AI from — cross-provider, regulatory, affects AI access at scale.
- KEEP **landmark AI-governance trials** (for-profit/nonprofit governance, major equity stakes) — industry-defining precedent.
- KEEP **State AGs suing AI companies** — regulatory pulse on consumer AI.
- DROP a partisan campaign video that merely uses AI for political flair — low industry signal.
- DROP **Politician X tweets about AI** — campaign noise.
- DROP **partisan AI policy debate threads**.

Heuristic: if removing the political angle leaves a clear AI-industry impact story → keep. If the political angle IS the story → drop.

## Profile-provided impact lens (optional)

When the active profile supplies a tech-stack lens, Step 4.5 enrichment annotates each HIGH
item with `impact: high|medium|low|none + 1-line reason`, cross-checked against that stack.
With **no** profile stack lens (the default, unprofiled run), the impact tag is omitted.

A profile declares its stack as a short list an engineer recognizes — for example a web-app
team might list its language/runtime, database, auth, hosting, and AI-integration surface —
and the enrichment pass reasons about each HIGH item's relevance to those. Examples of the
annotation shape:

- "Agent-loop feature → impact: medium — could automate our webhook integration testing"
- "New open-weight model → impact: low — no current use case in our stack"

Schema field: `impact` per item in `seen-items.json` (optional). Rendered as an italic tag
below the body in the briefing markdown.
