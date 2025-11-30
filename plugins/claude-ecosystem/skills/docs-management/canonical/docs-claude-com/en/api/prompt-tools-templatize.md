<!-- Source: https://docs.claude.com/en/api/prompt-tools-templatize -->

# Templatize a prompt

post /v1/experimental/templatize_prompt
Templatize a prompt by indentifying and extracting variables

<Tip>
  The prompt tools APIs are in a closed research preview. [Request to join the closed research preview](https://forms.gle/LajXBafpsf1SuJHp7).
</Tip>

## Before you begin

The prompt tools are a set of APIs to generate and improve prompts. Unlike our other APIs, this is an experimental API: you'll need to request access, and it doesn't have the same level of commitment to long-term support as other APIs.

These APIs are similar to what's available in the [Anthropic Workbench](https://console.anthropic.com/workbench), and are intented for use by other prompt engineering platforms and playgrounds.

## Getting started with the prompt improver

To use the prompt generation API, you'll need to:

1. Have joined the closed research preview for the prompt tools APIs
2. Use the API directly, rather than the SDK
3. Add the beta header `prompt-tools-2025-04-02`

<Tip>
  This API is not available in the SDK
</Tip>

## Templatize a prompt