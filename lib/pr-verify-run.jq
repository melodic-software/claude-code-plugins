.status == "completed" and .conclusion == "success"
  and .path == ".github/workflows/pr-verify.yml" and .event == "workflow_run" and .head_branch == $def
  and .repository.full_name == $repo and .head_repository.full_name == $repo
