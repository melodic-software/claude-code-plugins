# Routing: model and effort

This skill holds no model names and no effort defaults. A run passes a model only when the user
names one or `codex.model` is set, and an effort only when `codex.effort` is set; otherwise Codex's
own configuration and recommended default decide. Which model and effort each agent role in a
multi-agent run uses is `/multi-agent:route`'s config, not this skill's.

When the user asks which Codex model or effort to use, or `update` prints `routing: due`, read the
pages below live and answer from them, citing the section:

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
