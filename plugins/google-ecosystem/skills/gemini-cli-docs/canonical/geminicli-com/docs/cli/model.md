---
source_url: http://geminicli.com/docs/cli/model
source_type: llms-txt
content_hash: sha256:4503679dec0599d258687c93a094fe389d79c0a1f8832c9ad219da6acf37d4dc
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"b6bc5233b1d756157439be04daf101b889d190c7af2534fe018113327ab49cfe"'
last_modified: '2025-12-01T20:04:32Z'
---

# Gemini CLI model selection (`/model` command)

Select your Gemini CLI model. The `/model` command opens a dialog where you can
configure the model used by Gemini CLI, giving you more control over your
results.

## How to use the `/model` command

Use the following command in Gemini CLI:

```
/model
```

Running this command will open a dialog with your model options:

| Option             | Description                                                   | Models                                                                                     |
| ------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Auto (recommended) | Let the system choose the best model for your task.           | gemini-3-pro-preview (if enabled), gemini-2.5-pro, gemini-2.5-flash, gemini-2.5-flash-lite |
| Pro                | For complex tasks that require deep reasoning and creativity. | gemini-3-pro-preview (if enabled), gemini-2.5-pro                                          |
| Flash              | For tasks that need a balance of speed and reasoning.         | gemini-2.5-flash                                                                           |
| Flash-Lite         | For simple tasks that need to be done quickly.                | gemini-2.5-flash-lite                                                                      |

### Gemini 3 Pro and preview features

Note: Gemini 3 is not currently available on all account types. To learn more
about Gemini 3 access, refer to
[Gemini 3 Pro on Gemini CLI](/docs/get-started/gemini-3).

To enable Gemini 3 Pro (if available), enable
[**Preview features** by using the `settings` command](/docs/cli/settings). Once
enabled, Gemini CLI will attempt to use Gemini 3 Pro when you select **Auto** or
**Pro**. Both **Auto** and **Pro** will try to use Gemini 3 Pro before falling
back to Gemini 2.5 Pro.

You can also use the `--model` flag to specify a particular Gemini model on
startup. For more details, refer to the
[configuration documentation](/docs/cli/configuration).

Changes to these settings will be applied to all subsequent interactions with
Gemini CLI.

## Best practices for model selection

- **Default to Auto (recommended).** For most users, the _Auto (recommended)_
  model provides a balance between speed and performance, automatically
  selecting the correct model based on the complexity of the task. Example:
  Developing a web application could include a mix of complex tasks (building
  architecture and scaffolding the project) and simple tasks (generating CSS).

- **Switch to Pro if you aren't getting the results you want.** If you think you
  need your model to be a little "smarter," use Pro. Pro will provide you with
  the highest levels of reasoning and creativity. Example: A complex or
  multi-stage debugging task.

- **Switch to Flash or Flash-Lite if you need faster results.** If you need a
  simple response quickly, Flash or Flash-Lite is the best option. Example:
  Converting a JSON object to a YAML string.
