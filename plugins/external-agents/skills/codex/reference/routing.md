# Routing: model and effort

This skill holds no model names and no effort defaults; without an override Codex's own
configuration and recommended default decide. Which vendor, model and effort fit a task is
`/multi-agent:route vendors <task>`'s choice, made on criteria and benchmarks shared across
vendors. This file lists only Codex's own facts and docs.

When the user asks which Codex model or effort to use, or `update` prints `routing: due`, read the
pages below live and answer from them, citing the section:

- The models and effort levels this Codex version offers: `external-agents models codex` (JSON).
- Index of the Codex docs, to find a page that moved:
  [llms.txt](https://learn.chatgpt.com/docs/llms.txt).
- Which models are current and recommended:
  [Models § Recommended models](https://learn.chatgpt.com/docs/models#recommended-models).
- Matching a model to the work:
  [Models § Choosing a model](https://learn.chatgpt.com/docs/models#choosing-a-model) and
  [Model selection § Find the right model for your workflow](https://learn.chatgpt.com/docs/model-selection#find-the-right-model-for-your-workflow).
- Effort:
  [Models § Pick a reasoning effort](https://learn.chatgpt.com/docs/models#pick-a-reasoning-effort)
  and
  [Model selection § How to think about models and reasoning effort](https://learn.chatgpt.com/docs/model-selection#how-to-think-about-models-and-reasoning-effort).
- Codex's own default, which applies when nothing is configured:
  [Models § Configure your default local model](https://learn.chatgpt.com/docs/models#configure-your-default-local-model).

A recommendation goes to the user as a config change for them to make (`codex.model`,
`codex.effort`), with the section it rests on. On `routing: due`, the check is the one in
[update.md § Routing refresh](update.md#routing-refresh).
