---
description: "Design anything a person or agent interacts with: CLI output, TUIs, prompt themes, PowerShell formatting, banners, Claude Code mods, web and app UI. Detects the project's own design system and the design tools installed, routes each concern to the best present source with the project first, and fills gaps with its own guidance. Use when: 'design this CLI output', 'how should this TUI look', 'style this error message', 'design a mod band', 'make this UI match our design system', 'which design tool should I use'. Throwaway layout variants: /prototype:explore-directions."
argument-hint: "[what to design]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Design interfaces from the project's system and installed tools; terminal guidance built in
---

# Design a user interface

## Step 1: Detect

Run `node "${CLAUDE_PLUGIN_ROOT}/scripts/detect.mjs"` from the project root. It prints JSON with the
project's design-system signals (`project`) and the routed tools that are installed (`installed`).

## Step 2: Route

Read `${CLAUDE_PLUGIN_ROOT}/reference/routing.json`. Its rows rank the routes for each concern.
When `project` has signals for a concern, the project's own system leads that concern.

## Step 3: Pick the interface type

List `${CLAUDE_PLUGIN_ROOT}/reference/types/` and read the file whose name matches the interface
being designed.
