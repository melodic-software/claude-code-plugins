---
bump: patch
---

### Fixed

- **The `default-judge-same-model` eval case no longer Greps the plugin root.** Leaving Grep and Glob out of `allowed_tools` did not stop the model calling them, and the sandbox denied the search in every with-arm run, which made the case's runs invalid. The case now carries an `append_system_prompt` that limits the session to Read and Skill and says not to search the filesystem.
