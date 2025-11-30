<!-- Source: https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/prompt-templates-and-variables -->

# Use prompt templates and variables

When deploying an LLM-based application with Claude, your API calls will typically consist of two types of content:

* **Fixed content:** Static instructions or context that remain constant across multiple interactions
* **Variable content:** Dynamic elements that change with each request or conversation, such as:
  * User inputs
  * Retrieved content for Retrieval-Augmented Generation (RAG)
  * Conversation context such as user account history
  * System-generated data such as tool use results fed in from other independent calls to Claude

A **prompt template** combines these fixed and variable parts, using placeholders for the dynamic content. In the [Claude Console](https://console.anthropic.com/), these placeholders are denoted with **\{\{double brackets}}**, making them easily identifiable and allowing for quick testing of different values.

***