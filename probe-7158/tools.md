# PR activity tool probe

Both `mcp__claude-code-remote__subscribe_pr_activity` and
`mcp__claude-code-remote__unsubscribe_pr_activity` are present in the session's tool list as
directly callable tools; no ToolSearch load was needed. Neither was invoked.

## subscribe_pr_activity

```json
{
  "properties": {
    "owner": {
      "description": "The repository owner (user or organization name).",
      "type": "string"
    },
    "pullNumber": {
      "description": "The pull request number.",
      "type": "integer"
    },
    "repo": {
      "description": "The repository name.",
      "type": "string"
    }
  },
  "required": ["owner", "repo", "pullNumber"],
  "type": "object"
}
```

## unsubscribe_pr_activity

```json
{
  "properties": {
    "owner": {
      "description": "The repository owner (user or organization name).",
      "type": "string"
    },
    "pullNumber": {
      "description": "The pull request number.",
      "type": "integer"
    },
    "repo": {
      "description": "The repository name.",
      "type": "string"
    }
  },
  "required": ["owner", "repo", "pullNumber"],
  "type": "object"
}
```

## Other mcp__claude-code-remote__ tools present

- add_repo
- archive_session
- confirm_repository_trust
- create_session
- create_trigger
- delete_trigger
- fire_trigger
- get_event
- get_session
- get_trigger
- interrupt_session
- list_environments
- list_events
- list_repos
- list_sessions
- list_triggers
- read_documentation
- register_repo_root
- send_later
- send_message
- set_session_tags
- set_session_title
- unarchive_session
- unwatch_url
- update_trigger
- watch_url
